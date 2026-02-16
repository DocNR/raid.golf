// RAID Golf — DM Invite Service
// Orchestrates fetching, unwrapping, and deduplicating incoming NIP-17 round invites.

import Foundation
import NostrSDK
import GRDB

struct IncomingInvite: Identifiable {
    let id: String              // nevent string (dedup key)
    let nevent: String
    let senderPubkeyHex: String
    let senderProfile: NostrProfile?
    let courseName: String?
    let receivedAt: Date
}

enum DMInviteService {

    /// Fetch and unwrap incoming round invites from NIP-17 gift-wrapped DMs.
    /// Deduplicates against already-joined rounds. Resolves sender profiles.
    static func fetchIncomingInvites(
        nostrService: NostrService,
        keys: Keys,
        dbQueue: DatabaseQueue
    ) async throws -> [IncomingInvite] {
        // Look back 7 days for invites
        let sevenDaysAgo = UInt64(Date().timeIntervalSince1970) - (7 * 24 * 60 * 60)

        let giftWraps = try await nostrService.fetchGiftWraps(
            recipientPubkey: keys.publicKey(),
            since: sevenDaysAgo
        )

        var invites: [IncomingInvite] = []
        var senderHexes: Set<String> = []
        let nostrRepo = RoundNostrRepository(dbQueue: dbQueue)

        for event in giftWraps {
            // Unwrap gift wrap → extract sender + rumor
            guard let unwrapped = await nostrService.unwrapGiftWrap(keys: keys, giftWrap: event) else {
                continue
            }

            let rumor = unwrapped.rumor()

            // Only process kind 14 (NIP-17 private direct messages)
            guard rumor.kind().asU16() == 14 else { continue }

            // Extract nevent from rumor content
            guard let nevent = DMInviteBuilder.extractNevent(from: rumor) else { continue }

            // Deduplicate: skip if already joined this round
            if let (eventIdHex, _) = try? RoundInviteBuilder.parseNevent(nevent: nevent),
               (try? nostrRepo.fetchRound(byInitiationEventId: eventIdHex)) != nil {
                continue
            }

            // Deduplicate within this batch (same nevent)
            guard !invites.contains(where: { $0.nevent == nevent }) else { continue }

            let senderHex = unwrapped.sender().toHex()
            senderHexes.insert(senderHex)

            let courseName = DMInviteBuilder.extractCourseName(fromContent: rumor.content())
            let receivedAt = Date(timeIntervalSince1970: TimeInterval(event.createdAt().asSecs()))

            invites.append(IncomingInvite(
                id: nevent,
                nevent: nevent,
                senderPubkeyHex: senderHex,
                senderProfile: nil,
                courseName: courseName,
                receivedAt: receivedAt
            ))
        }

        guard !invites.isEmpty else { return [] }

        // Resolve sender profiles
        let profiles = try await nostrService.resolveProfiles(pubkeyHexes: Array(senderHexes))

        // Enrich invites with profiles
        let enriched = invites.map { invite in
            IncomingInvite(
                id: invite.id,
                nevent: invite.nevent,
                senderPubkeyHex: invite.senderPubkeyHex,
                senderProfile: profiles[invite.senderPubkeyHex],
                courseName: invite.courseName,
                receivedAt: invite.receivedAt
            )
        }

        // Sort newest first
        return enriched.sorted { $0.receivedAt > $1.receivedAt }
    }
}
