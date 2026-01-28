# 7. Derived Data & Projections

[← Back to Index](00_index.md)

---

## 7.1 Overview

This section defines the boundary between **authoritative data** (source of truth) and **derived data** (regenerable artifacts). Maintaining this separation is critical to system integrity.

---

## 7.2 Definition of Derived Data

### 7.2.1 Characteristics

Data is **derived** if it:

1. Can be **regenerated** from authoritative sources without information loss
2. Does **not** introduce new facts or measurements
3. Is created for **convenience** (performance, export) rather than necessity
4. Can be **deleted** without losing information

### 7.2.2 Examples in Phase 0

**Derived (Regenerable):**
- Projection JSON (exported session summaries)
- Cached trend calculations
- Pre-computed rolling averages
- CSV export files

**Authoritative (Not Regenerable):**
- Session records (ingested from launch monitor)
- Club sub-session analysis results
- KPI templates (imported or generated once)

**Important Note on Shot-Level Data:**

Phase 0 does **not persist raw shot-level data** in the database. The source CSV files contain shot-by-shot measurements, but only the **aggregated analysis results** (shot counts, A/B/C classifications, averages) are stored in `club_subsessions`.

Raw shot data remains in the immutable source CSV files as the original input artifact. The Phase 0 schema intentionally omits a shots table to keep the MVP focused on session-level analytics.

---

## 7.3 Projection Entity

### 7.3.1 Purpose

A **projection** is a pre-computed JSON export of sub-session results intended for:

- Sharing via file or network (e.g., Nostr)
- Displaying in external systems
- Archiving session summaries

### 7.3.2 Projection Contents

A typical projection includes:

```json
{
  "session_date": "2026-01-27T17:30:00Z",
  "club": "7i",
  "shot_count": 20,
  "validity_status": "valid",
  "a_percentage": 72.5,
  "avg_carry": 164.3,
  "kpi_template_hash": "a3f8b5c2...",
  "analyzed_at": "2026-01-27T18:00:00Z"
}
```

**Notable Exclusions:**
- Raw shot-level data (privacy, size)
- Session ID (local system identifier, not portable)
- Template alias names (local metadata)

### 7.3.3 Generation Semantics

**On-Demand Generation:**

```python
def generate_projection(subsession_id):
    # Query authoritative data
    subsession = db.get_subsession(subsession_id)
    session = db.get_session(subsession.session_id)
    
    # Construct projection
    projection = {
        "session_date": session.session_date,
        "club": subsession.club,
        "shot_count": subsession.shot_count,
        # ... other fields
    }
    
    return projection
```

**Optional Caching:**

```python
# Cache for performance (optional)
cached = db.get_cached_projection(subsession_id)
if cached:
    return cached
else:
    projection = generate_projection(subsession_id)
    db.cache_projection(subsession_id, projection)
    return projection
```

### 7.3.4 Immutability of Projections

Once generated, a projection is **immutable**:

- Represents a point-in-time snapshot
- Should not be modified after generation
- If source data changes, generate a **new** projection

**Rationale:** Projections shared externally must remain consistent.

---

## 7.4 Regeneration Rules

### 7.4.1 Regeneration Triggers

Projections should be regenerated when:

1. **Cache invalidation:** Cached projection is deleted
2. **Export request:** User requests fresh export
3. **Format change:** Export schema is updated (Phase 1+)

### 7.4.2 Regeneration Guarantees

**Guarantee:** Regenerating a projection from the same authoritative data produces:

- **Identical analytical results** (deterministic computations)
- **Identical content structure** (if projection schema unchanged)
- **Different timestamp** (`generated_at` field updates)

**Note:** Projections are not content-addressed in Phase 0. The guarantee is about analytical correctness, not byte-for-byte identity.

**Prohibited:** Regeneration should **never** produce different analytical results for the same source data.

### 7.4.3 Cache Deletion Policy

Projections may be deleted to:

- Reclaim storage space
- Invalidate stale formats
- Comply with data retention policies

**Effect:** Deletion only removes the cache — source data is unaffected.

---

## 7.5 Import Prohibition

### 7.5.1 No Reverse Import

**Critical Rule:** Projections **MUST NOT** be imported back into the database as authoritative data.

**Prohibited Operations:**

```python
# WRONG — DO NOT DO THIS
def import_projection(projection_json):
    # Parse projection
    data = json.loads(projection_json)
    
    # WRONG: Create session from projection
    session_id = db.create_session(
        session_date=data['session_date'],
        # ...
    )
    
    # WRONG: Create sub-session from projection
    db.create_subsession(
        session_id=session_id,
        a_count=data['a_count'],  # Lost detail!
        # ...
    )
```

**Why This Is Wrong:**

