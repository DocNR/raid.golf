# Data Confidence Report — Phase 4A

## Purpose

This report documents the validation work performed in **Phase 4A** to establish
confidence that the RAID iOS pipeline is:

- End-to-end correct
- Deterministic
- Kernel-compliant

No UI, trend analysis, or insight layers are built on top of the system until
the guarantees documented here hold.

---

## Fixtures Used

### Session Fixture
- `tests/vectors/sessions/rapsodo_mlm2pro_mixed_club_sample.csv`

Properties:
- 15 valid shot rows
  - 6 × 7-iron
  - 9 × 5-iron
- 2 footer rows (`Average`, `Std. Dev.`) explicitly excluded

### Template Fixture
- JSON template fixture for **7-iron**
- Inserted via the production repository path
- Canonicalized and hashed using kernel rules

---

## Authoritative Semantics

### source_row_index

`source_row_index` is defined as:

> The **0-based index of ingested shot rows after filtering non-shot rows**
> (e.g., footer or summary rows).

It is **not** the raw CSV file line number.

For the session fixture:
- Valid range: `0..14`
- Uniqueness is enforced
- Ordering is stable and deterministic

---

## Tests Implemented

### 1) Fixture Ingest Integration
**CSV → persisted shots**

Asserts:
- Imported count equals expected shot rows
- No skipped or malformed rows
- `source_row_index` is unique and sequential
- Shots are fetchable by `session_id`
- Foreign key integrity holds (shots → session)

---

### 2) Classification + Aggregation Determinism
**Template → classify → aggregate**

Asserts:
- `A + B + C == totalShots`
- Repeated classification runs produce identical outputs
- Fresh database ingest produces the same A%
- No golden counts are locked in this phase

---

### 3) Immutability Guardrail
**Authoritative data cannot be mutated**

Asserts:
- UPDATE on shots table hard-fails
- DELETE on shots table hard-fails
- No silent mutation is possible

---

## What Is Explicitly Asserted

- End-to-end ingest correctness
- Deterministic classification and aggregation
- Stable row identity (`source_row_index`)
- Referential integrity
- Database-enforced immutability

---

## What Is Explicitly NOT Asserted (Deferred)

- Exact golden A/B/C counts
- Exact golden aggregate values (carry, spin, speed, descent)
- Cross-platform parity with Python outputs

These are deferred to **Phase 4A.2 — Golden Aggregate Fixtures**.

---

## Known Limitations

- Template coverage limited to 7-iron
- 5-iron classification intentionally deferred
- Aggregates validated for determinism, not numeric parity

---

## Exit Criteria

Phase 4A is considered complete when:
- All integration tests pass deterministically
- Immutability violations are explicitly rejected
- This report accurately reflects test coverage
- No UI or trend code depends on unvalidated assumptions

---

## Appendix: Observed Results (Non-Normative)

During Phase 4A validation runs, the following were observed for the
`rapsodo_mlm2pro_mixed_club_sample.csv` fixture:

- 7-iron shots: 6
- Classification: A=5, B=0, C=1 (A%=83.33%)
- Template hash: 96bf2f0d…

These values are **not contractual** and may change.
Exact numeric parity is locked only in Phase 4A.2 via golden fixtures.
