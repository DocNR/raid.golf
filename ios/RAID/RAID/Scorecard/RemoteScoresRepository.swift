// RemoteScoresRepository.swift
// RAID Golf
//
// Mutable cache for remote players' scores fetched from Nostr relays.
// Backed by remote_scores_cache table (v8 migration). No immutability triggers.
// Upserted on each fetch — always reflects the latest relay data.

import Foundation
import GRDB

class RemoteScoresRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// Upsert scores for a remote player. Replaces existing entries for same (round, player, hole).
    func upsertScores(roundId: Int64, playerPubkey: String, scores: [Int: Int]) throws {
        let now = ISO8601DateFormatter().string(from: Date())

        try dbQueue.write { db in
            for (holeNumber, strokes) in scores {
                try db.execute(
                    sql: """
                    INSERT INTO remote_scores_cache (round_id, player_pubkey, hole_number, strokes, fetched_at)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT (round_id, player_pubkey, hole_number)
                    DO UPDATE SET strokes = excluded.strokes, fetched_at = excluded.fetched_at
                    """,
                    arguments: [roundId, playerPubkey, holeNumber, strokes, now]
                )
            }
        }
    }

    /// Fetch all cached remote scores for a round, grouped by player pubkey.
    /// Returns: [playerPubkey: [holeNumber: strokes]]
    func fetchRemoteScores(forRound roundId: Int64) throws -> [String: [Int: Int]] {
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db,
                sql: """
                SELECT player_pubkey, hole_number, strokes
                FROM remote_scores_cache
                WHERE round_id = ?
                ORDER BY player_pubkey, hole_number
                """,
                arguments: [roundId])

            var result: [String: [Int: Int]] = [:]
            for row in rows {
                let pubkey: String = row["player_pubkey"]
                let hole: Int = row["hole_number"]
                let strokes: Int = row["strokes"]
                result[pubkey, default: [:]][hole] = strokes
            }
            return result
        }
    }
}
