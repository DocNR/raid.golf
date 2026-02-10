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

### Model Gotchas
- `RoundListItem` does NOT include `courseHash` field (it's joined from rounds table)
- To get courseHash: query directly with `SELECT course_hash FROM rounds WHERE round_id = ?`
- RoundRepository doesn't have `fetchRound(byId:)` — use `listRounds().first(where:)` or direct SQL

### Repository APIs
- All repositories use kernel pattern: Insert types for writes, Record types for reads
- CourseSnapshotRepository: content-addressed (canonicalize + hash on insert)
- RoundRepository: immutable rows, completion via events table
- HoleScoreRepository: append-only, latest-wins for corrections

## File Organization
- Views go in `/Users/danielwyler/raid.golf/ios/RAID/RAID/Views/`
- Blue folder references: files in directory tree are auto-included in Xcode
- Import order: `import SwiftUI` then `import GRDB`
- No `@testable` imports in production code
