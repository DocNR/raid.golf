# Nostr Integration Plan — RAID Golf

> Protocol-layer plan for expanding Nostr integration in RAID Golf.
> Companion doc: `onboarding_flow_plan.md` (UX layer, planned separately).

---

## Status & Phase Renumbering

> **Note:** This plan was originally written using "Phase 7A-7F" numbering. The actual Phase 7 implemented multi-device rounds. The Nostr protocol roadmap has been renumbered to 8A-8F to avoid confusion.

| Original Phase | Current Phase | Status | Completion Date |
|----------------|---------------|--------|-----------------|
| 7A | 8A | ✅ COMPLETE | 2026-02-15 |
| 7B | 8B | ✅ COMPLETE | 2026-02-18 |
| 7C | 8C | ✅ COMPLETE | 2026-02-18 |
| 7D | 8D.A | ✅ COMPLETE | 2026-02-17 |
| 7D | 8D.B | ✅ COMPLETE | 2026-02-18 |
| 7E | 8E | FUTURE | - |
| 7F | 8F | FUTURE | - |

### Phase 8A Summary (COMPLETE)
- **Key import backend:** `KeyManager.importKey(nsec:)` validates and stores nsec1/hex keys
- **NostrService refactor:** Replaced static `NostrClient.swift` with `@Observable` injectable `NostrService.swift` (19 call sites migrated)
- **Signature verification:** `verifiedEvents()` helper on all 6 fetch methods, explicit `event.verify()` checks
- **Author verification:** `isAuthorizedPlayer()` validates scoring events (kind 30501/1502) against round roster (closes B-004)
- **Fire-and-forget preserved:** Persistent connections deferred to Phase 8C (intentional)
- **Test coverage:** 200 total unit/integration tests (5 new KeyManager tests, 1 removed NostrClientTests)

---

## Current State

### What Exists (Phase 8D.B, shipped 2026-02-18)

| Component | File | Status |
|-----------|------|--------|
| Key generation | `KeyManager.swift` | Auto-generates keypair, stores nsec in Keychain |
| Key import | `KeyManager.swift` | `importKey(nsec:)` validates nsec1/hex, overwrites Keychain |
| Publishing | `NostrService.swift` | `@Observable` injectable class, fire-and-forget to 3 hardcoded relays |
| Relay reads | `NostrService.swift` | One-shot reads with EOSE exit (3 read relays), signature verification on all fetches |
| NIP-101g events | `NIP101gEventBuilder.swift` | Kind 1501 (initiation) + 1502 (final record) + 30501 (live scorecards) |
| Profile display | `SideDrawerView.swift` | Avatar + display name in side drawer; inline edit on profile screen |
| Profile editing | `DrawerState.swift` + `NostrService.swift` | Kind 0 metadata publishing: name, display_name, picture, about |
| Follow list | `NostrService.swift` | Reads kind 3 (NIP-02), fetches kind 0 profiles, verifies signatures |
| Profile cache | `ProfileCacheRepository.swift` | GRDB `nostr_profiles` table; 3-layer resolution (memory → DB → relay); batch enrichment |
| Player selection | `CreateRoundView.swift` | Multi-select from follow list + search by npub/name against profile cache |
| Multi-device rounds | `RoundJoinService.swift` | Invite sharing (nevent bech32), join flow, live score sync, final records |
| DM invites | `DMInviteService.swift` | NIP-17 gift-wrapped round invites to inbox relays (kind 14/10050) |
| Guest mode | `FeedViewModel.swift` + `NostrActivationAlert.swift` | `@AppStorage("nostrActivated")` gates all Nostr features; `.guest` load state |
| Reactions | `NostrService.swift` | NIP-25 kind 7; optimistic UI; batch fetch via `fetchReactions()` |
| Comments | `NostrService.swift` | NIP-22 kind 1111 for scorecard events; NIP-10 kind 1 replies for text notes |
| Thread UX | `ThreadDetailView.swift` | Damus-style push navigation; pinned original post; scrollable replies; input bar |
| Clubhouse | `ClubhouseRepository.swift` + `ClubhouseView.swift` | NIP-51 kind 30000 curated player list; relay sync; GRDB `clubhouse_members` table (schema v10) |
| Nav structure | `ContentView.swift` + `SideDrawerView.swift` | 3-tab layout (Feed / Play / Courses) + side drawer (Profile, Practice, Keys & Relays, About) |
| Replaceable event fix | `NostrService.swift` | All replaceable event fetches select newest `created_at` (fixes stale follow-list bug) |
| Security | `NostrService.swift` | Signature verification on all events; author verification on scoring events |
| SDK | `rust-nostr-swift` | NostrSDK v0.44.2 |

