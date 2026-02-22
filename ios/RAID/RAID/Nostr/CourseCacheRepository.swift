// CourseCacheRepository.swift
// RAID Golf
//
// Persistent cache for Nostr course data (kind 33501 events).
// Backed by nostr_courses table (v15 migration). Mutable, no immutability triggers.
// Courses are upserted on each relay fetch — always reflects the latest data.

import Foundation
import GRDB

class CourseCacheRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// Batch upsert parsed courses into the cache.
    func upsertCourses(_ courses: [ParsedCourse]) throws {
        let now = ISO8601DateFormatter().string(from: Date())
        let encoder = JSONEncoder()

        try dbQueue.write { db in
            for course in courses {
                let holesJSON = (try? encoder.encode(course.holes))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
                let teesJSON = (try? encoder.encode(course.tees))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
                let yardagesJSON: String? = course.yardages.isEmpty ? nil :
                    (try? encoder.encode(course.yardages))
                        .flatMap { String(data: $0, encoding: .utf8) }

                try db.execute(
                    sql: """
                    INSERT INTO nostr_courses
                        (d_tag, author_hex, title, location, country, hole_count,
                         holes_json, tees_json, yardages_json, content, website,
                         architect, established, operator_pubkey, event_id_hex,
                         event_created_at, raw_json, cached_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT (d_tag, author_hex) DO UPDATE SET
                        title = excluded.title,
                        location = excluded.location,
                        country = excluded.country,
                        hole_count = excluded.hole_count,
                        holes_json = excluded.holes_json,
                        tees_json = excluded.tees_json,
                        yardages_json = excluded.yardages_json,
                        content = excluded.content,
                        website = excluded.website,
                        architect = excluded.architect,
                        established = excluded.established,
                        operator_pubkey = excluded.operator_pubkey,
                        event_id_hex = excluded.event_id_hex,
                        event_created_at = excluded.event_created_at,
                        raw_json = excluded.raw_json,
                        cached_at = excluded.cached_at
                    """,
                    arguments: [
                        course.dTag,
                        course.authorHex,
                        course.title,
                        course.location,
                        course.country,
                        course.holes.count,
                        holesJSON,
                        teesJSON,
                        yardagesJSON,
                        course.content,
                        course.website,
                        course.architect,
                        course.established,
                        course.operatorPubkey,
                        course.eventId,
                        course.eventCreatedAt,
                        course.eventId, // raw_json placeholder — will be replaced with actual event JSON
                        now
                    ]
                )
            }
        }
    }

    /// Upsert courses with raw event JSON for replay.
    func upsertCourses(_ courses: [ParsedCourse], rawJSONs: [String: String]) throws {
        let now = ISO8601DateFormatter().string(from: Date())
        let encoder = JSONEncoder()

        try dbQueue.write { db in
            for course in courses {
                let holesJSON = (try? encoder.encode(course.holes))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
                let teesJSON = (try? encoder.encode(course.tees))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
                let yardagesJSON: String? = course.yardages.isEmpty ? nil :
                    (try? encoder.encode(course.yardages))
                        .flatMap { String(data: $0, encoding: .utf8) }
                let rawJSON = rawJSONs[course.dTag] ?? "{}"

                try db.execute(
                    sql: """
                    INSERT INTO nostr_courses
                        (d_tag, author_hex, title, location, country, hole_count,
                         holes_json, tees_json, yardages_json, content, website,
                         architect, established, operator_pubkey, event_id_hex,
                         event_created_at, raw_json, cached_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT (d_tag, author_hex) DO UPDATE SET
                        title = excluded.title,
                        location = excluded.location,
                        country = excluded.country,
                        hole_count = excluded.hole_count,
                        holes_json = excluded.holes_json,
                        tees_json = excluded.tees_json,
                        yardages_json = excluded.yardages_json,
                        content = excluded.content,
                        website = excluded.website,
                        architect = excluded.architect,
                        established = excluded.established,
                        operator_pubkey = excluded.operator_pubkey,
                        event_id_hex = excluded.event_id_hex,
                        event_created_at = excluded.event_created_at,
                        raw_json = excluded.raw_json,
                        cached_at = excluded.cached_at
                    """,
                    arguments: [
                        course.dTag,
                        course.authorHex,
                        course.title,
                        course.location,
                        course.country,
                        course.holes.count,
                        holesJSON,
                        teesJSON,
                        yardagesJSON,
                        course.content,
                        course.website,
                        course.architect,
                        course.established,
                        course.operatorPubkey,
                        course.eventId,
                        course.eventCreatedAt,
                        rawJSON,
                        now
                    ]
                )
            }
        }
    }

    /// Fetch all cached courses, ordered by title.
    func fetchAllCourses() throws -> [ParsedCourse] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM nostr_courses ORDER BY title COLLATE NOCASE
                """)
            return rows.compactMap { decodeRow($0) }
        }
    }

    /// Search courses by title or location (case-insensitive).
    func searchCourses(query: String, limit: Int = 50) -> [ParsedCourse] {
        let pattern = "%\(query)%"
        do {
            return try dbQueue.read { db in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT * FROM nostr_courses
                    WHERE title LIKE ? OR location LIKE ?
                    ORDER BY title COLLATE NOCASE
                    LIMIT ?
                    """, arguments: [pattern, pattern, limit])
                return rows.compactMap { decodeRow($0) }
            }
        } catch {
            return []
        }
    }

    /// Fetch a single course by d-tag and author.
    func fetchCourse(dTag: String, authorHex: String) -> ParsedCourse? {
        do {
            return try dbQueue.read { db in
                let row = try Row.fetchOne(db, sql: """
                    SELECT * FROM nostr_courses WHERE d_tag = ? AND author_hex = ?
                    """, arguments: [dTag, authorHex])
                return row.flatMap { decodeRow($0) }
            }
        } catch {
            return nil
        }
    }

    /// Delete all cached courses.
    func deleteAll() throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM nostr_courses")
        }
    }

    // MARK: - Private

    private func decodeRow(_ row: Row) -> ParsedCourse? {
        let decoder = JSONDecoder()

        guard let dTag = row["d_tag"] as? String,
              let authorHex = row["author_hex"] as? String,
              let title = row["title"] as? String,
              let location = row["location"] as? String,
              let holesJSON = row["holes_json"] as? String,
              let teesJSON = row["tees_json"] as? String,
              let eventId = row["event_id_hex"] as? String,
              let eventCreatedAt = row["event_created_at"] as? Int64
        else { return nil }

        guard let holesData = holesJSON.data(using: .utf8),
              let holes = try? decoder.decode([ParsedCourse.ParsedHole].self, from: holesData),
              let teesData = teesJSON.data(using: .utf8),
              let tees = try? decoder.decode([ParsedCourse.ParsedTee].self, from: teesData)
        else { return nil }

        var yardages: [ParsedCourse.ParsedYardage] = []
        if let yardagesJSON = row["yardages_json"] as? String,
           let yardagesData = yardagesJSON.data(using: .utf8),
           let decoded = try? decoder.decode([ParsedCourse.ParsedYardage].self, from: yardagesData) {
            yardages = decoded
        }

        return ParsedCourse(
            dTag: dTag,
            authorHex: authorHex,
            title: title,
            location: location,
            country: row["country"] as? String,
            holes: holes,
            tees: tees,
            yardages: yardages,
            content: row["content"] as? String,
            website: row["website"] as? String,
            architect: row["architect"] as? String,
            established: row["established"] as? String,
            operatorPubkey: row["operator_pubkey"] as? String,
            eventId: eventId,
            eventCreatedAt: UInt64(eventCreatedAt)
        )
    }
}
