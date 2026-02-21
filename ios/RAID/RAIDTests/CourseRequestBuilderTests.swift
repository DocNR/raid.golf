// CourseRequestBuilderTests.swift
// RAID Golf
//
// Tests for NIP-17 course request DM building and parsing.

import XCTest
import NostrSDK
@testable import RAID

final class CourseRequestBuilderTests: XCTestCase {

    // MARK: - Build Rumor

    func testBuildRumor_KindAndAuthor() throws {
        let senderKeys = Keys.generate()

        let rumor = try CourseRequestBuilder.buildCourseRequestRumor(
            senderPubkey: senderKeys.publicKey(),
            botPubkeyHex: RAIDBot.pubkeyHex,
            courseName: "Shadowmoss Golf & Country Club",
            city: "Charleston",
            state: "SC"
        )

        XCTAssertEqual(rumor.kind().asU16(), 14, "Rumor should be kind 14 (NIP-17 DM)")
        XCTAssertEqual(rumor.author().toHex(), senderKeys.publicKey().toHex())
    }

    func testBuildRumor_ContentContainsHumanReadableHeader() throws {
        let senderKeys = Keys.generate()

        let rumor = try CourseRequestBuilder.buildCourseRequestRumor(
            senderPubkey: senderKeys.publicKey(),
            botPubkeyHex: RAIDBot.pubkeyHex,
            courseName: "Shadowmoss Golf & Country Club",
            city: "Charleston",
            state: "SC"
        )

        let content = rumor.content()
        XCTAssertTrue(content.contains("Course Request: Shadowmoss Golf & Country Club, Charleston, SC"))
        XCTAssertTrue(content.contains("Sent from RAID Golf"))
    }

    func testBuildRumor_ContentContainsJSON() throws {
        let senderKeys = Keys.generate()

        let rumor = try CourseRequestBuilder.buildCourseRequestRumor(
            senderPubkey: senderKeys.publicKey(),
            botPubkeyHex: RAIDBot.pubkeyHex,
            courseName: "Shadowmoss Golf & Country Club",
            city: "Charleston",
            state: "SC"
        )

        let content = rumor.content()
        XCTAssertTrue(content.contains("\"type\":\"course_request\""))
        XCTAssertTrue(content.contains("\"course_name\":\"Shadowmoss Golf & Country Club\""))
        XCTAssertTrue(content.contains("\"city\":\"Charleston\""))
        XCTAssertTrue(content.contains("\"state\":\"SC\""))
    }

    func testBuildRumor_HasBotPTag() throws {
        let senderKeys = Keys.generate()

        let rumor = try CourseRequestBuilder.buildCourseRequestRumor(
            senderPubkey: senderKeys.publicKey(),
            botPubkeyHex: RAIDBot.pubkeyHex,
            courseName: "Test Course",
            city: "Test City",
            state: "TS"
        )

        let tags = try rumor.tags().toVec()
        let pTags = tags.filter { $0.asVec().first == "p" }
        XCTAssertEqual(pTags.count, 1, "Should have exactly one p tag")
        XCTAssertEqual(pTags.first?.asVec()[1], RAIDBot.pubkeyHex, "p tag should contain bot pubkey")
    }

    // MARK: - Build JSON

    func testBuildJSON_ContainsAllFields() {
        let json = CourseRequestBuilder.buildJSON(
            courseName: "Pine Valley",
            city: "Pine Valley",
            state: "NJ"
        )

        XCTAssertTrue(json.contains("\"type\":\"course_request\""))
        XCTAssertTrue(json.contains("\"version\":1"))
        XCTAssertTrue(json.contains("\"course_name\":\"Pine Valley\""))
        XCTAssertTrue(json.contains("\"city\":\"Pine Valley\""))
        XCTAssertTrue(json.contains("\"state\":\"NJ\""))
    }

    func testBuildJSON_SortedKeys() {
        let json = CourseRequestBuilder.buildJSON(
            courseName: "Test",
            city: "City",
            state: "ST"
        )

        // With .sortedKeys, "city" should appear before "course_name"
        guard let cityIndex = json.range(of: "\"city\""),
              let courseIndex = json.range(of: "\"course_name\""),
              let stateIndex = json.range(of: "\"state\""),
              let typeIndex = json.range(of: "\"type\""),
              let versionIndex = json.range(of: "\"version\"") else {
            XCTFail("JSON should contain all keys")
            return
        }
        XCTAssertTrue(cityIndex.lowerBound < courseIndex.lowerBound)
        XCTAssertTrue(courseIndex.lowerBound < stateIndex.lowerBound)
        XCTAssertTrue(stateIndex.lowerBound < typeIndex.lowerBound)
        XCTAssertTrue(typeIndex.lowerBound < versionIndex.lowerBound)
    }

