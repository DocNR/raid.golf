# Kernel Steward Memory

## Approved Kernel Extensions

### Scorecard v0 Schema (2026-02-08)
**Status**: APPROVED as KERNEL EXTENSION
**Classification**: Kernel-adjacent (incubation stage)
**Migration**: v3_create_scorecard_schema

**What was added:**
- 5 new tables: course_snapshots, course_holes, rounds, round_events, hole_scores
- All tables have immutability triggers (UPDATE/DELETE blocked)
- Course snapshots use content-addressed hash PK (SHA-256 of JCS canonical JSON)
- Rounds use append-only event model (no mutable status field)
- Hole scores use latest-wins correction semantics with deterministic tie-break

**Why approved:**
- Additive migration (no modification to existing kernel tables)
- Full immutability enforcement from day 1
- Follows kernel patterns (content-addressing, hash-once, append-only)
- Comprehensive test coverage (27 tests)
- Properly classified as kernel-adjacent (not yet frozen)

**Key invariants verified:**
1. Hash-once: Canonicalization + hashing only on insert, never on read
2. Immutability: All 5 tables protected by ABORT triggers
3. Deterministic ordering: Latest-wins uses MAX(recorded_at) + MAX(score_id) tie-break
4. FK integrity: All foreign keys with ON DELETE RESTRICT
5. Content-addressing: course_hash uses same JCS canonicalization as kpi_templates

## Common Safe Patterns

### Additive Schema Migrations
- Adding new tables with immutability triggers = KERNEL EXTENSION (safe)
- New tables must not reference existing kernel tables in ways that create implicit coupling
- Use ON DELETE RESTRICT for FK constraints to prevent cascade deletions

### Content-Addressed Insert Pattern
Scorecard's CourseSnapshotRepository demonstrates the approved pattern:
1. Accept high-level input types (not raw JSON)
2. Build canonical JSON dict with frozen keys (alphabetically ordered by JCS)
3. Call canonicalizer.canonicalize() once
4. Call hasher.sha256Hex() once
5. Store hash + canonical JSON
6. INSERT OR IGNORE for idempotency
7. Read path fetches stored hash + canonical JSON, never recomputes

This mirrors KPITemplateRepository.insertTemplate() from the frozen kernel.

### Append-Only Lifecycle Events
Scorecard's round completion shows approved pattern for mutable state without UPDATE:
- rounds table: immutable creation row (no status field)
- round_events table: append-only events (completed, etc.)
- Derived state via COUNT query on events table
- UNIQUE(round_id, event_type) prevents duplicate events

This is SUPERIOR to a mutable status column because:
- Preserves full history
- No UPDATE trigger violations
- Auditable timeline
- Can extend with new event types without schema change

### Latest-Wins Corrections
Scorecard's hole scores show approved pattern for append-only corrections:
- No UPDATE/DELETE allowed
- Multiple rows per (round_id, hole_number) allowed
- Query resolves latest via: MAX(recorded_at), tie-break MAX(score_id)
- Full history preserved
- Deterministic selection rules

Tie-break requirement: Always use PK (score_id) as final tie-break to guarantee determinism.

### Pinned-Template Analysis Pattern (Phase 4B v2)
Approved pattern for historical analytical stability:
1. Analysis happens at import time (or on-demand re-analysis)
2. analyzeSessionClub() persists classification results + template_hash to club_subsessions
3. INSERT OR IGNORE with UNIQUE(session_id, club, kpi_template_hash) for idempotency
4. Read path (fetchAOnlyTrendPoints) joins sessions → club_subsessions to get pinned template_hash
5. Never calls fetchLatestTemplate from read path (no query-time drift)
6. Re-analysis with different template creates NEW row (append-only, preserves history)

This eliminates silent semantic drift where trend points change meaning when a new template is inserted.

## Boundary Markers

### Kernel vs Kernel-Adjacent
**Kernel (frozen)**: Changes require version bump, golden vectors, migration plan
- sessions, kpi_templates, club_subsessions, shots tables
- Canonical.swift, Hashing.swift, Schema.swift migrations v1/v2, Repository.swift methods
- Template canonicalization rules, hash computation

**Kernel-Adjacent (incubation)**: Changes allowed but must respect invariants
- scorecard tables (course_snapshots, course_holes, rounds, round_events, hole_scores)
- ScorecardRepository.swift, ScorecardModels.swift, ScorecardTests.swift
- May undergo schema changes during incubation with documentation
- Must maintain immutability, determinism, hash-once where applicable

**Outside Kernel (free evolution)**: UI, views, presentation logic
- ContentView.swift, TrendsView.swift, SessionsView.swift, RoundsView.swift
- ScoreEntryView.swift, CreateRoundView.swift, RoundDetailView.swift

### Key Distinction
Kernel-adjacent is NOT a weaker form of kernel protection. It means:
- Same invariants (immutability, hash-once, FK integrity)
- Same rigor (comprehensive tests)
- Different promise: schema MAY evolve during incubation
- Promotion path: kernel-adjacent → hardened → frozen kernel (requires promotion checklist)

## Red Flags to Watch For

### Implicit Coupling
Adding FK from new table to frozen kernel table = OK if ON DELETE RESTRICT
Adding computed columns that depend on JOIN with kernel table = requires careful review
Adding triggers on kernel tables that reference new tables = BLOCKED (modifies frozen schema)

