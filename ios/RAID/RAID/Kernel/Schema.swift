// Schema.swift
// RAID Golf - iOS Port
//
// Phase 2.3: SQLite Schema + Immutability Triggers
// Phase 2.3b: Shots Table (v2_add_shots migration)
//
// Purpose:
// - Define authoritative tables with immutability triggers
// - Use GRDB DatabaseMigrator for auditable schema timeline
// - Enable foreign keys per connection (PRAGMA foreign_keys = ON)
//
// Migrations:
// - v1_create_schema: sessions, kpi_templates, club_subsessions, projections
// - v2_add_shots: shots table with FK to sessions
//
// Invariant: All authoritative tables are immutable at creation time
// Design rule: No table ever transitions from mutable → immutable in-place

import Foundation
import GRDB

/// SQLite schema definition and migrations
struct Schema {
    /// Create and configure database migrator
    /// - Returns: Configured DatabaseMigrator with all migrations
    static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        
        // ============================================================
        // v1_create_schema: Core authoritative tables
        // ============================================================
        migrator.registerMigration("v1_create_schema") { db in
            // Enable foreign key enforcement (per connection)
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            
            // Sessions (immutable after creation - RTM-01)
            try db.execute(sql: """
                CREATE TABLE sessions (
                    session_id INTEGER PRIMARY KEY AUTOINCREMENT,
                    session_date TEXT NOT NULL,
                    source_file TEXT NOT NULL,
                    device_type TEXT,
                    location TEXT,
                    ingested_at TEXT NOT NULL
                )
                """)
            
            try db.execute(sql: "CREATE INDEX idx_sessions_date ON sessions(session_date)")
            
            // KPI Templates (immutable forever - RTM-03)
            try db.execute(sql: """
                CREATE TABLE kpi_templates (
                    template_hash TEXT PRIMARY KEY,
                    schema_version TEXT NOT NULL,
                    club TEXT NOT NULL,
                    canonical_json TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    imported_at TEXT,
                    
                    CHECK (length(template_hash) = 64),
                    CHECK (template_hash GLOB '[0-9a-f]*')
                )
                """)
            
            try db.execute(sql: "CREATE INDEX idx_templates_club ON kpi_templates(club)")
            
            // Club Sub-Sessions (immutable after creation - RTM-02)
            try db.execute(sql: """
                CREATE TABLE club_subsessions (
                    subsession_id INTEGER PRIMARY KEY AUTOINCREMENT,
                    session_id INTEGER NOT NULL,
                    club TEXT NOT NULL,
                    kpi_template_hash TEXT NOT NULL,
                    shot_count INTEGER NOT NULL,
                    validity_status TEXT NOT NULL,
                    a_count INTEGER NOT NULL,
                    b_count INTEGER NOT NULL,
                    c_count INTEGER NOT NULL,
                    a_percentage REAL,
                    avg_carry REAL,
                    avg_ball_speed REAL,
                    avg_spin REAL,
                    avg_descent REAL,
                    analyzed_at TEXT NOT NULL,
                    
                    FOREIGN KEY (session_id) REFERENCES sessions(session_id)
                        ON DELETE RESTRICT,
                    FOREIGN KEY (kpi_template_hash) REFERENCES kpi_templates(template_hash)
                        ON DELETE RESTRICT,
                    
                    UNIQUE (session_id, club, kpi_template_hash),
                    
                    CHECK (shot_count > 0),
                    CHECK (a_count >= 0),
                    CHECK (b_count >= 0),
                    CHECK (c_count >= 0),
                    CHECK (a_count + b_count + c_count = shot_count),
                    CHECK (validity_status IN ('invalid_insufficient_data', 'valid_low_sample_warning', 'valid')),
                    CHECK (a_percentage IS NULL OR (a_percentage >= 0.0 AND a_percentage <= 100.0)),
                    CHECK (validity_status != 'invalid_insufficient_data' OR a_percentage IS NULL)
                )
                """)
            
            try db.execute(sql: "CREATE INDEX idx_subsessions_session ON club_subsessions(session_id)")
            try db.execute(sql: "CREATE INDEX idx_subsessions_template ON club_subsessions(kpi_template_hash)")
            try db.execute(sql: "CREATE INDEX idx_subsessions_club_date ON club_subsessions(club, analyzed_at)")
            try db.execute(sql: "CREATE INDEX idx_subsessions_validity ON club_subsessions(validity_status)")
            
            // ============================================================
            // IMMUTABILITY TRIGGERS (RTM-01, RTM-02, RTM-03)
            // ============================================================
            
            // RTM-01: Block ALL updates and deletes on sessions
            try db.execute(sql: """
                CREATE TRIGGER sessions_no_update
                BEFORE UPDATE ON sessions
                BEGIN
                    SELECT RAISE(ABORT, 'Sessions are immutable after creation');
                END
                """)
            
            try db.execute(sql: """
                CREATE TRIGGER sessions_no_delete
                BEFORE DELETE ON sessions
                BEGIN
                    SELECT RAISE(ABORT, 'Sessions are immutable after creation');
                END
                """)
            
            // RTM-02: Block ALL updates and deletes on club_subsessions
            try db.execute(sql: """
                CREATE TRIGGER subsessions_no_update
                BEFORE UPDATE ON club_subsessions
                BEGIN
                    SELECT RAISE(ABORT, 'Club sub-sessions are immutable after creation');
                END
                """)
            
            try db.execute(sql: """
                CREATE TRIGGER subsessions_no_delete
                BEFORE DELETE ON club_subsessions
                BEGIN
                    SELECT RAISE(ABORT, 'Club sub-sessions are immutable after creation');
                END
                """)
            
            // RTM-03: Block ALL updates and deletes on kpi_templates
            try db.execute(sql: """
                CREATE TRIGGER templates_no_update
                BEFORE UPDATE ON kpi_templates
                BEGIN
                    SELECT RAISE(ABORT, 'KPI templates are immutable forever');
                END
                """)
            
            try db.execute(sql: """
                CREATE TRIGGER templates_no_delete
                BEFORE DELETE ON kpi_templates
                BEGIN
                    SELECT RAISE(ABORT, 'KPI templates are immutable forever');
                END
                """)
            
            // ============================================================
            // DERIVED TABLES (OPTIONAL, EPHEMERAL)
            // ============================================================
            
            // RTM-16: Projections are derived/regenerable artifacts
            try db.execute(sql: """
                CREATE TABLE projections (
                    projection_id INTEGER PRIMARY KEY AUTOINCREMENT,
                    subsession_id INTEGER NOT NULL UNIQUE,
                    projection_json TEXT NOT NULL,
                    generated_at TEXT NOT NULL,
                    
                    FOREIGN KEY (subsession_id) REFERENCES club_subsessions(subsession_id)
                        ON DELETE CASCADE
                )
                """)
        }
        
