// ClubSubsession.swift
// RAID Golf
//
// Purpose:
// - Model for club-specific subsessions within a practice session
// - Corresponds to `club_subsessions` table in SQLite schema
//
// Invariants:
// - Immutable after creation
// - subsession_id is primary key
// - Foreign key to sessions table
// - Foreign key to kpi_templates table via template_hash
//
// Reference: raid/schema.sql, docs/schema_brief/02_authoritative_entities.md

import Foundation
import GRDB

/// Club subsession model (authoritative, immutable)
struct ClubSubsession: Codable, FetchableRecord, PersistableRecord {
    // TODO: Phase 2 - Define properties matching club_subsessions table
    // - subsession_id: String (TEXT PRIMARY KEY)
    // - session_id: String (FOREIGN KEY → sessions)
    // - club: String
    // - template_hash: String (FOREIGN KEY → kpi_templates)
    // - shot_count: Int
    // - a_count: Int
    // - b_count: Int
    // - c_count: Int
    // - validity: String (enum: invalid, warning, valid)
    // - a_percentage: Double? (NULL when invalid)
    
    static let databaseTableName = "club_subsessions"
}