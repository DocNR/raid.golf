// RAID Golf — Nostr Service
// Observable service for dependency injection.
// Fire-and-forget publisher + one-shot reader. No persistent connections.

import Foundation
import SwiftUI
import NostrSDK

@Observable
class NostrService {

    // MARK: - Relay Configuration

    static let defaultPublishRelays = [
        "wss://relay.damus.io",
        "wss://nos.lol",
        "wss://relay.nostr.band"
    ]

    static let defaultReadRelays = [
        "wss://relay.damus.io",
        "wss://nos.lol",
        "wss://purplepag.es"
    ]

    private let readTimeout: TimeInterval = 5

    /// Session-scoped profile cache. Populated by resolveProfiles, fetchProfiles,
    /// and fetchFollowListWithProfiles. Cleared on app restart.
    private(set) var profileCache: [String: NostrProfile] = [:]

    /// Session-scoped relay list cache. Populated by resolveRelayLists, fetchRelayLists.
    /// Cleared on app restart.
    private(set) var relayListCache: [String: [CachedRelayEntry]] = [:]

    /// Update the in-memory relay list cache for a given pubkey.
    /// Call after local edits to prevent stale cache from overriding user changes.
    func updateRelayListCache(pubkeyHex: String, relays: [CachedRelayEntry]) {
        relayListCache[pubkeyHex] = relays
    }

    // MARK: - Activation Gate

    /// Whether Nostr features are active. Guest users have this set to false.
    var isActivated: Bool {
        UserDefaults.standard.bool(forKey: "nostrActivated")
    }

    // MARK: - Publish

    /// Publish a pre-built EventBuilder and return its event ID.
    /// Used for NIP-101g events where we need the ID for cross-referencing.
    func publishEvent(keys: Keys, builder: EventBuilder) async throws -> String {
        guard isActivated else {
            print("[RAID][Guest] publishEvent blocked — Nostr not activated")
            return ""
        }
        let signer = NostrSigner.keys(keys: keys)
        let client = Client(signer: signer)

        for urlString in Self.defaultPublishRelays {
            let url = try RelayUrl.parse(url: urlString)
            _ = try await client.addRelay(url: url)
        }

        await client.connect()

        let output = try await client.sendEventBuilder(builder: builder)

        if output.success.isEmpty {
            await client.disconnect()
            throw NostrPublishError.allRelaysFailed
        }

        let eventId = output.id.toHex()
        await client.disconnect()
        return eventId
    }

    // MARK: - Read Operations

    /// Fetch the follow list (kind 3 / NIP-02) for a given public key.
    /// Returns an array of followed public key hex strings.
    func fetchFollowList(pubkey: PublicKey) async throws -> [String] {
        guard isActivated else {
            print("[RAID][Guest] fetchFollowList blocked — Nostr not activated")
            return []
        }
        let client = try await connectReadClient()

        let filter = Filter()
            .author(author: pubkey)
            .kind(kind: Kind(kind: 3))
            .limit(limit: 1)

        let events: Events
        do {
            events = try await client.fetchEvents(filter: filter, timeout: readTimeout)
        } catch {
            await client.disconnect()
            throw NostrReadError.networkFailure(error)
        }

        await client.disconnect()

        // Kind 3 is replaceable — different relays may return different versions.
        // Pick newest created_at (authoritative per protocol).
        let allContactEvents = verifiedEvents(try events.toVec())
        guard let contactEvent = allContactEvents
            .sorted(by: { $0.createdAt().asSecs() > $1.createdAt().asSecs() })
            .first else {
            return []
        }

        // Extract pubkeys from p tags
        let pubkeys = contactEvent.tags().publicKeys()
        return pubkeys.map { $0.toHex() }
    }

    /// Fetch profile metadata (kind 0 / NIP-01) for a list of public keys.
    /// Returns a dictionary mapping pubkey hex → NostrProfile.
    func fetchProfiles(pubkeyHexes: [String]) async throws -> [String: NostrProfile] {
        guard isActivated else {
            print("[RAID][Guest] fetchProfiles blocked — Nostr not activated")
            return [:]
        }
        guard !pubkeyHexes.isEmpty else { return [:] }

        let pubkeys = try pubkeyHexes.compactMap { hex -> PublicKey? in
            try PublicKey.parse(publicKey: hex)
        }

        guard !pubkeys.isEmpty else { return [:] }

        let client = try await connectReadClient()

        let events = try await fetchProfileEvents(client: client, pubkeys: pubkeys)

        await client.disconnect()

        let result = parseProfileEvents(verifiedEvents(events))
        for (key, profile) in result { profileCache[key] = profile }
        return result
    }

