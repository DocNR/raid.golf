# Identifier Glossary — Taxonomy & Disambiguation

**Status:** DRAFT / NON-NORMATIVE / PLANNING ONLY  
**Purpose:** Prevent confusion between identifiers in the kernel-first on-course model  

---

## 0) Overview

This glossary exists to prevent exactly the kind of confusion that arises when multiple identifier types coexist in a distributed system.

**Key principle:**

Not all identifiers are equal. Some are **trust anchors** (content-addressed, immutable). Others are **references** (stable, addressable). Still others are **transport artifacts** (incidental, ephemeral).

Understanding which is which prevents subtle bugs and semantic drift.

---

## 1) Three-Tier Identifier Taxonomy

### Tier 1: Trust / Identity (Kernel-Critical)

Content-addressed, immutable identifiers that participate in **verification** and **trust**.

Examples:

- `fss_hash`
- `template_hash`
- `course_hash`
- Attestation signatures

**Property:** These MUST NOT change. Any change produces a new identifier.

---

### Tier 2: Stable Logical References (Addressable)

Logical identifiers that provide **continuity** but not **immutability**.

Examples:

- Addressable course reference: `(kind:pubkey:d)`
- `round_uid` (stable grouping key)

**Property:** These MAY evolve over time (e.g., course republishing), but do NOT participate in verification.

---

### Tier 3: Transport Artifacts (Incidental)

Implementation or transport details with **no semantic authority**.

Examples:

- Nostr event IDs
- Relay URLs
- Timestamps (in some contexts)

**Property:** These are incidental and MUST NOT be treated as truth anchors.

---

## 2) Identifier Definitions (Detailed)

### A) Course Identifiers

#### `course_id` (local)

- **What it is:** A stable local identifier for a course record in the local database
- **Where it lives:** Local DB only
- **Purpose:** Internal reference when building rounds and snapshots
- **Type:** Tier 3 (local artifact)
- **Not used for:** Cross-client identity or verification

---

#### Addressable Course Reference: `(kind:pubkey:d)`

- **What it is:** A tuple that defines an addressable course definition on Nostr
- **Where it lives:** Nostr events (e.g., kind 33501)
- **Components:**
  - `kind` — Event kind (e.g., 33501)
  - `pubkey` — Author's public key (who controls this namespace)
  - `d` — Stable logical identifier within (kind, pubkey)
- **Purpose:** Stable, addressable identifier for a published course
- **Type:** Tier 2 (stable logical reference)
- **Important rule:** Multiple events may exist over time with the same `(kind:pubkey:d)`; that's expected

**Common mistake:** Treating `d` alone as an identifier.

**Correct framing:** The full tuple `(kind:pubkey:d)` defines addressability, not `d` by itself.

**Shorthand:** `a = kind:pubkey:d` (per NIP-01)

**Not authoritative for:** Historical rounds, verification, or scoring logic.

---

#### `course_hash`

- **What it is:** SHA-256 hash of a canonical course snapshot JSON
- **Where it lives:** Round initiation facts, `fss` payloads, projections
- **Purpose:** Content-addressed identity of an exact playable course configuration
- **Type:** Tier 1 (trust anchor)
- **Formula:** `course_hash = SHA-256(UTF-8(JCS(course_snapshot_json)))`
- **Used for:** Binding rounds to immutable course state, verification
- **Not the same as:** Addressable course reference `(kind:pubkey:d)`

**Rule:** Any change to course snapshot JSON produces a new `course_hash`.

---

### B) Round & Score Identifiers

#### `round_uid`

- **What it is:** A stable identifier for a single round instance
- **Where it lives:** Local DB, `fss` payloads, Nostr projections
- **Purpose:** Group all facts, snapshots, and attestations for one round
- **Type:** Tier 2 (stable logical reference)
- **How generated:** Implementation choice (UUID, deterministic hash, etc.)
- **Important:** This is **not** a Nostr event ID

**Common mistake:** Confusing `round_uid` with event IDs.

**Correct usage:** `round_uid` is semantic; event IDs are transport.

---

#### `stroke_fact_id`

- **What it is:** Local identifier for a single immutable stroke entry
- **Where it lives:** Local DB only
- **Purpose:** Audit trail and reconstruction
- **Type:** Tier 3 (local artifact)
- **Not published directly** (by default)

---

### C) Snapshot & Hashing

#### `fss` (Final Score Snapshot)

- **What it is:** Canonical JSON document describing a completed score for one player in one round
- **Where it lives:**
  - Local DB (derived from stroke facts)
  - Snapshot bundle payload (exported)
- **Type:** Data object, **not an identifier**
- **Properties:**
  - Human-readable
  - Immutable once created
  - Represents data, not identity
- **Any change:** Produces a new `fss`

**Rule:** `fss` is what you hash. It is **not** what you sign.

---

#### `fss_hash`

- **What it is:** SHA-256 hash of the canonical `fss` JSON
- **Where it lives:** Attestation facts, verification logic, projections
- **Purpose:** Semantic identity of that exact score state
- **Type:** Tier 1 (trust anchor)
- **Formula:** `fss_hash = SHA-256(UTF-8(JCS(fss_json)))`
- **Used by:**
  - Attestation facts
  - Verification logic
  - Third-party reproduction