### What's Missing

- **No persistent connections** — fire-and-forget kept intentionally
- **No NIP-51 Golf Buddies extended UX** — Clubhouse (kind 30000) shipped in 8D.B; further Golf Buddies list work deferred to Phase 8E
- **No follow list publishing** — reads kind 3 but never writes it (Phase 8E)
- **No full social feed** — feed reads exist (FeedView); follow-list write deferred to 8E

---

## Anti-Patterns to Fix

These should be addressed as part of Phase 8A (foundations), not deferred.

### 1. Fire-and-Forget Publishing (Deferred to Phase 8C)

**Update (Phase 8A):** Fire-and-forget pattern was intentionally preserved. NostrService refactor improved structure (@Observable injectable class) but kept per-operation connections. Persistent connections deferred to Phase 8C.

`publishEvent()` calls `client.connect()` then immediately `sendEventBuilder()`. WebSocket handshake may not be complete. The SDK's `sendEventBuilder` may handle this internally with a queue, but the connect→publish→disconnect-per-event pattern creates unnecessary overhead and connection churn.

**Fix (deferred to Phase 8C):** Move to a `NostrService` singleton with persistent connections. Connect on app foreground, disconnect on background. Reuse the client for all operations.

### 2. Hardcoded Relays

**Update (Phase 8A):** Still hardcoded. Deferred to Phase 8C (NIP-65).

Three publish relays (`damus.io`, `nos.lol`, `relay.nostr.band`) and three read relays (`damus.io`, `nos.lol`, `purplepag.es`) are hardcoded. If any go down or ban the app, publishing breaks silently.

**Fix (deferred to Phase 8C):** NIP-65 relay list metadata (Phase 8C). Fall back to hardcoded defaults only when NIP-65 data is unavailable.

### 3. No Key Import (Backend DONE Phase 8A, UI needed Phase 8B)

**Update (Phase 8A):** Backend complete. `KeyManager.importKey(nsec:)` validates nsec1/hex, overwrites existing key. UI flow (Settings screen, confirmation dialog) deferred to Phase 8B.

Users who reinstall, switch devices, or already have a Nostr identity cannot bring it to RAID Golf. This is the #1 blocker for interop with other Nostr clients.

**Fix (backend done, UI deferred):** `KeyManager.importKey(nsec:)` implemented. Import UI (Phase 8B).

---

## Phased Roadmap

### Phase 8A: Identity & Connection Foundations ✅ COMPLETE (2026-02-15)

> **Goal:** Users can import existing Nostr identities. Publishing is reliable.

#### 8A.1 — Key Import ✅

Add `importKey(nsec:)` to `KeyManager`:
- Validate nsec format via `Keys.parse(secretKey:)`
- Overwrite existing Keychain entry (with confirmation UI)
- Return new `KeyManager` instance

UI: Settings → "Import Nostr Account" → paste `nsec1...` → validate → save.

**Scope:** ~2 hours. No schema changes.

**COMPLETE:** `KeyManager.importKey(nsec:)` validates nsec1/hex via `Keys.parse()`, overwrites Keychain entry, returns new KeyManager. UI deferred to Phase 8B.

#### 8A.2 — NostrService Refactor ✅

Replace static `NostrClient` enum with a `NostrService` class:
- Singleton, initialized at app launch
- Persistent `Client` connection (connect on foreground, disconnect on background)
- `publish(builder:)` reuses existing connection
- `fetchFollowList()`, `fetchProfiles()` reuse existing connection
- Retry logic for transient failures (1 retry with 2s delay)
- Observable connection status for UI indicators

