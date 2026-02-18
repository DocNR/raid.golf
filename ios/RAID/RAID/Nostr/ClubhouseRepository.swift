// ClubhouseRepository.swift
// RAID Golf
//
// Local cache for the user's curated Clubhouse player list.
// Backed by clubhouse_members table (v10 migration). Mutable, no triggers.
// Synced to/from NIP-51 kind 30000 follow set (d="clubhouse").

import Foundation
import GRDB

struct ClubhouseMember {
    let pubkeyHex: String
    let addedAt: String
}

class ClubhouseRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// All members ordered by added_at.
    func fetchAll() throws -> [ClubhouseMember] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db,
                sql: "SELECT pubkey_hex, added_at FROM clubhouse_members ORDER BY added_at ASC")
            return rows.map {
                ClubhouseMember(pubkeyHex: $0["pubkey_hex"], addedAt: $0["added_at"])
            }
        }
    }

    /// All member pubkey hexes (ordered by added_at).
    func allPubkeyHexes() throws -> [String] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db,
                sql: "SELECT pubkey_hex FROM clubhouse_members ORDER BY added_at ASC")
            return rows.map { $0["pubkey_hex"] as String }
        }
    }

    /// Check if a pubkey is in the Clubhouse.
    func isMember(pubkeyHex: String) throws -> Bool {
        try dbQueue.read { db in
            let count = try Int.fetchOne(db,
                sql: "SELECT COUNT(*) FROM clubhouse_members WHERE pubkey_hex = ?",
                arguments: [pubkeyHex])
            return (count ?? 0) > 0
        }
    }

    /// Add a member. No-op if already present (INSERT OR IGNORE).
    func add(pubkeyHex: String) throws {
        let now = ISO8601DateFormatter().string(from: Date())
        try dbQueue.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO clubhouse_members (pubkey_hex, added_at) VALUES (?, ?)",
                arguments: [pubkeyHex, now])
        }
    }

    /// Remove a member by pubkey hex.
    func remove(pubkeyHex: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM clubhouse_members WHERE pubkey_hex = ?",
                arguments: [pubkeyHex])
        }
    }

    /// Replace all members in a single transaction. Used for NIP-51 import.
    func replaceAll(pubkeyHexes: [String]) throws {
        let now = ISO8601DateFormatter().string(from: Date())
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM clubhouse_members")
            for hex in pubkeyHexes {
                try db.execute(
                    sql: "INSERT INTO clubhouse_members (pubkey_hex, added_at) VALUES (?, ?)",
                    arguments: [hex, now])
            }
        }
    }

    /// Number of members.
    func count() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM clubhouse_members") ?? 0
        }
    }

    /// Whether the table has any members.
    func isEmpty() throws -> Bool {
        try count() == 0
    }
}
