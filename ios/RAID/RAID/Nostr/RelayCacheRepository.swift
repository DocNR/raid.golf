// RelayCacheRepository.swift
// RAID Golf
//
// Persistent cache for Nostr relay list metadata (NIP-65 kind 10002 events).
// Backed by nostr_relay_lists table (v11 migration). Mutable, no immutability triggers.
// Relay lists are upserted on each fetch — always reflects the latest relay data.

import Foundation
import GRDB

/// A single relay entry from a NIP-65 kind 10002 relay list.
struct CachedRelayEntry: Codable, Equatable {
    let url: String
    let marker: String?  // nil = both, "read", "write"

    /// Whether this relay accepts writes (marker is nil or "write").
    var isWrite: Bool { marker == nil || marker == "write" }

    /// Whether this relay serves reads (marker is nil or "read").
    var isRead: Bool { marker == nil || marker == "read" }
}

/// A user's complete NIP-65 relay list, cached locally.
struct CachedRelayList: Equatable {
    let pubkeyHex: String
    let relays: [CachedRelayEntry]
    let cachedAt: Date

    /// Relays the user writes to (marker is nil or "write").
    var writeRelays: [CachedRelayEntry] { relays.filter(\.isWrite) }

    /// Relays the user reads from (marker is nil or "read").
    var readRelays: [CachedRelayEntry] { relays.filter(\.isRead) }
}

class RelayCacheRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// Upsert a single relay list. Updates all fields on conflict.
    func upsertRelayList(_ list: CachedRelayList) throws {
        let now = ISO8601DateFormatter().string(from: Date())
        let json = try JSONEncoder().encode(list.relays)
        let jsonString = String(data: json, encoding: .utf8)!
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO nostr_relay_lists (pubkey_hex, relay_json, cached_at)
                VALUES (?, ?, ?)
                ON CONFLICT (pubkey_hex) DO UPDATE SET
                    relay_json = excluded.relay_json,
                    cached_at = excluded.cached_at
                """,
                arguments: [list.pubkeyHex, jsonString, now]
            )
        }
    }

    /// Batch upsert. Wraps all inserts in one write transaction.
    func upsertRelayLists(_ lists: [CachedRelayList]) throws {
        guard !lists.isEmpty else { return }
        let now = ISO8601DateFormatter().string(from: Date())
        let encoder = JSONEncoder()
        try dbQueue.write { db in
            for list in lists {
                let json = try encoder.encode(list.relays)
                let jsonString = String(data: json, encoding: .utf8)!
                try db.execute(
                    sql: """
                    INSERT INTO nostr_relay_lists (pubkey_hex, relay_json, cached_at)
                    VALUES (?, ?, ?)
                    ON CONFLICT (pubkey_hex) DO UPDATE SET
                        relay_json = excluded.relay_json,
                        cached_at = excluded.cached_at
                    """,
                    arguments: [list.pubkeyHex, jsonString, now]
                )
            }
        }
    }

    /// Fetch one relay list by pubkey hex. Returns nil if not cached.
    func fetchRelayList(pubkeyHex: String) throws -> CachedRelayList? {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db,
                sql: "SELECT * FROM nostr_relay_lists WHERE pubkey_hex = ? LIMIT 1",
                arguments: [pubkeyHex])
            return try rows.first.map { try self.rowToRelayList($0) }
        }
    }

    /// Batch fetch relay lists by pubkey hexes. Returns dict keyed by pubkeyHex.
    func fetchRelayLists(pubkeyHexes: [String]) throws -> [String: CachedRelayList] {
        guard !pubkeyHexes.isEmpty else { return [:] }
        return try dbQueue.read { db in
            let placeholders = databaseQuestionMarks(count: pubkeyHexes.count)
            let rows = try Row.fetchAll(db,
                sql: "SELECT * FROM nostr_relay_lists WHERE pubkey_hex IN (\(placeholders))",
                arguments: StatementArguments(pubkeyHexes))
            var result: [String: CachedRelayList] = [:]
            for row in rows {
                let list = try self.rowToRelayList(row)
                result[list.pubkeyHex] = list
            }
            return result
        }
    }

    /// Convenience: return only write relays for a pubkey. Empty if not cached.
    func writeRelays(forPubkey pubkeyHex: String) throws -> [CachedRelayEntry] {
        guard let list = try fetchRelayList(pubkeyHex: pubkeyHex) else { return [] }
        return list.writeRelays
    }

    /// Delete a single relay list entry.
    func delete(pubkeyHex: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM nostr_relay_lists WHERE pubkey_hex = ?",
                arguments: [pubkeyHex])
        }
    }

    /// Delete all cached relay lists.
    func deleteAll() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM nostr_relay_lists")
        }
    }

    // MARK: - Private

    private func rowToRelayList(_ row: Row) throws -> CachedRelayList {
        let jsonString: String = row["relay_json"]
        let relays = try JSONDecoder().decode(
            [CachedRelayEntry].self,
            from: Data(jsonString.utf8)
        )
        let cachedAtString: String = row["cached_at"]
        let cachedAt = ISO8601DateFormatter().date(from: cachedAtString) ?? Date()
        return CachedRelayList(
            pubkeyHex: row["pubkey_hex"],
            relays: relays,
            cachedAt: cachedAt
        )
    }
}

/// Build a comma-separated string of `?` placeholders for SQL IN clauses.
private func databaseQuestionMarks(count: Int) -> String {
    Array(repeating: "?", count: count).joined(separator: ", ")
}
