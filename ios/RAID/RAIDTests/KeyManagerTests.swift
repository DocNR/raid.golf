// KeyManagerTests.swift
// Gambit Golf
//
// Tests for KeyManager key import functionality.

import XCTest
import NostrSDK
@testable import RAID

final class KeyManagerTests: XCTestCase {

    // Generate a known keypair for deterministic testing
    private static let testKeys = Keys.generate()
    private static var testNsec: String { try! testKeys.secretKey().toBech32() }
    private static var testPubkeyBech32: String { try! testKeys.publicKey().toBech32() }
    private static var testSecretKeyHex: String { testKeys.secretKey().toHex() }

    // MARK: - Import Tests

    func testImportValidNsecBech32() throws {
        let km = try KeyManager.importKey(nsec: Self.testNsec)
        let pubkey = try km.publicKeyBech32()
        XCTAssertEqual(pubkey, Self.testPubkeyBech32)
    }

    func testImportValidHex() throws {
        let km = try KeyManager.importKey(nsec: Self.testSecretKeyHex)
        let pubkey = try km.publicKeyBech32()
        XCTAssertEqual(pubkey, Self.testPubkeyBech32)
    }

    func testImportInvalidStringThrows() {
        XCTAssertThrowsError(try KeyManager.importKey(nsec: "not-a-valid-key")) { error in
            XCTAssertTrue(error is KeyManagerError)
        }
    }

    func testImportOverwritesExisting() throws {
        // Ensure a key exists first
        _ = try KeyManager.loadOrCreate()

        // Import a different key
        let newKeys = Keys.generate()
        let newNsec = try newKeys.secretKey().toBech32()
        let newExpectedPubkey = try newKeys.publicKey().toBech32()

        let km = try KeyManager.importKey(nsec: newNsec)
        XCTAssertEqual(try km.publicKeyBech32(), newExpectedPubkey)
    }

    func testLoadOrCreateAfterImportReturnsSameKey() throws {
        let km1 = try KeyManager.importKey(nsec: Self.testNsec)
        let pubkey1 = try km1.publicKeyBech32()

        let km2 = try KeyManager.loadOrCreate()
        let pubkey2 = try km2.publicKeyBech32()

        XCTAssertEqual(pubkey1, pubkey2)
    }
}
