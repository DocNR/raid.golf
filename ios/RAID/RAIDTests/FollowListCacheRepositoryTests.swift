// FollowListCacheRepositoryTests.swift
// RAID Golf
//
// Tests for FollowListCacheRepository — upsert, fetch, TTL, delete, edge cases.
// Uses in-memory GRDB database with v12 migration applied inline.

import XCTest
import GRDB
@testable import RAID

final class FollowListCacheRepositoryTests: XCTestCase {

    private var db: DatabaseQueue!
    private var repo: FollowListCacheRepository!

    private let pubkey1 = String(repeating: "a", count: 64)
    private let pubkey2 = String(repeating: "b", count: 64)

    private let sampleFollows = [
        String(repeating: "1", count: 64),
        String(repeating: "2", count: 64),
        String(repeating: "3", count: 64)
    ]

    override func setUpWithError() throws {
        db = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v12_create_nostr_follow_lists") { db in
            try db.execute(sql: """
            CREATE TABLE nostr_follow_lists (
                pubkey_hex        TEXT NOT NULL PRIMARY KEY CHECK(length(pubkey_hex) = 64),
                follows_json      TEXT NOT NULL,
                event_created_at  INTEGER NOT NULL,
                cached_at         TEXT NOT NULL
            )
            """)
        }
        try migrator.migrate(db)
        repo = FollowListCacheRepository(dbQueue: db)
    }

    override func tearDownWithError() throws {
        repo = nil
        db = nil
    }

    // MARK: - Upsert + Fetch Roundtrip

    func testUpsert_roundtrip() throws {
        let list = CachedFollowList(
            pubkeyHex: pubkey1,
            follows: sampleFollows,
            eventCreatedAt: 1_700_000_000,
            cachedAt: Date()
        )
        try repo.upsert(list)

        let fetched = try repo.fetch(pubkeyHex: pubkey1)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.pubkeyHex, pubkey1)
        XCTAssertEqual(fetched?.follows, sampleFollows)
        XCTAssertEqual(fetched?.eventCreatedAt, 1_700_000_000)
    }

    func testFetch_missingKey_returnsNil() throws {
        let result = try repo.fetch(pubkeyHex: pubkey1)
        XCTAssertNil(result)
    }

    // MARK: - Upsert Overwrites

    func testUpsert_overwritesExisting() throws {
        let first = CachedFollowList(
            pubkeyHex: pubkey1,
            follows: sampleFollows,
            eventCreatedAt: 100,
            cachedAt: Date()
        )
        try repo.upsert(first)

        let newFollows = [String(repeating: "4", count: 64)]
        let second = CachedFollowList(
            pubkeyHex: pubkey1,
            follows: newFollows,
            eventCreatedAt: 200,
            cachedAt: Date()
        )
        try repo.upsert(second)

        let fetched = try repo.fetch(pubkeyHex: pubkey1)
        XCTAssertEqual(fetched?.follows, newFollows)
        XCTAssertEqual(fetched?.eventCreatedAt, 200)
    }

    // MARK: - TTL Check

    func testCachedAt_withinTTL_isValid() throws {
        let list = CachedFollowList(
            pubkeyHex: pubkey1,
            follows: sampleFollows,
            eventCreatedAt: 0,
            cachedAt: Date()
        )
        try repo.upsert(list)

        let fetched = try repo.fetch(pubkeyHex: pubkey1)
        XCTAssertNotNil(fetched)
        let ttl: TimeInterval = 60 * 60
        XCTAssertLessThan(Date().timeIntervalSince(fetched!.cachedAt), ttl)
    }

    func testCachedAt_expiredTTL_detectedByCallerLogic() throws {
        let oldDate = Date(timeIntervalSinceNow: -(60 * 61))  // 61 minutes ago
        let list = CachedFollowList(
            pubkeyHex: pubkey1,
            follows: sampleFollows,
            eventCreatedAt: 0,
            cachedAt: oldDate
        )
        try repo.upsert(list)

        let fetched = try repo.fetch(pubkeyHex: pubkey1)
        XCTAssertNotNil(fetched)
        let ttl: TimeInterval = 60 * 60
        XCTAssertGreaterThan(Date().timeIntervalSince(fetched!.cachedAt), ttl)
    }

    // MARK: - Empty Follows

    func testUpsert_emptyFollowList_roundtrips() throws {
        let list = CachedFollowList(
            pubkeyHex: pubkey1,
            follows: [],
            eventCreatedAt: 0,
            cachedAt: Date()
        )
        try repo.upsert(list)

        let fetched = try repo.fetch(pubkeyHex: pubkey1)
        XCTAssertEqual(fetched?.follows, [])
    }

    // MARK: - Multiple Keys

    func testMultipleKeys_independentEntries() throws {
        let list1 = CachedFollowList(pubkeyHex: pubkey1, follows: sampleFollows, eventCreatedAt: 1, cachedAt: Date())
        let list2 = CachedFollowList(pubkeyHex: pubkey2, follows: [String(repeating: "9", count: 64)], eventCreatedAt: 2, cachedAt: Date())
        try repo.upsert(list1)
        try repo.upsert(list2)

        XCTAssertEqual(try repo.fetch(pubkeyHex: pubkey1)?.follows, sampleFollows)
        XCTAssertEqual(try repo.fetch(pubkeyHex: pubkey2)?.follows.count, 1)
    }

    // MARK: - DeleteAll

    func testDeleteAll_removesAllEntries() throws {
        try repo.upsert(CachedFollowList(pubkeyHex: pubkey1, follows: sampleFollows, eventCreatedAt: 0, cachedAt: Date()))
        try repo.upsert(CachedFollowList(pubkeyHex: pubkey2, follows: sampleFollows, eventCreatedAt: 0, cachedAt: Date()))

        try repo.deleteAll()

        XCTAssertNil(try repo.fetch(pubkeyHex: pubkey1))
        XCTAssertNil(try repo.fetch(pubkeyHex: pubkey2))
    }

    func testDeleteAll_emptyTable_noError() throws {
        XCTAssertNoThrow(try repo.deleteAll())
    }

    // MARK: - Large Follow List

    func testUpsert_largeFollowList_roundtrips() throws {
        let bigList = (0..<500).map { i -> String in
            String(format: "%064x", i)
        }
        let list = CachedFollowList(pubkeyHex: pubkey1, follows: bigList, eventCreatedAt: 0, cachedAt: Date())
        try repo.upsert(list)

        let fetched = try repo.fetch(pubkeyHex: pubkey1)
        XCTAssertEqual(fetched?.follows.count, 500)
        XCTAssertEqual(fetched?.follows, bigList)
    }
}
