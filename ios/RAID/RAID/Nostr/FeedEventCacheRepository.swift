// FeedEventCacheRepository.swift
// RAID Golf
//
// Persistent cache for Nostr feed events (kind 1, 1501, 1502).
// Backed by nostr_feed_events table (v13 migration). Mutable, no triggers.
// No TTL — pruned by count (keepCount: 200 newest by created_at).

import Foundation
import GRDB
import NostrSDK

class FeedEventCacheRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// Batch upsert events. Overwrites raw_json + fetched_at on conflict.
    /// Skips any event whose JSON serialization fails.
    func upsertEvents(_ events: [Event]) throws {
        guard !events.isEmpty else { return }
        let now = ISO8601DateFormatter().string(from: Date())
        let encoder = JSONEncoder()
        try dbQueue.write { db in
            for event in events {
                guard let rawJson = try? event.asJson() else { continue }
                let idHex = event.id().toHex()
                let pubkeyHex = event.author().toHex()
                let kind = Int64(event.kind().asU16())
                let createdAt = Int64(event.createdAt().asSecs())
                let content = event.content()
                let tagsVec = event.tags().toVec().map { $0.asVec() }
                let tagsData = (try? encoder.encode(tagsVec)) ?? Data("[]".utf8)
                let tagsJson = String(data: tagsData, encoding: .utf8) ?? "[]"
                try db.execute(
                    sql: """
                    INSERT INTO nostr_feed_events
                        (event_id_hex, pubkey_hex, kind, created_at, content, tags_json, raw_json, fetched_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT (event_id_hex) DO UPDATE SET
                        raw_json   = excluded.raw_json,
                        fetched_at = excluded.fetched_at
                    """,
                    arguments: [idHex, pubkeyHex, kind, createdAt, content, tagsJson, rawJson, now]
                )
            }
        }
    }

    /// Fetch most recent N events ordered by created_at DESC.
    func fetchRecentEvents(limit: Int) throws -> [Event] {
        let rows = try dbQueue.read { db in
            try Row.fetchAll(db,
                sql: "SELECT raw_json FROM nostr_feed_events ORDER BY created_at DESC LIMIT ?",
                arguments: [limit])
        }
        return rows.compactMap { row in
            let json: String = row["raw_json"]
            return try? Event.fromJson(json: json)
        }
    }

    /// Fetch a single event by hex event ID. Returns nil if not cached.
    func fetchEvent(idHex: String) throws -> Event? {
        let rows = try dbQueue.read { db in
            try Row.fetchAll(db,
                sql: "SELECT raw_json FROM nostr_feed_events WHERE event_id_hex = ? LIMIT 1",
                arguments: [idHex])
        }
        guard let row = rows.first else { return nil }
        let json: String = row["raw_json"]
        return try? Event.fromJson(json: json)
    }

    /// Delete all but the newest `keepCount` events (by created_at DESC).
    func pruneOldEvents(keepCount: Int) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                DELETE FROM nostr_feed_events
                WHERE event_id_hex NOT IN (
                    SELECT event_id_hex FROM nostr_feed_events
                    ORDER BY created_at DESC
                    LIMIT ?
                )
                """,
                arguments: [keepCount]
            )
        }
    }

    /// Delete all cached feed events (called on sign-out).
    func deleteAll() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM nostr_feed_events")
        }
    }
}
