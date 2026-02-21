# RAID Golf — Long-Term Product Roadmap (Private)

**Status:** Internal / Private  
**Audience:** Project owner, core contributors, AI agents  
**Scope:** Multi-year vision; 12-month execution focus  
**Authority:** Non-canonical (does not override PRD, RTM, or Kernel Contract)

---

## Purpose of This Document

This roadmap describes **how RAID evolves from its current Phase 0 analytics kernel into a Grint-class alternative** with:

- on-course scoring
- optional social federation (Nostr)
- competition formats (skins, Nassau, etc.)
- Bitcoin-native challenges

This document **assumes the kernel already exists and remains intact**.  
It is intentionally written to **extend**, not reinterpret, Phase 0.

---

## Kernel Dependency (Applies to All Milestones)

All milestones in this roadmap **depend on the continued integrity of the RAID kernel**:

- immutable facts (sessions, shots, strokes, attestations)
- immutable templates (content-addressed via canonical JSON + SHA-256)
- deterministic re-analysis semantics
- strict derived-data boundaries (projections are regenerable only)

**No milestone in this roadmap authorizes modification of kernel invariants.**

Any feature added must follow the extension pattern:

1. Define new immutable facts (tables / events)
2. Define new templates (rules) if interpretation is required
3. Evaluate facts + template via pure logic
4. Store results as derived projections referencing:
   - fact IDs
   - template hash

See: `docs/private/kernel/KERNEL_CONTRACT.md`

---

## Guiding Principles (Non-Negotiable)

1. **Local-first is canonical**
   - All authoritative data lives locally.
   - Network layers only consume projections.

2. **Facts never change; interpretations do**
   - Corrections are append-only.
   - History is never silently rewritten.

3. **Standards before social**
   - No feed, leaderboard, or betting feature may exist without a deterministic rule template underneath it.

4. **Opt-in federation**
   - Nostr is a projection layer, not a dependency.
   - The app must remain fully usable with Nostr disabled.

5. **Economic incentives follow integrity**
   - Bitcoin challenges require attestations and determinism first.

---

## Current Baseline (As-Is)

> Updated 2026-02-21 after Phase 8E.1 (Follow/Unfollow + Favorites + Profile Caching) complete.

### Completed
- Phase 0 (A–F): Python kernel, all RTMs validated
- Canonical JSON + hashing (RFC 8785 JCS, kernel v2.0)
- Immutability enforcement (all authoritative tables + triggers)
- Multi-club ingest (Rapsodo MLM2Pro CSV)
- Deterministic analysis semantics (pinned-template A-only trends)
- Derived-projection boundary
- iOS port: kernel harness, CSV import, trends, session detail
- Shot persistence (all 14 normalized metrics)
- KPI template management (active/hidden/rename/duplicate, preferences layer)
- Scorecard v0 → full multiplayer scoring with review scorecard
- Error handling polish (user-facing flows)
- First-run experience (welcome sheet, empty states)
- Nostr integration: auto-gen keys, profile view, fire-and-forget publishing
- NIP-101g structured events: kind 1501 (round initiation) + kind 1502 (final record)
- Relay read infrastructure: follow list (kind 3), profiles (kind 0), batch fetch
- Same-device multiplayer: player model, round-robin scoring, per-player NIP-101g events
- Scoring UX polish: prominent hole display, haptics, review scorecard, progress indicators
- Companion kind 1 social notes with player mentions + njump.me links
- Production hardening complete (Phase 5): docs, TestFlight notes, release validation
- App icon + App Store Connect setup + first TestFlight upload
- Multi-device rounds: invite sharing, join flow, live score sync, per-player final records (Phase 7)
- Nostr protocol foundations: key import, injectable NostrService, signature verification, author verification (Phase 8A)
- Nostr identity display: profile avatars, display names, NIP-17 DM round invites (Phase 8B.1-2)
- Nav restructure + side drawer + in-app profile editing + kind 0 publishing (Phase 8B.3-4)
- Guest mode activation gates: `nostrActivated` flag, WelcomeView, NostrActivationAlert (Phase 8D.A)
- Profile cache: `nostr_profiles` table (schema v9), 3-layer resolution, batch feed enrichment (Phase 8D.A)
- NIP-25 reactions, NIP-22 comments, NIP-10 replies, ThreadDetailView (Phase 8D.B)
- NIP-51 Clubhouse (kind 30000): `clubhouse_members` table (schema v10), ClubhouseView (Phase 8D.B)
- Replaceable event correctness fix: newest `created_at` wins (Phase 8D.B)
- Follow list write path: `publishFollowList()` kind 3, merge-before-publish, `FollowListCacheRepository` convenience methods (Phase 8E.1)
- PeopleView: segmented Following/Favorites tabs, npub-entry search bar, swipe gestures (Phase 8E.1)
- UserProfileSheet: other-user profile sheet from feed/people taps, follow/favorite actions inline (Phase 8E.1)
- "Clubhouse" renamed to "Favorites" in all user-facing labels; data layer unchanged (Phase 8E.1)
- `AvatarImageCache` NSCache singleton in ProfileAvatarView: eliminates scroll flicker (Phase 8E.1)
- Relay-fetched profiles persisted to GRDB; Phase B refresh merges instead of overwriting (Phase 8E.1)
- Bundle identifier: `golf.raid.app`
- 314 unit/integration tests passing
- UX Contract v1.1 locked (A.1-A.11)

