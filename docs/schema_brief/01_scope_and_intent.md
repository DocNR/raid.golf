# 1. Scope & Intent

[← Back to Index](00_index.md)

---

## 1.1 Purpose of This Document

This Schema-First Implementation Brief serves as the **authoritative data architecture specification** for RAID Phase 0. It translates the product requirements defined in the PRD into concrete, enforceable data-layer constraints.

The brief ensures that:

1. **Implementation is deterministic** — Two developers (or AI agents) given the same PRD and this brief will produce compatible schemas
2. **Constraints are explicit** — Implicit assumptions about immutability, identity, and data ownership are made concrete
3. **Drift is prevented** — Schema evolution cannot violate foundational principles without explicit PRD amendment
4. **Reproducibility is guaranteed** — Historical analyses remain valid indefinitely through content-addressed templates

---

## 1.2 Relationship to the Phase 0 PRD

This document is **strictly subordinate** to the PRD located at:

```
/Users/danielwyler/raid.golf/docs/PRD_Phase_0_MVP.md
```

The relationship is hierarchical:

```
PRD (Product Requirements)
    ↓ translates to
Schema-First Brief (Data Architecture)
    ↓ informs
Implementation (Code)
```

### Governing Principles

1. **No new requirements** — This brief does not introduce features, entities, or behaviors not present in the PRD
2. **Strict derivation** — All constraints derive from explicit PRD statements or strict logical implications
3. **PRD precedence** — Any conflict between this brief and the PRD is resolved in favor of the PRD
4. **Amendment process** — Changes to data architecture require PRD updates first, followed by brief regeneration

### What This Document Does

- Defines conceptual schema for all authoritative entities
- Specifies identity mechanisms (primary keys, content-addressing)
- Enumerates immutability invariants
- Establishes canonicalization and hashing contracts
- Lists prohibited capabilities to prevent scope creep

### What This Document Does Not Do

- Provide SQL implementation (vendor-specific)
- Define migration paths or upgrade strategies
- Specify API contracts or wire formats
- Include performance optimization guidance
- Describe UI/UX requirements

---

## 1.3 Explicit Exclusions

The following are **intentionally excluded** from this Schema-First Brief:

### 1.3.1 Implementation Details

**Not Covered:**
- SQL dialect specifics (SQLite, PostgreSQL, etc.)
- Index strategies or query optimization
- ORM mappings or code generation
- Database connection pooling or transaction management
- File system layout or directory structure

**Rationale:** These are implementation concerns that vary by platform and language. The schema remains conceptual to support Python, Swift, and future platforms uniformly.

### 1.3.2 Migration & Evolution

**Not Covered:**
- Schema migration scripts
- Backward-compatibility strategies for schema changes
- Data backfill or transformation procedures
- Version upgrade paths from pre-MVP prototypes

**Rationale:** Phase 0 is greenfield. Migration concerns arise in Phase 1+ when the schema is established and must evolve.

### 1.3.3 User Interface & Interaction

**Not Covered:**
- CLI command syntax or output formatting
- Query result pagination or sorting
- Export file naming conventions
- User preferences or configuration storage

**Rationale:** UI/UX is a separate concern. This brief focuses solely on the data layer.

### 1.3.4 Network & Sync

**Not Covered:**
- Nostr event publishing mechanisms
- Conflict resolution for multi-device sync
- Authentication or authorization models
- Network protocols or wire formats

**Rationale:** Phase 0 is strictly local-first. Network capabilities are Phase 1+ concerns, though the schema is designed to support them.

### 1.3.5 Performance & Scale

**Not Covered:**
- Expected data volumes or growth projections
- Query performance benchmarks
- Caching strategies
- Database size limits or archival policies

**Rationale:** MVP priorities are correctness and reproducibility, not scale. Performance optimization is premature at this stage.

---

## 1.4 Intended Audience

This document is written for:

### Primary Audience

- **Senior software engineers** implementing Phase 0
- **Data architects** validating schema design
- **AI coding assistants** (Claude, GitHub Copilot, etc.) generating schema-related code

### Secondary Audience

- **Code reviewers** validating PRD compliance
- **Future maintainers** understanding design rationale
- **External contributors** (if project opens)

### Assumed Knowledge

Readers are expected to understand:

- Relational data modeling (entities, relationships, constraints)
- Immutability concepts in data systems
- Content-addressing and cryptographic hashing
- JSON serialization and canonicalization
- Local-first architecture principles

No domain knowledge of golf or launch monitor technology is required to understand the schema.

---

## 1.5 Document Maintenance

### Update Policy

This brief is **regenerated, not edited** when the PRD changes.

**Process:**

1. Update PRD with requirement changes (version bump)
2. Regenerate this brief from updated PRD
3. Compare new brief to previous version (diff review)
4. Update implementation to comply with new constraints

**Prohibited:** Ad-hoc edits to this brief without PRD updates create divergence and undermine the schema-first approach.

### Version Alignment

The brief version must track PRD version:

| PRD Version | Brief Version | Status |
|-------------|---------------|--------|
| 1.0 | 1.0 | Active |

Future versions will maintain strict alignment.

---

## 1.6 Terminology

This document uses precise terminology. See the PRD Glossary (Section 9.1) for definitions.

**Key Terms in This Brief:**

- **Authoritative** — Source of truth; not derived or cached
- **Derived** — Computed from authoritative data; regenerable
- **Immutable** — Cannot be modified after creation
- **Content-addressed** — Identity based on content hash, not name
- **Canonical** — Deterministic representation (e.g., sorted keys)
- **Projection** — Read-only export artifact

---

[Next: Authoritative Entities →](02_authoritative_entities.md)
