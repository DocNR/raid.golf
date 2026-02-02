# RAID Golf — Rapsodo A-shot Integrity & Discipline

A structured, versioned golf practice framework focused on **strike quality**, **repeatability**, and **data integrity**.

This project defines *how* practice is conducted, *what* data counts, and *how* performance metrics evolve over time without drifting.

---

## Project Goals

- Increase **A-shot percentage** (clean, repeatable strikes)
- Separate **speed**, **technique**, and **performance** work
- Produce **stable gapping and KPI data**
- Avoid reinterpretation of past results as technique or speed changes

---

## Phase 0 Architecture

RAID Phase 0 establishes a **local-first, immutable data architecture** that prioritizes integrity over convenience.

### Key Design Principles

- **SQLite is authoritative** — All persisted data lives in SQLite; JSON is export-only
- **Content-addressed templates** — KPI templates identified by SHA-256 hash of canonical JSON
- **Immutable after creation** — Sessions, sub-sessions, and templates cannot be modified
- **No raw shot storage** — Phase 0 stores only analysis results (sessions and sub-sessions)
- **Decimal-based canonicalization** — Cross-platform determinism via explicit Decimal formatting

### Data Model

```
Session (immutable)
  ├─ session_id, session_date, source_file
  └─ Club Sub-Sessions (immutable)
      ├─ club, shot_count, a_count, b_count, c_count
      ├─ kpi_template_hash (reference to template used)
      └─ validity_status (data quality indicator)

KPI Template (immutable forever)
  ├─ template_hash (SHA-256, primary key)
  ├─ canonical_json (content)
  └─ schema_version, club, created_at
```

### Data Sources

- **Primary:** Rapsodo MLM2Pro CSV exports (mixed-club sessions supported)
- **Planned:** TrackMan CSV support
- **Not Supported:** Target Range exports (different intent/success criteria)

### What Phase 0 Does NOT Store

- Individual shot data (raw shots are analyzed then discarded)
- Swing mechanics or launch monitor metadata beyond classification metrics
- Projections or derived summaries (regenerable from authoritative data)

---

## Kernel & Governance

RAID is built on a protected **integrity kernel** that guarantees:
- Immutable facts (sessions, sub-sessions, templates)
- Content-addressed templates (SHA-256 identity)
- Deterministic re-analysis semantics
- Strict derived-data boundaries

The kernel is domain-agnostic and designed to scale beyond practice analytics into on-course scoring, competitions, and economic incentives without breaking trust guarantees.

**Agent/Contributor Constraints:** See `.clinerules/kernel.md` for hard STOP conditions that protect kernel invariants from accidental mutation.

**Governance & Roadmap:** Long-term product roadmap and detailed kernel governance documentation live in `docs/private/` and are intentionally not tracked in version control.

---

## Forking & Local Setup

1. Fork this repo on GitHub.
2. Clone your fork locally.
3. Keep your personal exports and summaries private (see **Data Privacy** below).
4. Run the analyzer against your session exports:

```bash
python tools/scripts/analyze_session.py data/session_logs/<your_export>.csv --device rapsodo
```

---

## Canonical Artifacts

This project intentionally contains only a small number of authoritative files.

### 1. Strike Quality Practice System (Canonical)
- **File:** `docs/Strike_Quality_Practice_Session_Plan.md`
- Defines:
  - The 3-lane training model (Speed / Technique / Strike Quality)
  - Session structure
  - What constitutes an A / B / C shot
  - How practice sessions are run and evaluated

> If a practice idea does not fit within this document, it is not used.

Versioning contract:
- Practice system docs are versioned in both filename and content (e.g., `Strike_Quality_Practice_System_v2.md`).
- Major version bumps change rules, KPIs, or classification logic.
- Minor version bumps are clarifications only.

---

### 2. Gapping & KPI Log (Source of Truth)
- **File:** `data/templates/Strike_Quality_Gapping_KPI_Log.xlsx`
- Two tabs:
  - `Session_Log` → one row per club, per strike-quality session
  - `Club_KPIs` → authoritative KPI thresholds and validation status

All gapping and stock yardages are derived **only from A-shots**.

Spreadsheet versioning contract:
- Rows reference the KPI version used for classification, not the logic itself.
- Templates are implicitly versioned by KPI version.
- Historical rows are never retroactively edited.

---

### 3. CHANGELOG
- **File:** `CHANGELOG.md`
- Records:
  - Practice system version changes
  - KPI version changes
  - Rationale for any structural updates

---

## Practice Philosophy (High Level)

- **Quality > Volume**
- **Count reps, not balls**
- **Do not fix C-shots — exclude them**
- **Never mix training lanes**
- **Never change KPIs retroactively**

---

## Versioning Rules (Summary)

### Practice System
- Minor versions (`v2.1`) → clarifications only
- Major versions (`v3.0`) → rule or KPI logic changes

### KPIs
- Each session logs the KPI version used
- KPIs are only changed after sufficient data accumulation
- Past data is never reclassified under new thresholds

KPIs live in `tools/kpis.json` and are immutable once used. New KPI logic means a new version key (e.g. `v2.1`, `v3.0`).

---

## Typical Workflow

1. Run a session using `docs/Strike_Quality_Practice_Session_Plan.md`
2. Export session data (Rapsodo / TrackMan)
3. Analyze session
4. Log **one row** in `Session_Log`
5. Periodically review club validation status

---

## Current Status

- **Validated club:** 7-iron
- All other clubs: provisional
- System version: v2.0

---

## Non-Goals

This project does **not** attempt to:
- Store raw shot-by-shot data
- Track swing mechanics
- Serve as a swing journal
- Optimize launch conditions independently of strike quality

---

## Data Privacy

This repo is designed to be shareable without exposing personal session data.

- Raw exports in `data/session_logs/*.csv` are ignored by default.
- Derived summaries in `data/summaries/*.csv` are ignored by default.
- Anonymized examples are included for onboarding:
  - `data/session_logs/sample_session_log.csv`
  - `data/summaries/sample_session_summary.csv`

If you publish this repo, keep your personal exports and summaries local.

---

## App Direction

This project can evolve into a lightweight iOS app that:
- imports session CSVs,
- runs KPI classification locally,
- surfaces A-shot trends and summaries.

Nothing in the current structure blocks that path.

---

## Guiding Principle

> *Consistency is trained. Speed is unlocked. Data is filtered.*
