// ScorecardRepository.swift
// Gambit Golf
//
// Storage boundary for the scorecard domain (kernel-adjacent).
//
// CourseSnapshotRepository: content-addressed insert (canonicalize + hash once)
// RoundRepository: round lifecycle (create + complete via events)
// HoleScoreRepository: append-only scores with latest-wins corrections
// RoundPlayerRepository: immutable player roster per round (Phase 6C)
// RoundNostrRepository: Nostr initiation event ID per round (Phase 6C)
//
// Invariants:
// - Hash computed ONLY on insert, never on read (RTM-04 equivalent)
// - All inserts are append-only; no UPDATE/DELETE
// - Completion is an event row, not a status UPDATE

import Foundation
import GRDB

// MARK: - Errors

enum CourseSnapshotError: Error {
    case invalidHoleCount(expected: Int, actual: Int)
    case invalidHoleSet(holeNumbers: [Int])
    case utf8EncodingFailed
}

// MARK: - Course Snapshot Repository

class CourseSnapshotRepository {
    private let dbQueue: DatabaseQueue
    private let canonicalizer: Canonicalizing
    private let hasher: Hashing

    init(dbQueue: DatabaseQueue,
         canonicalizer: Canonicalizing = RAIDCanonicalizer(),
         hasher: Hashing = RAIDHasher()) {
        self.dbQueue = dbQueue
        self.canonicalizer = canonicalizer
        self.hasher = hasher
    }

    /// Insert a course snapshot. Canonicalizes + hashes once.
    /// Idempotent: duplicate hashes silently return existing record.
    /// Also inserts course_holes rows in the same transaction.
    func insertCourseSnapshot(_ input: CourseSnapshotInput) throws -> CourseSnapshotRecord {
        let holeCount = input.holes.count

        // Validate hole count (9 or 18)
        guard holeCount == 9 || holeCount == 18 else {
            throw CourseSnapshotError.invalidHoleCount(expected: 9, actual: holeCount)
        }

        // Validate hole numbers form a valid set (front 9, back 9, or full 18)
        let holeNumbers = Set(input.holes.map(\.holeNumber))
        let validSets: [Set<Int>] = [Set(1...9), Set(10...18), Set(1...18)]
        guard holeNumbers.count == holeCount && validSets.contains(holeNumbers) else {
            throw CourseSnapshotError.invalidHoleSet(holeNumbers: input.holes.map(\.holeNumber).sorted())
        }

        // Build NIP-aligned JSON dict with frozen keys
        let holesArray: [[String: Any]] = input.holes.map { hole in
            [
                "handicap_index": NSNull(),
                "hole_number": hole.holeNumber,
                "par": hole.par
            ]
        }

        let jsonDict: [String: Any] = [
            "course_name": input.courseName,
            "hole_count": holeCount,
            "holes": holesArray,
            "tee_set": input.teeSet
        ]

        let rawJSON = try JSONSerialization.data(withJSONObject: jsonDict)

        // Canonicalize + hash (called ONLY here)
        let canonicalData = try canonicalizer.canonicalize(rawJSON)
        let hash = hasher.sha256Hex(canonicalData)

        guard let canonicalString = String(data: canonicalData, encoding: .utf8) else {
            throw CourseSnapshotError.utf8EncodingFailed
        }

        let now = ISO8601DateFormatter().string(from: Date())

        // Insert snapshot + holes in one transaction
        try dbQueue.write { db in
            // INSERT OR IGNORE for idempotent re-insert
            try db.execute(
                sql: """
                INSERT OR IGNORE INTO course_snapshots (course_hash, course_name, tee_set, hole_count, canonical_json, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [hash, input.courseName, input.teeSet, holeCount, canonicalString, now]
            )

            // Insert course_holes (also OR IGNORE for idempotency)
            for hole in input.holes {
                try db.execute(
                    sql: """
                    INSERT OR IGNORE INTO course_holes (course_hash, hole_number, par, handicap_index)
                    VALUES (?, ?, ?, ?)
                    """,
                    arguments: [hash, hole.holeNumber, hole.par, nil as Int?]
                )
            }
        }

        // Return the record (may have been pre-existing if OR IGNORE hit)
        guard let record = try fetchCourseSnapshot(byHash: hash) else {
            // Should never happen: we just inserted or it already existed
            fatalError("Course snapshot not found after insert: \(hash)")
        }
        return record
    }

    /// Fetch a course snapshot by its stored hash.
    /// Read path: returns stored hash + canonical_json directly, never recomputes.
    func fetchCourseSnapshot(byHash hash: String) throws -> CourseSnapshotRecord? {
        return try dbQueue.read { db in
            guard let row = try Row.fetchOne(db,
                sql: "SELECT * FROM course_snapshots WHERE course_hash = ?",
                arguments: [hash]) else {
                return nil
            }

            return CourseSnapshotRecord(
                courseHash: row["course_hash"],
                courseName: row["course_name"],
                teeSet: row["tee_set"],
                holeCount: row["hole_count"],
                canonicalJSON: row["canonical_json"],
                createdAt: row["created_at"]
            )
        }
    }

    /// Fetch normalized hole definitions for a course snapshot.
    func fetchHoles(forCourse hash: String) throws -> [CourseHoleRecord] {
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db,
                sql: """
                SELECT course_hash, hole_number, par, handicap_index
                FROM course_holes
                WHERE course_hash = ?
                ORDER BY hole_number ASC
                """,
                arguments: [hash])

            return rows.map { row in
                CourseHoleRecord(
                    courseHash: row["course_hash"],
                    holeNumber: row["hole_number"],
                    par: row["par"],
                    handicapIndex: row["handicap_index"]
                )
            }
        }
    }
}

// MARK: - Round Repository

class RoundRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// Create a new round (immutable row).
    func createRound(courseHash: String, roundDate: String) throws -> RoundRecord {
        let now = ISO8601DateFormatter().string(from: Date())

        let roundId = try dbQueue.write { db -> Int64 in
            try db.execute(
                sql: """
                INSERT INTO rounds (course_hash, round_date, created_at)
                VALUES (?, ?, ?)
                """,
                arguments: [courseHash, roundDate, now]
            )
            return db.lastInsertedRowID
        }

        return RoundRecord(
            roundId: roundId,
            courseHash: courseHash,
            roundDate: roundDate,
            createdAt: now
        )
    }

    /// Complete a round by inserting a completion event.
    /// UNIQUE constraint on (round_id, event_type) prevents double-completion.
    func completeRound(roundId: Int64) throws {
        let now = ISO8601DateFormatter().string(from: Date())

        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO round_events (round_id, event_type, recorded_at)
                VALUES (?, 'completed', ?)
                """,
                arguments: [roundId, now]
            )
        }
    }

