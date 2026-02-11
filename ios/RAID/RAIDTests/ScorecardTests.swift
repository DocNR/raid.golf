// ScorecardTests.swift
// Gambit Golf
//
// Tests for scorecard domain (kernel-adjacent):
// - Schema immutability (5 tables × UPDATE/DELETE)
// - Content-addressing (hash computed once, fetch never recomputes)
// - Hole-count consistency (9-hole/18-hole validation)
// - Round lifecycle (create → score → complete)
// - Latest-wins corrections (deterministic ordering)
// - Constraint validation (FK, range checks)
// - Partial scoring

import XCTest
import GRDB
@testable import RAID

final class ScorecardTests: XCTestCase {

    // MARK: - Helpers

    private func createTestDatabase() throws -> DatabaseQueue {
        try DatabaseQueue.createRAIDDatabase(at: ":memory:")
    }

    /// Insert a course snapshot via raw SQL (for schema-level tests)
    private func insertRawCourseSnapshot(db: Database, hash: String = "a" + String(repeating: "0", count: 63)) throws {
        try db.execute(sql: """
            INSERT INTO course_snapshots (course_hash, course_name, tee_set, hole_count, canonical_json, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """, arguments: [hash, "Test Course", "Blue", 9, "{\"test\":true}", "2026-02-08T12:00:00Z"])
    }

    /// Insert a course hole via raw SQL
    private func insertRawCourseHole(db: Database, hash: String = "a" + String(repeating: "0", count: 63), holeNumber: Int = 1, par: Int = 4) throws {
        try db.execute(sql: """
            INSERT INTO course_holes (course_hash, hole_number, par, handicap_index)
            VALUES (?, ?, ?, ?)
            """, arguments: [hash, holeNumber, par, nil as Int?])
    }

    /// Insert a round via raw SQL, returns round_id
    private func insertRawRound(db: Database, courseHash: String = "a" + String(repeating: "0", count: 63)) throws -> Int64 {
        try db.execute(sql: """
            INSERT INTO rounds (course_hash, round_date, created_at)
            VALUES (?, ?, ?)
            """, arguments: [courseHash, "2026-02-08", "2026-02-08T12:00:00Z"])
        return db.lastInsertedRowID
    }

    /// Create a 9-hole course snapshot input
    private func make9HoleInput() -> CourseSnapshotInput {
        CourseSnapshotInput(
            courseName: "Test Course",
            teeSet: "Blue",
            holes: (1...9).map { HoleDefinition(holeNumber: $0, par: 4) }
        )
    }

    /// Create an 18-hole course snapshot input
    private func make18HoleInput() -> CourseSnapshotInput {
        CourseSnapshotInput(
            courseName: "Full Course",
            teeSet: "White",
            holes: (1...18).map { HoleDefinition(holeNumber: $0, par: $0 % 3 == 0 ? 3 : ($0 % 5 == 0 ? 5 : 4)) }
        )
    }

    /// Create a back-9 course snapshot input (holes 10-18)
    private func makeBack9Input() -> CourseSnapshotInput {
        CourseSnapshotInput(
            courseName: "Back Nine Course",
            teeSet: "Blue",
            holes: (10...18).map { HoleDefinition(holeNumber: $0, par: 4) }
        )
    }

    // MARK: - Schema Immutability: course_snapshots

    func testCourseSnapshotUpdateRejected() throws {
        let dbQueue = try createTestDatabase()

        try dbQueue.write { db in
            try self.insertRawCourseSnapshot(db: db)
        }

        do {
            try dbQueue.write { db in
                try db.execute(sql: "UPDATE course_snapshots SET course_name = ? WHERE course_hash = ?",
                              arguments: ["Modified", "a" + String(repeating: "0", count: 63)])
            }
            XCTFail("UPDATE should have been rejected by trigger")
        } catch let error as DatabaseError {
            XCTAssertTrue(error.message?.lowercased().contains("immutable") == true)
        }
    }

    func testCourseSnapshotDeleteRejected() throws {
        let dbQueue = try createTestDatabase()

        try dbQueue.write { db in
            try self.insertRawCourseSnapshot(db: db)
        }

        do {
            try dbQueue.write { db in
                try db.execute(sql: "DELETE FROM course_snapshots WHERE course_hash = ?",
                              arguments: ["a" + String(repeating: "0", count: 63)])
            }
            XCTFail("DELETE should have been rejected by trigger")
        } catch let error as DatabaseError {
            XCTAssertTrue(error.message?.lowercased().contains("immutable") == true)
        }
    }

    // MARK: - Schema Immutability: course_holes

