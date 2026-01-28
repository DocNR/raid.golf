# 6. Session & Sub-Session Invariants

[← Back to Index](00_index.md)

---

## 6.1 Overview

This section defines cardinality constraints, data retention rules, and validity status handling for sessions and sub-sessions.

---

## 6.2 Session-to-Sub-Session Cardinality

### 6.2.1 One-to-Many Relationship

**Constraint:** A session may contain **one or more** club sub-sessions.

```
Session 1
  ├─ Sub-session: 7i (20 shots)
  ├─ Sub-session: PW (15 shots)
  └─ Sub-session: DR (10 shots)
```

**Rationale:** Real practice sessions commonly involve multiple clubs. Enforcing single-club sessions would fragment natural session grouping.

### 6.2.2 Sub-Session-to-Session Relationship

**Constraint:** Each sub-session belongs to **exactly one** session.

**Enforced by:** Foreign key `club_subsessions.session_id → sessions.session_id`

**Prohibited:** Sub-sessions cannot be shared across sessions or orphaned.

### 6.2.3 Sub-Session-to-Template Relationship

**Constraint:** Each sub-session references **exactly one** KPI template.

**Enforced by:** Foreign key `club_subsessions.kpi_template_hash → kpi_templates.template_hash`

**Re-analysis Rule:** To analyze the same session/club with a different template:
- Create a **new sub-session** with the new template
- Unique constraint prevents duplicate (session, club, template) combinations
- Original sub-session remains unchanged

---

## 6.3 Validity Status Handling

### 6.3.1 Status Definitions

Per PRD Section 3.B.2, three validity statuses are defined:

| Status | Threshold | Meaning |
|--------|-----------|---------|
| `invalid_insufficient_data` | shot_count < 5 | Cannot compute meaningful statistics |
| `valid_low_sample_warning` | 5 ≤ shot_count < 15 | Results valid but limited confidence |
| `valid` | shot_count ≥ 15 | Sufficient sample for reliable analysis |

### 6.3.2 Threshold Configuration

**Default Values:**
- Minimum for any analysis: 5 shots
- Minimum for high confidence: 15 shots

**Implementation:**
- Thresholds are **configurable constants**, not hardcoded magic numbers
- Same thresholds apply to all clubs (Phase 0 simplification)
- Future phases may introduce club-specific thresholds

### 6.3.3 Computation Rules

**When status = `invalid_insufficient_data`:**
- `a_percentage` MUST be NULL
- `avg_carry`, `avg_ball_speed`, `avg_spin`, `avg_descent` MAY be NULL or computed
- Sub-session is still stored (not rejected)

**When status = `valid_low_sample_warning` or `valid`:**
- `a_percentage` MUST be computed and stored
- All average metrics MUST be computed

### 6.3.4 Data Retention Rule

**Critical Invariant:** Invalid and low-sample sessions **MUST be stored**.

**Rationale:**
1. **Completeness:** Historical record must be complete
2. **Transparency:** Users see all data, not filtered view
3. **Flexibility:** Users can apply their own thresholds in queries
4. **Audit trail:** No silent data exclusion

**Prohibited:** Rejecting or silently discarding sessions with low shot counts.

---

## 6.4 Query Filtering by Validity

### 6.4.1 Trend Analysis Filters

When computing trends (e.g., rolling A% average):

**User-configurable filters:**
- Include all sub-sessions (no filter)
- Exclude `invalid_insufficient_data` only
- Exclude both `invalid_insufficient_data` and `valid_low_sample_warning`

**Default behavior:** Exclude `invalid_insufficient_data`, include warnings with visual indicator.

### 6.4.2 Display Rules

Sub-sessions with `valid_low_sample_warning` should be:
- Included in results by default
- Visually distinguished (e.g., ⚠️ warning icon)
- Accompanied by explanatory text

**Example Display:**

```
Session: 2026-01-27
  7i: 18 shots → 72.2% A-shots ✓
  PW: 8 shots → 62.5% A-shots ⚠️ (Low sample size)
  DR: 3 shots → N/A ❌ (Insufficient data)
```

### 6.4.3 No Silent Exclusion

**Prohibited:** Queries that filter out low-sample data without user knowledge.

**Required:** Any filter applied must be:
- Explicit in the query parameters
- Visible in result metadata
- Documented in output

---

## 6.5 Shot Count Constraints

### 6.5.1 Minimum Shot Count

**Constraint:** `shot_count > 0` (enforced by CHECK constraint)

**Rationale:** A sub-session with zero shots has no analytical value and represents a data integrity issue.

### 6.5.2 Classification Consistency

**Constraint:** `a_count + b_count + c_count = shot_count` (enforced by CHECK constraint)

**Rationale:** Every valid shot must be classified. No shots can be "unclassified" or double-counted.

### 6.5.3 Non-Negative Counts

