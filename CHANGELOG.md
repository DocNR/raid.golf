# Changelog
All notable changes to RAID Golf are documented here.

The format follows a simplified version of Keep a Changelog.
This project versions **behavior and rules**, not files.

---

## [v2.0] — Initial Canonical System
### Added
- Three-lane training model:
  - Lane 1: Speed Training
  - Lane 2: Technique / Constraints
  - Lane 3: Strike-Quality Ball Work
- Formal A / B / C shot classification
- Strike-quality KPIs for 7-iron
- Session structure with safety valves
- Explicit separation of training intent
- Gapping & KPI Log spreadsheet (Excel)
- KPI versioning and validation rules

### Notes
- 7-iron is the only validated club at this version
- All other clubs are provisional pending data
- This version establishes the canonical practice framework
---

## [Unreleased]

> Entries include both iOS port phases and feature sprints; ordered chronologically, grouped by theme.

### Changed

- **Revert "Gambit Golf" rebrand → "RAID Golf"**
  - Reverted all branding back to RAID Golf due to trademark conflict with gambitgolf.com (putter company)
  - Bundle identifier: `com.gambitgolf.ios` → `dev.local.RAID`
  - Display name: "Gambit Golf" → "RAID"
  - Keychain service: `com.gambitgolf.ios.nostr` → `dev.local.RAID.nostr`
  - Nostr tags: `["t","gambitgolf"]` → `["t","raidgolf"]`, `["client","gambit-golf-ios"]` → `["client","raid-golf-ios"]`
  - Updated all file headers, debug log prefixes, UI strings, test assertions, and public docs
  - 78 files modified across production code, tests, and documentation

### Added

- **iOS Phase 8A: Nostr Protocol Foundations**
  - **8A.1: Key Import**
    - `KeyManager.importKey(nsec:)` static method accepts nsec1 bech32 or hex private keys
    - Overwrites existing keypair in Keychain (no confirmation prompt — destructive by design)
    - `KeyManagerError.invalidKey(String)` error case for malformed keys
    - 5 new tests in `KeyManagerTests.swift` (import hex, import nsec1, import invalid, overwrite behavior)
  - **8A.2: NostrService Refactor**
    - Replaced static `NostrClient` enum with `@Observable NostrService` class
    - Injectable via SwiftUI Environment (`\.nostrService`) for testability and dependency injection
    - Same fire-and-forget connection pattern (NOT persistent connections)
    - Migrated all 19 call sites across 7 files (ActiveRoundStore, RoundDetailView, RoundsView, CreateRoundView, JoinRoundView, NostrProfileView, RoundSetupSheet)
    - `RAIDApp.swift` provides default `NostrService()` instance via `.environment(\.nostrService, ...)`
    - Renamed `NostrClientTests.swift` → `NostrServiceTests.swift`, deleted `NostrClient.swift`
  - **8A.3: Signature Verification**
    - All relay fetch methods now verify event signatures via `event.verify() -> Bool` (rust-nostr-swift)
    - Invalid events (bad event ID or schnorr signature) silently discarded before parsing
    - Applied in 6 methods: `fetchFollowList`, `fetchProfiles`, `fetchFollowListWithProfiles`, `fetchLiveScorecards`, `fetchFinalRecords`, `fetchEvent`
    - `verifiedEvents(_ events: [Event]) -> [Event]` private helper for DRY verification logic
  - **8A.4: Author Verification (closes B-004)**
    - Remote scoring events (kind 30501/1502) verified against round player roster
    - `isAuthorizedPlayer(eventPubkey:roundId:)` module-level helper checks `event.pubkey` against stored `round_players`
    - Applied in `ActiveRoundStore.fetchRemoteScores()` (live scorecards) and `RoundDetailView.fetchRemoteFinalRecords()` (final records)
    - Unauthorized events rejected with debug log (not cached or displayed)
    - Uses existing `RoundPlayerRepository.fetchPlayerPubkeys(forRound:)` method
  - 200 total unit/integration tests (added 5 KeyManager tests, removed 1 = 200, all passing)
  - No schema changes, no kernel changes

- **iOS Phase 7: Multi-Device Rounds**
  - Schema v7: `remote_scores` table for caching remote player scores fetched from relay queries
  - Kind 30501 addressable replaceable events for live scorecard sync (one per player per round)
  - `RemoteScoresRepository` for local persistence of relay-fetched scores (update-or-insert pattern)
  - `NIP101gEventParser.parseLiveScorecard()` / `parseFinalRecord()` for parsing 30501/1502 events
  - `NostrClient.fetchLiveScorecards()` / `fetchFinalRecords()` one-shot relay queries with d-tag filters
  - `RoundInviteBuilder` + `QRCodeGenerator` for generating QR-encoded nevent1 round invites
  - `RoundInviteSheet` displays QR code + plain-text nevent URI for sharing (toolbar QR icon in ScoreEntryView)
  - `RoundSetupSheet` loading UX: spinner ("Setting up your round...") → QR invite + "Start Scoring" button
  - `JoinRoundView` for joining multi-device rounds via nevent paste (paste-only, camera scanning deferred)
  - `RoundJoinService.joinRound()`: parses kind 1501 initiation event, creates local round, validates hashes
  - Hash verification on join: recomputes `course_hash` and `rules_hash` from embedded JSON, asserts match
  - Joiner always becomes local `player_index = 0` (local scoring convention)
  - `RoundNostrRepository.fetchRound(byInitiationEventId:)` for idempotent join (prevents duplicate rounds)
  - `fetchIsMultiDevice()` helper distinguishes single-device vs multi-device rounds for nav logic
  - Live scorecard publish: fires on `advanceHole()` / `retreatHole()` / `requestFinish()` (confirmed scores only)
  - Auto-publish kind 1502 final records on `finishRound()` via `publishFinalRecords()` (fire-and-forget)
  - UserDefaults 1502 dedup: `"1502_event_\(roundId)"` cache prevents duplicate final record publishes
  - RoundDetailView "Post to Nostr" reuses cached 1502 event ID, publishes only kind 1 social note if 1502 already published
  - LiveScorecardSheet shows all player columns from `store.players` (not just those who published)
  - RoundDetailView auto-fetches remote 1502 final records on load for multi-device rounds
  - Invite nevent loading with polling: 5 retries × 2s delay, graceful cancellation on view dismiss
  - 36 new tests in RoundJoinTests, LiveScorecardTests, RemoteFinalRecordTests (196 total)

