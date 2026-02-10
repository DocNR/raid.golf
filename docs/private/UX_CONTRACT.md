# UX Contract -- RAID Analytical Semantics (Private)

**Version:** 1.0 (as of 2026-02-09)
**Status:** Frozen pending review before KPI Template UX sprint
**Applies to:** Trends, classification, scorecard, and analysis features
**Companion:** `KERNEL_CONTRACT_v2.md` (integrity layer)

> This document declares which analytical behaviors are locked, which decisions are explicitly deferred, and which areas remain free to iterate. Any change to Section A requires test updates and a CHANGELOG entry.

---

## A) Locked Semantics (What MUST NOT Change)

### A.1 A-Only Trends Use Pinned Template
- Classification uses `club_subsessions.kpi_template_hash` persisted at analysis time
- The A-only query path NEVER calls `fetchLatestTemplate`
- Historical trend points are stable: inserting a new template does not change existing points
- **Test:** `testAOnlyTrendStableWhenNewTemplateInserted` (IngestIntegrationTests)

### A.2 Sessions Without Analysis Are Excluded
- Sessions missing a `club_subsessions` row are excluded from A-only trends
- No silent fallback to latest template; absence = not yet analyzed
- **Test:** `testTrendsV2_AllShotsAndAOnly_DeterministicAndStable` (IngestIntegrationTests)

### A.3 Re-Analysis Is Append-Only
- Analyzing with a new template creates a NEW `club_subsessions` row
- The original row is preserved with all metrics unchanged
- `UNIQUE(session_id, club, kpi_template_hash)` prevents duplicate analysis with the same template
- **Test:** `testAppendOnlyAnalysis_DifferentTemplateCreatesNewRow` (IngestIntegrationTests)

### A.4 Validity Thresholds
- <5 shots = `invalid_insufficient_data` (A% is NULL)
- 5-14 shots = `valid_low_sample_warning`
- >=15 shots = `valid`
- **Enforcement:** `SubsessionRepository.analyzeSessionClub()` at `ios/RAID/RAID/Kernel/Repository.swift` lines 642-648
- **Test coverage:** No standalone unit test; exercised indirectly through integration tests

### A.5 allShots Uses SQL AVG/COUNT
- No Swift classification involved; purely SQL aggregation
- COUNT uses non-null metric values only
- Ordering of points is `session_date ASC, session_id ASC`
- **Test:** `testTrendsV2_AllShotsAndAOnly_DeterministicAndStable` (IngestIntegrationTests)

### A.6 Hole Set Validation
- 9-hole snapshots must be exactly {1..9} (front) or {10..18} (back)
- 18-hole snapshots must be exactly {1..18}
- Malformed sets are rejected with `invalidHoleSet` error; transaction rolls back completely
- **Tests:** `testBack9SnapshotInsertsExactlyNineHolesStartingAt10`, `testMalformedNineHoleSetRejected` (ScorecardTests)

### A.7 Latest-Wins Scoring
- Corrections are new `hole_scores` rows (append-only, immutable)
- Current score = latest by `MAX(recorded_at), MAX(score_id)`
- Deterministic tie-breaking guaranteed
- **Tests:** `testCorrectionLatestWins`, `testLatestWinsDeterministicOrdering` (ScorecardTests)

### A.8 Immutability
- All authoritative tables have SQLite triggers blocking UPDATE/DELETE
- Kernel tables: `sessions`, `kpi_templates`, `shots`, `club_subsessions`
- Scorecard tables: `course_snapshots`, `course_holes`, `rounds`, `round_events`, `hole_scores`
- **Tests:** KernelTests (4 tables) + ScorecardTests (5 tables)

---

## B) Non-Decisions (Explicitly Deferred)

### B.1 Advanced Re-Analysis UX
- Manual analysis of unanalyzed clubs is supported via UI (creates first analysis)
- Re-analysis of existing analyses with a different template requires code (no UI yet)
- No bulk re-analysis or batch re-classification UI
- Individual template identity (name + short hash) per analysis is displayed in session detail

### B.2 Multi-Template Trend Filtering
- A-only chart currently mixes points from different template versions
- No per-template filtering or version comparison UI yet
- Template identity per point is persisted and available for future filtering

### B.3 Subsession Lifecycle Management
- No mechanism to archive or soft-delete stale analysis rows
- Append-only semantics mean old analyses accumulate; this is by design

### B.4 Template Versioning Display
- Template identity (name + short hash) is available in `club_subsessions.kpi_template_hash`
- Basic visibility of which template was used may be added in the template UX sprint
- Advanced version diffing or migration tooling is deferred

### B.5 Back-9 Starting Hole
- No `hole_start` column on `course_snapshots`
- `hole_number` on `course_holes` rows encodes front-9 vs back-9 identity directly
- Tests prove this is sufficient for current 9/18-hole formats

---

## C) What CAN Change Freely

These areas iterate without breaking analytical guarantees:
- UI layout, colors, animations, tab ordering
- Chart presentation, axes, labels
- Empty state copy and illustrations
- Navigation patterns (modal vs push)
- Non-authoritative derived views and summaries
- Export formats (as long as derived from authoritative data)

---

## D) Reference

| Document | Path |
|----------|------|
| Kernel Contract v2 | `docs/private/kernel/KERNEL_CONTRACT_v2.md` |
| Schema | `ios/RAID/RAID/Kernel/Schema.swift` |
| Integration Tests | `ios/RAID/RAIDTests/IngestIntegrationTests.swift` |
| Scorecard Tests | `ios/RAID/RAIDTests/ScorecardTests.swift` |
| Kernel Tests | `ios/RAID/RAIDTests/KernelTests.swift` |
| CHANGELOG | `CHANGELOG.md` |
