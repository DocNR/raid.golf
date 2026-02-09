# .clinerules — RAID Agent & Workflow Rules Index

**Read this file first** before starting any new sprint, phase, or significant coding task.

This directory contains rules that govern how coding agents and human developers interact with the RAID codebase. Rules protect kernel invariants, enforce data governance, and prevent accidental violations of frozen contracts.

---

## Reading Order

For a new sprint or significant coding task, review files in this order:

| Order | File | Audience | Purpose |
|-------|------|----------|---------|
| 1 | **README.md** (this file) | All | Index and orientation |
| 2 | **kernel-governance.md** | Agents | Kernel governance guardrails: STOP conditions, allowed/disallowed actions, data classification, promotion lifecycle |
| 3 | **kernel.md** | Agents | Kernel protection addendum: frozen invariants, extension pattern, PR hygiene |
| 4 | **client-governance.md** | Humans | Workflow guide: rules of thumb, adding data, handling edits, branching, freezes |
| 5 | **doc-updates.md** | All | Documentation hygiene after milestones |
| 6 | **phase-0-rules.md** | Agents | Phase 0 MVP rules and Rapsodo ingest handling (see note below) |

---

## File Descriptions

### kernel-governance.md — Kernel Governance Rules
**Audience:** Coding agents
**Status:** Current
**Upstream doc:** `docs/private/kernel/KERNEL_GOVERNANCE.md`

Comprehensive agent-facing governance rules. Covers:
- Definitions (kernel, kernel-adjacent, authoritative, derived)
- 9 STOP conditions (must halt and ask before proceeding)
- Disallowed and allowed actions
- Data classification (store vs derive)
- Rules for adding new fields (nullable, no reinterpretation)
- Edit semantics (append-only corrections)
- Kernel-adjacent to frozen promotion checklist
- Required test coverage for schema changes

### kernel.md — Kernel Protection Addendum
**Audience:** Coding agents
**Status:** Current
**Upstream doc:** `docs/private/kernel/KERNEL_CONTRACT_v2.md`

The original kernel protection rules from Phase 0. Covers:
- Canonical kernel invariants (templates, facts, derived boundary, analysis semantics, corrections)
- 8 STOP conditions
- Allowed extension pattern (facts + templates + evaluators + projections)
- PR hygiene requirements

**Overlap note:** This file and `kernel-governance.md` share coverage of STOP conditions and allowed/disallowed actions. Both files are active. `kernel-governance.md` is the broader document (adds lifecycle, data classification, promotion). `kernel.md` provides the original extension pattern and PR hygiene rules. They are consistent with each other.

### client-governance.md — Human Workflow Guide
**Audience:** Human developers
**Status:** Current
**Upstream doc:** `docs/private/kernel/KERNEL_GOVERNANCE.md`

Practical guidance for developers working in the IDE. Covers:
- Kernel vs kernel-adjacent (brief explanation)
- Rules of thumb (store only what you can't infer, derived is never truth, immutable means immutable)
- Adding new data points
- Handling edits (latest-wins, revision events)
- When to branch for new domains
- Kernel freeze principles
- Quick reference: "Is this a kernel change?"

### doc-updates.md — Documentation Hygiene
**Audience:** All
**Status:** Current

Lightweight rule: update `CHANGELOG.md` and relevant docs after completing a major phase or milestone.

### phase-0-rules.md — Phase 0 MVP & Rapsodo Rules
**Audience:** Coding agents
**Status:** Partially outdated

Contains two sections:
1. **Phase 0 MVP rules** — scope constraints and authority order for Phase 0. The scope lock ("Phase 0 only") and Python tooling references (`tools/scripts/analyze_session.py`, `tools/kpis.json`, `data/summaries/`) are outdated as the project has moved to Phase 4C with an iOS app. Core principles (SQLite is authoritative, immutability enforced, no template_hash recomputation) remain valid but are now covered more completely in `kernel-governance.md` and `kernel.md`.
2. **Strike Quality Practice System rules** — Rapsodo CSV handling, session ingest workflow, derived output rules, versioning rules. These remain relevant for any work touching CSV ingest or the Python analysis pipeline.

---

## Upstream Governance Documents

These rule files are enforcements of policies defined in:

| Document | Purpose |
|----------|---------|
| `docs/private/kernel/KERNEL_GOVERNANCE.md` | Authoritative data governance: lifecycle, promotion, data classification |
| `docs/private/kernel/KERNEL_CONTRACT_v2.md` | Frozen kernel contract v2 (invariants, extension patterns, review checklist) |
| `docs/private/kernel/KERNEL_SURFACE_AREA.md` | File-level classification: KERNEL vs KERNEL-ADJACENT vs OUTSIDE KERNEL |
| `docs/private/kernel/KERNEL_FREEZE_v2.md` | Freeze declaration for kernel v2.0 |

---

## Decision Quick Reference

**Is this a kernel change?** Ask:
1. Does it change canonical bytes or hashes for existing data?
2. Does it change what an existing stored field means?
3. Does it allow mutation of immutable facts?
4. Does it make derived data authoritative?

Any **yes** → kernel change → requires governance (versioning, rationale, migration, tests).
All **no** → safe extension → proceed.

**Unsure?** Treat it as kernel-affecting and STOP.
