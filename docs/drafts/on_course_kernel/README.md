# On-Course Kernel Model — Draft Documentation

**Status:** DRAFT / NON-NORMATIVE / PLANNING ONLY  
**Purpose:** Design preservation and future planning  
**Not authorized for implementation**  
**Revisit before Milestone 4 (On-Course Scoring)**

---

## Problem Statement

On-course golf rounds require a **kernel-first, local-truth model** that:

- Treats the local database as the authoritative source of truth
- Uses immutable facts and content-addressed snapshots
- Makes attestation explicit and verifiable
- Uses Nostr strictly as a projection and distribution layer
- Enables full round reproducibility via optional data bundles

Without this model, historical rounds become ambiguous, attestations lose semantic meaning, and verification becomes non-deterministic.

---

## What This Is / What This Is Not

### ✅ What this is

- **Planning documentation** for a future phase of RAID
- **Design intent preservation** to reduce future confusion
- **Conceptual alignment** with existing kernel principles
- **Identifier disambiguation** to prevent implementation mistakes

### ❌ What this is NOT

- Not a normative specification
- Not implementation-ready code or schemas
- Not Nostr event kind assignments
- Not a finalized technical standard
- Not a replacement for existing kernel contracts

All existing kernel contracts, specs, and roadmap commitments remain authoritative.

---

## Document Structure

This draft consists of four focused documents:

### 1. [mental_model.md](./mental_model.md) — System-Level Flow & Trust Boundaries

Explains the end-to-end mental model for kernel-first on-course rounds:

- Data flow: local facts → snapshots → attestations → projections → Nostr
- Clear separation between authoritative local data, derived projections, and Nostr transport
- Explicit trust boundaries
- Simple flow diagram

**Key insight:** Local database is truth. Nostr is projection + distribution. Nothing on Nostr can change local truth.

---

### 2. [attestation_and_snapshots.md](./attestation_and_snapshots.md) — Core Trust Model

Defines how attestation works safely using content-addressed snapshots:

- Definition of `fss` (Final Score Snapshot) as canonical JSON data
- Definition of `fss_hash` as content-addressed identity
- Explicit distinction: data vs identity
- Attestation semantics (who signs what, and why)
- Snapshot bundles vs full fact bundles
- Conflict handling at a conceptual level

**Key insight:** Attestations sign `fss_hash`, not mutable scorecards. This makes verification deterministic and history tamper-evident.

---

### 3. [identifier_glossary.md](./identifier_glossary.md) — Identifier Taxonomy & Disambiguation

Prevents confusion between identifiers by clearly distinguishing:

- Local course IDs vs addressable course references
- `round_uid` vs Nostr event IDs
- `fss` vs `fss_hash`
- Attestation facts vs verification projections
- Bundles vs projections
- Which identifiers participate in verification and which do not

**Key insight:** Three-tier taxonomy (trust/identity, stable logical references, transport artifacts) clarifies what each identifier actually means.

---

## Relationship to Existing Specs

This draft documentation builds on and references (but does not replace):

- **KERNEL_CONTRACT_v2.md** — Frozen kernel invariants (immutable facts, content-addressed templates, derived projections)
- **course_identity_and_snapshots.md** — Course container vs snapshot model, content-addressed course hashes
- **multiplayer-competition-model.md** — Competition rules, embedded context, attestation flow

All design choices in this draft align with these upstream authorities.

---

## Next Steps (When Ready to Implement)

Before implementation begins:

1. Revisit all four draft documents
2. Confirm snapshot schema and canonicalization rules
3. Decide minimal vs full bundle strategy
4. Align with current NIP drafts (if applicable)
5. Write test vectors for `fss` canonicalization and `fss_hash` computation
6. Update any conflicts with evolved kernel contracts

---

## Summary

**Goal:** Preserve design intent now, reduce confusion later.

**Core principle:** Rounds are immutable facts; `fss` snapshots are immutable interpretations; attestations are immutable signatures; verification is a projection; Nostr is distribution.

---

**End of README**