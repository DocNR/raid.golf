// CourseFavoritesRepositoryTests.swift
// RAID Golf
//
// Tests for CourseFavoritesRepository — add, remove, isFavorite, replaceAll, composite PK.

import XCTest
import GRDB
@testable import RAID

final class CourseFavoritesRepositoryTests: XCTestCase {

    private var db: DatabaseQueue!
    private var repo: CourseFavoritesRepository!

    private let authorHex = String(repeating: "a", count: 64)
    private let authorHex2 = String(repeating: "b", count: 64)

    override func setUpWithError() throws {
        db = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v17_create_course_favorites") { db in
            try db.execute(sql: """
            CREATE TABLE course_favorites (
                d_tag      TEXT NOT NULL,
                author_hex TEXT NOT NULL CHECK(length(author_hex) = 64),
                added_at   TEXT NOT NULL,
                PRIMARY KEY (d_tag, author_hex)
            )
            """)
        }
        try migrator.migrate(db)
        repo = CourseFavoritesRepository(dbQueue: db)
    }

    override func tearDownWithError() throws {
        db = nil
        repo = nil
    }

    // MARK: - Basic Operations

    func testAddAndFetchAll() throws {
        try repo.add(dTag: "course-1", authorHex: authorHex)
        try repo.add(dTag: "course-2", authorHex: authorHex)

        let all = try repo.fetchAll()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[0].dTag, "course-1")
        XCTAssertEqual(all[1].dTag, "course-2")
    }

    func testAddDuplicateIsNoOp() throws {
        try repo.add(dTag: "course-1", authorHex: authorHex)
        try repo.add(dTag: "course-1", authorHex: authorHex)

        XCTAssertEqual(try repo.count(), 1)
    }

    func testRemove() throws {
        try repo.add(dTag: "course-1", authorHex: authorHex)
        try repo.add(dTag: "course-2", authorHex: authorHex)

        try repo.remove(dTag: "course-1", authorHex: authorHex)

        let all = try repo.fetchAll()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].dTag, "course-2")
    }

    func testIsFavorite() throws {
        try repo.add(dTag: "course-1", authorHex: authorHex)

        XCTAssertTrue(try repo.isFavorite(dTag: "course-1", authorHex: authorHex))
        XCTAssertFalse(try repo.isFavorite(dTag: "course-2", authorHex: authorHex))
    }

    func testCount() throws {
        XCTAssertEqual(try repo.count(), 0)
        XCTAssertTrue(try repo.isEmpty())

        try repo.add(dTag: "course-1", authorHex: authorHex)
        XCTAssertEqual(try repo.count(), 1)
        XCTAssertFalse(try repo.isEmpty())
    }

    func testAllIdentifiers() throws {
        try repo.add(dTag: "course-1", authorHex: authorHex)
        try repo.add(dTag: "course-2", authorHex: authorHex2)

        let ids = try repo.allIdentifiers()
        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(ids[0].dTag, "course-1")
        XCTAssertEqual(ids[0].authorHex, authorHex)
        XCTAssertEqual(ids[1].dTag, "course-2")
        XCTAssertEqual(ids[1].authorHex, authorHex2)
    }

    // MARK: - Composite PK

    func testCompositePK_sameDTagDifferentAuthor() throws {
        try repo.add(dTag: "course-1", authorHex: authorHex)
        try repo.add(dTag: "course-1", authorHex: authorHex2)

        XCTAssertEqual(try repo.count(), 2)
        XCTAssertTrue(try repo.isFavorite(dTag: "course-1", authorHex: authorHex))
        XCTAssertTrue(try repo.isFavorite(dTag: "course-1", authorHex: authorHex2))
    }

    func testCompositePK_differentDTagSameAuthor() throws {
        try repo.add(dTag: "course-1", authorHex: authorHex)
        try repo.add(dTag: "course-2", authorHex: authorHex)

        XCTAssertEqual(try repo.count(), 2)
    }

    // MARK: - ReplaceAll

    func testReplaceAll() throws {
        try repo.add(dTag: "old-1", authorHex: authorHex)
        try repo.add(dTag: "old-2", authorHex: authorHex)

        try repo.replaceAll(identifiers: [
            (dTag: "new-1", authorHex: authorHex),
            (dTag: "new-2", authorHex: authorHex2)
        ])

        let all = try repo.fetchAll()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[0].dTag, "new-1")
        XCTAssertEqual(all[1].dTag, "new-2")
    }

    func testReplaceAllWithEmptyList() throws {
        try repo.add(dTag: "course-1", authorHex: authorHex)

        try repo.replaceAll(identifiers: [])

        XCTAssertEqual(try repo.count(), 0)
    }
}
