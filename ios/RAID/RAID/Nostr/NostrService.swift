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

        // Kind 3 is replaceable — first() gives the newest
        guard let contactEvent = events.first(),
              verifiedEvents([contactEvent]).first != nil else {
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

        guard let contactEvent = followEvents.first(),
              verifiedEvents([contactEvent]).first != nil else {
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

        guard let event = events.first(),
              verifiedEvents([event]).first != nil else {
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
