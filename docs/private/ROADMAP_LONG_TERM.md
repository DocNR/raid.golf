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

> Updated 2026-02-10 after KPI Template UX sprint merge to main.

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
- Scorecard v0 (kernel-adjacent, sandbox status)
- 96 unit/integration tests passing

### Explicitly Missing
- ~~Shot persistence~~ (DONE)
- ~~On-course rounds~~ (Scorecard v0 shipped, sandbox status)
- Social sharing (Nostr)
- Handicaps
- Competition formats
- Economic incentives
- Production hardening (iOS Phase 5 — next)

This roadmap defines how those layers are added **without breaking Phase 0**.

---

## Milestone 1 — Productization (Analytics App) ✅ FEATURE-COMPLETE

> Status updated 2026-02-10. Feature work done; production hardening (Phase 5) pending.

**Goal:** Replace scripts and spreadsheets with a usable application.

### Scope
- Native app (iOS or desktop) — ✅ iOS (SwiftUI + GRDB)
- CSV import — ✅ Rapsodo MLM2Pro via fileImporter
- Session list + detail view — ✅ SessionsView + PracticeSummaryView
- Club-level analytics — ✅ A-only trends with pinned templates
- A/B/C breakdowns — ✅ Per-session, per-club via club_subsessions
- Validity indicators — ✅ Shot count thresholds

### Production Hardening (iOS Phase 5)
Before moving to Milestone 2, the app needs production-readiness work:
- Release build sanity (archive, physical device, file import permissions)
- Export/share foundation (session summary JSON, share sheet)
- Error handling polish (replace silent `try?` with actionable messages)
- First-run experience (empty states, template explanation, import CTA)
- UX contract + docs (user-facing README, TestFlight notes, known limitations)
- Local debug screen (db version, template/session/subsession counts)

See `docs/private/ios-port-plan.md` Phase 5 for execution details.

### Out of Scope
- Nostr
- Social feeds
- Betting
- On-course scoring (Scorecard v0 shipped separately as sandbox)

### Kernel Impact
- **None** (extended with template_preferences as non-kernel product layer)
- Uses existing Phase 0 kernel as-is

### Success Criteria
- Non-technical users can analyze sessions end-to-end — ✅ (pending Phase 5 polish)
- Spreadsheet workflow fully replaced — ✅ (pending export/share in Phase 5)

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

## Milestone 2 — Aggregate Trends & Temporal Modeling

**Goal:** Enable real longitudinal analysis with explainability.

### New Capabilities
- Rolling time windows (7d / 30d / 90d)
- Trend charts (A% over time, club-level trends)
- Session-to-session comparisons
- Retrospective re-analysis with new templates

### Foundation
- Built on shot persistence from Milestone 1.5
- Trends operate on subsession aggregates
- Underlying shot data provides:
  - root-cause analysis
  - confidence in template stability
  - validation of trend signals

### Kernel Impact
- **None**
- Trends are derived projections only

### Unlocks
- True improvement tracking
- Coach workflows
- Betting integrity prerequisites

---

## Milestone 3 — Deterministic Insights (Optional AI Assist)

**Goal:** Increase perceived value without risk.

### Scope
- Deterministic insight flags (non-AI):
  - strike volatility
  - speed vs contact stability
  - spin-limited patterns
- Optional AI explanation layer:
  - summary-only
  - no rule mutation
  - no fact mutation

### Kernel Impact
- **None**
- AI operates strictly outside the kernel

### Success Criteria
- Users learn something actionable without rule drift

---

## Milestone 4 — On-Course Scoring (Local-Only)

**Goal:** Enter Grint territory without social complexity.

### Scope
- Rounds
- Holes
- Stroke entries (append-only)
- Player vs marker separation
- Attestations
- Offline support

### Design Notes
- Rounds are a **parallel fact domain**
- Scorecards are derived projections
- Corrections require new entries and/or re-attestation

### Kernel Impact
- **None**
- Parallel immutable fact system

### Success Criteria
- Complete round lifecycle works locally
- Attestation model is enforceable

### References
- /Users/danielwyler/raid.golf/docs/specs/course_identity_and_snapshots.md
- /Users/danielwyler/raid.golf/docs/private/multiplayer-competition-model.md
- /Users/danielwyler/raid.golf/docs/private/nip-101g.md

---

## Milestone 5 — Round Analytics

**Goal:** Make rounds as valuable as practice data.

### Scope
- FIR / GIR / putts
- Round-to-round trends
- Practice ↔ round correlations

### Kernel Impact
- **None**
- Analytics are derived projections

### Success Criteria
- Rounds feel analyzed, not just logged

---

## Milestone 6 — Nostr Projection Layer (Opt-In)

**Goal:** Add social capability without centralization.

### What Gets Published
- Practice milestones
- Round summaries
- Signed attestations
- Benchmark templates

### What Never Gets Published
- Raw shots
- Raw strokes
- Private notes
- Editable scorecards

### Kernel Impact
- **None**
- Nostr consumes projections only

### Success Criteria
- Users voluntarily publish
- App remains fully functional offline

### References
- /Users/danielwyler/raid.golf/docs/private/multiplayer-competition-model.md

---

## Milestone 7 — Competition Templates (Skins, Nassau, etc.)

**Goal:** Enable structured games deterministically.

### Scope
- Competition templates:
  - skins
  - Nassau
  - match play
  - Stableford
- Templates define:
  - scoring rules
  - carry / push logic
  - handicap application
  - payout logic

### Design Rule
- Competition rules are **templates**
- Outcomes are **derived projections**
- Rule changes ⇒ new template hash

### Kernel Impact
- **None**
- Same template kernel, new template kind

### References
- /Users/danielwyler/raid.golf/docs/private/multiplayer-competition-model.md

---

## Milestone 8 — Handicap Engine

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

## Milestone 9 — Competitive Play (Non-Economic)

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

## Milestone 10 — Bitcoin-Native Challenges

**Goal:** Introduce economic incentives safely.

### Phase 10A — Non-Custodial Challenges
- Lightning / zaps
- Deterministic outcomes
- App never holds funds

### Phase 10B — Verifiable Resolution
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
