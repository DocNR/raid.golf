// RAID Golf — Feed View Model
// Owns feed state, fetch logic, event processing, and dedup.

import Foundation
import NostrSDK

@Observable
class FeedViewModel {

    // MARK: - Public State

    var items: [FeedItem] = []
    var isLoading = false
    var errorMessage: String?
    var resolvedProfiles: [String: NostrProfile] = [:]

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

    func loadIfNeeded(nostrService: NostrService) async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await refresh(nostrService: nostrService)
    }

    func refresh(nostrService: NostrService) async {
        guard nostrService.isActivated else {
            loadState = .guest
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            // 1. Get user's pubkey
            guard KeyManager.hasExistingKey() else {
                loadState = .noKey
                isLoading = false
                return
            }
            let keyManager = try KeyManager.loadOrCreate()
            let pubkey = keyManager.signingKeys().publicKey()

            // 2. Fetch follow list + profiles in one connection
            let (follows, _) = try await nostrService.fetchFollowListWithProfiles(pubkey: pubkey)

            guard !follows.isEmpty else {
                loadState = .noFollows
                isLoading = false
                return
            }

            // 3. Fetch feed events
            let events = try await nostrService.fetchFeedEvents(followedPubkeys: follows)

            // 4. Process into FeedItems (batch relay fetches)
            let processed = await processEvents(events, nostrService: nostrService)
            items = processed
            loadState = .loaded

            // 5. Resolve profiles for all authors; snapshot into resolvedProfiles for stable UI reads
            let pubkeyHexes = Array(Set(processed.map(\.pubkeyHex)))
            let uncached = pubkeyHexes.filter { nostrService.profileCache[$0] == nil }
            if !uncached.isEmpty {
                _ = try? await nostrService.resolveProfiles(pubkeyHexes: uncached)
            }
            resolvedProfiles = pubkeyHexes.reduce(into: [:]) { dict, hex in
                dict[hex] = nostrService.profileCache[hex]
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Event Processing

    private func processEvents(_ events: [Event], nostrService: NostrService) async -> [FeedItem] {
        var kind1Events: [Event] = []
        var kind1502Events: [Event] = []
        var quotedScorecardIds: Set<String> = []

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

        // Pass 2: batch fetch all referenced 1502 events (single relay connection)
        var fetchedEventsById: [String: Event] = [:]
        let allRefIds = Array(quotedScorecardIds)
        if !allRefIds.isEmpty {
            let fetched = (try? await nostrService.fetchEventsByIds(allRefIds)) ?? []
            for event in fetched {
                fetchedEventsById[event.id().toHex()] = event
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

        // Pass 4: batch fetch all 1501 initiation events (single relay connection)
        var courseInfoById: [String: CourseSnapshotContent] = [:]
        if !initiationIds.isEmpty {
            let fetched1501s = (try? await nostrService.fetchEventsByIds(Array(initiationIds))) ?? []
            for event in fetched1501s {
                let id = event.id().toHex()
                if let content = try? NIP101gEventParser.parseInitiationContent(json: event.content()) {
                    courseInfoById[id] = content.courseSnapshot
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
