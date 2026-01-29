-- RAID Phase 0 MVP Schema
-- SQLite 3.35+
-- 
-- Immutability enforced via BEFORE UPDATE triggers that ABORT.
-- No soft immutability - violations cause transaction failure.

PRAGMA foreign_keys = ON;

-- ============================================================
-- AUTHORITATIVE TABLES
-- ============================================================

-- Sessions (immutable after creation - RTM-01)
CREATE TABLE sessions (
    session_id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_date TEXT NOT NULL,                    -- ISO-8601 timestamp
    source_file TEXT NOT NULL,                     -- Original CSV filename
    device_type TEXT,                              -- e.g., "Rapsodo MLM2Pro"
    location TEXT,                                 -- Practice location
    ingested_at TEXT NOT NULL                      -- ISO-8601 timestamp
);

CREATE INDEX idx_sessions_date ON sessions(session_date);

-- KPI Templates (immutable forever - RTM-03)
CREATE TABLE kpi_templates (
    template_hash TEXT PRIMARY KEY,                -- SHA-256 hex, 64 chars
    schema_version TEXT NOT NULL,                  -- e.g., "1.0"
    club TEXT NOT NULL,                            -- Target club
    canonical_json TEXT NOT NULL,                  -- Canonical JSON content
    created_at TEXT NOT NULL,                      -- ISO-8601 timestamp
    imported_at TEXT,                              -- ISO-8601 (NULL if local)
    
    CHECK (length(template_hash) = 64),
    CHECK (template_hash GLOB '[0-9a-f]*')         -- Lowercase hex only
);

CREATE INDEX idx_templates_club ON kpi_templates(club);

-- Club Sub-Sessions (immutable after creation - RTM-02)
CREATE TABLE club_subsessions (
    subsession_id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id INTEGER NOT NULL,
    club TEXT NOT NULL,
    kpi_template_hash TEXT NOT NULL,
    shot_count INTEGER NOT NULL,
    validity_status TEXT NOT NULL,                 -- Enum: see CHECK
    a_count INTEGER NOT NULL,
    b_count INTEGER NOT NULL,
    c_count INTEGER NOT NULL,
    a_percentage REAL,                             -- NULL if invalid
    avg_carry REAL,
    avg_ball_speed REAL,
    avg_spin REAL,
    avg_descent REAL,
    analyzed_at TEXT NOT NULL,                     -- ISO-8601 timestamp
    
    FOREIGN KEY (session_id) REFERENCES sessions(session_id)
        ON DELETE RESTRICT,
    FOREIGN KEY (kpi_template_hash) REFERENCES kpi_templates(template_hash)
        ON DELETE RESTRICT,
    
    UNIQUE (session_id, club, kpi_template_hash),  -- Prevent duplicate analysis
    
    CHECK (shot_count > 0),
    CHECK (a_count >= 0),
    CHECK (b_count >= 0),
    CHECK (c_count >= 0),
    CHECK (a_count + b_count + c_count = shot_count),
    CHECK (validity_status IN ('invalid_insufficient_data', 'valid_low_sample_warning', 'valid')),
    CHECK (a_percentage IS NULL OR (a_percentage >= 0.0 AND a_percentage <= 100.0)),
    -- A% must be NULL if invalid
    CHECK (validity_status != 'invalid_insufficient_data' OR a_percentage IS NULL)
);

CREATE INDEX idx_subsessions_session ON club_subsessions(session_id);
CREATE INDEX idx_subsessions_template ON club_subsessions(kpi_template_hash);
CREATE INDEX idx_subsessions_club_date ON club_subsessions(club, analyzed_at);
CREATE INDEX idx_subsessions_validity ON club_subsessions(validity_status);

-- Template Aliases (mutable: display_name, notes)
CREATE TABLE template_aliases (
    alias_id INTEGER PRIMARY KEY AUTOINCREMENT,
    template_hash TEXT NOT NULL,
    display_name TEXT NOT NULL,
    notes TEXT,
    created_at TEXT NOT NULL,                      -- ISO-8601 timestamp
    updated_at TEXT,                               -- ISO-8601 timestamp
    
    FOREIGN KEY (template_hash) REFERENCES kpi_templates(template_hash)
        ON DELETE CASCADE,
    
    UNIQUE (display_name),
    CHECK (length(display_name) > 0),
    CHECK (length(display_name) <= 255)
);

CREATE INDEX idx_aliases_template ON template_aliases(template_hash);

-- ============================================================
-- IMMUTABILITY TRIGGERS (RTM-01, RTM-02, RTM-03)
-- ============================================================

-- RTM-01: Block ALL updates on sessions
CREATE TRIGGER sessions_immutable
BEFORE UPDATE ON sessions
BEGIN
    SELECT RAISE(ABORT, 'Sessions are immutable after creation');
END;

-- RTM-02: Block ALL updates on club_subsessions
CREATE TRIGGER subsessions_immutable
BEFORE UPDATE ON club_subsessions
BEGIN
    SELECT RAISE(ABORT, 'Club sub-sessions are immutable after creation');
END;

-- RTM-03: Block ALL updates on kpi_templates
CREATE TRIGGER templates_immutable
BEFORE UPDATE ON kpi_templates
BEGIN
    SELECT RAISE(ABORT, 'KPI templates are immutable forever');
END;

-- ============================================================
-- DERIVED TABLES (OPTIONAL, EPHEMERAL)
-- ============================================================

-- RTM-16: Projections are derived/regenerable artifacts.
-- This table is optional and may not be persisted at all.
-- Projections MUST NOT be referenced by authoritative tables.
-- No foreign keys should point TO this table.
-- Entries may be deleted at any time without data loss.
CREATE TABLE projections (
    projection_id INTEGER PRIMARY KEY AUTOINCREMENT,
    subsession_id INTEGER NOT NULL UNIQUE,
    projection_json TEXT NOT NULL,
    generated_at TEXT NOT NULL,                    -- ISO-8601 timestamp
    
    FOREIGN KEY (subsession_id) REFERENCES club_subsessions(subsession_id)
        ON DELETE CASCADE
);
