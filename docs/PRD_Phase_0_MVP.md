# Product Requirements Document: RAID Phase 0 (MVP)

**Project Codename:** RAID  
**Document Version:** 1.0  
**Date:** 2026-01-28  
**Status:** Active  

---

## 1. Overview

### 1.1 Product Goal

Replace spreadsheet-based analysis of launch-monitor sessions with a **trusted, repeatable, local analytics loop** that:

- Ingests CSV session data from launch monitors (primarily Rapsodo MLM2Pro)
- Evaluates shots using versioned KPI templates
- Persists results locally in SQLite
- Supports trend analysis by club over time
- Is future-proof for iOS deployment and optional Nostr-based sharing

### 1.2 Phase Scope

This document covers **Phase 0 / MVP** only. This is a personal analytics tool for serious golfers, not a consumer application. The scope is intentionally narrow to validate the core value proposition before expansion.

### 1.3 Background

Launch monitors produce large volumes of raw shot data but provide weak interpretation beyond basic averages. The problem is not data collection—it is **meaning**. This project addresses that gap by applying explicit, versioned standards (KPIs) to practice session data.

---

## 2. Core Design Constraints

These constraints are **mandatory** and must not be relaxed without explicit PRD amendment.

### 2.1 Local-First Architecture

- **SQLite** is the **authoritative local datastore** for all persisted entities.
- **JSON** is used only for:
  - Exporting shareable "projections" (read-only derived artifacts)
  - Importing KPI templates from external sources
- There is **no requirement** for full SQLite ↔ JSON round-trip conversion.
- The system must function fully offline with no network dependency.

**Rationale:** Local-first ensures data ownership, privacy, and eliminates sync complexity for MVP. SQLite provides ACID guarantees and is natively supported on iOS.

### 2.2 Immutable Artifacts

- **Raw session logs** are immutable after ingestion. Original CSV data is preserved as-is.
- **KPI templates** are immutable artifacts. Once a template is created and hashed, its content never changes.
- "Editing" a KPI template means creating a **new version** with a new hash. The original template remains unchanged and accessible.

**Rationale:** Immutability guarantees reproducibility. Any historical analysis can be re-validated against the exact KPI version used at the time.

---

## 3. Functional Requirements

### 3.A Session Ingestion

#### 3.A.1 Input Format

The system ingests CSV files exported from launch monitors. The primary target is Rapsodo MLM2Pro "Shot Export" format.

**Supported Session Types:**

| Session Type | Format | Support Status | Rationale |
|--------------|--------|----------------|-----------|
| Shot Export | Single header, flat shot list | ✅ Supported (MVP) | Standard practice analysis with full swings |
| Target Range | Multi-block, target-grouped | ❌ Explicitly Unsupported | Different swing intent and success criteria |

**Shot Export Format Variants:**

The system must support two file structure variants:

*Standard Format (current Rapsodo website exports):*
- Row 1: Header row with 18 column names
- Rows 2-N: Shot data (one shot per row)
- Optional: Footer summaries (`"Average"`, `"Std. Dev."`) — must be excluded if present

*Legacy Format (older exports):*
- Row 1: Metadata line (e.g., `"Rapsodo MLM2PRO: User Name - MM/DD/YYYY HH:MM AM/PM"`)
- Row 2: Empty (comma placeholders)
- Row 3: Header row with 18 column names
- Rows 4-N: Shot data (one shot per row)
- Optional: Footer summaries (`"Average"`, `"Std. Dev."`) — must be excluded if present

**Header Detection:** System must search rows 1-3 for a row containing both `"Club Type"` and `"Ball Speed"` column headers. This row is treated as the header regardless of position.

**Key Characteristics:**
- Footer rows are optional in both variants
- **May contain shots from multiple clubs in a single file**
- All 18 columns are present in both variants

**Target Range Format (Unsupported):**
Target Range exports group shots by target distance with repeated headers. These are explicitly unsupported because:
- Users are hitting at specific distance targets, not making natural full swings
- The success metric is "hit percentage" (e.g., `"1/3 (33%)"`) not strike quality
- KPI thresholds assume full swings and do not apply to controlled partial swings
- The multi-block structure with repeated headers requires different parsing logic

