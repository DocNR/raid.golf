// DMInviteTests.swift
// RAID Golf
//
// Tests for NIP-17 DM invite building, parsing, and gift wrap round-trip.

import XCTest
import NostrSDK
@testable import RAID

final class DMInviteTests: XCTestCase {

    // MARK: - Test Fixtures

    private static let testEventIdHex = "1007f13a9443b9dede6aa178d5ad6fea58b0fbbd311b1e5d2510a888bb2f8466"
    private static let testRelays = [
        "wss://relay.damus.io",
        "wss://nos.lol",
        "wss://relay.nostr.band"
    ]

    private lazy var testNevent: String = {
        try! RoundInviteBuilder.buildNevent(eventIdHex: Self.testEventIdHex, relays: Self.testRelays)
    }()

    // MARK: - Build Invite Rumor

    func testBuildInviteRumor_KindAndContent() throws {
        let senderKeys = Keys.generate()
        let receiverKeys = Keys.generate()

        let rumor = try DMInviteBuilder.buildInviteRumor(
            senderPubkey: senderKeys.publicKey(),
            receiverPubkeyHex: receiverKeys.publicKey().toHex(),
            courseName: "Pine Valley Golf Club",
            nevent: testNevent
        )

        // Kind 14 (NIP-17 private direct message)
        XCTAssertEqual(rumor.kind().asU16(), 14)

        // Content contains the course name
        XCTAssertTrue(rumor.content().contains("Pine Valley Golf Club"))

        // Content contains the nevent
        XCTAssertTrue(rumor.content().contains(testNevent))

        // Author is the sender
        XCTAssertEqual(rumor.author().toHex(), senderKeys.publicKey().toHex())
    }

    func testBuildInviteRumor_ContainsNostrURI() throws {
        let senderKeys = Keys.generate()
        let receiverKeys = Keys.generate()

        let rumor = try DMInviteBuilder.buildInviteRumor(
            senderPubkey: senderKeys.publicKey(),
            receiverPubkeyHex: receiverKeys.publicKey().toHex(),
            courseName: "Test Course",
            nevent: testNevent
        )

        let expectedURI = "nostr:\(testNevent)"
        XCTAssertTrue(rumor.content().contains(expectedURI), "Content should include nostr: URI")
    }

    func testBuildInviteRumor_HasPTag() throws {
        let senderKeys = Keys.generate()
        let receiverKeys = Keys.generate()
        let receiverHex = receiverKeys.publicKey().toHex()

        let rumor = try DMInviteBuilder.buildInviteRumor(
            senderPubkey: senderKeys.publicKey(),
            receiverPubkeyHex: receiverHex,
            courseName: "Test Course",
            nevent: testNevent
        )

        // Check p tag contains receiver pubkey
        let tags = rumor.tags().toVec()
        let pTags = tags.filter { $0.asVec().first == "p" }
        XCTAssertEqual(pTags.count, 1)
        XCTAssertEqual(pTags.first?.asVec()[1], receiverHex)
    }

    // MARK: - Extract Nevent

    func testExtractNevent_FromContent() throws {
        let senderKeys = Keys.generate()
        let receiverKeys = Keys.generate()

        let rumor = try DMInviteBuilder.buildInviteRumor(
            senderPubkey: senderKeys.publicKey(),
            receiverPubkeyHex: receiverKeys.publicKey().toHex(),
            courseName: "Test Course",
            nevent: testNevent
        )

        let extracted = DMInviteBuilder.extractNevent(from: rumor)
        XCTAssertEqual(extracted, testNevent)
    }

    func testExtractNevent_NoNevent_ReturnsNil() {
        let result = DMInviteBuilder.extractNevent(fromContent: "Hello, this is a regular message with no invite.")
        XCTAssertNil(result)
    }

    func testExtractNevent_FromNostrURI() {
        let content = "Check this out: nostr:\(testNevent) - join my round!"
        let extracted = DMInviteBuilder.extractNevent(fromContent: content)
        XCTAssertEqual(extracted, testNevent)
    }

    // MARK: - Round Trip