    /// Fetch follow list and profiles in a single connection session.
    /// Avoids the overhead of connecting/disconnecting twice.
    func fetchFollowListWithProfiles(pubkey: PublicKey) async throws -> (follows: [String], profiles: [String: NostrProfile]) {
        guard isActivated else {
            print("[RAID][Guest] fetchFollowListWithProfiles blocked — Nostr not activated")
            return (follows: [], profiles: [:])
        }
        let client = try await connectReadClient()

        // 1. Fetch kind 3 (follow list)
        let followFilter = Filter()
            .author(author: pubkey)
            .kind(kind: Kind(kind: 3))
            .limit(limit: 1)

        let followEvents: Events
        do {
            followEvents = try await client.fetchEvents(filter: followFilter, timeout: readTimeout)
        } catch {
            await client.disconnect()
            throw NostrReadError.networkFailure(error)
        }

        // Kind 3 is replaceable — different relays may have different versions.
        // Pick the one with the newest created_at (authoritative per protocol).
        let allContactEvents = verifiedEvents(try followEvents.toVec())
        guard let contactEvent = allContactEvents
            .sorted(by: { $0.createdAt().asSecs() > $1.createdAt().asSecs() })
            .first else {
            await client.disconnect()
            return (follows: [], profiles: [:])
        }

        let followedPubkeys = contactEvent.tags().publicKeys()
        let followedHexes = followedPubkeys.map { $0.toHex() }

        guard !followedPubkeys.isEmpty else {
            await client.disconnect()
            return (follows: followedHexes, profiles: [:])
        }

        // 2. Fetch kind 0 (profiles) for all followed pubkeys — reuse same connection
        let profileEvents = try await fetchProfileEvents(client: client, pubkeys: followedPubkeys)

        await client.disconnect()

        let profiles = parseProfileEvents(verifiedEvents(profileEvents))
        for (key, profile) in profiles { profileCache[key] = profile }
        return (follows: followedHexes, profiles: profiles)
    }

    // MARK: - Profile Resolution (Cache-First)

    /// Resolve profiles from cache (in-memory then GRDB) or fetch uncached keys from relays.
    /// Three-layer lookup: in-memory → GRDB → relay fetch.
    func resolveProfiles(pubkeyHexes: [String], cacheRepo: ProfileCacheRepository? = nil) async throws -> [String: NostrProfile] {
        if !isActivated {
            return pubkeyHexes.reduce(into: [:]) { result, hex in
                result[hex] = profileCache[hex]
            }
        }

        var result: [String: NostrProfile] = [:]
        var uncachedAfterMemory: [String] = []

        // Layer 1: in-memory
        for hex in pubkeyHexes {
            if let cached = profileCache[hex] {
                result[hex] = cached
            } else {
                uncachedAfterMemory.append(hex)
            }
        }

        // Layer 2: GRDB
        var uncachedAfterDB: [String] = []
        if let repo = cacheRepo {
            for hex in uncachedAfterMemory {
                if let cached = try? repo.fetchProfile(pubkeyHex: hex) {
                    result[hex] = cached
                    profileCache[hex] = cached  // warm in-memory cache
                } else {
                    uncachedAfterDB.append(hex)
                }
            }
        } else {
            uncachedAfterDB = uncachedAfterMemory
        }

        // Layer 3: relay fetch
        if !uncachedAfterDB.isEmpty {
            let fetched = try await fetchProfiles(pubkeyHexes: uncachedAfterDB)
            for (key, profile) in fetched {
                profileCache[key] = profile
                result[key] = profile
            }
            try? cacheRepo?.upsertProfiles(Array(fetched.values))
        }

        return result
    }

    // MARK: - Feed

    /// Fetch kind 1 (text notes) and kind 1502 (final round records) from followed pubkeys
    /// that are tagged with #golf. Returns verified events sorted by created_at descending.
    func fetchFeedEvents(followedPubkeys: [String]) async throws -> [Event] {
        guard isActivated else {
            print("[RAID][Guest] fetchFeedEvents blocked — Nostr not activated")
            return []
        }
        guard !followedPubkeys.isEmpty else { return [] }

        let pubkeys = try followedPubkeys.compactMap { hex -> PublicKey? in
            try PublicKey.parse(publicKey: hex)
        }
        guard !pubkeys.isEmpty else { return [] }

        let client = try await connectReadClient()

        let filter = Filter()
            .authors(authors: pubkeys)
            .kinds(kinds: [Kind(kind: 1), Kind(kind: NIP101gKind.finalRoundRecord)])
            .hashtag(hashtag: "golf")
            .limit(limit: 50)

        let events: Events
        do {
            events = try await client.fetchEvents(filter: filter, timeout: readTimeout)
        } catch {
            await client.disconnect()
            throw NostrReadError.networkFailure(error)
        }

        await client.disconnect()
        return verifiedEvents(try events.toVec())
    }

    /// Fetch feed events using NIP-65 outbox routing.
    /// Fans out to authors' write relays (capped at 6), with orphan safety net via default relays.
    /// Deduplicates by event ID across relay results. Per-relay failures are non-fatal.
    func fetchFeedEventsOutbox(authorRelayMap: [String: [String]], keys: Keys? = nil) async throws -> [Event] {
        guard isActivated else {
            print("[RAID][Guest] fetchFeedEventsOutbox blocked — Nostr not activated")
            return []
        }
        guard !authorRelayMap.isEmpty else { return [] }

        let allAuthors = Set(authorRelayMap.keys)

        // Steps 1-5: pure relay plan building (extracted for testability)
        let (relayPlan, orphanCount) = Self.buildRelayPlan(authorRelayMap: authorRelayMap)

        print("[RAID][Outbox] Fan-out: \(relayPlan.count) relays, \(allAuthors.count) authors (\(orphanCount) orphaned)")

        // 6. Fan out with TaskGroup — one connection per relay, 8s total timeout each
        var allEvents: [Event] = []
        await withTaskGroup(of: [Event].self) { group in
            for (relayURL, authorHexes) in relayPlan {
                group.addTask {
                    await self.fetchFeedFromRelay(relayURL: relayURL, authorHexes: authorHexes, keys: keys)
                }
            }
            for await relayEvents in group {
                allEvents.append(contentsOf: relayEvents)
            }
        }

        // 7. Dedup by event ID
        var seen = Set<String>()
        var unique: [Event] = []
        for event in allEvents {
            let id = event.id().toHex()
            if seen.insert(id).inserted {
                unique.append(event)
            }
        }

        return verifiedEvents(unique)
    }