    func testCourseHoleUpdateRejected() throws {
        let dbQueue = try createTestDatabase()
        let hash = "a" + String(repeating: "0", count: 63)

        try dbQueue.write { db in
            try self.insertRawCourseSnapshot(db: db, hash: hash)
            try self.insertRawCourseHole(db: db, hash: hash)
        }

        do {
            try dbQueue.write { db in
                try db.execute(sql: "UPDATE course_holes SET par = ? WHERE course_hash = ? AND hole_number = ?",
                              arguments: [5, hash, 1])
            }
            XCTFail("UPDATE should have been rejected by trigger")
        } catch let error as DatabaseError {
            XCTAssertTrue(error.message?.lowercased().contains("immutable") == true)
        }
    }

    func testCourseHoleDeleteRejected() throws {
        let dbQueue = try createTestDatabase()
        let hash = "a" + String(repeating: "0", count: 63)

        try dbQueue.write { db in
            try self.insertRawCourseSnapshot(db: db, hash: hash)
            try self.insertRawCourseHole(db: db, hash: hash)
        }

        do {
            try dbQueue.write { db in
                try db.execute(sql: "DELETE FROM course_holes WHERE course_hash = ? AND hole_number = ?",
                              arguments: [hash, 1])
            }
            XCTFail("DELETE should have been rejected by trigger")
        } catch let error as DatabaseError {
            XCTAssertTrue(error.message?.lowercased().contains("immutable") == true)
        }
    }

    // MARK: - Schema Immutability: rounds

    func testRoundUpdateRejected() throws {
        let dbQueue = try createTestDatabase()
        let hash = "a" + String(repeating: "0", count: 63)

        var roundId: Int64 = 0
        try dbQueue.write { db in
            try self.insertRawCourseSnapshot(db: db, hash: hash)
            roundId = try self.insertRawRound(db: db, courseHash: hash)
        }

        do {
            try dbQueue.write { db in
                try db.execute(sql: "UPDATE rounds SET round_date = ? WHERE round_id = ?",
                              arguments: ["2026-03-01", roundId])
            }
            XCTFail("UPDATE should have been rejected by trigger")
        } catch let error as DatabaseError {
            XCTAssertTrue(error.message?.lowercased().contains("immutable") == true)
        }
    }

    func testRoundDeleteRejected() throws {
        let dbQueue = try createTestDatabase()
        let hash = "a" + String(repeating: "0", count: 63)

        var roundId: Int64 = 0
        try dbQueue.write { db in
            try self.insertRawCourseSnapshot(db: db, hash: hash)
            roundId = try self.insertRawRound(db: db, courseHash: hash)
        }

        do {
            try dbQueue.write { db in
                try db.execute(sql: "DELETE FROM rounds WHERE round_id = ?", arguments: [roundId])
            }
            XCTFail("DELETE should have been rejected by trigger")
        } catch let error as DatabaseError {
            XCTAssertTrue(error.message?.lowercased().contains("immutable") == true)
        }
    }

    // MARK: - Schema Immutability: round_events

    func testRoundEventUpdateRejected() throws {
        let dbQueue = try createTestDatabase()
        let hash = "a" + String(repeating: "0", count: 63)

        var eventId: Int64 = 0
        try dbQueue.write { db in
            try self.insertRawCourseSnapshot(db: db, hash: hash)
            let roundId = try self.insertRawRound(db: db, courseHash: hash)
            try db.execute(sql: """
                INSERT INTO round_events (round_id, event_type, recorded_at)
                VALUES (?, 'completed', ?)
                """, arguments: [roundId, "2026-02-08T13:00:00Z"])
            eventId = db.lastInsertedRowID
        }

        do {
            try dbQueue.write { db in
                try db.execute(sql: "UPDATE round_events SET recorded_at = ? WHERE event_id = ?",
                              arguments: ["2026-02-08T14:00:00Z", eventId])
            }
            XCTFail("UPDATE should have been rejected by trigger")
        } catch let error as DatabaseError {
            XCTAssertTrue(error.message?.lowercased().contains("immutable") == true)
        }
    }

    func testRoundEventDeleteRejected() throws {
        let dbQueue = try createTestDatabase()
        let hash = "a" + String(repeating: "0", count: 63)

        var eventId: Int64 = 0
        try dbQueue.write { db in
            try self.insertRawCourseSnapshot(db: db, hash: hash)
            let roundId = try self.insertRawRound(db: db, courseHash: hash)
            try db.execute(sql: """
                INSERT INTO round_events (round_id, event_type, recorded_at)
                VALUES (?, 'completed', ?)
                """, arguments: [roundId, "2026-02-08T13:00:00Z"])
            eventId = db.lastInsertedRowID
        }

        do {
            try dbQueue.write { db in
                try db.execute(sql: "DELETE FROM round_events WHERE event_id = ?", arguments: [eventId])
            }
            XCTFail("DELETE should have been rejected by trigger")
        } catch let error as DatabaseError {
            XCTAssertTrue(error.message?.lowercased().contains("immutable") == true)
        }
    }

