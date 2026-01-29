# RAID Phase 0 — Implementation Phases

**Document Version:** 1.0  
**Date:** 2026-01-29  
**Status:** Active  

---

## Purpose of This Document

This document organizes Phase 0 work into coherent execution phases. It does not replace or supersede the **PRD** (`docs/PRD_Phase_0_MVP.md`) or the **Reference Test Matrix** (`docs/reference_test_matrix.md`), which remain the authoritative sources of requirements and test specifications.

**Phases are an execution aid** designed to:

- Provide a clear roadmap for implementing Phase 0
- Map groups of RTMs into logical implementation units
- Define entry criteria, exit criteria, and STOP conditions per phase
- Create safe stopping points and reduce scope creep
- Serve as onboarding context for future contributors and AI agents

The Reference Test Matrix (RTM) remains the source of truth for what must be tested and validated. Phases simply organize that work into a sensible execution order.

---

## Phase A — Canonical Identity ✅ **COMPLETE**

### Purpose

Establish deterministic, cross-platform template identity through canonical JSON hashing. Without this foundation, no other phase can reliably reference or persist KPI templates.

### RTMs Covered

- **RTM-11:** Canonical key ordering ✅
- **RTM-12:** Compact JSON + UTF-8 ✅
- **RTM-13:** Numeric normalization ✅
- **RTM-14:** Hash determinism (Python ↔ Swift) ✅

### Key Guarantees

- Template JSON is canonicalized with deterministic key ordering at all nesting levels
- Numeric values are normalized consistently (no ambiguity between `1`, `1.0`, `1.00`)
- JSON is compact (no whitespace) and UTF-8 encoded without BOM
- SHA-256 hashes are identical across Python and Swift for the same template content
- Golden hash values are computed once and frozen as expected values in tests

### Completion Status

**Completed:** 2026-01-28  
**Commits:** Multiple (canonicalization, hashing, test fixtures)

- ✅ All three test fixtures (A, B, C) canonicalize correctly
- ✅ Golden hashes computed, frozen in `tests/vectors/expected/template_hashes.json`
- ✅ Python canonicalization tests pass (27 tests)
- ✅ Python hashing tests pass (13 tests)
- ✅ Decimal-based numeric normalization ensures cross-platform determinism

**Implementation Files:**
- `raid/canonical.py` - Canonical JSON transformation
- `raid/hashing.py` - SHA-256 content-addressed hashing
- `tests/unit/test_canonicalization.py` - Canonicalization test suite
- `tests/unit/test_hashing.py` - Hashing test suite

### STOP Conditions Encountered

None. Decimal-based normalization provided platform-independent numeric handling.

---

## Phase B — Immutability & Identity Enforcement ✅ **COMPLETE**

### Purpose

Enforce immutability of sessions, club sub-sessions, and KPI templates at the database level. Guarantee that stored template hashes are authoritative and never recomputed on read.

### RTMs Covered

- **RTM-01:** Session immutability ✅
- **RTM-02:** Sub-session immutability ✅
- **RTM-03:** KPI template immutability ✅
- **RTM-04:** Hash not recomputed on read ✅

### Key Guarantees

- Sessions cannot be mutated after creation (rejected with clear error)
- Club sub-sessions cannot be mutated after creation (rejected with clear error)
- KPI templates cannot be mutated after insertion (rejected with clear error)
- Template hashes are stored and trusted as authoritative; no re-hashing on read
- Integrity checks (if needed) are out-of-band operations, not part of normal read path

### Completion Status

**Completed:** 2026-01-28  
**Commits:** Schema and repository implementation

- ✅ Immutability enforced via BEFORE UPDATE triggers that ABORT
- ✅ Mutation attempts rejected with explicit error messages
- ✅ Tests validate stored rows remain unchanged after mutation attempts
- ✅ Read path does NOT call canonicalize() or hash functions (proven via monkeypatch/spy)
- ✅ All immutability tests passing (9 tests)

**Implementation Files:**
- `raid/schema.sql` - SQLite schema with immutability triggers
- `raid/repository.py` - Repository layer (insert and read operations)
- `tests/unit/test_immutability.py` - Immutability test suite

### STOP Conditions Encountered

None. SQLite triggers provided effective immutability enforcement without performance issues.

---

## Phase C — Analysis Semantics ✅ **COMPLETE**

### Purpose

Define and enforce the rules for how sessions are analyzed, re-analyzed, and prevented from duplication. Ensure that analysis results are tied to specific KPI template versions.

### RTMs Covered

- **RTM-05:** Duplicate analysis prevented ✅
- **RTM-06:** Re-analysis with different template ✅

### Key Guarantees

- Duplicate sub-sessions (same `session_id`, `club`, `kpi_template_hash`) are prevented via UNIQUE constraint
- Re-analyzing the same session/club with a different template creates a new sub-session
- Original sub-sessions remain unchanged when re-analysis occurs
- Users can compare results across different KPI template versions for the same session

### Completion Status

**Completed:** 2026-01-29  
**Commit:** `b884105` - Phase C: RTM-05/06 analysis semantics tests

- ✅ UNIQUE constraint on (`session_id`, `club`, `kpi_template_hash`) validated
- ✅ Duplicate insert attempts rejected with constraint violation error
- ✅ Re-analysis with different template creates new sub-session row
- ✅ Tests validate both scenarios with 8 comprehensive test cases
- ✅ No schema changes required (constraint already in place)
- ✅ All 48 unit tests passing