    /// Fetch feed events from a single relay for specific authors.
    /// Per-relay failure is non-fatal — returns empty array on error.
    private func fetchFeedFromRelay(relayURL: String, authorHexes: [String], keys: Keys? = nil) async -> [Event] {
        let pubkeys = authorHexes.compactMap { try? PublicKey.parse(publicKey: $0) }
        guard !pubkeys.isEmpty else { return [] }

        do {
            let client: Client
            if let keys {
                let signer = NostrSigner.keys(keys: keys)
                client = ClientBuilder().signer(signer: signer).build()
            } else {
                client = Client()
            }
            let url = try RelayUrl.parse(url: relayURL)
            _ = try await client.addRelay(url: url)
            await client.connect()

            let filter = Filter()
                .authors(authors: pubkeys)
                .kinds(kinds: [Kind(kind: 1), Kind(kind: NIP101gKind.finalRoundRecord)])
                .hashtag(hashtag: "golf")
                .limit(limit: 50)

            let events = try await client.fetchEvents(filter: filter, timeout: 8)
            await client.disconnect()
            let verified = verifiedEvents(try events.toVec())
            print("[RAID][Outbox] \(relayURL): \(verified.count) events from \(authorHexes.count) authors")
            return verified
        } catch {
            print("[RAID][Outbox] \(relayURL) failed: \(error.localizedDescription)")
            return []
        }
    }

    /// Strip trailing slash from relay URLs for consistent grouping.
    static func normalizedRelayURL(_ url: String) -> String {
        url.hasSuffix("/") ? String(url.dropLast()) : url
    }

    /// Build an outbox relay plan from an author→relays map.
    ///
    /// Pure data transformation — no network calls. Extracted for testability.
    ///
    /// Steps:
    ///   1. Normalize URLs and invert to relayURL → Set<authorHex>.
    ///   2. Remove metadata-only relays (purplepag.es, user.kindpag.es, relay.nos.social).
    ///   3. Sort by author-coverage descending, cap at `maxRelays`.
    ///   4. Identify authors not covered by the top relays (orphans).
    ///   5. Route orphans to `defaultPublishRelays`; merge if relay already in plan.
    ///
    /// - Returns: `relayPlan` mapping relay URL → [authorHex], and `orphanCount`.
    static func buildRelayPlan(
        authorRelayMap: [String: [String]],
        maxRelays: Int = 6
    ) -> (relayPlan: [String: [String]], orphanCount: Int) {
        guard !authorRelayMap.isEmpty else { return ([:], 0) }

        let allAuthors = Set(authorRelayMap.keys)

        // 1. Normalize URLs and build relayURL → Set<authorHex> map
        var relayAuthorMap: [String: Set<String>] = [:]
        for (authorHex, relayURLs) in authorRelayMap {
            for url in relayURLs {
                let normalized = normalizedRelayURL(url)
                relayAuthorMap[normalized, default: []].insert(authorHex)
            }
        }

        // 2. Remove metadata-only relays that never carry content events
        let metadataOnlyRelays: Set<String> = [
            "wss://purplepag.es",
            "wss://user.kindpag.es",
            "wss://relay.nos.social",
        ]
        for url in metadataOnlyRelays {
            relayAuthorMap.removeValue(forKey: url)
        }

        // 3. Sort relays by author-coverage (most authors first), take top N
        let sortedRelays = relayAuthorMap.keys.sorted {
            relayAuthorMap[$0]!.count > relayAuthorMap[$1]!.count
        }
        let topRelays = Array(sortedRelays.prefix(maxRelays))

        // 4. Orphan safety net: find authors not covered by top relays
        let coveredAuthors = topRelays.reduce(into: Set<String>()) { result, url in
            result.formUnion(relayAuthorMap[url] ?? [])
        }
        let orphanedAuthors = allAuthors.subtracting(coveredAuthors)

        // 5. Build final relay plan: top relays + default relays with orphans
        var relayPlan: [String: [String]] = [:]
        for url in topRelays {
            relayPlan[url] = Array(relayAuthorMap[url] ?? [])
        }

        let defaultRelayAuthors = orphanedAuthors.isEmpty ? [] : Array(orphanedAuthors)
        for defaultURL in Self.defaultPublishRelays {
            let normalized = normalizedRelayURL(defaultURL)
            if relayPlan[normalized] != nil {
                if !defaultRelayAuthors.isEmpty {
                    var existing = Set(relayPlan[normalized]!)
                    existing.formUnion(orphanedAuthors)
                    relayPlan[normalized] = Array(existing)
                }
            } else if !defaultRelayAuthors.isEmpty {
                relayPlan[normalized] = defaultRelayAuthors
            }
        }

        return (relayPlan, orphanedAuthors.count)
    }

    // MARK: - Live Scorecard Fetch

