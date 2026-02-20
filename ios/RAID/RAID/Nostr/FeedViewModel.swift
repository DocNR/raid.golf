// RAID Golf — Feed View Model
// Owns feed state, fetch logic, event processing, and dedup.

import Foundation
import NostrSDK
import GRDB

@Observable
class FeedViewModel {

    // MARK: - Public State

    var items: [FeedItem] = []
    var isLoading = false
    var errorMessage: String?
    var resolvedProfiles: [String: NostrProfile] = [:]

    // Reactions (NIP-25) & Comments (NIP-22)
    var reactionCounts: [String: Int] = [:]
    var ownReactions: Set<String> = []
    var commentCounts: [String: Int] = [:]
    var rawEvents: [String: Event] = [:]

    /// True while a background relay sync (Phase B) is running on top of cached content.
    var isBackgroundRefreshing = false

    enum LoadState {
        case idle
        case guest
        case noKey
        case noFollows
        case loaded
    }
    var loadState: LoadState = .idle

    private var hasLoaded = false

    // MARK: - Load

    func loadIfNeeded(nostrService: NostrService, dbQueue: DatabaseQueue) async {
        guard !hasLoaded else { return }
        hasLoaded = true
        // Phase A: instant paint from GRDB cache (< 200ms target)
        await paintFromCache(nostrService: nostrService, dbQueue: dbQueue)
        // Phase B: full relay sync; shows bg indicator if Phase A painted
        await refresh(nostrService: nostrService, dbQueue: dbQueue)
    }

