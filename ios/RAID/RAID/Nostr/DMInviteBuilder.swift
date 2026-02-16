// RAID Golf — DM Invite Builder
// Pure transformation: build and parse NIP-17 gift-wrapped round invite rumors.
// No database queries, no network calls.

import Foundation
import NostrSDK

enum DMInviteBuilder {

    /// Build a kind 14 rumor (unsigned event) for a round invite DM.
    /// The rumor content is human-readable so it displays well in any NIP-17 client.
    static func buildInviteRumor(
        senderPubkey: PublicKey,
        receiverPubkeyHex: String,
        courseName: String,
        nevent: String
    ) throws -> UnsignedEvent {
        let nostrURI = RoundInviteBuilder.buildNostrURI(nevent: nevent)

        let content = """
            You've been invited to play golf at \(courseName)!

            Join: \(nostrURI)

            Sent from RAID Golf
            """.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")

        let pTag = try Tag.parse(data: ["p", receiverPubkeyHex])

        return EventBuilder(kind: Kind(kind: 14), content: content)
            .tags(tags: [pTag])
            .build(publicKey: senderPubkey)
    }

    /// Extract a nevent from a kind 14 rumor's content.
    /// Scans for nevent1[a-z0-9]+ patterns, strips any nostr: prefix.
    /// Returns nil if no valid nevent found.
    static func extractNevent(from rumor: UnsignedEvent) -> String? {
        extractNevent(fromContent: rumor.content())
    }

    /// Extract a nevent from arbitrary text content.
    static func extractNevent(fromContent content: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "nevent1[a-z0-9]+", options: []) else {
            return nil
        }
        let range = NSRange(content.startIndex..., in: content)
        guard let match = regex.firstMatch(in: content, options: [], range: range),
              let matchRange = Range(match.range, in: content) else {
            return nil
        }
        let nevent = String(content[matchRange])

        // Validate it's a real nevent by attempting to parse
        guard (try? RoundInviteBuilder.parseNevent(nevent: nevent)) != nil else {
            return nil
        }
        return nevent
    }

    /// Extract course name from invite DM content.
    /// Looks for "play golf at <name>!" pattern.
    static func extractCourseName(fromContent content: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: "play golf at (.+?)!",
            options: [.caseInsensitive]
        ) else { return nil }

        let range = NSRange(content.startIndex..., in: content)
        guard let match = regex.firstMatch(in: content, options: [], range: range),
              match.numberOfRanges > 1,
              let nameRange = Range(match.range(at: 1), in: content) else {
            return nil
        }
        return String(content[nameRange])
    }
}