Detection rule: Target Range files are identifiable by a distance/hit-percentage marker in row 2 (e.g., `"166 Yds","1/3 (33%)"`). Ingest should detect and reject these files with a clear error message.

#### 3.A.2 Session Model

A single CSV ingest produces:

| Entity | Cardinality | Description |
|--------|-------------|-------------|
| Session | 1 | Logical container representing one practice session |
| Club Sub-Session | 1..N | Per-club grouping of shots within the session |

**Design Decision:** Sessions are not tied to a single club because real practice sessions commonly involve multiple clubs. The unit of analysis and trending is the **club sub-session**, not the session itself.

#### 3.A.3 Shot Validation

Valid shot rows must satisfy:
- All required metrics are present and numeric
- Row is not a footer summary (Average, Std Dev)
- Row is not a metadata or blank row

Required metrics for classification:
- Ball Speed
- Smash Factor
- Descent Angle
- Spin Rate
- Carry Distance (for reporting, not classification)

Invalid rows are logged with rejection reason but do not halt ingestion.

---

### 3.B Limited Datapoint Handling

The system must **never overstate confidence** when sample sizes are small.

#### 3.B.1 Club Sub-Session Metadata

Each club sub-session record must include:

| Field | Type | Description |
|-------|------|-------------|
| `shot_count` | integer | Total valid shots for this club |
| `validity_status` | enum | See below |

#### 3.B.2 Validity Status Enum

```
validity_status:
  - invalid_insufficient_data   # Cannot compute meaningful statistics
  - valid_low_sample_warning    # Results computed but confidence is limited
  - valid                       # Sufficient data for reliable analysis
```

#### 3.B.3 Validity Thresholds

| Status | Threshold | Rationale |
|--------|-----------|-----------|
| `invalid_insufficient_data` | shot_count < 5 | Cannot meaningfully compute percentages |
| `valid_low_sample_warning` | 5 ≤ shot_count < 15 | Results valid but may not represent true capability |
| `valid` | shot_count ≥ 15 | Sufficient sample for reliable trend analysis |

**Configuration:** Thresholds are configurable constants, not hardcoded magic numbers. These are **club-agnostic defaults** for Phase 0 and are deliberately conservative. Future phases may introduce club-specific thresholds if empirical data warrants differentiation.

#### 3.B.4 Treatment of Invalid/Low-Sample Data

- Invalid and low-sample sessions **are still stored**
- They are **not silently excluded** from the database
- They **may be excluded** from trend calculations (user-configurable filter)
- Query results must clearly indicate validity status

---

### 3.C KPI Template System

#### 3.C.1 Template Definition

KPI templates are defined as **canonical JSON artifacts** with the following structure:

```json
{
  "schema_version": "1.0",
  "club": "7i",
  "metrics": {
    "ball_speed": {
      "a_min": 108.92,
      "b_min": 106.60,
      "direction": "higher_is_better"
    },
    "smash_factor": {
      "a_min": 1.32,
      "b_min": 1.29,
      "direction": "higher_is_better"
    },
    "descent_angle": {
      "a_min": 48.42,
      "b_min": 46.30,
      "direction": "higher_is_better"
    },
    "spin_rate": {
      "a_min": 4854,
      "b_min": 4669,
      "direction": "higher_is_better"
    }
  },
  "aggregation_method": "worst_metric",
  "created_at": "2026-01-28T05:03:44Z",
  "provenance": {
    "method": "percentile_baseline",
    "source_session": "fixture_mlm2pro_shotexport_anonymized.csv",
    "n_shots_used": 59
  }
}
```

#### 3.C.2 Canonical JSON Requirements

To ensure deterministic hashing:

- **Deterministic key ordering:** Keys sorted alphabetically at all nesting levels
- **Normalized numeric representation:** No trailing zeros, consistent precision. Numeric normalization must be deterministic and language-independent (e.g., string-based formatting or scaled-integer representation). The specific mechanism is implementation-defined, but cross-platform ambiguity is forbidden.
- **No whitespace variation:** Compact JSON (no pretty-printing for hashing)
- **UTF-8 encoding:** Always UTF-8 with no BOM

#### 3.C.3 Template Identity

Template identity is defined by content hash:

```
template_hash = sha256(canonical_template_json)
```

