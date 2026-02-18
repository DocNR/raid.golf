// NostrServiceTests.swift
// RAID Golf
//
// Tests for NostrService read infrastructure: profile parsing, follow list extraction.
// Network-dependent tests are separated and can be skipped in CI.

import XCTest
import NostrSDK
@testable import RAID

final class NostrServiceTests: XCTestCase {

    private let service = NostrService()

    override func setUp() {
        super.setUp()
        // Enable Nostr activation gate so service methods contact relays
        UserDefaults.standard.set(true, forKey: "nostrActivated")
    }

    // MARK: - NostrProfile Parsing

    func testParseProfile_AllFields() {
        let json = """
        {"name":"alice","display_name":"Alice Q.","picture":"https://example.com/alice.jpg","about":"golfer"}
        """

        let profile = NostrProfile.parse(from: json, pubkeyHex: "aabbccdd")

        XCTAssertEqual(profile.pubkeyHex, "aabbccdd")
        XCTAssertEqual(profile.name, "alice")
        XCTAssertEqual(profile.displayName, "Alice Q.")
        XCTAssertEqual(profile.picture, "https://example.com/alice.jpg")
    }

    func testParseProfile_NameOnly() {
        let json = """
        {"name":"bob"}
        """

        let profile = NostrProfile.parse(from: json, pubkeyHex: "11223344")

        XCTAssertEqual(profile.name, "bob")
        XCTAssertNil(profile.displayName)
        XCTAssertNil(profile.picture)
    }

    func testParseProfile_EmptyJSON() {
        let json = "{}"

        let profile = NostrProfile.parse(from: json, pubkeyHex: "deadbeef")

        XCTAssertNil(profile.name)
        XCTAssertNil(profile.displayName)
        XCTAssertNil(profile.picture)
        XCTAssertEqual(profile.pubkeyHex, "deadbeef")
    }

    func testParseProfile_InvalidJSON() {
        let profile = NostrProfile.parse(from: "not json at all", pubkeyHex: "abcd1234")

        XCTAssertNil(profile.name)
        XCTAssertNil(profile.displayName)
        XCTAssertNil(profile.picture)
        XCTAssertEqual(profile.pubkeyHex, "abcd1234")
    }

    func testParseProfile_EmptyString() {
        let profile = NostrProfile.parse(from: "", pubkeyHex: "00001111")

        XCTAssertNil(profile.name)
        XCTAssertNil(profile.displayName)
    }

    // MARK: - Display Label

    func testDisplayLabel_PrefersDisplayName() {
        let profile = NostrProfile(
            pubkeyHex: "aabb",
            name: "alice",
            displayName: "Alice Quinn",
            picture: nil
        )

        XCTAssertEqual(profile.displayLabel, "Alice Quinn")
    }

    func testDisplayLabel_FallsBackToName() {
        let profile = NostrProfile(
            pubkeyHex: "aabb",
            name: "alice",
            displayName: nil,
            picture: nil
        )

        XCTAssertEqual(profile.displayLabel, "alice")
    }

    func testDisplayLabel_FallsBackToTruncatedPubkey() {
        let profile = NostrProfile(
            pubkeyHex: "aabbccdd11223344",
            name: nil,
            displayName: nil,
            picture: nil
        )

        XCTAssertEqual(profile.displayLabel, "aabbccdd...")
    }

    func testDisplayLabel_SkipsEmptyDisplayName() {
        let profile = NostrProfile(
            pubkeyHex: "aabbccdd11223344",
            name: "alice",
            displayName: "",
            picture: nil
        )

        XCTAssertEqual(profile.displayLabel, "alice")
    }

    func testDisplayLabel_SkipsEmptyNameToo() {
        let profile = NostrProfile(
            pubkeyHex: "aabbccdd11223344",
            name: "",
            displayName: "",
            picture: nil
        )

        XCTAssertEqual(profile.displayLabel, "aabbccdd...")
    }

    // MARK: - fetchProfiles Empty Input