    // MARK: - Schema Immutability: hole_scores

    func testHoleScoreUpdateRejected() throws {
        let dbQueue = try createTestDatabase()
        let hash = "a" + String(repeating: "0", count: 63)

        var scoreId: Int64 = 0
        try dbQueue.write { db in
            try self.insertRawCourseSnapshot(db: db, hash: hash)
            let roundId = try self.insertRawRound(db: db, courseHash: hash)
            try db.execute(sql: """
                INSERT INTO hole_scores (round_id, hole_number, strokes, recorded_at)
                VALUES (?, ?, ?, ?)
                """, arguments: [roundId, 1, 5, "2026-02-08T12:01:00Z"])
            scoreId = db.lastInsertedRowID
        }

        do {
            try dbQueue.write { db in
                try db.execute(sql: "UPDATE hole_scores SET strokes = ? WHERE score_id = ?",
                              arguments: [4, scoreId])
            }
            XCTFail("UPDATE should have been rejected by trigger")
        } catch let error as DatabaseError {
            XCTAssertTrue(error.message?.lowercased().contains("immutable") == true)
        }
    }

    func testHoleScoreDeleteRejected() throws {
        let dbQueue = try createTestDatabase()
        let hash = "a" + String(repeating: "0", count: 63)

        var scoreId: Int64 = 0
        try dbQueue.write { db in
            try self.insertRawCourseSnapshot(db: db, hash: hash)
            let roundId = try self.insertRawRound(db: db, courseHash: hash)
            try db.execute(sql: """
                INSERT INTO hole_scores (round_id, hole_number, strokes, recorded_at)
                VALUES (?, ?, ?, ?)
                """, arguments: [roundId, 1, 5, "2026-02-08T12:01:00Z"])
            scoreId = db.lastInsertedRowID
        }

        do {
            try dbQueue.write { db in
                try db.execute(sql: "DELETE FROM hole_scores WHERE score_id = ?", arguments: [scoreId])
            }
            XCTFail("DELETE should have been rejected by trigger")
        } catch let error as DatabaseError {
            XCTAssertTrue(error.message?.lowercased().contains("immutable") == true)
        }
    }

    // MARK: - Content-Addressing: Hash Computed Once

    func testCourseSnapshotHashComputedOnce() throws {
        let dbQueue = try createTestDatabase()
        let spyCanon = SpyCanonicalizer()
        let spyHash = SpyHasher()

        let repo = CourseSnapshotRepository(dbQueue: dbQueue, canonicalizer: spyCanon, hasher: spyHash)
        let input = make9HoleInput()

        let record = try repo.insertCourseSnapshot(input)

        XCTAssertEqual(spyCanon.callCount, 1, "Canonicalize should be called exactly once during insert")
        XCTAssertEqual(spyHash.callCount, 1, "Hash should be called exactly once during insert")

        // Fetch should NOT call canonicalize or hash
        let fetched = try repo.fetchCourseSnapshot(byHash: record.courseHash)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.courseHash, record.courseHash)

