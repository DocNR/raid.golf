# 2. Authoritative Entities

[← Back to Index](00_index.md)

---

## 2.1 Overview

Phase 0 defines **five core entities**, categorized by their role in the system:

| Entity | Category | Authoritative? | Lifecycle |
|--------|----------|----------------|-----------|
| **Session** | Domain Data | Yes | Immutable after ingestion |
| **Club Sub-Session** | Domain Data | Yes | Immutable after analysis |
| **KPI Template** | Standard/Artifact | Yes | Immutable forever |
| **Template Alias** | Metadata | Yes | Mutable (local preference) |
| **Projection** | Derived Data | No | Regenerable cache |

---

## 2.2 Session

### Purpose

A **Session** represents a single practice session, typically corresponding to one CSV import from a launch monitor. It serves as the logical container for all shots recorded during that practice period.

### Lifecycle

1. **Creation:** Occurs during CSV ingestion
2. **Persistence:** Stored immediately with immutable core fields
3. **Analysis:** Sub-sessions are created and linked
4. **Retention:** Never deleted (historical record)

### Ownership

- **Authoritative:** Yes — SQLite is the source of truth
- **Immutable Fields:** `session_date`, `source_file`, `device_type`, `location`, `ingested_at`
- **Mutable Fields:** None (all fields immutable after creation)

### Key Characteristics

- A session may contain shots from **multiple clubs** (1:N relationship to sub-sessions)
- Session identity is system-assigned (auto-increment primary key)
- The original CSV file path is preserved for reference but not required for analysis
- Sessions are never merged or split post-creation

### Design Rationale

Sessions map directly to real-world practice sessions. Golfers commonly use multiple clubs in a single session, so forcing single-club sessions would fragment the natural grouping and complicate date-based queries.

---

## 2.3 Club Sub-Session

### Purpose

A **Club Sub-Session** represents all shots for a specific club within a session. This is the **primary unit of analysis** and trending in the system.

### Lifecycle

1. **Creation:** Generated during session analysis (one per unique club in session)
2. **Analysis:** KPI template is applied to classify shots
3. **Persistence:** Results stored with reference to parent session and KPI template
4. **Querying:** Used for trend analysis and reporting

### Ownership

- **Authoritative:** Yes — analysis results are persisted, not recomputed on read
- **Immutable Fields:** All fields (once created, sub-session results never change)
- **Mutable Fields:** None

### Key Characteristics

- Each sub-session references exactly **one session** (parent)
- Each sub-session references exactly **one KPI template** (used for classification)
- Each sub-session represents exactly **one club**
- Sub-sessions include validity status based on sample size
- A/B/C counts and percentages are precomputed and stored

### Design Rationale

Pre-computing and persisting analysis results ensures:

1. **Reproducibility:** Historical analyses remain valid even if KPI templates change
2. **Performance:** Trend queries don't re-analyze raw shot data
3. **Audit trail:** Can see exactly which template version was used for each analysis

---

## 2.4 KPI Template

### Purpose

A **KPI Template** is an immutable artifact that defines classification thresholds for a specific club. Templates are identified by the SHA-256 hash of their canonical JSON representation (content-addressing).

### Lifecycle

1. **Creation:** Generated from baseline data or imported from external source
2. **Canonicalization:** JSON is normalized (sorted keys, deterministic numbers)
3. **Hashing:** `template_hash = sha256(canonical_json)`
4. **Storage:** Persisted keyed by hash (deduplication automatic)
5. **Application:** Referenced by sub-sessions for classification
6. **Retention:** Never deleted (historical artifact)

### Ownership

- **Authoritative:** Yes — locally stored templates are source of truth
- **Immutable Fields:** ALL — templates are completely immutable artifacts
- **Mutable Fields:** None

### Key Characteristics

- Identity is content-based (hash), not name-based
- Multiple imports of identical content produce same hash (idempotent)
- "Editing" creates a new template with new hash; original preserved
- Templates can be shared across users/devices (hash is universal)
- No versioning metadata within template (hash IS the version)

### Design Rationale

Content-addressing provides:

1. **Deduplication:** Same standard imported from different sources → single storage
2. **Integrity:** Any modification produces different hash (tampering evident)
3. **Provenance:** Historical analyses reference exact template used
4. **Interoperability:** External systems can independently verify template identity

---

## 2.5 Template Alias

### Purpose

A **Template Alias** provides human-readable names and local metadata for KPI templates. Aliases are **local preferences only** and do not affect template identity or sharing.

### Lifecycle

