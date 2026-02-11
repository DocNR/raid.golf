# RAID Data Governance: Kernel, Kernel-Adjacent, and Derived

**Status:** Authoritative governance document (private)
**Authority:** Supplements KERNEL_CONTRACT_v2.md. Does not supersede existing frozen contracts.
**Scope:** Defines how RAID data domains evolve from incubation to frozen kernel status.

---

## 1) Definitions

### Kernel

The **kernel** is the set of frozen schemas, invariants, and identity rules that RAID treats as contractually stable. It includes:

- Frozen fact table schemas (sessions, shots, subsessions, kpi_templates)
- Canonicalization rules (RFC 8785 JCS)
- Hashing rules (SHA-256 of canonical bytes, computed once on insert)
- Immutability enforcement (ABORT triggers on UPDATE/DELETE)
- Golden parity tests that verify cross-platform determinism

The kernel is not "everything stored in SQLite." It is the subset of schemas and rules that have been explicitly frozen and versioned.

Changes to the kernel require explicit versioning (e.g., Kernel v2 → v3), written rationale, migration plan, and updated test vectors.

### Kernel-Adjacent

**Kernel-adjacent** describes authoritative data domains whose schema and semantics may still evolve. A kernel-adjacent domain:

- Stores immutable facts (no UPDATE/DELETE)
- Uses the same invariant style as the kernel (append-only, content-addressed where applicable)
- Does **not** yet carry a promise of long-term schema stability
- May undergo breaking changes during incubation, with documentation

Kernel-adjacent domains are candidates for eventual promotion to frozen kernel status.

### Authoritative Facts

**Authoritative facts** are data that RAID treats as ground truth:

- Stored in SQLite as the source of truth
- Immutable at the row level (UPDATE/DELETE rejected)
- Have stable, documented semantics (what a field "means" does not silently change)
- Cannot be reliably inferred or reconstructed from other stored data

Examples: hole strokes, putts per hole, penalties, shot metrics from a launch monitor, template JSON.

A fact may be authoritative without being part of the frozen kernel. Kernel status is a governance decision, not an ontological one.

### Derived Outputs

**Derived outputs** are data that is recomputable from authoritative facts:

- Not kernel truth
- May change if algorithms, templates, or classification rules change
- Can be cached for performance, but caches must be disposable and reproducible
- Must never be imported into authoritative tables

Examples: total score (sum of hole strokes), A/B/C shot classifications, trends, stableford points, GIR percentage.

---

## 2) Data Classification Rules

### Rule A: Store as authoritative if you cannot reliably infer it later

If the data point will be impossible or unreliable to reconstruct from other stored facts, it must be stored as an authoritative fact.

Ask: "If I don't store it now, will it be impossible to reconstruct later?"

- If yes → store as authoritative.
- If no → derive it.

### Rule B: Do not store data that is a pure function of other authoritative facts

If a value can be deterministically computed from existing authoritative data, it should be derived, not stored.

Storing derived values as authoritative creates drift risk: the stored value and the computed value may diverge.

If caching is needed for performance, the cache must be explicitly marked as derived, keyed by input hashes/IDs, and disposable.

### Rule C: Subjective or ambiguous observations are optional, not fundamental

Data like "good drive" or "miss type" may be stored as optional observations but must not become required for correctness of derived outputs.

---

## 3) What Constitutes a Kernel Change

A change is a **kernel change** (requiring explicit version bump) if it would alter any of the following for existing frozen facts:

- Canonical bytes (how data is serialized for identity)
- Hash computation or meaning of stored hashes
- Interpretation or meaning of existing stored facts
- Immutability guarantees for existing authoritative tables

Examples of kernel changes:

- Changing JCS canonicalization behavior
- Changing how template hashes are computed
- Redefining what a stored field means (e.g., "strokes includes penalties" → "strokes excludes penalties")
- Removing or weakening immutability triggers on frozen tables

### What is a Kernel Extension by Addition (Safe)

These do **not** require a kernel version bump:

