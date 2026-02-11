# iOS Port Plan — Phase 0 Kernel to Swift

**Status:** HISTORICAL (through Phase 4D — KPI Template UX)
**Created:** 2026-02-05
**Context:** Jumping ahead on roadmap to start iOS development

> **Note:** This document records the design and execution of the iOS kernel port through Phase 2.4. Future work proceeds via milestone-specific plans (e.g., Phase 3 Practice MVP).

---

## Roadmap Context

### What's Complete (Python)
- Phase 0 (A-F): All RTM-01 through RTM-17 validated
- Phase 0.1: CLI + Results & Trends
- Kernel v2.0: canonicaljson-compatible JCS

### What We're Skipping (For Now)
- Phase 0.2: Shot explainability & advanced analytics
- Phase 0.3: Aggregate Trends improvements

### Why Skip Ahead
- On-course scoring is the real goal (Phase 3)
- iOS/Swift competence is required regardless
- Phase 0 kernel is stable and has cross-platform test vectors
- Shot persistence (0.2) doesn't help on-course scoring
- Better to learn iOS on simpler Phase 0 domain first

---

**Current Next Phase: Phase 5 — Production Hardening**

Practice MVP is feature-complete. Phase 4B v2 (analysis-context linkage) and
Phase 4D (KPI Template UX sprint) are both complete and merged to main.

The app now has: CSV import, 4-tab navigation (Trends + Sessions + Rounds + Templates),
template management (active/hidden/rename/duplicate), pinned-template A-only trends,
session detail with persisted analyses, trends template filtering, and scorecard scoring.

96 unit/integration tests passing. UX Contract v1.1 locked (A.1-A.10).

Focus shifts to production-readiness for user testing:
- 5.1: Release build sanity (archive, physical device, file import permissions)
- 5.2: Export/share foundation (session summary JSON, share sheet)
- 5.3: Error handling polish (replace silent `try?` with actionable messages)
- 5.4: First-run experience (empty states, template explanation, import CTA)
- 5.5: UX contract + docs (user-facing README, TestFlight notes, known limitations)
- 5.6: Local debug screen (db version, template/session/subsession counts)

---

## Critical Risk: JSON Number Serialization

**This is the #1 cross-platform failure mode.**

Foundation's `JSONSerialization` / `JSONEncoder` will mangle numbers:
- Trailing `.0` on integers (e.g., `1` becomes `1.0`)
- Exponent notation for large/small numbers
- Precision loss when parsing into `Double`
- `-0` handling differences

### Solution: Token-Preserving Parse

Do NOT parse JSON numbers into `Double` and re-emit. Instead:
1. Parse JSON into a tree where numbers are stored as **original text**
2. Apply JCS normalization rules on the text representation
3. Re-emit normalized text (not binary float conversion)

### Explicit Guardrails
- **Reject non-JSON numbers at parse time:** NaN, Infinity, leading zeros, etc.
- **Normalize from textual lexeme**, never from `Double`
- Integer-looking values (e.g., `1.0`) must emit as `1` per RFC 8785

This matches the Python `canonicaljson` library behavior.

---

## Execution Phases

> **Phase Naming Note**
> This document uses Phases 1–5 for iOS execution milestones.
> Phases 1–4D cover the kernel port through KPI Template UX.
> Phase 5 covers production hardening for user testing.
> Product-level milestones (Milestone 1, 2, 3...) are in `ROADMAP_LONG_TERM.md`.
> Python implementation phases (A–F) are in `docs/implementation_phases.md`.

### Phase 1: Project Setup

**Do this first** — you need an Xcode project before you can run kernel tests.

**Location:** Same repo, in `ios/` subdirectory. This keeps test vectors, specs, and Python reference implementation co-located.

1. Create iOS project (SwiftUI) in `ios/`
2. Add GRDB dependency via Swift Package Manager
3. Create test target for kernel harness (XCTest)
4. Structure:
   ```
   raid.golf/
   ├── raid/                 # Python implementation (existing)
   ├── tests/                # Python tests + shared test vectors (existing)
   │   └── vectors/          # JCS vectors, golden hashes — shared with Swift
   ├── docs/                 # Specs (existing, shared)
   ├── ios/                  # NEW: Swift/iOS project
   │   ├── RAID.xcodeproj
   │   ├── RAID/
   │   │   ├── Kernel/       # Separate module (enforces access boundaries)
   │   │   │   ├── Canonical.swift
   │   │   │   ├── Hashing.swift
   │   │   │   ├── Schema.swift
   │   │   │   └── Repository.swift
   │   │   ├── Models/
   │   │   │   ├── Session.swift
   │   │   │   ├── ClubSubsession.swift
   │   │   │   └── KPITemplate.swift
   │   │   ├── Ingest/
   │   │   │   └── RapsodoIngest.swift
   │   │   └── Views/
   │   │       └── (minimal)
   │   └── RAIDTests/
   │       └── KernelTests.swift
   └── tools/                # KPIs, scripts (existing)
   ```