    /// Check if a round has been completed (derived from round_events).
    func isCompleted(roundId: Int64) throws -> Bool {
        return try dbQueue.read { db in
            let count = try Int.fetchOne(db,
                sql: """
                SELECT COUNT(*) FROM round_events
                WHERE round_id = ? AND event_type = 'completed'
                """,
                arguments: [roundId]) ?? 0
            return count > 0
        }
    }

    /// List all rounds with course info, completion status, and scoring totals.
    /// Single joined query (no N+1). ORDER BY round_date DESC, round_id DESC.
    func listRounds() throws -> [RoundListItem] {
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT
                    r.round_id,
                    cs.course_name,
                    cs.tee_set,
                    r.round_date,
                    cs.hole_count,
                    (SELECT COUNT(*) FROM round_events re
                     WHERE re.round_id = r.round_id AND re.event_type = 'completed') AS is_completed,
                    (SELECT SUM(latest.strokes)
                     FROM (
                         SELECT hs.hole_number, hs.strokes
                         FROM hole_scores hs
                         WHERE hs.round_id = r.round_id AND hs.player_index = 0
                         GROUP BY hs.hole_number
                         HAVING hs.recorded_at = MAX(hs.recorded_at)
                            AND hs.score_id = MAX(hs.score_id)
                     ) latest
                    ) AS total_strokes,
                    (SELECT COUNT(DISTINCT hs2.hole_number)
                     FROM hole_scores hs2
                     WHERE hs2.round_id = r.round_id AND hs2.player_index = 0
                    ) AS holes_scored
                FROM rounds r
                INNER JOIN course_snapshots cs ON cs.course_hash = r.course_hash
                ORDER BY r.round_date DESC, r.round_id DESC
                """)

            return rows.map { row in
                RoundListItem(
                    roundId: row["round_id"],
                    courseName: row["course_name"],
                    teeSet: row["tee_set"],
                    roundDate: row["round_date"],
                    holeCount: row["hole_count"],
                    isCompleted: (row["is_completed"] as Int) > 0,
                    totalStrokes: row["total_strokes"],
                    holesScored: row["holes_scored"]
                )
            }
        }
    }

    /// Total round count (for empty-state checks).
    func roundCount() throws -> Int {
        return try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM rounds") ?? 0
        }
    }
}

// MARK: - Hole Score Repository

class HoleScoreRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// Record a score for a hole (append-only).
    /// Corrections are new inserts; the latest by recorded_at wins.
    /// playerIndex defaults to 0 (creator) for backward compat.
    func recordScore(roundId: Int64, playerIndex: Int = 0, score: HoleScoreInput) throws -> HoleScoreRecord {
        let now = ISO8601DateFormatter().string(from: Date())

        let scoreId = try dbQueue.write { db -> Int64 in
            try db.execute(
                sql: """
                INSERT INTO hole_scores (round_id, player_index, hole_number, strokes, recorded_at)
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [roundId, playerIndex, score.holeNumber, score.strokes, now]
            )
            return db.lastInsertedRowID
        }

        return HoleScoreRecord(
            scoreId: scoreId,
            roundId: roundId,
            playerIndex: playerIndex,
            holeNumber: score.holeNumber,
            strokes: score.strokes,
            recordedAt: now
        )
    }

    /// Fetch latest scores for a specific player in a round (latest-wins resolved).
    /// Deterministic: MAX(recorded_at), tie-break MAX(score_id).
    /// playerIndex defaults to 0 (creator) for backward compat.
    func fetchLatestScores(forRound roundId: Int64, playerIndex: Int = 0) throws -> [HoleScoreRecord] {
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db,
                sql: """
                SELECT hs.score_id, hs.round_id, hs.player_index, hs.hole_number, hs.strokes, hs.recorded_at
                FROM hole_scores hs
                INNER JOIN (
                    SELECT hole_number, MAX(recorded_at) AS max_ra, MAX(score_id) AS max_id
                    FROM hole_scores
                    WHERE round_id = ? AND player_index = ?
                    GROUP BY hole_number
                ) latest ON hs.hole_number = latest.hole_number
                       AND hs.recorded_at = latest.max_ra
                       AND hs.score_id = latest.max_id
                WHERE hs.round_id = ? AND hs.player_index = ?
                ORDER BY hs.hole_number ASC
                """,
                arguments: [roundId, playerIndex, roundId, playerIndex])

            return rows.map { row in
                HoleScoreRecord(
                    scoreId: row["score_id"],
                    roundId: row["round_id"],
                    playerIndex: row["player_index"],
                    holeNumber: row["hole_number"],
                    strokes: row["strokes"],
                    recordedAt: row["recorded_at"]
                )
            }
        }
    }

    /// Fetch latest scores for ALL players in a round, grouped by player_index.
    /// Returns playerIndex -> [HoleScoreRecord] dictionary.
    func fetchAllPlayersLatestScores(forRound roundId: Int64) throws -> [Int: [HoleScoreRecord]] {
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db,
                sql: """
                SELECT hs.score_id, hs.round_id, hs.player_index, hs.hole_number, hs.strokes, hs.recorded_at
                FROM hole_scores hs
                INNER JOIN (
                    SELECT player_index, hole_number, MAX(recorded_at) AS max_ra, MAX(score_id) AS max_id
                    FROM hole_scores
                    WHERE round_id = ?
                    GROUP BY player_index, hole_number
                ) latest ON hs.player_index = latest.player_index
                       AND hs.hole_number = latest.hole_number
                       AND hs.recorded_at = latest.max_ra
                       AND hs.score_id = latest.max_id
                WHERE hs.round_id = ?
                ORDER BY hs.player_index ASC, hs.hole_number ASC
                """,
                arguments: [roundId, roundId])

            var result: [Int: [HoleScoreRecord]] = [:]
            for row in rows {
                let record = HoleScoreRecord(
                    scoreId: row["score_id"],
                    roundId: row["round_id"],
                    playerIndex: row["player_index"],
                    holeNumber: row["hole_number"],
                    strokes: row["strokes"],
                    recordedAt: row["recorded_at"]
                )
                result[record.playerIndex, default: []].append(record)
            }
            return result
        }
    }
}