- Adding new tables for new fact domains (e.g., rounds, hole_scores, course_snapshots)
- Adding new nullable columns to existing tables that do not change the meaning of existing columns
- Adding new derived caches that are recomputable and disposable
- Adding new tests, vectors, or documentation

A kernel extension adds new frozen invariants without affecting existing ones. It may be recorded as a minor version update (e.g., Kernel v2.0 → v2.1).

### What is Disallowed

- UPDATE/DELETE of authoritative fact rows (enforced by triggers)
- Silent reinterpretation: changing what stored data means without explicit versioning and tests
- Recomputing hashes for existing rows to "fix" them
- Importing derived projections into authoritative tables

---

## 4) Immutability and Edit Semantics

### Authoritative facts are append-only

If a user "edits" a previously recorded fact:

- Do **not** UPDATE the existing row
- Insert a new fact that supersedes it

### Edit approaches

**Latest-wins by recorded_at:**
Insert multiple rows for the same logical entity; queries select the row with the latest `recorded_at` timestamp. Simple, preserves full history, requires deterministic selection rules.

**Explicit revision event:**
A separate immutable "correction" event references the prior fact's hash or ID. More explicit, slightly more schema surface.

For early-stage domains (e.g., scorecard v0), "latest-wins" is acceptable if documented. More structured revision semantics can be adopted at the hardening stage.

---

## 5) How New Data Fields Are Added

When adding a new data point to an existing domain:

1. **Add as a nullable column** (or as a new observation table).
2. Old records naturally have `NULL` for the new field.
3. Derived metrics must handle `NULL` explicitly and gracefully.
4. The new field must not change the meaning of existing columns.
5. The precise meaning of the new field must be defined (e.g., "putts = strokes taken on the putting surface, excludes fringe chips").

Adding a new nullable column that does not alter existing column semantics is an additive extension, not a kernel change.

Fields must not be silently reinterpreted after data has been stored. If the meaning of a field needs to change, it requires a new field or a kernel version bump.

---

## 6) Lifecycle: Kernel-Adjacent → Hardened → Frozen Kernel

### Stage 1: Kernel-Adjacent (Incubation)

**Entry criteria:**

- New domain tables exist
- Immutability enforcement exists (triggers planned or in place)
- No promise of long-term schema stability

**Allowed:**

- Rename columns
- Change table shapes
- Rework semantics

**Required discipline:**

- Keep changes small and intentional
- Maintain invariants (immutability, determinism)
- Record breaking changes in a CHANGELOG section

### Stage 2: Hardened (Stabilization)

**Entry criteria:**

- Domain has been used enough that the schema is "boring" — it has stopped thrashing
- You are confident in the semantics

**Requirements:**

- DB-level immutability enforced (ABORT triggers on UPDATE/DELETE)
- Deterministic ordering and selection rules documented
- Invariant tests added (immutability, FK integrity, deterministic reads)
- At least one golden vector if hashing or canonicalization is involved

**Allowed:**

- Additive changes (new nullable fields)
- New tables for extensions
- Breaking changes only with an explicit migration plan

### Stage 3: Frozen Kernel (Promotion)

**Entry criteria:**

- Hardened for at least one release cycle or meaningful usage period
- No known semantic ambiguities remain

**Requirements before promotion:**

- Contract document created (e.g., `KERNEL_CONTRACT_scorecard_v1.md`)
- Schema migration locked
- Golden vectors created (where relevant)
- "Authoritative vs derived" section written
- "What constitutes a kernel change" section written for this domain
- Added to `KERNEL_SURFACE_AREA.md` as KERNEL

**After freeze:**

- Changes require explicit versioning (v1 → v2)
- Backward compatibility strategy documented

---

## 7) Promotion Checklist

To promote a domain from kernel-adjacent to frozen kernel, all items must be satisfied:

1. All authoritative tables have UPDATE/DELETE rejection triggers
2. Deterministic selection rules documented (e.g., "latest-wins" semantics, tie-breakers)
3. Canonicalization and hashing rules defined for any content-addressed objects
4. Invariant tests exist:
   - Immutability trigger tests
   - FK integrity tests
   - Deterministic read/ordering tests
