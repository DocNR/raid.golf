// Schema.swift
// RAID Golf - iOS Port
//
// Phase 2.3: SQLite Schema + Immutability Triggers
//
// Purpose:
// - Define authoritative tables: sessions, kpi_templates, club_subsessions
// - Enforce immutability via SQLite triggers (BEFORE UPDATE/DELETE → ABORT)
// - Enable foreign keys per connection (PRAGMA foreign_keys = ON)
//
// Invariant: All authoritative tables are immutable at creation time
// Design rule: No table ever transitions from mutable → immutable in-place
//
// Test: UPDATE and DELETE attempts must fail with trigger error

import Foundation
import GRDB

/// SQLite schema definition and migrations
struct Schema {
    // TODO: Phase 2.3 - Port schema from raid/schema.sql
    // See: docs/schema_brief/03_logical_schema.md
    // Reference: raid/schema.sql
    
    /// Install schema with immutability triggers
    /// - Parameter db: GRDB database connection
    /// - Throws: Database error if schema creation fails
    static func install(in db: Database) throws {
        // TODO: Implement schema installation
        // 1. PRAGMA foreign_keys = ON
        // 2. Create tables: sessions, kpi_templates, club_subsessions
        // 3. Create triggers: BEFORE UPDATE/DELETE → ABORT (all three tables)
        fatalError("Not implemented - Phase 2.3")
    }
}