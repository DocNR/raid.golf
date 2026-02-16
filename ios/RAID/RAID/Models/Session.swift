// Session.swift
// RAID Golf
//
// Purpose:
// - Model for practice sessions (authoritative, immutable)
// - Corresponds to `sessions` table in SQLite schema
//
// Invariants:
// - Immutable after creation
// - session_id is primary key (TEXT, UUID recommended)
// - session_date is ISO 8601 timestamp
//
// Reference: raid/schema.sql, docs/schema_brief/02_authoritative_entities.md

import Foundation
import GRDB

/// Practice session model (authoritative, immutable)
struct Session: Codable, FetchableRecord, PersistableRecord {
    // TODO: Phase 2 - Define properties matching sessions table
    // - session_id: String (TEXT PRIMARY KEY)
    // - session_date: String (ISO 8601)
    // - location: String? (optional)
    // - device: String
    // - source_file: String
    
    static let databaseTableName = "sessions"
}