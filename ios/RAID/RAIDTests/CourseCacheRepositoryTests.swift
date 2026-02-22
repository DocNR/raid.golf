// CourseCacheRepositoryTests.swift
// RAID Golf
//
// Tests for CourseCacheRepository — upsert, fetch, search, and d-tag dedup.

import XCTest
import GRDB
@testable import RAID

final class CourseCacheRepositoryTests: XCTestCase {

    private var db: DatabaseQueue!
    private var repo: CourseCacheRepository!

    private let authorHex = String(repeating: "a", count: 64)
    private let eventId1 = String(repeating: "b", count: 64)
    private let eventId2 = String(repeating: "c", count: 64)

    override func setUpWithError() throws {
        db = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v15_create_nostr_courses") { db in
            try db.execute(sql: """
            CREATE TABLE nostr_courses (
                d_tag            TEXT NOT NULL,
                author_hex       TEXT NOT NULL CHECK(length(author_hex) = 64),
                title            TEXT NOT NULL,
                location         TEXT NOT NULL,
                country          TEXT,
                hole_count       INTEGER NOT NULL,
                holes_json       TEXT NOT NULL,
                tees_json        TEXT NOT NULL,
                yardages_json    TEXT,
                content          TEXT,
                website          TEXT,
                architect        TEXT,
                established      TEXT,
                operator_pubkey  TEXT,
                event_id_hex     TEXT NOT NULL CHECK(length(event_id_hex) = 64),
                event_created_at INTEGER NOT NULL,
                raw_json         TEXT NOT NULL,
                cached_at        TEXT NOT NULL,
                PRIMARY KEY (d_tag, author_hex)
            )
            """)
            try db.execute(sql: """
            CREATE INDEX idx_nostr_courses_title ON nostr_courses(title COLLATE NOCASE)
            """)
        }
        try migrator.migrate(db)
        repo = CourseCacheRepository(dbQueue: db)
    }

    override func tearDownWithError() throws {
        db = nil
        repo = nil
    }

    // MARK: - Helpers

    private func makeCourse(
        dTag: String = "test-course",
        title: String = "Test Course",
        location: String = "City, State, USA",
        holeCount: Int = 18,
        teeCount: Int = 2,
        eventId: String? = nil,
        eventCreatedAt: UInt64 = 1000
    ) -> ParsedCourse {
        let holes = (1...holeCount).map {
            ParsedCourse.ParsedHole(number: $0, par: $0 % 3 == 0 ? 3 : 4, handicap: $0)
        }
        let tees = (0..<teeCount).map {
            ParsedCourse.ParsedTee(name: "Tee\($0)", rating: 70.0 + Double($0), slope: 120 + $0)
        }
        return ParsedCourse(
            dTag: dTag,
            authorHex: authorHex,
            title: title,
            location: location,
            country: "US",
            holes: holes,
            tees: tees,
            yardages: [],
            content: "A test course",
            website: "https://example.com",
            architect: "Test Architect",
            established: "2020",
            operatorPubkey: nil,
            eventId: eventId ?? eventId1,
            eventCreatedAt: eventCreatedAt
        )
    }

    // MARK: - Tests

    func testUpsert_InsertAndFetch() throws {
        let course = makeCourse()
        try repo.upsertCourses([course], rawJSONs: ["test-course": "{}"])

        let all = try repo.fetchAllCourses()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].title, "Test Course")
        XCTAssertEqual(all[0].location, "City, State, USA")
        XCTAssertEqual(all[0].holes.count, 18)
        XCTAssertEqual(all[0].tees.count, 2)
        XCTAssertEqual(all[0].country, "US")
    }

    func testUpsert_UpdatesExisting() throws {
        let course1 = makeCourse(title: "Original Name")
        try repo.upsertCourses([course1], rawJSONs: ["test-course": "{}"])

        let course2 = makeCourse(title: "Updated Name", eventCreatedAt: 2000)
        try repo.upsertCourses([course2], rawJSONs: ["test-course": "{}"])

        let all = try repo.fetchAllCourses()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].title, "Updated Name")
        XCTAssertEqual(all[0].eventCreatedAt, 2000)
    }

    func testFetchAllCourses_OrderedByTitle() throws {
        let courseB = makeCourse(dTag: "b-course", title: "Beta Course", eventId: eventId1)
        let courseA = makeCourse(dTag: "a-course", title: "Alpha Course", eventId: eventId2)
        try repo.upsertCourses([courseB, courseA], rawJSONs: ["b-course": "{}", "a-course": "{}"])

        let all = try repo.fetchAllCourses()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[0].title, "Alpha Course")
        XCTAssertEqual(all[1].title, "Beta Course")
    }

    func testSearchCourses_ByTitle() throws {
        let course1 = makeCourse(dTag: "fowlers", title: "Fowler's Mill", eventId: eventId1)
        let course2 = makeCourse(dTag: "punderson", title: "Punderson State Park", eventId: eventId2)
        try repo.upsertCourses([course1, course2], rawJSONs: ["fowlers": "{}", "punderson": "{}"])

        let results = repo.searchCourses(query: "fowl")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].dTag, "fowlers")
    }

    func testSearchCourses_ByLocation() throws {
        let course = makeCourse(dTag: "test", title: "Some Course", location: "Cleveland, Ohio, USA")
        try repo.upsertCourses([course], rawJSONs: ["test": "{}"])

        let results = repo.searchCourses(query: "Ohio")
        XCTAssertEqual(results.count, 1)
    }

    func testSearchCourses_NoMatch() throws {
        let course = makeCourse()
        try repo.upsertCourses([course], rawJSONs: ["test-course": "{}"])

        let results = repo.searchCourses(query: "zzzzz")
        XCTAssertEqual(results.count, 0)
    }

    func testFetchCourse_ByDTagAndAuthor() throws {
        let course = makeCourse(dTag: "my-course")
        try repo.upsertCourses([course], rawJSONs: ["my-course": "{}"])

        let found = repo.fetchCourse(dTag: "my-course", authorHex: authorHex)
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.title, "Test Course")

        let notFound = repo.fetchCourse(dTag: "nonexistent", authorHex: authorHex)
        XCTAssertNil(notFound)
    }

    func testDeleteAll() throws {
        let course = makeCourse()
        try repo.upsertCourses([course], rawJSONs: ["test-course": "{}"])
        XCTAssertEqual(try repo.fetchAllCourses().count, 1)

        try repo.deleteAll()
        XCTAssertEqual(try repo.fetchAllCourses().count, 0)
    }

    func testHolesPreserveOrder() throws {
        let course = makeCourse(holeCount: 9)
        try repo.upsertCourses([course], rawJSONs: ["test-course": "{}"])

        let fetched = try repo.fetchAllCourses()
        XCTAssertEqual(fetched[0].holes.count, 9)
        XCTAssertEqual(fetched[0].holes[0].number, 1)
        XCTAssertEqual(fetched[0].holes[8].number, 9)
    }

    func testYardagesRoundTrip() throws {
        let yardages = [
            ParsedCourse.ParsedYardage(hole: 1, tee: "Gold", yards: 425),
            ParsedCourse.ParsedYardage(hole: 2, tee: "Gold", yards: 380),
        ]
        let course = ParsedCourse(
            dTag: "yard-test",
            authorHex: authorHex,
            title: "Yardage Course",
            location: "Somewhere, USA",
            country: nil,
            holes: [
                .init(number: 1, par: 4, handicap: 1),
                .init(number: 2, par: 4, handicap: 2),
            ] + (3...18).map { .init(number: $0, par: 4, handicap: $0) },
            tees: [.init(name: "Gold", rating: 74.7, slope: 136)],
            yardages: yardages,
            content: nil,
            website: nil,
            architect: nil,
            established: nil,
            operatorPubkey: nil,
            eventId: eventId1,
            eventCreatedAt: 1000
        )
        try repo.upsertCourses([course], rawJSONs: ["yard-test": "{}"])

        let fetched = try repo.fetchAllCourses()
        XCTAssertEqual(fetched[0].yardages.count, 2)
        XCTAssertEqual(fetched[0].yardages[0].yards, 425)
        XCTAssertEqual(fetched[0].totalYardage(forTee: "Gold"), 805)
    }
}