**Constraint:** `a_count >= 0`, `b_count >= 0`, `c_count >= 0` (enforced by CHECK constraints)

**Rationale:** Negative shot counts are logically impossible.

---

## 6.6 Temporal Constraints

### 6.6.1 Analysis After Session

**Constraint:** `analyzed_at >= session.session_date`

**Rationale:** Cannot analyze a session before it occurred (causality violation).

**Enforcement:** Application-level validation (requires join to verify).

### 6.6.2 Ingestion After Session

**Constraint:** `ingested_at >= session_date`

**Rationale:** Cannot ingest data before the session occurred.

**Enforcement:** CHECK constraint on `sessions` table.

### 6.6.3 Timestamp Precision

**Requirement:** Timestamps should include timezone information (ISO-8601 with timezone).

**Example:** `2026-01-28T17:30:00Z` (UTC) or `2026-01-28T12:30:00-05:00` (EST)

**Rationale:** Prevents ambiguity when analyzing sessions across time zones.

---

## 6.7 Club Identifier Conventions

### 6.7.1 Standardized Format

**Recommendation:** Use Rapsodo's club naming convention:
- Irons: `7i`, `8i`, `9i`
- Wedges: `PW`, `GW`, `SW`, `LW`
- Woods: `3w`, `5w`
- Driver: `DR` or `Driver`
- Hybrid: `3h`, `4h`

**Flexibility:** System does not enforce specific format (club is a string field).

**Case sensitivity:** Club identifiers are case-sensitive (`7i` ≠ `7I`).

### 6.7.2 Club Grouping

For queries that group by club:
- Match exact string
- No normalization or "fuzzy matching"
- User responsible for consistent naming

**Future consideration:** Club alias table for normalization (Phase 1+).

---

## 6.8 Session Metadata Constraints

### 6.8.1 Required Fields

**Mandatory:**
- `session_date` (NOT NULL)
- `source_file` (NOT NULL)
- `ingested_at` (NOT NULL)

**Optional:**
- `device_type` (NULL allowed)
- `location` (NULL allowed)

### 6.8.2 Source File Handling

**Purpose:** Historical reference only — file path preserved but not required for analysis.

**No constraint on:**
- File existence (file may be moved/deleted after ingestion)
- Path format (absolute vs relative)
- Path uniqueness (same file may be imported multiple times)

**Rationale:** Source file is audit metadata, not functional dependency.

---

## 6.9 Duplicate Analysis Prevention

### 6.9.1 Unique Constraint

**Constraint:** (`session_id`, `club`, `kpi_template_hash`) UNIQUE

**Effect:** Prevents analyzing the same session/club combination with the same template twice.

**Allowed:** Re-analyzing with a **different** template creates a new sub-session.

### 6.9.2 Idempotent Import

If a user re-analyzes a session:
- With the **same template:** Unique constraint violation → error (or skip)
- With a **different template:** New sub-session created successfully

**Design decision:** Prefer explicit over implicit. No silent overwriting.

---

## 6.10 Multi-Club Session Requirements

### 6.10.1 Club Detection

When ingesting a CSV with multiple clubs:

1. **Parse all shots** and extract club identifiers
2. **Group shots by club** (exact string match)
3. **Create one sub-session per unique club**
4. Each sub-session references the same parent session

### 6.10.2 Mixed-Club Files

**Supported:** Single CSV file containing shots from multiple clubs.

**Example:**

```
Session: 2026-01-27 (from mixed_clubs.csv)
  ├─ 7i: 20 shots
  ├─ PW: 15 shots
  └─ DR: 10 shots
```

**Rationale:** Real Rapsodo exports often contain mixed clubs from a single practice session.

---

## 6.11 Invariants Summary

### Session Invariants (MUST)

1. A session MUST have at least one sub-session
2. A session's date MUST NOT be after ingestion timestamp
3. A session MUST preserve original source file reference
4. Sessions MUST NOT be merged or split after creation

### Sub-Session Invariants (MUST)

1. A sub-session MUST belong to exactly one session
2. A sub-session MUST reference exactly one KPI template
3. A sub-session MUST have shot_count > 0
4. Classification counts MUST sum to shot_count
5. A percentage MUST be NULL if status is `invalid_insufficient_data`
6. Sub-sessions with low samples MUST be stored, not rejected

### Validity Status Invariants (MUST)

1. Status MUST reflect configured thresholds (default: 5, 15)
2. Invalid sessions MUST be stored (no silent exclusion)
3. Status MUST be visible in all query results
4. Queries MUST document any validity filters applied

### Prohibited Behaviors (MUST NOT)

1. MUST NOT silently exclude invalid/low-sample sub-sessions from storage
2. MUST NOT analyze the same (session, club, template) combination twice
3. MUST NOT orphan sub-sessions (session deletion RESTRICTED)
4. MUST NOT modify sub-session results after creation

---

[Next: Derived Data & Projections →](07_derived_data_projections.md)
