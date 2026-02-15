# Gambit Golf — Backlog

Known issues and deferred improvements, roughly prioritized.

## B-001: Club Name Normalization

**Priority:** Medium (post-Milestone 1)
**Area:** Ingest, Templates, Analysis

Club-to-template matching is an exact, case-sensitive string comparison.
Different data sources (or even different Rapsodo firmware versions) may emit
different representations of the same club:

| Equivalent names | Current behavior |
|---|---|
| `7i`, `7 Iron`, `7-iron`, `7I` | Treated as four separate clubs |

### Impact
- Templates created for `7i` won't match shots imported as `7 Iron`.
- Trends and analysis silently miss data from the "other" spelling.
- Within a single Rapsodo setup this is mitigated by the club Picker, which
  sources its list from previously imported shot data.

### Proposed fix
Add a club alias / canonical-name mapping layer:
1. Canonical club names table (`canonical_clubs`) with aliases.
2. Normalize on ingest (`RapsodoIngest.parseShot`) — map raw name → canonical.
3. Template and analysis lookups already use exact match, so normalization at
   ingest time is sufficient.

### Code pointers
- `ios/RAID/RAID/Ingest/RapsodoIngest.swift` — `parseShot()` (raw club name)
- `ios/RAID/RAID/Views/CreateTemplateView.swift` — `loadClubChoices()` (picker)
- `ios/RAID/RAID/Views/SessionsView.swift` — `analyzeImportedSession()` (exact match lookup)

---

## B-002: Template Versioning

**Priority:** Low (post-Milestone 1)
**Area:** Templates, Analysis

Adding or removing a metric from a template creates a new `template_hash`.
Existing `club_subsessions` rows referencing the old hash remain unchanged.
There is no migration or "upgrade" path from one template version to another.

### Impact
- Historical analyses remain pinned to the template version used at the time.
- Re-analysis with a new template creates a new `club_subsessions` row.
- Users may accumulate multiple template versions for the same club.

### Proposed fix
- Add template lifecycle UI: mark templates as deprecated, show lineage
- Optionally allow re-analysis of all sessions with a new template (batch operation)

---

## B-003: Shot Editing

**Priority:** Low (post-Milestone 1)
**Area:** Ingest, Shots

Shots table has immutability triggers (no UPDATE/DELETE).
If a user imports incorrect data, there is no in-app way to correct it.

### Impact
- Bad data (e.g., Rapsodo sensor glitch) cannot be edited.
- Only workaround: re-import corrected CSV as a new session.

### Proposed fix
- Append-only correction model: INSERT a correction row with FK to original shot.
- Analysis queries prefer correction rows over originals where present.
- Alternatively: relax immutability for shots (not recommended; breaks audit trail).

---

## B-004: Course Editing

**Priority:** Low (post-Milestone 1)
**Area:** Scorecard, Courses

Course snapshots have immutability triggers (no UPDATE/DELETE).
If a user creates a course with incorrect hole data, they cannot edit it.

### Impact
- Typos or incorrect par values cannot be fixed.
- Only workaround: create a new course and hide the old one.

### Proposed fix
- Add hide/archive flag for course snapshots (similar to templates).
- Alternatively: relax immutability for course snapshots (not recommended).

---

## B-005: Multi-Device Round Completion UX

**Priority:** Medium (Phase 7+)
**Area:** Scorecard, Multi-Device Rounds, Nostr

When the round creator finishes before a joiner, `RoundReviewView` shows stale remote scores cached from kind 30501 live updates. Full final scores appear in `RoundDetailView` after both players finish (fetched via kind 1502 query).

### Impact
- Review screen may show incomplete remote scores if other player hasn't finished yet.
- RoundDetailView eventually shows correct final scores after kind 1502 publish.
- No data loss, but potentially confusing UX during transition.

### Proposed fix
- Detect "all players done" state via 1502 event count matching player count.
- Live-fetch 1502 events in review screen, not just detail view.
- Add "Waiting for other players..." UI when creator finishes first.
- Future: subscribe to 1502 publishes in real-time instead of one-shot queries.

### Code pointers
- `ios/RAID/RAID/Views/RoundReviewView.swift` — review screen (currently uses ActiveRoundStore state)
- `ios/RAID/RAID/Views/RoundDetailView.swift` — detail screen (fetches 1502 on load)
- `ios/RAID/RAID/Nostr/NostrClient.swift` — `fetchFinalRecords()` method

---

## B-006: Camera QR Scanning for Round Join

**Priority:** Low (Phase 7+)
**Area:** Scorecard, Multi-Device Rounds, UX

Round join flow currently requires pasting nevent URI. QR scanning with device camera would improve UX.

### Impact
- Users must manually copy/paste nevent strings from QR codes shown by round creator.
- Extra friction compared to native camera scan.

### Proposed fix
- Add camera-based QR scanner using `DataScannerViewController` (iOS 16+).
- Add `NSCameraUsageDescription` to Info.plist.
- Detect nevent1 pattern in scanned data, parse and validate before join.

### Code pointers
- `ios/RAID/RAID/Views/JoinRoundView.swift` — nevent paste entry
- Needs: `AVCaptureSession` or `DataScannerViewController` integration

---

## B-007: Signature Verification on Remote Events

**Priority:** High (Phase 7+, security)
**Area:** Scorecard, Multi-Device Rounds, Nostr

Kind 1502 final records and kind 30501 live scorecards are accepted without verifying that the author's pubkey matches a player in the kind 1501 initiation event's `p` tags.

### Impact
- Malicious or accidental score publishes from non-players could be accepted.
- No authentication of event authorship against round roster.

### Proposed fix
- On parse, verify `event.pubkey` is present in the stored `round_players` table for that round.
- Reject events from non-rostered pubkeys with explicit error (do not cache).
- Use rust-nostr-swift `event.verify()` to validate Nostr signature cryptographically.

### Code pointers
- `ios/RAID/RAID/Nostr/NIP101gEventParser.swift` — `parseLiveScorecard()` / `parseFinalRecord()`
- `ios/RAID/RAID/Scorecard/RoundPlayerRepository.swift` — `fetchPlayers(forRound:)` for roster lookup
- rust-nostr-swift: `Event.verify()` method
