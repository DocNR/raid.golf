// KPITemplate.swift
// RAID Golf - iOS Port
//
// Purpose:
// - Model for KPI classification templates (authoritative, immutable)
// - Corresponds to `kpi_templates` table in SQLite schema
//
// Invariants:
// - Immutable after creation
// - template_hash is primary key (content-addressed via SHA-256)
// - Hash computed ONCE on insert, NEVER recomputed on read
// - template_json stores the canonicalized JSON
//
// Reference: raid/schema.sql, docs/schema_brief/04_identity_and_immutability.md

import Foundation
import GRDB

/// KPI template model (authoritative, immutable, content-addressed)
struct KPITemplate: Codable, FetchableRecord, PersistableRecord {
    // TODO: Phase 2 - Define properties matching kpi_templates table
    // - template_hash: String (TEXT PRIMARY KEY, SHA-256 hex)
    // - template_json: String (canonicalized JSON)
    // - kpi_version: String
    // - club: String
    // - created_at: String (ISO 8601)
    
    static let databaseTableName = "kpi_templates"
}