**Key:** Consider making `Kernel/` a separate Swift module. This enforces "no re-hash on read" at compile time — read-side code literally cannot import the hashing functions.

**Test vectors:** Reference `../tests/vectors/` from Swift tests. Single source of truth for cross-platform parity.

---

### Phase 2: Kernel Harness (No UI, No Ingest)

**Goal:** Prove Swift can match Python kernel before building anything else.

This is XCTest only. No SwiftUI.

#### 2.1 Canonical.swift — Kernel v2 Canonicalization (canonicaljson parity)

*Kernel v2 canonicalization is canonicaljson-compatible JCS, including preservation of -0.0. Strict RFC 8785 normalization (e.g., `-0` → `0`) is explicitly deferred to a future kernel version.*

- Lexicographic key ordering at all nesting levels
- Number normalization (integers without decimal, minimal precision)
- Compact JSON (no whitespace), UTF-8 without BOM
- **Reject invalid JSON numbers** (NaN, Infinity, leading zeros) at parse time
- **Test:** All 12 vectors from `tests/vectors/jcs_vectors.json` pass

#### 2.2 Hashing.swift — SHA-256 Content-Addressed Hashing

- Formula: `hash = SHA-256(UTF-8(JCS(json)))`
- Use CryptoKit
- **Test:** All golden hashes from `tests/vectors/expected/template_hashes.json` match

#### 2.3 Schema.swift — SQLite Schema + Immutability Triggers

Tables (all authoritative, all immutable):
- `sessions`
- `kpi_templates`
- `club_subsessions`

Triggers:
- BEFORE UPDATE → ABORT (all three tables)
- BEFORE DELETE → ABORT (all three tables)

Schema install must:
- Run `PRAGMA foreign_keys = ON;` per connection
- Create triggers in same migration step as tables (GRDB handles this)

**Invariant:** All authoritative tables are immutable; only derived views/queries change.

**Design rule:** No table ever transitions from mutable → immutable in-place; immutability is a creation-time property.

**Test:** UPDATE and DELETE attempts fail with trigger error

#### 2.3b Shots Table — Shot Persistence (v2_add_shots migration)

**Goal:** Add authoritative shot-level fact table as a separate migration.

**Migration:** `v2_add_shots` (separate from `v1_create_schema`)

**Schema:**
```sql
CREATE TABLE shots (
    shot_id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id INTEGER NOT NULL,
    
    -- Provenance
    source_row_index INTEGER NOT NULL,    -- 0-based row in source CSV
    source_format TEXT NOT NULL,          -- e.g. "rapsodo_mlm2pro_shotexport_v1"
    imported_at TEXT NOT NULL,            -- ISO-8601
    raw_json TEXT NOT NULL,              -- Full parsed row as JSON
    
    -- Normalized columns (KPI-relevant, all nullable)
    club TEXT NOT NULL,                   -- Normalized club label
    carry REAL,                          -- Carry Distance (yards)
    total_distance REAL,                 -- Total Distance (yards)
    ball_speed REAL,                     -- Ball Speed (mph)
    club_speed REAL,                     -- Club Speed (mph)
    launch_angle REAL,                   -- Launch Angle (degrees)
    launch_direction REAL,              -- Launch Direction (degrees)
    spin_rate REAL,                      -- Spin Rate (rpm)
    spin_axis REAL,                      -- Spin Axis (degrees)
    apex REAL,                           -- Apex / max height (ft)
    descent_angle REAL,                  -- Descent Angle (degrees)
    smash_factor REAL,                   -- Smash Factor (ratio)
    attack_angle REAL,                   -- Attack Angle (degrees)
    club_path REAL,                      -- Club Path (degrees)
    side_carry REAL,                     -- Side Carry (yards)
    
    FOREIGN KEY (session_id) REFERENCES sessions(session_id)
        ON DELETE RESTRICT,
    
    UNIQUE (session_id, source_row_index),
    CHECK (source_row_index >= 0)
);

CREATE INDEX idx_shots_session ON shots(session_id);
CREATE INDEX idx_shots_club ON shots(club);

-- Immutability triggers
CREATE TRIGGER shots_no_update BEFORE UPDATE ON shots
BEGIN SELECT RAISE(ABORT, 'Shots are immutable after creation'); END;

CREATE TRIGGER shots_no_delete BEFORE DELETE ON shots  
BEGIN SELECT RAISE(ABORT, 'Shots are immutable after creation'); END;
```

