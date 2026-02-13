# Feature Builder Memory

## View Patterns (SwiftUI + GRDB)

### Standard View Structure
- Views receive `dbQueue: DatabaseQueue` via init parameter (no global singleton)
- Use `@State` for view-local data (e.g., `@State private var rounds: [RoundListItem] = []`)
- Use `.task { loadData() }` for async loading (NOT `onAppear`)
- Error handling: print to console with `[RAID]` prefix, no alerts for load errors
- Date formatting: `ISO8601DateFormatter` for parsing, `DateFormatter` for display

### List View Pattern (see SessionsView.swift)
- NavigationStack wrapper
- Empty state: `ContentUnavailableView` with label, description, actions
- List view: iterate over items, show detail rows
- Toolbar: `ToolbarItem(placement: .primaryAction)` for primary action button
- Load data in `.task { }` block
- Add `.refreshable { }` to list for pull-to-refresh

### Form/Sheet Pattern
- Use `@Environment(\.dismiss) private var dismiss` for dismissal
- Form with sections for grouping
- Toolbar items for Cancel/Save actions
- Pass completion callbacks from parent view

### Navigation
- Use `NavigationStack` with `@State private var navigationTarget: NavigationTarget?`
- Define private enum NavigationTarget: Identifiable, Hashable for type-safe navigation
- Use `.navigationDestination(item: $navigationTarget)` for programmatic navigation

## Scorecard Domain

### Repository Files
- `/Users/danielwyler/raid.golf/ios/RAID/RAID/Scorecard/ScorecardRepository.swift` - all three repositories
- `/Users/danielwyler/raid.golf/ios/RAID/RAID/Scorecard/ScorecardModels.swift` - all model types

## KPI Template Preferences Domain

### Repository Files
- `/Users/danielwyler/raid.golf/ios/RAID/RAID/Kernel/TemplatePreferencesRepository.swift` - mutable preference layer
- Pattern: NOT a kernel repository (operates on mutable `template_preferences` table)

### Key Methods
- `setActive(templateHash:club:)` - transactional activation (deactivates others, activates target)
- `fetchActiveTemplate(forClub:)` - JOINs to kpi_templates, returns TemplateRecord
- `ensurePreferenceExists(forHash:club:)` - INSERT OR IGNORE with defaults (idempotent)
- `setDisplayName/setHidden` - standard UPDATE operations

### Kernel Extensions (Task 2)
- `TemplateRecord` now includes `importedAt: String?` field
- `TemplateRepository.listTemplates(forClub:)` - list non-hidden templates for club, ordered by recency
- `TemplateRepository.listAllTemplates()` - list all non-hidden templates, grouped by club ASC
- `SubsessionRecord` struct - full subsession data with all aggregates
- `SubsessionRepository.fetchSubsessions(forSession:)` - list subsessions ordered by club ASC, analyzed_at DESC

### Bootstrap Pattern (Task 5)
- Location: `/Users/danielwyler/raid.golf/ios/RAID/RAID/RAIDApp.swift`
- Bootstrap runs async (`.task` on ContentView) with `.utility` priority
- Template seeds loaded via `TemplateBootstrap.loadSeeds(into:)`
- After template insert, immediately create preference row and set active if first for club
- Pattern: idempotent (PK constraint + INSERT OR IGNORE), non-fatal (try-catch per seed)
- Preference bootstrap uses `ensurePreferenceExists` + `fetchActiveTemplate` + `setActive`