- The hash is the **primary key** for template storage and reference
- Templates with identical content will have identical hashes (deduplication)
- Template names/aliases are metadata, not identity

**Constraint:** Once persisted, `template_hash` is treated as authoritative and must never be recomputed unless the `canonical_json` payload itself is modified. This prevents migration and read-path bugs from silently corrupting template identity.

#### 3.C.4 Template Storage

Templates are stored locally keyed by `template_hash`. The storage model:

| Field | Type | Description |
|-------|------|-------------|
| `template_hash` | string (64 hex) | SHA-256 of canonical JSON (primary key) |
| `schema_version` | string | Template schema version |
| `club` | string | Target club identifier |
| `canonical_json` | text | The canonical JSON content |
| `created_at` | timestamp | When this template was first stored locally |
| `imported_at` | timestamp | When imported (null if locally created) |

#### 3.C.5 Shot Classification

Classification uses the **worst-metric ("floor") model**:

- Each shot is graded per-metric (A/B/C based on thresholds)
- A shot's overall grade equals its **lowest-performing metric**
- Examples:
  - A, A, B, A → **B**
  - A, A, A, C → **C**
  - A, A, A, A → **A**

**Rationale:** An A-shot represents no meaningful weaknesses. This strict model favors consistency and produces conservative, trustworthy classifications.

---

### 3.D KPI Template Import / Sharing

#### 3.D.1 Import Process

When a user imports a KPI template (from file, URL, or future Nostr event):

1. **Parse** the incoming JSON
2. **Validate** against schema requirements
3. **Canonicalize** JSON (sort keys, normalize numbers)
4. **Compute** `template_hash = sha256(canonical_json)`
5. **Check** if template_hash already exists locally
6. **Store** if new; skip if duplicate (idempotent)
7. **Record** import metadata (source, timestamp)

#### 3.D.2 Template Aliases

Imported templates may be given **local aliases** for display purposes:

| Field | Type | Description |
|-------|------|-------------|
| `alias_id` | integer | Local alias identifier |
| `template_hash` | string | Reference to template |
| `display_name` | string | Human-readable name |
| `notes` | text | User notes about this template |

Aliases are local metadata only—they do not affect template identity.

#### 3.D.3 Template Modification

If a user "edits" an imported or existing template:

1. Create a new template artifact with the changes
2. Compute new `template_hash` for the modified content
3. Store as a new template (original remains unchanged)
4. Optionally create an alias linking to the new template

**Constraint:** Existing templates are never mutated. History is preserved.

---

### 3.E Analysis Persistence

#### 3.E.1 Club Sub-Session Results

Club sub-session analysis results are persisted with:

| Field | Type | Description |
|-------|------|-------------|
| `subsession_id` | integer | Primary key |
| `session_id` | integer | Parent session reference |
| `club` | string | Club identifier |
| `kpi_template_hash` | string | Reference to KPI template used |
| `shot_count` | integer | Total valid shots |
| `validity_status` | enum | Data quality indicator |
| `a_count` | integer | Shots classified A |
| `b_count` | integer | Shots classified B |
| `c_count` | integer | Shots classified C |
| `a_percentage` | decimal | A% (null if invalid) |
| `avg_carry` | decimal | Average carry distance |
| `avg_ball_speed` | decimal | Average ball speed |
| `avg_spin` | decimal | Average spin rate |
| `avg_descent` | decimal | Average descent angle |
| `analyzed_at` | timestamp | When analysis was performed |

#### 3.E.2 Projection Cache

Optionally, a JSON "projection" may be cached for export:

| Field | Type | Description |
|-------|------|-------------|
| `subsession_id` | integer | Foreign key |
| `projection_json` | text | Pre-computed export JSON |
| `generated_at` | timestamp | When projection was generated |

**Constraint:** Projections are derived artifacts, regenerable from source data. They are not authoritative.

---

### 3.F Query & Reporting

#### 3.F.1 Required Queries

The system must support (CLI acceptable for MVP):

| Query | Description |
|-------|-------------|
| List sessions | Show all sessions with date, club count, shot count |
| List by club | Show all sub-sessions for a specific club |
| Session detail | Show full breakdown of a single session |
| Trend report | Compute rolling metrics for a club over time |

