# Kernel Governance Rules (Must Follow)

**Full policy:** `docs/private/kernel/KERNEL_GOVERNANCE.md`

## Definitions

- **Kernel facts** live in SQLite authoritative tables and are immutable (no UPDATE/DELETE).
- **Identity** is content-addressed: `hash = SHA-256(JCS(canonical_json))`. Hash computed once on insert, never recomputed on read.
- **Derived outputs** (classifications, trends, summaries, totals) are recomputable and are not kernel truth.
- **Kernel-adjacent** = authoritative + immutable, but schema not yet frozen. May evolve during incubation.

---

## STOP Conditions (MUST HALT)

Stop immediately and ask for instruction if any task requires:

1. UPDATE or DELETE on any authoritative table (frozen or kernel-adjacent)
2. Recomputing hashes for existing stored rows
3. Changing canonicalization rules (JCS / RFC 8785)
4. Changing the meaning or interpretation of an existing stored field
5. Importing derived projections into authoritative tables
6. Overwriting prior analysis results instead of creating a new derived record
7. Removing or weakening immutability triggers on any authoritative table
8. Silently reinterpreting historical data without storing a new template hash or version
9. Adding non-deterministic elements to classification or outcome logic (randomness, ML inference without deterministic fallback, external API calls, system time dependencies, floating-point operations without deterministic normalization)

**If unsure whether a change is kernel-affecting, treat it as kernel-affecting and STOP.**

When STOP is triggered:
- Explain the conflict
- Propose an additive design that preserves invariants
- Do not implement the violating change

---

## Disallowed Actions

- UPDATE/DELETE of any authoritative fact row
- Recomputing or "fixing" hashes for existing records
- Changing canonicalization logic
- Making templates mutable
- Storing derived outputs as authoritative truth
- Silent semantic changes to existing columns

## Allowed Without Kernel Version Bump

- Adding new tables (kernel-adjacent domains)
- Adding nullable columns that do not change meaning of existing columns
- Adding derived caches (must be recomputable and disposable)
- Adding new tests, vectors, and documentation

---

## Data Classification

- **Store as authoritative** only if it cannot be reliably inferred from other stored facts.
- **Compute as derived** anything that is a pure function of authoritative data.
- Derived caches are disposable. Deleting them must not affect authoritative reads.

---

## Adding New Fields

- New fields must be **nullable** (old records get NULL).
- New fields must **not** change the meaning of existing columns.
- Derived metrics must handle NULL explicitly.
- The precise meaning of each new field must be defined before implementation.

---

## Edit Semantics

- Corrections are **append-only**: insert a new superseding fact, never UPDATE.
- "Latest-wins" by `recorded_at` or explicit revision events — both acceptable, must be documented.

---

## Kernel-Adjacent → Frozen Promotion

Before promoting a kernel-adjacent domain to frozen kernel:

1. All authoritative tables have UPDATE/DELETE rejection triggers
2. Deterministic selection rules documented
3. Canonicalization/hashing rules defined for content-addressed objects
4. Invariant tests exist (immutability, FK integrity, deterministic reads)
5. At least one golden vector (if hashing/publishing involved)
6. Contract document written and added to KERNEL_SURFACE_AREA.md
7. CHANGELOG entry recorded

**Documentation must precede promotion. No domain is frozen without a contract document.**

---

## Required Test Coverage for Schema Changes

Any change to an authoritative or kernel-adjacent schema must include:
- Immutability trigger tests (attempted UPDATE/DELETE → rejected)
- FK integrity tests
- Deterministic ordering/read tests
