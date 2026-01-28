# 9. Forward-Compatibility Guarantees

[← Back to Index](00_index.md)

---

## 9.1 Overview

While Phase 0 focuses solely on local-only Python/CLI implementation, the schema is designed to support future expansion without structural changes. This section describes how the Phase 0 schema enables iOS deployment, Nostr integration, and long-term evolution.

---

## 9.2 iOS Deployment

### 9.2.1 SQLite Portability

**Guarantee:** Phase 0 schema is directly portable to iOS.

**Rationale:**
- SQLite is natively supported on iOS (SQLite3 framework)
- Schema uses standard SQL types (no vendor-specific extensions)
- Foreign keys, constraints, and indexes are iOS-compatible

**Migration path:**

```
Phase 0 (Python + SQLite)
    ↓ Database file copy
iOS App (Swift + SQLite3)
```

### 9.2.2 Swift Codable Mapping

**KPI Template JSON → Swift:**

```swift
struct KPITemplate: Codable {
    let schemaVersion: String
    let club: String
    let metrics: [String: MetricThresholds]
    let aggregationMethod: String
    let createdAt: Date
    let provenance: Provenance
    
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case club
        case metrics
        case aggregationMethod = "aggregation_method"
        case createdAt = "created_at"
        case provenance
    }
}

struct MetricThresholds: Codable {
    let aMin: Double
    let bMin: Double
    let direction: String
    
    enum CodingKeys: String, CodingKey {
        case aMin = "a_min"
        case bMin = "b_min"
        case direction
    }
}
```

**Guarantee:** Template JSON structure maps cleanly to Swift Codable structs with no data loss.

### 9.2.3 No Structural Changes Required

**Phase 0 → iOS migration requires:**
- ✅ SQLite database file copy
- ✅ Swift data access layer
- ✅ iOS UI implementation

**Phase 0 → iOS migration does NOT require:**
- ❌ Schema changes
- ❌ Data migration scripts
- ❌ Template rehashing
- ❌ Session re-ingestion

---

## 9.3 Nostr Integration (Phase 1+)

### 9.3.1 KPI Templates as Nostr Events

**Conceptual Mapping:** KPI templates can be published as Nostr events (likely as replaceable or parameterized replaceable events; specific kind numbers TBD in Phase 1).

**Example Event Structure (Illustrative):**

```json
{
  "kind": "<TBD>",
  "content": "<canonical_template_json>",
  "tags": [
    ["d", "<template_hash>"],
    ["t", "golf-kpi-template"],
    ["club", "7i"],
    ["schema_version", "1.0"]
  ],
  "created_at": 1706454224,
  "pubkey": "<author_pubkey>",
  "id": "<event_id>",
  "sig": "<signature>"
}
```

**Key Properties:**

1. **Content = canonical JSON:** Same payload stored locally
2. **Template identity in tag:** `template_hash` preserved in tag structure (e.g., `d` tag)
3. **Event ID ≠ template hash:** Event ID includes author signature; template identity is content-based
4. **Multiple authors, one template:** Different users publishing identical template → same `template_hash`

**Note:** Phase 0 does not commit to specific Nostr event kinds or tag structures. The above is conceptual only. Phase 1 will define concrete Nostr integration specs.

### 9.3.2 Template Import from Nostr

**Process:**

```
1. Receive Nostr event (kind 30078)
2. Extract content (canonical JSON)
3. Verify d tag matches sha256(content)
4. Import template using existing import logic
5. Template deduplicates if already exists (idempotent)
```

**No schema changes required** — existing import process handles Nostr-sourced templates.

### 9.3.3 Session Projections as Nostr Events

**Mapping:** Session projections map to ephemeral or replaceable events.

**Event Structure:**

```json
{
  "kind": 30079,
  "content": "<projection_json>",
  "tags": [
    ["d", "<session_date>_<club>"],
    ["t", "golf-session"],
    ["club", "7i"],
    ["session_date", "2026-01-27"]
  ],
  "created_at": 1706454224,
  "pubkey": "<user_pubkey>",
  "id": "<event_id>",
  "sig": "<signature>"
}
```

**Critical constraint:** Projections published to Nostr are **not imported back** as authoritative data (same rule as file-based projections).

### 9.3.4 No Nostr-Specific Schema

**Guarantee:** Phase 0 schema does not include Nostr-specific fields.

**When Nostr is added (Phase 1+):**
- Optional: Add `nostr_event_id` column to templates (for reference)
- Optional: Add `published_to_nostr` flag to projections
- Core schema remains unchanged

---

## 9.4 Historical Analysis Validity

### 9.4.1 Perpetual Validity

**Guarantee:** Analyses performed in Phase 0 remain valid indefinitely.

**Mechanism:**
- Sub-sessions reference `kpi_template_hash` (content-addressed)
- Templates are immutable and never deleted if referenced
- Analyses can be **validated** at any time by re-running with same template

**Example:**

```
2026-01-27: Analyze session with template abc123...
2027-01-27: Query historical analysis
  → Returns original results
  → Can verify by re-analyzing with template abc123...
  → Results match exactly (reproducible)
```

### 9.4.2 Template Provenance

**Each sub-session includes:**
- `kpi_template_hash` — which template was used
- `analyzed_at` — when analysis was performed

**This enables:**
- Trend analysis filtered by template version
- Comparison of analyses using different templates
- Audit trail of template evolution

### 9.4.3 No Retroactive Changes

**Guarantee:** Changing active template does **not** affect historical analyses.