    func testFetchProfiles_EmptyInputReturnsEmpty() async throws {
        let result = try await service.fetchProfiles(pubkeyHexes: [])
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - resolveProfiles

    func testResolveProfiles_EmptyInput() async throws {
        let result = try await service.resolveProfiles(pubkeyHexes: [])
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Guest Mode Gate

    func testGuestMode_FetchProfilesReturnsEmpty() async throws {
        UserDefaults.standard.set(false, forKey: "nostrActivated")
        let result = try await service.fetchProfiles(pubkeyHexes: ["aabbccdd"])
        XCTAssertTrue(result.isEmpty, "Guest mode should return empty profiles")
        UserDefaults.standard.set(true, forKey: "nostrActivated")
    }

    func testGuestMode_PublishReturnsEmptyId() async throws {
        UserDefaults.standard.set(false, forKey: "nostrActivated")
        let keys = Keys.generate()
        let builder = EventBuilder(kind: Kind(kind: 1), content: "test")
        let eventId = try await service.publishEvent(keys: keys, builder: builder)
        XCTAssertEqual(eventId, "", "Guest mode publish should return empty event ID")
        UserDefaults.standard.set(true, forKey: "nostrActivated")
    }

    func testGuestMode_ResolveProfilesReturnsEmptyForUncached() async throws {
        UserDefaults.standard.set(false, forKey: "nostrActivated")
        let result = try await service.resolveProfiles(pubkeyHexes: ["uncached_key_123"])
        XCTAssertNil(result["uncached_key_123"], "Guest mode should not fetch uncached profiles from relays")
        UserDefaults.standard.set(true, forKey: "nostrActivated")
    }

    // MARK: - Live Relay Tests (require network)

    /// Test account pubkey: nsec1324q936nn4pp8yd34jg4ufxle7tnpv8z457gha0rwueqluz78cjq20ufjj
    /// This account follows 13 users and has a kind 3 event on relays.
    private static let testAccountPubkeyHex = "55127fc9e1c03c6b459a3bab72fdb99def1644c5f239bdd09f3e5fb401ed9b21"

    /// One of the followed accounts
    private static let followedPubkeyHex = "838917a3b10d606cfed683e4aa13876225e86a312f56717125fa0ad1c2c24cd7"

    /// fiatjaf — widely replicated profile, reliable for testing kind 0 fetches
    private static let fiatjafPubkeyHex = "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d"

    func testLive_FetchFollowList() async throws {
        let pubkey = try PublicKey.parse(publicKey: Self.testAccountPubkeyHex)
        let followList = try await service.fetchFollowList(pubkey: pubkey)

        // Test account follows 13 users (may change if account is modified)
        XCTAssertFalse(followList.isEmpty, "Follow list should not be empty")
        XCTAssertTrue(followList.count >= 5, "Expected at least 5 follows, got \(followList.count)")

        // Verify known followed pubkey is present
        XCTAssertTrue(
            followList.contains(Self.followedPubkeyHex),
            "Follow list should contain known followed pubkey"
        )

        // All entries should be 64-char hex strings
        for hex in followList {
            XCTAssertEqual(hex.count, 64, "Pubkey hex should be 64 characters: \(hex)")
        }
    }

    func testLive_FetchProfiles() async throws {
        let profiles = try await service.fetchProfiles(pubkeyHexes: [Self.fiatjafPubkeyHex])

        XCTAssertEqual(profiles.count, 1, "Should fetch exactly 1 profile")

        let profile = try XCTUnwrap(profiles[Self.fiatjafPubkeyHex])
        XCTAssertEqual(profile.name, "fiatjaf", "Expected name 'fiatjaf'")
        XCTAssertEqual(profile.pubkeyHex, Self.fiatjafPubkeyHex)
    }

    func testLive_FetchFollowListWithProfiles() async throws {
        // End-to-end: single connection fetches follow list + all profiles
        let pubkey = try PublicKey.parse(publicKey: Self.testAccountPubkeyHex)
        let (follows, profiles) = try await service.fetchFollowListWithProfiles(pubkey: pubkey)

        // Follow list assertions
        XCTAssertFalse(follows.isEmpty, "Follow list should not be empty")
        XCTAssertTrue(follows.count >= 5, "Expected at least 5 follows, got \(follows.count)")
        XCTAssertTrue(
            follows.contains(Self.followedPubkeyHex),
            "Follow list should contain known followed pubkey"
        )

        // Profile assertions
        XCTAssertFalse(profiles.isEmpty, "Should fetch at least one profile from follows")

        // Known profile should be present
        if let baxter = profiles[Self.followedPubkeyHex] {
            XCTAssertEqual(baxter.displayName, "Baxter")
        }

        // Every returned profile should have a valid displayLabel
        for (hex, profile) in profiles {
            XCTAssertEqual(profile.pubkeyHex, hex)
            XCTAssertFalse(profile.displayLabel.isEmpty, "Display label should never be empty")
        }
    }
}
