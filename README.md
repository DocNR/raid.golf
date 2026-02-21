# RAID Golf

A golf performance tracker for iOS. Practice analytics, on-course scoring, and optional Nostr-based social features — all stored locally on your device.

RAID stands for **Rapsodo A-shot Integrity & Discipline**.

---

## What It Does

**Practice (Practice tab)**
- Import Rapsodo MLM2Pro CSV exports
- Classify shots as A, B, or C per club using configurable KPI templates
- Track A-shot percentage trends over time with pinned-template analysis
- Manage KPI templates (create, rename, hide, duplicate, set active per club)

**Rounds (Play tab)**
- Score rounds hole-by-hole, solo or with other players
- Same-device multiplayer: round-robin scoring, pass the device per player
- Multi-device multiplayer: invite via QR code or nevent link, score independently, sync via Nostr relays
- Scorecard grid with standard golf notation (circles for under-par, squares for over-par)
- Publish completed rounds as structured NIP-101g events (kind 1501/1502)

**Feed (Feed tab)**
- Social feed of golf rounds from players you follow
- Inline rich content: images, GIFs, video, tappable @mentions, tappable URLs
- React (NIP-25), comment (NIP-22/NIP-10), and thread view for any event
- Outbox-routed feed: reads from each author's write relays, not just your own

**Profile & Social**
- Nostr identity: create a new keypair, import an existing nsec, or sign in read-only with npub
- Follow list management (PeopleView): Following and Favorites tabs, swipe gestures, npub search
- NIP-65 relay management: add/remove/configure read and write relays per user
- NIP-17 DM round invites to players' inbox relays
- User profile sheets: view and follow/unfollow/favorite any player from feed or PeopleView

---

## Architecture

### Local-First

All authoritative data lives in SQLite on-device (GRDB). Nostr events are projections derived from local facts — not the source of truth. Deleting the app deletes your data. There is no cloud sync.

### Integrity Kernel (Frozen)

The kernel layer enforces immutability at the database level:
- Sessions, shots, templates, and scorecards are immutable after creation
- Content-addressed templates: SHA-256 of RFC 8785 JCS canonical JSON
- Immutability triggers on all authoritative tables
- Repository owns canonicalization and hashing on insert; read path never recomputes

**Kernel Contract:** `docs/private/kernel/KERNEL_CONTRACT_v2.md` (v2.0, frozen 2026-02-02)

**Governance:** `.clinerules/kernel.md` defines hard STOP conditions for AI-assisted development. See `docs/private/kernel/KERNEL_GOVERNANCE.md` for the full domain registry and promotion checklist.

### Schema (v14)

| Table | Domain | Mutable |
|-------|--------|---------|
| `sessions`, `shots`, `kpi_templates`, `club_subsessions` | Kernel (frozen) | No |
| `course_snapshots`, `course_holes`, `rounds`, `round_events`, `hole_scores` | Kernel-adjacent | No |
| `round_players`, `round_nostr` | Kernel-adjacent | No |
| `template_preferences` | Product layer | Yes |
| `nostr_profiles` (v9) | Social cache | Yes |
| `clubhouse_members` (v10) | Favorites list | Yes |
| `nostr_relay_lists` (v11) | Relay cache | Yes |
| `follow_list_cache` (v12) | Follow list cache | Yes |
| `feed_event_cache` (v13) | Feed event cache | Yes |
| `referenced_event_cache` (v14) | Referenced event cache | Yes |

### Nostr Integration

RAID uses Nostr for identity and optional social features. The app is fully usable without Nostr (guest mode). Nostr is a projection layer — not a dependency.

- **SDK:** rust-nostr-swift v0.44.2
- **NIPs implemented:** 01 (events), 02 (follow lists), 10 (reply threading), 17 (DMs), 22 (comments), 25 (reactions), 51 (lists/Favorites), 59 (gift wrap), 65 (relay lists), 101g (golf events)
- **Publishing:** fire-and-forget to configured write relays
- **Read:** one-shot reads with EOSE exit; outbox routing via NIP-65 relay lists

---

## Project Layout

```
ios/RAID/                  iOS app (SwiftUI + GRDB)
  RAID/
    Kernel/                Frozen kernel layer (canonical, hashing, schema, repositories)
    Models/                Domain models
    Ingest/                CSV import pipeline
    Nostr/                 NostrService, KeyManager, NIP builders
    Views/                 SwiftUI views
    Scorecard/             Round scoring state (ActiveRoundStore)
  RAIDTests/               XCTest target (314+ tests)

docs/
  private/                 Planning docs (gitignored): roadmap, Nostr plan, onboarding plan
  specs/                   JCS hashing spec, NIP-101g draft
  schema_brief/            Schema documentation

.clinerules/               AI agent governance rules
CHANGELOG.md               Project changelog
TESTFLIGHT_NOTES.md        Beta tester instructions
```

---

## Development Setup

Requirements:
- Xcode 16+
- iOS 18.4 simulator or physical device (iOS 17.0+ minimum deployment target)
- Swift Package Manager (GRDB, rust-nostr-swift resolved automatically)

```bash
open ios/RAID/RAID.xcodeproj
```

Run tests:
```bash
xcodebuild test \
  -project ios/RAID/RAID.xcodeproj \
  -scheme RAID \
  -destination "platform=iOS Simulator,name=iPhone 16,OS=18.4"
```

Live relay tests require `RAID_LIVE_TESTS=1` environment variable and are skipped by default.

---

## Governance & Agent Constraints

AI agents working on this codebase must follow `.clinerules/`. Key rules:
- Do not modify kernel layer files without explicit authorization
- Do not add mutability to immutable tables
- Read path must not recompute hashes (RTM-04)
- `docs/private/` is gitignored — update `MEMORY.md` instead of committing planning docs

---

## License

RAID Golf kernel and analysis framework: see repository root for license details.

iOS app: proprietary, not open source.