**Test File:** `tests/unit/test_analysis_semantics.py`

### STOP Conditions Encountered

None. Schema constraint was already in place and working correctly.

---

## Phase D — Validity & Transparency

### Purpose

Implement data quality indicators based on sample size thresholds and ensure that validity status is visible and never silently filtered. Prevent overconfident reporting on small sample sizes.

### RTMs Covered

- **RTM-07:** Validity thresholds
- **RTM-08:** A% null when invalid
- **RTM-09:** Low/invalid stored
- **RTM-10:** No silent filtering

### Key Guarantees

- Validity status is computed correctly based on shot count:
  - `invalid_insufficient_data`: shot_count < 5
  - `valid_low_sample_warning`: 5 ≤ shot_count < 15
  - `valid`: shot_count ≥ 15
- These threshold values are fixed per PRD Phase 0 defaults and are not configurable in Phase 0
- A% is NULL when status is `invalid_insufficient_data`
- Invalid and low-sample sub-sessions are stored (not excluded)
- Query results include explicit validity status fields
- Filters are explicit and reflected in output (no silent exclusion)

### Done When

- Validity computation logic is implemented and tested at boundary values (4, 5, 14, 15 shots)
- A% is correctly NULL for invalid sub-sessions
- Invalid sub-sessions are persisted without rejection
- Query interfaces include validity status in output
- Tests validate all boundary conditions and filtering behavior

### STOP Conditions

- Threshold values are unclear or conflict with PRD defaults
- Ambiguity about whether thresholds should be configurable vs. hardcoded
- Edge cases discovered where validity logic is incorrect
- Conflict between storing invalid data and query performance concerns

---

## Phase E — Derived Data Boundary

### Purpose

Establish clear boundaries between authoritative data (SQLite) and derived projections (JSON exports, caches). Ensure projections are regenerable and cannot corrupt authoritative data through import.

### RTMs Covered

- **RTM-15:** Projection regeneration + no import
- **RTM-16:** Derived data isolation

### Key Guarantees

- Projections can be deleted and regenerated with identical analytical results
- Projections are derived from authoritative SQLite data, not the other way around
- Attempting to import a projection fails with an explicit error
- No foreign key relationships point from authoritative tables to projection/cache tables
- Derived data is clearly segregated (e.g., separate schema, explicit naming conventions)

### Done When

- Projection generation logic is implemented and tested
- Regeneration after deletion yields identical results
- Import of projections is rejected with clear error message
- Schema validation confirms no FK dependencies from authoritative to derived tables
- Tests validate regeneration and import rejection

### STOP Conditions

- Performance requirements conflict with regeneration approach
- Ambiguity about what constitutes "derived" vs. "authoritative" data
- Schema changes required to enforce isolation
- Edge cases where cached projections cannot be safely regenerated

---

## Phase F — Multi-Club Ingest

### Purpose

Validate the complete end-to-end pipeline by ingesting real-world mixed-club CSV exports. Ensure one session can contain multiple clubs and that sub-sessions are correctly grouped.

### RTMs Covered

- **RTM-17:** Multi-club ingest

### Key Guarantees

- A single CSV containing shots from multiple clubs is parsed correctly
- One session entity is created
- One sub-session per club is created, all sharing the same `session_id`
- Club grouping is correct (shots are not mixed across sub-sessions)
- Real-world Rapsodo MLM2Pro exports (both standard and legacy formats) ingest successfully

### Done When

- CSV parsing correctly handles both file structure variants (standard and legacy)
- Header detection searches rows 1-3 for column headers
- Footer rows (Average, Std Dev) are excluded from shot analysis
- Mixed-club test fixture ingests successfully
- One session and multiple sub-sessions are created with correct relationships
- Real CSV exports from Rapsodo validate successfully

### STOP Conditions

- CSV format variations discovered that don't match PRD specifications
- Ambiguity about how to group shots by club (e.g., club name normalization issues)
- Edge cases where multi-club logic produces incorrect results
- Performance issues with large CSV files
- Schema changes required to support multi-club relationships

---

## Why Phases Are Sequential

Phases are intentionally ordered to minimize rework and maximize safety:

1. **Identity first (Phase A):** Cannot persist or reference templates without deterministic hashing
2. **Immutability second (Phase B):** Cannot trust historical data without immutability guarantees
3. **Analysis semantics (Phase C):** Build on immutable foundation to define analysis behavior
4. **Validity rules (Phase D):** Layer quality indicators on top of working analysis
5. **Derived boundaries (Phase E):** Clarify what is authoritative vs. regenerable
6. **End-to-end validation (Phase F):** Validate complete pipeline with real data

**Earlier phases should rarely change once completed.** Breaking changes to Phase A or B would invalidate all subsequent work. Later phases (C-F) are additive and can be refined without affecting earlier foundations.

---

## Additive Features Layer on Top

Once Phase 0 (Phases A–F) is complete, future features layer on top without modifying the core:

- **New device support:** Add parsers without changing schema or analysis logic
- **Trend calculations:** Query existing sub-sessions without schema changes
- **Nostr integration:** Export projections without modifying authoritative data
- **iOS port:** Port logic using the same schema and hash algorithms
- **UI development:** Build interfaces on top of existing query layer

The sequential phase structure creates a stable foundation that supports extension without disruption.

---

*This document is a non-authoritative execution aid. Refer to the PRD and Reference Test Matrix for canonical requirements.*
