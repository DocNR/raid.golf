// Gambit Golf — Nostr Client
// Fire-and-forget publisher. No singleton, no persistent connections.

import Foundation
import NostrSDK

enum NostrClient {

    static let defaultRelays = [
        "wss://relay.damus.io",
        "wss://nos.lol",
        "wss://relay.nostr.band"
    ]

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
}

enum NostrPublishError: LocalizedError {
    case allRelaysFailed

    var errorDescription: String? {
        switch self {
        case .allRelaysFailed:
            return "Couldn't connect to Nostr relays. Try again later."
        }
    }
}