#### 3.F.2 Trend Calculations

Trend analysis for a given club:

- **A% over time:** Rolling percentage of A-shots
- **Rolling N-session average:** Configurable window (default: 3 sessions)
- **Filter options:** Exclude invalid/low-sample sessions from trend

#### 3.F.3 Output Formats

- Terminal output (human-readable)
- CSV export (for external analysis)
- JSON projection (for sharing)

---

## 4. Data Model

### 4.1 Entity Relationship Diagram (Conceptual)

```
┌──────────────────────┐
│       Session        │
├──────────────────────┤
│ session_id (PK)      │
│ session_date         │
│ source_file          │
│ device_type          │
│ location             │
│ ingested_at          │
└──────────┬───────────┘
           │ 1
           │
           │ N
┌──────────▼───────────┐        ┌──────────────────────┐
│   Club Sub-Session   │        │    KPI Template      │
├──────────────────────┤        ├──────────────────────┤
│ subsession_id (PK)   │   N:1  │ template_hash (PK)   │
│ session_id (FK)      │───────>│ schema_version       │
│ club                 │        │ club                 │
│ kpi_template_hash(FK)│        │ canonical_json       │
│ shot_count           │        │ created_at           │
│ validity_status      │        └──────────────────────┘
│ a_count, b_count ... │
│ analyzed_at          │        ┌──────────────────────┐
└──────────────────────┘        │  Template Alias      │
                                ├──────────────────────┤
                                │ alias_id (PK)        │
                                │ template_hash (FK)   │
                                │ display_name         │
                                │ notes                │
                                └──────────────────────┘
```

### 4.2 Design Rationale

#### Why Sessions Are Not Tied to a Single Club

Real practice sessions frequently involve multiple clubs. A typical session might include:
- 20 shots with 7-iron for baseline warm-up
- 15 shots with wedge for short game work
- 10 shots with driver for distance check

Modeling this as three separate "sessions" would lose the contextual relationship and complicate date-based queries. The hierarchical model (Session → Club Sub-Sessions) preserves both the logical grouping and the per-club analysis unit.

#### Why KPI Templates Are Content-Addressed

Content-addressing (hash-based identity) provides:

1. **Deduplication:** Identical templates imported from different sources resolve to the same hash
2. **Integrity:** Any modification produces a new hash, preventing silent corruption
3. **Provenance:** Historical analyses reference the exact template used, not a mutable pointer
4. **Interoperability:** External systems can independently compute the same hash for the same template

Name-based identity would create ambiguity when templates are shared across users or updated over time.

#### Why Projections Are Derived Artifacts

Projections (JSON exports) are:

1. **Derived:** Computed from authoritative SQLite data
2. **Immutable:** Once generated, a projection represents a point-in-time snapshot
3. **Not round-tripped:** Projections are export-only; importing a projection does not reconstruct the original session

This separation ensures:
- The local database remains the single source of truth
- Shared projections cannot corrupt or conflict with local data
- Analysis integrity is maintained even when projections are distributed

---

## 5. Future-Proofing

This section describes future capabilities that inform current design but are **not implemented in Phase 0**.

### 5.1 Nostr Integration (Phase 1+)

#### KPI Templates as Nostr Events

KPI templates map cleanly to NIP-01 compliant Nostr events:

```json
{
  "kind": 30078,
  "content": "<canonical_template_json>",
  "tags": [
    ["d", "<template_hash>"],
    ["t", "golf-kpi-template"],
    ["club", "7i"]
  ]
}
```

Key properties:
- **Event ID** is author-specific (includes pubkey and signature)
- **Template identity** is payload-hash-based (the `d` tag contains the content hash)
- Multiple authors can publish the same template; all resolve to the same `template_hash`

#### Session Projections as Nostr Events

Published session projections:
- Contain summary statistics only (not raw shot data)
- Are derived and immutable (point-in-time snapshots)
- Are **not** imported back into the local database
- May include achievement markers (PRs, streaks)

### 5.2 iOS Deployment

The architecture is designed for iOS compatibility:

- **SQLite:** Native iOS support via SQLite3 framework
- **Codable JSON:** Template JSON maps directly to Swift Codable structs
- **Local-first:** No network dependency for core functionality
- **File import:** iOS document picker can import CSV/JSON files

