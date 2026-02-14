// RoundJoinTests.swift
// Gambit Golf
//
// Tests for Phase 7B: Join Round Flow.
// Covers NIP-101g event parsing, hash verification, and local round creation from relay data.

import XCTest
import GRDB
@testable import RAID

final class RoundJoinTests: XCTestCase {

    // MARK: - Test Account Fixtures

    /// Account A (round creator)
    private static let accountAPubkey = "1007f13a9443b9dede6aa178d5ad6fea58b0fbbd311b1e5d2510a888bb2f8466"
    /// Account B (joining player)
    private static let accountBPubkey = "55127fc9e1c03c6b459a3bab72fdb99def1644c5f239bdd09f3e5fb401ed9b21"

    // MARK: - Initiation Content Fixtures

    private func makeInitiationContent() -> RoundInitiationContent {
        let holes = (1...9).map { i in
            NIP101gHoleDefinition(holeNumber: i, par: 4, handicapIndex: nil)
        }
        let course = CourseSnapshotContent(
            courseName: "Fowler's Mill Golf Course",
            teeSet: "Silver M",
            holeCount: 9,
            holes: holes
        )
        let rules = RulesTemplateContent(format: "stroke_play")
        return RoundInitiationContent(courseSnapshot: course, rulesTemplate: rules)
    }

    private func makeInitiationJSON() throws -> String {
        let content = makeInitiationContent()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(content)
        return String(data: data, encoding: .utf8)!
    }

    // MARK: - 1. Parse Initiation Content

    func testParseInitiationContent_ExtractsFields() throws {
        let json = try makeInitiationJSON()

        let parsed = try NIP101gEventParser.parseInitiationContent(json: json)

        XCTAssertEqual(parsed.courseSnapshot.courseName, "Fowler's Mill Golf Course")
        XCTAssertEqual(parsed.courseSnapshot.teeSet, "Silver M")
        XCTAssertEqual(parsed.courseSnapshot.holeCount, 9)
        XCTAssertEqual(parsed.courseSnapshot.holes.count, 9)
        XCTAssertEqual(parsed.courseSnapshot.holes[0].holeNumber, 1)
        XCTAssertEqual(parsed.courseSnapshot.holes[0].par, 4)
        XCTAssertEqual(parsed.rulesTemplate.format, "stroke_play")
    }

    func testParseInitiationContent_InvalidJSON() {
        XCTAssertThrowsError(try NIP101gEventParser.parseInitiationContent(json: "not json"))
    }

    // MARK: - 2. Parse Initiation Tags

    func testParseInitiationTags_ExtractsAllTags() throws {
        let content = makeInitiationContent()
        let courseHash = try NIP101gEventBuilder.computeCourseHash(content: content)
        let rulesHash = try NIP101gEventBuilder.computeRulesHash(content: content)

        let tagData = NIP101gEventParser.parseInitiationTags(tagArrays: [
            ["course_hash", courseHash],
            ["rules_hash", rulesHash],
            ["date", "2026-02-14"],
            ["p", Self.accountAPubkey],
            ["p", Self.accountBPubkey],
            ["t", "golf"],
            ["t", "gambitgolf"],
            ["client", "gambit-golf-ios"]
        ])

        XCTAssertEqual(tagData.courseHash, courseHash)
        XCTAssertEqual(tagData.rulesHash, rulesHash)
        XCTAssertEqual(tagData.date, "2026-02-14")
        XCTAssertEqual(tagData.playerPubkeys, [Self.accountAPubkey, Self.accountBPubkey])
    }

    func testParseInitiationTags_MissingCourseHash() throws {
        let tagData = NIP101gEventParser.parseInitiationTags(tagArrays: [
            ["rules_hash", "abc"],
            ["date", "2026-02-14"],
        ])

        XCTAssertNil(tagData.courseHash)
        XCTAssertEqual(tagData.rulesHash, "abc")
    }

    // MARK: - 3. Hash Verification

    func testVerifyHashes_ValidContent() throws {
        let content = makeInitiationContent()
        let courseHash = try NIP101gEventBuilder.computeCourseHash(content: content)
        let rulesHash = try NIP101gEventBuilder.computeRulesHash(content: content)

        let result = try NIP101gEventParser.verifyHashes(
            content: content,
            courseHash: courseHash,
            rulesHash: rulesHash
        )

        XCTAssertTrue(result, "Valid hashes should verify successfully")
    }

    func testVerifyHashes_TamperedCourseHash() throws {
        let content = makeInitiationContent()
        let rulesHash = try NIP101gEventBuilder.computeRulesHash(content: content)

        let result = try NIP101gEventParser.verifyHashes(
            content: content,
            courseHash: "0000000000000000000000000000000000000000000000000000000000000000",
            rulesHash: rulesHash
        )

        XCTAssertFalse(result, "Tampered course hash should fail verification")
    }

    func testVerifyHashes_TamperedRulesHash() throws {
        let content = makeInitiationContent()
        let courseHash = try NIP101gEventBuilder.computeCourseHash(content: content)

        let result = try NIP101gEventParser.verifyHashes(
            content: content,
            courseHash: courseHash,
            rulesHash: "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
        )

        XCTAssertFalse(result, "Tampered rules hash should fail verification")
    }

    // MARK: - 4. Local Round Creation from Initiation