    /// Fetch kind 30501 live scorecard events for a round (by initiation event ID).
    /// Returns all matching events — caller deduplicates (keep latest per author).
    func fetchLiveScorecards(initiationEventId: String) async throws -> [Event] {
        guard isActivated else {
            print("[RAID][Guest] fetchLiveScorecards blocked — Nostr not activated")
            return []
        }
        let client = try await connectReadClient()

        // Filter by kind 30501 with e tag matching initiation event ID
        let eventId = try EventId.parse(id: initiationEventId)
        let filter = Filter()
            .kind(kind: Kind(kind: NIP101gKind.liveScorecard))
            .event(eventId: eventId)

        let events: Events
        do {
            events = try await client.fetchEvents(filter: filter, timeout: readTimeout)
        } catch {
            await client.disconnect()
            throw NostrReadError.networkFailure(error)
        }

        await client.disconnect()
        return verifiedEvents(try events.toVec())
    }

    /// Fetch kind 1502 final record events for a round (by initiation event ID).
    /// Returns all matching events — each player publishes their own.
    func fetchFinalRecords(initiationEventId: String) async throws -> [Event] {
        guard isActivated else {
            print("[RAID][Guest] fetchFinalRecords blocked — Nostr not activated")
            return []
        }
        let client = try await connectReadClient()

        let eventId = try EventId.parse(id: initiationEventId)
        let filter = Filter()
            .kind(kind: Kind(kind: NIP101gKind.finalRoundRecord))
            .event(eventId: eventId)

        let events: Events
        do {
            events = try await client.fetchEvents(filter: filter, timeout: readTimeout)
        } catch {
            await client.disconnect()
            throw NostrReadError.networkFailure(error)
        }

        await client.disconnect()
        return verifiedEvents(try events.toVec())
    }

    // MARK: - Event Fetch by ID

    /// Fetch a single event by its hex ID from read relays.
    /// Returns nil if the event is not found on any relay.
    func fetchEvent(eventIdHex: String) async throws -> Event? {
        guard isActivated else {
            print("[RAID][Guest] fetchEvent blocked — Nostr not activated")
            return nil
        }
        let eventId = try EventId.parse(id: eventIdHex)
        let client = try await connectReadClient()

        let filter = Filter()
            .id(id: eventId)
            .limit(limit: 1)

        let events: Events
        do {
            events = try await client.fetchEvents(filter: filter, timeout: readTimeout)
        } catch {
            await client.disconnect()
            throw NostrReadError.networkFailure(error)
        }

        await client.disconnect()
        guard let event = events.first() else { return nil }
        return verifiedEvents([event]).first
    }

    /// Fetch multiple events by their hex IDs in a single relay query.
    /// Returns verified events. Unmatched IDs are silently omitted.
    func fetchEventsByIds(_ hexIds: [String]) async throws -> [Event] {
        guard isActivated else {
            print("[RAID][Guest] fetchEventsByIds blocked — Nostr not activated")
            return []
        }
        guard !hexIds.isEmpty else { return [] }

        let eventIds = hexIds.compactMap { try? EventId.parse(id: $0) }
        guard !eventIds.isEmpty else { return [] }

        let client = try await connectReadClient()

        let filter = Filter().ids(ids: eventIds)

        let events: Events
        do {
            events = try await client.fetchEvents(filter: filter, timeout: readTimeout)
        } catch {
            await client.disconnect()
            throw NostrReadError.networkFailure(error)
        }

        await client.disconnect()
        return verifiedEvents(try events.toVec())
    }

    // MARK: - NIP-25 Reactions

    /// Publish a reaction to an event (NIP-25, kind 7).
    /// reaction: "+" for like, or emoji string like "🔥".
    func publishReaction(keys: Keys, event: Event, reaction: String = "+") async throws {
        guard isActivated else {
            print("[RAID][Guest] publishReaction blocked — Nostr not activated")
            return
        }
        let builder = EventBuilder.reaction(event: event, reaction: reaction)
        _ = try await publishEvent(keys: keys, builder: builder)
    }

    /// Fetch reactions (kind 7) for a batch of event IDs in a single relay connection.
    /// Returns counts per event and the set of event IDs the given user has reacted to.
    func fetchReactions(eventIds: [String], ownPubkeyHex: String?) async throws -> (counts: [String: Int], ownReacted: Set<String>) {
        guard isActivated else { return (counts: [:], ownReacted: []) }
        guard !eventIds.isEmpty else { return (counts: [:], ownReacted: []) }

        let client = try await connectReadClient()

        // kind 7 events referencing any of these event IDs
        let ids = try eventIds.map { try EventId.parse(id: $0) }
        let filter = Filter()
            .kind(kind: Kind(kind: 7))
            .events(ids: ids)

        let events: Events
        do {
            events = try await client.fetchEvents(filter: filter, timeout: readTimeout)
        } catch {
            await client.disconnect()
            throw NostrReadError.networkFailure(error)
        }

        await client.disconnect()

        var counts: [String: Int] = [:]
        var ownReacted: Set<String> = []

        for event in try events.toVec() {
            // Find which event this reaction references via e-tag
            let tags = event.tags().toVec()
            for tag in tags {
                let vec = tag.asVec()
                if vec.count >= 2 && vec[0] == "e" {
                    let refId = vec[1]
                    counts[refId, default: 0] += 1
                    if let own = ownPubkeyHex, event.author().toHex() == own {
                        ownReacted.insert(refId)
                    }
                    break
                }
            }
        }

        return (counts: counts, ownReacted: ownReacted)
    }

