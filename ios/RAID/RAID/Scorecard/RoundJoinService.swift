// Gambit Golf — Round Join Service
// Orchestrates creating a local round from relay-fetched NIP-101g initiation data.
// Coordinates: CourseSnapshotRepository, RoundRepository, RoundPlayerRepository, RoundNostrRepository.
//
// Idempotent: if a round for the same initiation event already exists locally,
// returns the existing round ID instead of creating a duplicate.

import Foundation
import GRDB

class RoundJoinService {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// Create a local round from a NIP-101g initiation event's parsed content.
    ///
    /// - Parameters:
    ///   - content: Parsed RoundInitiationContent from the kind 1501 event
    ///   - initiationEventId: Hex event ID of the kind 1501
    ///   - date: Round date from the "date" tag
    ///   - playerPubkeys: Ordered pubkeys from "p" tags (index 0 = creator)
    ///   - myPubkey: The joining player's hex pubkey (must be in playerPubkeys)
    /// - Returns: The local round_id
    /// - Throws: RoundJoinError if player not in list, or database errors
    func createLocalRound(
        from content: RoundInitiationContent,
        initiationEventId: String,
        date: String,
        playerPubkeys: [String],
        myPubkey: String
    ) throws -> Int64 {
        // Check if already joined (idempotent)
        let nostrRepo = RoundNostrRepository(dbQueue: dbQueue)
        if let existing = try nostrRepo.fetchRound(byInitiationEventId: initiationEventId) {
            return existing.roundId
        }

        // Verify my pubkey is in the player list
        guard playerPubkeys.contains(myPubkey) else {
            throw RoundJoinError.notInPlayerList
        }

        // 1. Insert course snapshot (idempotent via INSERT OR IGNORE on hash PK)
        let snapshotRepo = CourseSnapshotRepository(dbQueue: dbQueue)
        let holes = content.courseSnapshot.holes.map { hole in
            HoleDefinition(holeNumber: hole.holeNumber, par: hole.par)
        }
        let snapshot = try snapshotRepo.insertCourseSnapshot(CourseSnapshotInput(
            courseName: content.courseSnapshot.courseName,
            teeSet: content.courseSnapshot.teeSet,
            holes: holes
        ))

        // 2. Create round
        let roundRepo = RoundRepository(dbQueue: dbQueue)
        let round = try roundRepo.createRound(courseHash: snapshot.courseHash, roundDate: date)

        // 3. Insert players — joiner is always index 0 locally (matches hole_scores convention)
        // The p-tag order from the 1501 event is preserved in Nostr events themselves;
        // the local index is purely for local scoring and display.
        let playerRepo = RoundPlayerRepository(dbQueue: dbQueue)
        let otherPubkeys = playerPubkeys.filter { $0 != myPubkey }
        try playerRepo.insertPlayers(roundId: round.roundId, creatorPubkey: myPubkey, otherPubkeys: otherPubkeys)

        // 4. Store round_nostr with joined_via = "joined"
        try nostrRepo.insertInitiation(roundId: round.roundId, initiationEventId: initiationEventId, joinedVia: "joined")

        return round.roundId
    }
}

// MARK: - Errors

enum RoundJoinError: LocalizedError {
    case notInPlayerList
    case initiationNotFound
    case hashVerificationFailed

    var errorDescription: String? {
        switch self {
        case .notInPlayerList:
            return "You are not listed as a player in this round."
        case .initiationNotFound:
            return "Round initiation event not found on relays."
        case .hashVerificationFailed:
            return "Round data integrity check failed. The initiation event may have been tampered with."
        }
    }
}