        // ============================================================
        // v2_add_shots: Shot-level fact table
        // ============================================================
        migrator.registerMigration("v2_add_shots") { db in
            // Shots (immutable after creation)
            try db.execute(sql: """
                CREATE TABLE shots (
                    shot_id INTEGER PRIMARY KEY AUTOINCREMENT,
                    session_id INTEGER NOT NULL,
                    
                    -- Provenance
                    source_row_index INTEGER NOT NULL,
                    source_format TEXT NOT NULL,
                    imported_at TEXT NOT NULL,
                    raw_json TEXT NOT NULL,
                    
                    -- Normalized columns (KPI-relevant, all nullable)
                    club TEXT NOT NULL,
                    carry REAL,
                    total_distance REAL,
                    ball_speed REAL,
                    club_speed REAL,
                    launch_angle REAL,
                    launch_direction REAL,
                    spin_rate REAL,
                    spin_axis REAL,
                    apex REAL,
                    descent_angle REAL,
                    smash_factor REAL,
                    attack_angle REAL,
                    club_path REAL,
                    side_carry REAL,
                    
                    FOREIGN KEY (session_id) REFERENCES sessions(session_id)
                        ON DELETE RESTRICT,
                    
                    UNIQUE (session_id, source_row_index),
                    CHECK (source_row_index >= 0)
                )
                """)
            
            try db.execute(sql: "CREATE INDEX idx_shots_session ON shots(session_id)")
            try db.execute(sql: "CREATE INDEX idx_shots_club ON shots(club)")
            
            // Immutability triggers for shots
            try db.execute(sql: """
                CREATE TRIGGER shots_no_update
                BEFORE UPDATE ON shots
                BEGIN
                    SELECT RAISE(ABORT, 'Shots are immutable after creation');
                END
                """)
            
            try db.execute(sql: """
                CREATE TRIGGER shots_no_delete
                BEFORE DELETE ON shots
                BEGIN
                    SELECT RAISE(ABORT, 'Shots are immutable after creation');
                END
                """)
        }
        
        return migrator
    }
    
    /// Install schema using migrator (runs all pending migrations)
    /// - Parameter writer: GRDB database writer (e.g., DatabaseQueue)
    /// - Throws: Database error if migration fails
    static func install(in writer: any DatabaseWriter) throws {
        try migrator().migrate(writer)
    }
}
