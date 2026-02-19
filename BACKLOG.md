# RAID Golf — Backlog

Known issues and deferred improvements, roughly prioritized.

Numbers match those used in MEMORY.md. Closed items retained for audit trail.

---

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

## B-002: Multi-Device Round Completion UX

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
- `ios/RAID/RAID/Nostr/NostrService.swift` — `fetchFinalRecords()` method

---

## B-003: Camera QR Scanning for Round Join

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

## B-004: Signature Verification on Remote Events

**Status:** ✅ CLOSED (Phase 8A.4, 2026-02-15)
**Priority:** High (Phase 7+, security)
**Area:** Scorecard, Multi-Device Rounds, Nostr

Kind 1502 final records and kind 30501 live scorecards were accepted without verifying that the author's pubkey matched a player in the kind 1501 initiation event's `p` tags.

### Resolution
- **Phase 8A.3:** All relay fetch methods now call `event.verify() -> Bool` to verify event ID and schnorr signature. Invalid events are silently discarded.
- **Phase 8A.4:** Added `isAuthorizedPlayer()` module-level helper. Applied in `ActiveRoundStore.fetchRemoteScores()` (kind 30501) and `RoundDetailView.fetchRemoteFinalRecords()` (kind 1502). Events from pubkeys not in the round's player roster are rejected with log.
- Cryptographic signature verification prevents forged events.
- Author verification prevents unauthorized score publishing from non-rostered pubkeys.

### Code pointers
- `ios/RAID/RAID/Nostr/NostrService.swift` — `verifiedEvents()` private helper (Phase 8A.3)
- `ios/RAID/RAID/Scorecard/ActiveRoundStore.swift` — `fetchRemoteScores()` author check (Phase 8A.4)
- `ios/RAID/RAID/Views/RoundDetailView.swift` — `fetchRemoteFinalRecords()` author check (Phase 8A.4)
- `ios/RAID/RAID/Scorecard/RoundPlayerRepository.swift` — `fetchPlayerPubkeys(forRound:)` for roster lookup

---

## B-005: NostrService Profile Cache Concurrency

**Priority:** Low (post-Phase 8C)
**Area:** Nostr, Threading

`NostrService.profileCache` is a plain `var` dictionary with no synchronization. Multiple async callers (e.g., `resolveProfiles` + `fetchFollowListWithProfiles` overlapping) can write concurrently, causing undefined behavior or crashes under load.

### Impact
- Rare in practice (fire-and-forget connections are short-lived), but theoretically unsafe.
- No user-visible crash reported yet.

### Proposed fix
- Make `NostrService` an `actor`, or
- Protect `profileCache` with an `NSLock` or serial dispatch queue, or
- Move cache entirely into `ProfileCacheRepository` (GRDB-backed, already thread-safe).

### Code pointers
- `ios/RAID/RAID/Nostr/NostrService.swift` — `profileCache` property

---

## B-006: No Outbox Queue for Social Events

**Priority:** Low (post-Phase 8C)
**Area:** Nostr, Social

Comments, replies, and reactions are published fire-and-forget. If the app is force-quit during the ~1s publish window (after the user taps send but before relay confirms), the event is silently lost. There is no local queue to retry on next launch.

### Impact
- A user who taps "Send" and immediately force-quits the app may lose their comment.
- No data loss in the local sense (nothing was stored), but the social action is dropped.
- Low frequency in practice; not yet user-reported.

### Proposed fix
- GRDB-backed outbox queue: write event to a `pending_nostr_events` table before publishing.
- On next app foreground, retry any pending events not yet acknowledged by a relay.
- On relay `OK` response, mark as sent and delete from queue.
- Phase 8C (NIP-65 relay routing) is complete. Outbox-routed send queue can now use the established relay routing logic to determine where to send events.

### Code pointers
- `ios/RAID/RAID/Nostr/NostrService.swift` — `publishReaction()`, `publishComment()`, `publishReply()`

---

## B-007: Social Content Caching

**Priority:** Medium (post-Phase 8C)
**Area:** Nostr, Social, Performance

The social layer has no local persistence for fetched content. Every visit to a previously-seen feed, thread, or profile triggers a fresh relay round-trip.

### Impact
- **PFP images:** `AsyncImage` re-fetches from the remote URL on every view appearance — no image cache layer. Avatars flash as gray circles before loading.
- **Comment threads:** Visiting a thread that was already loaded re-fetches all comments from the relay.
- **Feed:** The feed is completely lost on app restart — `FeedViewModel` is re-instantiated and repopulates from relay. First-open feed is blank until relay responds.
- **Profile display lag:** Even after a profile is stored in `nostr_profiles` (GRDB), avatar images are not cached locally, so images always re-download.

### Proposed fix
- **Image cache:** Use `URLCache` with a configured disk capacity, or wrap `URLSession` to respect cache-control headers.
- **Comment/reaction persistence:** Store fetched comments and reaction counts in GRDB (`cached_comments`, `cached_reaction_counts` tables) with a TTL or per-feed staleness policy.
- **Feed persistence:** Persist the last N feed items to GRDB so the feed renders immediately on app start, then refreshes in the background.

### Sequencing
**Phase 8C is complete.** This is now the clear next optimization target. Timing profiling from Phase 8C shows the feed first-load bottleneck is ~15s, with the serial relay connection paths (follow list fetch, relay resolution, event processing) as the primary contributors — not outbox fan-out (~1.5s). Caching architecture should account for the NIP-65 relay routing established in 8C when designing cache invalidation.

### Code pointers
- `ios/RAID/RAID/Nostr/FeedViewModel.swift` — feed state, no persistence on restart
- `ios/RAID/RAID/Nostr/NostrService.swift` — `fetchComments()`, `fetchReactions()`, `fetchReplies()`
- `ios/RAID/RAID/Nostr/ProfileCacheRepository.swift` — profiles cached (GRDB), but avatar images are not

---

## B-011: Relay Management UX Polish

**Priority:** Low (post-Phase 8C)
**Area:** Nostr, Relay Management, UX

The Keys & Relays screen manages NIP-65 relay lists and NIP-17 DM inbox relays. Core functionality (add, remove, edit direction, swipe-to-cycle) is complete. Several UX improvements remain.

### Missing features
- **Online/offline indicator:** Green/red dot showing relay connectivity status.
- **Latency display:** Ping time (ms) per relay, shown as secondary text.
- **Paid/free indicator:** Fetch NIP-11 relay info document to detect payment requirements.
- **Relay info sheet:** Tap relay to see NIP-11 metadata (name, description, supported NIPs, limits).

### Code pointers
- `ios/RAID/RAID/Views/NostrProfileView.swift` — `relayRow()`, `relaySection`, `inboxRelaySection`
- NIP-11 info fetch: `curl -H "Accept: application/nostr+json" <relay_url>` — needs Swift equivalent

---

## B-008: Template Versioning

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
- Add template lifecycle UI: mark templates as deprecated, show lineage.
- Optionally allow re-analysis of all sessions with a new template (batch operation).

---

## B-009: Shot Editing

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

## B-010: Course Editing

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
