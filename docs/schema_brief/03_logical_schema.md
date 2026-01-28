# 3. Logical Schema Definition

[← Back to Index](00_index.md)

---

## 3.1 Overview

This section defines the **conceptual schema** for all authoritative entities. The definitions are vendor-neutral and language-agnostic — they describe **what must exist**, not **how to implement it**.

**Important:** This is not SQL. Implementations in SQLite, PostgreSQL, or other systems must translate these conceptual definitions to their specific syntax while preserving all constraints.

---

## 3.2 Data Type Conventions

The following conceptual types are used:

| Conceptual Type | Description | Example Values |
|-----------------|-------------|----------------|
| `integer` | Whole number | 1, 42, 1000 |
| `decimal` | Floating-point number | 156.4, 1.32, 48.5 |
| `string` | Text (UTF-8) | "7i", "PW", "Rapsodo" |
| `text` | Large text (UTF-8) | JSON documents, notes |
| `timestamp` | ISO-8601 date/time with timezone | "2026-01-28T17:30:00Z" |
| `enum` | Enumerated value from fixed set | See specific enum definitions |
| `boolean` | True/false | true, false |

**Nullability:** Explicitly marked as `NULL` or `NOT NULL` for each field.

---

## 3.3 Entity: Session

### Table Name
`sessions`

### Columns

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| `session_id` | integer | NOT NULL | Primary key (auto-increment) |
| `session_date` | timestamp | NOT NULL | Date/time of practice session |
| `source_file` | string | NOT NULL | Original CSV filename (for reference) |
| `device_type` | string | NULL | Launch monitor type (e.g., "Rapsodo MLM2Pro") |
| `location` | string | NULL | Practice location (optional metadata) |
| `ingested_at` | timestamp | NOT NULL | When CSV was imported into system |

### Primary Key
- `session_id`

### Foreign Keys
- None

### Unique Constraints
- None (multiple imports of same CSV are allowed)

### Check Constraints
- `ingested_at >= session_date` (cannot ingest before session occurred)

### Indexes (Recommended)
- `session_date` (for date-range queries)

---

## 3.4 Entity: Club Sub-Session

### Table Name
`club_subsessions`

### Columns

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| `subsession_id` | integer | NOT NULL | Primary key (auto-increment) |
| `session_id` | integer | NOT NULL | Foreign key to parent session |
| `club` | string | NOT NULL | Club identifier (e.g., "7i", "PW", "DR") |
| `kpi_template_hash` | string(64) | NOT NULL | SHA-256 hash of KPI template used |
| `shot_count` | integer | NOT NULL | Total valid shots analyzed |
| `validity_status` | enum | NOT NULL | Data quality indicator (see enum below) |
| `a_count` | integer | NOT NULL | Number of A-grade shots |
| `b_count` | integer | NOT NULL | Number of B-grade shots |
| `c_count` | integer | NOT NULL | Number of C-grade shots |
| `a_percentage` | decimal | NULL | Percentage of A shots (null if invalid) |
| `avg_carry` | decimal | NULL | Average carry distance (yards) |
| `avg_ball_speed` | decimal | NULL | Average ball speed (mph) |
| `avg_spin` | decimal | NULL | Average spin rate (rpm) |
| `avg_descent` | decimal | NULL | Average descent angle (degrees) |
| `analyzed_at` | timestamp | NOT NULL | When analysis was performed |

### Primary Key
- `subsession_id`

### Foreign Keys
- `session_id` → `sessions.session_id`
- `kpi_template_hash` → `kpi_templates.template_hash`

### Unique Constraints
- (`session_id`, `club`, `kpi_template_hash`) — prevents duplicate analysis

### Check Constraints
- `shot_count > 0`
- `a_count + b_count + c_count = shot_count`
- `a_count >= 0`, `b_count >= 0`, `c_count >= 0`
- `a_percentage` is NULL if `validity_status = 'invalid_insufficient_data'`
- `a_percentage >= 0.0 AND a_percentage <= 100.0` (when not NULL)

**Cross-Table Constraint (Application-Level or Trigger):**
- `analyzed_at >= session.session_date` — Analysis cannot predate session occurrence

**Enforcement:** This constraint requires a join to the `sessions` table and cannot be enforced via standard CHECK constraint syntax. Implementations must enforce this via:
- Application-level validation before insertion
- Database trigger (implementation-specific)
- Transaction-level validation

### Indexes (Recommended)
- `session_id` (FK index)
- `kpi_template_hash` (FK index)
- (`club`, `analyzed_at`) (for trend queries)
- `validity_status` (for filtering queries)

### Enum: validity_status

| Value | Description |
|-------|-------------|
| `invalid_insufficient_data` | shot_count < 5 — cannot compute meaningful statistics |
| `valid_low_sample_warning` | 5 ≤ shot_count < 15 — results valid but limited confidence |
| `valid` | shot_count ≥ 15 — sufficient sample for reliable analysis |

**Implementation Note:** The specific threshold values (5, 15) are configurable constants, not hardcoded in schema. These are conservative defaults.

