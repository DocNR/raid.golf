# 4. Identity & Immutability Rules

[← Back to Index](00_index.md)

---

## 4.1 Overview

This section defines **hard invariants** governing what can and cannot be mutated after creation. These rules are enforced by schema constraints and application logic — they are not conventions or best practices, but **mandatory system behaviors**.

---

## 4.2 Session Immutability

### Immutable After Creation

Once a session is created and persisted, the following fields **MUST NOT** be modified:

- `session_id` (primary key — system-assigned, never changes)
- `session_date` (represents when the practice occurred)
- `source_file` (historical record of data provenance)
- `device_type` (factual metadata about source)
- `location` (factual metadata about source)
- `ingested_at` (audit trail timestamp)

### Rationale

Sessions represent historical facts. Modifying session metadata would:

1. Break referential integrity with sub-sessions
2. Corrupt historical trend analysis
3. Create ambiguity about data provenance
4. Violate audit trail requirements

### Permitted Operations

- **Create:** New sessions may be added at any time
- **Read:** Sessions may be queried freely
- **Delete:** Prohibited if sub-sessions exist (enforced by RESTRICT FK)

### Prohibited Operations

- **Update:** No fields may be modified after creation
- **Merge:** Sessions cannot be combined
- **Split:** Sessions cannot be divided into multiple sessions

---

## 4.3 Club Sub-Session Immutability

### Immutable After Creation

All fields in a club sub-session are immutable after analysis:

- `subsession_id` (primary key)
- `session_id` (parent reference)
- `club` (club identifier)
- `kpi_template_hash` (template used for classification)
- `shot_count`, `a_count`, `b_count`, `c_count` (analysis results)
- `a_percentage` (computed percentage)
- `avg_carry`, `avg_ball_speed`, `avg_spin`, `avg_descent` (statistics)
- `validity_status` (data quality indicator)
- `analyzed_at` (audit trail timestamp)

### Rationale

Sub-session immutability guarantees:

1. **Reproducibility:** Historical analyses can be validated
2. **Provenance:** Clear record of which template version was used
3. **Audit trail:** No silent modification of results
4. **Trend validity:** Trend analysis compares consistent metrics

### Re-Analysis Semantics

If a user wants to "re-analyze" a session with a different KPI template:

1. Create a **new sub-session** with the new template
2. Original sub-session remains unchanged
3. Queries can filter by `kpi_template_hash` to select desired version
4. The unique constraint (`session_id`, `club`, `kpi_template_hash`) prevents duplicate analysis

**Prohibited:** Modifying existing sub-session to reference a different template.

### Permitted Operations

- **Create:** New sub-sessions may be added (e.g., re-analysis)
- **Read:** Sub-sessions may be queried freely
- **Delete:** Prohibited if projections exist (enforced by CASCADE)

### Prohibited Operations

- **Update:** No fields may be modified after creation
- **Template swap:** Cannot change `kpi_template_hash` of existing sub-session

---

## 4.4 KPI Template Immutability

### Immutable Forever

KPI templates are **completely immutable artifacts**. All fields are immutable:

- `template_hash` (primary key, content-addressed identity)
- `schema_version` (template schema version)
- `club` (target club)
- `canonical_json` (the template content)
- `created_at` (original authorship timestamp)
- `imported_at` (local import timestamp)

### Rationale

Template immutability is foundational to the system's integrity:

1. **Content-addressing:** Hash uniquely identifies content; changing content invalidates hash
2. **Historical validity:** Past analyses reference exact template used
3. **Reproducibility:** Same input + same template → identical output
4. **Interoperability:** Templates can be shared across users/systems with guaranteed identity

### Hash Computation Rule

**Critical Invariant:** The `template_hash` field is computed **exactly once** during insertion and **never recomputed**.

```
Insertion Flow:
1. Parse incoming JSON
2. Canonicalize JSON (sort keys, normalize numbers)
3. Compute hash = sha256(canonical_json)
4. Store (template_hash, canonical_json, ...)
5. Hash is now immutable truth
```

**Prohibited:** Reading `canonical_json` and recomputing hash on query. The stored hash is authoritative.

### "Editing" Semantics

If a user wants to modify a template:

1. Load the existing template's `canonical_json`
2. Make desired changes (in memory)
3. Canonicalize the modified JSON
4. Compute **new hash** for modified content
5. Insert as **new template** (original unchanged)
6. Optionally create alias pointing to new template

The original template remains in the database, unchanged, and any historical sub-sessions still reference it correctly.

### Permitted Operations

- **Create:** New templates may be added (generated or imported)
- **Read:** Templates may be queried freely
- **Delete:** Prohibited if sub-sessions reference it (enforced by RESTRICT FK)

### Prohibited Operations

- **Update:** No fields may be modified
- **Hash recomputation:** The stored hash must never be recalculated
- **Content mutation:** Canonical JSON cannot be changed

---

## 4.5 Template Alias Mutability

### Immutable Fields

- `alias_id` (primary key)
- `template_hash` (reference to template — must not change)
- `created_at` (audit trail)

### Mutable Fields

- `display_name` (user may rename for clarity)
- `notes` (user may add/edit annotations)
- `updated_at` (updated on modification)

