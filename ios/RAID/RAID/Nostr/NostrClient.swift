// Gambit Golf — Nostr Client
// Fire-and-forget publisher + one-shot reader. No singleton, no persistent connections.
// Future: centralized NostrClientService with persistent connections and caching.

import Foundation
import NostrSDK

enum NostrClient {

    static let defaultRelays = [
        "wss://relay.damus.io",
        "wss://nos.lol",
        "wss://relay.nostr.band"
    ]

    /// Relays used for metadata reads. Kept small to minimize connection overhead.
    static let readRelays = [
        "wss://relay.damus.io",
        "wss://nos.lol",
        "wss://purplepag.es"
    ]

    private static let readTimeout: TimeInterval = 5

    /// Publish a pre-built EventBuilder and return its event ID.
    /// Used for NIP-101g events where we need the ID for cross-referencing.
    static func publishEvent(keys: Keys, builder: EventBuilder) async throws -> String {
        let signer = NostrSigner.keys(keys: keys)
        let client = Client(signer: signer)

        for urlString in defaultRelays {
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
    static func fetchFollowList(pubkey: PublicKey) async throws -> [String] {
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
        guard let contactEvent = events.first() else {
            return []
        }

        // Extract pubkeys from p tags
        let pubkeys = contactEvent.tags().publicKeys()
        return pubkeys.map { $0.toHex() }
    }

    /// Fetch profile metadata (kind 0 / NIP-01) for a list of public keys.
    /// Returns a dictionary mapping pubkey hex → NostrProfile.
    static func fetchProfiles(pubkeyHexes: [String]) async throws -> [String: NostrProfile] {
        guard !pubkeyHexes.isEmpty else { return [:] }

        let pubkeys = try pubkeyHexes.compactMap { hex -> PublicKey? in
            try PublicKey.parse(publicKey: hex)
        }

        guard !pubkeys.isEmpty else { return [:] }

        let client = try await connectReadClient()

        let events = try await fetchProfileEvents(client: client, pubkeys: pubkeys)

        await client.disconnect()

        return parseProfileEvents(events)
    }

    /// Fetch follow list and profiles in a single connection session.
    /// Avoids the overhead of connecting/disconnecting twice.
    static func fetchFollowListWithProfiles(pubkey: PublicKey) async throws -> (follows: [String], profiles: [String: NostrProfile]) {
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

        guard let contactEvent = followEvents.first() else {
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

        return (follows: followedHexes, profiles: parseProfileEvents(profileEvents))
    }

    // MARK: - Live Scorecard Fetch

    /// Fetch kind 30501 live scorecard events for a round (by initiation event ID).
    /// Returns all matching events — caller deduplicates (keep latest per author).
    static func fetchLiveScorecards(initiationEventId: String) async throws -> [Event] {
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
        return try events.toVec()
    }

    /// Fetch kind 1502 final record events for a round (by initiation event ID).
    /// Returns all matching events — each player publishes their own.
    static func fetchFinalRecords(initiationEventId: String) async throws -> [Event] {
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
        return try events.toVec()
    }

    // MARK: - Event Fetch by ID

    /// Fetch a single event by its hex ID from read relays.
    /// Returns nil if the event is not found on any relay.
    static func fetchEvent(eventIdHex: String) async throws -> Event? {
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
        return events.first()
    }

    // MARK: - Private Helpers

    private static func connectReadClient() async throws -> Client {
        let client = Client()

        for urlString in readRelays {
            let url = try RelayUrl.parse(url: urlString)
            _ = try await client.addRelay(url: url)
        }

        await client.connect()
        return client
    }

    private static func fetchProfileEvents(client: Client, pubkeys: [PublicKey]) async throws -> [Event] {
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

    private static func parseProfileEvents(_ eventList: [Event]) -> [String: NostrProfile] {
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

// MARK: - Data Types

/// Profile metadata parsed from kind 0 events (NIP-01).
struct NostrProfile: Identifiable {
    var id: String { pubkeyHex }

    let pubkeyHex: String
    let name: String?
    let displayName: String?
    let picture: String?

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
            picture: json["picture"] as? String
        )
    }
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
