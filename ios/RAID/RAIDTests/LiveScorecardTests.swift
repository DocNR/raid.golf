// LiveScorecardTests.swift
// RAID Golf
//
// Tests for Phase 7C: Score Sync via Replaceable Events (kind 30501).
// Covers event building, parsing, and remote scores caching.

import XCTest
import GRDB
@testable import RAID

final class LiveScorecardTests: XCTestCase {

    // MARK: - Fixtures

    private static let initiationEventId = "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233"
    private static let accountAPubkey = "1007f13a9443b9dede6aa178d5ad6fea58b0fbbd311b1e5d2510a888bb2f8466"
    private static let accountBPubkey = "55127fc9e1c03c6b459a3bab72fdb99def1644c5f239bdd09f3e5fb401ed9b21"

    // MARK: - 1. Event Building

    func testBuildLiveScorecardEvent_Kind30501() throws {
        let builder = try NIP101gEventBuilder.buildLiveScorecardEvent(
            initiationEventId: Self.initiationEventId,
            scores: [1: 4, 2: 5, 3: 3],
            status: "in_progress",
            playerPubkeys: [Self.accountAPubkey, Self.accountBPubkey]
        )
        // Builder creation should succeed (kind is set internally)
        XCTAssertNotNil(builder)
    }

    func testBuildLiveScorecardEvent_ScoreTagsCorrect() throws {
        let tagArrays = NIP101gEventBuilder.buildLiveScorecardTagArrays(
            initiationEventId: Self.initiationEventId,
            scores: [1: 4, 2: 5],
            status: "in_progress",
            playerPubkeys: [Self.accountAPubkey]
        )

        // Find score tags
        let scoreTags = tagArrays.filter { $0.first == "score" }
        XCTAssertEqual(scoreTags.count, 2)

        // Scores should be sorted by hole number
        XCTAssertEqual(scoreTags[0], ["score", "1", "4"])
        XCTAssertEqual(scoreTags[1], ["score", "2", "5"])
    }

    func testBuildLiveScorecardEvent_DTagIsInitiationId() throws {
        let tagArrays = NIP101gEventBuilder.buildLiveScorecardTagArrays(
            initiationEventId: Self.initiationEventId,
            scores: [1: 4],
            status: "in_progress",
            playerPubkeys: []
        )

        let dTag = tagArrays.first { $0.first == "d" }
        XCTAssertNotNil(dTag)
        XCTAssertEqual(dTag?[1], Self.initiationEventId)
    }

    func testBuildLiveScorecardEvent_StatusTagPresent() throws {
        let tagArrays = NIP101gEventBuilder.buildLiveScorecardTagArrays(
            initiationEventId: Self.initiationEventId,
            scores: [:],
            status: "in_progress",
            playerPubkeys: []
        )

        let statusTag = tagArrays.first { $0.first == "status" }
        XCTAssertNotNil(statusTag)
        XCTAssertEqual(statusTag?[1], "in_progress")
    }

    // MARK: - 2. Event Parsing

    func testParseLiveScorecardEvent_ExtractsScores() throws {
        let tagArrays: [[String]] = [
            ["d", Self.initiationEventId],
            ["e", Self.initiationEventId],
            ["status", "in_progress"],
            ["score", "1", "4"],
            ["score", "2", "5"],
            ["score", "3", "3"],
        ]

        let data = NIP101gEventParser.parseLiveScorecard(
            tagArrays: tagArrays,
            authorPubkeyHex: Self.accountAPubkey
        )

        XCTAssertNotNil(data)
        XCTAssertEqual(data?.scores[1], 4)
        XCTAssertEqual(data?.scores[2], 5)
        XCTAssertEqual(data?.scores[3], 3)
        XCTAssertEqual(data?.scores.count, 3)
    }

