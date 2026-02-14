// Gambit Golf — Round Invite Builder
// Pure transformation: encode/decode round invites as NIP-19 nevent strings and NIP-21 nostr: URIs.
// No database queries, no network calls.

import Foundation
import NostrSDK

enum RoundInviteBuilder {

    /// Build a nevent1... bech32 string with relay hints.
    /// The nevent encodes the initiation event ID + relay URLs for discovery.
    static func buildNevent(eventIdHex: String, relays: [String]) throws -> String {
        let eventId = try EventId.parse(id: eventIdHex)

        let relayUrls = try relays.map { try RelayUrl.parse(url: $0) }

        let nip19Event = Nip19Event(eventId: eventId, relays: relayUrls)
        return try nip19Event.toBech32()
    }

    /// Wrap a nevent in a nostr: URI (NIP-21).
    static func buildNostrURI(nevent: String) -> String {
        return "nostr:\(nevent)"
    }

    /// Parse a nostr: URI, returning the bech32 payload or nil.
    static func parseNostrURI(uri: String) -> String? {
        let prefix = "nostr:"
        guard uri.hasPrefix(prefix) else { return nil }
        let payload = String(uri.dropFirst(prefix.count))
        guard !payload.isEmpty else { return nil }
        return payload
    }

    /// Parse a nevent1... string, extracting event ID hex and relay hints.
    static func parseNevent(nevent: String) throws -> (eventIdHex: String, relays: [String]) {
        let nip19Event = try Nip19Event.fromBech32(bech32: nevent)

        let eventIdHex = nip19Event.eventId().toHex()
        let relays = nip19Event.relays().map { $0.description }

        return (eventIdHex: eventIdHex, relays: relays)
    }
}