5. At least one golden vector if publishing or cross-platform verification is expected
6. Contract document written and added to KERNEL_SURFACE_AREA.md
7. CHANGELOG entry: "[Domain] kernel vX frozen"

---

## 8) Early Freezes

Freezing a kernel domain early is acceptable when:

- You are freezing **invariants and mechanics** (immutability, hash-once, canonicalization rules, FK integrity), not speculative semantics
- The schema is **general enough** to accommodate additive extensions (nullable columns, new tables)
- You accept that **derived behavior** (classifiers, trends, summaries) will continue to evolve outside the freeze

An early freeze is not a mistake. It is a commitment: any future breaking corrections must be handled as an explicit kernel version change (e.g., v2 → v3) with governance, migration, and updated test vectors.

The launch-monitor kernel was frozen early. This is acceptable because:

- The frozen surface covers mechanics (hash-once, immutability, canonicalization), not evolving analytics
- Post-freeze testing (golden aggregate parity, ingest integration tests, template bootstrap tests) validated the frozen invariants
- If a true semantic mistake is discovered, the correct response is Kernel v3 with explicit governance — not a quiet unfreeze

---

## 9) Domain Registry

This section tracks each data domain and its current governance status. Update this registry when a domain changes stage.

### Frozen Kernel

| Domain | Tables | Frozen Since | Contract |
|--------|--------|-------------|----------|
| Launch-monitor (practice) | `sessions`, `kpi_templates`, `club_subsessions`, `shots` | Kernel v2.0 (2026-02-02) | `KERNEL_CONTRACT_v2.md` |

Frozen domains have locked schema, immutability triggers, golden vectors, and cross-platform parity tests. Changes require explicit kernel versioning.

### Kernel-Adjacent

| Domain | Status | Tables (planned/actual) | Notes |
|--------|--------|------------------------|-------|
| Scorecards | v0 bugfix sprint complete | `course_snapshots`, `course_holes`, `rounds`, `round_events`, `hole_scores` | Schema landed in `v3_create_scorecard_schema` migration on `feature/scorecard-v0`. All 5 tables have immutability triggers. Course snapshots are content-addressed (SHA-256 of JCS canonical JSON). Rounds use append-only `round_events` for lifecycle (no mutable status). Hole scores use latest-wins correction semantics. 31 scorecard-specific tests in ScorecardTests.swift cover immutability, hash-once, latest-wins, FK integrity, nested-read safety, default-value persistence, last-hole finish eligibility. Bugfix sprint fixed nested-read crash, default-value persistence, last-hole finish button. ActiveRoundStore pattern introduced for long-lived scoring state. Becomes frozen kernel only after the promotion checklist (Section 7) is satisfied. |

Kernel-adjacent domains store authoritative immutable facts but do not yet carry a promise of long-term schema stability.

### Derived / Outside Kernel

| Domain | Examples | Notes |
|--------|----------|-------|
| Shot classification | A/B/C grades, worst_metric aggregation | Recomputable from shots + template; evolves freely |
| Trends | Carry/ball-speed trend lines | Recomputable from shots; evolves freely |
| Session summaries | Per-session aggregates | Derived from shots; cached but disposable |
| Template preferences | Active/hidden flags, display names per template | Mutable product-layer UX state; FK to kpi_templates |

---

## 10) Relationship to Existing Governance Documents

This document supplements but does not replace:

- **KERNEL_CONTRACT_v2.md** — the frozen contract for the launch-monitor kernel (invariants, extension patterns, review checklist)
- **KERNEL_SURFACE_AREA.md** — file-level classification of what is KERNEL vs KERNEL-ADJACENT vs OUTSIDE KERNEL (both Python and iOS)
- **KERNEL_FREEZE_v2.md** — the freeze declaration for kernel v2.0

This document adds:

- The domain registry (Section 9) — which data domains are kernel, kernel-adjacent, or derived
- The lifecycle model (kernel-adjacent → hardened → frozen)
- The promotion checklist
- Data classification rules (authoritative vs derived)
- Edit semantics (append-only corrections)
- Rules for adding new fields to existing domains
- Justification for early freezes