### Not Yet Built
- Activity feed subscription (real-time, outbox-routed) — Phase 8E.2 (8C complete; persistent connections still deferred)
- NIP-51 Favorites extended UX (beyond current kind 30000 Favorites list) — Phase 8E.2+
- Handicaps
- Competition formats
- Attestation (score verification by playing partners)
- Economic incentives

This roadmap defines how those layers are added **without breaking Phase 0**.

---

## Milestone 1 — Productization (Analytics App) ✅ COMPLETE

> Completed 2026-02-13. Production hardening done, TestFlight uploaded.

**Goal:** Replace scripts and spreadsheets with a usable application.

### Scope
- Native app (iOS or desktop) — ✅ iOS (SwiftUI + GRDB)
- CSV import — ✅ Rapsodo MLM2Pro via fileImporter
- Session list + detail view — ✅ SessionsView + PracticeSummaryView
- Club-level analytics — ✅ A-only trends with pinned templates
- A/B/C breakdowns — ✅ Per-session, per-club via club_subsessions
- Validity indicators — ✅ Shot count thresholds

### Production Hardening (iOS Phase 5) — ✅ COMPLETE
- Error handling polish — COMPLETE (2026-02-11)
- First-run experience — COMPLETE (2026-02-11)
- Nostr round sharing — COMPLETE (2026-02-12)
- User docs (README, TestFlight notes) — COMPLETE (2026-02-13)
- Release build validation (archive, TestFlight upload) — COMPLETE (2026-02-13)

### Kernel Impact
- **None** (extended with template_preferences as non-kernel product layer)
- Uses existing Phase 0 kernel as-is

### Success Criteria
- Non-technical users can analyze sessions end-to-end — ✅
- Spreadsheet workflow fully replaced — ✅
- TestFlight build available for beta testers — ✅

---

## Milestone 1.5 — Shot Persistence (Explainability Foundation) ✅ COMPLETE

> Completed as part of iOS port Phase 2.3b + Phase 4C (2026-02-06/07).

**Goal:** Enable explainability and trustworthy trends.

### New Capabilities
- Shot-level persistence (append-only) — ✅ `shots` table with immutability triggers
- Session ↔ club ↔ shot relationships — ✅ FK to sessions, indexed by club
- Per-shot fact storage — ✅ All 14 normalized metrics + raw_json + provenance fields

### Constraints
- Shots are immutable facts — ✅ BEFORE UPDATE/DELETE triggers
- Corrections occur via append-only annotations
- Subsessions remain derived views
- No per-shot UI or replay features yet

### Kernel Impact
- **None**
- Adds new fact tables only (additive, non-kernel change)

### Unlocks
- Explainable A/B/C distributions — ✅ (via worst_metric classification on shot data)
- Dominant failure mode identification
- Template validation with confidence
- Foundation for trustworthy trends — ✅ (A-only trends use shot-level classification)

---

## Milestone 2 — Multiplayer Rounds + NIP-101g (Same-Device) ✅ COMPLETE

> Completed 2026-02-13. All 4 sub-phases done in 2 days (2026-02-12 to 2026-02-13).
> Priority pivot (2026-02-12): Multiplayer and structured Nostr events moved ahead of practice analytics.

