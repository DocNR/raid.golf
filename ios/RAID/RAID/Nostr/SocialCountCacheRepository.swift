// SocialCountCacheRepository.swift
// RAID Golf
//
// Persistent cache for reaction counts (NIP-25) and comment/reply counts
// (NIP-22/NIP-10) per feed event. Backed by nostr_reaction_counts and
// nostr_comment_counts tables (v14 migration). Mutable, no triggers.
// Upserted every Phase B refresh; read in Phase A for instant counts.

import Foundation
import GRDB

struct CachedReactionCount {
    let eventIdHex: String
    let count: Int
    let ownReacted: Bool
}

struct CachedCommentCount {
    let eventIdHex: String
    let count: Int
}

class SocialCountCacheRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    // MARK: - Reactions

    /// Upsert reaction counts for a batch of event IDs.
    func upsertReactionCounts(_ counts: [String: Int], ownReacted: Set<String>) throws {
        guard !counts.isEmpty else { return }
        let now = ISO8601DateFormatter().string(from: Date())
        try dbQueue.write { db in
            for (eventId, count) in counts {
                let own = ownReacted.contains(eventId) ? 1 : 0
                try db.execute(
                    sql: """
                    INSERT INTO nostr_reaction_counts (event_id_hex, count, own_reacted, cached_at)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT (event_id_hex) DO UPDATE SET
                        count       = excluded.count,
                        own_reacted = excluded.own_reacted,
                        cached_at   = excluded.cached_at
                    """,
                    arguments: [eventId, count, own, now]
                )
            }
        }
    }

    /// Fetch cached reaction counts for a list of event IDs.
    func fetchReactionCounts(eventIds: [String]) throws -> (counts: [String: Int], ownReacted: Set<String>) {
        guard !eventIds.isEmpty else { return ([:], []) }
        return try dbQueue.read { db in
            let placeholders = Array(repeating: "?", count: eventIds.count).joined(separator: ", ")
            let rows = try Row.fetchAll(db,
                sql: "SELECT event_id_hex, count, own_reacted FROM nostr_reaction_counts WHERE event_id_hex IN (\(placeholders))",
                arguments: StatementArguments(eventIds))
            var counts: [String: Int] = [:]
            var own: Set<String> = []
            for row in rows {
                let id: String = row["event_id_hex"]
                counts[id] = row["count"]
                let ownFlag: Int = row["own_reacted"]
                if ownFlag != 0 { own.insert(id) }
            }
            return (counts, own)
        }
    }

    // MARK: - Comments

    /// Upsert comment/reply counts for a batch of event IDs.
    func upsertCommentCounts(_ counts: [String: Int]) throws {
        guard !counts.isEmpty else { return }
        let now = ISO8601DateFormatter().string(from: Date())
        try dbQueue.write { db in
            for (eventId, count) in counts {
                try db.execute(
                    sql: """
                    INSERT INTO nostr_comment_counts (event_id_hex, count, cached_at)
                    VALUES (?, ?, ?)
                    ON CONFLICT (event_id_hex) DO UPDATE SET
                        count     = excluded.count,
                        cached_at = excluded.cached_at
                    """,
                    arguments: [eventId, count, now]
                )
            }
        }
    }

    /// Fetch cached comment counts for a list of event IDs.
    func fetchCommentCounts(eventIds: [String]) throws -> [String: Int] {
        guard !eventIds.isEmpty else { return [:] }
        return try dbQueue.read { db in
            let placeholders = Array(repeating: "?", count: eventIds.count).joined(separator: ", ")
            let rows = try Row.fetchAll(db,
                sql: "SELECT event_id_hex, count FROM nostr_comment_counts WHERE event_id_hex IN (\(placeholders))",
                arguments: StatementArguments(eventIds))
            var result: [String: Int] = [:]
            for row in rows {
                result[row["event_id_hex"]] = row["count"]
            }
            return result
        }
    }

    // MARK: - Cleanup

    /// Delete all cached counts (called on sign-out).
    func deleteAll() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM nostr_reaction_counts")
            try db.execute(sql: "DELETE FROM nostr_comment_counts")
        }
    }
}