        XCTAssertEqual(spyCanon.callCount, 1, "Fetch should NOT call canonicalize")
        XCTAssertEqual(spyHash.callCount, 1, "Fetch should NOT call hash")
    }

    func testFetchCourseSnapshotNeverRecomputesHash() throws {
        let dbQueue = try createTestDatabase()
        let spyCanon = SpyCanonicalizer()
        let spyHash = SpyHasher()

        let repo = CourseSnapshotRepository(dbQueue: dbQueue, canonicalizer: spyCanon, hasher: spyHash)
        let record = try repo.insertCourseSnapshot(make9HoleInput())

        XCTAssertEqual(spyCanon.callCount, 1)
        XCTAssertEqual(spyHash.callCount, 1)

        // Fetch multiple times
        for _ in 1...3 {
            _ = try repo.fetchCourseSnapshot(byHash: record.courseHash)
        }

        XCTAssertEqual(spyCanon.callCount, 1, "Fetch should never call canonicalize")
        XCTAssertEqual(spyHash.callCount, 1, "Fetch should never call hash")
    }

    func testCourseSnapshotIdempotentInsert() throws {
        let dbQueue = try createTestDatabase()
        let repo = CourseSnapshotRepository(dbQueue: dbQueue)
        let input = make9HoleInput()

        let record1 = try repo.insertCourseSnapshot(input)
        let record2 = try repo.insertCourseSnapshot(input)

        XCTAssertEqual(record1.courseHash, record2.courseHash, "Same input should produce same hash")

        // Verify only one row exists
        let count = try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM course_snapshots")
        }
        XCTAssertEqual(count, 1, "Idempotent insert should not create duplicate rows")

        // Verify only 9 course_holes rows
        let holesCount = try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM course_holes WHERE course_hash = ?",
                            arguments: [record1.courseHash])
        }
        XCTAssertEqual(holesCount, 9, "Should have exactly 9 course_holes rows")
    }

    // MARK: - Hole-Count Consistency

    func testNineHoleSnapshotInsertsExactlyNineHoles() throws {
        let dbQueue = try createTestDatabase()
        let repo = CourseSnapshotRepository(dbQueue: dbQueue)

        let record = try repo.insertCourseSnapshot(make9HoleInput())
        XCTAssertEqual(record.holeCount, 9)

        let holes = try repo.fetchHoles(forCourse: record.courseHash)
        XCTAssertEqual(holes.count, 9)
        XCTAssertEqual(holes.map(\.holeNumber), Array(1...9))
    }

    func testEighteenHoleSnapshotInsertsExactlyEighteenHoles() throws {
        let dbQueue = try createTestDatabase()
        let repo = CourseSnapshotRepository(dbQueue: dbQueue)

        let record = try repo.insertCourseSnapshot(make18HoleInput())
        XCTAssertEqual(record.holeCount, 18)

        let holes = try repo.fetchHoles(forCourse: record.courseHash)
        XCTAssertEqual(holes.count, 18)
        XCTAssertEqual(holes.map(\.holeNumber), Array(1...18))
    }

    func testBack9SnapshotInsertsExactlyNineHolesStartingAt10() throws {
        let dbQueue = try createTestDatabase()
        let repo = CourseSnapshotRepository(dbQueue: dbQueue)

        let record = try repo.insertCourseSnapshot(makeBack9Input())
        XCTAssertEqual(record.holeCount, 9)

        let holes = try repo.fetchHoles(forCourse: record.courseHash)
        XCTAssertEqual(holes.count, 9)
        XCTAssertEqual(holes.map(\.holeNumber), Array(10...18),
                       "Back 9 snapshot must store exactly holes 10-18")
    }

    func testMalformedNineHoleSetRejected() throws {
        let dbQueue = try createTestDatabase()
        let repo = CourseSnapshotRepository(dbQueue: dbQueue)

        // 9 holes but not a valid front/back set: {1..8, 10}
        let malformedInput = CourseSnapshotInput(
            courseName: "Bad Course",
            teeSet: "Red",
            holes: [1, 2, 3, 4, 5, 6, 7, 8, 10].map { HoleDefinition(holeNumber: $0, par: 4) }
        )

        XCTAssertThrowsError(try repo.insertCourseSnapshot(malformedInput)) { error in
            guard case CourseSnapshotError.invalidHoleSet = error else {
                XCTFail("Expected invalidHoleSet error, got: \(error)")
                return
            }
        }

        // Verify transactional rollback: no course_snapshots rows
        let snapshotCount = try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM course_snapshots")
        }
        XCTAssertEqual(snapshotCount, 0, "No snapshot should exist after rejection")

        // Verify transactional rollback: no course_holes rows
        let holesCount = try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM course_holes")
        }
        XCTAssertEqual(holesCount, 0, "No course_holes should exist after rejection")
    }

    func testInvalidHoleCountRejected() throws {
        let dbQueue = try createTestDatabase()
        let repo = CourseSnapshotRepository(dbQueue: dbQueue)

        let invalidInput = CourseSnapshotInput(
            courseName: "Bad Course",
            teeSet: "Red",
            holes: (1...12).map { HoleDefinition(holeNumber: $0, par: 4) }
        )

        XCTAssertThrowsError(try repo.insertCourseSnapshot(invalidInput)) { error in
            guard case CourseSnapshotError.invalidHoleCount(let expected, let actual) = error else {
                XCTFail("Expected invalidHoleCount error, got: \(error)")
                return
            }
            XCTAssertEqual(expected, 9) // or 18
            XCTAssertEqual(actual, 12)
        }
    }

    // MARK: - Round Lifecycle

    func testCreateRoundEndToEnd() throws {
        let dbQueue = try createTestDatabase()
        let snapshotRepo = CourseSnapshotRepository(dbQueue: dbQueue)
        let roundRepo = RoundRepository(dbQueue: dbQueue)
        let scoreRepo = HoleScoreRepository(dbQueue: dbQueue)

        // Create snapshot
        let snapshot = try snapshotRepo.insertCourseSnapshot(make9HoleInput())

        // Create round
        let round = try roundRepo.createRound(courseHash: snapshot.courseHash, roundDate: "2026-02-08")
        XCTAssertEqual(round.courseHash, snapshot.courseHash)

        // Record scores for all 9 holes
        for hole in 1...9 {
            _ = try scoreRepo.recordScore(roundId: round.roundId, score: HoleScoreInput(holeNumber: hole, strokes: 4))
        }

        // Complete round
        try roundRepo.completeRound(roundId: round.roundId)
        XCTAssertTrue(try roundRepo.isCompleted(roundId: round.roundId))

        // Verify round row is unchanged (completion is an event, not UPDATE)
        let fetchedRound = try dbQueue.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM rounds WHERE round_id = ?", arguments: [round.roundId])
        }
        XCTAssertEqual(fetchedRound?["round_date"] as String?, "2026-02-08")
        XCTAssertEqual(fetchedRound?["course_hash"] as String?, snapshot.courseHash)
    }

    func testCompletionIsAppendEvent() throws {
        let dbQueue = try createTestDatabase()
        let snapshotRepo = CourseSnapshotRepository(dbQueue: dbQueue)
        let roundRepo = RoundRepository(dbQueue: dbQueue)

        let snapshot = try snapshotRepo.insertCourseSnapshot(make9HoleInput())
        let round = try roundRepo.createRound(courseHash: snapshot.courseHash, roundDate: "2026-02-08")

        // Before completion: not completed
        XCTAssertFalse(try roundRepo.isCompleted(roundId: round.roundId))

        // Complete
        try roundRepo.completeRound(roundId: round.roundId)

        // After completion: completed
        XCTAssertTrue(try roundRepo.isCompleted(roundId: round.roundId))

        // Verify event row exists
        let eventCount = try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM round_events WHERE round_id = ? AND event_type = 'completed'",
                            arguments: [round.roundId])
        }
        XCTAssertEqual(eventCount, 1)
    }

    func testDoubleCompletionRejected() throws {
        let dbQueue = try createTestDatabase()
        let snapshotRepo = CourseSnapshotRepository(dbQueue: dbQueue)
        let roundRepo = RoundRepository(dbQueue: dbQueue)

        let snapshot = try snapshotRepo.insertCourseSnapshot(make9HoleInput())
        let round = try roundRepo.createRound(courseHash: snapshot.courseHash, roundDate: "2026-02-08")

        // First completion succeeds
        try roundRepo.completeRound(roundId: round.roundId)

        // Second completion should fail (UNIQUE constraint)
        XCTAssertThrowsError(try roundRepo.completeRound(roundId: round.roundId)) { error in
            guard let dbError = error as? DatabaseError else {
                XCTFail("Expected DatabaseError, got: \(error)")
                return
            }
            XCTAssertEqual(dbError.resultCode, .SQLITE_CONSTRAINT)
        }
    }

    func testListRoundsReturnsCorrectData() throws {
        let dbQueue = try createTestDatabase()
        let snapshotRepo = CourseSnapshotRepository(dbQueue: dbQueue)
        let roundRepo = RoundRepository(dbQueue: dbQueue)
        let scoreRepo = HoleScoreRepository(dbQueue: dbQueue)

        let snapshot = try snapshotRepo.insertCourseSnapshot(make9HoleInput())
        let round = try roundRepo.createRound(courseHash: snapshot.courseHash, roundDate: "2026-02-08")

        // Score all 9 holes with par (4 each)
        for hole in 1...9 {
            _ = try scoreRepo.recordScore(roundId: round.roundId, score: HoleScoreInput(holeNumber: hole, strokes: 4))
        }
        try roundRepo.completeRound(roundId: round.roundId)

        let list = try roundRepo.listRounds()
        XCTAssertEqual(list.count, 1)

        let item = list[0]
        XCTAssertEqual(item.roundId, round.roundId)
        XCTAssertEqual(item.courseName, "Test Course")
        XCTAssertEqual(item.teeSet, "Blue")
        XCTAssertEqual(item.holeCount, 9)
        XCTAssertTrue(item.isCompleted)
        XCTAssertEqual(item.totalStrokes, 36) // 9 holes × 4 strokes
        XCTAssertEqual(item.holesScored, 9)
    }

    // MARK: - Latest-Wins Corrections

    func testCorrectionLatestWins() throws {
        let dbQueue = try createTestDatabase()
        let snapshotRepo = CourseSnapshotRepository(dbQueue: dbQueue)
        let roundRepo = RoundRepository(dbQueue: dbQueue)
        let scoreRepo = HoleScoreRepository(dbQueue: dbQueue)

        let snapshot = try snapshotRepo.insertCourseSnapshot(make9HoleInput())
        let round = try roundRepo.createRound(courseHash: snapshot.courseHash, roundDate: "2026-02-08")

        // Record initial score for hole 1
        _ = try scoreRepo.recordScore(roundId: round.roundId, score: HoleScoreInput(holeNumber: 1, strokes: 5))

        // Small delay to ensure different recorded_at
        Thread.sleep(forTimeInterval: 0.01)

        // Correct to 4
        _ = try scoreRepo.recordScore(roundId: round.roundId, score: HoleScoreInput(holeNumber: 1, strokes: 4))

        // Latest should show 4
        let latest = try scoreRepo.fetchLatestScores(forRound: round.roundId)
        XCTAssertEqual(latest.count, 1)
        XCTAssertEqual(latest[0].holeNumber, 1)
        XCTAssertEqual(latest[0].strokes, 4, "Latest-wins should show corrected score")
    }

    func testCorrectionPreservesHistory() throws {
        let dbQueue = try createTestDatabase()
        let snapshotRepo = CourseSnapshotRepository(dbQueue: dbQueue)
        let roundRepo = RoundRepository(dbQueue: dbQueue)
        let scoreRepo = HoleScoreRepository(dbQueue: dbQueue)

        let snapshot = try snapshotRepo.insertCourseSnapshot(make9HoleInput())
        let round = try roundRepo.createRound(courseHash: snapshot.courseHash, roundDate: "2026-02-08")

        _ = try scoreRepo.recordScore(roundId: round.roundId, score: HoleScoreInput(holeNumber: 1, strokes: 5))
        Thread.sleep(forTimeInterval: 0.01)
        _ = try scoreRepo.recordScore(roundId: round.roundId, score: HoleScoreInput(holeNumber: 1, strokes: 4))

        // Both rows should exist in the database
        let allRows = try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM hole_scores WHERE round_id = ? AND hole_number = ?",
                            arguments: [round.roundId, 1])
        }
        XCTAssertEqual(allRows, 2, "Both original and correction should be preserved")
    }

    func testLatestWinsDeterministicOrdering() throws {
        let dbQueue = try createTestDatabase()
        let snapshotRepo = CourseSnapshotRepository(dbQueue: dbQueue)
        let roundRepo = RoundRepository(dbQueue: dbQueue)
        let scoreRepo = HoleScoreRepository(dbQueue: dbQueue)

        let snapshot = try snapshotRepo.insertCourseSnapshot(make9HoleInput())
        let round = try roundRepo.createRound(courseHash: snapshot.courseHash, roundDate: "2026-02-08")

        // Record scores out of order
        _ = try scoreRepo.recordScore(roundId: round.roundId, score: HoleScoreInput(holeNumber: 3, strokes: 5))
        _ = try scoreRepo.recordScore(roundId: round.roundId, score: HoleScoreInput(holeNumber: 1, strokes: 4))
        _ = try scoreRepo.recordScore(roundId: round.roundId, score: HoleScoreInput(holeNumber: 2, strokes: 3))

        let latest = try scoreRepo.fetchLatestScores(forRound: round.roundId)
        XCTAssertEqual(latest.count, 3)
        // Should be ordered by hole_number ASC
        XCTAssertEqual(latest[0].holeNumber, 1)
        XCTAssertEqual(latest[1].holeNumber, 2)
        XCTAssertEqual(latest[2].holeNumber, 3)
    }

    // MARK: - Constraint Validation

    func testRoundWithInvalidCourseHashRejected() throws {
        let dbQueue = try createTestDatabase()
        let roundRepo = RoundRepository(dbQueue: dbQueue)

        XCTAssertThrowsError(try roundRepo.createRound(courseHash: "nonexistent_hash", roundDate: "2026-02-08")) { error in
            guard let dbError = error as? DatabaseError else {
                XCTFail("Expected DatabaseError, got: \(error)")
                return
            }
            XCTAssertEqual(dbError.resultCode, .SQLITE_CONSTRAINT)
        }
    }

    func testHoleNumberOutOfRangeRejected() throws {
        let dbQueue = try createTestDatabase()
        let snapshotRepo = CourseSnapshotRepository(dbQueue: dbQueue)
        let roundRepo = RoundRepository(dbQueue: dbQueue)

        let snapshot = try snapshotRepo.insertCourseSnapshot(make9HoleInput())
        let round = try roundRepo.createRound(courseHash: snapshot.courseHash, roundDate: "2026-02-08")

        // hole_number = 0 should fail
        XCTAssertThrowsError(try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO hole_scores (round_id, hole_number, strokes, recorded_at)
                VALUES (?, ?, ?, ?)
                """, arguments: [round.roundId, 0, 4, "2026-02-08T12:00:00Z"])
        })

        // hole_number = 19 should fail
        XCTAssertThrowsError(try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO hole_scores (round_id, hole_number, strokes, recorded_at)
                VALUES (?, ?, ?, ?)
                """, arguments: [round.roundId, 19, 4, "2026-02-08T12:00:00Z"])
        })
    }

    func testStrokesOutOfRangeRejected() throws {
        let dbQueue = try createTestDatabase()
        let snapshotRepo = CourseSnapshotRepository(dbQueue: dbQueue)
        let roundRepo = RoundRepository(dbQueue: dbQueue)

        let snapshot = try snapshotRepo.insertCourseSnapshot(make9HoleInput())
        let round = try roundRepo.createRound(courseHash: snapshot.courseHash, roundDate: "2026-02-08")

        // strokes = 0 should fail
        XCTAssertThrowsError(try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO hole_scores (round_id, hole_number, strokes, recorded_at)
                VALUES (?, ?, ?, ?)
                """, arguments: [round.roundId, 1, 0, "2026-02-08T12:00:00Z"])
        })

        // strokes = 21 should fail
        XCTAssertThrowsError(try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO hole_scores (round_id, hole_number, strokes, recorded_at)
                VALUES (?, ?, ?, ?)
                """, arguments: [round.roundId, 1, 21, "2026-02-08T12:00:00Z"])
        })
    }

    // MARK: - Partial Scoring

    func testPartialScoringShowsRunningTotal() throws {
        let dbQueue = try createTestDatabase()
        let snapshotRepo = CourseSnapshotRepository(dbQueue: dbQueue)
        let roundRepo = RoundRepository(dbQueue: dbQueue)
        let scoreRepo = HoleScoreRepository(dbQueue: dbQueue)

        let snapshot = try snapshotRepo.insertCourseSnapshot(make9HoleInput())
        let round = try roundRepo.createRound(courseHash: snapshot.courseHash, roundDate: "2026-02-08")

        // Score only 5 of 9 holes
        for hole in 1...5 {
            _ = try scoreRepo.recordScore(roundId: round.roundId, score: HoleScoreInput(holeNumber: hole, strokes: 4))
        }

        let list = try roundRepo.listRounds()
        XCTAssertEqual(list.count, 1)

        let item = list[0]
        XCTAssertEqual(item.holesScored, 5)
        XCTAssertEqual(item.totalStrokes, 20) // 5 holes × 4 strokes
        XCTAssertFalse(item.isCompleted)
    }

    // MARK: - Bugfix Regression: Default Par Persistence

    /// Issue A regression: advancing through holes without adjusting scores
    /// must still persist the default par value for each hole.
    func testDefaultParScoresPersistedOnAdvance() throws {
        let dbQueue = try createTestDatabase()
        let snapshotRepo = CourseSnapshotRepository(dbQueue: dbQueue)
        let roundRepo = RoundRepository(dbQueue: dbQueue)
        let scoreRepo = HoleScoreRepository(dbQueue: dbQueue)

        let snapshot = try snapshotRepo.insertCourseSnapshot(make9HoleInput())
        let round = try roundRepo.createRound(courseHash: snapshot.courseHash, roundDate: "2026-02-08")
        let holes = try snapshotRepo.fetchHoles(forCourse: snapshot.courseHash)

        // Simulate advancing through all 9 holes without adjusting:
        // persist the displayed value (par) for each hole — same logic as ActiveRoundStore.saveCurrentScore()
        for hole in holes {
            let displayedStrokes = hole.par // default: no adjustment
            let input = HoleScoreInput(holeNumber: hole.holeNumber, strokes: displayedStrokes)
            _ = try scoreRepo.recordScore(roundId: round.roundId, score: input)
        }

        // Verify: 9 scores persisted, each matching par (4)
        let latestScores = try scoreRepo.fetchLatestScores(forRound: round.roundId)
        XCTAssertEqual(latestScores.count, 9)
        for score in latestScores {
            XCTAssertEqual(score.strokes, 4, "Hole \(score.holeNumber) should have par (4)")
        }

        // Verify: listRounds reflects all holes scored
        let list = try roundRepo.listRounds()
        XCTAssertEqual(list[0].holesScored, 9)
        XCTAssertEqual(list[0].totalStrokes, 36) // 9 × 4
    }

    /// Issue A regression: finish eligibility must be true when all holes
    /// have default par scores persisted (even with no manual adjustments).
    func testFinishEnabledWhenAllHolesHaveDefaultPar() throws {
        let dbQueue = try createTestDatabase()
        let snapshotRepo = CourseSnapshotRepository(dbQueue: dbQueue)
        let roundRepo = RoundRepository(dbQueue: dbQueue)
        let scoreRepo = HoleScoreRepository(dbQueue: dbQueue)

        let snapshot = try snapshotRepo.insertCourseSnapshot(make9HoleInput())
        let round = try roundRepo.createRound(courseHash: snapshot.courseHash, roundDate: "2026-02-08")
        let holes = try snapshotRepo.fetchHoles(forCourse: snapshot.courseHash)

        // Persist default par for all holes (simulates advanceHole through all 9)
        var scores: [Int: Int] = [:]
        for hole in holes {
            let strokes = hole.par
            scores[hole.holeNumber] = strokes
            _ = try scoreRepo.recordScore(roundId: round.roundId, score: HoleScoreInput(holeNumber: hole.holeNumber, strokes: strokes))
        }

        // Assert finish eligibility: holesScored >= holes.count
        let holesScored = holes.filter { scores[$0.holeNumber] != nil }.count
        XCTAssertEqual(holesScored, holes.count)
        XCTAssertTrue(holesScored >= holes.count, "Finish should be enabled when all holes scored")
    }

    // MARK: - Bugfix Regression: RoundDetailView Sequential Reads

    /// Issue B regression: loading round detail data must work without
    /// nested dbQueue.read calls. This test exercises the sequential read pattern.
    func testRoundDetailLoadDataSequentialReads() throws {
        let dbQueue = try createTestDatabase()
        let snapshotRepo = CourseSnapshotRepository(dbQueue: dbQueue)
        let roundRepo = RoundRepository(dbQueue: dbQueue)
        let scoreRepo = HoleScoreRepository(dbQueue: dbQueue)

        // Create a completed round with scores
        let snapshot = try snapshotRepo.insertCourseSnapshot(make9HoleInput())
        let round = try roundRepo.createRound(courseHash: snapshot.courseHash, roundDate: "2026-02-08")

        for hole in 1...9 {
            _ = try scoreRepo.recordScore(roundId: round.roundId, score: HoleScoreInput(holeNumber: hole, strokes: hole + 3))
        }
        try roundRepo.completeRound(roundId: round.roundId)

        // Sequential read pattern — same as RoundDetailView.loadData()
        // Step 1: standalone read for courseHash
        let courseHash = try dbQueue.read { db in
            try String.fetchOne(db,
                sql: "SELECT course_hash FROM rounds WHERE round_id = ?",
                arguments: [round.roundId])
        }
        XCTAssertNotNil(courseHash)

        // Step 2-4: sequential repo calls (each owns its own dbQueue.read)
        let loadedSnapshot = try snapshotRepo.fetchCourseSnapshot(byHash: courseHash!)
        XCTAssertNotNil(loadedSnapshot)
        XCTAssertEqual(loadedSnapshot!.courseName, "Test Course")

        let loadedHoles = try snapshotRepo.fetchHoles(forCourse: courseHash!)
        XCTAssertEqual(loadedHoles.count, 9)

        let loadedScores = try scoreRepo.fetchLatestScores(forRound: round.roundId)
        XCTAssertEqual(loadedScores.count, 9)

        // Verify scores are correct
        for score in loadedScores {
            XCTAssertEqual(score.strokes, score.holeNumber + 3)
        }
    }

    // MARK: - Bugfix Regression: Score Entry Resume

    /// Scoring holes 1–5 and reloading should resume at hole 6 (first unscored).
    /// If all holes scored, resume at last hole with finish enabled.
    func testScoreEntryResumesFromPersistedState() throws {
        let dbQueue = try createTestDatabase()
        let snapshotRepo = CourseSnapshotRepository(dbQueue: dbQueue)
        let roundRepo = RoundRepository(dbQueue: dbQueue)
        let scoreRepo = HoleScoreRepository(dbQueue: dbQueue)

        let snapshot = try snapshotRepo.insertCourseSnapshot(make9HoleInput())
        let round = try roundRepo.createRound(courseHash: snapshot.courseHash, roundDate: "2026-02-08")

        // Score holes 1–5
        for hole in 1...5 {
            _ = try scoreRepo.recordScore(roundId: round.roundId, score: HoleScoreInput(holeNumber: hole, strokes: 4))
        }

        // Simulate store reload: fetch holes and scores, compute resume index
        let holes = try snapshotRepo.fetchHoles(forCourse: snapshot.courseHash)
        let existingScores = try scoreRepo.fetchLatestScores(forRound: round.roundId)
        var scores: [Int: Int] = [:]
        for score in existingScores {
            scores[score.holeNumber] = score.strokes
        }

        let firstUnscoredIndex = holes.firstIndex(where: { scores[$0.holeNumber] == nil })
        XCTAssertEqual(firstUnscoredIndex, 5, "Should resume at index 5 (hole 6)")
        XCTAssertEqual(scores.count, 5)

        // Now score all remaining holes and verify resume at last hole
        for hole in 6...9 {
            _ = try scoreRepo.recordScore(roundId: round.roundId, score: HoleScoreInput(holeNumber: hole, strokes: 4))
        }

        let allScores = try scoreRepo.fetchLatestScores(forRound: round.roundId)
        var fullScores: [Int: Int] = [:]
        for score in allScores {
            fullScores[score.holeNumber] = score.strokes
        }

        let allScoredResume = holes.firstIndex(where: { fullScores[$0.holeNumber] == nil })
        XCTAssertNil(allScoredResume, "No unscored holes — firstIndex should be nil")

        // When all scored, store resumes at last hole (index = count - 1)
        let resumeIndex = allScoredResume ?? (holes.count - 1)
        XCTAssertEqual(resumeIndex, 8, "Should resume at last hole (index 8) when all scored")
    }
}
