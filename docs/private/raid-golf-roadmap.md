# RAID Golf — Private Roadmap & Business Plan

**Status:** SUPERSEDED — execution tracking moved to `ios-port-plan.md`; product milestones moved to `ROADMAP_LONG_TERM.md`.
**Last updated:** 2026-02-10

> **This document is retained for historical context only.** It was the original business plan and roadmap written before the iOS port began. The active documents are:
> - **Product milestones:** `docs/private/ROADMAP_LONG_TERM.md` (Milestones 1–10)
> - **iOS execution phases:** `docs/private/ios-port-plan.md` (Phases 1–5)
> - **Python implementation phases:** `docs/implementation_phases.md` (Phases A–F, all complete)

This document captures the internal roadmap, risk assessment, and business plan for RAID Golf. It is not intended for public release.

---

## Executive Summary (Non-Inflated)

**Wedge:** Launch monitor analytics with versioned KPIs and local-first data ownership.  
**Moat:** Trustworthy KPI versioning, clean analytics pipeline, and open data model.  
**Primary risk:** Narrow TAM until expanding into on-course scoring or broader social features.  
**Best path:** Dominate LM practice analytics first → add optional social projections via Nostr → expand toward Grint-style features only after traction.

---

## Product Strategy

### Positioning
- “Own your launch monitor data, track true strike-quality, and share highlights when you choose.”
- Lead with analysis, not social. Social is opt-in.

### Primary user archetypes
- Launch monitor owners (Rapsodo, TrackMan, GCQuad)
- Coaches who want consistent KPI-driven feedback
- Data-focused golfers tracking improvement over time

---

## Roadmap (Phased)

### **Phase 0 — Core LM Analytics (MVP)** ✅ COMPLETE

**Goal:** Replace the current spreadsheet workflow with a high-trust analysis app.

Deliverables:
- ✅ CSV ingest for Rapsodo (extend to TrackMan later)
- ✅ Local-first data store + KPI version tagging
- ✅ Session summaries, per-club A/B/C breakdowns
- ✅ Export of summaries (JSON) for manual workflows
- ✅ CLI for all operations (Phase 0.1)

**Completed:** 2026-02-02 (Kernel v2.0 + CLI)

---

### **Phase 0.1-iOS — Swift Kernel Port** *(ACTIVE)*

**Goal:** Port Phase 0 kernel to iOS/Swift as learning infrastructure for on-course scoring.

**Rationale for jumping ahead:**
- On-course scoring (Phase 3) is the real goal
- iOS/Swift competence required regardless
- Phase 0 kernel is stable with cross-platform test vectors
- Better to learn iOS on simpler domain before tackling on-course

**Deliverables:**
- RFC 8785 JCS canonicalization in Swift
- SHA-256 content-addressed hashing (matching Python golden hashes)
- SQLite schema with immutability triggers (UPDATE + DELETE blocked)
- Repository layer (hash-once-on-insert, never-rehash-on-read)
- Rapsodo CSV ingest (parity with Python)
- Minimal SwiftUI viewer (sessions, details, trends)

**Critical risk:** RFC 8785 number serialization — Foundation JSON mangles floats. Must use token-preserving parse, not Double round-trip.

**Exit criteria:**
- All 12 JCS test vectors pass
- All golden template hashes match exactly
- Ingest produces identical results to Python

**Detailed plan:** `docs/private/ios-port-plan.md`

**What this skips (for now):**
- Phase 0.2 shot persistence (not needed for on-course)
- Phase 0.3 advanced trends
- Phase 0.5 AI assist

---

### **Phase 0.2 — Minimal Shot Persistence (Explainability Layer)** *(DEFERRED)*

**Purpose:**
Introduce immutable, per-shot fact storage to support **template validation, explainability, and trustworthy trends**.

This phase does **not** change kernel rules, template semantics, or analytics logic.
It adds a new immutable fact layer that records *what happened*, not *what it means*.

**Scope (Strictly Limited):**

* Persist each shot as an immutable fact:
  * session_id
  * subsession_id
  * shot_index
  * club
  * raw measured metrics
  * template_hash used for evaluation
* No per-shot scoring UI
* No replay or visualization
* No ML or statistical modeling
* No kernel or template changes

**What This Enables:**

* Explain *why* A/B/C distributions occur
* Identify dominant failure modes per session
* Debug and refine templates with confidence
* Make aggregate trends interpretable (not just numeric)

**What This Does NOT Enable (Yet):**

* Shot re-evaluation under new templates
* Historical backfills
* Advanced trend analytics
* User-facing shot timelines

**Why This Comes Before Trends:**
Aggregate trends without shot persistence are numerically correct but semantically weak.
Shot persistence ensures trends are explainable and trustworthy before they are emphasized.

