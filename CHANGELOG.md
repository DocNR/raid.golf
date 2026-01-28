# Changelog
All notable changes to the Strike Quality Practice System are documented here.

The format follows a simplified version of Keep a Changelog.
This project versions **behavior and rules**, not files.

---

## [v2.0] — Initial Canonical System
### Added
- Three-lane training model:
  - Lane 1: Speed Training
  - Lane 2: Technique / Constraints
  - Lane 3: Strike-Quality Ball Work
- Formal A / B / C shot classification
- Strike-quality KPIs for 7-iron
- Session structure with safety valves
- Explicit separation of training intent
- Gapping & KPI Log spreadsheet (Excel)
- KPI versioning and validation rules

### Notes
- 7-iron is the only validated club at this version
- All other clubs are provisional pending data
- This version establishes the canonical practice framework

---

## [Unreleased]
### Added
- Adopted structured folders (`docs/`, `data/`, `tools/`) for canonical, raw, and working artifacts
- Added `.clinerule` with AI agent guardrails
- Added `data/session_logs/README.md` to enforce raw-export rules
- Added KPI version propagation to session summaries (`kpi_version`) from `tools/kpis.json`
- Documented versioning contract across practice system docs, KPIs, spreadsheets, and derived summaries
- Added forward-only KPI generator with provenance/versioning for KPIs
- Confirmed no behavior changes to `tools/scripts/analyze_session.py`
### Planned
- Validation of 5-iron and 6-iron KPIs
- Potential minor clarifications to pressure blocks
- Optional visualization guidance (non-canonical)

---

## Versioning Policy
- **Minor versions (v2.x):** wording clarity, scheduling notes
- **Major versions (v3.0):** KPI logic, lane structure, evaluation rules

Historical data is never reinterpreted under new versions.
