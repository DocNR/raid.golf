# Kernel Steward Memory

## Approved Kernel Extensions

### Template Preferences Layer (2026-02-10)
**Status**: APPROVED as KERNEL EXTENSION
**Classification**: Non-kernel preference layer (mutable by design)
**Migration**: v4_create_template_preferences
**Commits**: 067cc9c (migration), 4aa003f (repository layer)

**What was added:**
- template_preferences table: mutable preference storage for KPI templates
- TemplatePreferencesRepository: CRUD for display names, active/hidden status
- TemplateRepository read extensions: listTemplates(forClub:), listAllTemplates()
- SubsessionRepository read extension: fetchSubsessions(forSession:)
- TemplateRecord extension: added importedAt field (internal change only)

**Why approved:**
- Additive migration (no modification to existing kernel tables)
- Clean separation: kpi_templates (immutable facts) vs template_preferences (mutable UI state)
- Partial unique index enforces "at most one active per club" without application locking
- FK to kpi_templates with ON DELETE RESTRICT (read-only reference)
- TemplatePreferencesRepository only mutates template_preferences (never kernel tables)
- No nested dbQueue.read calls (correct GRDB usage)
- 16 new tests covering migration, constraints, transactions, read extensions

**Key invariants verified:**
1. Immutability: Zero writes to kernel tables (sessions, kpi_templates, club_subsessions, shots)
2. Hash-once: No hash computation in any new code
3. Schema stability: TemplateRecord.importedAt change isolated to kernel layer (no external callers)
4. Transactional integrity: setActive() uses atomic 3-step transaction (deactivate → ensure → activate)
5. Deterministic ordering: All list methods use deterministic tie-breaks (rowid where applicable)

**Pattern: Mutable Preference Layer Over Immutable Kernel**
- Preference table with FK to authoritative table (ON DELETE RESTRICT)
- Club denormalized from parent for partial unique index support
- LEFT JOIN for filtering (NULL = default/not-hidden)
- INNER JOIN for active resolution (active implies row exists)
- Transactional activation to prevent race conditions

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

### NIP-101g Event Builder (2026-02-12)
**Status**: APPROVED as KERNEL-ADJACENT
**Classification**: Product layer extension (read-only kernel consumer)
**Files**: Nostr/NIP101gEvent.swift, Nostr/NIP101gEventBuilder.swift, NIP101gEventBuilderTests.swift

**What was added:**
- NIP-101g structured events (kind 1501 round initiation, kind 1502 final record)
- Pure transformation: CourseSnapshotRecord + holes → Nostr events with content-addressed hashes
- Hash parity: NIP-101g course_hash matches CourseSnapshotRepository hash for equivalent data
- 12 new tests including explicit hash parity verification

**Why approved:**
- Zero kernel modifications (no Schema, Repository, Canonical, Hashing changes)
- Read-only consumer: accepts already-fetched data, never calls repository methods
- Uses RAIDCanonicalizer + RAIDHasher via protocol DI (default args, no implementation changes)
- Hash parity test proves Codable encoding → JCS → hash matches dict-based approach
- All code in Nostr/ product layer (no kernel coupling)
- Deterministic at all layers (sorted holes, scores, JSON keys + JCS)

**Key invariants verified:**
1. Immutability: Zero writes to any kernel or scorecard tables
2. Hash-once: No kernel hash computation modified; builder uses kernel as read-only service
3. Deterministic ordering: Explicit sorts + .sortedKeys + JCS canonicalization
4. Schema stability: No kernel method signatures changed
5. Semantic drift: NONE — hash parity test proves equivalent JSON → equivalent hash

**Pattern: Read-Only Kernel Consumer**
- Product layer accepts already-fetched records (no repository coupling)
- Rebuilds canonical JSON structure using same frozen keys
- Calls kernel canonicalizer + hasher via protocol abstraction (no modification)
- Hash parity test verifies no semantic divergence
- Pure transformation with no side effects

## Common Safe Patterns

### Sprint Finalization (Regression Test Lock-In) — Task 10 (2026-02-10)
**Status**: APPROVED as KERNEL-ADJACENT
**Pattern:** Sprint finale regression test lock-in

**What was added:**
- 3 regression tests in KernelTests.swift (lines 1697-1994)
- UX_CONTRACT.md v1.1 (added A.9, A.10 locked semantics; updated B.2, B.4)
- CHANGELOG.md entry documenting full KPI Template UX Sprint scope

