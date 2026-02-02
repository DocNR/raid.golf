# Schema-First Implementation Brief: RAID Phase 0 (MVP)

**Project Codename:** RAID  
**Document Version:** 1.1 (Kernel v2.0)  
**Date:** 2026-02-02  
**Status:** Active  
**Authoritative Source:** [PRD_Phase_0_MVP.md](../PRD_Phase_0_MVP.md)  
**Kernel Contract:** [KERNEL_CONTRACT_v2.md](../private/kernel/KERNEL_CONTRACT_v2.md) (v2.0 - RFC 8785 JCS)

---

## Purpose

This Schema-First Implementation Brief defines the **authoritative data schema and invariants** that govern all Phase 0 implementations of the RAID golf analytics system.

It exists to:

- Prevent architectural drift during implementation
- Constrain AI-assisted code generation with explicit rules
- Guarantee reproducibility, immutability, and future interoperability (iOS + JSON + Nostr)
- Ensure the PRD cannot be "reinterpreted" during coding

**This is not** a migration plan, task list, sprint backlog, or SQL implementation guide.

---

## Document Structure

This brief is organized as a modular documentation set for maintainability:

1. **[Scope & Intent](01_scope_and_intent.md)**  
   Purpose, relationship to PRD, explicit exclusions

2. **[Authoritative Entities](02_authoritative_entities.md)**  
   Core data entities, their lifecycles, and ownership boundaries

3. **[Logical Schema Definition](03_logical_schema.md)**  
   Conceptual table definitions (vendor-neutral, no SQL)

4. **[Identity & Immutability Rules](04_identity_and_immutability.md)**  
   Hard invariants governing what can and cannot mutate

5. **[Canonical JSON & Hashing Contract](05_canonical_json_hashing.md)**  
   Deterministic serialization and content-addressing rules (RFC 8785 JCS as of v2.0)

6. **[Session & Sub-Session Invariants](06_session_invariants.md)**  
   Cardinality constraints, validity status, data retention rules

7. **[Derived Data & Projections](07_derived_data_projections.md)**  
   Rules for regenerable artifacts and export-only data

8. **[Non-Goals at the Schema Layer](08_non_goals.md)**  
   Explicitly prohibited capabilities and future temptations

9. **[Forward-Compatibility Guarantees](09_forward_compatibility.md)**  
   How the schema supports iOS, Nostr, and long-term evolution

10. **[Summary of Enforced Invariants](10_enforced_invariants.md)**  
    The "Constitution" - non-negotiable rules in bullet form

---

## Core Principles (Quick Reference)

1. **SQLite is authoritative** — JSON is serialization only
2. **Immutability is enforced** — by schema + rules, not convention
3. **Content-addressed identity** — templates identified by `sha256(canonical_json)`
4. **No speculative features** — no sync, no UI, no cloud, no ML
5. **Schema-first always** — define what must exist and what must never happen

---

## Usage Guidelines

### For Implementation

When implementing Phase 0 features:

1. Read the **[Enforced Invariants](10_enforced_invariants.md)** first
2. Consult relevant sections for detailed constraints
3. Validate against the PRD for requirement alignment
4. Never relax constraints without explicit PRD amendment

### For AI-Assisted Development

When prompting AI coding assistants:

1. Reference this brief as the authoritative schema specification
2. Include relevant section links in context
3. Enforce that generated code must not violate stated invariants
4. Use the invariants summary as a validation checklist

### For Code Review

When reviewing schema-related changes:

1. Verify compliance with identity and immutability rules
2. Check that no prohibited capabilities have been introduced
3. Confirm that derived data remains separate from authoritative data
4. Validate that changes preserve forward-compatibility guarantees

---

## Relationship to PRD

This document is **strictly subordinate** to the Phase 0 PRD. It:

- Translates PRD requirements into data-layer constraints
- Makes implicit schema rules explicit
- Does **not** introduce new features or requirements
- Serves as a "compiler" from product requirements to implementation constraints

Any contradiction between this brief and the PRD must be resolved in favor of the PRD.

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-28 | Initial Schema-First Implementation Brief |
| 1.1 | 2026-02-02 | Updated for Kernel v2.0 (RFC 8785 JCS canonicalization) |

---

*For questions or amendments, update the authoritative PRD first, then regenerate this brief.*