### Model Gotchas
- `RoundListItem` does NOT include `courseHash` field (it's joined from rounds table)
- To get courseHash: query directly with `SELECT course_hash FROM rounds WHERE round_id = ?`
- RoundRepository doesn't have `fetchRound(byId:)` — use `listRounds().first(where:)` or direct SQL
- When testing nullable aggregates (e.g., `aPercentage: Double?`, `avgCarry: Double?`), use `try XCTUnwrap()` before `XCTAssertEqual(..., accuracy:)` since accuracy parameter requires non-optional Double
- **GRDB pattern:** Never fetch preferences in a loop inside a single `dbQueue.read {}` block. Instead, fetch templates once, then iterate with separate reads for each preference. This avoids nested read transactions.
- **Template decoding:** Use `Data(templateRecord.canonicalJSON.utf8)` then `JSONDecoder().decode(KPITemplate.self, from: canonicalData)` - there is no `decodeTemplate()` method on TemplateRecord

### Repository APIs
- All repositories use kernel pattern: Insert types for writes, Record types for reads
- CourseSnapshotRepository: content-addressed (canonicalize + hash on insert)
- RoundRepository: immutable rows, completion via events table
- HoleScoreRepository: append-only, latest-wins for corrections

### Template List/Detail Views (Tasks 3+4+6)
- **Template display name logic:** preference.displayName (if non-empty) else "\(club) \(hash[:8])"
- **Preference row creation:** Must call `ensurePreferenceExists(forHash:club:)` before any UPDATE operations (INSERT OR IGNORE pattern)
- **Active template alert:** "Used for new imports only. Past sessions are not affected."
- **Metric formatting:** snake_case → Title Case (split on underscore, capitalize each word)
- **Direction icons:** higherIsBetter → arrow.up, lowerIsBetter → arrow.down
- **List grouping:** Templates come pre-sorted by club ASC from `listAllTemplates()`, use Dictionary(grouping:) to group by club
- **Sheet pattern for rename:** Use `@State private var isRenaming = false` + `.sheet(isPresented:)` + NavigationStack wrapper
- **Action confirmation:** Use `.alert()` for destructive/significant actions like "Set Active"
- **Create template flow (Task 6):**
  - Use `insertTemplate(rawJSON:)` - repository owns canonicalization + hashing
  - PK collision (SQLITE_CONSTRAINT) → user-friendly message about identical thresholds
  - After insert: create preference row, set display name if provided, set as active
  - Duplicate mode: pre-fill club + metrics from source, leave display name empty
  - Form validation: computed `isValid` property, disable Save button when invalid
  - Dynamic metric list: `EditableMetric` with UUID id, use `firstIndex(where:)` for bindings

### Import + Session Detail (Tasks 7+8)
- **Import flow wiring (Task 7):** Use `TemplatePreferencesRepository.fetchActiveTemplate(forClub:)` with fallback to `fetchLatestTemplate(forClub:)` in `analyzeImportedSession()`
- **Session detail refactor (Task 8):**
  - Display persisted `club_subsessions` data (no on-the-fly classification)
  - Multiple analyses per club possible (different templates = multiple cards)
  - Show "ACTIVE" badge for analyses using currently-active template
  - Unanalyzed clubs show "Not yet analyzed" + "Analyze" button
  - Re-analysis creates NEW `club_subsessions` row (append-only semantic)
  - Use `SubsessionRepository.fetchSubsessions(forSession:)` for persisted data
  - NavigationLink from SessionsView session list → PracticeSummaryView

### Trends Template Filter (Task 9)
- **Location:** `/Users/danielwyler/raid.golf/ios/RAID/RAID/Views/TrendsView.swift`
- **Filter pattern:** `TemplateFilter` enum with `.all`, `.activeOnly`, `.specific(String)` cases
- **Filter scope:** Only A-only section is filtered; allShots section never filtered (has no template concept)
- **Default behavior:** Defaults to `.activeOnly` when active template exists, `.all` otherwise
- **Preference fetching:** Sequential reads after fetching trend points (avoids nested read transactions)
- **Display names:** Use preference.displayName if non-empty, else hash.prefix(8)
- **State management:** Filter resets when club or metric changes (loadTrends resets state)
- **Computed properties:** filteredAOnlyPoints, distinctTemplateHashes, templateDisplayName helper

### Test Patterns (Task 10)
- **SubsessionRepository.analyzeSessionClub** requires full parameters: `sessionId`, `club`, `shots`, `template`, `templateHash`
- Must fetch shots via `ShotRepository.fetchShots(forSession:)`
- Must decode template from TemplateRecord: `Data(record.canonicalJSON.utf8)` → `JSONDecoder().decode(KPITemplate.self, from:)`
- Template JSON must include valid KPI structure with `aggregation_method`, `club`, `metrics`, `schema_version`
- Use 64-char hex template hashes (e.g., `"a" + String(repeating: "1", count: 63)`)
- Avoid duplicate variable names in same scope (use `shotRepo2`, `templateRepo2` if needed)

## Debug Screen (Phase 5.6)
- **Location:** `/Users/danielwyler/raid.golf/ios/RAID/RAID/Views/DebugView.swift`
- **Access:** Long-press on "Templates" title in TemplateListView (4th tab)
- **Gating:** Entire DebugView wrapped in `#if DEBUG` — no debug code in release builds
- **Data loading:** Single `dbQueue.read` block with COUNT queries for all tables
- **DB file size:** Get from FileManager attributes of `ApplicationSupport/raid_ios.sqlite`
- **Nostr identity:** Use `KeyManager.loadOrCreate()` + `publicKeyBech32()` + `toHex()` methods
- **Build info:** Use `Bundle.main.object(forInfoDictionaryKey:)` for version/build number
- **Pattern:** Read-only diagnostics, no write operations, no separate repository file
- **Long-press gesture:** Added to `.toolbar` with `.principal` placement in TemplateListView

## File Organization
- Views go in `/Users/danielwyler/raid.golf/ios/RAID/RAID/Views/`
- Blue folder references: files in directory tree are auto-included in Xcode
- Import order: `import SwiftUI` then `import GRDB`
- No `@testable` imports in production code
