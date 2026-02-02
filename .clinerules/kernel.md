# .clinerules — Kernel Protection Addendum (RAID)

**Canonical Kernel Contract:** See `docs/private/kernel/KERNEL_CONTRACT.md` for full governance specification.

## Role Constraint
You are an assistant contributing to RAID Golf. The **kernel invariants are locked**.  
If your work would violate these invariants, you MUST STOP and propose an additive alternative.

---

## Canonical Kernel Invariants (HARD RULES)

### Templates
- KPI / competition / handicap templates are **content-addressed** via canonical JSON + SHA-256.
- Template hashes are computed once on insert and **never recomputed on read**.
- Templates are **immutable** once stored.

### Authoritative Facts
- Fact tables are immutable:
  - sessions, subsessions (existing)
  - shots (future)
  - rounds, strokes, attestations (future)
- UPDATE/DELETE on fact tables is forbidden. Use ABORT triggers or equivalent.

### Derived Data Boundary
- Projections are derived-only and regenerable.
- Projection import into authoritative tables is forbidden.
- Deleting projections must not affect authoritative reads.

### Analysis Semantics
- Duplicate derived result for same (facts, template_hash) must be prevented.
- Re-analysis with a new template_hash must create a new derived record, never overwrite.

### Corrections
- Corrections are append-only events/annotations, never edits in place.

---

## STOP Conditions (MUST HALT)

Stop immediately and ask for instruction if any task requires:
1. Editing canonicalization or hashing rules
2. Allowing templates to be updated in-place
3. Recomputing a template hash during a read path
4. Adding UPDATE/DELETE capability to any fact table
5. Importing projections into authoritative tables
6. Overwriting prior analysis results instead of creating a new derived record
7. "Fixing" historical outcomes by changing rules without storing a new template hash
8. Adding non-deterministic elements to classification or outcome logic (randomness, ML inference without deterministic fallback, external API calls, system time dependencies, floating-point operations without deterministic normalization)

When STOP is triggered:
- Explain the conflict
- Propose an additive design that preserves invariants
- Do not implement the violating change

---

## Allowed Extension Pattern (DEFAULT)

For any new feature (shots, rounds, games, betting):
1. Add new immutable fact tables
2. Add template kind + validator
3. Add evaluator (pure function)
4. Store outputs as projections referencing:
   - fact IDs
   - template_hash
   - evaluator version (if relevant)

---

## Required PR Hygiene
- Any kernel-adjacent change must add/extend tests:
  - immutability tests (attempted UPDATE/DELETE)
  - determinism tests (golden vectors)
  - re-analysis semantics tests
- Avoid refactors that mix domains (practice vs rounds vs games) unless necessary.