**Example:**

```
2026-01: Use template v1 (hash: abc123...)
  → 10 sessions analyzed with v1
2026-02: Create template v2 (hash: def456...)
  → New sessions analyzed with v2
  → Old 10 sessions still show v1 results
```

---

## 9.5 Schema Evolution Strategy

### 9.5.1 Additive Changes Only

**Phase 1+ schema changes are limited to:**

1. **New tables** (not referenced by existing tables)
2. **New columns** (nullable, with defaults)
3. **New indexes** (performance optimization)

**Prohibited:**
- Removing columns
- Changing column types
- Modifying primary keys
- Relaxing NOT NULL constraints on existing columns

### 9.5.2 Opt-In Features

**New capabilities are opt-in:**

```sql
-- Phase 1: Add sync metadata (optional)
ALTER TABLE sessions ADD COLUMN sync_status TEXT NULL;
ALTER TABLE sessions ADD COLUMN remote_id TEXT NULL;

-- Existing sessions: sync_status = NULL (not synced)
-- New sessions: sync_status set on creation
```

**Guarantee:** Phase 0 databases can be opened in Phase 1+ implementations without migration (new columns default to NULL).

### 9.5.3 Version Metadata

**Future consideration:**

```sql
CREATE TABLE schema_version (
    version TEXT PRIMARY KEY,
    applied_at TEXT NOT NULL
);

INSERT INTO schema_version VALUES ('1.0', '2026-01-28T00:00:00Z');
```

**Benefit:** Implementations can detect schema version and handle appropriately.

---

## 9.6 JSON Export Evolution

### 9.6.1 Projection Schema Versioning

**When projection format changes:**

```json
{
  "schema_version": "2.0",
  "session_date": "2026-01-27T17:30:00Z",
  "club": "7i",
  "new_field_in_v2": "value",
  // ...
}
```

**Backward compatibility:**
- Consumers ignore unknown fields
- Required fields remain stable
- Optional fields added incrementally

### 9.6.2 Template Schema Versioning

**Template schema version is part of content:**

```json
{
  "schema_version": "1.0",
  "club": "7i",
  // ...
}
```

**If template schema changes:**
- Create new schema version ("2.0")
- Both versions coexist
- Hash includes schema_version (different schemas → different hashes)

---

## 9.7 Multi-Platform Consistency

### 9.7.1 Cross-Platform Guarantees

**Guarantee:** Python and Swift implementations produce identical results.

**Validation areas:**

1. **Template hashing:**
   - Python: `hashlib.sha256()`
   - Swift: `CryptoKit.SHA256.hash()`
   - Must produce identical hashes for identical canonical JSON

2. **Shot classification:**
   - Same template + same shot data → same A/B/C classification
   - Deterministic sorting, comparison logic

3. **Percentage calculations:**
   - Float precision handled consistently
   - Rounding applied uniformly

### 9.7.2 Test Coverage

**Cross-platform test suite includes:**

```
Reference test cases (JSON files):
  - template_7i_v1.json → Expected hash
  - session_20260127.csv → Expected classifications
  - trend_7i_jan2026.json → Expected rolling averages

Python tests: Assert results match expected
Swift tests: Assert results match expected
```

**CI/CD validation:** Both implementations pass identical test suite.

---

## 9.8 Data Portability

### 9.8.1 Export Formats

**Phase 0 supports:**
- SQLite database file (full export)
- JSON projections (per sub-session export)
- CSV summaries (trend reports)

**Phase 1+ may add:**
- Nostr events (decentralized sharing)
- Binary formats (efficiency)
- GraphQL APIs (programmatic access)

**Guarantee:** All export formats derive from same SQLite source.

### 9.8.2 Import Formats

**Phase 0 supports:**
- CSV session logs (from launch monitors)
- JSON KPI templates (from files or future Nostr)

**Phase 1+ may add:**
- Nostr event ingestion (templates only, not projections)
- Other launch monitor formats (TrackMan, etc.)

**Guarantee:** Import formats populate same authoritative schema.

---

## 9.9 Long-Term Data Retention

### 9.9.1 Archival Strategy

**10-year horizon:**

- Sessions from 2026 remain queryable in 2036
- KPI templates from 2026 remain usable in 2036
- Analyses from 2026 remain reproducible in 2036

**Mechanism:**
- Immutable data (no silent updates)
- Content-addressed templates (hash-based identity)
- Self-contained database (no external dependencies)

### 9.9.2 No Planned Obsolescence

**Guarantee:** No forced upgrades that invalidate historical data.

**Migration policy:**
- Additive schema changes only
- Backward-compatible formats
- Conversion tools for format changes (if needed)

---

## 9.10 Summary of Forward-Compatibility Guarantees

### MUST Support (Without Schema Changes)

1. iOS deployment with SQLite3 framework
2. Swift Codable mapping of KPI templates
3. Nostr event import for KPI templates
4. Nostr event export of projections
5. Historical analysis validity indefinitely
6. Multi-platform consistency (Python ↔ Swift)

### MUST Enable (With Additive Changes Only)

1. Sync metadata (optional columns)
2. Nostr event references (optional columns)
3. Extended metrics (new tables)
4. Performance indexes (no data changes)

### MUST Preserve

1. Existing sessions and sub-sessions remain valid
2. Existing templates remain usable
3. Historical analyses remain reproducible
4. Template hashes remain stable
5. Data export formats remain readable

---

[Next: Summary of Enforced Invariants →](10_enforced_invariants.md)