    // MARK: - NIP-10 Text Note Replies

    /// Publish a kind 1 reply to a kind 1 text note (NIP-10 threading).
    func publishReply(keys: Keys, content: String, replyTo: Event) async throws {
        guard isActivated else {
            print("[RAID][Guest] publishReply blocked — Nostr not activated")
            return
        }
        let builder = try EventBuilder.textNoteReply(content: content, replyTo: replyTo, root: nil, relayUrl: nil)
        _ = try await publishEvent(keys: keys, builder: builder)
    }

    /// Fetch kind 1 replies to a specific event (NIP-10 threading).
    /// Returns verified events sorted by created_at ascending.
    func fetchReplies(eventId: String) async throws -> [Event] {
        guard isActivated else { return [] }
        let id = try EventId.parse(id: eventId)
        let client = try await connectReadClient()

        let filter = Filter()
            .kind(kind: Kind(kind: 1))
            .event(eventId: id)

        let events: Events
        do {
            events = try await client.fetchEvents(filter: filter, timeout: readTimeout)
        } catch {
            await client.disconnect()
            throw NostrReadError.networkFailure(error)
        }

        await client.disconnect()
        return verifiedEvents(try events.toVec())
            .sorted { $0.createdAt().asSecs() < $1.createdAt().asSecs() }
    }

    /// Fetch reply counts (kind 1 with e-tag) for multiple events. Returns [eventIdHex: count].
    func fetchReplyCounts(eventIds: [String]) async throws -> [String: Int] {
        guard isActivated else { return [:] }
        guard !eventIds.isEmpty else { return [:] }

        let ids = try eventIds.map { try EventId.parse(id: $0) }
        let client = try await connectReadClient()

        let filter = Filter()
            .kind(kind: Kind(kind: 1))
            .events(ids: ids)

        let events: Events
        do {
            events = try await client.fetchEvents(filter: filter, timeout: readTimeout)
        } catch {
            await client.disconnect()
            throw NostrReadError.networkFailure(error)
        }

        await client.disconnect()

        var counts: [String: Int] = [:]
        for event in try events.toVec() {
            let tags = event.tags().toVec()
            for tag in tags {
                let vec = tag.asVec()
                if vec.count >= 2 && vec[0] == "e" {
                    counts[vec[1], default: 0] += 1
                    break
                }
            }
        }

        return counts
    }

    // MARK: - NIP-22 Comments

    /// Publish a comment on a non-kind-1 event (NIP-22, kind 1111).
    /// Must NOT be used for kind 1 text notes — use publishReply instead.
    func publishComment(keys: Keys, content: String, targetEvent: Event) async throws {
        guard isActivated else {
            print("[RAID][Guest] publishComment blocked — Nostr not activated")
            return
        }
        let target = CommentTarget.event(
            id: targetEvent.id(),
            relayHint: nil,
            pubkeyHint: targetEvent.author(),
            kind: targetEvent.kind()
        )
        let builder = try EventBuilder.comment(content: content, commentTo: target, root: nil)
        _ = try await publishEvent(keys: keys, builder: builder)
    }

    /// Fetch comments (kind 1111) on a specific event.
    /// Returns verified events sorted by created_at ascending.
    func fetchComments(eventId: String) async throws -> [Event] {
        guard isActivated else { return [] }
        let id = try EventId.parse(id: eventId)
        let client = try await connectReadClient()

        let filter = Filter()
            .kind(kind: Kind(kind: 1111))
            .event(eventId: id)

        let events: Events
        do {
            events = try await client.fetchEvents(filter: filter, timeout: readTimeout)
        } catch {
            await client.disconnect()
            throw NostrReadError.networkFailure(error)
        }

        await client.disconnect()
        return verifiedEvents(try events.toVec())
            .sorted { $0.createdAt().asSecs() < $1.createdAt().asSecs() }
    }

    /// Fetch comment counts for multiple events. Returns [eventIdHex: count].
    func fetchCommentCounts(eventIds: [String]) async throws -> [String: Int] {
        guard isActivated else { return [:] }
        guard !eventIds.isEmpty else { return [:] }

        let ids = try eventIds.map { try EventId.parse(id: $0) }
        let client = try await connectReadClient()

        let filter = Filter()
            .kind(kind: Kind(kind: 1111))
            .events(ids: ids)

        let events: Events
        do {
            events = try await client.fetchEvents(filter: filter, timeout: readTimeout)
        } catch {
            await client.disconnect()
            throw NostrReadError.networkFailure(error)
        }

        await client.disconnect()

        var counts: [String: Int] = [:]
        for event in try events.toVec() {
            let tags = event.tags().toVec()
            for tag in tags {
                let vec = tag.asVec()
                // NIP-22 uses uppercase E for root, lowercase e for parent
                if vec.count >= 2 && (vec[0] == "E" || vec[0] == "e") {
                    counts[vec[1], default: 0] += 1
                    break
                }
            }
        }

        return counts
    }

    // MARK: - NIP-51 Clubhouse (Follow Set)