**Goal:** Same-device multiplayer scoring with NIP-101g structured event publishing.

### Scope — All Complete

#### 2A: NIP-101g Event Builder ✅
- Kind 1501 (round initiation): embeds course_snapshot + rules_template with JCS-canonicalized hashes
- Kind 1502 (final round record): per-hole score tags, total, references initiation via `e` tag
- Replaced kind 1 text notes with structured events
- Hash parity verified with CourseSnapshotRepository

#### 2B: Relay Read Infrastructure ✅
- One-shot relay reads via `client.fetchEvents()` with EOSE exit policy
- `fetchFollowList` (kind 3), `fetchProfiles` (kind 0), combined `fetchFollowListWithProfiles`
- Read relays: damus.io, nos.lol, purplepag.es. 5s timeout.
- `NostrReadError` enum for user-facing errors

#### 2C: Player Model + UI ✅
- Schema v5: `round_players` (composite PK, immutable triggers) + `round_nostr` (initiation event ID)
- Player selection: follow list multi-select + manual npub entry via `PublicKey.parse()`
- Kind 1501 published at round creation (background Task)
- Companion kind 1 social note with player mentions + njump.me links

#### 2D: Multi-Player Scoring UI ✅
- Round-robin scoring (P1 → P2 per hole before advancing)
- Per-player progress indicator with finish-gating feedback
- Review scorecard sheet before finishing
- One kind 1502 per player (multiplayer), companion kind 1 with all scores
- `RoundShareBuilder` multi-player overloads

### Kernel Impact
- **None**
- Scorecard tables are non-kernel (round_players/round_nostr have immutability triggers but are kernel-adjacent)
- NIP-101g events are projections (derived from local facts)

### Success Criteria — All Met ✅
- ✅ Create a round with 2+ players on one device
- ✅ Enter scores per player per hole (round-robin flow)
- ✅ Review scorecard with score-to-par for each player
- ✅ Publish round as NIP-101g structured events (verifiable by any client)
- ✅ Add players from Nostr follow list by npub
- ✅ 160+ tests passing

### References
- `docs/nips/nip101g_round_wip.md`
- `docs/private/multiplayer-competition-model.md`

---

## Milestone 3 — Multi-Device Rounds ✅ COMPLETE

> Completed 2026-02-15 (iOS Phase 7). Tested on two physical devices.

**Goal:** Each player scores on their own device. Rounds sync via Nostr relays.

### Scope — All Complete
- Round invite sharing (nevent bech32 + QR code + NIP-21 `nostr:` URI)
- "Join a Round" flow (fetch initiation event, verify hashes, create local round)
- Score sync via kind 30501 replaceable events (manual refresh)
- Post-round: fetch other players' kind 1502 final records, merge into combined scorecard
- NIP-17 DM invites to players with inbox relay routing (kind 10050)

### Kernel Impact
- **None**

### Success Criteria — All Met ✅
- ✅ Player A creates round on Device A, Player B joins on Device B
- ✅ Both score independently, see each other's progress
- ✅ Both publish final round records referencing same initiation

---

## Milestone 3.5 — Nostr Protocol Hardening (Phase 8A-8F)

> In progress. Detailed spec: `docs/private/nostr_integration_plan.md`

**Goal:** Complete Nostr integration: identity, relay management, guest mode, social features.

### Phases

| Phase | Name | Status |
|-------|------|--------|
| 8A | Identity & Connection Foundations | ✅ COMPLETE (2026-02-15) |
| 8B | Profile Management (kind 0, edit profile, nav restructure) | ✅ COMPLETE (2026-02-18) |
| 8C | NIP-65 Relay List Metadata (user-configurable relays) | ✅ COMPLETE (2026-02-18) |
| 8D.A | Guest Mode & Delayed Activation + Profile Cache | ✅ COMPLETE (2026-02-17) |
| 8D.B | Social Interactions + Thread UX + Clubhouse | ✅ COMPLETE (2026-02-18) |
| 8E | Follow List Publishing & Social Feed (outbox routing) | 🔄 PARTIAL — 8E.1 COMPLETE (2026-02-21); 8E.2 not started |
| 8F | Practice Data Portability (optional) | Not started |

### Kernel Impact
- **None** — All Nostr work is projection-layer

---

## Milestone 4 — Attestation + Trust Layer

**Goal:** Enable verifiable score confirmation by playing partners.

