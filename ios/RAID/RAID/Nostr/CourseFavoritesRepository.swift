// CourseFavoritesRepository.swift
// RAID Golf
//
// Local cache for the user's saved course list ("My Courses").
// Backed by course_favorites table (v17 migration). Mutable, no triggers.
// Synced to/from NIP-51 kind 30000 follow set (d="raid-golf-courses").

import Foundation
import GRDB

struct CourseFavorite {
    let dTag: String
    let authorHex: String
    let addedAt: String
}

class CourseFavoritesRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// All favorites ordered by added_at.
    func fetchAll() throws -> [CourseFavorite] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db,
                sql: "SELECT d_tag, author_hex, added_at FROM course_favorites ORDER BY added_at ASC")
            return rows.map {
                CourseFavorite(dTag: $0["d_tag"], authorHex: $0["author_hex"], addedAt: $0["added_at"])
            }
        }
    }

    /// All favorite identifiers as (dTag, authorHex) tuples.
    func allIdentifiers() throws -> [(dTag: String, authorHex: String)] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db,
                sql: "SELECT d_tag, author_hex FROM course_favorites ORDER BY added_at ASC")
            return rows.map { (dTag: $0["d_tag"] as String, authorHex: $0["author_hex"] as String) }
        }
    }

    /// Check if a course is in favorites.
    func isFavorite(dTag: String, authorHex: String) throws -> Bool {
        try dbQueue.read { db in
            let count = try Int.fetchOne(db,
                sql: "SELECT COUNT(*) FROM course_favorites WHERE d_tag = ? AND author_hex = ?",
                arguments: [dTag, authorHex])
            return (count ?? 0) > 0
        }
    }

    /// Add a course to favorites. No-op if already present (INSERT OR IGNORE).
    func add(dTag: String, authorHex: String) throws {
        let now = ISO8601DateFormatter().string(from: Date())
        try dbQueue.write { db in
            try db.execute(
                sql: "INSERT OR IGNORE INTO course_favorites (d_tag, author_hex, added_at) VALUES (?, ?, ?)",
                arguments: [dTag, authorHex, now])
        }
    }

    /// Remove a course from favorites.
    func remove(dTag: String, authorHex: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM course_favorites WHERE d_tag = ? AND author_hex = ?",
                arguments: [dTag, authorHex])
        }
    }

    /// Replace all favorites in a single transaction. Used for NIP-51 import.
    func replaceAll(identifiers: [(dTag: String, authorHex: String)]) throws {
        let now = ISO8601DateFormatter().string(from: Date())
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM course_favorites")
            for id in identifiers {
                try db.execute(
                    sql: "INSERT INTO course_favorites (d_tag, author_hex, added_at) VALUES (?, ?, ?)",
                    arguments: [id.dTag, id.authorHex, now])
            }
        }
    }

    /// Number of favorites.
    func count() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM course_favorites") ?? 0
        }
    }

    /// Whether the favorites list is empty.
    func isEmpty() throws -> Bool {
        try count() == 0
    }
}