**Test Details:**
1. `testActiveTemplateSwitchDoesNotAffectExistingSubsessions`:
   - Creates session + analyze with T1, sets T1 active
   - Switches active to T2 (template_preferences UPDATE)
   - Asserts: club_subsessions.kpi_template_hash = T1 (immutable)
   - Asserts: A/B/C counts unchanged
   - Proves: UX_CONTRACT A.9 (Active Template Is Forward-Only)

2. `testHiddenTemplateAnalysesRemainVisible`:
   - Creates session + analyze with T1
   - Hides T1 (template_preferences UPDATE)
   - Asserts: fetchSubsessions(forSession:) returns 1 (analysis preserved)
   - Asserts: listTemplates(forClub:) returns 0 (UI filtering works)
   - Proves: UX_CONTRACT A.10 (Hidden Templates Preserve Analyses)

3. `testImportFlowUsesActiveTemplateWithFallback`:
   - Scenario 1: T2 active → fetchActiveTemplate returns T2
   - Scenario 2: No preference → fetchActiveTemplate returns nil, fetchLatestTemplate returns T1
   - Proves: Import-time resolution pattern (fetchActiveTemplate ?? fetchLatestTemplate)

**Why approved:**
- Zero kernel code changes (no Schema, Repository, Canonical, Hashing modifications)
- Tests use kernel-compliant patterns (raw SQL INSERT, repository fetch)
- Test names in UX_CONTRACT match actual method names exactly
- Tests enforce existing invariants (defensive regression guards)
- Proves separation: template_preferences (mutable) vs club_subsessions (immutable)

**Classification:** KERNEL-ADJACENT (no kernel changes, documents existing behavior)

**Pattern checklist:**
- [ ] Regression tests added at end of sprint (not enabling new behavior)
- [ ] UX_CONTRACT updated with locked semantics + test references
- [ ] CHANGELOG entry summarizing sprint scope
- [ ] Test names match UX_CONTRACT references exactly
- [ ] Tests verify separation of mutable preferences vs immutable kernel data

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

### Kernel Struct Changes (Method Signature Risk)
Adding fields to kernel structs (TemplateRecord, ShotRecord, etc.) = REVIEW REQUIRED
- Check all construction sites (are they internal or external?)
- Views consuming structs = safe (read-only)
- Views constructing structs = breaking change
- Optional fields = less breaking than required fields
- Example: TemplateRecord.importedAt addition was safe (all constructors internal to Repository.swift)

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

**SAFE EXCEPTION: Import-time vs Display-time distinction (2026-02-10)**
- Import-time template resolution (fetchActiveTemplate ?? fetchLatestTemplate) = SAFE
  - Creates FIRST analysis for a session
  - Template hash is still recorded in club_subsessions.kpi_template_hash
  - Pinned context preserved for historical stability
- Display-time template resolution = BLOCKED (causes drift)
- Manual re-analysis (explicit user action) = SAFE (creates NEW row, append-only)

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

### KPI Template UX Sprint — Tasks 7+8 (2026-02-10)
**Status**: APPROVED as KERNEL-ADJACENT
**Classification**: UI consuming kernel data, no kernel method changes

**What changed:**
- SessionsView: Import auto-analyze prefers fetchActiveTemplate() ?? fetchLatestTemplate() (import-time)
- PracticeSummaryView: Complete refactor — display path reads club_subsessions (no on-the-fly classification)
- Manual re-analysis via "Analyze" button (explicit user action, append-only)

**Why approved:**
- Eliminates analytical semantic drift (old PracticeSummaryView called fetchLatestTemplate on every view)
- Display path now read-only from persisted club_subsessions
- Import-time template resolution follows approved safe pattern (Phase 4B v2)
- Re-analysis creates NEW rows via INSERT OR IGNORE (history preserved)
- No kernel signature changes, no schema changes
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

### KPI Template UX - Tasks 7+8 (2026-02-10)
**Status**: APPROVED as KERNEL-ADJACENT
**Classification**: Product layer enhancement using existing kernel contracts

**What changed:**
- Import path: Now uses `fetchActiveTemplate ?? fetchLatestTemplate` instead of just `fetchLatestTemplate`
- PracticeSummaryView: Removed on-the-fly classification, now reads persisted `club_subsessions` rows
- Re-analysis UI: Manual analyze button per club, creates NEW row via SubsessionRepository

