// ClubhouseRepositoryTests.swift
// RAID Golf
//
// Tests for ClubhouseRepository — add, remove, replace, membership checks.
// Uses in-memory GRDB database with v10 migration applied inline.

import XCTest
import GRDB
@testable import RAID

final class ClubhouseRepositoryTests: XCTestCase {

    private var db: DatabaseQueue!
    private var repo: ClubhouseRepository!

    private let pubkey1 = String(repeating: "a", count: 64)
    private let pubkey2 = String(repeating: "b", count: 64)
    private let pubkey3 = String(repeating: "c", count: 64)

    override func setUpWithError() throws {
        db = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v10_create_clubhouse_members") { db in
            try db.execute(sql: """
            CREATE TABLE clubhouse_members (
                pubkey_hex TEXT NOT NULL PRIMARY KEY CHECK(length(pubkey_hex) = 64),
                added_at   TEXT NOT NULL
            )
            """)
        }
        try migrator.migrate(db)
        repo = ClubhouseRepository(dbQueue: db)
    }

    override func tearDownWithError() throws {
        repo = nil
        db = nil
    }

    // MARK: - Add + Fetch

    func testAdd_and_fetchAll() throws {
        try repo.add(pubkeyHex: pubkey1)
        try repo.add(pubkeyHex: pubkey2)

        let all = try repo.fetchAll()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[0].pubkeyHex, pubkey1)
        XCTAssertEqual(all[1].pubkeyHex, pubkey2)
    }

    func testAdd_duplicateIsNoOp() throws {
        try repo.add(pubkeyHex: pubkey1)
        try repo.add(pubkeyHex: pubkey1)

        let count = try repo.count()
        XCTAssertEqual(count, 1)
    }

    func testAllPubkeyHexes() throws {
        try repo.add(pubkeyHex: pubkey1)
        try repo.add(pubkeyHex: pubkey2)

        let hexes = try repo.allPubkeyHexes()
        XCTAssertEqual(hexes.count, 2)
        XCTAssertTrue(hexes.contains(pubkey1))
        XCTAssertTrue(hexes.contains(pubkey2))
    }

    // MARK: - Remove

    func testRemove() throws {
        try repo.add(pubkeyHex: pubkey1)
        try repo.add(pubkeyHex: pubkey2)
        try repo.remove(pubkeyHex: pubkey1)

        let all = try repo.allPubkeyHexes()
        XCTAssertEqual(all, [pubkey2])
    }

    func testRemove_nonExistentIsNoOp() throws {
        try repo.remove(pubkeyHex: pubkey1)
        let count = try repo.count()
        XCTAssertEqual(count, 0)
    }

    // MARK: - Membership

    func testIsMember() throws {
        try repo.add(pubkeyHex: pubkey1)

        XCTAssertTrue(try repo.isMember(pubkeyHex: pubkey1))
        XCTAssertFalse(try repo.isMember(pubkeyHex: pubkey2))
    }

    // MARK: - Replace All

    func testReplaceAll() throws {
        try repo.add(pubkeyHex: pubkey1)
        try repo.add(pubkeyHex: pubkey2)

        try repo.replaceAll(pubkeyHexes: [pubkey2, pubkey3])

        let all = try repo.allPubkeyHexes()
        XCTAssertEqual(all.count, 2)
        XCTAssertFalse(all.contains(pubkey1))
        XCTAssertTrue(all.contains(pubkey2))
        XCTAssertTrue(all.contains(pubkey3))
    }

    func testReplaceAll_withEmptyArrayClearsAll() throws {
        try repo.add(pubkeyHex: pubkey1)
        try repo.replaceAll(pubkeyHexes: [])

        XCTAssertTrue(try repo.isEmpty())
    }

    // MARK: - Count + Empty

    func testCount() throws {
        XCTAssertEqual(try repo.count(), 0)

        try repo.add(pubkeyHex: pubkey1)
        XCTAssertEqual(try repo.count(), 1)

        try repo.add(pubkeyHex: pubkey2)
        XCTAssertEqual(try repo.count(), 2)
    }

    func testIsEmpty() throws {
        XCTAssertTrue(try repo.isEmpty())

        try repo.add(pubkeyHex: pubkey1)
        XCTAssertFalse(try repo.isEmpty())
    }
}