**Design rationale:**
- **Normalized columns** cover all MLM2Pro fields relevant to KPIs (all nullable REAL)
- **`raw_json`** preserves full parsed CSV row (never lose data)
- **`source_row_index`** + `session_id` UNIQUE prevents duplicate shot import
- **`source_format`** versioned (e.g. `"rapsodo_mlm2pro_shotexport_v1"`) for future device support
- **No `club_brand`/`club_model`** as normalized columns — in `raw_json` if needed later

**Tests (5 tests in KernelTests.swift):**
1. `testShotInsertSucceeds` — Insert shot with FK to session
2. `testShotUpdateRejected` — UPDATE blocked by trigger
3. `testShotDeleteRejected` — DELETE blocked by trigger
4. `testShotFKEnforced` — Insert with nonexistent session_id fails
5. `testShotDuplicateRowIndexRejected` — UNIQUE(session_id, source_row_index) enforced

**Exit criteria:** All 5 shot tests pass; shots table immutable; FK enforced

#### 2.4 Repository.swift — Data Access Layer

**Completed:** 2026-02-06

**Implementation:**
- **Repository owns canonicalization + hashing** — callers provide raw JSON bytes (`Data`), not pre-computed hashes
- **Read paths are hash-free by construction + test-enforced** — fetch methods return stored hash directly, never recompute
- **Database factory with explicit FK enforcement** — `DatabaseQueue.createRAIDDatabase()` sets `Configuration.foreignKeysEnabled = true`
- **Protocol-based dependency injection** — `Canonicalizing` and `Hashing` protocols enable behavioral testing via spies (no global DEBUG counters)

**Files created:**
- `Kernel/Protocols.swift` — DI protocols + production implementations
- `Kernel/Repository.swift` — TemplateRepository, SessionRepository, ShotRepository

**Test coverage:**
- `testInsertTemplateComputesHashOnce` — Verifies exactly 1 canonicalize + 1 hash call during insert
- `testFetchTemplateNeverRecomputesHash` — Verifies 0 calls during fetch (RTM-04 compliance)
- Test spies: `SpyCanonicalizer`, `SpyHasher` count calls without polluting production code

**Exit Criteria:** ✅ All 31 tests pass (29 existing + 2 repository tests). Swift hashes match Python hashes exactly.

**Repository interfaces are now FROZEN** — treat method signatures as semi-public kernel API. Any change here should feel "expensive."

---

### Phase 3: Ingest + Validity

**Note:** Ingest is outside-kernel and can iterate, but parity with Python must be strict.

#### 3.1 RapsodoIngest.swift — CSV Parsing

- Header detection (rows 1-3)
- Footer exclusion (Average, Std. Dev.)
- Multi-club session support
- Shot classification (worst_metric aggregation)
- Output as pure intermediate structures first, then persist via repository

#### 3.2 Validity.swift — Validity Computation

- Thresholds: invalid (<5), warning (5-14), valid (≥15)
- A% computation (NULL when invalid)

#### 3.3 Golden Aggregate Fixture

Generate from Python for `rapsodo_mlm2pro_mixed_club_sample.csv`:
- Totals per club
- A/B/C counts
- Key averages (carry, ball speed, spin, descent)

**Equality semantics (explicit):**
- Numeric comparison: exact match (no rounding in stored facts; rounding only at display)
- Ordering: clubs sorted alphabetically, subsessions by creation order
- Nulls: A% is NULL when validity = invalid

**Test:** Ingest sample CSV, compare to golden fixture with explicit equality rules.

---

### Phase 4A: Validation Harness (Data Confidence)

**Goal:** Prove correctness and determinism before UI.

#### 4A.1 Fixture Ingest Test
- CSV fixture ingestion
- Count, row identity, FK integrity assertions

#### 4A.2 Classification Determinism Test
- Template-driven classification
- Deterministic aggregation

#### 4A.3 Immutability Guardrail
- UPDATE/DELETE explicitly rejected

#### 4A.4 Golden Aggregate Fixtures (Deferred)
- Python-generated goldens
- Cross-platform parity
- Not implemented in this phase

---

### Phase 4: Minimal UI

Keep it intentionally dumb — thin viewer over repository.

1. **Sessions List** — Date, source file, session count
2. **Session Detail** — Clubs, A/B/C counts, validity, averages
3. **Trend View** — A% over time for a club
4. **File Import** — Document picker for CSV, import feedback