**Why approved:**
1. Template preference is product layer: Active template selection happens before analysis, but template hash is still persisted in club_subsessions
2. Display-time classification REMOVED: Eliminated a query-time template resolution path (strengthens invariant, not weakens)
3. Append-only re-analysis: Uses INSERT OR IGNORE with UNIQUE constraint, creates NEW row for different template
4. No kernel method changes: All methods used are existing frozen kernel methods
5. Distinction upheld: Import-time resolution (first analysis) is acceptable; display-time resolution (historical drift) is blocked

**Files changed:**
- SessionsView.swift: Import auto-analyze now prefers active template
- PracticeSummaryView.swift: Complete refactor from on-the-fly to persisted data reads

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

### Nostr Round Sharing (2026-02-12)
**Status**: APPROVED as KERNEL-ADJACENT
**Classification**: Ephemeral social sharing (output-only, no feedback loop)

**What was added:**
- Nostr/KeyManager.swift: iOS Keychain-backed nsec storage (no SQLite interaction)
- Nostr/NostrClient.swift: Fire-and-forget kind 1 note publisher (no persistence, no subscriptions)
- Nostr/RoundShareBuilder.swift: Pure formatting (receives RoundRecord/CourseSnapshot/HoleScore, returns strings)
- Views/NostrProfileView.swift: npub display, nsec copy, relay info (read-only)
- RoundDetailView: Added share toolbar, changed loadData to fetch full RoundRecord instead of just course_hash
- RoundsView: Added profile button on toolbar

**Why approved:**
1. Zero writes to kernel or kernel-adjacent tables (Nostr publishing is ephemeral)
2. No new schema, no migrations, no repository modifications
3. Read path expansion (course_hash → full RoundRecord) is safe widening for presentation
4. RoundShareBuilder is pure formatting layer (no DB access, 8 tests)
5. NostrClient has no durable state, no "posted" flags, no FK constraints (correct pattern)
6. No feedback loop: data flows OUT (read → format → publish), never IN from Nostr to SQLite
7. All kernel invariants preserved (immutability, hash-once, schema stability, determinism)

**Pattern: Ephemeral Social Sharing**
- Read immutable data from kernel-adjacent layer (scorecard)
- Format for external platform (Nostr, Twitter, etc.) in pure presentation layer
- Fire-and-forget publish with no persistence of "posted" state
- No feedback loop into data layer
- Analogous to PDF export, email, etc.
- Safe to replicate for future integrations (webhooks, social APIs)

## Review Lessons

### Template Preferences Review (2026-02-10)
**Reviewed**: Tasks 1 & 2 from KPI Template UX Sprint (commits 067cc9c, 4aa003f)
**Outcome**: ✅ APPROVED as KERNEL EXTENSION

**Files changed:**
- Task 1 (067cc9c): Schema.swift migration v4, KernelTests.swift (+7 tests)
- Task 2 (4aa003f): Repository.swift (+3 read methods), TemplatePreferencesRepository.swift (new), KernelTests.swift (+9 tests)

**Key findings:**
1. Migration positioned correctly after v3, no conflicts
2. template_preferences correctly has NO immutability triggers (intentionally mutable)
3. Partial unique index syntax correct: `CREATE UNIQUE INDEX ... ON template_preferences(club) WHERE is_active = 1`
4. FK constraint correct: REFERENCES kpi_templates(template_hash) ON DELETE RESTRICT
5. CHECK constraints work: `CHECK (is_active IN (0, 1))`, `CHECK (is_hidden IN (0, 1))`
6. No risk to existing kernel tables
7. All new Repository methods are read-only extensions (no signature changes)
8. TemplateRecord.importedAt addition safe (all constructors internal to Repository.swift)
9. TemplatePreferencesRepository only writes to template_preferences (never kernel tables)
10. setActive() transaction correct: deactivate → ensure → activate (3 steps, atomic)
11. No nested dbQueue.read calls anywhere
12. 16 new tests cover all constraints, transactions, and edge cases
13. All KernelTests pass (no regressions)

**Test coverage verified:**
- Migration constraints: FK, unique index, defaults, CHECK constraints
- Mutability: UPDATE/DELETE allowed (no triggers)
- Transactional activation: setActive switches atomically
- Read-only kernel extensions: listTemplates, listAllTemplates, fetchSubsessions
- CRUD operations: setDisplayName, setHidden, fetchActiveTemplate, ensurePreferenceExists

**Retrospective lessons:**
- Always verify nested dbQueue.read calls (grep with multiline)
- Always verify struct construction sites when adding optional fields
- Always verify transactional semantics for multi-step operations
- Test coverage for constraints is as important as feature tests
- Partial unique indexes work correctly for "at most one X per Y" patterns