**Scope:** ~4 hours. Replaces all `NostrClient` call sites.

**COMPLETE:** `NostrService.swift` is an `@Observable` class injectable via SwiftUI Environment. Fire-and-forget pattern preserved (not singleton, not persistent connections). 19 call sites migrated from static NostrClient. NostrClient.swift deleted. Persistent connections deferred to Phase 8C.

#### 8A.3 — Signature Verification ✅

Verify event signatures on all relay reads before processing:
- `fetchFollowList()` — verify kind 3 event
- `fetchProfiles()` — verify each kind 0 event
- Log and discard events that fail verification

The `rust-nostr` SDK likely verifies internally, but we should be explicit. Check if `Event` has a `.verify()` method and use it.

**Scope:** ~1 hour.

**COMPLETE:** All 6 fetch methods use `verifiedEvents()` helper that calls `event.verify()`. Invalid signatures logged and discarded. Covered by existing tests.

#### 8A.4 — Author Verification ✅

Verify scoring event authors against round roster before accepting remote scores:
- `isAuthorizedPlayer(event:players:)` checks event pubkey against `round_players` table
- Applied to kind 30501 (live scorecards) and kind 1502 (final records)
- Unauthorized events logged and discarded
- Closes backlog item B-004 (signature verification on remote scores)

**COMPLETE:** Implemented in `NostrService.swift`. Tested via integration tests.

**Deliverable (COMPLETE):** Users can import nsec1 keys from other clients. Event signatures verified on all relay reads. Scoring events verified against round roster. NostrService refactored for testability. Fire-and-forget connections preserved (persistent connections deferred to 8C).

---

### Phase 8B: Identity & Profile Management

> **Goal:** Users can see and edit their identity. DM-based round invites work across clients.

#### 8B.1 — Profile Display (COMPLETE — 2026-02-16)

- `ProfileAvatarView` with AsyncImage + 2-letter initials fallback
- Display names shown in player picker, score entry, round detail
- Own profile fetched on Rounds tab load (avatar in toolbar)
- Key import validation in `NostrProfileView` (nsec paste + error handling)

#### 8B.2 — NIP-17 DM Round Invites (COMPLETE — 2026-02-16)

- `DMInviteBuilder`: kind 14 rumor with nevent + course name
- `DMInviteService`: fetch/unwrap incoming gift wraps (7-day lookback)
- NIP-17 compliant: gift wraps sent to recipient's kind 10050 inbox relays
- Auto-publish own kind 10050 on first multi-device round
- Incoming invites displayed in JoinRoundView with sender profile
- Pull-to-refresh for invite checking on Rounds tab
- 11 tests (build rumor, extract nevent, gift wrap encrypt/decrypt)

#### 8B.3 — Profile Publishing (Kind 0) — COMPLETE (2026-02-18)

Shipped as part of nav restructure + side drawer sprint:
- Kind 0 metadata publishing: `name`, `display_name`, `picture` (URL), `about`
- Published via `NostrService.publishProfile()` to write relays
- `DrawerState.ownProfile` is the single source of truth (no local `@State` duplication in child views)
- `NostrProfileView` in side drawer pre-populates from cached kind 0 profile
- Golf-specific fields (handicap, home course) intentionally excluded from kind 0 — deferred to kind 30078

#### 8B.4 — Edit Profile UI — COMPLETE (2026-02-18)

Shipped as part of nav restructure + side drawer sprint:
- In-app profile editing in `SideDrawerView` (Profile menu item)
- Text fields for name, display_name, about; image URL field for picture
- "Save" publishes kind 0 via `NostrService`
- `ownProfile` in `DrawerState` is the single source of truth — not duplicated in child views

**Deliverable:** User's name/avatar appears in Primal, Damus, etc. when someone looks up their pubkey. COMPLETE.

---

### Phase 8C: NIP-65 Relay List Metadata

