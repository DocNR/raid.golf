# Documentation & Governance Agent Memory

## Governance Structure

- **KERNEL_SURFACE_AREA.md** — file-level classification (KERNEL / KERNEL-ADJACENT / OUTSIDE KERNEL)
- **KERNEL_GOVERNANCE.md** — domain-level registry, lifecycle rules, promotion checklist
- **KERNEL_CONTRACT_v2.md** — frozen contract for launch-monitor kernel (sessions, shots, templates)
- **KERNEL_FREEZE_v2.md** — freeze declaration for kernel v2.0

## File Classification Rules

### KERNEL-ADJACENT
- Storage repositories (e.g., ScorecardRepository, ShotRepository)
- Schema definitions that enforce immutability
- Domain models that match authoritative schema

### OUTSIDE KERNEL
- View models and presentation logic (e.g., ActiveRoundStore)
- UI views and SwiftUI components
- Application entry points (RAIDApp, ContentView)

**Key distinction:** Repositories define storage invariants; view models call repositories but are presentation/state glue.

## iOS/SwiftUI Patterns Discovered

### GRDB Read Patterns
- **Problem:** Nested `dbQueue.read` calls cause GRDB precondition failures ("Database methods are not reentrant")
- **Solution:** Use sequential non-nested reads — call repos one after another, not nested
- **Example:** `RoundDetailView.loadData()` bugfix (Issue B) restructured to sequential reads
- **Reference:** `ios/RAID/RAID/Views/RoundDetailView.swift`, `ios/RAID/RAID/Scorecard/ActiveRoundStore.swift` (loadData method)

### Default Value Persistence
- **Problem:** Using `guard let` to check if user adjusted from default skips persistence when they didn't
- **Solution:** Always persist the displayed value, even if it's the default
- **Example:** `saveCurrentScore()` in ActiveRoundStore (Issue A fix) — removed `guard let`, always writes `strokes ?? hole.par`
- **Reference:** `ios/RAID/RAID/Scorecard/ActiveRoundStore.swift` lines 148-163

### Long-Lived View Model Pattern
- **Pattern:** For stateful flows that must survive view recreation, use `@Observable` class owned at parent level via `@State`
- **Example:** `ActiveRoundStore` owned by `RoundsView`, passed to `ScoreEntryView`
- **Benefit:** State survives navigation/view recreation; child view becomes thin render shell
- **Reference:** `ios/RAID/RAID/Scorecard/ActiveRoundStore.swift`, `ios/RAID/RAID/Views/RoundsView.swift`

### Confirmation Dialog Pattern
- **Pattern:** Use boolean `@State` flag + `.alert()` modifier for confirmation prompts
- **Example:** `showFinishConfirmation` in ActiveRoundStore triggers "Are you sure?" alert before finishing round
- **Reference:** `ios/RAID/RAID/Scorecard/ActiveRoundStore.swift` lines 137-144

### Last-Hole Finish Eligibility Pattern
- **Problem:** Finish button disabled on last hole because `saveCurrentScore()` only fired when navigating away
- **Solution:** Call `ensureCurrentHoleHasDefault()` when arriving at each hole to populate default par in memory
- **Example:** ActiveRoundStore navigateToHole method ensures default value exists before rendering
- **Reference:** `ios/RAID/RAID/Scorecard/ActiveRoundStore.swift`

## Recent Updates

### 2026-02-10: KPI Template UX Sprint Task 10 Documentation Review (COMPLETE)
- **Sprint scope:** Tasks 1-9 implementation + Task 10 documentation hardening
- **Test count:** 20 new tests added (16 in KernelTests, 4 in BootstrapTests) → 96 total project tests
- **CHANGELOG.md:** Sprint entry added to [Unreleased] section — accurate and complete
- **UX_CONTRACT.md:** Updated to v1.1 with two new locked semantics (A.9, A.10) — both have verified test references
- **KERNEL_SURFACE_AREA.md v1.5:** All new files properly classified (product-layer table, repositories, views)
- **KERNEL_GOVERNANCE.md:** template_preferences correctly listed in "Derived / Outside Kernel" section (line 287)
- **A.9 test:** `testActiveTemplateSwitchDoesNotAffectExistingSubsessions` exists at KernelTests.swift:1697
- **A.10 test:** `testHiddenTemplateAnalysesRemainVisible` exists at KernelTests.swift:1822
- **Minor inconsistency:** CHANGELOG claims "~30 new tests" but actual count is 20 (does not affect semantic accuracy)

### 2026-02-10: Hard-Stop Deliverables Cleanup
- **UX_CONTRACT.md** (A.4): Added enforcement location (SubsessionRepository.analyzeSessionClub lines 642-648) and test coverage note (indirect via integration tests)
- **UX_CONTRACT.md** (A.5): Added deterministic ordering guarantee (`session_date ASC, session_id ASC`)
- **CHANGELOG.md**: Replaced v1/v2 limitation note with clean v2-final semantics in Notes section
- **CHANGELOG.md**: Changed first line from "Strike Quality Practice System" to "RAID Golf"

## Domain Status (as of 2026-02-09)

### Frozen Kernel
- **Launch-monitor:** sessions, shots, templates, subsessions — frozen since Kernel v2.0 (2026-02-02)

### Kernel-Adjacent (Incubation)
- **Scorecards:** course_snapshots, course_holes, rounds, round_events, hole_scores
- 70 tests (as of scorecard v0 bugfix sprint)
- No schema changes in bugfix sprint — only implementation/state management fixes

## Test Count Evolution
- Scorecard v0 initial: 27 tests in ScorecardTests.swift
- Scorecard v0 bugfix sprint: +4 tests → 31 tests in ScorecardTests.swift (~69 total project-wide)
  - Covers: immutability, hash-once, latest-wins, FK integrity, nested-read safety, default-value persistence
- KPI Template UX sprint: +20 tests (16 KernelTests, 4 BootstrapTests) → 96 total project tests
  - Covers: v4 migration, preference CRUD, FK enforcement, active uniqueness, list methods, bootstrap idempotency, active/hidden semantics

## Cross-Reference Map

- `KERNEL_SURFACE_AREA.md` references `KERNEL_GOVERNANCE.md` domain registry (line 6)
- Domain registry in `KERNEL_GOVERNANCE.md` section 9 lists all kernel/kernel-adjacent domains
- `KERNEL_GOVERNANCE.md` promotion checklist (section 7) defines path from incubation → frozen

## Version History Conventions

Both `KERNEL_SURFACE_AREA.md` and `KERNEL_GOVERNANCE.md` maintain version tables at the end:
- Format: `| Version | Date | Changes |`
- Date format: `YYYY-MM-DD`
- Changes: concise description of what was added/modified
