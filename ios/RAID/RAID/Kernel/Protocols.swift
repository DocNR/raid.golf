// Protocols.swift
// Gambit Golf
//
// Kernel Protocols for Dependency Injection
//
// Purpose:
// - Enable behavioral testing of repository without global state
// - Enforce "no re-hash on read" via spy injection
// - Keep production code clean (no DEBUG counters)

import Foundation

/// Protocol for canonical JSON transformation
protocol Canonicalizing {
    /// Canonicalize raw JSON bytes to RAID Canonical JSON v1 format
    /// - Parameter raw: Raw JSON bytes (UTF-8)
    /// - Returns: Canonical JSON bytes (UTF-8, sorted keys, compact)
    /// - Throws: Error if JSON is invalid or contains NaN/Infinity
    func canonicalize(_ raw: Data) throws -> Data
}

/// Protocol for SHA-256 hashing
protocol Hashing {
    /// Compute SHA-256 hash of canonical JSON bytes
    /// - Parameter canonical: Canonical JSON bytes (UTF-8)
    /// - Returns: 64-character lowercase hex SHA-256 hash
    func sha256Hex(_ canonical: Data) -> String
}

// MARK: - Production Implementations

/// Production canonicalizer wrapping RAIDCanonical
struct RAIDCanonicalizer: Canonicalizing {
    func canonicalize(_ raw: Data) throws -> Data {
        // Parse JSON from bytes
        guard let jsonObject = try? JSONSerialization.jsonObject(with: raw, options: []) else {
            throw NSError(domain: "RAIDCanonicalizer", code: 1, 
                         userInfo: [NSLocalizedDescriptionKey: "Invalid JSON bytes"])
        }
        
        // Canonicalize using existing RAIDCanonical
        let canonicalString = try RAIDCanonical.canonicalize(jsonObject)
        
        // Return as UTF-8 bytes
        return Data(canonicalString.utf8)
    }
}

/// Production hasher wrapping CryptoKit SHA-256
struct RAIDHasher: Hashing {
    func sha256Hex(_ canonical: Data) -> String {
        return RAIDHashing.hashBytes(canonical)
    }
}
