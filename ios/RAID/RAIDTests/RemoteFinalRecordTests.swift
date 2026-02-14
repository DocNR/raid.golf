// RemoteFinalRecordTests.swift
// Gambit Golf
//
// Tests for Phase 7D: Post-Round (fetch + display final records).
// Covers kind 1502 parsing and combined scorecard building.

import XCTest
@testable import RAID

final class RemoteFinalRecordTests: XCTestCase {

    // MARK: - Fixtures

    private static let initiationEventId = "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233"
    private static let accountAPubkey = "1007f13a9443b9dede6aa178d5ad6fea58b0fbbd311b1e5d2510a888bb2f8466"
    private static let accountBPubkey = "55127fc9e1c03c6b459a3bab72fdb99def1644c5f239bdd09f3e5fb401ed9b21"

    // MARK: - 1. Parse Final Record

    func testParseFinalRecord_ExtractsScores() {
        let tagArrays: [[String]] = [
            ["e", Self.initiationEventId],
            ["total", "40"],
            ["score", "1", "4"],
            ["score", "2", "5"],
            ["score", "3", "3"],
            ["score", "4", "5"],
            ["score", "5", "4"],
            ["score", "6", "6"],
            ["score", "7", "5"],
            ["score", "8", "4"],
            ["score", "9", "4"],
            ["p", Self.accountAPubkey],
            ["t", "golf"],
        ]

        let data = NIP101gEventParser.parseFinalRecord(
            tagArrays: tagArrays,
            authorPubkeyHex: Self.accountAPubkey,
            content: ""
        )

        XCTAssertNotNil(data)
        XCTAssertEqual(data?.scores.count, 9)
        XCTAssertEqual(data?.scores.first(where: { $0.holeNumber == 1 })?.strokes, 4)
        XCTAssertEqual(data?.scores.first(where: { $0.holeNumber == 9 })?.strokes, 4)
        XCTAssertEqual(data?.total, 40)
    }

    func testParseFinalRecord_ExtractsScoredBy() {
        let tagArrays: [[String]] = [
            ["e", Self.initiationEventId],
            ["total", "42"],
            ["scored_by", Self.accountBPubkey],
            ["score", "1", "5"],
            ["p", Self.accountBPubkey],
            ["p", Self.accountAPubkey],
        ]

        let data = NIP101gEventParser.parseFinalRecord(
            tagArrays: tagArrays,
            authorPubkeyHex: Self.accountAPubkey,
            content: ""
        )

        XCTAssertEqual(data?.scoredByPubkey, Self.accountBPubkey)
    }

    func testParseFinalRecord_NoScoredByDefaultsToAuthor() {
        let tagArrays: [[String]] = [
            ["e", Self.initiationEventId],
            ["total", "36"],
            ["score", "1", "4"],
            ["p", Self.accountAPubkey],
        ]

        let data = NIP101gEventParser.parseFinalRecord(
            tagArrays: tagArrays,
            authorPubkeyHex: Self.accountAPubkey,
            content: ""
        )

        XCTAssertNil(data?.scoredByPubkey, "No scored_by tag should return nil")
        XCTAssertEqual(data?.authorPubkeyHex, Self.accountAPubkey)
    }

    func testParseFinalRecord_ExtractsInitiationReference() {
        let tagArrays: [[String]] = [
            ["e", Self.initiationEventId],
            ["total", "36"],
        ]

        let data = NIP101gEventParser.parseFinalRecord(
            tagArrays: tagArrays,
            authorPubkeyHex: Self.accountAPubkey,
            content: ""
        )

        XCTAssertEqual(data?.initiationEventId, Self.initiationEventId)
    }

    // MARK: - 2. Combined Scorecard

    func testCombinedScorecardDisplay_MergesAllPlayers() {
        let playerA = FinalRecordData(
            authorPubkeyHex: Self.accountAPubkey,
            scoredByPubkey: nil,
            initiationEventId: Self.initiationEventId,
            scores: [(1, 4), (2, 5), (3, 3)],
            total: 12,
            notes: nil
        )

        let playerB = FinalRecordData(
            authorPubkeyHex: Self.accountBPubkey,
            scoredByPubkey: nil,
            initiationEventId: Self.initiationEventId,
            scores: [(1, 5), (2, 4), (3, 4)],
            total: 13,
            notes: nil
        )

        let combined = CombinedScorecard(records: [playerA, playerB])

        XCTAssertEqual(combined.players.count, 2)
        XCTAssertEqual(combined.players[0].total, 12)
        XCTAssertEqual(combined.players[1].total, 13)
        XCTAssertEqual(combined.scoreForPlayer(Self.accountAPubkey, hole: 1), 4)
        XCTAssertEqual(combined.scoreForPlayer(Self.accountBPubkey, hole: 1), 5)
    }

    func testFinalRecord_IgnoresDuplicateFromSameAuthor() {
        // Same author, two records — keep the one with higher total (simulating latest)
        let record1 = FinalRecordData(
            authorPubkeyHex: Self.accountAPubkey,
            scoredByPubkey: nil,
            initiationEventId: Self.initiationEventId,
            scores: [(1, 4)],
            total: 4,
            notes: nil
        )

        let record2 = FinalRecordData(
            authorPubkeyHex: Self.accountAPubkey,
            scoredByPubkey: nil,
            initiationEventId: Self.initiationEventId,
            scores: [(1, 4), (2, 5)],
            total: 9,
            notes: nil
        )

        // CombinedScorecard deduplicates — keeps latest (last in array)
        let combined = CombinedScorecard(records: [record1, record2])
        XCTAssertEqual(combined.players.count, 1, "Should deduplicate same-author records")
        XCTAssertEqual(combined.players[0].total, 9, "Should keep latest record")
    }
}