---

### **Phase 0.3 — Aggregate Trends (Now Explainable)** *(DEFERRED)*

**Goal:** Enable trend calculations with explainability.

With shot persistence in place:

* Trends operate on subsession aggregates as before
* Underlying shot data provides:
  * root-cause analysis
  * confidence in template stability
  * validation of trend signals

No changes to trend computation logic are required—only improved interpretability.

**Deliverables:**
- Trend charts (rolling averages, A% over time)
- Club-level trend analysis
- Session-to-session comparisons

---

## **Key Note (Do Not Remove)**

> Shot persistence is an **additive, non-kernel change**.
> All kernel invariants remain intact:
>
> * templates immutable
> * facts append-only
> * derived state reproducible

---

### **Phase 0.5 — AI Assist (Optional / Experimental)** *(DEFERRED)*

**Goal:** Provide interpretations without overpromising coaching.

Deliverables:
- AI-generated insights based on summary statistics (not raw shots)
- Clear opt-in, privacy messaging, and output disclaimers
- NO auto-adjusting KPIs; AI can only suggest

Risks:
- Bad advice erodes trust
- Privacy concerns if raw data leaves device
- Ongoing API cost

Safer approach:
- Start with deterministic insights; add AI for explanation only
- Consider “bring your own API key” or paid tier to manage cost

---

### **Phase 1 — Social Projections (Nostr Optional)**
**Goal:** Enable sharing without exposing raw data.

Deliverables:
- Publish practice session summaries & PR milestones as projections
- Minimal feed of followed users
- Zaps/tips on PRs (optional)

Success signals:
- Users publish projections voluntarily
- Engagement beyond private analytics

---

### **Phase 2 — Community & Challenges**
**Goal:** Build retention with challenges and streaks.

Deliverables:
- Challenge cards (e.g., A% improvement streaks)
- Progress tracking and badges
- Optional zap-based rewards (no formal wagering yet)

Success signals:
- Users return for progression, not just uploads

---

### **Phase 3 — Toward Grint Territory**
**Goal:** Add on-course scoring and golf-round social features.

Deliverables:
- Scoring module (reuse NIP-101g concepts)
- Course discovery, GPS, round history
- Social rounds + leaderboard features

Critical note:
- This is a new product class; don’t begin until LM analytics has traction.

---

## Nostr Strategy (Critical Constraints)

Principles:
- Local-first is canonical; Nostr is a service layer.
- Projections are opt-in and limited to summaries or milestones.
- Do not require users to understand keys or relays to get value.

Risk: Nostr adoption in golf is low. This should be a *feature*, not the wedge.

---

## Business Model (Realistic Options)

### 1) Freemium + Pro Analytics
- Free: ingest + basic summaries
- Paid: advanced trends, anomaly detection, alerts

### 2) Coach / Team Workspaces
- Paid private relay + roster analytics
- Optional white-label for academies

### 3) Template Packs / Practice Plans
- Paid practice frameworks (from coaches or pro users)

### 4) Managed Relay / Encrypted Backups
- Subscription for encrypted backup + private sharing

Reality check:
- “Open source + public relays + zaps” is not a business by itself.
- Monetization must come from analytics, coaching, or managed services.

---

## AI Analysis (Feasibility & Guardrails)

### Feasible implementation
- Use summary stats only (A%, carry, spin, dispersion, KPI deltas)
- Generate explanations and highlight outliers

### Not recommended early
- Prescriptive coaching (high risk)
- Auto-updating KPIs

### Cost + privacy
- Using your API key incurs ongoing cost and liability
- Consider paid tier or BYOK

---

## Key Risks (Explicit)

1. **Narrow TAM** without on-course features
2. **Social adoption** may be low in golf/Nostr
3. **Ingest fragmentation** (CSV format variance)
4. **AI trust** if advice is off
5. **Competing with Grint** requires enormous scope & data network

---

## Tactical Priorities (Next 90 Days)

1. ✅ ~~Finish Rapsodo ingest + KPI versioning pipeline~~ (Complete)
2. ✅ ~~Design local database schema for sessions + summaries~~ (Complete)
3. **Port kernel to Swift/iOS** (Phase 0.1-iOS) — ACTIVE
4. Build iOS UI for ingest + session review
5. Validate kernel parity (JCS vectors, golden hashes)
6. Decide whether AI assist is Phase 0.5 or later (deferred)

---

## Key Decision Gates

- **Gate A:** At least 20 consistent users uploading LM exports
- **Gate B:** Users report clear value over spreadsheets
- **Gate C:** Social sharing actually happens before building a full feed

---

## Appendix: Possible Acronym Expansion
**RAID** — Rapsodo A-shot Integrity & Discipline