**Invariant:** Trend views are computed from subsession aggregates only; no direct DB mutation.

**Not in scope:**
- Template editing (kernel-sensitive, use insert path only)
- Polish / production UI
- App Store submission

---

## Library Choices

| Component | Library | Rationale |
|-----------|---------|-----------|
| SQLite | GRDB | Clean migrations, good concurrency, raw SQL for triggers |
| Hashing | CryptoKit | Built-in, no dependencies |
| JSON | Custom (token-preserving) | Foundation mangles numbers |

---

## Test Vectors (Shared with Python)

Located in repo root `tests/vectors/` — referenced from Swift via `../tests/vectors/`.

| File | Purpose |
|------|---------|
| `tests/vectors/jcs_vectors.json` | 12 RFC 8785 compliance vectors |
| `tests/vectors/expected/template_hashes.json` | Golden template hashes |
| `tests/vectors/sessions/rapsodo_mlm2pro_mixed_club_sample.csv` | Real Rapsodo export |

**Single source of truth:** Python generates golden values, Swift validates against them.

---

## Python Files to Port

| Python Source | Purpose | Swift Target |
|---------------|---------|--------------|
| `raid/canonical.py` | JCS canonicalization | `Kernel/Canonical.swift` |
| `raid/hashing.py` | SHA-256 hashing | `Kernel/Hashing.swift` |
| `raid/schema.sql` | SQLite schema | `Kernel/Schema.swift` |
| `raid/repository.py` | Data access | `Kernel/Repository.swift` |
| `raid/validity.py` | Validity rules | `Kernel/Validity.swift` |
| `raid/ingest.py` | CSV parsing | `Ingest/RapsodoIngest.swift` |

---

## Success Criteria

- [ ] JCS canonicalization matches Python for all 12 test vectors
- [ ] Template hashes match all golden values exactly
- [ ] SQLite immutability triggers block UPDATE and DELETE
- [ ] Repository read path never calls canonicalize/hash (enforced by module boundaries + tests)
- [ ] Ingest produces identical results to Python for sample CSV (exact numeric match)
- [ ] Basic UI shows sessions and details
- [ ] DB file reproducibility: same inputs → same row counts + same stored hashes + same derived aggregates

---

## Out of Scope (This Plan)

- Nostr integration
- Advanced shot explainability and analytics (Phase 0.2 feature); minimal authoritative shot persistence is complete (Phase 2.3b)
- On-course scoring (Phase 3 — next after this)
- App Store submission
- Production UI polish

---

## Deferred by Design

The following are intentionally postponed until after the Practice MVP validates the kernel + ingestion pipeline:

- **Projections:** Derived-only views regenerable from facts
- **Trend caches:** Pre-computed aggregate snapshots
- **Extended list/filter queries:** UI-driven search beyond basic list/detail

These will be addressed in Phase 3+ once the kernel and ingestion pipeline are battle-tested.

---

## Resume Point

If pausing, note which phase you're in:

- [x] Phase 1: Project Setup — **COMPLETE** (2026-02-05)
- [x] Phase 2.1: Canonical.swift — **COMPLETE** (2026-02-05)
- [x] Phase 2.2: Hashing.swift — **COMPLETE** (2026-02-05)
- [x] Phase 2.3: Schema.swift — SQLite Schema + Immutability Triggers — **COMPLETE** (2026-02-06)
- [x] Phase 2.3b: Shots Table — Shot Persistence (v2_add_shots migration) — **COMPLETE** (2026-02-06)
- [x] Phase 2.4: Repository.swift — Data Access Layer — **COMPLETE** (2026-02-06)
  - Repository owns canonicalization + hashing on insert
  - Hash computed once, never recomputed on read
  - FK enforcement enabled at DB open
  - Guardrail tests enforce invariants (spy-based verification)
- [ ] Phase 3: Ingest (sufficient for fixtures)
- [x] **Phase 4A: Validation Harness** — **COMPLETE** (2026-02-06)
  - End-to-end ingest integration test (CSV → persisted shots)
  - Classification + aggregation determinism test
  - Shot immutability guardrail test
  - Data Confidence Report documenting guarantees
- [x] **Phase 4A.2: Golden Aggregate Parity** — **COMPLETE** (2026-02-07)
  - Added deterministic generator: `tools/scripts/generate_aggregate_parity_golden.py`
  - Added canonical golden artifact: `tests/vectors/goldens/aggregate_parity_mixed_club_sample.json`
  - Added iOS bundle copy: `ios/RAID/RAIDTests/aggregate_parity_mixed_club_sample.json`
  - Added iOS parity test assertions:
    - per-club `total_shots`
    - per-club metric `count` + `sum` parity (`carry`, `ball_speed`, `smash_factor`, `spin_rate`, `descent_angle`)
    - 7i-only `template_hash` + `A/B/C` parity for `fixture_a`
  - Numeric policy locked: fixed rounding to 6 decimals, sums serialized as fixed-decimal strings
