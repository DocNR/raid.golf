# KPI Generation PRD (Forward-Only)

## 1) Background / Current State
- `tools/kpis.json` contains a manually-defined KPI version (v2.0).
- v2.0 thresholds (smash, ball speed, spin, descent) were derived from an existing dataset and validated manually.
- These thresholds are frozen and must never be regenerated or modified.
- This version represents the **hand-validated baseline** and must remain the active compatibility surface.

## 2) Problem Statement
We need a deterministic, script-based way to generate **new KPI versions** (e.g., v2.1, v3.0) from baseline session CSVs, while keeping historical KPI versions immutable and untouched.

## 3) Inputs
- Rapsodo MLM2Pro “Shot Export” CSV files.
- CSV structure may include:
  - Non-data rows at top (title / metadata)
  - Header row with metric names
  - Possible footer rows (Average / Std Dev)
- Sessions may contain mixed clubs, but the generator should target **one club at a time**.

## 4) Valid Shot Definition (CRITICAL)
Valid shot rows must satisfy:
- Required metrics are present and numeric.
- Exclude Average / Std Dev / blank rows.
- Non-numeric or missing values disqualify the row.

## 5) KPI Metrics (v1 generator scope — LOCKED)
The generator **may ONLY** operate on:
- `ball_speed`
- `smash_factor`
- `descent_angle`
- `spin_rate`

All KPI metrics in v1 are **higher-is-better**. No lower-is-better metrics are supported in this version.

Do **NOT** introduce swing-theory metrics (AoA, path, face angle, etc.).

## 6) Outlier Policy
- No winsorization.
- Drop rows only if required metrics are missing, non-numeric, or clearly non-shot rows (e.g., footer summaries).
- No statistical trimming (e.g., percentile clipping, IQR filtering) is allowed in v1.
- Be explicit about rejection rules in generated metadata.

## 7) Threshold Methodology
- Percentile-based thresholds computed from the baseline dataset.
- Explicit A/B/C definitions (per metric, per club):
  - **A ≥ 70th percentile**
  - **B = 50th–70th percentile**
  - **C < 50th percentile**
- Percentiles must be computed using a deterministic, documented method (e.g., nearest-rank or explicit interpolation rule) and recorded in metadata.

## 8) KPI Versioning Rules
- Existing version(s) (e.g., v2.0) are **`manual_locked`**.
- New versions are **`percentile_baseline`**.
- Generator must:
  - **Append new versions only**.
  - **Never rewrite or delete existing versions**.
- Each version must record:
  - `kpi_version`
  - `created_at`
  - `method` (`manual_locked` | `percentile_baseline`)
  - `source_session` (CSV filename)
  - `club`
  - `n_shots_total` / `n_shots_used`
  - `filters_applied`
  - `metric thresholds`

## 9) Output Schema
Extend `tools/kpis.json` in a backward-compatible way:
- Preserve current structure (`default_kpi_version`, `clubs.<club>.kpi_version`, `a/b/c`).
- Add a `versions` map per club for append-only history.
- Keep `default_kpi_version` and `clubs.<club>.kpi_version` as active pointers.

## 10) Acceptance Criteria
- v2.0 thresholds remain **unchanged** under `clubs.7i.a/b/c`.
- Generator can create v2.1 without altering v2.0.
- Same CSV → same thresholds (deterministic).
- `analyze_session.py` behavior and outputs remain unchanged when using existing v2.0 KPIs.