    // MARK: - Extract Course Request

    func testExtractCourseRequest_RoundTrip() throws {
        let senderKeys = Keys.generate()

        let rumor = try CourseRequestBuilder.buildCourseRequestRumor(
            senderPubkey: senderKeys.publicKey(),
            botPubkeyHex: RAIDBot.pubkeyHex,
            courseName: "Fowler's Mill Golf Course",
            city: "Chesterland",
            state: "OH"
        )

        let extracted = CourseRequestBuilder.extractCourseRequest(fromContent: rumor.content())
        XCTAssertNotNil(extracted)
        XCTAssertEqual(extracted?.courseName, "Fowler's Mill Golf Course")
        XCTAssertEqual(extracted?.city, "Chesterland")
        XCTAssertEqual(extracted?.state, "OH")
        XCTAssertEqual(extracted?.version, 1)
    }

    func testExtractCourseRequest_ReturnsNilForNonRequest() {
        let result = CourseRequestBuilder.extractCourseRequest(fromContent: "Just a regular message")
        XCTAssertNil(result)
    }

    func testExtractCourseRequest_ReturnsNilForWrongType() {
        let json = "{\"type\":\"something_else\",\"course_name\":\"Test\",\"city\":\"City\",\"state\":\"ST\"}"
        let result = CourseRequestBuilder.extractCourseRequest(fromContent: "Header\n\n\(json)")
        XCTAssertNil(result)
    }

    func testExtractCourseRequest_HandlesSpecialCharacters() throws {
        let senderKeys = Keys.generate()

        let rumor = try CourseRequestBuilder.buildCourseRequestRumor(
            senderPubkey: senderKeys.publicKey(),
            botPubkeyHex: RAIDBot.pubkeyHex,
            courseName: "TPC Sawgrass - Stadium Course",
            city: "Ponte Vedra Beach",
            state: "FL"
        )

        let extracted = CourseRequestBuilder.extractCourseRequest(fromContent: rumor.content())
        XCTAssertNotNil(extracted)
        XCTAssertEqual(extracted?.courseName, "TPC Sawgrass - Stadium Course")
        XCTAssertEqual(extracted?.city, "Ponte Vedra Beach")
    }

    // MARK: - Website Field

    func testBuildJSON_IncludesWebsiteWhenProvided() {
        let json = CourseRequestBuilder.buildJSON(
            courseName: "Test",
            city: "City",
            state: "ST",
            website: "https://testgolf.com"
        )
        XCTAssertTrue(json.contains("\"website\":\"https:\\/\\/testgolf.com\""))
    }

    func testBuildJSON_OmitsWebsiteWhenNil() {
        let json = CourseRequestBuilder.buildJSON(
            courseName: "Test",
            city: "City",
            state: "ST"
        )
        XCTAssertFalse(json.contains("website"))
    }

    func testExtractCourseRequest_RoundTripWithWebsite() throws {
        let senderKeys = Keys.generate()

        let rumor = try CourseRequestBuilder.buildCourseRequestRumor(
            senderPubkey: senderKeys.publicKey(),
            botPubkeyHex: RAIDBot.pubkeyHex,
            courseName: "Shadowmoss Golf & Country Club",
            city: "Charleston",
            state: "SC",
            website: "https://shadowmoss.com"
        )

        let extracted = CourseRequestBuilder.extractCourseRequest(fromContent: rumor.content())
        XCTAssertNotNil(extracted)
        XCTAssertEqual(extracted?.website, "https://shadowmoss.com")
    }

    func testExtractCourseRequest_WebsiteIsNilWhenNotProvided() throws {
        let senderKeys = Keys.generate()

        let rumor = try CourseRequestBuilder.buildCourseRequestRumor(
            senderPubkey: senderKeys.publicKey(),
            botPubkeyHex: RAIDBot.pubkeyHex,
            courseName: "Test Course",
            city: "City",
            state: "ST"
        )

        let extracted = CourseRequestBuilder.extractCourseRequest(fromContent: rumor.content())
        XCTAssertNotNil(extracted)
        XCTAssertNil(extracted?.website)
    }

    // MARK: - RAIDBot Config

    func testRAIDBotPubkeyIsValid() {
        XCTAssertEqual(RAIDBot.pubkeyHex.count, 64, "Bot pubkey should be 64-char hex")
        let validHex = CharacterSet(charactersIn: "0123456789abcdef")
        XCTAssertTrue(
            RAIDBot.pubkeyHex.unicodeScalars.allSatisfy { validHex.contains($0) },
            "Bot pubkey should be valid hex"
        )
    }
}