- [x] Phase 4: Minimal UI (after 4A)
  - Added Trends v1 minimal screen (allShots + aOnly) and app wiring
  - Deterministic trend ordering and A-only template hash surfacing
- [x] **Phase 4C: CSV Import + Sessions List + Empty States** — **COMPLETE** (2026-02-07)
  - Template bootstrap: bundled seed JSON, idempotent insert via repository path, async `.task`
  - Expanded `ShotRepository.insertShots` to store all 14 normalized metric columns (was carry + ball_speed only)
  - Updated `RapsodoIngest` / `ParsedShot` to pass all metrics through
  - `SessionRepository.listSessions()`: grouped SQL with shot count (no N+1)
  - `SessionRepository.sessionCount()`: for empty-state checks
  - TabView navigation: Trends + Sessions tabs
  - `SessionsView`: sessions list (newest first) + `fileImporter` CSV import + security-scoped URL handling
  - Empty-state UX on both Trends and Sessions, keyed on `sessions.count == 0`
  - Tests: bootstrap idempotency + seed template decode-as-KPITemplate

- [x] **Phase 4B v2: Analysis-Context Linkage** — **COMPLETE** (2026-02-09)
  - A-only trends pinned to `club_subsessions.kpi_template_hash`
  - Historical points stable when new templates inserted
  - Auto-analyze wired into import flow
  - Tests: `testAOnlyTrendStableWhenNewTemplateInserted`, `testAppendOnlyAnalysis`
- [x] **Scorecard v0** — **COMPLETE** (2026-02-09)
  - Full round scoring: create/entry/detail/history views
  - ActiveRoundStore pattern, Front 9/Back 9/18, hole set validation
  - 33 scorecard tests (kernel-adjacent, not frozen)
- [x] **Phase 4D: KPI Template UX Sprint** — **COMPLETE** (2026-02-10)
  - Template Library (4th tab), `template_preferences` table (v4 migration)
  - Active template per club, hide/rename/duplicate
  - Trends template filter (All / Active Only / Specific)
  - Session detail refactor (reads persisted `club_subsessions`)
  - 20 new tests (16 KernelTests, 4 BootstrapTests) — 96 total
- [ ] **Phase 5: Production Hardening** — NEXT

Current status: **Practice MVP feature-complete — Next: Phase 5 (Production Hardening)**

### Phase 1 Completion Notes (2026-02-05)

**What was completed:**
- ✅ Created iOS project (SwiftUI) at `ios/RAID/`
- ✅ Added GRDB 6.x via Swift Package Manager
- ✅ Created folder structure: Kernel/, Models/, Ingest/, Views/
- ✅ Created XCTest target (RAIDTests) with KernelTests.swift placeholder
- ✅ All placeholder files compile successfully
- ✅ App runs and displays "Phase 1 Setup Complete" UI

**Project structure:**
```
ios/RAID/
├── RAID.xcodeproj
├── RAID/
│   ├── RAIDApp.swift
│   ├── ContentView.swift
│   ├── Kernel/          # Blue folder references (auto-includes all files)
│   │   ├── Canonical.swift
│   │   ├── Hashing.swift
│   │   ├── Schema.swift
│   │   └── Repository.swift
│   ├── Models/
│   │   ├── Session.swift
│   │   ├── ClubSubsession.swift
│   │   └── KPITemplate.swift
│   ├── Ingest/
│   │   └── RapsodoIngest.swift
│   └── Views/
│       └── .gitkeep
└── RAIDTests/
    ├── RAIDTests.swift (Xcode default)
    └── KernelTests.swift (placeholder)
```

**Dependencies:**
- GRDB.swift 6.x (added to RAID target only)

**Notes:**
- Used blue folder references (not yellow groups) — works fine for compilation
- Test vectors at `../tests/vectors/` are accessible from Swift tests
- All files currently have `fatalError("Not implemented")` placeholders

**Next step:** Phase 2.1 — Implement Canonical.swift with RFC 8785 JCS canonicalization

---

## References

- Kernel Contract: `docs/private/kernel/KERNEL_CONTRACT_v2.md`
- JCS Spec: `docs/specs/jcs_hashing.md`
- Implementation Phases (Python): `docs/implementation_phases.md`
- Roadmap: `docs/private/raid-golf-roadmap.md`
