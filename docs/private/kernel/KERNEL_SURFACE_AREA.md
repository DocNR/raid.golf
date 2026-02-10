# Kernel Surface Area — File Classification (Private)

**Status:** Internal / Private
**Purpose:** Clearly identify which files are subject to kernel governance
**Authority:** Subordinate to KERNEL_CONTRACT_v2.md
**Related:** See `KERNEL_GOVERNANCE.md` for domain-level registry (which data domains are kernel vs kernel-adjacent) and lifecycle rules

---

## Definition

This document classifies RAID project files into three categories:
1. **KERNEL** — Changes require explicit kernel versioning
2. **KERNEL-ADJACENT** — Changes must respect kernel invariants
3. **OUTSIDE KERNEL** — May change without kernel governance

If a file is not listed here, treat it as OUTSIDE KERNEL until explicitly classified.

---

## KERNEL (Frozen — Requires Explicit Versioning to Change)

These files implement the core integrity guarantees. Any modification to these files constitutes a **kernel change** and requires:
- Written rationale in `docs/private/kernel/` changelog
- New test vectors + golden hashes (where applicable)
- Migration plan (if schema changes)
- Explicit version bump for Kernel Contract

| File | Purpose |
|------|---------|
| `raid/canonical.py` | RFC 8785 JCS canonicalization logic |
| `raid/hashing.py` | SHA-256 identity computation for templates |
| `raid/schema.sql` | Immutability enforcement (ABORT triggers on UPDATE/DELETE) |
| `docs/schema_brief/05_canonical_json_hashing.md` | Canonical hashing specification |
| `tests/vectors/expected/template_hashes.json` | Golden test vectors for template identity |

**iOS (Swift):**

| File | Purpose |
|------|---------|
| `ios/RAID/RAID/Kernel/Canonical.swift` | RFC 8785 JCS canonicalization logic |
| `ios/RAID/RAID/Kernel/Hashing.swift` | SHA-256 identity computation for templates |
| `ios/RAID/RAID/Kernel/Schema.swift` | SQLite schema + immutability triggers (GRDB migrations) |
| `ios/RAID/RAID/Kernel/Protocols.swift` | Canonicalizing/Hashing protocols + production implementations |
| `ios/RAID/RAID/Kernel/Repository.swift` | Storage boundary (hash-once on insert, read-never recompute) |
| `ios/RAID/RAIDTests/KernelTests.swift` | JCS vectors, golden hashes, immutability triggers, hash-once behavioral tests |

### Rationale

**Canonicalization & Hashing:**
- Any change to key ordering, numeric normalization, or hash computation breaks template identity
- Historical template hashes become invalid
- Re-analysis with "same" template would produce different hash

**Schema Immutability Enforcement:**
- Triggers enforce immutability at the storage boundary
- Removing or weakening triggers allows silent data mutation
- Breaks reproducibility and auditability guarantees

**Golden Test Vectors:**
- Expected hashes define the canonical interpretation of test templates
- Changing expected hashes without changing canonicalization = accepting drift
- Test vectors are the verification baseline for cross-platform consistency

---

## KERNEL-ADJACENT (Changes Must Respect Kernel Invariants)

These files interact with kernel mechanisms and must not violate invariants. Changes are allowed but require:
- Verification that kernel invariants remain enforced
- Test coverage for immutability, determinism, and derived-data boundaries

| File | Purpose | Constraint |
|------|---------|-----------|
| `raid/repository.py` | Storage boundary (insert/query) | Must enforce immutability via schema |
| `raid/projections.py` | Derived data boundary | Projections must remain regenerable |
| `tests/unit/test_immutability.py` | Kernel enforcement tests | Must verify ABORT on UPDATE/DELETE |
| `tests/unit/test_hashing.py` | Determinism tests | Must verify cross-platform consistency |
| `tests/unit/test_canonicalization.py` | Canonicalization tests | Must verify key ordering, normalization |
| `tests/unit/test_analysis_semantics.py` | Re-analysis semantics tests | Must verify idempotence and preservation |
| `tests/unit/test_derived_boundary.py` | Derived-data separation tests | Must verify projections are not authoritative |

**iOS (Swift):**

| File | Purpose | Constraint |
|------|---------|-----------|
| `ios/RAID/RAID/Domain/ShotClassifier.swift` | Shot classification (A/B/C) | Must remain a pure function; derived only |
| `ios/RAID/RAID/Domain/KPITemplate.swift` | Template data model + grade logic | Must match canonical template format |
| `ios/RAID/RAID/Ingest/RapsodoIngest.swift` | CSV ingest pipeline | Must call repository for immutable inserts |
| `ios/RAID/RAIDTests/IngestIntegrationTests.swift` | End-to-end pipeline tests | Must verify determinism and golden parity |
| `ios/RAID/RAID/Scorecard/ScorecardModels.swift` | Scorecard insert/read types | Must match scorecard schema; stable during incubation |
| `ios/RAID/RAID/Scorecard/ScorecardRepository.swift` | Scorecard storage boundary (3 repos) | Must enforce immutability via schema; hash-once on course insert |
| `ios/RAID/RAIDTests/ScorecardTests.swift` | Scorecard immutability + behavioral tests | Must verify triggers, hash-once, latest-wins, FK integrity |

### Rationale

**Storage Boundary:**
- Repository layer mediates all access to authoritative data
- Changes here can bypass schema enforcement if not careful
- Must preserve read-only access to immutable entities