No changes to the core data model are required for iOS port.

### 5.3 Multi-Device Sync (Out of Scope)

While the architecture does not preclude future sync capabilities, **no sync mechanism is specified for Phase 0**. Potential future approaches:
- SQLite file export/import
- Nostr-based sync events
- iCloud document sync

These are explicitly deferred.

---

## 6. Explicit Non-Goals

The following are **explicitly out of scope** for Phase 0:

| Non-Goal | Rationale |
|----------|-----------|
| Cloud sync | Adds complexity; local-first is sufficient for MVP |
| Collaborative editing | Single-user tool; collaboration deferred |
| KPI auto-tuning | Standards are deliberate, not reactive |
| Advanced statistical smoothing | Keep analysis transparent and reproducible |
| UI beyond minimal CLI | Validate core value before investing in UI |
| On-course scoring | Different product class; deferred to Phase 3+ |
| Real-time data streaming | Batch CSV import is sufficient for MVP |
| Multiple device sync | Single-device local-first for MVP |

---

## 7. Success Criteria

Phase 0 is successful when:

| Criterion | Measurement |
|-----------|-------------|
| Mixed-club session ingestion | Single CSV with multiple clubs produces correct sub-sessions |
| Small sample handling | Sessions with <5 shots are flagged but stored; <15 shots show warnings |
| Deterministic template identity | Same template JSON → same hash, regardless of import source |
| Historical analysis validity | Changing active KPI does not alter past session results |
| Zero spreadsheet dependency | Complete workflow from CSV → analysis → trends without Excel |
| Reproducible results | Same input + same KPI template → identical output |

---

## 8. Assumptions

The following assumptions were made during PRD authoring:

### 8.1 Input Data Assumptions

- Primary input format is Rapsodo MLM2Pro "Shot Export" CSV (two file structure variants supported)
- TrackMan format support is secondary but structurally similar
- CSV files are well-formed UTF-8 (possibly with BOM)
- Header detection is flexible (searches rows 1-3 for column headers)
- Footer rows are optional; when present, follow consistent labeling (Average, Std Dev)
- Metadata row is optional (may or may not be present in exports)
- Target Range exports are detectable by row 2 format (distance/hit-percentage marker) and should be rejected with a clear error message

### 8.2 Usage Assumptions

- Single user per installation (no multi-user auth)
- Session volumes: ~1-3 sessions per week, ~50-100 shots per session
- Trend analysis window: typically 5-20 sessions per club
- KPI template changes: rare (monthly or less)

### 8.3 Technical Assumptions

- Python 3.10+ available for CLI tooling
- SQLite 3.35+ for JSON functions if needed
- Standard filesystem access for CSV import
- No network required for core functionality

---

## 9. Appendix

### 9.1 Glossary

| Term | Definition |
|------|------------|
| Session | A single practice session, typically one CSV import |
| Club Sub-Session | Shots for one club within a session |
| KPI Template | Immutable artifact defining classification thresholds |
| Template Hash | SHA-256 of canonical template JSON; serves as identity |
| Projection | Derived JSON export of session results |
| Validity Status | Data quality indicator for sample size |
| A/B/C Classification | Shot quality grade based on KPI thresholds |

### 9.2 Related Documents

- [KPI Philosophy and Classification](kpi_philosophy_and_classification.md)
- [KPI Generation PRD](kpi_generation_prd.md)
- [Project Origin and MVP Scope](private/project_origin_and_mvp_scope.md)

### 9.3 Version History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-28 | — | Initial PRD |

---

### 9.4 Input Format Specification: Rapsodo MLM2Pro

This section documents the CSV export formats from Rapsodo MLM2Pro launch monitors.

#### 9.4.1 Shot Export Format (Supported)

**File Structure Variants:**

The system supports two file structure variants for Shot Export format:

*Standard Format (current Rapsodo website exports):*

| Row | Content | Example |
|-----|---------|---------|
| 1 | Header row | `"Club Type","Club Brand","Club Model",...` |
| 2-N | Shot data rows | `"7i",,,"156.4","163.0",...` |
| N+1 | Average footer (optional) | `"Average",,,"152.0","158.2",...` |
| N+2 | Std Dev footer (optional) | `"Std. Dev.",,,"8.4","8.0",...` |