// MARK: - Round Player Repository

class RoundPlayerRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// Insert players for a round in a single transaction.
    /// Creator gets player_index 0; others get 1, 2, ... in order provided.
    func insertPlayers(roundId: Int64, creatorPubkey: String, otherPubkeys: [String]) throws {
        let now = ISO8601DateFormatter().string(from: Date())

        try dbQueue.write { db in
            // Creator is always player_index 0
            try db.execute(
                sql: """
                INSERT OR IGNORE INTO round_players (round_id, player_pubkey, player_index, added_at)
                VALUES (?, ?, 0, ?)
                """,
                arguments: [roundId, creatorPubkey, now]
            )

            // Other players get sequential indices starting at 1
            for (offset, pubkey) in otherPubkeys.enumerated() {
                try db.execute(
                    sql: """
                    INSERT OR IGNORE INTO round_players (round_id, player_pubkey, player_index, added_at)
                    VALUES (?, ?, ?, ?)
                    """,
                    arguments: [roundId, pubkey, offset + 1, now]
                )
            }
        }
    }

    /// Fetch all player pubkeys for a round, ordered by player_index.
    /// Returns hex pubkey strings suitable for NIP-101g p tags.
    func fetchPlayerPubkeys(forRound roundId: Int64) throws -> [String] {
        return try dbQueue.read { db in
            try String.fetchAll(db,
                sql: """
                SELECT player_pubkey FROM round_players
                WHERE round_id = ?
                ORDER BY player_index ASC
                """,
                arguments: [roundId])
        }
    }

    /// Fetch full player records for a round, ordered by player_index.
    func fetchPlayers(forRound roundId: Int64) throws -> [RoundPlayerRecord] {
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db,
                sql: """
                SELECT round_id, player_pubkey, player_index, added_at
                FROM round_players
                WHERE round_id = ?
                ORDER BY player_index ASC
                """,
                arguments: [roundId])

            return rows.map { row in
                RoundPlayerRecord(
                    roundId: row["round_id"],
                    playerPubkey: row["player_pubkey"],
                    playerIndex: row["player_index"],
                    addedAt: row["added_at"]
                )
            }
        }
    }
}