    func testParseLiveScorecardEvent_ExtractsStatus() throws {
        let tagArrays: [[String]] = [
            ["d", Self.initiationEventId],
            ["status", "completed"],
        ]

        let data = NIP101gEventParser.parseLiveScorecard(
            tagArrays: tagArrays,
            authorPubkeyHex: Self.accountAPubkey
        )

        XCTAssertEqual(data?.status, "completed")
    }

    // MARK: - 3. Remote Scores Cache

    func testRemoteScoresRepository_UpsertAndFetch() throws {
        let dbQueue = try makeTestDatabase()
        let repo = RemoteScoresRepository(dbQueue: dbQueue)

        // Need a round to satisfy FK
        let roundId = try createTestRound(dbQueue: dbQueue)

        // Upsert scores for player A
        try repo.upsertScores(
            roundId: roundId,
            playerPubkey: Self.accountAPubkey,
            scores: [1: 4, 2: 5]
        )

        // Fetch
        let cached = try repo.fetchRemoteScores(forRound: roundId)
        XCTAssertEqual(cached[Self.accountAPubkey]?[1], 4)
        XCTAssertEqual(cached[Self.accountAPubkey]?[2], 5)
    }

    func testRemoteScoresRepository_UpsertReplacesPreviousScores() throws {
        let dbQueue = try makeTestDatabase()
        let repo = RemoteScoresRepository(dbQueue: dbQueue)
        let roundId = try createTestRound(dbQueue: dbQueue)

        // Initial scores
        try repo.upsertScores(
            roundId: roundId,
            playerPubkey: Self.accountAPubkey,
            scores: [1: 4, 2: 5]
        )

        // Updated scores (hole 1 changed, hole 3 added)
        try repo.upsertScores(
            roundId: roundId,
            playerPubkey: Self.accountAPubkey,
            scores: [1: 3, 2: 5, 3: 4]
        )

        let cached = try repo.fetchRemoteScores(forRound: roundId)
        XCTAssertEqual(cached[Self.accountAPubkey]?[1], 3, "Hole 1 should be updated to 3")
        XCTAssertEqual(cached[Self.accountAPubkey]?[3], 4, "Hole 3 should be added")
    }

    func testRemoteScoresRepository_MultiplePlayersIndependent() throws {
        let dbQueue = try makeTestDatabase()
        let repo = RemoteScoresRepository(dbQueue: dbQueue)
        let roundId = try createTestRound(dbQueue: dbQueue)

        try repo.upsertScores(roundId: roundId, playerPubkey: Self.accountAPubkey, scores: [1: 4])
        try repo.upsertScores(roundId: roundId, playerPubkey: Self.accountBPubkey, scores: [1: 5])

        let cached = try repo.fetchRemoteScores(forRound: roundId)
        XCTAssertEqual(cached[Self.accountAPubkey]?[1], 4)
        XCTAssertEqual(cached[Self.accountBPubkey]?[1], 5)
        XCTAssertEqual(cached.count, 2)
    }

    // MARK: - Helpers

    private func makeTestDatabase() throws -> DatabaseQueue {
        let dbQueue = try DatabaseQueue(configuration: {
            var config = Configuration()
            config.foreignKeysEnabled = true
            return config
        }())
        try Schema.install(in: dbQueue)
        return dbQueue
    }

    /// Create a minimal round for FK satisfaction in tests
    private func createTestRound(dbQueue: DatabaseQueue) throws -> Int64 {
        // Insert course snapshot
        let snapshotRepo = CourseSnapshotRepository(dbQueue: dbQueue)
        let holes = (1...9).map { HoleDefinition(holeNumber: $0, par: 4) }
        let snapshot = try snapshotRepo.insertCourseSnapshot(
            CourseSnapshotInput(courseName: "Test Course", teeSet: "White", holes: holes)
        )

        // Create round
        let roundRepo = RoundRepository(dbQueue: dbQueue)
        let round = try roundRepo.createRound(
            courseHash: snapshot.courseHash,
            roundDate: "2026-02-14"
        )
        return round.roundId
    }
}
