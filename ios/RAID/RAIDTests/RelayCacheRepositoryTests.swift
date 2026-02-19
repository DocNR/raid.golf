// RelayCacheRepositoryTests.swift
// RAID Golf
//
// Tests for RelayCacheRepository — upsert, fetch, delete, marker semantics, and batch operations.
// Uses in-memory GRDB database with v11 migration applied inline.

import XCTest
import GRDB
@testable import RAID

final class RelayCacheRepositoryTests: XCTestCase {

    private var db: DatabaseQueue!
    private var repo: RelayCacheRepository!

    // Valid 64-char hex pubkeys for tests
    private let pubkey1 = String(repeating: "a", count: 64)
    private let pubkey2 = String(repeating: "b", count: 64)
    private let pubkey3 = String(repeating: "c", count: 64)

    private let sampleRelays: [CachedRelayEntry] = [
        CachedRelayEntry(url: "wss://relay.damus.io", marker: nil),
        CachedRelayEntry(url: "wss://nos.lol", marker: "write"),
        CachedRelayEntry(url: "wss://purplepag.es", marker: "read")
    ]

    override func setUpWithError() throws {
        db = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v11_create_nostr_relay_lists") { db in
            try db.execute(sql: """
            CREATE TABLE nostr_relay_lists (
                pubkey_hex TEXT NOT NULL PRIMARY KEY CHECK(length(pubkey_hex) = 64),
                relay_json TEXT NOT NULL,
                cached_at  TEXT NOT NULL
            )
            """)
        }
        try migrator.migrate(db)
        repo = RelayCacheRepository(dbQueue: db)
    }

    override func tearDownWithError() throws {
        repo = nil
        db = nil
    }

    // MARK: - Upsert + Fetch Roundtrip

    func testUpsert_roundtrip() throws {
        let list = CachedRelayList(pubkeyHex: pubkey1, relays: sampleRelays, cachedAt: Date())
        try repo.upsertRelayList(list)

        let fetched = try repo.fetchRelayList(pubkeyHex: pubkey1)
        let result = try XCTUnwrap(fetched)

        XCTAssertEqual(result.pubkeyHex, pubkey1)
        XCTAssertEqual(result.relays.count, 3)
        XCTAssertEqual(result.relays[0].url, "wss://relay.damus.io")
        XCTAssertNil(result.relays[0].marker)
        XCTAssertEqual(result.relays[1].url, "wss://nos.lol")
        XCTAssertEqual(result.relays[1].marker, "write")
        XCTAssertEqual(result.relays[2].url, "wss://purplepag.es")
        XCTAssertEqual(result.relays[2].marker, "read")
    }

    // MARK: - Upsert Updates on Conflict

    func testUpsert_updatesOnConflict() throws {
        let original = CachedRelayList(
            pubkeyHex: pubkey1,
            relays: [CachedRelayEntry(url: "wss://old-relay.com", marker: nil)],
            cachedAt: Date()
        )
        try repo.upsertRelayList(original)

        let updated = CachedRelayList(
            pubkeyHex: pubkey1,
            relays: sampleRelays,
            cachedAt: Date()
        )
        try repo.upsertRelayList(updated)

        let fetched = try repo.fetchRelayList(pubkeyHex: pubkey1)
        let result = try XCTUnwrap(fetched)

        XCTAssertEqual(result.relays.count, 3)
        XCTAssertEqual(result.relays[0].url, "wss://relay.damus.io")
    }

    // MARK: - Batch Upsert

    func testBatchUpsert() throws {
        let lists = [
            CachedRelayList(pubkeyHex: pubkey1, relays: sampleRelays, cachedAt: Date()),
            CachedRelayList(pubkeyHex: pubkey2, relays: [CachedRelayEntry(url: "wss://nos.lol", marker: nil)], cachedAt: Date()),
            CachedRelayList(pubkeyHex: pubkey3, relays: [CachedRelayEntry(url: "wss://relay.nostr.band", marker: "write")], cachedAt: Date())
        ]

        try repo.upsertRelayLists(lists)

        let fetched1 = try repo.fetchRelayList(pubkeyHex: pubkey1)
        XCTAssertEqual(try XCTUnwrap(fetched1).relays.count, 3)

        let fetched2 = try repo.fetchRelayList(pubkeyHex: pubkey2)
        XCTAssertEqual(try XCTUnwrap(fetched2).relays.count, 1)

        let fetched3 = try repo.fetchRelayList(pubkeyHex: pubkey3)
        XCTAssertEqual(try XCTUnwrap(fetched3).relays.count, 1)
    }

    func testBatchUpsert_emptyArrayIsNoOp() throws {
        try repo.upsertRelayLists([])
        let result = try repo.fetchRelayList(pubkeyHex: pubkey1)
        XCTAssertNil(result)
    }

    // MARK: - Fetch

    func testFetchRelayList_returnsNilIfNotCached() throws {
        let result = try repo.fetchRelayList(pubkeyHex: pubkey1)
        XCTAssertNil(result)
    }

    func testFetchRelayLists_batch() throws {
        let lists = [
            CachedRelayList(pubkeyHex: pubkey1, relays: sampleRelays, cachedAt: Date()),
            CachedRelayList(pubkeyHex: pubkey2, relays: [CachedRelayEntry(url: "wss://nos.lol", marker: nil)], cachedAt: Date()),
            CachedRelayList(pubkeyHex: pubkey3, relays: [CachedRelayEntry(url: "wss://relay.nostr.band", marker: "write")], cachedAt: Date())
        ]
        try repo.upsertRelayLists(lists)

        let fetched = try repo.fetchRelayLists(pubkeyHexes: [pubkey1, pubkey3])

        XCTAssertEqual(fetched.count, 2)
        XCTAssertEqual(fetched[pubkey1]?.relays.count, 3)
        XCTAssertEqual(fetched[pubkey3]?.relays.count, 1)
        XCTAssertNil(fetched[pubkey2])
    }

    func testFetchRelayLists_emptyInput() throws {
        let fetched = try repo.fetchRelayLists(pubkeyHexes: [])
        XCTAssertTrue(fetched.isEmpty)
    }

    // MARK: - Write Relays Convenience

    func testWriteRelays_filtersCorrectly() throws {
        let list = CachedRelayList(pubkeyHex: pubkey1, relays: sampleRelays, cachedAt: Date())
        try repo.upsertRelayList(list)

        let writeRelays = try repo.writeRelays(forPubkey: pubkey1)

        // "wss://relay.damus.io" (nil marker = both → isWrite) and "wss://nos.lol" ("write" → isWrite)
        XCTAssertEqual(writeRelays.count, 2)
        XCTAssertTrue(writeRelays.contains(where: { $0.url == "wss://relay.damus.io" }))
        XCTAssertTrue(writeRelays.contains(where: { $0.url == "wss://nos.lol" }))
        // "wss://purplepag.es" ("read") should NOT be included
        XCTAssertFalse(writeRelays.contains(where: { $0.url == "wss://purplepag.es" }))
    }

    func testWriteRelays_returnsEmptyIfNotCached() throws {
        let writeRelays = try repo.writeRelays(forPubkey: pubkey1)
        XCTAssertTrue(writeRelays.isEmpty)
    }

    // MARK: - Delete

    func testDelete_removesSingleEntry() throws {
        let lists = [
            CachedRelayList(pubkeyHex: pubkey1, relays: sampleRelays, cachedAt: Date()),
            CachedRelayList(pubkeyHex: pubkey2, relays: [CachedRelayEntry(url: "wss://nos.lol", marker: nil)], cachedAt: Date())
        ]
        try repo.upsertRelayLists(lists)

        try repo.delete(pubkeyHex: pubkey1)

        XCTAssertNil(try repo.fetchRelayList(pubkeyHex: pubkey1))
        XCTAssertNotNil(try repo.fetchRelayList(pubkeyHex: pubkey2))
    }

    func testDelete_nonExistentIsNoOp() throws {
        // Should not throw
        try repo.delete(pubkeyHex: pubkey1)
    }

    func testDeleteAll() throws {
        let lists = [
            CachedRelayList(pubkeyHex: pubkey1, relays: sampleRelays, cachedAt: Date()),
            CachedRelayList(pubkeyHex: pubkey2, relays: [CachedRelayEntry(url: "wss://nos.lol", marker: nil)], cachedAt: Date()),
            CachedRelayList(pubkeyHex: pubkey3, relays: [CachedRelayEntry(url: "wss://relay.nostr.band", marker: "write")], cachedAt: Date())
        ]
        try repo.upsertRelayLists(lists)

        try repo.deleteAll()

        XCTAssertNil(try repo.fetchRelayList(pubkeyHex: pubkey1))
        XCTAssertNil(try repo.fetchRelayList(pubkeyHex: pubkey2))
        XCTAssertNil(try repo.fetchRelayList(pubkeyHex: pubkey3))
    }

    // MARK: - Marker Semantics

    func testMarkerNil_isBothReadAndWrite() {
        let entry = CachedRelayEntry(url: "wss://relay.damus.io", marker: nil)
        XCTAssertTrue(entry.isRead)
        XCTAssertTrue(entry.isWrite)
    }

    func testMarkerRead_isReadOnly() {
        let entry = CachedRelayEntry(url: "wss://purplepag.es", marker: "read")
        XCTAssertTrue(entry.isRead)
        XCTAssertFalse(entry.isWrite)
    }

    func testMarkerWrite_isWriteOnly() {
        let entry = CachedRelayEntry(url: "wss://nos.lol", marker: "write")
        XCTAssertFalse(entry.isRead)
        XCTAssertTrue(entry.isWrite)
    }

    // MARK: - CachedRelayList Computed Properties

    func testCachedRelayList_computedProperties() {
        let list = CachedRelayList(pubkeyHex: pubkey1, relays: sampleRelays, cachedAt: Date())

        XCTAssertEqual(list.writeRelays.count, 2)  // nil + "write"
        XCTAssertEqual(list.readRelays.count, 2)    // nil + "read"
    }

    // MARK: - JSON Encoding Roundtrip

    func testJSONEncoding_roundtrip() throws {
        let entries: [CachedRelayEntry] = [
            CachedRelayEntry(url: "wss://relay.damus.io", marker: nil),
            CachedRelayEntry(url: "wss://nos.lol", marker: "write"),
            CachedRelayEntry(url: "wss://purplepag.es", marker: "read")
        ]

        let data = try JSONEncoder().encode(entries)
        let decoded = try JSONDecoder().decode([CachedRelayEntry].self, from: data)

        XCTAssertEqual(entries, decoded)
    }
}
