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
- Added `.clinerules` to enforce RAID Phase 0 constraints for AI-assisted development
- Added Phase 0 PRD (`docs/PRD_Phase_0_MVP.md`) as the authoritative MVP requirements
- Added schema-first implementation brief (`docs/schema_brief/*`) documenting Phase 0 invariants
- Added KPI philosophy and classification guide (`docs/kpi_philosophy_and_classification.md`)
- Added `docs/reference_test_matrix.md` to map high-risk Phase 0 invariants to test scenarios
- Added `data/session_logs/README.md` to enforce raw-export rules
- Added KPI version propagation to session summaries (`kpi_version`) from `tools/kpis.json`
- Documented versioning contract across practice system docs, KPIs, spreadsheets, and derived summaries
- Added forward-only KPI generator with provenance/versioning for KPIs
- Confirmed no behavior changes to `tools/scripts/analyze_session.py`

**Phase A–B: Canonical Identity + Schema-Level Immutability**
- Implemented deterministic canonical JSON transformation (`raid/canonical.py`)
  - Alphabetically sorted keys at all nesting levels
  - Decimal-based numeric normalization (no binary floats)
  - `NumericToken` wrapper ensures correct JSON emission (strings quoted, numbers unquoted)
  - Compact UTF-8 format without BOM
- Implemented SHA-256 content-addressed hashing (`raid/hashing.py`)
  - Golden hashes frozen for test fixtures (Phase A proof)
  - Cross-platform deterministic via Decimal
- Implemented SQLite schema with immutability enforcement (`raid/schema.sql`)
  - Three authoritative tables: `sessions`, `kpi_templates`, `club_subsessions`
  - Immutability enforced via BEFORE UPDATE triggers that ABORT
  - Foreign keys enabled per connection with RESTRICT on deletes
- Implemented repository layer (`raid/repository.py`)
  - Insert and read operations for all authoritative entities
  - Read path does NOT call `canonicalize()` or `compute_template_hash()` (RTM-04)
  - Hardened schema validation (fails loudly on partial schema)
- Validated RTM-01 through RTM-04 with comprehensive tests
  - RTM-01: Sessions immutable after creation
  - RTM-02: Club sub-sessions immutable after creation
  - RTM-03: KPI templates immutable forever
  - RTM-04: Hash not recomputed on read (proven via monkeypatch/spy tests)
- Identity and storage layers now stable
- Added `docs/implementation_phases.md` as a non-authoritative execution roadmap
  - Maps Phase 0 work into six sequential phases (A–F)
  - Each phase groups related RTMs with clear entry/exit criteria and STOP conditions
  - Provides safe stopping points and reduces scope creep
  - Serves as onboarding context for contributors and AI agents

### Planned
- Validation of 5-iron and 6-iron KPIs
- Potential minor clarifications to pressure blocks
- Optional visualization guidance (non-canonical)

---

## Versioning Policy
- **Minor versions (v2.x):** wording clarity, scheduling notes
- **Major versions (v3.0):** KPI logic, lane structure, evaluation rules

Historical data is never reinterpreted under new versions.