    /// Fetch the user's Clubhouse list (kind 30000, d="clubhouse").
    /// Returns pubkey hex strings of members, or empty if no list found.
    func fetchClubhouse(pubkeyHex: String) async throws -> [String] {
        guard isActivated else {
            print("[RAID][Guest] fetchClubhouse blocked — Nostr not activated")
            return []
        }
        let pubkey = try PublicKey.parse(publicKey: pubkeyHex)
        let client = try await connectReadClient()

        let filter = Filter()
            .author(author: pubkey)
            .kind(kind: Kind(kind: 30000))
            .identifier(identifier: "clubhouse")
            .limit(limit: 1)

        let events: Events
        do {
            events = try await client.fetchEvents(filter: filter, timeout: readTimeout)
        } catch {
            await client.disconnect()
            throw NostrReadError.networkFailure(error)
        }

        await client.disconnect()

        // Kind 30000 is addressable replaceable — pick newest created_at.
        let allClubhouseEvents = verifiedEvents(try events.toVec())
        guard let event = allClubhouseEvents
            .sorted(by: { $0.createdAt().asSecs() > $1.createdAt().asSecs() })
            .first else {
            return []
        }

        // Extract p-tags (member pubkeys)
        let tags = event.tags().toVec()
        var members: [String] = []
        for tag in tags {
            let vec = tag.asVec()
            if vec.count >= 2 && vec[0] == "p" {
                members.append(vec[1])
            }
        }
        return members
    }

    /// Publish the user's Clubhouse list (kind 30000, d="clubhouse").
    /// Addressable replaceable — relays keep only the newest per (author, kind, d-tag).
    func publishClubhouse(keys: Keys, memberPubkeyHexes: [String]) async throws {
        guard isActivated else {
            print("[RAID][Guest] publishClubhouse blocked — Nostr not activated")
            return
        }
        let pubkeys = try memberPubkeyHexes.map { try PublicKey.parse(publicKey: $0) }
        let builder = EventBuilder.followSet(identifier: "clubhouse", publicKeys: pubkeys)
        _ = try await publishEvent(keys: keys, builder: builder)
    }

    // MARK: - NIP-17 Gift Wrap DMs

    /// Fetch a user's kind 10050 DM inbox relay list (NIP-17).
    /// Returns relay URL strings, or empty if no 10050 found.
    func fetchInboxRelays(pubkeyHex: String) async throws -> [String] {
        guard isActivated else {
            print("[RAID][Guest] fetchInboxRelays blocked — Nostr not activated")
            return []
        }
        let pubkey = try PublicKey.parse(publicKey: pubkeyHex)
        let client = try await connectReadClient()

        let filter = Filter()
            .author(author: pubkey)
            .kind(kind: Kind(kind: 10050))
            .limit(limit: 1)

        let events: Events
        do {
            events = try await client.fetchEvents(filter: filter, timeout: readTimeout)
        } catch {
            await client.disconnect()
            throw NostrReadError.networkFailure(error)
        }

        await client.disconnect()

        // Kind 10050 is replaceable — pick newest created_at.
        let allInboxEvents = verifiedEvents(try events.toVec())
        guard let event = allInboxEvents
            .sorted(by: { $0.createdAt().asSecs() > $1.createdAt().asSecs() })
            .first else {
            return []
        }

        // Parse "relay" tags from kind 10050
        let tags = event.tags().toVec()
        var relays: [String] = []
        for tag in tags {
            let vec = tag.asVec()
            if vec.count >= 2 && vec[0] == "relay" {
                relays.append(vec[1])
            }
        }
        return relays
    }

    /// Send a NIP-17 gift-wrapped DM to a single recipient.
    /// The SDK handles the full NIP-59 flow internally (rumor → seal → gift wrap).
    /// Sends to recipient's inbox relays (kind 10050) + default relays for redundancy.
    func sendGiftWrapDM(senderKeys: Keys, receiverPubkeyHex: String, rumor: UnsignedEvent, targetRelays: [String]? = nil) async throws {
        guard isActivated else {
            print("[RAID][Guest] sendGiftWrapDM blocked — Nostr not activated")
            return
        }
        let receiver = try PublicKey.parse(publicKey: receiverPubkeyHex)
        let signer = NostrSigner.keys(keys: senderKeys)
        let client = Client(signer: signer)

        // Connect to all relays: inbox + defaults (deduplicated)
        var allRelayStrings = Set(Self.defaultPublishRelays)
        if let targetRelays {
            allRelayStrings.formUnion(targetRelays)
        }

        for urlString in allRelayStrings {
            let url = try RelayUrl.parse(url: urlString)
            _ = try await client.addRelay(url: url)
        }

        await client.connect()

        // Use giftWrap to send to ALL connected relays (inbox + defaults)
        let output = try await client.giftWrap(receiver: receiver, rumor: rumor, extraTags: [])

        await client.disconnect()

        if output.success.isEmpty {
            throw NostrPublishError.allRelaysFailed
        }
    }

    /// Publish the user's kind 10050 DM inbox relay preferences (NIP-17).
    /// Replaceable — overwrites any previous 10050.
    func publishInboxRelays(keys: Keys, relays: [String]) async throws {
        guard isActivated else {
            print("[RAID][Guest] publishInboxRelays blocked — Nostr not activated")
            return
        }
        var tags: [Tag] = []
        for relay in relays {
            tags.append(try Tag.parse(data: ["relay", relay]))
        }

        let builder = EventBuilder(kind: Kind(kind: 10050), content: "")
            .tags(tags: tags)

        _ = try await publishEvent(keys: keys, builder: builder)
    }