---

## 3.5 Entity: KPI Template

### Table Name
`kpi_templates`

### Columns

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| `template_hash` | string(64) | NOT NULL | SHA-256 hash of canonical_json (hex encoding) |
| `schema_version` | string | NOT NULL | Template schema version (e.g., "1.0") |
| `club` | string | NOT NULL | Target club identifier |
| `canonical_json` | text | NOT NULL | The canonical JSON representation |
| `created_at` | timestamp | NOT NULL | When template was first created (original authorship) |
| `imported_at` | timestamp | NULL | When template was imported locally (NULL if locally created) |

### Primary Key
- `template_hash`

### Foreign Keys
- None

### Unique Constraints
- `template_hash` (enforced by PK)

### Check Constraints
- `length(template_hash) = 64` (SHA-256 hex is always 64 chars)
- `template_hash` matches regex `^[0-9a-f]{64}$` (lowercase hex)
- `canonical_json` is valid JSON (implementation-dependent validation)

### Indexes (Recommended)
- `club` (for listing templates by club)

### Critical Invariant

**The `template_hash` field must NEVER be recomputed from `canonical_json` after initial storage.**

Rationale: Bugs in canonicalization or hashing logic would cause historical references to break. The hash is set once at insertion and treated as immutable truth.

---

## 3.6 Entity: Template Alias

### Table Name
`template_aliases`

### Columns

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| `alias_id` | integer | NOT NULL | Primary key (auto-increment) |
| `template_hash` | string(64) | NOT NULL | Foreign key to KPI template |
| `display_name` | string | NOT NULL | Human-readable name for UI/CLI |
| `notes` | text | NULL | User notes about this template |
| `created_at` | timestamp | NOT NULL | When alias was created |
| `updated_at` | timestamp | NULL | When alias was last modified |

### Primary Key
- `alias_id`

### Foreign Keys
- `template_hash` → `kpi_templates.template_hash`

### Unique Constraints
- `display_name` (prevents duplicate names within local system)

### Check Constraints
- `display_name` is not empty string
- `length(display_name) <= 255`

### Indexes (Recommended)
- `template_hash` (FK index)
- `display_name` (for name lookups)

---

## 3.7 Entity: Projection (Derived)

### Table Name
`projections` (optional — may not be persisted)

### Columns

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| `projection_id` | integer | NOT NULL | Primary key (auto-increment) |
| `subsession_id` | integer | NOT NULL | Foreign key to club sub-session |
| `projection_json` | text | NOT NULL | Pre-computed JSON export |
| `generated_at` | timestamp | NOT NULL | When projection was generated |

### Primary Key
- `projection_id`

### Foreign Keys
- `subsession_id` → `club_subsessions.subsession_id`

### Unique Constraints
- `subsession_id` (one cached projection per sub-session)

### Check Constraints
- None (derived data has no business logic constraints)

### Indexes (Recommended)
- `subsession_id` (unique FK index)

### Critical Notes

1. **This table is entirely optional** — projections can be generated on-the-fly
2. **Entries may be deleted at any time** without data loss
3. **Projections are never imported** — they are export-only
4. **Schema may evolve freely** — no backward compatibility required

---

## 3.8 Referential Integrity Rules

### Cascade Behavior

| Parent Table | Child Table | On Delete | On Update |
|--------------|-------------|-----------|-----------|
| `sessions` | `club_subsessions` | **RESTRICT** | CASCADE |
| `kpi_templates` | `club_subsessions` | **RESTRICT** | CASCADE |
| `kpi_templates` | `template_aliases` | CASCADE | CASCADE |
| `club_subsessions` | `projections` | CASCADE | CASCADE |

**Rationale:**

- **RESTRICT on sessions/templates → subsessions:** Historical data must not be deleted. Attempting to delete a referenced template or session should fail.
- **CASCADE on templates → aliases:** Deleting a template (rare) should clean up aliases automatically.
- **CASCADE on subsessions → projections:** Projections are derived; they should be cleaned up when source data is deleted.

---

## 3.9 Schema Validation Rules

Implementations must enforce:

1. **Foreign key constraints** — No orphaned references
2. **Check constraints** — All business logic validations
3. **Unique constraints** — Prevent logical duplicates
4. **NOT NULL constraints** — Required fields are never NULL
5. **Enum validation** — Only valid enum values accepted

**Prohibited:** "Soft validation" where invalid data is accepted and flagged. The schema must enforce correctness.

---

## 3.10 Schema Evolution Constraints

### Allowed Changes (Phase 1+)

- Adding new optional columns (NULL allowed)
- Adding new indexes
- Adding new tables (not referenced by existing tables)

### Prohibited Changes

- Removing columns referenced in queries
- Changing primary keys or foreign keys
- Relaxing NOT NULL constraints
- Modifying enum values (breaks historical data)
- Changing template_hash computation (breaks content-addressing)

**Migration Strategy:** New columns and tables only. Existing schema is immutable once released.

---

[Next: Identity & Immutability Rules →](04_identity_and_immutability.md)