    func refresh(nostrService: NostrService, dbQueue: DatabaseQueue) async {
        guard nostrService.isActivated else {
            loadState = .guest
            isLoading = false
            return
        }

        // Show full loading spinner only if nothing is painted yet.
        // If Phase A painted items, show the subtle background indicator instead.
        if items.isEmpty {
            isLoading = true
        } else {
            isBackgroundRefreshing = true
        }
        errorMessage = nil

        do {
            let t0 = CFAbsoluteTimeGetCurrent()

            // 1. Get user's pubkey
            guard KeyManager.hasExistingKey() else {
                loadState = .noKey
                isLoading = false
                return
            }
            let keyManager = try KeyManager.loadOrCreate()
            let pubkey = keyManager.signingKeys().publicKey()

            // 2. Follow list — GRDB cache (1h TTL) → relay fallback
            let followListRepo = FollowListCacheRepository(dbQueue: dbQueue)
            let followCacheTTL: TimeInterval = 60 * 60  // 1 hour
            let pubkeyHex = pubkey.toHex()
            var follows: [String]

            if let cached = try? followListRepo.fetch(pubkeyHex: pubkeyHex),
               Date().timeIntervalSince(cached.cachedAt) < followCacheTTL {
                follows = cached.follows
            } else {
                let (fetched, _) = try await nostrService.fetchFollowListWithProfiles(pubkey: pubkey)
                follows = fetched
                if !follows.isEmpty {
                    try? followListRepo.upsert(CachedFollowList(
                        pubkeyHex: pubkeyHex, follows: follows, eventCreatedAt: 0, cachedAt: Date()
                    ))
                }
            }
            let t1 = CFAbsoluteTimeGetCurrent()
            print("[RAID][Feed] Step 2 follow list: \(String(format: "%.1f", t1 - t0))s (\(follows.count) follows)")

            guard !follows.isEmpty else {
                loadState = .noFollows
                isLoading = false
                return
            }

            // 3. Resolve relay lists for all follows (3-layer cache, 24h TTL)
            let cacheRepo = RelayCacheRepository(dbQueue: dbQueue)
            let relayMap = try await nostrService.resolveRelayLists(
                pubkeyHexes: follows, cacheRepo: cacheRepo
            )
            let t2 = CFAbsoluteTimeGetCurrent()
            print("[RAID][Feed] Step 3 relay lists: \(String(format: "%.1f", t2 - t1))s")

            // Build authorRelayMap: [authorHex: [writeRelayURLs]]
            var authorRelayMap: [String: [String]] = [:]
            for hex in follows {
                if let entries = relayMap[hex] {
                    let writeURLs = entries.filter(\.isWrite).map(\.url)
                    if !writeURLs.isEmpty {
                        authorRelayMap[hex] = writeURLs
                        continue
                    }
                }
                // No relay list or no write relays → use content relays (not defaultReadRelays
                // which includes metadata-only relays like purplepag.es)
                authorRelayMap[hex] = NostrService.defaultPublishRelays
            }

            // 4. Fetch feed events via outbox routing
            let events = try await nostrService.fetchFeedEventsOutbox(authorRelayMap: authorRelayMap, keys: keyManager.signingKeys())
            let t3 = CFAbsoluteTimeGetCurrent()
            print("[RAID][Feed] Step 4 outbox fan-out: \(String(format: "%.1f", t3 - t2))s (\(events.count) events)")

            // 5. Process into FeedItems (batch relay fetches)
            let processed = await processEvents(events, nostrService: nostrService, dbQueue: dbQueue)
            let t4 = CFAbsoluteTimeGetCurrent()
            print("[RAID][Feed] Step 5 process events: \(String(format: "%.1f", t4 - t3))s")

            // Merge: keep previously-seen items that aren't in this fetch,
            // so a flaky relay response doesn't nuke posts.
            // Only retain items from authors still in the follow list (respects unfollows).
            let followSet = Set(follows)
            let newIds = Set(processed.map(\.id))
            let retained = items.filter { !newIds.contains($0.id) && followSet.contains($0.pubkeyHex) }
            items = (processed + retained).sorted { $0.createdAt > $1.createdAt }
            if items.count > 150 { items = Array(items.prefix(150)) }
            loadState = .loaded

            // Cache all fetched events to GRDB (kind 1, 1501, 1502 + referenced events)
            let feedEventRepo = FeedEventCacheRepository(dbQueue: dbQueue)
            let allEvents = Array(rawEvents.values)
            if !allEvents.isEmpty {
                try? feedEventRepo.upsertEvents(allEvents)
                try? feedEventRepo.pruneOldEvents(keepCount: 200)
            }

            // 6-8. Enrichment — profiles, reactions, and comments run concurrently
            let pubkeyHexes = Array(Set(items.map(\.pubkeyHex)))
            let profileRepo = ProfileCacheRepository(dbQueue: dbQueue)
            let uncached = pubkeyHexes.filter { nostrService.profileCache[$0] == nil }
            let ownHex = keyManager.signingKeys().publicKey().toHex()
            let feedIds = items.map(\.id)
            let textNoteIds = items.compactMap { item -> String? in
                if case .textNote = item { return item.id } else { return nil }
            }
            let scorecardIds = items.compactMap { item -> String? in
                if case .scorecard = item { return item.id } else { return nil }
            }

            let profilesHandle = Task {
                if !uncached.isEmpty {
                    _ = try? await nostrService.resolveProfiles(pubkeyHexes: uncached, cacheRepo: profileRepo)
                }
            }

            let reactionsHandle = Task { () -> (counts: [String: Int], ownReacted: Set<String>)? in
                return try? await nostrService.fetchReactions(eventIds: feedIds, ownPubkeyHex: ownHex)
            }

            let commentsHandle = Task { () -> [String: Int] in
                var counts: [String: Int] = [:]
                if !textNoteIds.isEmpty,
                   let replyCounts = try? await nostrService.fetchReplyCounts(eventIds: textNoteIds) {
                    counts.merge(replyCounts) { $1 }
                }
                if !scorecardIds.isEmpty,
                   let commentCountsResult = try? await nostrService.fetchCommentCounts(eventIds: scorecardIds) {
                    counts.merge(commentCountsResult) { $1 }
                }
                return counts
            }

            await profilesHandle.value
            resolvedProfiles = pubkeyHexes.reduce(into: [:]) { dict, hex in
                dict[hex] = nostrService.profileCache[hex]
            }

            if let result = await reactionsHandle.value {
                reactionCounts = result.counts
                ownReactions = result.ownReacted
            }

            commentCounts = await commentsHandle.value

            // Cache social counts to GRDB for Phase A instant paint
            let socialRepo = SocialCountCacheRepository(dbQueue: dbQueue)
            try? socialRepo.upsertReactionCounts(reactionCounts, ownReacted: ownReactions)
            try? socialRepo.upsertCommentCounts(commentCounts)

            let t5 = CFAbsoluteTimeGetCurrent()
            print("[RAID][Feed] Step 6-8 enrichment (parallel): \(String(format: "%.1f", t5 - t4))s")
            print("[RAID][Feed] Total: \(String(format: "%.1f", t5 - t0))s")
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
        isBackgroundRefreshing = false
    }

    // MARK: - Cache Paint (Phase A)

    /// Load cached feed events from GRDB and reconstruct FeedItems instantly (< 200ms).
    /// Called before the relay fetch so the user sees content immediately on launch.
    private func paintFromCache(nostrService: NostrService, dbQueue: DatabaseQueue) async {
        let tA0 = CFAbsoluteTimeGetCurrent()
        guard nostrService.isActivated, KeyManager.hasExistingKey() else { return }
        let feedEventRepo = FeedEventCacheRepository(dbQueue: dbQueue)
        guard let cachedEvents = try? feedEventRepo.fetchRecentEvents(limit: 50),
              !cachedEvents.isEmpty else { return }
        let tA1 = CFAbsoluteTimeGetCurrent()

        let reconstructed = reconstructFeedItems(from: cachedEvents)
        guard !reconstructed.isEmpty else { return }
        let tA2 = CFAbsoluteTimeGetCurrent()

        // Filter to known follows if the follow list is cached; otherwise show all.
        let keyManager = try? KeyManager.loadOrCreate()
        let pubkeyHex = keyManager?.signingKeys().publicKey().toHex() ?? ""
        let followListRepo = FollowListCacheRepository(dbQueue: dbQueue)
        let followSet: Set<String>
        if let cached = try? followListRepo.fetch(pubkeyHex: pubkeyHex) {
            followSet = Set(cached.follows)
        } else {
            followSet = []
        }

        // Populate rawEvents so reactions work immediately on cached content.
        for event in cachedEvents {
            rawEvents[event.id().toHex()] = event
        }

        let filtered = followSet.isEmpty
            ? reconstructed
            : reconstructed.filter { followSet.contains($0.pubkeyHex) }
        guard !filtered.isEmpty else { return }

        items = Array(filtered.prefix(150))
        loadState = .loaded

        // Load profiles from GRDB so names and PFPs appear immediately on cold launch.
        // Also warm the in-memory profileCache so Phase B's resolveProfiles skips re-reads.
        let pubkeyHexes = Array(Set(items.map(\.pubkeyHex)))
        let profileRepo = ProfileCacheRepository(dbQueue: dbQueue)
        let dbProfiles = (try? profileRepo.fetchProfiles(pubkeyHexes: pubkeyHexes)) ?? [:]
        resolvedProfiles = dbProfiles
        nostrService.warmProfileCache(dbProfiles)

        // Load cached reaction + comment counts from GRDB
        let itemIds = items.map(\.id)
        let socialRepo = SocialCountCacheRepository(dbQueue: dbQueue)
        if let cached = try? socialRepo.fetchReactionCounts(eventIds: itemIds) {
            reactionCounts = cached.counts
            ownReactions = cached.ownReacted
        }
        if let cached = try? socialRepo.fetchCommentCounts(eventIds: itemIds) {
            commentCounts = cached
        }
        let tA3 = CFAbsoluteTimeGetCurrent()

        print("[RAID][Feed] Phase A: fetch=\(String(format: "%.3f", tA1 - tA0))s reconstruct=\(String(format: "%.3f", tA2 - tA1))s profiles+counts=\(String(format: "%.3f", tA3 - tA2))s total=\(String(format: "%.3f", tA3 - tA0))s (\(cachedEvents.count) events → \(items.count) items)")
    }

    /// Reconstruct FeedItems from cached events with no relay calls.
    /// Mirrors processEvents but uses the provided event collection for all lookups.
    private func reconstructFeedItems(from cachedEvents: [Event]) -> [FeedItem] {
        var byId: [String: Event] = [:]
        var kind1Events: [Event] = []
        var kind1502Events: [Event] = []
        var kind1501InfoById: [String: CourseSnapshotContent] = [:]

        for event in cachedEvents {
            let id = event.id().toHex()
            byId[id] = event
            let kind = event.kind().asU16()
            if kind == 1 {
                kind1Events.append(event)
            } else if kind == NIP101gKind.finalRoundRecord {
                kind1502Events.append(event)
            } else if kind == NIP101gKind.roundInitiation {
                if let content = try? NIP101gEventParser.parseInitiationContent(json: event.content()) {
                    kind1501InfoById[id] = content.courseSnapshot
                }
            }
        }

        var quotedScorecardIds: Set<String> = []
        for event in kind1Events {
            let tags = event.tags().toVec().map { $0.asVec() }
            if let eTag = tags.first(where: { $0.count >= 2 && $0[0] == "e" }) {
                quotedScorecardIds.insert(eTag[1])
            }
        }

        var feedItems: [FeedItem] = []

        for event in kind1Events {
            let id = event.id().toHex()
            let pubkey = event.author().toHex()
            let createdAt = Date(timeIntervalSince1970: TimeInterval(event.createdAt().asSecs()))
            let content = event.content()
            let tags = event.tags().toVec().map { $0.asVec() }

            if let eTagValue = tags.first(where: { $0.count >= 2 && $0[0] == "e" })?[1],
               let refEvent = byId[eTagValue],
               refEvent.kind().asU16() == NIP101gKind.finalRoundRecord {
                let refTags = refEvent.tags().toVec().map { $0.asVec() }
                let refPubkey = refEvent.author().toHex()
                if let record = NIP101gEventParser.parseFinalRecord(
                    tagArrays: refTags, authorPubkeyHex: refPubkey, content: refEvent.content()
                ) {
                    let courseInfo = record.initiationEventId.flatMap { kind1501InfoById[$0] }
                    feedItems.append(.scorecard(
                        id: id, pubkeyHex: pubkey, commentary: content,
                        record: record, courseInfo: courseInfo, createdAt: createdAt
                    ))
                    continue
                }
            }
            feedItems.append(.textNote(id: id, pubkeyHex: pubkey, content: content, createdAt: createdAt))
        }

        for event in kind1502Events {
            let id = event.id().toHex()
            guard !quotedScorecardIds.contains(id) else { continue }
            let pubkey = event.author().toHex()
            let createdAt = Date(timeIntervalSince1970: TimeInterval(event.createdAt().asSecs()))
            let tags = event.tags().toVec().map { $0.asVec() }
            guard let record = NIP101gEventParser.parseFinalRecord(
                tagArrays: tags, authorPubkeyHex: pubkey, content: event.content()
            ) else { continue }
            let courseInfo = record.initiationEventId.flatMap { kind1501InfoById[$0] }
            feedItems.append(.scorecard(
                id: id, pubkeyHex: pubkey, commentary: nil,
                record: record, courseInfo: courseInfo, createdAt: createdAt
            ))
        }

        return feedItems.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Reactions

    func react(itemId: String, nostrService: NostrService) {
        guard !ownReactions.contains(itemId),
              let event = rawEvents[itemId] else { return }

        // Optimistic update
        ownReactions.insert(itemId)
        reactionCounts[itemId, default: 0] += 1

        Task {
            do {
                let keys = try KeyManager.loadOrCreate().signingKeys()
                try await nostrService.publishReaction(keys: keys, event: event)
            } catch {
                // Revert optimistic update on failure
                ownReactions.remove(itemId)
                reactionCounts[itemId, default: 1] -= 1
            }
        }
    }

    // MARK: - Event Processing

    private func processEvents(_ events: [Event], nostrService: NostrService, dbQueue: DatabaseQueue) async -> [FeedItem] {
        var kind1Events: [Event] = []
        var kind1502Events: [Event] = []
        var quotedScorecardIds: Set<String> = []

        // Store raw events for reaction publishing (needs full Event object)
        for event in events {
            rawEvents[event.id().toHex()] = event
        }

        // Pass 1: categorize events, collect all e-tag IDs from kind-1 events
        for event in events {
            let kind = event.kind().asU16()
            if kind == 1 {
                kind1Events.append(event)
                let tags = event.tags().toVec().map { $0.asVec() }
                if let eTag = tags.first(where: { $0.count >= 2 && $0[0] == "e" }) {
                    quotedScorecardIds.insert(eTag[1])
                }
            } else if kind == NIP101gKind.finalRoundRecord {
                kind1502Events.append(event)
            }
        }

        // Pass 2: resolve referenced 1502 events — GRDB cache first, relay for misses
        var fetchedEventsById: [String: Event] = [:]
        let allRefIds = Array(quotedScorecardIds)
        if !allRefIds.isEmpty {
            let feedEventRepo = FeedEventCacheRepository(dbQueue: dbQueue)
            var missIds: [String] = []
            for id in allRefIds {
                if let cached = try? feedEventRepo.fetchEvent(idHex: id) {
                    fetchedEventsById[id] = cached
                    rawEvents[id] = cached
                } else {
                    missIds.append(id)
                }
            }
            if !missIds.isEmpty {
                let fetched = (try? await nostrService.fetchEventsByIds(missIds)) ?? []
                for event in fetched {
                    let id = event.id().toHex()
                    fetchedEventsById[id] = event
                    rawEvents[id] = event
                }
            }
        }

        // Pass 3: collect all initiation event IDs from 1502s (both quoted and direct)
        var initiationIds: Set<String> = []

        for refId in quotedScorecardIds {
            if let refEvent = fetchedEventsById[refId],
               refEvent.kind().asU16() == NIP101gKind.finalRoundRecord {
                let refTags = refEvent.tags().toVec().map { $0.asVec() }
                if let record = NIP101gEventParser.parseFinalRecord(
                    tagArrays: refTags,
                    authorPubkeyHex: refEvent.author().toHex(),
                    content: refEvent.content()
                ), let initId = record.initiationEventId {
                    initiationIds.insert(initId)
                }
            }
        }

        for event in kind1502Events {
            let id = event.id().toHex()
            guard !quotedScorecardIds.contains(id) else { continue }
            let tags = event.tags().toVec().map { $0.asVec() }
            if let record = NIP101gEventParser.parseFinalRecord(
                tagArrays: tags,
                authorPubkeyHex: event.author().toHex(),
                content: event.content()
            ), let initId = record.initiationEventId {
                initiationIds.insert(initId)
            }
        }

        // Pass 4: resolve 1501 initiation events — GRDB cache first, relay for misses
        var courseInfoById: [String: CourseSnapshotContent] = [:]
        if !initiationIds.isEmpty {
            let feedEventRepo = FeedEventCacheRepository(dbQueue: dbQueue)
            var missIds: [String] = []
            for id in initiationIds {
                if let cached = try? feedEventRepo.fetchEvent(idHex: id) {
                    rawEvents[id] = cached
                    if let content = try? NIP101gEventParser.parseInitiationContent(json: cached.content()) {
                        courseInfoById[id] = content.courseSnapshot
                    }
                } else {
                    missIds.append(id)
                }
            }
            if !missIds.isEmpty {
                let fetched1501s = (try? await nostrService.fetchEventsByIds(missIds)) ?? []
                for event in fetched1501s {
                    let id = event.id().toHex()
                    rawEvents[id] = event
                    if let content = try? NIP101gEventParser.parseInitiationContent(json: event.content()) {
                        courseInfoById[id] = content.courseSnapshot
                    }
                }
            }
        }

        // Pass 5: assemble FeedItems
        var feedItems: [FeedItem] = []

        // Process kind-1 events
        for event in kind1Events {
            let id = event.id().toHex()
            let pubkey = event.author().toHex()
            let createdAt = Date(timeIntervalSince1970: TimeInterval(event.createdAt().asSecs()))
            let content = event.content()
            let tags = event.tags().toVec().map { $0.asVec() }

            if let eTagValue = tags.first(where: { $0.count >= 2 && $0[0] == "e" })?[1],
               let refEvent = fetchedEventsById[eTagValue],
               refEvent.kind().asU16() == NIP101gKind.finalRoundRecord {
                let refTags = refEvent.tags().toVec().map { $0.asVec() }
                let refPubkey = refEvent.author().toHex()
                if let record = NIP101gEventParser.parseFinalRecord(
                    tagArrays: refTags,
                    authorPubkeyHex: refPubkey,
                    content: refEvent.content()
                ) {
                    let courseInfo = record.initiationEventId.flatMap { courseInfoById[$0] }
                    feedItems.append(.scorecard(
                        id: id, pubkeyHex: pubkey, commentary: content,
                        record: record, courseInfo: courseInfo, createdAt: createdAt
                    ))
                    continue
                }
            }

            // Plain text note
            feedItems.append(.textNote(id: id, pubkeyHex: pubkey, content: content, createdAt: createdAt))
        }

        // Process direct kind-1502 events (skip those already quoted)
        for event in kind1502Events {
            let id = event.id().toHex()
            guard !quotedScorecardIds.contains(id) else { continue }

            let pubkey = event.author().toHex()
            let createdAt = Date(timeIntervalSince1970: TimeInterval(event.createdAt().asSecs()))
            let tags = event.tags().toVec().map { $0.asVec() }

            guard let record = NIP101gEventParser.parseFinalRecord(
                tagArrays: tags, authorPubkeyHex: pubkey, content: event.content()
            ) else { continue }

            let courseInfo = record.initiationEventId.flatMap { courseInfoById[$0] }
            feedItems.append(.scorecard(
                id: id, pubkeyHex: pubkey, commentary: nil,
                record: record, courseInfo: courseInfo, createdAt: createdAt
            ))
        }

        return feedItems.sorted { $0.createdAt > $1.createdAt }
    }
}

// MARK: - FeedItem

enum FeedItem: Identifiable {
    case textNote(id: String, pubkeyHex: String, content: String, createdAt: Date)
    case scorecard(id: String, pubkeyHex: String, commentary: String?,
                   record: FinalRecordData, courseInfo: CourseSnapshotContent?, createdAt: Date)

    var id: String {
        switch self {
        case .textNote(let id, _, _, _): return id
        case .scorecard(let id, _, _, _, _, _): return id
        }
    }

    var createdAt: Date {
        switch self {
        case .textNote(_, _, _, let date): return date
        case .scorecard(_, _, _, _, _, let date): return date
        }
    }

    var pubkeyHex: String {
        switch self {
        case .textNote(_, let pk, _, _): return pk
        case .scorecard(_, let pk, _, _, _, _): return pk
        }
    }
}
