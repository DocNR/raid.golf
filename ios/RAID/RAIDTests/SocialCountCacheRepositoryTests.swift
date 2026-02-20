// SocialCountCacheRepositoryTests.swift
// RAID Golf
//
// Tests for SocialCountCacheRepository — reaction counts, comment counts,
// own-reaction tracking, upsert/fetch/delete. Uses in-memory GRDB with v14 migration.

import XCTest
import GRDB
@testable import RAID

final class SocialCountCacheRepositoryTests: XCTestCase {

    private var db: DatabaseQueue!
    private var repo: SocialCountCacheRepository!

    override func setUpWithError() throws {
        db = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v14_create_social_count_caches") { db in
            try db.execute(sql: """
            CREATE TABLE nostr_reaction_counts (
                event_id_hex  TEXT NOT NULL PRIMARY KEY CHECK(length(event_id_hex) = 64),
                count         INTEGER NOT NULL DEFAULT 0,
                own_reacted   INTEGER NOT NULL DEFAULT 0,
                cached_at     TEXT NOT NULL
            )
            """)
            try db.execute(sql: """
            CREATE TABLE nostr_comment_counts (
                event_id_hex  TEXT NOT NULL PRIMARY KEY CHECK(length(event_id_hex) = 64),
                count         INTEGER NOT NULL DEFAULT 0,
                cached_at     TEXT NOT NULL
            )
            """)
        }
        try migrator.migrate(db)
        repo = SocialCountCacheRepository(dbQueue: db)
    }

    override func tearDownWithError() throws {
        repo = nil
        db = nil
    }

    // MARK: - Helpers

    private func hexId(_ suffix: String) -> String {
        String(repeating: "0", count: 64 - suffix.count) + suffix
    }

    // MARK: - Reaction Counts

    func testUpsertReactionCounts_roundtrip() throws {
        let id1 = hexId("a1")
        let id2 = hexId("a2")
        try repo.upsertReactionCounts([id1: 5, id2: 3], ownReacted: [id1])

        let result = try repo.fetchReactionCounts(eventIds: [id1, id2])
        XCTAssertEqual(result.counts[id1], 5)
        XCTAssertEqual(result.counts[id2], 3)
        XCTAssertTrue(result.ownReacted.contains(id1))
        XCTAssertFalse(result.ownReacted.contains(id2))
    }

    func testUpsertReactionCounts_overwritesOnConflict() throws {
        let id = hexId("b1")
        try repo.upsertReactionCounts([id: 2], ownReacted: [])
        try repo.upsertReactionCounts([id: 10], ownReacted: [id])

        let result = try repo.fetchReactionCounts(eventIds: [id])
        XCTAssertEqual(result.counts[id], 10)
        XCTAssertTrue(result.ownReacted.contains(id))
    }

    func testFetchReactionCounts_emptyInput_returnsEmpty() throws {
        let result = try repo.fetchReactionCounts(eventIds: [])
        XCTAssertTrue(result.counts.isEmpty)
        XCTAssertTrue(result.ownReacted.isEmpty)
    }

    func testFetchReactionCounts_missingIds_returnsPartial() throws {
        let id1 = hexId("c1")
        let id2 = hexId("c2")
        try repo.upsertReactionCounts([id1: 7], ownReacted: [])

        let result = try repo.fetchReactionCounts(eventIds: [id1, id2])
        XCTAssertEqual(result.counts[id1], 7)
        XCTAssertNil(result.counts[id2])
    }

    // MARK: - Comment Counts

    func testUpsertCommentCounts_roundtrip() throws {
        let id1 = hexId("d1")
        let id2 = hexId("d2")
        try repo.upsertCommentCounts([id1: 12, id2: 0])

        let result = try repo.fetchCommentCounts(eventIds: [id1, id2])
        XCTAssertEqual(result[id1], 12)
        XCTAssertEqual(result[id2], 0)
    }

    func testUpsertCommentCounts_overwritesOnConflict() throws {
        let id = hexId("e1")
        try repo.upsertCommentCounts([id: 3])
        try repo.upsertCommentCounts([id: 8])

        let result = try repo.fetchCommentCounts(eventIds: [id])
        XCTAssertEqual(result[id], 8)
    }

    func testFetchCommentCounts_emptyInput_returnsEmpty() throws {
        let result = try repo.fetchCommentCounts(eventIds: [])
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Delete All

    func testDeleteAll_removesReactionsAndComments() throws {
        let id = hexId("f1")
        try repo.upsertReactionCounts([id: 5], ownReacted: [id])
        try repo.upsertCommentCounts([id: 3])

        try repo.deleteAll()

        let reactions = try repo.fetchReactionCounts(eventIds: [id])
        XCTAssertTrue(reactions.counts.isEmpty)
        let comments = try repo.fetchCommentCounts(eventIds: [id])
        XCTAssertTrue(comments.isEmpty)
    }

    func testDeleteAll_emptyTables_noError() throws {
        XCTAssertNoThrow(try repo.deleteAll())
    }

    // MARK: - Empty Upsert

    func testUpsertReactionCounts_emptyDict_noError() throws {
        XCTAssertNoThrow(try repo.upsertReactionCounts([:], ownReacted: []))
    }

    func testUpsertCommentCounts_emptyDict_noError() throws {
        XCTAssertNoThrow(try repo.upsertCommentCounts([:]))
    }
}
