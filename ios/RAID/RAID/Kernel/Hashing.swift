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
struct Hashing {
    // TODO: Phase 2.2 - Implement SHA-256 hashing
    // See: docs/specs/jcs_hashing.md
    // Reference: raid/hashing.py
    
    /// Compute SHA-256 hash of canonicalized JSON
    /// - Parameter canonicalJSON: UTF-8 bytes of JCS-canonicalized JSON
    /// - Returns: Hex-encoded SHA-256 hash (lowercase)
    static func hash(_ canonicalJSON: Data) -> String {
        // TODO: Implement using CryptoKit.SHA256
        fatalError("Not implemented - Phase 2.2")
    }
}