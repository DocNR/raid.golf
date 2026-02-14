// RoundInviteTests.swift
// Gambit Golf
//
// TDD tests for Phase 7A: Round invite sharing.
// Tests nevent encoding/decoding, nostr: URI handling, and QR code generation.

import XCTest
import NostrSDK
@testable import RAID

final class RoundInviteTests: XCTestCase {

    // MARK: - Test Fixtures

    /// A known event ID hex (64 chars) for testing.
    private static let testEventIdHex = "1007f13a9443b9dede6aa178d5ad6fea58b0fbbd311b1e5d2510a888bb2f8466"

    private static let testRelays = [
        "wss://relay.damus.io",
        "wss://nos.lol",
        "wss://relay.nostr.band"
    ]

    // MARK: - nevent Building

    func testBuildInviteNevent_IncludesEventIdAndRelays() throws {
        let nevent = try RoundInviteBuilder.buildNevent(
            eventIdHex: Self.testEventIdHex,
            relays: Self.testRelays
        )

        // Should be a valid nevent1... bech32 string
        XCTAssertTrue(nevent.hasPrefix("nevent1"), "Should start with nevent1, got: \(nevent)")

        // Round-trip: parse it back and verify
        let parsed = try RoundInviteBuilder.parseNevent(nevent: nevent)
        XCTAssertEqual(parsed.eventIdHex, Self.testEventIdHex)
        XCTAssertEqual(parsed.relays.count, Self.testRelays.count)
        for relay in Self.testRelays {
            XCTAssertTrue(parsed.relays.contains(relay), "Missing relay: \(relay)")
        }
    }

    func testBuildInviteNevent_NoRelays() throws {
        let nevent = try RoundInviteBuilder.buildNevent(
            eventIdHex: Self.testEventIdHex,
            relays: []
        )

        XCTAssertTrue(nevent.hasPrefix("nevent1"))

        let parsed = try RoundInviteBuilder.parseNevent(nevent: nevent)
        XCTAssertEqual(parsed.eventIdHex, Self.testEventIdHex)
        XCTAssertTrue(parsed.relays.isEmpty)
    }

    // MARK: - nostr: URI

    func testBuildInviteURI_HasNostrPrefix() throws {
        let nevent = try RoundInviteBuilder.buildNevent(
            eventIdHex: Self.testEventIdHex,
            relays: Self.testRelays
        )

        let uri = RoundInviteBuilder.buildNostrURI(nevent: nevent)

        XCTAssertTrue(uri.hasPrefix("nostr:"), "URI should start with nostr:")
        XCTAssertTrue(uri.hasSuffix(nevent), "URI should end with the nevent string")
        XCTAssertEqual(uri, "nostr:\(nevent)")
    }

    func testParseInviteURI_ExtractsNevent() throws {
        let nevent = try RoundInviteBuilder.buildNevent(
            eventIdHex: Self.testEventIdHex,
            relays: Self.testRelays
        )
        let uri = "nostr:\(nevent)"

        let extracted = RoundInviteBuilder.parseNostrURI(uri: uri)

        XCTAssertEqual(extracted, nevent)
    }

    func testParseInviteURI_RejectsInvalidScheme() {
        let result = RoundInviteBuilder.parseNostrURI(uri: "https://example.com")
        XCTAssertNil(result, "Should reject non-nostr: URIs")
    }

    func testParseInviteURI_RejectsEmptyString() {
        let result = RoundInviteBuilder.parseNostrURI(uri: "")
        XCTAssertNil(result, "Should reject empty string")
    }

    func testParseInviteURI_RejectsNostrPrefixOnly() {
        let result = RoundInviteBuilder.parseNostrURI(uri: "nostr:")
        XCTAssertNil(result, "Should reject nostr: with no payload")
    }

    // MARK: - nevent Parsing

    func testParseNevent_ExtractsEventId() throws {
        // Build a nevent, then parse it
        let nevent = try RoundInviteBuilder.buildNevent(
            eventIdHex: Self.testEventIdHex,
            relays: ["wss://relay.damus.io"]
        )

        let parsed = try RoundInviteBuilder.parseNevent(nevent: nevent)

        XCTAssertEqual(parsed.eventIdHex, Self.testEventIdHex)
        XCTAssertEqual(parsed.relays, ["wss://relay.damus.io"])
    }

    // MARK: - QR Code Generation

    func testQRCodeGeneration_ProducesNonNilImage() throws {
        let nevent = try RoundInviteBuilder.buildNevent(
            eventIdHex: Self.testEventIdHex,
            relays: Self.testRelays
        )
        let uri = RoundInviteBuilder.buildNostrURI(nevent: nevent)

        let image = QRCodeGenerator.generate(from: uri)

        XCTAssertNotNil(image, "QR code should be generated for a valid string")
    }

    func testQRCodeGeneration_EmptyStringReturnsNil() {
        let image = QRCodeGenerator.generate(from: "")
        XCTAssertNil(image, "Empty string should produce nil QR image")
    }
}