### Rationale

Aliases are **local metadata only**. Changing an alias does not affect:

- Template identity (hash remains unchanged)
- Historical analyses (sub-sessions reference hash, not alias)
- Exported projections (aliases are not exported)

This separation allows flexibility without compromising integrity.

### Permitted Operations

- **Create:** New aliases may be added
- **Read:** Aliases may be queried
- **Update:** `display_name` and `notes` may be modified
- **Delete:** Aliases may be deleted (does not affect template)

### Prohibited Operations

- **Template swap:** Cannot change which template an alias references

---

## 4.6 Projection Ephemerality

### Immutable? No — Ephemeral

Projections are **regenerable artifacts**, not immutable records. The entire projection entity is ephemeral:

- May be generated on-demand
- May be cached for performance
- May be deleted without data loss
- May be regenerated with different formats

### Rationale

Projections are **views**, not source data. They derive from authoritative entities and can be reconstructed at any time from:

- `club_subsessions` (analysis results)
- `sessions` (metadata)
- `kpi_templates` (template details, if included in projection)

### Permitted Operations

- **Create:** Generate and cache projections
- **Read:** Export projections to file/network
- **Update:** Regenerate with updated format (delete + recreate)
- **Delete:** Remove cached projections freely

### Prohibited Operations

- **Import as authoritative:** Projections cannot be re-imported to create sessions/sub-sessions
- **Manual editing:** Projections should not be hand-edited (regenerate instead)

---

## 4.7 Identity Mechanisms Summary

| Entity | Identity Type | Key Field(s) |
|--------|---------------|--------------|
| Session | System-assigned | `session_id` (auto-increment) |
| Club Sub-Session | System-assigned | `subsession_id` (auto-increment) |
| KPI Template | Content-addressed | `template_hash` (SHA-256) |
| Template Alias | System-assigned | `alias_id` (auto-increment) |
| Projection | System-assigned (optional) | `projection_id` (auto-increment) |

### System-Assigned Identity

- Generated by database (typically auto-increment integer)
- Unique within local database
- Not portable across installations
- Used for sessions, sub-sessions, aliases

### Content-Addressed Identity

- Derived from content via cryptographic hash
- Globally unique (same content → same hash everywhere)
- Portable across installations
- Used exclusively for KPI templates

### Design Rationale

- **System-assigned** for domain entities tied to specific instances (practice sessions are local events)
- **Content-addressed** for shareable standards (KPI templates are universal definitions)

---

## 4.8 Immutability Enforcement

### Schema-Level Enforcement

1. **No UPDATE permissions** on immutable tables (if using row-level security)
2. **Triggers** to block updates on immutable fields (implementation-specific)
3. **Check constraints** to prevent logical violations

### Application-Level Enforcement

1. **No UPDATE methods** in data access layer for immutable entities
2. **Versioned creation** — edits create new records, not mutations
3. **Audit logging** — all data modifications logged for review

### Validation Requirements

Implementations must:

1. Reject attempts to update immutable fields (return error)
2. Log prohibited operations for security review
3. Provide clear error messages explaining immutability rules

**Prohibited:** "Silent failure" where updates are ignored without error.

---

## 4.9 Hash Recomputation Prohibition (Critical)

### The Problem

If `template_hash` is recomputed on read:

```
# WRONG — DO NOT DO THIS
def get_template(template_hash):
    row = db.query("SELECT * FROM kpi_templates WHERE template_hash = ?", template_hash)
    # BUG: Recomputing hash
    recomputed_hash = sha256(canonicalize(row['canonical_json']))
    if recomputed_hash != template_hash:
        raise IntegrityError("Hash mismatch!")
    return row
```

**Why This Is Wrong:**

1. If canonicalization logic has a bug, all historical references break
2. Cross-platform differences (Python vs Swift) could produce different hashes
3. Performance: hashing on every read is expensive
4. Trust: The stored hash is the identity; recomputation questions that

### The Solution

**Treat stored hash as immutable truth:**

```
# CORRECT
def get_template(template_hash):
    row = db.query("SELECT * FROM kpi_templates WHERE template_hash = ?", template_hash)
    return row  # Trust the stored hash
```

### Validation Strategy

Hash integrity should be validated:

1. **Once at insertion** — compute hash and store it
2. **Optionally during database integrity checks** — background verification job
3. **Never on normal read path** — trust stored values

---

## 4.10 Invariants Summary

### MUST Rules (Non-Negotiable)

1. Sessions MUST NOT be modified after creation
2. Sub-sessions MUST NOT be modified after creation
3. KPI templates MUST NOT be modified ever
4. Template hashes MUST NOT be recomputed after storage
5. "Editing" MUST create new records, not mutate existing ones
6. Projections MUST NOT be treated as authoritative data

### MUST NOT Rules (Prohibited)

1. MUST NOT update immutable fields
2. MUST NOT merge or split sessions
3. MUST NOT swap template references in sub-sessions
4. MUST NOT modify canonical_json after storage
5. MUST NOT import projections as authoritative data
6. MUST NOT silently ignore immutability violations

---

[Next: Canonical JSON & Hashing Contract →](05_canonical_json_hashing.md)
