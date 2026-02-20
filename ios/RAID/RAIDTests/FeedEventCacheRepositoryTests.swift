// FeedEventCacheRepositoryTests.swift
// RAID Golf
//
// Tests for FeedEventCacheRepository — upsert, fetch, prune, delete, edge cases.
// Uses in-memory GRDB database with v13 migration applied inline.
// Test events are created with generated Keys + EventBuilder.signWithKeys.

import XCTest
import GRDB
import NostrSDK
@testable import RAID

final class FeedEventCacheRepositoryTests: XCTestCase {

    private var db: DatabaseQueue!
    private var repo: FeedEventCacheRepository!
    private var keys: Keys!

    override func setUpWithError() throws {
        db = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v13_create_nostr_feed_events") { db in
            try db.execute(sql: """
            CREATE TABLE nostr_feed_events (
                event_id_hex  TEXT NOT NULL PRIMARY KEY CHECK(length(event_id_hex) = 64),
                pubkey_hex    TEXT NOT NULL CHECK(length(pubkey_hex) = 64),
                kind          INTEGER NOT NULL,
                created_at    INTEGER NOT NULL,
                content       TEXT NOT NULL,
                tags_json     TEXT NOT NULL,
                raw_json      TEXT NOT NULL,
                fetched_at    TEXT NOT NULL
            )
            """)
            try db.execute(sql: "CREATE INDEX idx_feed_events_created ON nostr_feed_events(created_at DESC)")
        }
        try migrator.migrate(db)
        repo = FeedEventCacheRepository(dbQueue: db)
        keys = Keys.generate()
    }

    override func tearDownWithError() throws {
        repo = nil
        db = nil
        keys = nil
    }

    // MARK: - Helpers

    private func makeEvent(kind: UInt16 = 1, content: String = "hello", createdAt: UInt64? = nil) throws -> Event {
        var builder = EventBuilder(kind: Kind(kind: kind), content: content)
        if let ts = createdAt {
            builder = builder.customCreatedAt(createdAt: Timestamp.fromSecs(secs: ts))
        }
        return try builder.signWithKeys(keys: keys)
    }

    // MARK: - Upsert + Fetch Roundtrip

    func testUpsert_roundtrip() throws {
        let event = try makeEvent(content: "test roundtrip")
        try repo.upsertEvents([event])

        let fetched = try repo.fetchRecentEvents(limit: 10)
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].id().toHex(), event.id().toHex())
        XCTAssertEqual(fetched[0].content(), "test roundtrip")
    }

    func testFetchRecentEvents_empty_returnsEmpty() throws {
        let fetched = try repo.fetchRecentEvents(limit: 10)
        XCTAssertTrue(fetched.isEmpty)
    }

    func testFetchEvent_byId_returnsCorrectEvent() throws {
        let event = try makeEvent(content: "by id")
        try repo.upsertEvents([event])

        let idHex = event.id().toHex()
        let fetched = try repo.fetchEvent(idHex: idHex)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.content(), "by id")
    }

    func testFetchEvent_missingId_returnsNil() throws {
        let fetched = try repo.fetchEvent(idHex: String(repeating: "a", count: 64))
        XCTAssertNil(fetched)
    }

    // MARK: - Upsert Overwrites

    func testUpsert_sameId_overwritesRawJson() throws {
        let event = try makeEvent(content: "original")
        try repo.upsertEvents([event])

        // Upsert again — raw_json should be updated (fetched_at changes)
        try repo.upsertEvents([event])

        let fetched = try repo.fetchRecentEvents(limit: 10)
        XCTAssertEqual(fetched.count, 1)  // no duplicate
    }

    // MARK: - Batch Upsert

    func testUpsert_multipleEvents_allStored() throws {
        let e1 = try makeEvent(content: "one")
        let e2 = try makeEvent(content: "two")
        let e3 = try makeEvent(content: "three")
        try repo.upsertEvents([e1, e2, e3])

        let fetched = try repo.fetchRecentEvents(limit: 10)
        XCTAssertEqual(fetched.count, 3)
    }

    func testUpsert_emptyArray_noError() throws {
        XCTAssertNoThrow(try repo.upsertEvents([]))
    }

    // MARK: - Ordering

    func testFetchRecentEvents_orderedByCreatedAtDesc() throws {
        let ts: UInt64 = 1_700_000_000
        let older = try makeEvent(content: "older", createdAt: ts)
        let newer = try makeEvent(content: "newer", createdAt: ts + 3600)
        let newest = try makeEvent(content: "newest", createdAt: ts + 7200)

        try repo.upsertEvents([older, newest, newer])  // intentionally out of order

        let fetched = try repo.fetchRecentEvents(limit: 10)
        XCTAssertEqual(fetched.count, 3)
        XCTAssertEqual(fetched[0].content(), "newest")
        XCTAssertEqual(fetched[1].content(), "newer")
        XCTAssertEqual(fetched[2].content(), "older")
    }

    func testFetchRecentEvents_limit_returnsNewest() throws {
        let ts: UInt64 = 1_700_000_000
        for i in 0..<5 {
            let event = try makeEvent(content: "event \(i)", createdAt: ts + UInt64(i * 100))
            try repo.upsertEvents([event])
        }

        let fetched = try repo.fetchRecentEvents(limit: 3)
        XCTAssertEqual(fetched.count, 3)
        XCTAssertEqual(fetched[0].content(), "event 4")
        XCTAssertEqual(fetched[1].content(), "event 3")
        XCTAssertEqual(fetched[2].content(), "event 2")
    }

    // MARK: - Prune

    func testPruneOldEvents_keepsNewest() throws {
        let ts: UInt64 = 1_700_000_000
        for i in 0..<5 {
            let event = try makeEvent(content: "event \(i)", createdAt: ts + UInt64(i * 100))
            try repo.upsertEvents([event])
        }

        try repo.pruneOldEvents(keepCount: 3)

        let fetched = try repo.fetchRecentEvents(limit: 10)
        XCTAssertEqual(fetched.count, 3)
        // Should have kept the 3 newest
        let contents = Set(fetched.map { $0.content() })
        XCTAssertTrue(contents.contains("event 4"))
        XCTAssertTrue(contents.contains("event 3"))
        XCTAssertTrue(contents.contains("event 2"))
        XCTAssertFalse(contents.contains("event 0"))
        XCTAssertFalse(contents.contains("event 1"))
    }

    func testPruneOldEvents_fewerThanKeepCount_noChange() throws {
        let e1 = try makeEvent(content: "one")
        let e2 = try makeEvent(content: "two")
        try repo.upsertEvents([e1, e2])

        try repo.pruneOldEvents(keepCount: 200)

        let fetched = try repo.fetchRecentEvents(limit: 10)
        XCTAssertEqual(fetched.count, 2)
    }

    func testPruneOldEvents_emptyTable_noError() throws {
        XCTAssertNoThrow(try repo.pruneOldEvents(keepCount: 200))
    }

    // MARK: - DeleteAll

    func testDeleteAll_removesAllEntries() throws {
        let e1 = try makeEvent(content: "one")
        let e2 = try makeEvent(content: "two")
        try repo.upsertEvents([e1, e2])

        try repo.deleteAll()

        let fetched = try repo.fetchRecentEvents(limit: 10)
        XCTAssertTrue(fetched.isEmpty)
    }

    func testDeleteAll_emptyTable_noError() throws {
        XCTAssertNoThrow(try repo.deleteAll())
    }

    // MARK: - Multiple Kinds

    func testUpsert_differentKinds_allRoundtrip() throws {
        let kind1 = try makeEvent(kind: 1, content: "text note")
        let kind1502 = try makeEvent(kind: 1502, content: "scorecard")
        let kind1501 = try makeEvent(kind: 1501, content: "{}")
        try repo.upsertEvents([kind1, kind1502, kind1501])

        let fetched = try repo.fetchRecentEvents(limit: 10)
        XCTAssertEqual(fetched.count, 3)

        let kinds = Set(fetched.map { $0.kind().asU16() })
        XCTAssertTrue(kinds.contains(1))
        XCTAssertTrue(kinds.contains(1502))
        XCTAssertTrue(kinds.contains(1501))
    }
}
