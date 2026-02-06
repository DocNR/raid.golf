// Repository.swift
// RAID Golf - iOS Port
//
// Phase 2.4: Data Access Layer
//
// Purpose:
// - Insert path: canonicalize → hash → store (hash computed once)
// - Read path: return stored hash directly (never recompute)
// - Enforce "no re-hash on read" mechanically via API design
//
// Invariants:
// - template_hash is required column
// - No save(updatedTemplate) method exists
// - Canonicalize/hash only callable from insert path
//
// Test: Prove read path never calls canonicalize/hash (spy/mock or compile-time enforcement)

import Foundation
import GRDB

/// Data access layer for RAID kernel
class Repository {
    // TODO: Phase 2.4 - Implement data access layer
    // See: docs/schema_brief/04_identity_and_immutability.md
    // Reference: raid/repository.py
    
    private let dbQueue: DatabaseQueue
    
    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }
    
    // MARK: - Insert Path (hash computed once)
    
    /// Insert a new KPI template (computes hash once)
    /// - Parameter templateJSON: Raw JSON object (not yet canonicalized)
    /// - Returns: The computed template hash
    /// - Throws: Database error or canonicalization error
    func insertTemplate(_ templateJSON: [String: Any]) throws -> String {
        // TODO: Implement
        // 1. Canonicalize JSON
        // 2. Compute hash
        // 3. Store template with hash
        fatalError("Not implemented - Phase 2.4")
    }
    
    // MARK: - Read Path (returns stored hash, never recomputes)
    
    /// Fetch a template by its stored hash
    /// - Parameter hash: The template hash (already computed)
    /// - Returns: Template JSON and stored hash
    /// - Throws: Database error
    func fetchTemplate(byHash hash: String) throws -> (json: [String: Any], storedHash: String) {
        // TODO: Implement
        // MUST NOT call canonicalize or hash functions
        // Returns stored hash directly
        fatalError("Not implemented - Phase 2.4")
    }
}