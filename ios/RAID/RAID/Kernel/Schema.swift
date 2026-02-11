// Schema.swift
// Gambit Golf
//
// SQLite Schema + Immutability Triggers
// Scorecard v0: course_snapshots, course_holes, rounds, round_events, hole_scores
//
// Purpose:
// - Define authoritative tables with immutability triggers
// - Use GRDB DatabaseMigrator for auditable schema timeline
// - Enable foreign keys per connection (PRAGMA foreign_keys = ON)
//
// Migrations:
// - v1_create_schema: sessions, kpi_templates, club_subsessions, projections
// - v2_add_shots: shots table with FK to sessions
// - v3_create_scorecard_schema: scorecard tables (kernel-adjacent)
// - v4_create_template_preferences: template_preferences (mutable preference table)
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
        
        // ============================================================
        // v3_create_scorecard_schema: Scorecard tables (kernel-adjacent)
        //
        // New domain: scorecards. Does NOT modify frozen kernel tables.
        // Tables: course_snapshots, course_holes, rounds, round_events, hole_scores
        // All authoritative tables are immutable (UPDATE/DELETE triggers).
        // ============================================================
        migrator.registerMigration("v3_create_scorecard_schema") { db in

            // Course Snapshots (content-addressed, immutable)
            // Mirrors kpi_templates: hash PK, canonical JSON stored.
            // course_hash = SHA-256(UTF-8(JCS(canonical_json)))
            try db.execute(sql: """
                CREATE TABLE course_snapshots (
                    course_hash TEXT PRIMARY KEY,
                    course_name TEXT NOT NULL,
                    tee_set TEXT NOT NULL,
                    hole_count INTEGER NOT NULL,
                    canonical_json TEXT NOT NULL,
                    created_at TEXT NOT NULL,

                    CHECK (length(course_hash) = 64),
                    CHECK (course_hash GLOB '[0-9a-f]*'),
                    CHECK (hole_count IN (9, 18))
                )
                """)

            try db.execute(sql: "CREATE INDEX idx_course_snapshots_name ON course_snapshots(course_name)")

            try db.execute(sql: """
                CREATE TRIGGER course_snapshots_no_update
                BEFORE UPDATE ON course_snapshots
                BEGIN
                    SELECT RAISE(ABORT, 'Course snapshots are immutable after creation');
                END
                """)

            try db.execute(sql: """
                CREATE TRIGGER course_snapshots_no_delete
                BEFORE DELETE ON course_snapshots
                BEGIN
                    SELECT RAISE(ABORT, 'Course snapshots are immutable after creation');
                END
                """)

            // Course Holes (normalized hole definitions, immutable)
            // Avoids JSON parsing at runtime. PK: (course_hash, hole_number).
            try db.execute(sql: """
                CREATE TABLE course_holes (
                    course_hash TEXT NOT NULL,
                    hole_number INTEGER NOT NULL,
                    par INTEGER NOT NULL,
                    handicap_index INTEGER,

                    PRIMARY KEY (course_hash, hole_number),

                    FOREIGN KEY (course_hash) REFERENCES course_snapshots(course_hash)
                        ON DELETE RESTRICT,

                    CHECK (hole_number >= 1 AND hole_number <= 18),
                    CHECK (par >= 3 AND par <= 6)
                )
                """)

            try db.execute(sql: """
                CREATE TRIGGER course_holes_no_update
                BEFORE UPDATE ON course_holes
                BEGIN
                    SELECT RAISE(ABORT, 'Course holes are immutable after creation');
                END
                """)

            try db.execute(sql: """
                CREATE TRIGGER course_holes_no_delete
                BEFORE DELETE ON course_holes
                BEGIN
                    SELECT RAISE(ABORT, 'Course holes are immutable after creation');
                END
                """)

            // Rounds (immutable — no UPDATE ever)
            try db.execute(sql: """
                CREATE TABLE rounds (
                    round_id INTEGER PRIMARY KEY AUTOINCREMENT,
                    course_hash TEXT NOT NULL,
                    round_date TEXT NOT NULL,
                    created_at TEXT NOT NULL,

                    FOREIGN KEY (course_hash) REFERENCES course_snapshots(course_hash)
                        ON DELETE RESTRICT
                )
                """)

            try db.execute(sql: "CREATE INDEX idx_rounds_date ON rounds(round_date)")

            try db.execute(sql: """
                CREATE TRIGGER rounds_no_update
                BEFORE UPDATE ON rounds
                BEGIN
                    SELECT RAISE(ABORT, 'Rounds are immutable after creation');
                END
                """)

            try db.execute(sql: """
                CREATE TRIGGER rounds_no_delete
                BEFORE DELETE ON rounds
                BEGIN
                    SELECT RAISE(ABORT, 'Rounds are immutable after creation');
                END
                """)

            // Round Events (append-only lifecycle events)
            // Completion is an event, not a status UPDATE on rounds.
            // UNIQUE(round_id, event_type) prevents double-completion.
            try db.execute(sql: """
                CREATE TABLE round_events (
                    event_id INTEGER PRIMARY KEY AUTOINCREMENT,
                    round_id INTEGER NOT NULL,
                    event_type TEXT NOT NULL,
                    recorded_at TEXT NOT NULL,

                    FOREIGN KEY (round_id) REFERENCES rounds(round_id)
                        ON DELETE RESTRICT,

                    UNIQUE (round_id, event_type),
                    CHECK (event_type IN ('completed'))
                )
                """)

            try db.execute(sql: """
                CREATE TRIGGER round_events_no_update
                BEFORE UPDATE ON round_events
                BEGIN
                    SELECT RAISE(ABORT, 'Round events are immutable after creation');
                END
                """)

            try db.execute(sql: """
                CREATE TRIGGER round_events_no_delete
                BEFORE DELETE ON round_events
                BEGIN
                    SELECT RAISE(ABORT, 'Round events are immutable after creation');
                END
                """)

            // Hole Scores (append-only, latest-wins corrections)
            // Multiple rows per (round_id, hole_number) allowed.
            // Latest-wins: MAX(recorded_at), tie-break MAX(score_id).
            try db.execute(sql: """
                CREATE TABLE hole_scores (
                    score_id INTEGER PRIMARY KEY AUTOINCREMENT,
                    round_id INTEGER NOT NULL,
                    hole_number INTEGER NOT NULL,
                    strokes INTEGER NOT NULL,
                    recorded_at TEXT NOT NULL,

                    FOREIGN KEY (round_id) REFERENCES rounds(round_id)
                        ON DELETE RESTRICT,

                    CHECK (hole_number >= 1 AND hole_number <= 18),
                    CHECK (strokes >= 1 AND strokes <= 20)
                )
                """)

            try db.execute(sql: "CREATE INDEX idx_hole_scores_round_hole ON hole_scores(round_id, hole_number, recorded_at DESC)")

            try db.execute(sql: """
                CREATE TRIGGER hole_scores_no_update
                BEFORE UPDATE ON hole_scores
                BEGIN
                    SELECT RAISE(ABORT, 'Hole scores are immutable; insert a correction instead');
                END
                """)

            try db.execute(sql: """
                CREATE TRIGGER hole_scores_no_delete
                BEFORE DELETE ON hole_scores
                BEGIN
                    SELECT RAISE(ABORT, 'Hole scores are immutable after creation');
                END
                """)
        }

        // ============================================================
        // v4_create_template_preferences: Template Preferences Table
        //
        // Mutable preference table for KPI templates (no immutability triggers).
        // Stores user-facing display names, active/hidden status per template.
        // Denormalizes club from kpi_templates for partial unique index constraint.
        // ============================================================
        migrator.registerMigration("v4_create_template_preferences") { db in
            // Template Preferences (mutable)
            try db.execute(sql: """
                CREATE TABLE template_preferences (
                    template_hash TEXT PRIMARY KEY,
                    club TEXT NOT NULL,
                    display_name TEXT,
                    is_active INTEGER NOT NULL DEFAULT 0,
                    is_hidden INTEGER NOT NULL DEFAULT 0,
                    updated_at TEXT NOT NULL,

                    FOREIGN KEY (template_hash) REFERENCES kpi_templates(template_hash)
                        ON DELETE RESTRICT,

                    CHECK (is_active IN (0, 1)),
                    CHECK (is_hidden IN (0, 1))
                )
                """)

            // Partial unique index: at most one active template per club
            try db.execute(sql: """
                CREATE UNIQUE INDEX idx_one_active_per_club
                ON template_preferences(club) WHERE is_active = 1
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