// MARK: - Round Nostr Repository

class RoundNostrRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// Store the Nostr initiation event ID for a round.
    /// PK constraint prevents duplicate inserts for the same round.
    /// joinedVia: "created" (default, round creator) or "joined" (remote player).
    func insertInitiation(roundId: Int64, initiationEventId: String, joinedVia: String = "created") throws {
        let now = ISO8601DateFormatter().string(from: Date())

        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO round_nostr (round_id, initiation_event_id, published_at, joined_via)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [roundId, initiationEventId, now, joinedVia]
            )
        }
    }

    /// Fetch the stored initiation event ID for a round, or nil if not yet published.
    func fetchInitiation(forRound roundId: Int64) throws -> RoundNostrRecord? {
        return try dbQueue.read { db in
            guard let row = try Row.fetchOne(db,
                sql: "SELECT round_id, initiation_event_id, published_at, joined_via FROM round_nostr WHERE round_id = ?",
                arguments: [roundId]) else {
                return nil
            }

            return RoundNostrRecord(
                roundId: row["round_id"],
                initiationEventId: row["initiation_event_id"],
                publishedAt: row["published_at"],
                joinedVia: row["joined_via"]
            )
        }
    }

    /// Fetch a round by its initiation event ID (for join deduplication).
    /// Uses the unique index on initiation_event_id (v7 migration).
    func fetchRound(byInitiationEventId eventId: String) throws -> RoundNostrRecord? {
        return try dbQueue.read { db in
            guard let row = try Row.fetchOne(db,
                sql: "SELECT round_id, initiation_event_id, published_at, joined_via FROM round_nostr WHERE initiation_event_id = ?",
                arguments: [eventId]) else {
                return nil
            }

            return RoundNostrRecord(
                roundId: row["round_id"],
                initiationEventId: row["initiation_event_id"],
                publishedAt: row["published_at"],
                joinedVia: row["joined_via"]
            )
        }
    }
}