1. **Creation:** User assigns alias to imported or generated template
2. **Update:** User may rename or annotate alias
3. **Deletion:** Removing alias does not delete underlying template
4. **Querying:** Used for display in UI/CLI

### Ownership

- **Authoritative:** Yes (for local metadata)
- **Immutable Fields:** `template_hash` (reference must not change)
- **Mutable Fields:** `display_name`, `notes`

### Key Characteristics

- One template may have zero, one, or many aliases
- One alias references exactly one template
- Aliases are local only (not exported in projections)
- Deleting an alias does not affect template or historical analyses

### Design Rationale

Separating human-readable names from template identity allows:

1. **Flexibility:** Users can label templates meaningfully for local use
2. **Stability:** Renaming an alias doesn't affect identity or historical data
3. **Simplicity:** Template export/import doesn't carry user-specific metadata

---

## 2.6 Projection (Derived)

### Purpose

A **Projection** is a pre-computed JSON export of sub-session results. Projections are **derived artifacts** — they are generated from authoritative data and can be regenerated at any time.

### Lifecycle

1. **Generation:** Computed on-demand from sub-session data
2. **Caching:** Optionally stored to avoid recomputation
3. **Export:** Written to file or published (e.g., to Nostr)
4. **Invalidation:** Cache entries may be deleted without data loss

### Ownership

- **Authoritative:** No — projections are regenerable from source data
- **Immutable Fields:** N/A (entire projection is ephemeral)
- **Mutable Fields:** N/A (regenerated, not mutated)

### Key Characteristics

- Projections are **read-only snapshots**
- Importing a projection does **not** recreate the session/sub-session
- Projections may be deleted to reclaim space (data is not lost)
- Multiple export formats may exist (JSON, CSV, etc.)

### Design Rationale

Separating derived data from authoritative data ensures:

1. **Single source of truth:** SQLite database is always authoritative
2. **Flexibility:** Export formats can evolve without migration
3. **Safety:** Shared projections cannot corrupt local database
4. **Clarity:** No confusion about which data is "real"

---

## 2.7 Entity Relationships (Summary)

```
┌─────────────────────────────────────────────────────┐
│                     Session                         │
│  (Authoritative, Immutable)                         │
│                                                     │
│  - session_id (PK)                                  │
│  - session_date                                     │
│  - source_file                                      │
│  - ingested_at                                      │
└──────────────────┬──────────────────────────────────┘
                   │
                   │ 1:N
                   ▼
┌─────────────────────────────────────────────────────┐
│               Club Sub-Session                      │
│  (Authoritative, Immutable)                         │
│                                                     │
│  - subsession_id (PK)                               │
│  - session_id (FK → Session)                        │
│  - club                                             │
│  - kpi_template_hash (FK → KPI Template)            │
│  - validity_status                                  │
│  - shot_count, a_count, b_count, c_count           │
│  - analyzed_at                                      │
└──────────────────┬──────────────────────────────────┘
                   │
                   │ N:1
                   ▼
┌─────────────────────────────────────────────────────┐
│                  KPI Template                       │
│  (Authoritative, Immutable, Content-Addressed)      │
│                                                     │
│  - template_hash (PK, SHA-256)                      │
│  - schema_version                                   │
│  - club                                             │
│  - canonical_json (TEXT)                            │
│  - created_at                                       │
└──────────────────┬──────────────────────────────────┘
                   │
                   │ 1:N
                   ▼
┌─────────────────────────────────────────────────────┐
│                Template Alias                       │
│  (Authoritative, Partially Mutable)                 │
│                                                     │
│  - alias_id (PK)                                    │
│  - template_hash (FK → KPI Template)                │
│  - display_name                                     │
│  - notes                                            │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│                   Projection                        │
│  (Derived, Regenerable, Optional Cache)             │
│                                                     │
│  - subsession_id (FK → Club Sub-Session)            │
│  - projection_json (TEXT)                           │
│  - generated_at                                     │
└─────────────────────────────────────────────────────┘
```

---

## 2.8 Ownership Summary

| Entity | Authoritative? | Source of Truth |
|--------|----------------|-----------------|
| Session | ✅ Yes | SQLite |
| Club Sub-Session | ✅ Yes | SQLite |
| KPI Template | ✅ Yes | SQLite (canonical_json field) |
| Template Alias | ✅ Yes | SQLite (local metadata) |
| Projection | ❌ No | Derived from SQLite data |

**Critical Rule:** Only authoritative entities may be referenced by foreign keys. Derived data must never become a dependency.

---

[Next: Logical Schema Definition →](03_logical_schema.md)
