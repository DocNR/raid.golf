// FollowListCacheRepository.swift
// RAID Golf
//
// Persistent cache for the user's Nostr follow list (NIP-02 kind 3).
// Backed by nostr_follow_lists table (v12 migration). Mutable, no triggers.
// TTL: 1 hour. Stale entries fall through to relay fetch in FeedViewModel.

import Foundation
import GRDB

/// A cached copy of a user's kind 3 follow list.
struct CachedFollowList {
    let pubkeyHex: String
    let follows: [String]         // hex pubkeys the user follows
    let eventCreatedAt: UInt64    // created_at of the kind 3 event
    let cachedAt: Date
}

class FollowListCacheRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// Upsert a follow list. Overwrites all fields on conflict.
    func upsert(_ list: CachedFollowList) throws {
        let cachedAtString = ISO8601DateFormatter().string(from: list.cachedAt)
        let json = try JSONEncoder().encode(list.follows)
        let jsonString = String(data: json, encoding: .utf8)!
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO nostr_follow_lists (pubkey_hex, follows_json, event_created_at, cached_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT (pubkey_hex) DO UPDATE SET
                    follows_json      = excluded.follows_json,
                    event_created_at  = excluded.event_created_at,
                    cached_at         = excluded.cached_at
                """,
                arguments: [list.pubkeyHex, jsonString, list.eventCreatedAt, cachedAtString]
            )
        }
    }

    /// Fetch cached follow list for a pubkey. Returns nil if not cached.
    func fetch(pubkeyHex: String) throws -> CachedFollowList? {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db,
                sql: "SELECT * FROM nostr_follow_lists WHERE pubkey_hex = ? LIMIT 1",
                arguments: [pubkeyHex])
            return try rows.first.map { row -> CachedFollowList in
                let jsonString: String = row["follows_json"]
                let follows = try JSONDecoder().decode([String].self, from: Data(jsonString.utf8))
                let cachedAtString: String = row["cached_at"]
                let cachedAt = ISO8601DateFormatter().date(from: cachedAtString) ?? Date()
                let eventCreatedAt: Int64 = row["event_created_at"]
                return CachedFollowList(
                    pubkeyHex: row["pubkey_hex"],
                    follows: follows,
                    eventCreatedAt: UInt64(eventCreatedAt),
                    cachedAt: cachedAt
                )
            }
        }
    }

    /// Convenience: update the local cache after publishing a new kind 3.
    /// Uses the current timestamp for both `eventCreatedAt` and `cachedAt`.
    func updateLocalFollowList(pubkeyHex: String, follows: [String]) throws {
        let now = UInt64(Date().timeIntervalSince1970)
        try upsert(CachedFollowList(
            pubkeyHex: pubkeyHex,
            follows: follows,
            eventCreatedAt: now,
            cachedAt: Date()
        ))
    }

    /// Check whether `ownerPubkeyHex` follows `targetPubkeyHex` in the local cache.
    func isFollowing(ownerPubkeyHex: String, targetPubkeyHex: String) throws -> Bool {
        guard let list = try fetch(pubkeyHex: ownerPubkeyHex) else { return false }
        return list.follows.contains(targetPubkeyHex)
    }

    /// Delete all cached follow lists (called on sign-out).
    func deleteAll() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM nostr_follow_lists")
        }
    }
}
