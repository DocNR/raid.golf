# Nostr Integration Plan — Gambit Golf

> Protocol-layer plan for expanding Nostr integration in Gambit Golf.
> Companion doc: `onboarding_flow_plan.md` (UX layer, planned separately).

---

## Current State

### What Exists (Phase 6A–6C, shipped)

| Component | File | Status |
|-----------|------|--------|
| Key generation | `KeyManager.swift` | Auto-generates keypair, stores nsec in Keychain |
| Publishing | `NostrClient.swift` | Fire-and-forget to 3 hardcoded relays |
| Relay reads | `NostrClient.swift` | One-shot reads with EOSE exit (3 read relays) |
| NIP-101g events | `NIP101gEventBuilder.swift` | Kind 1501 (initiation) + 1502 (final record) |
| Profile display | `NostrProfileView.swift` | Shows npub, offers nsec copy |
| Follow list | `NostrClient.swift` | Reads kind 3 (NIP-02), fetches kind 0 profiles |
| Player selection | `CreateRoundView.swift` | Multi-select from follow list + manual npub entry |
| SDK | `rust-nostr-swift` | NostrSDK v0.44.2 |

### What's Missing

- **No key import** — users can't restore identity on a new device
- **No profile editing** — can read kind 0 but never publishes it
- **No NIP-65** — hardcoded relays, no gossip model
- **No persistent connections** — connect/disconnect per operation
- **No guest mode** — keypair auto-generates, no opt-out
- **No social feed** — can publish rounds but can't see friends' rounds
- **No follow list publishing** — reads kind 3 but never writes it

---

## Anti-Patterns to Fix

These should be addressed as part of Phase 7A (foundations), not deferred.

### 1. Fire-and-Forget Publishing is Unreliable

`publishEvent()` calls `client.connect()` then immediately `sendEventBuilder()`. WebSocket handshake may not be complete. The SDK's `sendEventBuilder` may handle this internally with a queue, but the connect→publish→disconnect-per-event pattern creates unnecessary overhead and connection churn.

**Fix:** Move to a `NostrService` singleton with persistent connections. Connect on app foreground, disconnect on background. Reuse the client for all operations.

### 2. Hardcoded Relays

Three publish relays (`damus.io`, `nos.lol`, `relay.nostr.band`) and three read relays (`damus.io`, `nos.lol`, `purplepag.es`) are hardcoded. If any go down or ban the app, publishing breaks silently.

**Fix:** NIP-65 relay list metadata (Phase 7C). Fall back to hardcoded defaults only when NIP-65 data is unavailable.

### 3. No Key Import

Users who reinstall, switch devices, or already have a Nostr identity cannot bring it to Gambit Golf. This is the #1 blocker for interop with other Nostr clients.

**Fix:** `KeyManager.importKey(nsec:)` + import UI (Phase 7A).

---

## Phased Roadmap

### Phase 7A: Identity & Connection Foundations

> **Goal:** Users can import existing Nostr identities. Publishing is reliable.

#### 7A.1 — Key Import

Add `importKey(nsec:)` to `KeyManager`:
- Validate nsec format via `Keys.parse(secretKey:)`
- Overwrite existing Keychain entry (with confirmation UI)
- Return new `KeyManager` instance

UI: Settings → "Import Nostr Account" → paste `nsec1...` → validate → save.

**Scope:** ~2 hours. No schema changes.

#### 7A.2 — NostrService Singleton

Replace static `NostrClient` enum with a `NostrService` class:
- Singleton, initialized at app launch
- Persistent `Client` connection (connect on foreground, disconnect on background)
- `publish(builder:)` reuses existing connection
- `fetchFollowList()`, `fetchProfiles()` reuse existing connection
- Retry logic for transient failures (1 retry with 2s delay)
- Observable connection status for UI indicators

**Scope:** ~4 hours. Replaces all `NostrClient` call sites.

#### 7A.3 — Signature Verification

Verify event signatures on all relay reads before processing:
- `fetchFollowList()` — verify kind 3 event
- `fetchProfiles()` — verify each kind 0 event
- Log and discard events that fail verification

The `rust-nostr` SDK likely verifies internally, but we should be explicit. Check if `Event` has a `.verify()` method and use it.

**Scope:** ~1 hour.

**Deliverable:** A user can import their nsec from Primal/Damus/Amethyst and use it in Gambit Golf. Publishing works reliably.

---

### Phase 7B: Profile Management

> **Goal:** Users can set their name and avatar so other Nostr apps recognize them.

#### 7B.1 — Profile Publishing (Kind 0)

Build and publish kind 0 metadata events with:
- `name` (username)
- `display_name` (real name or nickname)
- `picture` (avatar URL — paste URL for MVP, NIP-96 upload later)
- `about` (optional bio)

**Important:** Do NOT add golf-specific fields (handicap, home course) to kind 0. That goes in a separate event kind later (kind 30078).

#### 7B.2 — Edit Profile UI

Settings → "Edit Profile" screen:
- Text fields for name, display_name, about
- Image URL field for picture (paste URL)
- "Save" publishes kind 0 to write relays
- Pre-populate from existing kind 0 if available (fetch on load)

#### 7B.3 — Profile Read Improvements