    func testRoundTrip_BuildAndExtract() throws {
        let senderKeys = Keys.generate()
        let receiverKeys = Keys.generate()

        let rumor = try DMInviteBuilder.buildInviteRumor(
            senderPubkey: senderKeys.publicKey(),
            receiverPubkeyHex: receiverKeys.publicKey().toHex(),
            courseName: "Augusta National",
            nevent: testNevent
        )

        let extracted = DMInviteBuilder.extractNevent(from: rumor)
        XCTAssertNotNil(extracted)

        // Parse both and compare event IDs
        let originalParsed = try RoundInviteBuilder.parseNevent(nevent: testNevent)
        let extractedParsed = try RoundInviteBuilder.parseNevent(nevent: extracted!)
        XCTAssertEqual(originalParsed.eventIdHex, extractedParsed.eventIdHex)
    }

    // MARK: - Course Name Extraction

    func testExtractCourseName() {
        let content = "You've been invited to play golf at Pine Valley Golf Club!\n\nJoin: nostr:nevent1..."
        let name = DMInviteBuilder.extractCourseName(fromContent: content)
        XCTAssertEqual(name, "Pine Valley Golf Club")
    }

    func testExtractCourseName_NoMatch() {
        let content = "Just a regular message with no invite pattern."
        let name = DMInviteBuilder.extractCourseName(fromContent: content)
        XCTAssertNil(name)
    }

    // MARK: - Gift Wrap Round Trip (NIP-59)

    func testGiftWrapRoundTrip() async throws {
        let senderKeys = Keys.generate()
        let receiverKeys = Keys.generate()

        let rumor = try DMInviteBuilder.buildInviteRumor(
            senderPubkey: senderKeys.publicKey(),
            receiverPubkeyHex: receiverKeys.publicKey().toHex(),
            courseName: "Pebble Beach",
            nevent: testNevent
        )

        // Wrap: rumor → seal → gift wrap (SDK handles full NIP-59 flow)
        let signer = NostrSigner.keys(keys: senderKeys)
        let giftWrapEvent = try await giftWrap(
            signer: signer,
            receiverPubkey: receiverKeys.publicKey(),
            rumor: rumor
        )

        // Gift wrap should be kind 1059
        XCTAssertEqual(giftWrapEvent.kind().asU16(), 1059)

        // Unwrap as receiver
        let receiverSigner = NostrSigner.keys(keys: receiverKeys)
        let unwrapped = try await UnwrappedGift.fromGiftWrap(signer: receiverSigner, giftWrap: giftWrapEvent)

        // Sender matches
        XCTAssertEqual(unwrapped.sender().toHex(), senderKeys.publicKey().toHex())

        // Rumor content preserved
        let unwrappedRumor = unwrapped.rumor()
        XCTAssertEqual(unwrappedRumor.kind().asU16(), 14)
        XCTAssertTrue(unwrappedRumor.content().contains("Pebble Beach"))

        // Nevent extractable from unwrapped rumor
        let extracted = DMInviteBuilder.extractNevent(from: unwrappedRumor)
        XCTAssertEqual(extracted, testNevent)
    }

    func testGiftWrapWrongKey_Fails() async throws {
        let senderKeys = Keys.generate()
        let receiverKeys = Keys.generate()
        let wrongKeys = Keys.generate()

        let rumor = try DMInviteBuilder.buildInviteRumor(
            senderPubkey: senderKeys.publicKey(),
            receiverPubkeyHex: receiverKeys.publicKey().toHex(),
            courseName: "Test Course",
            nevent: testNevent
        )

        let signer = NostrSigner.keys(keys: senderKeys)
        let giftWrapEvent = try await giftWrap(
            signer: signer,
            receiverPubkey: receiverKeys.publicKey(),
            rumor: rumor
        )

        // Unwrapping with wrong key should fail
        let wrongSigner = NostrSigner.keys(keys: wrongKeys)
        do {
            _ = try await UnwrappedGift.fromGiftWrap(signer: wrongSigner, giftWrap: giftWrapEvent)
            XCTFail("Should have thrown when unwrapping with wrong key")
        } catch {
            // Expected — decryption fails with wrong key
        }
    }
}