**Projections:**
- Must remain regenerable from authoritative data + template hash
- Any change that makes projections non-regenerable breaks derived-data boundary

**Kernel Tests:**
- These tests verify kernel enforcement
- Weakening tests = weakening kernel guarantees
- Tests must remain strict and comprehensive

---

## OUTSIDE KERNEL (May Change Without Kernel Governance)

These files do not affect kernel integrity and may evolve freely:

| File | Purpose | Notes |
|------|---------|-------|
| `raid/ingest.py` | CSV parsing & validation | Input handling, not kernel |
| `raid/validity.py` | Sample size handling | Business logic, not identity/immutability |
| `tools/scripts/analyze_session.py` | CLI entrypoint | Tooling, not core |
| `tools/kpi/generate_kpis.py` | KPI threshold generation | Generates templates, does not define identity |
| `tools/kpis.json` | KPI threshold data | Content, not mechanism |
| `data/summaries/*` | Derived outputs | Regenerable artifacts |
| `docs/PRD_Phase_0_MVP.md` | Requirements | Governance, not implementation |
| `docs/reference_test_matrix.md` | Test planning | Documentation |
| `README.md` | Public documentation | May evolve with features |

**iOS (Swift):**

| File | Purpose | Notes |
|------|---------|-------|
| `ios/RAID/RAID/RAIDApp.swift` | App entry point | Presentation layer |
| `ios/RAID/RAID/ContentView.swift` | Root TabView container | Presentation layer |
| `ios/RAID/RAID/Views/*.swift` | UI views (Trends, Sessions, Rounds, Summary, Templates) | Presentation layer |
| `ios/RAID/RAID/Scorecard/ActiveRoundStore.swift` | Active round view model | Presentation/state management; calls repositories but does not define storage invariants |
| `ios/RAID/RAID/Kernel/TemplatePreferencesRepository.swift` | Mutable preference CRUD | Product-layer; operates only on `template_preferences` (non-kernel table) |

**Product-Layer Tables (mutable, non-kernel):**

| Table | Purpose | Notes |
|-------|---------|-------|
| `template_preferences` | Display names, active/hidden per template | Mutable by design; no immutability triggers. FK to `kpi_templates`. |

**Product-Layer Methods on Kernel Classes:**

| Method | Class | Notes |
|--------|-------|-------|
| `listTemplates(forClub:)` | TemplateRepository | LEFT JOIN to `template_preferences` for hidden filter. Product convenience. |
| `listAllTemplates()` | TemplateRepository | Same; ordered by club ASC then recency DESC. |
| `fetchSubsessions(forSession:)` | SubsessionRepository | Read-only; returns persisted analysis records. |

Frozen kernel methods remain unchanged: `insertTemplate`, `fetchTemplate(byHash:)`, `fetchLatestTemplate(forClub:)`.

### Rationale

These files may iterate rapidly without breaking trust guarantees:
- Ingest logic can improve CSV parsing without affecting template identity
- Validity thresholds can change without affecting immutability
- CLI tooling is a presentation layer over the kernel
- Documentation reflects but does not define kernel behavior

---

## Decision Rules

### "Is this a kernel change?"

Ask these questions:

1. **Does it change how templates are identified?**  
   → If yes, it's a kernel change

2. **Does it change canonicalization or hashing rules?**  
   → If yes, it's a kernel change

3. **Does it allow mutation of immutable facts?**  
   → If yes, it's a kernel change

4. **Does it make projections authoritative?**  
   → If yes, it's a kernel change

5. **Does it change re-analysis semantics?**  
   → If yes, it's a kernel change

If any answer is "yes", the change requires kernel governance.

### "Can I add a new feature without changing the kernel?"

Yes, if the feature follows the extension pattern:
1. Define new immutable facts (tables)
2. Define new templates (rule documents)
3. Define evaluators (pure functions: facts + template → output)
4. Store outputs as projections referencing fact IDs + template_hash

If your design does not fit this pattern, it likely violates kernel invariants.

---

## Enforcement

**Pull Request Review:**
- Any PR touching KERNEL files must include:
  - Explicit kernel change rationale
  - Updated test vectors (if hashing/canonicalization changed)
  - Kernel Contract version bump

**Agent/AI Assistant Constraints:**
- See `.clinerules/kernel-governance.md` for governance guardrails (STOP conditions, lifecycle, data classification)
- See `.clinerules/kernel.md` for kernel protection addendum (extension patterns, PR hygiene)
- Agents must halt and propose alternatives if kernel change is required

**Manual Review:**
- All kernel changes require explicit human approval
- No automated merge for KERNEL or KERNEL-ADJACENT files

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-02-01 | Initial surface area classification |
| 1.1 | 2026-02-02 | Updated for Kernel v2.0 (RFC 8785 JCS) — no surface area changes |
| 1.2 | 2026-02-08 | Added iOS kernel/kernel-adjacent/outside file classifications; linked to KERNEL_GOVERNANCE.md domain registry |
| 1.3 | 2026-02-08 | Added scorecard v0 files: Scorecard/* as KERNEL-ADJACENT, Views/Rounds* as OUTSIDE KERNEL |
| 1.4 | 2026-02-09 | Added ActiveRoundStore.swift as OUTSIDE KERNEL (view model, not storage boundary) |
| 1.5 | 2026-02-10 | Added template_preferences (product-layer table), TemplatePreferencesRepository, product-layer methods on kernel classes |

---

**Bottom line:**  
If it's in the KERNEL category, changing it without governance breaks the roadmap.
