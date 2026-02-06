// Hashing.swift
// RAID Golf - iOS Port
//
// Phase 2.2: SHA-256 Content-Addressed Hashing
//
// Purpose:
// - Formula: hash = SHA-256(UTF-8(JCS(json)))
// - Use CryptoKit for SHA-256
// - Hash computed ONCE on insert, NEVER recomputed on read
//
// Test against: ../tests/vectors/expected/template_hashes.json (all golden hashes must match)

import Foundation
import CryptoKit

/// SHA-256 content-addressed hashing for templates
struct RAIDHashing {
    
    /// Compute SHA-256 hash of canonicalized template JSON
    ///
    /// Formula: hash = SHA-256(UTF-8(canonicalize(template)))
    ///
    /// The hash is computed ONCE during template creation and stored.
    /// Read operations must NOT call this function (RTM-04).
    ///
    /// - Parameter template: Template dictionary to hash
    /// - Returns: 64-character lowercase hex SHA-256 hash
    /// - Throws: RAIDCanonical.Error if template contains invalid values
    static func computeTemplateHash(_ template: [String: Any]) throws -> String {
        // Canonicalize using RAID Canonical JSON v1
        let canonical = try RAIDCanonical.canonicalize(template)
        
        // Convert to UTF-8 bytes
        let data = Data(canonical.utf8)
        
        // Compute SHA-256
        let digest = SHA256.hash(data: data)
        
        // Return lowercase hex string
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    
    /// Hash pre-canonicalized JSON bytes (for testing)
    ///
    /// - Parameter data: UTF-8 encoded canonical JSON
    /// - Returns: 64-character lowercase hex SHA-256 hash
    static func hashBytes(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