> **Goal:** Replace hardcoded relays with user-configurable relay lists following the gossip model.
>
> **Motivation:** With hardcoded relays, the feed is only as good as what 3 relays return in a 5-second window. Kind-3 contact list propagation is inconsistent — a follow added on another client may not appear (or may appear then disappear) depending on which relay responds first. The outbox model fixes this by querying where data actually lives.

#### 8C.1 — Read NIP-65 Relay Lists

Fetch kind 10002 events for users to learn their preferred relays:
- Parse `r` tags: `["r", "wss://relay.url"]`, `["r", "wss://relay.url", "read"]`, `["r", "wss://relay.url", "write"]`
- Batch-fetch kind 10002 for all follows in a single query (same pattern as profile batch fetch)
- Cache relay lists in `ProfileCacheRepository` (GRDB) alongside kind-0 profiles — same lifecycle, same staleness tolerance
- Fallback: hardcoded defaults when a user has no kind 10002

#### 8C.2 — Publish Own Relay List

UI: Side drawer → "Keys & Relays" → relay management section:
- Add/remove relays
- Mark as read, write, or both
- Publish kind 10002 on save

Default seed list (used until user customizes):
```
wss://relay.damus.io    (read + write)
wss://nos.lol           (read + write)
wss://relay.nostr.band  (write)
wss://purplepag.es      (read)
```

#### 8C.3 — Smart Relay Routing (Outbox Model)

The outbox model groups queries by relay, not by user. This avoids N separate connections:

1. Fetch all follows' kind-10002 relay lists (batchable in 1 query)
2. Build a **relay → pubkeys** map (e.g., "relay.damus.io serves 30 follows, nos.lol serves 25...")
3. Send **one filter per relay** with all the pubkeys that relay serves
4. Merge results

In practice, most users overlap on popular relays, so 50 follows compress to ~5-8 relay connections.

Routing rules:
- **Own kind-3 fetch:** query own NIP-65 read relays (fixes stale contact list from wrong relay)
- **Publishing:** use own NIP-65 write relays
- **Fetching other users' content:** query their NIP-65 write/outbox relays
- **Fallback:** hardcoded defaults when NIP-65 data is missing

#### 8C.4 — Feed Stability ✅ COMPLETE (2026-02-18)

**Shipped as a quick win ahead of Phase 8C relay work.**

`FeedViewModel.refresh()` now merges new items into existing state instead of wholesale replacement:
- `followSet` filter ensures unfollowed authors are still excluded
- Previously-seen posts survive stale kind-3 responses from relays
- Items reset on app restart (fresh `FeedViewModel` instance)
- No hard-refresh UI needed; behavior is automatic

~~Current bug: `FeedViewModel.refresh()` does a wholesale `items = processed` replacement. If a relay returns a stale kind-3 on one refresh, previously-seen posts vanish.~~

#### rust-nostr SDK Note

rust-nostr's `Client` supports outbox/gossip mode natively via relay routing. Evaluate whether we can use the SDK's built-in outbox mode instead of manual relay→pubkey grouping. This would simplify 8C.3 significantly but requires moving from fire-and-forget to a longer-lived `Client` instance.

**Deliverable:** App follows the gossip model. Feed is stable across refreshes. Users control where their data goes.

---

### Phase 8D: Guest Mode + Social Interactions

#### Phase 8D.A: Guest Mode & Delayed Activation — COMPLETE (2026-02-17)

> **Goal:** Users can use the app without knowing about Nostr. Convert when ready.

Silent key generation approach (implemented):
1. First launch → keypair generated silently → stored in Keychain
2. `@AppStorage("nostrActivated")` defaults to `false`
3. All publishing and relay reads gated behind this flag
4. `WelcomeView` shown to unauthenticated users (key import or new-key generation flow)
5. `NostrActivationAlert` presented when unauthenticated user reaches a gated feature
6. `FeedViewModel.loadState` enum with `.guest` case prevents relay connections without keys
7. Existing local data stays local — no retroactive publishing of practice data