**Critical rule:** Attestations sign **`fss_hash`**, not `fss`.

**Mirrors kernel pattern:**

- `template` → `template_hash`
- `fss` → `fss_hash`

---

### D) Attestation Identifiers

#### Attestation Fact

- **What it is:** An immutable statement: `marker_pubkey` attests `fss_hash`
- **Where it lives:**
  - Local DB
  - Nostr event (projection)
- **Type:** Tier 1 fact
- **What it does NOT do:** It does not store scores; it stores agreement

**Rule:** Attestations are append-only. Revocations are new facts.

---

#### `marker_pubkey`

- **What it is:** The signer's public key
- **Purpose:** Identity of the attesting party
- **Kernel meaning:** "Who is claiming this snapshot is correct?"

---

### E) Bundles & Projections

#### Snapshot Bundle

- **What it is:** A retrievable payload containing the `fss` JSON
- **Purpose:** Allow others to recompute `fss_hash` and verify attestations
- **Type:** Distribution artifact
- **Minimum for verification:** Yes

**Contents:**

- `fss` JSON (exact canonical payload)
- Optional: course snapshot, rules references

---

#### Full Fact Bundle (Optional, Later)

- **What it is:** Append-only export of all round facts + `fss` + attestations
- **Purpose:** Full audit, dispute resolution, re-projection
- **Type:** Distribution artifact
- **Not required early**

---

#### Round Summary Projection

- **What it is:** A compact, human-readable summary of the round
- **Where it lives:** Nostr only (optional)
- **Authority level:** Informational only; must reference `fss_hash`
- **Type:** Tier 3 (projection)

---

### F) Nostr-Specific Identifiers

#### Nostr Event ID

- **What it is:** The event's unique identifier as computed by Nostr (hash of serialized event)
- **Purpose:** Authorship, timestamp, relay indexing
- **Type:** Tier 3 (transport artifact)
- **Not used for:** Round identity, course identity, score identity

**Rule:** Event IDs are incidental. Do not treat as semantic identity.

---

#### Replaceable vs Addressable Events

- **Replaceable:** Newer events with same `(kind, pubkey)` replace older ones
- **Addressable:** Newer events with same `(kind, pubkey, d)` replace older ones

**Usage in this model:**

- **Addressable course definitions** are acceptable for discovery (Tier 2)
- **Live scorecards** may be replaceable for UX
- **Facts** (rounds, strokes, attestations) are NEVER replaceable

**Rule:** Trust anchors (Tier 1) are never replaceable or addressable.

---

## 3) Common Confusions (Explicitly Addressed)

### ❌ "Is the Nostr event ID the round ID?"

**No.**

- Event IDs are transport artifacts (Tier 3)
- `round_uid` is the semantic grouping key (Tier 2)

---

### ❌ "Is `course_hash` the same as the addressable course reference?"

**No.**

- `course_hash` is content-addressed identity (Tier 1, immutable)
- Addressable course reference `(kind:pubkey:d)` is a stable logical name (Tier 2, mutable over time)

---

### ❌ "If the score changes, do we edit `fss`?"

**Never.**

You generate a **new `fss`** with a new `fss_hash`.

Old `fss` + old `fss_hash` + old attestations remain valid for the old state.

---

### ❌ "If someone re-attests, do we delete the old attestation?"

**Never.**

Attestations are append-only facts. Projections decide which matter.

---

### ❌ "Can I sign `fss` directly instead of `fss_hash`?"

**Not recommended.**

- `fss` is a large JSON object
- Signing `fss_hash` is more compact and deterministic
- Verification is simpler with `fss_hash`

---

### ❌ "Is `d` alone an addressable identifier?"

**No.**

The full tuple `(kind:pubkey:d)` defines addressability, not `d` by itself.

---

## 4) Identifier Usage Rules (Summary Table)

| Identifier                     | Tier | Immutable? | Participates in Verification? | Where Used                     |
| ------------------------------ | ---- | ---------- | ----------------------------- | ------------------------------ |
| `fss_hash`                     | 1    | Yes        | Yes                           | Attestations, verification     |
| `template_hash`                | 1    | Yes        | Yes                           | KPI/rules evaluation           |
| `course_hash`                  | 1    | Yes        | Yes                           | Round binding, verification    |
| `(kind:pubkey:d)` (course ref) | 2    | No         | No                            | Discovery, UX                  |
| `round_uid`                    | 2    | Yes        | Grouping only                 | Fact grouping, projections     |
| `fss`                          | Data | Yes        | Payload only                  | Bundles, local DB              |
| `stroke_fact_id`               | 3    | Yes        | Audit trail only              | Local DB                       |
| Nostr event ID                 | 3    | Yes        | No                            | Transport, authorship          |
| Round summary projection       | 3    | No         | No                            | Nostr UX                       |

---

## 5) One-Sentence Takeaways

### On `fss` and `fss_hash`

> **If it is data, call it `fss`. If it is identity, call it `fss_hash`.**

### On course references

> **Addressable courses are identified by `(kind:pubkey:d)`; the `d` tag alone is just a local name, not an address.**

### On verification

> **Only Tier 1 identifiers (content-addressed hashes) participate in trust. Everything else is convenience.**

---

**End of Identifier Glossary**