    /// Fetch kind 1059 gift wrap events addressed to the user from read relays.
    /// Returns raw events — caller unwraps and filters.
    func fetchGiftWraps(recipientPubkey: PublicKey, since: UInt64? = nil) async throws -> [Event] {
        guard isActivated else {
            print("[RAID][Guest] fetchGiftWraps blocked — Nostr not activated")
            return []
        }
        let client = try await connectReadClient()

        var filter = Filter()
            .kind(kind: Kind(kind: 1059))
            .pubkey(pubkey: recipientPubkey)

        if let since {
            filter = filter.since(timestamp: Timestamp.fromSecs(secs: since))
        }

        let events: Events
        do {
            events = try await client.fetchEvents(filter: filter, timeout: readTimeout)
        } catch {
            await client.disconnect()
            throw NostrReadError.networkFailure(error)
        }

        await client.disconnect()
        // Note: gift wraps are signed by ephemeral keys, so we don't verify signatures here.
        // The UnwrappedGift.fromGiftWrap method handles cryptographic verification of the seal.
        return try events.toVec()
    }

    /// Unwrap a single gift wrap event. Returns nil if unwrap fails.
    func unwrapGiftWrap(keys: Keys, giftWrap: Event) async -> UnwrappedGift? {
        guard isActivated else {
            print("[RAID][Guest] unwrapGiftWrap blocked — Nostr not activated")
            return nil
        }
        let signer = NostrSigner.keys(keys: keys)
        do {
            return try await UnwrappedGift.fromGiftWrap(signer: signer, giftWrap: giftWrap)
        } catch {
            print("[RAID][GiftWrap] Failed to unwrap event: \(error)")
            return nil
        }
    }

    // MARK: - NIP-65 Relay List

    /// Fetch kind 10002 relay list metadata for multiple pubkeys in a single batch.
    /// Handles replaceable events: picks newest created_at per author.
    func fetchRelayLists(pubkeyHexes: [String]) async throws -> [String: [CachedRelayEntry]] {
        guard isActivated else {
            print("[RAID][Guest] fetchRelayLists blocked — Nostr not activated")
            return [:]
        }
        guard !pubkeyHexes.isEmpty else { return [:] }

        let pubkeys = pubkeyHexes.compactMap { try? PublicKey.parse(publicKey: $0) }
        guard !pubkeys.isEmpty else { return [:] }

        let client = try await connectReadClient()

        let filter = Filter()
            .authors(authors: pubkeys)
            .kind(kind: Kind(kind: 10002))

        let events: Events
        do {
            events = try await client.fetchEvents(filter: filter, timeout: readTimeout)
        } catch {
            await client.disconnect()
            throw NostrReadError.networkFailure(error)
        }

        await client.disconnect()

        // Kind 10002 is replaceable — keep newest per author
        var newest: [String: Event] = [:]
        for event in verifiedEvents(try events.toVec()) {
            let authorHex = event.author().toHex()
            if let existing = newest[authorHex] {
                if event.createdAt().asSecs() > existing.createdAt().asSecs() {
                    newest[authorHex] = event
                }
            } else {
                newest[authorHex] = event
            }
        }

        // Parse r-tags into CachedRelayEntry
        var result: [String: [CachedRelayEntry]] = [:]
        for (authorHex, event) in newest {
            var entries: [CachedRelayEntry] = []
            let tags = event.tags().toVec()
            for tag in tags {
                let vec = tag.asVec()
                if vec.count >= 2 && vec[0] == "r" {
                    let url = vec[1]
                    let marker: String? = vec.count >= 3 ? vec[2] : nil
                    entries.append(CachedRelayEntry(url: url, marker: marker))
                }
            }
            result[authorHex] = entries
        }

        // Warm in-memory cache
        for (key, entries) in result {
            relayListCache[key] = entries
        }

        return result
    }

    /// Publish the user's NIP-65 relay list (kind 10002).
    /// Replaceable — overwrites any previous 10002.
    func publishRelayList(keys: Keys, relays: [CachedRelayEntry]) async throws -> String {
        guard isActivated else {
            print("[RAID][Guest] publishRelayList blocked — Nostr not activated")
            return ""
        }
        var tags: [Tag] = []
        for relay in relays {
            if let marker = relay.marker {
                tags.append(try Tag.parse(data: ["r", relay.url, marker]))
            } else {
                tags.append(try Tag.parse(data: ["r", relay.url]))
            }
        }

        let builder = EventBuilder(kind: Kind(kind: 10002), content: "")
            .tags(tags: tags)

        return try await publishEvent(keys: keys, builder: builder)
    }