Also shipped in 8D.A:
- `ProfileCacheRepository` (schema v9: `nostr_profiles` table, mutable, no triggers)
  - 3-layer resolution: in-memory dict → GRDB → relay fetch
  - `resolveProfiles`: batch enrichment in 2 relay connections instead of N×2
  - Indexes on `name`, `display_name`, `nip05` for search
- `fetchEventsByIds([String])` on `NostrService` for single-round-trip batch feed enrichment
- Profile search bar in `CreateRoundView` (by npub or display name/name)
- 13 new tests (12 `ProfileCacheRepositoryTests` + 1 `NostrServiceTests`)

**Deliverable:** Golfers use the app for weeks before they ever hear the word "Nostr." COMPLETE.

---

#### Phase 8D.B: Social Interactions + Thread UX — COMPLETE (2026-02-18)

> **Goal:** Users can react to and comment on each other's rounds in the feed.

Shipped:
- **NIP-51 Clubhouse (kind 30000):** curated player list
  - Schema v10: `clubhouse_members` table (mutable, no triggers, outside kernel)
  - `ClubhouseRepository`: local GRDB CRUD
  - `NostrService.fetchClubhouse()` / `publishClubhouse()`: relay sync via kind 30000 replaceable events
  - `ClubhouseView`: manage members from follow list or by manual npub; auto-syncs to relay
  - Clubhouse members appear first in `CreateRoundView` player picker
  - 5 new `ClubhouseRepositoryTests`
- **NIP-25 Reactions (kind 7):** heart button on feed cards
  - `NostrService.publishReaction()` / `fetchReactions()` (batch, single relay connection)
  - Optimistic UI: reaction applied immediately, rolled back on relay failure
- **NIP-22 Comments (kind 1111) + NIP-10 Replies (kind 1):**
  - `NostrService.publishComment()` / `fetchComments()` / `fetchCommentCounts()`
  - `NostrService.publishReply()` / `fetchReplies()` / `fetchReplyCounts()`
  - NIP-22 used only on non-kind-1 events; kind 1 notes use kind 1 replies
- **ThreadDetailView:** Damus-style push navigation (replaces sheet-based `CommentSheetView`)
  - Original post pinned at top; replies/comments in scrollable list; input bar at bottom
  - Optimistic comment append with fire-and-forget relay publish
- **Replaceable event correctness fix:** all replaceable event fetches select newest `created_at`
  - Fixes stale follow-list bug (purplepag.es updated list vs. damus.io/nos.lol stale version)
- 233+ total tests (228 baseline + 5 new ClubhouseRepositoryTests)
- No kernel changes

**Deliverable:** Users can react to and comment on rounds in the feed. COMPLETE.

Note: The NIP-51 Golf Buddies list variant planned for this phase required schema v10 and was included. The full "Golf Buddies" standalone UX flow (originally called 8D.B before 8D.A was separated) is complete as the Clubhouse feature above.

---

### Phase 8E: Follow List Publishing & Social Feed Expansion

> **Goal:** Users can follow golf friends and the feed uses the gossip model for relay routing.

Note: NIP-25 reactions and NIP-22 comments shipped in Phase 8D.B. Phase 8E focuses on follow management and gossip-based feed routing.

#### 8E.1 — Follow/Unfollow

