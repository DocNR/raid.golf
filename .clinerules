# AI Agent Instructions — RAID Phase 0 (MVP)

If any RAID Phase 0 instruction conflicts with the Strike Quality Practice System instructions below, follow RAID Phase 0 requirements and **explicitly flag the conflict** instead of guessing.

## Authority & Scope (Phase 0 Only)
- **Authority order:** PRD (`docs/PRD_Phase_0_MVP.md`) > Schema Brief (`docs/schema_brief/*`) > Reference Test Matrix (`docs/reference_test_matrix.md`).
- **Scope locked to Phase 0** MVP requirements only. Anything beyond Phase 0 is out of scope.

## Non‑Negotiable Rules (Phase 0)
- **SQLite is authoritative** for persisted data; JSON is serialization/export only.
- **Immutability enforced:** sessions, club sub-sessions, and KPI templates never mutate.
- **No template_hash recomputation** after storage; stored hash is authoritative.
- **Projections are derived only** and must NOT be imported as authoritative data.
- **No silent filtering:** validity/status must be visible in outputs and queries.

## STOP Conditions (Ask Before Proceeding)
- A **schema change (including additive changes)** is required.
- An **invariant must be relaxed**.
- **Ambiguity or missing requirement** in PRD/brief.
- Request is **outside Phase 0 scope**.

## Testing Guidance
- When writing tests, align with **docs/reference_test_matrix.md**.

---

# AI Agent Instructions — Strike Quality Practice System

This project defines a **canonical, versioned golf practice system**.
The AI agent is a collaborator, not an authority.

---

## Canonical Sources
The following files are authoritative and must not be modified without explicit instruction:

- docs/Strike_Quality_Practice_Session_Plan.md
- README.md
- CHANGELOG.md
- data/templates/*

If a suggestion conflicts with these documents, the agent must flag the conflict instead of changing behavior.

---

## Session Ingest & Analysis Workflow (Critical)

### Raw Session Logs
- All raw exports live in `data/session_logs/`
- These files are **immutable**
- The agent must NEVER edit, rewrite, or normalize raw session logs

### Rapsodo-Specific Handling
- Rapsodo CSV exports may include footer rows such as:
  - `Average`
  - `Std. Dev.` / `Std Dev`
- These rows are **not shots** and MUST be excluded from shot-level analysis
- A valid shot row is one where:
  - Club is a real club label (e.g., `7i`, `5i`, `PW`)
  - Key numeric fields (carry, ball speed, spin, descent) parse as numbers

Footer rows must be filtered out explicitly before classification.

### Script Entrypoint
- Use `tools/scripts/analyze_session.py` to analyze new session logs
- KPI thresholds are defined in `tools/kpis.json`
- The script must accept:
  - A CSV path
  - Optional device flag (`--device rapsodo|trackman`)
  - Optional location flag (`--location`)

Expected artifacts (written only to `data/summaries/`):
- `session_summary.csv`
- `a_shot_trends.csv`
- `ingest_report.md`

These artifacts are **derived outputs** only.  
SQLite remains the authoritative datastore per RAID Phase 0 rules; CSV/markdown files must be regenerable and are not canonical.

---

## Derived Outputs
- All derived or aggregated data must be written **only** to `data/summaries/`
- Derived data is:
  - Regenerable
  - Non-canonical
  - Never edited manually

Acceptable derived outputs include:
- Session-level A/B/C summaries
- A-shot-only averages
- Rolling trends by club
- Human-readable ingest reports

---

## Version Propagation (Required)

- All classification-based outputs MUST include an explicit `kpi_version`.
- `kpi_version` must be sourced from `tools/kpis.json`:
  - Use club-specific `kpi_version` when present
  - Otherwise use `default_kpi_version`
- The agent must NEVER infer or rewrite KPI versions.
- Historical data remains tagged with the version used at time of analysis.

Template identity rule: the stored `template_hash` is authoritative and MUST NOT be recomputed on read or reuse.

---

## Allowed Agent Actions
The agent may:
- Analyze session CSV files
- Classify shots using current KPI thresholds
- Propose KPI adjustments (with justification)
- Summarize trends across sessions
- Generate derived summaries in `data/summaries/`
- Draft proposed changes for review

---

## Disallowed Agent Actions
The agent must NOT:
- Change KPIs retroactively
- Modify practice rules without a version bump
- Introduce new metrics casually
- Add new canonical documents without justification
- Optimize for speed or distance at the expense of strike quality
- Store interpretations inside raw data folders

---

## Versioning Rules
- Practice system changes require a version bump
- KPI changes require:
  - ≥ 3 sessions
  - ≥ 25 A-shots
  - Stable variance
- Old data remains valid under its original version

---

## Operating Principle
Quality-filtered data > volume  
Consistency > novelty  
Explicit decisions > implicit drift