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

    /// Publish a kind 1 text note to default relays.
    /// Creates a fresh client per call: connect → sign → publish → disconnect.
    static func publishRoundNote(keys: Keys, text: String) async throws {
        let signer = NostrSigner.keys(keys: keys)
        let client = Client(signer: signer)

        for urlString in defaultRelays {
            let url = try RelayUrl.parse(url: urlString)
            _ = try await client.addRelay(url: url)
        }

        await client.connect()

        let builder = EventBuilder.textNote(content: text)
            .tags(tags: [
                Tag.hashtag(hashtag: "golf"),
                Tag.hashtag(hashtag: "gambitgolf"),
                try Tag.parse(data: ["client", "gambit-golf-ios"])
            ])

        let output = try await client.sendEventBuilder(builder: builder)

        if output.success.isEmpty {
            throw NostrPublishError.allRelaysFailed
        }

        await client.disconnect()
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