- "Follow" button on player profiles (from round history, search)
- Publish kind 3 event (replaceable contact list) with all followed pubkeys
- Merge with existing kind 3 (don't blow away follows from other apps)

#### 8E.2 — Activity Feed Improvements

- Subscription for kind 1501/1502 events from followed pubkeys using outbox relay routing (depends on 8C)
- Real-time updates via persistent subscriptions (depends on 8C persistent connections)
- Feed card refinements as needed

**Deliverable:** Users can manage their follow list and the feed uses outbox routing via NIP-65.

---

### Phase 8F: Practice Data Portability (Future)

> **Goal:** Cross-device sync for practice sessions via Nostr events.

**Event kind:** 30078 (application-specific data, parameterized replaceable).

**What to publish:**
- Practice *sessions* (aggregated stats per club per session) — not individual shots
- Template configurations
- Namespaced via `d` tag: `raid-session-{uuid}`, `raid-template-{hash}`

**What NOT to publish:**
- Individual shot data (too granular, relay storage concerns)
- Raw Rapsodo CSVs (use NIP-96 file storage if needed)

**Privacy consideration:** Practice data is public by default on Nostr. Options:
- Publish openly (default — most useful for coaching/sharing)
- NIP-44 encryption (private sync only — derive key from nsec)
- User toggle: "Make practice data public" (default off)

**Sync strategy:**
- Local SQLite remains source of truth (always)
- Nostr events are best-effort backup, not required for app function
- On new device: fetch own kind 30078 events → import to local DB
- Conflict resolution: `created_at` timestamp wins

**This phase is optional and deferred.** The app works fully offline without it.

---

## NIP Prioritization

| NIP | Name | Phase | Priority |
|-----|------|-------|----------|
| NIP-01 | Basic protocol | Done | - |
| NIP-02 | Follow lists (read) | Done | - |
| NIP-02 | Follow lists (write) | 8E | High |
| NIP-17 | Private DM (gift wrap) | Done (Phase 8B.2) | - |
| NIP-19 | bech32 encoding | Done (Phase 7A) | - |
| NIP-21 | nostr: URI scheme | Done (Phase 7A) | - |
| NIP-22 | Comments (kind 1111) | Done (Phase 8D.B) | - |
| NIP-25 | Reactions (kind 7) | Done (Phase 8D.B) | - |
| NIP-51 | Curated lists (kind 30000) | Done (Phase 8D.B) | - |
| NIP-59 | Gift wrap | Done (Phase 8B.2) | - |
| NIP-101g | Golf rounds | Done | - |
| NIP-65 | Relay list metadata | 8C | High |
| NIP-09 | Event deletion | 8E+ | Medium |
| NIP-05 | DNS verification | Future | Low |
| NIP-44 | Encrypted content | 8F | Low |
| NIP-96 | File storage | Future | Low |
| NIP-47 | Wallet Connect | Future | Low |
| NIP-46 | Remote signing | Not planned | See below |

### Why Not NIP-46 (Remote Signing)?

- Amber (primary NIP-46 signer) is Android-only
- No widely-used iOS signer app exists yet
- NIP-46 adds relay-mediated handshake latency — overkill for a golf app
- iOS Keychain is hardware-backed secure storage — adequate for key protection
- If an iOS signer ecosystem emerges, add NIP-46 support then

---

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Guest mode approach | Silent key generation | No migration needed, Primal precedent |
| Key management | nsec import/export only | NIP-46 not viable on iOS yet |
| Profile fields | Standard kind 0 only | Golf-specific metadata in kind 30078 |
| Practice data sync | Deferred to Phase 8F | App must work fully offline first |
| Relay strategy | NIP-65 (Phase 8C) | Hardcoded relays are temporary |
| Connection model | **Fire-and-forget (Phase 8A), persistent deferred to 8C** | **8A refactored to NostrService but kept per-operation connections; persistent connections require lifecycle management (Phase 8C)** |
| Social features | After identity + relays | Foundation must be solid first |

---

## Dependencies

```
8A (Identity + Connections)     ✅ COMPLETE (2026-02-15)
 ├── 8B (Identity & Profiles)   ✅ COMPLETE (2026-02-18)
 │    └── 8D.A (Guest Mode)     ✅ COMPLETE (2026-02-17)
 │         └── 8D.B (Social)    ✅ COMPLETE (2026-02-18)
 ├── 8C (NIP-65 Relay Lists)    NEXT — needs persistent connections
 │    └── 8E (Social Feed)      FUTURE — needs relay routing from 8C
 └── Onboarding Flow Plan       — separate doc, partially unblocked
```

Phase 8F (Practice Data Portability) is independent and can be built anytime after 8A.

---

## Out of Scope

- Multi-device real-time sync (would need relay subscriptions + CRDT, too complex for now)
- Nostr-based payments / betting (NIP-47 — future product decision)
- Course directory via Nostr (kind 33501 is specced in NIP-101g but not prioritized)
- Relay hosting (users use public relays or bring their own)
