# Reference Test Matrix — RAID Phase 0 (MVP)

This document maps **Phase 0 invariants** to **high‑risk test scenarios**. It is a specification guide for implementing tests in Python now and in Swift later (hashing/determinism parity).

## How to use this matrix
- Each test case maps a requirement to a concrete scenario with setup/action/expected result.
- Implement tests in Python first using fixtures described here, then mirror them in Swift.
- When a test mentions “golden hash,” compute it once using the canonical Python implementation and freeze it as the expected value.

## Table of contents
- [RTM-01 Session immutability](#test-case-id-rtm-01)
- [RTM-02 Sub-session immutability](#test-case-id-rtm-02)
- [RTM-03 KPI template immutability](#test-case-id-rtm-03)
- [RTM-04 Hash not recomputed on read](#test-case-id-rtm-04)
- [RTM-05 Duplicate analysis prevented](#test-case-id-rtm-05)
- [RTM-06 Re-analysis with different template](#test-case-id-rtm-06)
- [RTM-07 Validity thresholds](#test-case-id-rtm-07)
- [RTM-08 A% null when invalid](#test-case-id-rtm-08)
- [RTM-09 Low/invalid stored](#test-case-id-rtm-09)
- [RTM-10 No silent filtering](#test-case-id-rtm-10)
- [RTM-11 Canonical key ordering](#test-case-id-rtm-11)
- [RTM-12 Compact JSON + UTF‑8](#test-case-id-rtm-12)
- [RTM-13 Numeric normalization](#test-case-id-rtm-13)
- [RTM-14 Hash determinism (Python↔Swift)](#test-case-id-rtm-14)
- [RTM-15 Projection regeneration + no import](#test-case-id-rtm-15)
- [RTM-16 Derived data isolation](#test-case-id-rtm-16)
- [RTM-17 Multi‑club ingest](#test-case-id-rtm-17)

---

### Hashing fixtures (reference only)
Use these **three JSON fixtures** in hashing-related tests. Do **not** hardcode hash values here; compute them via the canonical Python implementation and freeze as golden values in tests.

**Fixture A — Minimal template**
```json
{"schema_version":"1.0","club":"7i","metrics":{"ball_speed":{"a_min":100,"b_min":90,"direction":"higher_is_better"}},"aggregation_method":"worst_metric"}
```

**Fixture B — Nested keys ordering**
```json
{"club":"7i","schema_version":"1.0","metrics":{"smash_factor":{"direction":"higher_is_better","b_min":1.29,"a_min":1.32},"ball_speed":{"b_min":106.6,"direction":"higher_is_better","a_min":108.92}},"aggregation_method":"worst_metric"}
```

**Fixture C — Numeric edge cases**
```json
{"schema_version":"1.0","club":"7i","metrics":{"spin_rate":{"a_min":1.0,"b_min":1,"direction":"higher_is_better"},"descent_angle":{"a_min":0.001,"b_min":100,"direction":"higher_is_better"}},"aggregation_method":"worst_metric"}
```

---

#### Test Case ID: RTM-01
- **Invariant(s):** Sessions MUST be immutable after creation.
- **Risk addressed:** Historical session data can be mutated, invalidating trends and provenance.
- **Scenario:** Attempt to update session metadata after ingestion.
- **Setup (fixtures):** Create a session with `session_date`, `source_file`, `device_type`, `location`, `ingested_at`.
- **Action:** Update any immutable field (e.g., `source_file`).
- **Expected:** Update is rejected with a clear error; stored row remains unchanged.

#### Test Case ID: RTM-02
- **Invariant(s):** Club sub-sessions MUST be immutable after creation.
- **Risk addressed:** Analysis results can be silently altered.
- **Scenario:** Attempt to update sub-session metrics or template reference.
- **Setup (fixtures):** Create a sub-session with `shot_count`, `a_count`, `kpi_template_hash`, `validity_status`.
- **Action:** Update `a_count` or `kpi_template_hash`.
- **Expected:** Update is rejected with a clear error; stored row remains unchanged.

#### Test Case ID: RTM-03
- **Invariant(s):** KPI templates MUST be immutable forever.
- **Risk addressed:** Template identity no longer matches content.
- **Scenario:** Attempt to update `canonical_json` or `schema_version` after insert.
- **Setup (fixtures):** Insert a template using Fixture A.
- **Action:** Update `canonical_json`.
- **Expected:** Update is rejected; stored template remains unchanged.

#### Test Case ID: RTM-04
- **Invariant(s):** Template hashes MUST NOT be recomputed after storage.
- **Risk addressed:** Read path performs re-hash and fails due to canonicalization drift.
- **Scenario:** Retrieve a template and ensure no recomputation is required to validate identity.
- **Setup (fixtures):** Insert a template and store the computed hash.
- **Action:** Fetch template by hash via normal read path.
- **Expected:** Read succeeds without re-hashing; stored hash is trusted as authoritative. Assert via code-path inspection or by mocking/spying to ensure canonicalization + hashing are NOT invoked on read.
- **Notes:** Integrity checks (optional) must be out-of-band, not on normal read.

#### Test Case ID: RTM-05
- **Invariant(s):** Duplicate analysis MUST be prevented by UNIQUE (`session_id`,`club`,`kpi_template_hash`).
- **Risk addressed:** Duplicate sub-sessions corrupt reports.
- **Scenario:** Analyze same session/club/template twice.
- **Setup (fixtures):** One session + one club + one template.
- **Action:** Attempt second insert of identical tuple.
- **Expected:** Unique constraint violation or explicit error; no duplicate row.

#### Test Case ID: RTM-06
- **Invariant(s):** Re-analysis with different template MUST create new sub-session.
- **Risk addressed:** Users cannot compare template versions.
- **Scenario:** Analyze same session/club with different template hashes.
- **Setup (fixtures):** One session + one club + two templates.
- **Action:** Insert sub-session with second template.
- **Expected:** New sub-session row is created; original remains unchanged.

#### Test Case ID: RTM-07
- **Invariant(s):** Validity status MUST reflect thresholds (invalid <5, warning 5–14, valid ≥15).
- **Risk addressed:** Misclassified data quality impacts trends.
- **Scenario:** Compute validity status at boundary values (4, 5, 14, 15).
- **Setup (fixtures):** Four sub-sessions with shot counts 4, 5, 14, 15.
- **Action:** Run validity computation.
- **Expected:** Statuses map to invalid, warning, warning, valid respectively.
- **Notes:** Threshold values (<5, 5–14, ≥15) are Phase 0 defaults; tests should reference configured values if/when configuration is exposed.

#### Test Case ID: RTM-08
- **Invariant(s):** A% MUST be NULL if status is `invalid_insufficient_data`.
- **Risk addressed:** False precision for tiny sample sizes.
- **Scenario:** Compute A% for a sub-session with 4 shots.
- **Setup (fixtures):** Sub-session with shot_count=4 and classification counts.
- **Action:** Persist computed metrics.
- **Expected:** `a_percentage` is NULL; status is invalid.
- **Notes:** Threshold values (<5, 5–14, ≥15) are Phase 0 defaults; tests should reference configured values if/when configuration is exposed.

#### Test Case ID: RTM-09
- **Invariant(s):** Invalid/low-sample sub-sessions MUST be stored (no silent exclusion).
- **Risk addressed:** Data loss or hidden samples.
- **Scenario:** Ingest a session with a club having 3 shots.
- **Setup (fixtures):** Mixed club session where one club has 3 shots.
- **Action:** Ingest and persist sub-sessions.
- **Expected:** Sub-session is stored with status invalid; no rejection.

#### Test Case ID: RTM-10
- **Invariant(s):** No silent filtering; validity filters must be explicit and reflected in output.
- **Risk addressed:** Users see filtered results without knowing it.
- **Scenario:** Query trend results with and without validity filters.
- **Setup (fixtures):** Multiple sub-sessions across statuses.
- **Action:** Run query with filter parameters.
- **Expected:** Output includes an explicit signal of applied filters (e.g., included statuses, filter metadata, or echoed query parameters) and status fields; unfiltered query includes all.

#### Test Case ID: RTM-11
- **Invariant(s):** Canonical JSON must sort keys at all nesting levels.
- **Risk addressed:** Hash mismatch across systems.
- **Scenario:** Canonicalize Fixture B.
- **Setup (fixtures):** Fixture B JSON with unsorted keys.
- **Action:** Canonicalize to compact JSON string.
- **Expected:** Keys are alphabetically ordered at all levels.

#### Test Case ID: RTM-12
- **Invariant(s):** Canonical JSON must be compact and UTF‑8 without BOM.
- **Risk addressed:** Hash mismatch due to whitespace or encoding.
- **Scenario:** Canonicalize Fixture A with pretty formatting.
- **Setup (fixtures):** Fixture A formatted with whitespace/indent.
- **Action:** Canonicalize to string and encode bytes.
- **Expected:** No whitespace; UTF‑8 encoding; no BOM.

#### Test Case ID: RTM-13
- **Invariant(s):** Numeric values MUST be normalized deterministically.
- **Risk addressed:** `1`, `1.0`, and `1.00` hash differently across platforms.
- **Scenario:** Canonicalize Fixture C numeric variants.
- **Setup (fixtures):** Fixture C with `1`, `1.0`, `100`, `0.001`.
- **Action:** Canonicalize and compare canonical numeric forms.
- **Expected:** Canonical JSON numeric representations are consistent and identical across platforms per chosen strategy.
- **Notes:** Document the chosen normalization rule in implementation docs; tests assert that rule.

#### Test Case ID: RTM-14
- **Invariant(s):** Hash computation MUST be identical across Python and Swift.
- **Risk addressed:** Cross-platform hash mismatch breaks template identity.
- **Scenario:** Compute hashes for Fixtures A–C in Python and Swift.
- **Setup (fixtures):** Fixtures A–C and canonicalization implementation.
- **Action:** Compute hashes in Python; mirror in Swift.
- **Expected:** All hashes match the Python golden values.

#### Test Case ID: RTM-15
- **Invariant(s):** Projections are regenerable and must not be imported as authoritative.
- **Risk addressed:** Importing projections corrupts source of truth.
- **Scenario:** Generate a projection, delete it, regenerate; attempt import.
- **Setup (fixtures):** One sub-session with computed metrics.
- **Action:** Generate projection → delete cache → regenerate; attempt to import projection.
- **Expected:** Regeneration yields same analytical results; import fails with an explicit error and no authoritative data is written or modified.

#### Test Case ID: RTM-16
- **Invariant(s):** Derived data MUST NOT be referenced by authoritative tables.
- **Risk addressed:** Authoritative data depends on derived cache.
- **Scenario:** Validate schema if projections table exists.
- **Setup (fixtures):** Schema with optional projections cache.
- **Action:** Inspect FK relationships.
- **Expected:** No FK from authoritative tables to projections/derived tables.

#### Test Case ID: RTM-17
- **Invariant(s):** One session MAY contain multiple clubs; mixed-club CSVs supported.
- **Risk addressed:** Single-club assumption drops data.
- **Scenario:** Ingest a CSV with shots from multiple clubs.
- **Setup (fixtures):** Mixed-club CSV (or synthesized fixture) with at least 2 clubs.
- **Action:** Ingest and group by club.
- **Expected:** One session created; one sub-session per club; shared `session_id`.