- Fetch own profile on app launch (cache in memory)
- Show avatar + name in profile view and round creation
- Handle profile updates from other clients gracefully (newest `created_at` wins)

**Deliverable:** User's name/avatar appears in Primal, Damus, etc. when someone looks up their pubkey.

---

### Phase 7C: NIP-65 Relay List Metadata

> **Goal:** Replace hardcoded relays with user-configurable relay lists following the gossip model.

#### 7C.1 — Read NIP-65 Relay Lists

Fetch kind 10002 events for users to learn their preferred relays:
- Parse `r` tags: `["r", "wss://relay.url"]`, `["r", "wss://relay.url", "read"]`, `["r", "wss://relay.url", "write"]`
- When fetching a user's rounds or profile, query their declared read relays

#### 7C.2 — Publish Own Relay List

UI: Settings → "Relays" → manage relay list:
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

#### 7C.3 — Smart Relay Routing

- Publishing: use own NIP-65 write relays
- Fetching other users: query their NIP-65 read relays
- Fallback: hardcoded defaults when NIP-65 data is missing
- Cache relay lists in memory (refresh on profile view)

**Deliverable:** App follows the gossip model. Users control where their data goes.

---

### Phase 7D: Guest Mode & Delayed Activation

> **Goal:** Users can use the app without knowing about Nostr. Convert when ready.

#### Decision: Silent Key Generation (recommended)

Generate keypair on first launch, store in Keychain, but gate all Nostr features behind an "activation" flag.

**Why this approach:**
- No migration needed at conversion time (keypair exists from day one)
- All local features work immediately (practice, scorecards, rounds)
- Primal uses this same pattern
- Simpler than truly keyless → generate → migrate

**How it works:**
1. First launch → keypair generated silently → stored in Keychain
2. `@AppStorage("nostrActivated")` defaults to `false`
3. All publishing and relay reads gated behind this flag
4. User taps "Enable Nostr" (in settings or prompted contextually) → flag flips to `true`
5. First activation optionally triggers: publish kind 0 profile, publish kind 10002 relay list
6. Existing local data stays local — no retroactive publishing of practice data

**Contextual activation prompts** (shown when relevant, not nagging):
- "Share this round with friends?" → when completing a round
- "Add players from Nostr?" → when creating a multiplayer round
- "Back up your data?" → after N sessions

**Deliverable:** Golfers use the app for weeks before they ever hear the word "Nostr."

---

### Phase 7E: Follow List Publishing & Social Reads

> **Goal:** Users can follow golf friends and see their rounds.

#### 7E.1 — Follow/Unfollow

- "Follow" button on player profiles (from round history, search)
- Publish kind 3 event (replaceable contact list) with all followed pubkeys
- Merge with existing kind 3 (don't blow away follows from other apps)

#### 7E.2 — Activity Feed

- New tab or section: "Friends' Rounds"
- Subscription for kind 1501/1502 events from followed pubkeys
- Query their NIP-65 read relays (gossip model)
- Real-time updates via persistent subscriptions (NostrService)
- Basic card UI: player name, course, score, date

#### 7E.3 — Reactions (NIP-25)

- Kind 7 events for reacting to friends' rounds
- Tags: `["e", "round_event_id"], ["p", "round_author_pubkey"]`
- UI: simple reaction button on round cards in feed

**Deliverable:** The app feels like a social network for golfers.

---

### Phase 7F: Practice Data Portability (Future)

> **Goal:** Cross-device sync for practice sessions via Nostr events.

**Event kind:** 30078 (application-specific data, parameterized replaceable).

**What to publish:**
- Practice *sessions* (aggregated stats per club per session) — not individual shots
- Template configurations
- Namespaced via `d` tag: `gambit-session-{uuid}`, `gambit-template-{hash}`

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
| NIP-02 | Follow lists (write) | 7E | High |
| NIP-101g | Golf rounds | Done | - |
| NIP-65 | Relay list metadata | 7C | High |
| NIP-25 | Reactions | 7E | Medium |
| NIP-09 | Event deletion | 7E+ | Medium |
| NIP-05 | DNS verification | Future | Low |
| NIP-44 | Encrypted content | 7F | Low |
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
| Practice data sync | Deferred to Phase 7F | App must work fully offline first |
| Relay strategy | NIP-65 (Phase 7C) | Hardcoded relays are temporary |
| Connection model | Persistent singleton | Fire-and-forget is unreliable |
| Social features | After identity + relays | Foundation must be solid first |

---

## Dependencies

```
7A (Identity + Connections)
 ├── 7B (Profile Management)     — needs reliable publishing
 ├── 7C (NIP-65 Relay Lists)     — needs persistent connections
 │    └── 7E (Social Features)   — needs relay routing
 └── 7D (Guest Mode)             — needs key import for "Sign In" path
      └── Onboarding Flow Plan   — separate doc, depends on 7A + 7D
```

Phase 7F (Practice Data Portability) is independent and can be built anytime after 7A.

---

## Out of Scope

- Multi-device real-time sync (would need relay subscriptions + CRDT, too complex for now)
- Nostr-based payments / betting (NIP-47 — future product decision)
- Course directory via Nostr (kind 33501 is specced in NIP-101g but not prioritized)
- Relay hosting (users use public relays or bring their own)
