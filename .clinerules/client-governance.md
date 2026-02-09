# Client Governance — Human Workflow Guide

**Full policy:** `docs/private/kernel/KERNEL_GOVERNANCE.md`

---

## Kernel vs Kernel-Adjacent

**Kernel:** Frozen schemas and invariants. Changes require explicit versioning, rationale, migration, and updated test vectors. The launch-monitor domain (sessions, shots, templates, subsessions) is currently frozen at Kernel v2.

**Kernel-adjacent:** Authoritative data whose schema may still evolve. Follows the same principles (immutability, append-only, content-addressing) but is not yet contractually locked. New domains (e.g., scorecards) start here.

---

## Rules of Thumb

- **Store only what you can't infer.** If a value is a pure function of other stored facts, compute it — don't store it as truth.
- **Derived outputs are never truth.** Totals, percentages, classifications, and trend lines are recomputable. They may be cached but must remain disposable.
- **Immutable means immutable.** No UPDATE, no DELETE. Corrections are new rows, not edits.

---

## Adding New Data Points

When you want to store a new piece of information:

1. **Ask: "Can I infer this later from facts I already store?"**
   - Yes → derive it, don't store it.
   - No → store it as an authoritative fact.

2. **Add new fields as nullable columns.** Old records get NULL. Derived metrics must handle NULL gracefully.

3. **Define the meaning precisely** before implementation. Example: "putts = strokes taken on the putting surface, excludes fringe chips."

4. **Do not reinterpret existing fields.** If a field's meaning needs to change, add a new field or propose a kernel version bump.

---

## Handling Edits

- **Never UPDATE an authoritative row.** Insert a new row that supersedes the old one.
- **Latest-wins:** multiple rows for the same logical entity; queries pick the most recent by `recorded_at`.
- **Revision events:** a separate correction row references the prior fact. More explicit, slightly more schema.
- Either approach is acceptable. Document which one you use.

---

## When to Branch

Create a new branch for a new domain (e.g., `feature/scorecard-v0`):

- New domains have different invariants than existing ones.
- Branching prevents accidental coupling to existing kernel tables.
- Merge only when the domain model feels boring and obvious.

**While on a domain branch:** do not modify existing kernel tables (shots, sessions, templates) unless you explicitly decide the change belongs to both domains.

---

## Kernel Freezes

- **Freezes are explicit and documented.** A domain becomes frozen kernel only after satisfying the promotion checklist (see KERNEL_GOVERNANCE.md).
- **Freezes are governance decisions, not convenience decisions.** A domain should be used enough to be boring before it is frozen.
- **Early freezes are acceptable** when the frozen surface covers mechanics (immutability, hash-once, canonicalization), not speculative semantics. If a semantic mistake is found later, handle it as an explicit version bump — never a quiet unfreeze.
- **Kernel changes require governance.** No kernel modification happens without versioning, rationale, migration plan, and updated tests.

---

## Quick Reference: Is This a Kernel Change?

Ask:

1. Does it change how existing data is identified (canonical bytes, hashes)?
2. Does it change what an existing stored field means?
3. Does it allow mutation of immutable facts?
4. Does it make derived data authoritative?

If any answer is **yes** → kernel change. Requires governance.
If all answers are **no** → safe extension. Proceed.