    /// Resolve relay lists from cache (in-memory then GRDB) or fetch uncached keys from relays.
    /// Three-layer lookup: in-memory → GRDB (24h TTL) → relay fetch.
    func resolveRelayLists(pubkeyHexes: [String], cacheRepo: RelayCacheRepository? = nil) async throws -> [String: [CachedRelayEntry]] {
        if !isActivated {
            return pubkeyHexes.reduce(into: [:]) { result, hex in
                result[hex] = relayListCache[hex]
            }
        }

        let ttl: TimeInterval = 24 * 60 * 60  // 24 hours
        var result: [String: [CachedRelayEntry]] = [:]
        var uncachedAfterMemory: [String] = []

        // Layer 1: in-memory
        for hex in pubkeyHexes {
            if let cached = relayListCache[hex] {
                result[hex] = cached
            } else {
                uncachedAfterMemory.append(hex)
            }
        }

        // Layer 2: GRDB (with 24h TTL check)
        var uncachedAfterDB: [String] = []
        if let repo = cacheRepo {
            for hex in uncachedAfterMemory {
                if let cached = try? repo.fetchRelayList(pubkeyHex: hex),
                   Date().timeIntervalSince(cached.cachedAt) < ttl {
                    result[hex] = cached.relays
                    relayListCache[hex] = cached.relays  // warm in-memory cache
                } else {
                    uncachedAfterDB.append(hex)
                }
            }
        } else {
            uncachedAfterDB = uncachedAfterMemory
        }

        // Layer 3: relay fetch
        if !uncachedAfterDB.isEmpty {
            let fetched = try await fetchRelayLists(pubkeyHexes: uncachedAfterDB)
            for (key, entries) in fetched {
                relayListCache[key] = entries
                result[key] = entries
            }
            // Persist to GRDB
            if let repo = cacheRepo {
                let lists = fetched.map { (hex, entries) in
                    CachedRelayList(pubkeyHex: hex, relays: entries, cachedAt: Date())
                }
                try? repo.upsertRelayLists(lists)
            }
        }

        return result
    }

    // MARK: - Private Helpers

    /// Filter events to only those with valid cryptographic signatures.
    /// Discards events where id or schnorr signature verification fails.
    private func verifiedEvents(_ events: [Event]) -> [Event] {
        events.filter { event in
            if event.verify() { return true }
            print("[RAID][Verify] Discarded invalid event \(event.id().toHex().prefix(12))...")
            return false
        }
    }

    private func connectReadClient() async throws -> Client {
        let client = Client()

        for urlString in Self.defaultReadRelays {
            let url = try RelayUrl.parse(url: urlString)
            _ = try await client.addRelay(url: url)
        }

        await client.connect()
        return client
    }

    private func fetchProfileEvents(client: Client, pubkeys: [PublicKey]) async throws -> [Event] {
        let filter = Filter()
            .authors(authors: pubkeys)
            .kind(kind: Kind(kind: 0))

        let events: Events
        do {
            events = try await client.fetchEvents(filter: filter, timeout: readTimeout)
        } catch {
            throw NostrReadError.networkFailure(error)
        }

        return try events.toVec()
    }

    private func parseProfileEvents(_ eventList: [Event]) -> [String: NostrProfile] {
        // Kind 0 is replaceable — keep newest per author
        var newest: [String: Event] = [:]
        for event in eventList {
            let authorHex = event.author().toHex()
            if let existing = newest[authorHex] {
                if event.createdAt().asSecs() > existing.createdAt().asSecs() {
                    newest[authorHex] = event
                }
            } else {
                newest[authorHex] = event
            }
        }

        var result: [String: NostrProfile] = [:]
        for (authorHex, event) in newest {
            let profile = NostrProfile.parse(from: event.content(), pubkeyHex: authorHex)
            result[authorHex] = profile
        }
        return result
    }
}

// MARK: - Environment Key

private struct NostrServiceKey: EnvironmentKey {
    static let defaultValue = NostrService()
}

extension EnvironmentValues {
    var nostrService: NostrService {
        get { self[NostrServiceKey.self] }
        set { self[NostrServiceKey.self] = newValue }
    }
}

// MARK: - Data Types

/// Profile metadata parsed from kind 0 events (NIP-01).
struct NostrProfile: Identifiable {
    var id: String { pubkeyHex }

    let pubkeyHex: String
    var name: String?
    var displayName: String?
    var picture: String?
    var about: String?
    var banner: String?
    var nip05: String? = nil

    /// Best available display string: displayName > name > truncated pubkey.
    var displayLabel: String {
        if let displayName, !displayName.isEmpty { return displayName }
        if let name, !name.isEmpty { return name }
        return String(pubkeyHex.prefix(8)) + "..."
    }

    /// Parse profile from kind 0 event content JSON.
    static func parse(from content: String, pubkeyHex: String) -> NostrProfile {
        guard let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return NostrProfile(pubkeyHex: pubkeyHex, name: nil, displayName: nil, picture: nil)
        }

        return NostrProfile(
            pubkeyHex: pubkeyHex,
            name: json["name"] as? String,
            displayName: json["display_name"] as? String,
            picture: json["picture"] as? String,
            about: json["about"] as? String,
            banner: json["banner"] as? String,
            nip05: json["nip05"] as? String
        )
    }
}

// MARK: - Author Verification

/// Check whether an event's author is in the list of authorized pubkeys for a round.
/// Used to reject scoring events from unauthorized parties (B-004).
func isAuthorizedPlayer(_ authorHex: String, allowedPubkeys: [String]) -> Bool {
    allowedPubkeys.contains(authorHex)
}

// MARK: - Errors

enum NostrPublishError: LocalizedError {
    case allRelaysFailed

    var errorDescription: String? {
        switch self {
        case .allRelaysFailed:
            return "Couldn't connect to Nostr relays. Try again later."
        }
    }
}

enum NostrReadError: LocalizedError {
    case networkFailure(Error)

    var errorDescription: String? {
        switch self {
        case .networkFailure:
            return "Couldn't fetch data from Nostr relays. Check your connection and try again."
        }
    }
}
