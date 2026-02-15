// Gambit Golf — Nostr Key Management
// Keychain-backed keypair lifecycle for Nostr identity

import Foundation
import Security
import UIKit
import NostrSDK

final class KeyManager {

    private static let keychainService = "com.gambitgolf.ios.nostr"
    private static let keychainAccount = "nostr-nsec"

    private let keys: Keys

    /// Initialize with existing keys (for future import support)
    init(keys: Keys) {
        self.keys = keys
    }

    /// Import an existing Nostr identity from nsec (bech32) or hex secret key.
    /// Overwrites any existing key in Keychain.
    static func importKey(nsec: String) throws -> KeyManager {
        let keys: Keys
        do {
            keys = try Keys.parse(secretKey: nsec)
        } catch {
            throw KeyManagerError.invalidKey(error.localizedDescription)
        }
        let bech32 = try keys.secretKey().toBech32()
        try saveToKeychain(nsec: bech32)
        return KeyManager(keys: keys)
    }

    /// Load existing keys from Keychain or generate new ones
    static func loadOrCreate() throws -> KeyManager {
        if let nsec = loadFromKeychain() {
            let keys = try Keys.parse(secretKey: nsec)
            return KeyManager(keys: keys)
        }

        let keys = Keys.generate()
        let nsec = try keys.secretKey().toBech32()
        try saveToKeychain(nsec: nsec)
        return KeyManager(keys: keys)
    }

    /// Public key in bech32 format (npub1...)
    func publicKeyBech32() throws -> String {
        try keys.publicKey().toBech32()
    }

    /// The underlying Keys for signing operations
    func signingKeys() -> Keys {
        keys
    }

    // MARK: - Keychain (internal for testing)

    /// Copy nsec to pasteboard (the only way to reveal the secret key).
    /// Caller is responsible for showing confirmation UI before calling this.
    func copySecretKeyToPasteboard() throws {
        let nsec = try keys.secretKey().toBech32()
        UIPasteboard.general.string = nsec
    }

    // MARK: - Keychain Operations

    private static func loadFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let nsec = String(data: data, encoding: .utf8) else {
            return nil
        }

        return nsec
    }

    private static func saveToKeychain(nsec: String) throws {
        guard let data = nsec.data(using: .utf8) else {
            throw KeyManagerError.encodingFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        // Delete any existing entry first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeyManagerError.keychainWriteFailed(status)
        }
    }
}

enum KeyManagerError: LocalizedError {
    case encodingFailed
    case keychainWriteFailed(OSStatus)
    case invalidKey(String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode key data."
        case .keychainWriteFailed(let status):
            return "Failed to save key to Keychain (status: \(status))."
        case .invalidKey(let detail):
            return "Invalid Nostr key: \(detail)"
        }
    }
}
