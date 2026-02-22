// CourseEventParserTests.swift
// RAID Golf
//
// Tests for CourseEventParser — parsing kind 33501 events into ParsedCourse models.

import XCTest
import NostrSDK
@testable import RAID

final class CourseEventParserTests: XCTestCase {

    private var testKeys: Keys!

    override func setUpWithError() throws {
        testKeys = Keys.generate()
    }

    // MARK: - Helpers

    private func buildCourseEvent(
        dTag: String = "test-course",
        title: String = "Test Course",
        location: String = "City, State, USA",
        holeCount: Int = 18,
        tees: [(String, Double, Int)] = [("Gold", 74.7, 136)],
        extraTags: [[String]] = [],
        content: String = "A nice course"
    ) async throws -> Event {
        var tags: [Tag] = []
        tags.append(try Tag.parse(data: ["d", dTag]))
        tags.append(try Tag.parse(data: ["title", title]))
        tags.append(try Tag.parse(data: ["location", location]))

        for i in 1...holeCount {
            let par = (i % 3 == 0) ? 3 : 4
            tags.append(try Tag.parse(data: ["hole", "\(i)", "\(par)", "\(i)"]))
        }

        for (name, rating, slope) in tees {
            tags.append(try Tag.parse(data: ["tee", name, String(format: "%.1f", rating), "\(slope)"]))
        }

        for extra in extraTags {
            tags.append(try Tag.parse(data: extra))
        }

        let builder = EventBuilder(kind: Kind(kind: 33501), content: content)
            .tags(tags: tags)
        let signer = NostrSigner.keys(keys: testKeys)
        return try await builder.sign(signer: signer)
    }

    // MARK: - Tests

    func testParse_ValidEvent() async throws {
        let event = try await buildCourseEvent()
        let course = CourseEventParser.parse(event: event)

        XCTAssertNotNil(course)
        XCTAssertEqual(course?.dTag, "test-course")
        XCTAssertEqual(course?.title, "Test Course")
        XCTAssertEqual(course?.location, "City, State, USA")
        XCTAssertEqual(course?.holes.count, 18)
        XCTAssertEqual(course?.tees.count, 1)
        XCTAssertEqual(course?.tees[0].name, "Gold")
        XCTAssertEqual(course?.tees[0].rating, 74.7)
        XCTAssertEqual(course?.tees[0].slope, 136)
        XCTAssertEqual(course?.content, "A nice course")
        XCTAssertEqual(course?.authorHex, testKeys.publicKey().toHex())
    }

    func testParse_MissingTitle_ReturnsNil() async throws {
        var tags: [Tag] = []
        tags.append(try Tag.parse(data: ["d", "test"]))
        tags.append(try Tag.parse(data: ["location", "Somewhere"]))
        for i in 1...18 {
            tags.append(try Tag.parse(data: ["hole", "\(i)", "4", "\(i)"]))
        }
        tags.append(try Tag.parse(data: ["tee", "White", "70.0", "120"]))

        let builder = EventBuilder(kind: Kind(kind: 33501), content: "")
            .tags(tags: tags)
        let signer = NostrSigner.keys(keys: testKeys)
        let event = try await builder.sign(signer: signer)

        XCTAssertNil(CourseEventParser.parse(event: event))
    }

    func testParse_TooFewHoles_ReturnsNil() async throws {
        let event = try await buildCourseEvent(holeCount: 5)
        XCTAssertNil(CourseEventParser.parse(event: event))
    }

    func testParse_9Holes_Succeeds() async throws {
        let event = try await buildCourseEvent(holeCount: 9)
        let course = CourseEventParser.parse(event: event)
        XCTAssertNotNil(course)
        XCTAssertEqual(course?.holes.count, 9)
    }

    func testParse_MultipleTees() async throws {
        let event = try await buildCourseEvent(tees: [
            ("Gold", 74.7, 136),
            ("Black", 72.8, 133),
            ("Green", 69.9, 128),
        ])
        let course = CourseEventParser.parse(event: event)
        XCTAssertEqual(course?.tees.count, 3)
    }

    func testParse_Yardages() async throws {
        let event = try await buildCourseEvent(extraTags: [
            ["yardage", "1", "Gold", "425"],
            ["yardage", "2", "Gold", "380"],
            ["yardage", "1", "Black", "405"],
        ])
        let course = CourseEventParser.parse(event: event)
        XCTAssertEqual(course?.yardages.count, 3)

        let goldYardages = course?.yardages(forTee: "Gold")
        XCTAssertEqual(goldYardages?[1], 425)
        XCTAssertEqual(goldYardages?[2], 380)
    }

    func testParse_OptionalMetadata() async throws {
        let event = try await buildCourseEvent(extraTags: [
            ["country", "US"],
            ["website", "https://example.com"],
            ["architect", "Pete Dye"],
            ["established", "1995"],
        ])
        let course = CourseEventParser.parse(event: event)
        XCTAssertEqual(course?.country, "US")
        XCTAssertEqual(course?.website, "https://example.com")
        XCTAssertEqual(course?.architect, "Pete Dye")
        XCTAssertEqual(course?.established, "1995")
    }

    func testParse_ImageURL() async throws {
        let event = try await buildCourseEvent(extraTags: [
            ["image", "https://image.nostr.build/abc123.jpg"],
        ])
        let course = CourseEventParser.parse(event: event)
        XCTAssertEqual(course?.imageURL, "https://image.nostr.build/abc123.jpg")
    }

    func testParse_NoImageURL() async throws {
        let event = try await buildCourseEvent()
        let course = CourseEventParser.parse(event: event)
        XCTAssertNil(course?.imageURL)
    }

    func testParse_OperatorPubkey() async throws {
        let operatorHex = String(repeating: "f", count: 64)
        let event = try await buildCourseEvent(extraTags: [
            ["p", operatorHex, "", "operator"],
        ])
        let course = CourseEventParser.parse(event: event)
        XCTAssertEqual(course?.operatorPubkey, operatorHex)
    }

    func testParse_EmptyContent() async throws {
        let event = try await buildCourseEvent(content: "")
        let course = CourseEventParser.parse(event: event)
        XCTAssertNil(course?.content)
    }

    func testParse_HolesSortedByNumber() async throws {
        let event = try await buildCourseEvent(holeCount: 18)
        let course = CourseEventParser.parse(event: event)
        XCTAssertNotNil(course)
        for (i, hole) in (course?.holes ?? []).enumerated() {
            XCTAssertEqual(hole.number, i + 1)
        }
    }

    func testTotalPar() async throws {
        let event = try await buildCourseEvent(holeCount: 18)
        let course = CourseEventParser.parse(event: event)
        XCTAssertNotNil(course)
        // par 3 for holes divisible by 3, par 4 otherwise
        // Holes 3,6,9,12,15,18 = par 3 (6 holes), rest = par 4 (12 holes)
        let expectedPar = 6 * 3 + 12 * 4
        XCTAssertEqual(course?.totalPar(), expectedPar)
    }

    func testTotalYardage() async throws {
        let event = try await buildCourseEvent(extraTags: [
            ["yardage", "1", "Gold", "400"],
            ["yardage", "2", "Gold", "350"],
            ["yardage", "3", "Gold", "200"],
        ])
        let course = CourseEventParser.parse(event: event)
        XCTAssertEqual(course?.totalYardage(forTee: "Gold"), 950)
        XCTAssertEqual(course?.totalYardage(forTee: "Silver"), 0)
    }
}