### Scope
- Marker attestation events (NIP-101g kind 1zzz)
- Attestation UI (confirm/dispute another player's final scores)
- Verification display (show attestation status on round detail)
- Trust chain: initiation → final record → attestation

### Kernel Impact
- **None**
- Attestations are immutable facts in a parallel domain

### Success Criteria
- Playing partner can attest to scores
- Round detail shows attestation status
- Verifier can reconstruct trust chain from relay events

---

## Milestone 5 — Aggregate Trends & Temporal Modeling

> Moved back from original Milestone 2 position. Practice analytics improvements deferred to focus on multiplayer + Nostr.

**Goal:** Enable real longitudinal analysis with explainability.

### Scope
- Rolling time windows (7d / 30d / 90d)
- Trend charts (A% over time, club-level trends)
- Session-to-session comparisons
- Retrospective re-analysis with new templates

### Kernel Impact
- **None** — trends are derived projections only

---

## Milestone 6 — Deterministic Insights (Optional AI Assist)

> Moved back from original Milestone 3 position.

**Goal:** Increase perceived value without risk.

### Scope
- Deterministic insight flags (strike volatility, speed vs contact stability, spin-limited patterns)
- Optional AI explanation layer (summary-only, no rule/fact mutation)

### Kernel Impact
- **None**

---

## Milestone 7 — Round Analytics + Course Discovery

> Combines original Milestone 5 (Round Analytics) + NIP-101g course containers (33501).

**Goal:** Make rounds as valuable as practice data. Enable course discovery on Nostr.

### Scope
- FIR / GIR / putts
- Round-to-round trends
- Practice ↔ round correlations
- Course container events (kind 33501, addressable, replaceable)
- Course search/lookup from relays

### Kernel Impact
- **None** — analytics are projections, 33501 is discovery layer

---

## Milestone 8 — Competition Templates (Skins, Nassau, etc.)

**Goal:** Enable structured games deterministically.

### Scope
- Competition templates (skins, Nassau, match play, Stableford)
- Templates define scoring rules, carry/push logic, handicap application, payout logic
- Competition rules are **templates** → outcomes are **derived projections**
- Rule changes ⇒ new template hash

### Kernel Impact
- **None** — same template kernel, new template kind

### References
- `docs/private/multiplayer-competition-model.md`

---

## Milestone 9 — Handicap Engine

**Goal:** Match core Grint utility with higher trust.

### Scope
- Handicap calculation templates
- Versioned logic
- Historical reproducibility
- Optional publication of signed handicap certificates

### Kernel Impact
- **None**
- Handicap rules are templates; index is derived

### Success Criteria
- Users trust the number
- Past handicaps remain explainable

---

## Milestone 10 — Competitive Play (Non-Economic)

**Goal:** Structured competition without money.

### Scope
- Events
- Leagues
- Challenges
- Verified outcomes

### Kernel Impact
- **None**
- Uses competition templates + projections

---

## Milestone 11 — Bitcoin-Native Challenges

**Goal:** Introduce economic incentives safely.

### Phase 11A — Non-Custodial Challenges
- Lightning / zaps
- Deterministic outcomes
- App never holds funds

### Phase 11B — Verifiable Resolution
- Outcomes reference:
  - attested facts
  - competition template hash
- Disputes resolved via data transparency

### Kernel Impact
- **None**
- Betting operates entirely on projections + attestations

---

## Mental Model: Layer Stack

1. **Truth Layer**
   - shots
   - strokes
   - rounds
   - attestations

2. **Standards Layer**
   - KPI templates
   - competition templates
   - handicap templates

3. **Projection Layer**
   - analytics
   - scorecards
   - outcomes
   - summaries

4. **Economic Layer**
   - challenges
   - payouts
   - settlements

Higher layers may never mutate lower ones.

---

## Explicitly NOT Authorized by This Roadmap

This roadmap does **not** authorize:

- mutating historical facts
- editing templates after use
- recomputing template hashes on read
- importing projections into authoritative tables
- redefining past outcomes without a new template hash

Any such change is a **kernel change** and requires explicit revision of the Kernel Contract.

---

## Final Note

This roadmap is intentionally conservative.

Most products start with:
> social → engagement → monetization

RAID starts with:
> integrity → standards → trust → incentives

That ordering is the moat — and the kernel is what makes it possible.