1. **Information loss:** Projections are summaries; raw shot data is not included
2. **Provenance corruption:** Original CSV file reference is lost
3. **Duplicate creation:** Re-importing creates false records
4. **Integrity violation:** Projections lack validation of authoritative data

### 7.5.2 Sharing vs. Importing

**Correct workflow:**

```
User A:
  1. Ingest CSV → Session → Sub-session
  2. Generate projection → Export JSON
  3. Share projection file/event

User B:
  1. Receive projection
  2. View/display projection
  3. Do NOT import as authoritative data
  4. (Optional) Import source CSV if available
```

**Rationale:** Each user maintains their own authoritative local database. Projections are for display/sharing only.

---

## 7.6 Derived Data Storage

### 7.6.1 Optional Storage Table

The `projections` table is **optional**:

- May be implemented for performance caching
- May be omitted if projections are always generated on-the-fly
- Schema may evolve freely (not constrained by historical data)

### 7.6.2 Cascade Deletion

If `projections` table exists:

**Foreign key:** `subsession_id → club_subsessions.subsession_id` with `ON DELETE CASCADE`

**Effect:** Deleting a sub-session automatically cleans up cached projections.

**Rationale:** Projections are artifacts of sub-sessions; no orphaned projections should exist.

### 7.6.3 No Referential Dependencies

**Prohibited:** Other tables must **never** reference the `projections` table via foreign key.

**Rationale:** Derived data cannot be a dependency for authoritative data.

---

## 7.7 Export Formats

### 7.7.1 JSON Projections

**Primary format:** JSON (UTF-8)

**Schema:** Flexible, may evolve

**Content:**
- Summary statistics only
- No raw shot data
- Timestamp of generation
- Schema version indicator (for forward compatibility)

### 7.7.2 CSV Exports

**Purpose:** Integration with spreadsheet tools, external analysis

**Content:**
- One row per sub-session
- Columns: date, club, shot_count, a_count, a_percentage, etc.
- No nested structures (flat format)

**Not a projection:** CSV exports are generated on-demand, not cached.

### 7.7.3 Future Formats

Phase 1+ may introduce:

- Nostr event format (NIP-compliant)
- Binary formats (protobuf, msgpack)
- GraphQL responses

**Constraint:** All formats must derive from the same authoritative SQLite data.

---

## 7.8 Separation of Concerns

### 7.8.1 Authoritative Layer

**Responsibilities:**
- Persist raw session data
- Store analysis results
- Enforce referential integrity
- Maintain audit trail

**Data sources:**
- CSV ingestion
- KPI template import
- Session analysis

### 7.8.2 Derived Layer

**Responsibilities:**
- Generate export artifacts
- Cache for performance
- Support external integrations
- Provide read-only views

**Data sources:**
- Query authoritative layer
- Transform for specific use case
- Apply display logic

### 7.8.3 Boundary Enforcement

**Mechanism:**

1. **Read-only interface:** Derived layer queries but does not modify authoritative data
2. **No reverse flow:** Projections cannot modify source data
3. **Clear naming:** Tables like `projections`, `cache_*` signal derived nature

---

## 7.9 Version Evolution

### 7.9.1 Projection Schema Changes

When projection format changes (Phase 1+):

**Strategy:**

1. Add `schema_version` field to projections
2. Support generating multiple versions in parallel
3. Older projections remain valid (don't invalidate)
4. Consumers declare supported versions

**Example:**

```json
{
  "schema_version": "2.0",
  "session_date": "2026-01-27T17:30:00Z",
  "club": "7i",
  "new_field": "value",  // Added in v2.0
  // ...
}
```

### 7.9.2 Authoritative Schema Stability

**Constraint:** Changes to authoritative schema (sessions, sub-sessions, templates) require migration.

**Projection advantage:** Projections can evolve freely without migration because they're regenerable.

---

## 7.10 Invariants Summary

### Derived Data Rules (MUST)

1. Derived data MUST be regenerable from authoritative sources
2. Projections MUST NOT be imported as authoritative data
3. Derived tables MUST NOT be referenced by foreign keys from authoritative tables
4. Cached projections MAY be deleted without information loss
5. Regeneration MUST produce identical analytical results

### Projection Rules (MUST)

1. Projections MUST include `generated_at` timestamp
2. Projections SHOULD include schema version indicator
3. Projections MUST NOT contain raw shot-level data (Phase 0)
4. Projection format MAY evolve without affecting authoritative schema

### Prohibited Behaviors (MUST NOT)

1. MUST NOT import projections to create sessions or sub-sessions
2. MUST NOT treat cached projections as source of truth
3. MUST NOT modify projections after generation
4. MUST NOT create foreign key dependencies on derived tables
5. MUST NOT lose information when generating projections from authoritative data

---

[Next: Non-Goals at the Schema Layer →](08_non_goals.md)