- **Scoring UX Polish Sprint**
  - Prominent hole number display (48pt bold rounded font, replaces inline navigation title)
  - Navigation haptics: light impact on prev/next, medium on finish
  - Round-robin multiplayer navigation: Next cycles P1 → P2 per hole before advancing to next hole
  - Per-player progress indicator (e.g., "P1: 9/9, P2: 7/9") with finish-gating feedback text
  - End-of-round review scorecard sheet (`RoundReviewView`) replaces simple confirmation alert
  - `isOnFirstPosition`, `playerProgress`, `finishBlockedReason` computed properties on ActiveRoundStore

- **iOS Phase 6D: Multi-Player Scoring**
  - Schema v6: `player_index INTEGER NOT NULL DEFAULT 0 CHECK (player_index >= 0)` on `hole_scores`
  - `ActiveRoundStore`: multi-player state with `switchPlayer(to:)`, per-player scores dict `[Int: [Int: Int]]`
  - `ScoreEntryView`: segmented player picker (multiplayer only), auto-hidden for solo rounds
  - `HoleScoreRepository`: `recordScore`/`fetchLatestScores` accept `playerIndex` (default 0), `fetchAllPlayersLatestScores()` returns grouped dict
  - `listRounds()` filters by `player_index = 0` (rounds list shows creator's score only)
  - NIP-101g: `buildFinalRecordEvent` gains `scoredPlayerPubkey` param — one kind 1502 per player in multiplayer
  - `RoundShareBuilder`: multi-player `noteText`/`summaryText` overloads ("Shot 82/78 at...")
  - Companion kind 1 social note: includes all player scores in multiplayer
  - UX Contract A.11 added (rounds list shows creator score only for multiplayer)
  - 14 new tests (160 total)

- **iOS Phase 6C: Player Model + Initiation Timing**
  - Schema v5: `round_players` table (immutable player roster per round) and `round_nostr` table (initiation event ID storage)
  - `RoundPlayerRepository` and `RoundNostrRepository`: new repositories for player and Nostr metadata
  - Player selection UI in `CreateRoundView`: follow list multi-select + manual npub entry with validation
  - Kind 1501 (round initiation) now published at round creation time (background, fire-and-forget) with all player `p` tags
  - `RoundDetailView` conditional publishing: reuses stored initiation, only publishes kind 1502 + companion kind 1 social note
  - Companion kind 1 social note: includes `nostr:npub1...` mentions for other players and njump.me link to nevent
  - `NostrProfile: Identifiable` conformance for SwiftUI list usage
  - 15 new tests: immutability triggers, repository CRUD, constraint validation (146 total)
  - `DebugView` updated with round_players and round_nostr table counts

- **iOS Phase 6B: Relay Read Infrastructure**
  - One-shot relay reads via `client.fetchEvents()` with EOSE exit policy
  - `fetchFollowList(pubkey:)`: kind 3 query, extracts followed pubkeys from `p` tags (NIP-02)
  - `fetchProfiles(pubkeyHexes:)`: batch kind 0 query, parses display_name/name/picture (NIP-01)
  - `fetchFollowListWithProfiles(pubkey:)`: combined single-connection method (~2s vs ~20s separate)
  - `NostrProfile` struct with `displayLabel` fallback chain (displayName > name > truncated pubkey)
  - `NostrReadError` enum with user-facing error messages
  - Dedicated `readRelays` list (damus.io, nos.lol, purplepag.es) with 5s timeout
  - 14 new tests: 11 unit (profile parsing, display label, edge cases) + 3 live relay integration
  - No schema changes, no kernel changes

- **iOS Phase 6A: NIP-101g Event Builder**
  - Replaced kind 1 plain-text round sharing with structured NIP-101g events
  - Round Initiation (kind 1501): immutable event with embedded course_snapshot + rules_template + hashes
  - Final Round Record (kind 1502): immutable event referencing initiation, per-hole scores, total
  - `NIP101gEventBuilder`: pure transformation from local DB models to Nostr event structures
  - Hash computation uses kernel canonicalization (RAIDCanonicalizer + RAIDHasher) for parity
  - `course_hash = SHA-256(UTF-8(JCS(course_snapshot_json)))`, `rules_hash` same pattern
  - NostrClient.publishEvent: generic EventBuilder publisher that returns event ID for cross-referencing
  - Removed old `publishRoundNote` (kind 1) method
  - 12 new unit tests in `NIP101gEventBuilderTests` including hash parity verification
  - "Copy Summary" (plain text) still uses RoundShareBuilder — unchanged
  - No schema changes, no kernel changes

- **iOS Phase 5.5: UX Contract + Docs**
  - Added `README_USER.md` (user-facing quick start guide for GitHub repo visitors)
  - Added `TESTFLIGHT_NOTES.md` (TestFlight beta tester instructions)
  - Added `AboutView.swift` (in-app about screen with app name, version, tagline, and privacy notes)
  - AboutView accessible via info.circle button on Templates tab (top-right toolbar)
  - Updated `BACKLOG.md` with B-002 (template versioning), B-003 (shot editing), B-004 (course editing)
  - All documentation minimal and production-ready (no legal docs, no FAQs)

- **iOS Phase 5.6: Debug Screen**
  - Read-only diagnostic screen showing kernel facts, scorecard counts, product state, Nostr identity, and build info
  - Accessible via long-press on Templates tab title (debug builds only)
  - All diagnostic data loaded via simple SQL COUNT queries
  - Gated behind `#if DEBUG` — no debug code in release builds

- **iOS Phase 5.2: Nostr Login + Round Sharing**
  - Added rust-nostr-swift (NostrSDK v0.44.2) as Swift Package Manager dependency
  - Auto-generate Nostr keypair on first use, stored securely in iOS Keychain
  - Fire-and-forget kind 1 note publishing from completed round scorecards
  - "Post to Nostr" and "Copy Summary" share actions on `RoundDetailView`
  - `NostrProfileView` sheet with npub display, nsec copy (with confirmation), relay list
  - Profile button on Rounds tab (person.circle icon, top-right)
  - Default relay: wss://relay.damus.io
  - Event tags: `["t","golf"]`, `["t","raidgolf"]`, `["client","raid-golf-ios"]`
  - Round summary format: course name, date, holes, score (with par-relative display), highlights (eagles/birdies/bogeys)
  - 8 new unit tests in `RoundShareBuilderTests` (105 total project tests, 0 failures)
  - No kernel changes, no schema changes

- **iOS Phase 5.4: First-Run Experience**
  - Added one-time welcome sheet (`FirstRunSheetView`) shown on first launch via `@AppStorage("hasSeenFirstRun")`
  - Welcome sheet explains Practice, Rounds, and Templates with 3-card layout
  - Enhanced empty state copy in all 4 tabs (Trends, Sessions, Rounds, Templates)
  - Added action button to Templates empty state for discoverability
  - Added `BACKLOG.md` with B-001 (club name normalization) and TODO markers in code

- **iOS Phase 5.3: Error Handling Polish**
  - Added user-facing error alerts to 9 error sites across 5 files (user-facing flows only)
  - TemplateDetailView: 4 error sites (loadTemplate, setActive, saveDisplayName, toggleHidden) now show alerts
  - ActiveRoundStore: 3 error sites (completeRound, saveScore, loadData) now set errorMessage, displayed via ScoreEntryView alert
  - RoundsView: 1 error site (fetchCourseHash) now shows alert
  - PracticeSummaryView: 1 error site (analyzeClub) now shows alert via separate analyzeError state
  - Error handling pattern: `@State private var errorMessage: String?` + `.alert()` modifier
  - Debug print statements preserved alongside user alerts for development diagnostics
  - All 96 tests pass, build succeeds

- **iOS Phase 5.0: Rebrand to Gambit Golf** (REVERTED 2026-02-15)
  - App display name changed from "RAID" to "Gambit Golf" (iOS app only)
  - Bundle identifier changed from `dev.local.RAID` to `com.gambitgolf.ios`
  - File headers, debug logs, and CFBundleDisplayName all updated to Gambit Golf
  - **REVERTED 2026-02-15:** All branding reverted back to "RAID Golf", bundle ID `dev.local.RAID`, tags `raidgolf`
  - Python kernel and repository names remain as RAID (no changes to backend/kernel layer)
  - All tests passing post-rebrand

- **KPI Template UX Sprint (feature/kpi-template-ux)**
  - Added `template_preferences` table (v4 migration) for mutable template metadata (display names, active/hidden flags)
    - Partial unique index `idx_one_active_per_club` enforces one active template per club
    - FK to `kpi_templates` with RESTRICT on delete
    - No immutability triggers (mutable by design — non-kernel product layer)
  - Added `TemplatePreferencesRepository` with CRUD operations:
    - `setActive(templateHash:club:)`: transactional deactivate-old → activate-new
    - `setHidden(templateHash:hidden:)`, `setDisplayName(templateHash:name:)`
    - `fetchActiveTemplate(forClub:)`: JOIN to kpi_templates for full template record
    - `ensurePreferenceExists(forHash:club:)`: idempotent INSERT OR IGNORE
  - Extended `TemplateRepository` with list methods:
    - `listTemplates(forClub:)`: excludes hidden via LEFT JOIN, ordered by recency
    - `listAllTemplates()`: grouped by club ASC, ordered by created_at DESC
  - Extended `SubsessionRepository` with `fetchSubsessions(forSession:)` read method
  - Added Template Library tab (4th tab in TabView):
    - `TemplateListView`: grouped by club, active badge, metric count, navigation to detail
    - `TemplateDetailView`: full metadata display, rename, set active, hide/unhide, duplicate
    - `CreateTemplateView`: form-based template creation with PK collision handling
  - Added template preference bootstrap: seed templates get preference rows and active flag on first launch
  - Updated import flow: `analyzeImportedSession()` now uses active template with fallback to latest
  - Refactored `PracticeSummaryView` (Session Detail):
    - Reads persisted `club_subsessions` instead of on-the-fly classification
    - Shows multiple analyses per club with template identity (name + hash + ACTIVE badge)
    - "Analyze" button for unanalyzed clubs
  - Added trends template filter:
    - `TemplateFilter` enum: `.all`, `.activeOnly`, `.specific(hash)`
    - In-memory filtering of A-only points; allShots section never filtered
    - Default: activeOnly when active template set, all otherwise
  - 20 new tests across KernelTests and BootstrapTests
  - Total test count: 96

- **iOS Phase 4B v2: Analysis-Context Linkage (A-only trend stability)**
  - A-only trend classification now uses template_hash persisted in `club_subsessions` at analysis time
  - Removed latest-template resolution from A-only query path — historical points are stable
  - Sessions without a `club_subsessions` row are excluded from A-only trends (no silent drift)
  - Added `SubsessionRepository.analyzeSessionClub()`:
    - Creates `club_subsessions` row with full classification aggregates
    - Pins `kpi_template_hash` at analysis time (analysis context linkage)
    - Computes validity status, A/B/C counts, A%, and average metrics for A-shots
    - Idempotent: `UNIQUE(session_id, club, kpi_template_hash)` prevents duplicates
  - Added regression test `testAOnlyTrendStableWhenNewTemplateInserted`:
    - Ingest session + analyze with T1 → insert stricter T2 → re-query A-only
    - Asserts trend points are identical before/after T2 insertion
    - Asserts all points use T1 hash (not T2)
  - Added `testAppendOnlyAnalysis_DifferentTemplateCreatesNewRow`:
    - Proves Kernel Contract invariant 1.4: re-analysis with different template creates new row
    - Asserts different `subsession_id`, different `kpi_template_hash`, original metrics unchanged
  - Updated existing trends test to Phase 4B v2 semantics
  - UI wiring: `analyzeImportedSession` called automatically after CSV import in SessionsView

- **Scorecard v0: Back-9 hole set guardrail**
  - Added hole set validation to `CourseSnapshotRepository.insertCourseSnapshot()`:
    - 9-hole snapshots must be exactly {1..9} (front) or {10..18} (back)
    - 18-hole snapshots must be exactly {1..18}
    - Malformed sets (e.g., {1..8, 10}) rejected with `invalidHoleSet` error
    - No schema change; validation is code-level in repository
  - Added 2 tests:
    - `testBack9SnapshotInsertsExactlyNineHolesStartingAt10`: back-9 stores holes 10-18
    - `testMalformedNineHoleSetRejected`: {1..8, 10} rejected; asserts transactional rollback (no snapshots, no holes)

- **Hard Stop: UX Contract**
  - Created `docs/private/UX_CONTRACT.md` declaring locked analytical semantics, deferred non-decisions, and free-to-iterate areas
  - 73 unit/integration tests at time of hard stop

- **iOS Scorecard v0 Bugfix Sprint (feature/scorecard-v0)**
  - Added `ActiveRoundStore` view model pattern for long-lived scoring state
    - Owned by `RoundsView` via `@State`, passed to `ScoreEntryView`
    - ScoreEntryView becomes thin render shell over store
    - State survives view recreation and navigation
  - Added finish confirmation dialog ("Are you sure you want to end your round?")
  - Added Front 9 / Back 9 / 18 hole picker in CreateRoundView
    - Front 9: holes 1-9
    - Back 9: holes 10-18
    - 18: all holes
  - Added 4 regression tests in ScorecardTests.swift (31 scorecard tests total, ~69 project-wide)
    - Nested-read safety test
    - Default-value persistence test
    - Last-hole finish eligibility test
  - Fixed Issue B (EXC_BREAKPOINT crash): Restructured `RoundDetailView.loadData()` to use sequential non-nested reads
    - GRDB precondition failure: "Database methods are not reentrant"
    - Replaced nested `dbQueue.read` with sequential repo calls
  - Fixed Issue A (default par persistence): Removed `guard let` check in `saveCurrentScore()`
    - Now always persists displayed value (falls back to par if user didn't adjust)
    - Previously skipped persistence when user didn't change from default
  - Fixed last-hole finish bug: Added `ensureCurrentHoleHasDefault()` pattern
    - Populates default par in memory when arriving at each hole
    - Finish button now works on last hole
  - **Pattern learned:** Never nest `dbQueue.read` calls in GRDB
  - **Pattern learned:** Always persist displayed values, even defaults
  - **Pattern learned:** Use `@Observable` class at parent level for stateful flows that must survive view recreation

- **iOS Phase 4A.2: Golden aggregate parity fixture lock-in**
  - Added deterministic Python golden generator:
    - `tools/scripts/generate_aggregate_parity_golden.py`
  - Added golden artifact (source of parity truth):
    - `tests/vectors/goldens/aggregate_parity_mixed_club_sample.json`
  - Added RAIDTests bundle copy for iOS runtime parity checks:
    - `ios/RAID/RAIDTests/aggregate_parity_mixed_club_sample.json`
  - Added iOS parity integration coverage in `IngestIntegrationTests`:
    - per-club `total_shots` parity
    - per-club metric `count` + `sum` parity for `carry`, `ball_speed`, `smash_factor`, `spin_rate`, `descent_angle`
    - 7i-only classification parity (`A/B/C`) using `fixture_a.json`
    - template hash parity assertion for fixture_a (`96bf2f0d...`)
  - Numeric policy locked for parity comparisons:
    - fixed rounding to 6 decimals
    - sums serialized and compared as fixed-decimal strings
  - Scope explicitly template-scoped for this vector:
    - 7i classified
    - 5i aggregate-only

- **iOS Phase 4C: CSV Import + Sessions List + Empty States**
  - Template bootstrap: bundled `template_seeds.json` with v2.0 7i template (4 metrics)
    - Idempotent: PK constraint prevents duplicate inserts
    - Async: runs via `.task` modifier, non-blocking, non-fatal errors
    - Seed inserted via `TemplateRepository.insertTemplate(rawJSON:)` (kernel-safe)
  - Expanded `ShotRepository.insertShots` to store all 14 normalized metric columns
    - Previously only `carry` and `ball_speed` were stored; classification needs `smash_factor`, `spin_rate`, `descent_angle`
    - Added `ShotInsertData` struct replacing tuple parameter
  - Updated `RapsodoIngest` and `ParsedShot` to pass all parsed metrics through to INSERT
  - Added `SessionRepository.listSessions()`: single grouped SQL query with shot count (no N+1)
  - Added `SessionRepository.sessionCount()`: for empty-state checks
  - Added `SessionListItem` struct (session + shotCount)
  - TabView navigation: Trends tab + Sessions tab in `ContentView`
  - `SessionsView`: sessions list (newest first, date + source file + shot count)
    - Import CSV via `fileImporter` with security-scoped URL handling
    - Import result alert (imported/skipped counts)
    - Empty state: `ContentUnavailableView` with import button
  - `TrendsView`: empty state keyed on `sessions.count == 0` (not trend results)
  - Tests:
    - `testTemplateBootstrapIsIdempotent`: insert twice, count unchanged
    - `testSeedTemplateDecodesAsKPITemplate`: insert seed → fetch → decode → verify all 4 metrics

- **iOS Phase 4B: Trends v1 (tests-first)**
  - Added `TrendsRepository` and trends domain model in `ios/RAID/RAID/Kernel/Repository.swift`
    - `TrendPoint` unit is per session
    - deterministic ordering: `session_date ASC, session_id ASC`
  - Implemented `allShots` series via SQL-only aggregation:
    - `AVG(metric)` and `COUNT(metric)` (non-null aligned), grouped by session
  - Implemented `aOnly` series in Swift (no schema changes):
    - deterministic template resolution: latest template for club at query time
    - deterministic shot classification order: `source_row_index ASC`
    - every A-only trend point includes non-null `templateHash`
  - Added integration coverage in `ios/RAID/RAIDTests/IngestIntegrationTests.swift`:
    - two deterministic sessions with fixed `session_date`
    - validates point count, ordering, repeat-run determinism
    - validates `aOnly.nShots` equals A-with-metric count
    - validates non-null, stable `templateHash` on A-only points
  - Added minimal UI in `ios/RAID/RAID/Views/TrendsView.swift`
    - default: 7i + carry
    - list/table presentation for allShots and A-only

### Notes

- **Phase 4B v2 semantics (final):** A-only trends read persisted `club_subsessions` aggregates (A/B/C counts, A%, averages) pinned at analysis time via `kpi_template_hash`. No recomputation occurs on the read path. Recomputation only happens via explicit analysis actions (import auto-analyze or manual re-analyze button). Historical points are stable — inserting a new template does not change existing classifications.

---

## [iOS Phase 4A] - 2026-02-06

### Added - Data Confidence Harness (Complete)

**RAIDTests/IngestIntegrationTests.swift**
- End-to-end ingest integration test (CSV → persisted shots)
  - Verifies import counts (15 shots imported, 0 skipped)
  - Validates `source_row_index` uniqueness and sequencing (0..14)
  - Confirms FK integrity (shots → session)
- Classification + aggregation determinism test
  - Template-driven classification (7i template: `96bf2f0d...`)
  - Deterministic results: A=5, B=0, C=1 (A%=83.33%)
  - Repeated runs produce identical outputs
  - Fresh DB ingest produces identical A%
- Shot immutability guardrail test
  - UPDATE rejected: "Shots are immutable after creation"
  - DELETE rejected: "Shots are immutable after creation"
  - No silent mutation possible

**docs/Data_Confidence_Report.md**
- Documents Phase 4A validation coverage
- Defines authoritative `source_row_index` semantics (0-based ingested shot index)
- Explicitly states what is/isn't asserted (golden aggregates deferred to Phase 4A.2)
- Exit criteria checklist for Phase 4A completion

**docs/private/ios-port-plan.md**
- Updated to reflect Phase 4A as completed milestone
- Clarified phase naming (iOS port phases vs. product phases)
- Set Phase 4A as current resume point

### Test Results
- ✅ All 34 tests passing (3 integration + 31 kernel tests)
- ✅ JCS canonicalization vectors (12/12)
- ✅ Template hash fixtures (3/3)
- ✅ Immutability enforcement (sessions, templates, subsessions, shots)
- ✅ Repository hash-once tests (RTM-04)
- ✅ Deterministic end-to-end pipeline verified

### Notes
- No UI or trend analysis in this phase (tests only)
- Golden aggregate fixtures deferred to Phase 4A.2
- Kernel invariants remain frozen

---

## [iOS Phase 2.4] - 2026-02-06

### Added - iOS Repository Layer (RTM-04 Compliance)

**Kernel/Protocols.swift**
- `Canonicalizing` protocol for canonical JSON transformation
- `Hashing` protocol for SHA-256 hashing
- Production implementations: `RAIDCanonicalizer`, `RAIDHasher`
- Enables behavioral testing via dependency injection (no global DEBUG counters)

**Kernel/Repository.swift**
- `DatabaseQueue.createRAIDDatabase()` factory with explicit FK enforcement
- `TemplateRepository`: Insert (computes hash once), Fetch (never recomputes)
  - Repository owns canonicalization + hashing (callers provide raw JSON `Data`)
  - Read path returns stored hash directly (RTM-04: never calls canonicalize/hash)
- `SessionRepository`: Insert/fetch sessions
- `ShotRepository`: Batch insert/fetch shots

**RAIDTests/KernelTests.swift**
- `testInsertTemplateComputesHashOnce`: Verifies exactly 1 canonicalize + 1 hash call during insert
- `testFetchTemplateNeverRecomputesHash`: Verifies 0 calls during fetch (RTM-04 compliance)
- Test spies: `SpyCanonicalizer`, `SpyHasher` count calls without polluting production code

### Changed
- Repository interfaces are now **FROZEN** — treat method signatures as semi-public kernel API

### Test Results
- ✅ All 31 tests passing (29 existing + 2 repository tests)
- ✅ Swift hashes match Python hashes exactly
- ✅ RTM-04 verified: Read path never calls canonicalize/hash

---

## [iOS Phase 2.3 + 2.3b] - 2026-02-06
**iOS Port — Phase 2.3 + 2.3b: Schema, Immutability, and Shot Persistence (2026-02-06)**
- **Phase 2.3b: Shots Table**
- Added `shots` table as separate migration (`v2_add_shots`)
  - Shot-level fact table with FK to sessions
  - Provenance: source_row_index, source_format (versioned), imported_at, raw_json
  - Normalized columns: 14 MLM2Pro metrics (carry, ball_speed, spin_rate, etc.) as nullable REALs
  - UNIQUE(session_id, source_row_index) prevents duplicate shot import
  - Immutability triggers: BEFORE UPDATE/DELETE → ABORT
- Refactored Schema.swift to use GRDB DatabaseMigrator
  - `v1_create_schema`: sessions, kpi_templates, club_subsessions, projections
  - `v2_add_shots`: shots table (separate auditable migration)
  - Migration names are stable and never renamed (kernel discipline)
- Added 5 shot immutability/FK tests (all passing):
  - testShotInsertSucceeds: Insert with FK to session
  - testShotUpdateRejected: UPDATE blocked by trigger
  - testShotDeleteRejected: DELETE blocked by trigger
  - testShotFKEnforced: Invalid session_id rejected
  - testShotDuplicateRowIndexRejected: UNIQUE constraint enforced
- All 29 Phase 2.3 + 2.3b tests passing:
  - 12 JCS canonicalization vectors
  - 3 template hash fixtures
  - 10 immutability tests (sessions/templates/subsessions)
  - 5 shot tests (insert, update/delete rejection, FK enforcement, duplicate rejection)
- **Note**: 2 Phase 2.4 tests intentionally fail as TODO placeholders:
  - `testInsertTemplateComputesHashOnce` — Repository insert path (Phase 2.4)
  - `testFetchTemplateNeverRecomputesHash` — Repository read path (Phase 2.4)

- **Phase 2.3: Schema + Immutability**
- Implemented SQLite schema in Swift (Schema.swift) with GRDB
  - sessions, kpi_templates, club_subsessions tables with full CHECK constraints
  - Immutability triggers: BEFORE UPDATE and BEFORE DELETE → ABORT on all 3 authoritative tables
  - Foreign keys enforced per connection (PRAGMA foreign_keys = ON)
- Added 10 immutability tests in KernelTests.swift (all passing):
  - Sessions: UPDATE rejected, DELETE rejected, all fields protected (RTM-01)
  - Templates: UPDATE rejected, DELETE rejected (RTM-03)
  - Subsessions: UPDATE rejected, DELETE rejected, template swap rejected (RTM-02)
- Schema matches Python `raid/schema.sql` structure (parity achieved)
- Phase 2.4 repository tests remain as TODO placeholders (2 expected failures)

**iOS Port — Phase 2.2: Template Hash Fixtures (2026-02-05)**
- Implemented `RAIDHashing.computeTemplateHash()` in Swift using CryptoKit SHA-256
- Cross-platform template identity verified: all 3 Swift hashes match Python golden fixtures exactly
  - fixture_a: `96bf2f0d9540211669916f580aaec0ac26d1a14e8d2fdd35cee2172595f86698`
  - fixture_b: `b23b186c3af4fc21bb78dd6645f8b040e947e561f4a131cb5c0de02708ffbcbb`
  - fixture_c: `1fc0d89d5a530069631b13ffdd9d21622d5cf2b2f0291cca743f1646351643e1`
- Added template hash fixture tests (3/3 passing)
- Template hashing uses RAID canonical JSON v1 (Phase 2.1 dependency)
- Kernel parity achieved: Swift and Python produce identical template hashes

**iOS Port — Phase 2.1: Canonical JSON Implementation (2026-02-05)**
- Implemented `RAIDCanonical` struct matching Python `canonicaljson` behavior
  - UTF-16 lexicographic key ordering (matches RFC 8785 and Python default)
  - Deterministic number handling (int vs decimal, negative zero preservation)
  - CFBoolean detection for true JSON booleans vs numeric 0/1
  - Compact JSON output (no whitespace), UTF-8 without BOM
- Added comprehensive JCS vector test coverage (12/12 passing)
  - All vectors validated byte-for-byte against Python reference
  - SHA-256 hash verification for each vector
  - Special test harness handling for negative zero edge case
  - Test vectors loaded from bundle resource (`jcs_vectors.json`)
- **Note**: This implementation matches Python `canonicaljson` library, not strict RFC 8785
  - Preserves negative zero (`-0.0`) instead of normalizing to `0`
  - Intentional deviation to maintain frozen kernel hashes
  - See backlog item for potential Kernel v3 migration to strict RFC 8785

**iOS Port — Phase 1: Project Setup (2026-02-05)**
- Created iOS project (SwiftUI) at `ios/RAID/`
- Added GRDB 6.x via Swift Package Manager
- Created folder structure: Kernel/, Models/, Ingest/, Views/
- Created XCTest target (RAIDTests) with kernel test harness
- All placeholder files compile successfully
- App runs and displays "Phase 1 Setup Complete" UI
- Test vectors at `../tests/vectors/` accessible from Swift tests

- Phase 0.2 real-data validation of the 7-iron v2 template (Kernel v2)
  - Added validation script: `scripts/validate_7i_v2.py`
  - Added validation report: `data/summaries/phase02_validation_report.md`
  - Documented Phase 0 schema limitation for B/C threshold gaps in template design docs

**Kernel v2.0: RFC 8785 JCS Template Canonicalization (BREAKING)**
- **BREAKING CHANGE**: Template identity now uses RFC 8785 JSON Canonicalization Scheme (JCS)
  - Formula: `template_hash = SHA-256(UTF-8(JCS(template_json)))`
  - Replaces custom Decimal-based canonicalization (v1.0)
  - Enables true cross-platform interoperability (Python ↔ Swift ↔ JavaScript)
- Added RFC 8785 JCS implementation via `canonicaljson==2.0.0` library
- Added interop artifacts for cross-platform verification:
  - `tests/vectors/jcs_vectors.json` — 12 RFC 8785 compliance test vectors
  - `docs/specs/jcs_hashing.md` — Normative spec for non-Python implementers
- Added kernel governance documentation:
  - `docs/private/kernel/KERNEL_FREEZE_v2.md` — Kernel v2.0 freeze declaration
  - `docs/private/kernel/KERNEL_CONTRACT_v2.md` — Authoritative kernel contract (v1 preserved)
  - `docs/private/kernel/changes/2026-02-02_rationale_rfc8785_jcs.md` — Change rationale
- Updated schema brief documentation for RFC 8785:
  - `docs/schema_brief/00_index.md` — Points to Kernel v2.0
  - `docs/schema_brief/05_canonical_json_hashing.md` — RFC 8785 specification
- Regenerated all golden template hashes under JCS
- Replaced v1 Decimal-specific tests with JCS compliance tests
- **Migration**: No production data exists; no migration required
- **Note**: v1.0 template hashes are incompatible with v2.0 (breaking change)

### Fixed
- Fixed DeprecationWarning in `raid/projections.py` (replaced `datetime.utcnow()` with timezone-aware UTC)

### Added
- Adopted structured folders (`docs/`, `data/`, `tools/`) for canonical, raw, and working artifacts
- Added `.clinerules` to enforce RAID Phase 0 constraints for AI-assisted development
- Added Phase 0 PRD (`docs/PRD_Phase_0_MVP.md`) as the authoritative MVP requirements
- Added schema-first implementation brief (`docs/schema_brief/*`) documenting Phase 0 invariants
- Added KPI philosophy and classification guide (`docs/kpi_philosophy_and_classification.md`)
- Added `docs/reference_test_matrix.md` to map high-risk Phase 0 invariants to test scenarios
- Added `data/session_logs/README.md` to enforce raw-export rules
- Added KPI version propagation to session summaries (`kpi_version`) from `tools/kpis.json`
- Documented versioning contract across practice system docs, KPIs, spreadsheets, and derived summaries
- Added forward-only KPI generator with provenance/versioning for KPIs
- Confirmed no behavior changes to `tools/scripts/analyze_session.py`

**Phase A–B: Canonical Identity + Schema-Level Immutability**
- Implemented deterministic canonical JSON transformation (`raid/canonical.py`)
  - Alphabetically sorted keys at all nesting levels
  - Decimal-based numeric normalization (no binary floats)
  - `NumericToken` wrapper ensures correct JSON emission (strings quoted, numbers unquoted)
  - Compact UTF-8 format without BOM
- Implemented SHA-256 content-addressed hashing (`raid/hashing.py`)
  - Golden hashes frozen for test fixtures (Phase A proof)
  - Cross-platform deterministic via Decimal
- Implemented SQLite schema with immutability enforcement (`raid/schema.sql`)
  - Three authoritative tables: `sessions`, `kpi_templates`, `club_subsessions`
  - Immutability enforced via BEFORE UPDATE triggers that ABORT
  - Foreign keys enabled per connection with RESTRICT on deletes
- Implemented repository layer (`raid/repository.py`)
  - Insert and read operations for all authoritative entities
  - Read path does NOT call `canonicalize()` or `compute_template_hash()` (RTM-04)
  - Hardened schema validation (fails loudly on partial schema)
- Validated RTM-01 through RTM-04 with comprehensive tests
  - RTM-01: Sessions immutable after creation
  - RTM-02: Club sub-sessions immutable after creation
  - RTM-03: KPI templates immutable forever
  - RTM-04: Hash not recomputed on read (proven via monkeypatch/spy tests)
- Identity and storage layers now stable
- Added `docs/implementation_phases.md` as a non-authoritative execution roadmap
  - Maps Phase 0 work into six sequential phases (A–F)
  - Each phase groups related RTMs with clear entry/exit criteria and STOP conditions
  - Provides safe stopping points and reduces scope creep
  - Serves as onboarding context for contributors and AI agents

**Phase C: Analysis Semantics**
- Validated RTM-05 and RTM-06 with comprehensive tests
  - RTM-05: Duplicate analysis prevented via UNIQUE constraint on (session_id, club, kpi_template_hash)
  - RTM-06: Re-analysis with different template creates new sub-session (original preserved)
- Implemented `tests/unit/test_analysis_semantics.py` with 8 test cases
  - Duplicate prevention validated
  - Re-analysis behavior confirmed
  - Multiple template versions per session/club supported
  - Immutability preserved across re-analysis scenarios
- No schema or code changes required (constraint already in place)
- All 48 unit tests passing (Phase A, B, C)

**Phase D: Validity & Transparency**
- Implemented validity computation with fixed Phase 0 thresholds
  - invalid: shot_count < 5
  - warning: 5 ≤ shot_count < 15
  - valid: shot_count ≥ 15
- Added `raid/validity.py` for validity status + A% computation
- Added `tests/unit/test_validity_transparency.py` covering RTM-07 to RTM-10
  - Boundary tests at 4, 5, 14, 15 shots
  - A% NULL enforcement when invalid
  - Low/invalid persistence guarantees
  - Explicit filtering semantics for validity visibility
- Added explicit repository filter: `list_subsessions_by_club(min_validity=...)`
- All 60 unit tests passing (Phase A–D)

**Phase E: Derived Data Boundary**
- Implemented projection generation and serialization (`raid/projections.py`)
  - Projections are regenerable JSON exports derived from authoritative SQLite data
  - Deterministic serialization (sorted keys, compact format)
  - `ProjectionImportError` raised when import is attempted
- Added projection cache methods to repository (`raid/repository.py`)
  - `upsert_projection()`, `get_projection()`, `delete_projection()`, `delete_all_projections()`
  - Optional cache for performance only (projections table)
- Added comprehensive boundary tests (`tests/unit/test_derived_boundary.py`) for RTM-15 and RTM-16
  - RTM-15: Projection regeneration produces identical analytical results (only `generated_at` differs)
  - RTM-15: Import attempts fail with explicit error and do not modify authoritative data
  - RTM-16: No FK dependencies from authoritative tables to projections
  - RTM-16: Authoritative reads work after all projection rows deleted
  - RTM-16: Projection deletion does not affect authoritative data integrity
- All 67 unit tests passing (Phase A–E)
- Schema unchanged (existing `projections` table design already correct)

**Phase F: Multi-Club CSV Ingest**
- Implemented Rapsodo MLM2Pro CSV ingest (`raid/ingest.py`)
  - Multi-club session support: one session, multiple club sub-sessions
  - Header detection (searches rows 1–3 for required columns)
  - Footer row exclusion (Average, Std. Dev. rows skipped)
  - Club normalization (lowercase, trimmed)
  - Shot classification using worst_metric aggregation
  - Validity computation and A% calculation per club
  - Average metrics (carry, ball speed, spin, descent) computed per club
- Added real-export-derived test fixture (`tests/vectors/sessions/rapsodo_mlm2pro_mixed_club_sample.csv`)
  - 7i (6 shots) and 5i (9 shots) from real MLM2Pro export
  - Footer rows added to prove skip logic
  - Exact schema/formatting preserved from real export
- Added comprehensive RTM-17 tests (`tests/unit/test_multiclub_ingest.py`)
  - One session created for mixed-club CSV
  - One sub-session per club, all sharing same session_id
  - Shot counts exclude footer rows
  - A/B/C classification per club with club-specific templates
  - Validity status and A% computed correctly
  - Club name normalization validated
  - Template hash references correct and immutable
  - Average metrics computed for each club
- All 77 unit tests passing (Phase A–F)
- **Phase 0 MVP complete**: All RTM-01 through RTM-17 validated
- No schema changes required

**Phase 0.1: CLI + Results & Trends**
- Added command-line interface (`raid/cli.py`)
  - `templates load` - Load KPI templates from tools/kpis.json
  - `templates list` - List all stored templates
  - `ingest <csv>` - Ingest Rapsodo CSV files
  - `sessions` - List all sessions
  - `show <id>` - Show session details (clubs, A/B/C counts, averages)
  - `trend <club>` - Show A% trend over time for a club
  - `export <id>` - Export session projections as JSON
- Added template loader (`raid/templates_loader.py`)
  - Loads KPI templates from tools/kpis.json into database
  - Content-addressed hashing (templates hashed once at insert)
  - Idempotent (no-op if template already exists)
  - Kernel-safe (insert-only, no mutations)
- Added trend analysis (`raid/trends.py`)
  - Computes A% trends using subsession aggregates only
  - Shot-weighted average A% computation
  - Explicit validity filtering (min_validity parameter)
  - Optional rolling window (last N sessions)
  - Derived projections (regenerable from authoritative data)
- Extended repository with read-only methods
  - `list_sessions()` - List all sessions (newest first)
  - `list_template_clubs()` - List distinct clubs with templates
- Removed hardcoded "7i" assumptions from CLI
  - Template loading and listing now query database for all clubs
  - Ingest automatically uses templates for all clubs in database
- Added smoke test script (`scripts/smoke_phase01.sh`)
  - End-to-end CLI workflow validation
  - Tests template load idempotency
  - Tests duplicate ingest behavior (creates new session)
- Added CLI help regression test (`tests/unit/test_cli_help.py`)
  - Prevents argparse % escaping crashes
  - Validates all help commands render without errors
- No schema changes
- No modifications to Phase 0 kernel invariants
- SQLite remains authoritative, JSON is export-only
- All trends are query-only derived projections

### Planned
- Validation of 5-iron and 6-iron KPIs
- Potential minor clarifications to pressure blocks
- Optional visualization guidance (non-canonical)

---

## Versioning Policy
- **Minor versions (v2.x):** wording clarity, scheduling notes
- **Major versions (v3.0):** KPI logic, lane structure, evaluation rules

Historical data is never reinterpreted under new versions.