### Semantic Drift
Adding a field with ambiguous meaning during incubation = flag for review
Example: "putts" — does it include fringe chips? Must be precisely defined before hardening.

### Hash-on-Read Anti-Pattern
Any proposal to "verify hash on read" = BLOCKED
Any proposal to "recompute hash to validate" = BLOCKED (except in test verification path)
The repository owns the hash, the read path trusts the stored hash

### Latest-Template-on-Read Anti-Pattern (Phase 4B v2 lesson)
Any proposal to call fetchLatestTemplate() from a read/query path = REVIEW REQUIRED
Historical analytical results should use pinned context (template_hash from analysis time)
Query-time resolution of "latest" causes silent semantic drift

### Latest-Wins Without Tie-Break
Using MAX(recorded_at) alone = INSUFFICIENT (non-deterministic if same timestamp)
Must always include MAX(primary_key) as final tie-break

## Test Coverage Requirements for Kernel-Adjacent

Scorecard v0 demonstrates required test coverage for kernel-adjacent domains:

**Schema Immutability** (10 tests):
- UPDATE rejected for all 5 tables
- DELETE rejected for all 5 tables

**Content-Addressing** (3 tests):
- Hash computed exactly once on insert
- Fetch never recomputes hash
- Idempotent insert (duplicate hash returns existing)

**Hole-Count Consistency** (3 tests):
- 9-hole validation
- 18-hole validation
- Invalid hole count rejected

**Round Lifecycle** (4 tests):
- End-to-end create → score → complete
- Completion is append event
- Double completion rejected
- listRounds returns correct data

**Latest-Wins** (3 tests):
- Correction overwrites earlier score
- History preserved
- Deterministic ordering

**Constraint Validation** (3 tests):
- FK integrity (invalid course_hash rejected)
- Range checks (hole_number, strokes)

**Partial Scoring** (1 test):
- Running total with incomplete data

Total: 27 tests covering all invariants.

This is the bar for kernel-adjacent domains seeking hardening/promotion.

## Governance Document Updates

When adding kernel-adjacent domain:
1. Add tables to KERNEL_GOVERNANCE.md Section 9 (Domain Registry) under "Kernel-Adjacent"
2. Add files to KERNEL_SURFACE_AREA.md under "KERNEL-ADJACENT" section
3. Document status, tables, notes (immutability, content-addressing, correction semantics)
4. Link to branch/migration where schema landed
5. State promotion criteria (not yet hardened, not yet frozen)

Scorecard v0 correctly updated both documents.

### Phase 4B v2 Analysis-Context Linkage (2026-02-10)
**Status**: APPROVED as KERNEL EXTENSION
**Classification**: Extends frozen kernel (club_subsessions table added in v1 migration)

**What was added:**
- SubsessionRepository class with analyzeSessionClub() method
- A-only trends rewritten to use club_subsessions.kpi_template_hash (pinned at analysis time)
- UI wiring: analyzeImportedSession() in SessionsView (post-import hook)
- 2 new integration tests proving append-only analysis + trend stability

**Why approved:**
1. No kernel table modifications: club_subsessions table already existed in v1 schema migration
2. Additive repository class: SubsessionRepository does not modify existing frozen repositories
3. Hash-once preserved: Template hash is read from kpi_templates (stored hash), never recomputed
4. Immutability preserved: club_subsessions has immutability trigger (already in Schema.swift)
5. Idempotent insert: Uses INSERT OR IGNORE with UNIQUE(session_id, club, kpi_template_hash)
6. Read path discipline: fetchAOnlyTrendPoints reads stored hash from club_subsessions, never calls fetchLatestTemplate
7. No semantic drift: Previous "latest template at query time" behavior replaced with explicit pinned-template semantics

**Kernel touchpoints reviewed:**
- Repository.swift lines 493-691: TrendsRepository.fetchAOnlyTrendPoints() rewritten
- Repository.swift lines 613-691: SubsessionRepository added
- SessionsView.swift lines 150-178: analyzeImportedSession() (UI layer, non-kernel)
- Schema.swift: club_subsessions table pre-existing (v1 migration), immutability trigger confirmed

**Tests proving correctness:**
- testAOnlyTrendStableWhenNewTemplateInserted: Proves historical points stable when new template inserted (RTM-04 + pinned-template semantics)
- testAppendOnlyAnalysis_DifferentTemplateCreatesNewRow: Proves Kernel Contract invariant 1.4 (append-only, no UPDATE)
- testTrendsV2_AllShotsAndAOnly_DeterministicAndStable: Updated to Phase 4B v2 semantics

### Back-9 Hole Set Validation (2026-02-10)
**Status**: APPROVED as KERNEL-ADJACENT EXTENSION
**Classification**: Code-level validation in kernel-adjacent repository (no schema change)

**What was added:**
- CourseSnapshotRepository.insertCourseSnapshot() validation:
  - 9-hole snapshots must be {1..9} or {10..18}
  - 18-hole snapshots must be {1..18}
  - Malformed sets (e.g., {1..8, 10}) rejected with CourseSnapshotError.invalidHoleSet
  - Transaction rollback on rejection (no partial insert)

**Why approved:**
- No schema change (validation is pre-insert guardrail)
- Maintains transactional integrity (GRDB write block ensures rollback)
- Test coverage proves rollback correctness (testMalformedNineHoleSetRejected)
- Scorecard domain is kernel-adjacent (not frozen)