    func testCreateLocalRoundFromInitiation_InsertsCorrectRecords() throws {
        let dbQueue = try makeTestDatabase()
        let service = RoundJoinService(dbQueue: dbQueue)
        let content = makeInitiationContent()

        let roundId = try service.createLocalRound(
            from: content,
            initiationEventId: "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233",
            date: "2026-02-14",
            playerPubkeys: [Self.accountAPubkey, Self.accountBPubkey],
            myPubkey: Self.accountBPubkey
        )

        // Verify round was created
        let roundRepo = RoundRepository(dbQueue: dbQueue)
        let rounds = try roundRepo.listRounds()
        XCTAssertEqual(rounds.count, 1)
        XCTAssertEqual(rounds[0].roundId, roundId)
        XCTAssertEqual(rounds[0].courseName, "Fowler's Mill Golf Course")
        XCTAssertEqual(rounds[0].holeCount, 9)

        // Verify course snapshot was created — get courseHash from DB
        let courseHash = try dbQueue.read { db in
            try String.fetchOne(db,
                sql: "SELECT course_hash FROM rounds WHERE round_id = ?",
                arguments: [roundId])
        }
        XCTAssertNotNil(courseHash)
        let snapshotRepo = CourseSnapshotRepository(dbQueue: dbQueue)
        let holes = try snapshotRepo.fetchHoles(forCourse: courseHash!)
        XCTAssertEqual(holes.count, 9)

        // Verify round_nostr was created with joined_via = 'joined'
        let nostrRepo = RoundNostrRepository(dbQueue: dbQueue)
        let nostrRecord = try nostrRepo.fetchInitiation(forRound: roundId)
        XCTAssertNotNil(nostrRecord)
        XCTAssertEqual(nostrRecord?.initiationEventId, "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233")
        XCTAssertEqual(nostrRecord?.joinedVia, "joined")

        // Verify players were created
        let playerRepo = RoundPlayerRepository(dbQueue: dbQueue)
        let players = try playerRepo.fetchPlayerPubkeys(forRound: roundId)
        XCTAssertEqual(players.count, 2)
        XCTAssertEqual(players[0], Self.accountAPubkey)
        XCTAssertEqual(players[1], Self.accountBPubkey)
    }

    func testCreateLocalRound_IdempotentOnDuplicateJoin() throws {
        let dbQueue = try makeTestDatabase()
        let service = RoundJoinService(dbQueue: dbQueue)
        let content = makeInitiationContent()
        let eventId = "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233"

        let roundId1 = try service.createLocalRound(
            from: content,
            initiationEventId: eventId,
            date: "2026-02-14",
            playerPubkeys: [Self.accountAPubkey, Self.accountBPubkey],
            myPubkey: Self.accountBPubkey
        )

        // Second join attempt should detect existing and return same round
        let roundId2 = try service.createLocalRound(
            from: content,
            initiationEventId: eventId,
            date: "2026-02-14",
            playerPubkeys: [Self.accountAPubkey, Self.accountBPubkey],
            myPubkey: Self.accountBPubkey
        )

        XCTAssertEqual(roundId1, roundId2, "Duplicate join should return existing round ID")

        // Only one round should exist
        let roundRepo = RoundRepository(dbQueue: dbQueue)
        let rounds = try roundRepo.listRounds()
        XCTAssertEqual(rounds.count, 1)
    }

    func testCreateLocalRound_DeterminesPlayerIndex() throws {
        let dbQueue = try makeTestDatabase()
        let service = RoundJoinService(dbQueue: dbQueue)
        let content = makeInitiationContent()

        let roundId = try service.createLocalRound(
            from: content,
            initiationEventId: "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233",
            date: "2026-02-14",
            playerPubkeys: [Self.accountAPubkey, Self.accountBPubkey],
            myPubkey: Self.accountBPubkey
        )

        // Account B is index 1 in the p tags (0-indexed, Account A is index 0)
        let playerRepo = RoundPlayerRepository(dbQueue: dbQueue)
        let players = try playerRepo.fetchPlayers(forRound: roundId)
        let myPlayer = players.first(where: { $0.playerPubkey == Self.accountBPubkey })
        XCTAssertEqual(myPlayer?.playerIndex, 1)
    }

    func testJoinRound_RejectsIfMyPubkeyNotInPTags() throws {
        let dbQueue = try makeTestDatabase()
        let service = RoundJoinService(dbQueue: dbQueue)
        let content = makeInitiationContent()

        XCTAssertThrowsError(try service.createLocalRound(
            from: content,
            initiationEventId: "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233",
            date: "2026-02-14",
            playerPubkeys: [Self.accountAPubkey], // Account B not included
            myPubkey: Self.accountBPubkey
        )) { error in
            guard let joinError = error as? RoundJoinError else {
                XCTFail("Expected RoundJoinError, got \(error)")
                return
            }
            if case .notInPlayerList = joinError {
                // Expected
            } else {
                XCTFail("Expected .notInPlayerList, got \(joinError)")
            }
        }
    }

    // MARK: - 5. Repository: Lookup by Initiation Event ID

    func testFetchRoundByInitiationEventId() throws {
        let dbQueue = try makeTestDatabase()
        let service = RoundJoinService(dbQueue: dbQueue)
        let content = makeInitiationContent()
        let eventId = "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233"

        let roundId = try service.createLocalRound(
            from: content,
            initiationEventId: eventId,
            date: "2026-02-14",
            playerPubkeys: [Self.accountAPubkey, Self.accountBPubkey],
            myPubkey: Self.accountBPubkey
        )

        let nostrRepo = RoundNostrRepository(dbQueue: dbQueue)
        let record = try nostrRepo.fetchRound(byInitiationEventId: eventId)
        XCTAssertNotNil(record)
        XCTAssertEqual(record?.roundId, roundId)
    }

    func testFetchRoundByInitiationEventId_NotFound() throws {
        let dbQueue = try makeTestDatabase()
        let nostrRepo = RoundNostrRepository(dbQueue: dbQueue)
        let record = try nostrRepo.fetchRound(byInitiationEventId: "0000000000000000000000000000000000000000000000000000000000000000")
        XCTAssertNil(record)
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
}