*Legacy Format (older exports):*

| Row | Content | Example |
|-----|---------|---------|
| 1 | Metadata line | `"Rapsodo MLM2PRO: Daniel Wyler - 01/27/2026 4:30 PM"` |
| 2 | Empty (comma placeholders) | `,,,,,,,,,,,,,,,,` |
| 3 | Header row | `"Club Type","Club Brand",...` |
| 4-N | Shot data rows | `"7i",,,"156.4","163.0",...` |
| N+1 | Average footer (optional) | `"Average",,,"152.0","158.2",...` |
| N+2 | Std Dev footer (optional) | `"Std. Dev.",,,"8.4","8.0",...` |

**Implementation Note:** Header detection must search rows 1-3 for `"Club Type"` and `"Ball Speed"` columns rather than assuming header position.

**Column Dictionary (18 columns):**

| # | Column Name | Data Type | Used for Classification | Description |
|---|-------------|-----------|------------------------|-------------|
| 1 | Club Type | string | ✅ (grouping) | Club identifier (e.g., "7i", "PW", "DR") |
| 2 | Club Brand | string | ❌ | Equipment brand (often empty) |
| 3 | Club Model | string | ❌ | Equipment model (often empty) |
| 4 | Carry Distance | decimal | ✅ (reporting) | Ball carry distance in yards |
| 5 | Total Distance | decimal | ❌ | Total distance including roll |
| 6 | Ball Speed | decimal | ✅ **Classification** | Ball velocity in mph |
| 7 | Launch Angle | decimal | ❌ | Vertical launch angle in degrees |
| 8 | Launch Direction | decimal | ❌ | Horizontal launch angle in degrees |
| 9 | Apex | decimal | ❌ | Maximum ball height in feet |
| 10 | Side Carry | decimal | ❌ | Lateral deviation in yards |
| 11 | Club Speed | decimal | ❌ | Clubhead velocity in mph |
| 12 | Smash Factor | decimal | ✅ **Classification** | Ball speed ÷ Club speed ratio |
| 13 | Descent Angle | decimal | ✅ **Classification** | Landing angle in degrees |
| 14 | Attack Angle | decimal | ❌ | Angle of attack in degrees |
| 15 | Club Path | decimal | ❌ | Club path angle in degrees |
| 16 | Club Data Est Type | integer | ❌ | Estimation type flag (0=measured) |
| 17 | Spin Rate | decimal | ✅ **Classification** | Ball spin in RPM |
| 18 | Spin Axis | decimal | ❌ | Spin tilt angle in degrees |

**Classification Metrics Subset:**
Only 4 metrics are used for A/B/C classification (per KPI Generation PRD):
- Ball Speed (column 6)
- Smash Factor (column 12)
- Descent Angle (column 13)
- Spin Rate (column 17)

Carry Distance (column 4) is captured for reporting but does not affect classification.

**Footer Detection:**
Rows where column 1 matches (case-insensitive):
- `"Average"`, `"Avg"`
- `"Std. Dev."`, `"Std Dev"`, `"Standard Deviation"`

These rows must be excluded from shot analysis.

#### 9.4.2 Target Range Format (Unsupported)

**File Structure:**
Target Range exports contain multiple blocks, one per target distance:

```
Row 1: Metadata line
Row 2: Target header — "166 Yds","1/3 (33%)"
Row 3: Column headers (18 columns, same as Shot Export)
Rows 4-N: Shot data for this target
Row N+1: Average footer for this target
Row N+2: Std Dev footer for this target
Row N+3: (blank or next target header)
... repeats for each target distance ...
```

**Detection Rule:**
Row 2 contains a target distance and hit percentage:
- Pattern: `"<number> Yds","<hits>/<attempts> (<percent>%)"`
- Example: `"166 Yds","1/3 (33%)"`

If row 2 matches this pattern, the file is a Target Range export and should be rejected.

**Why Unsupported:**
1. Swing intent differs (distance control vs. natural full swing)
2. KPI thresholds assume full swings; partial swings produce different metrics
3. Success is already measured by hit percentage
4. Multi-block parsing requires different logic

---

*This document is the authoritative specification for RAID Phase 0. Changes require explicit versioning and review.*
