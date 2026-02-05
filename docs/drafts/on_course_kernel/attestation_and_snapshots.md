# Attestation & Snapshots — Core Trust Model

**Status:** DRAFT / NON-NORMATIVE / PLANNING ONLY  
**Purpose:** Define attestation semantics and snapshot identity for kernel-first rounds  

---

## 1) Purpose

This document defines how attestation works safely in a kernel-first on-course model, using:

- Content-addressed snapshots (`fss` + `fss_hash`)
- Immutable attestation facts
- Deterministic verification
- Optional bundling for reproducibility

---

## 2) Roles

- **Player** — The golfer whose score is being recorded
- **Marker (Attester)** — A playing partner who confirms the player's final score
- **Scorer** — Any party entering strokes during play (entry ≠ truth)

---

## 3) Final Score Snapshot (`fss`)

### 3.1 Definition

An **`fss` (Final Score Snapshot)** is a canonical JSON document that fully describes a player's completed score state for a round.

### 3.2 Properties

- **Canonical JSON** (per RFC 8785 JCS)
- **Human-readable**
- **Immutable** once created
- **Represents data**, not identity

### 3.3 Contents (Conceptual)

At minimum:

- `round_uid`
- `player_pubkey`
- `course_hash` (or course snapshot reference)
- `holes_scope` (e.g., 1–18, 1–9)
- per-hole strokes
- optional: putts, penalties
- optional: rules references (e.g., net vs gross interpretation)

Totals may be included or derived.

### 3.4 Where it exists

- Local DB (derived from stroke facts)
- Snapshot bundle payload (exported for verification)
- Optionally cached by other clients

### 3.5 What it answers

> "What exactly was this player's final score?"

---

## 4) Snapshot Hash (`fss_hash`)

### 4.1 Definition

An **`fss_hash`** is the cryptographic digest of an `fss`:

```
fss_hash = SHA-256( UTF-8( JCS( fss_json ) ) )
```

Where:

- `JCS(fss_json)` produces canonical JSON per RFC 8785
- UTF-8 encoding without BOM
- SHA-256 hash output as lowercase hexadecimal (64 characters)

### 4.2 Properties

- **Content-addressed identity**
- **Fixed-length**
- **Opaque** (not human-readable)
- **Collision-resistant**
- **Immutable**

Any change to `fss` produces a new `fss_hash`.

### 4.3 Where it exists

- Inside attestation facts
- Inside verification logic
- Inside round summaries and projections

### 4.4 What it answers

> "Which exact snapshot is being attested to?"

---

## 5) `fss` vs `fss_hash` (Critical Distinction)

These two terms are **not interchangeable**.

| Aspect                  | `fss` (data)          | `fss_hash` (identity) |
| ----------------------- | --------------------- | --------------------- |
| Type                    | JSON document         | SHA-256 hash          |
| Readable?               | Yes                   | No (opaque)           |
| Signed directly?        | No                    | Yes                   |
| Transported?            | Yes (in bundles)      | Yes (in attestations) |
| Trust anchor?           | Indirectly            | **Yes**               |
| Can it change?          | New snapshot required | New hash required     |
| Used for verification?  | Payload for hashing   | Identity for matching |

### Rule (normative for mental model)

> Attestations never sign "`fss`".  
> Attestations sign **`fss_hash`**.

This mirrors the established kernel pattern:

- `template` → `template_hash`
- `fss` → `fss_hash`

**Naming convention:**

Objects are named `<thing>`, and their content-addressed identity is named `<thing>_hash` (e.g., `template` / `template_hash`, `fss` / `fss_hash`).

---

## 6) Attestation Fact

### 6.1 Definition

An **attestation fact** is an immutable statement:

> "I, `marker_pubkey`, attest that `fss_hash` correctly represents `player_pubkey`'s final score for `round_uid`."

### 6.2 Required Fields

- `round_uid`
- `player_pubkey`
- `fss_hash`
- signer pubkey (marker)
- signature (transport-specific)

Optional:

- pointer to snapshot bundle location
- attestation type (final / partial)

### 6.3 Storage Semantics

- Attestations are stored locally as **immutable facts**
- No updates or deletes
- Later disagreement is expressed via a **new attestation fact**, not mutation

---

## 7) Live Scoring vs Final Truth

### 7.1 Live Scorecards (UX Only)

- Replaceable or mutable representations are allowed for **display**
- They are explicitly **non-authoritative**
- They must **never be attested**

### 7.2 Authoritative Boundary

Only the **`fss_hash`** may be attested and verified.

---

## 8) Verification Policy (Projection)

Verification is a **derived projection**, not a fact.

### 8.1 Example Policies (Illustrative)

- **Basic:** ≥ 1 valid marker attestation
- **Strict:** ≥ 1 attestation from a listed participant
- **Stricter:** ≥ 2 attestations if group size ≥ 3

### 8.2 Inputs

The policy consumes:

- `fss_hash`
- attestation facts
- round metadata (participants, etc.)

### 8.3 Outputs

- verified / unverified
- verification strength (optional)

Policies MAY later be versioned as templates.

---

## 9) Data Bundling for Reproducibility

Attestation alone proves a signature exists.  
**Bundles provide reproducibility.**

### 9.1 Snapshot Bundle (Minimum Viable)

**Contains:**

- `fss` JSON (exact payload)
- course reference or minimal course snapshot
- optional rules references

**Verification steps:**

1. Fetch `fss` JSON from bundle
2. Canonicalize + hash: `computed_hash = SHA-256(UTF-8(JCS(fss)))`
3. Confirm `computed_hash == fss_hash`
4. Verify attestation signature binds to `fss_hash`

**Outcome:** Definitive final score verification.

---

### 9.2 Full Fact Bundle (Audit-Grade, Optional)

**Contains:**

- Round initiation fact
- All stroke facts
- Correction facts
- Derived `fss` (can be recomputed)
- Attestations

**Enables:**

- Full round reconstruction
- Dispute inspection
- Independent projection recomputation

**Not required for early phases.**

---

## 10) Conflict Handling (Kernel-Safe)

### 10.1 Multiple `fss` for Same Round/Player

- All `fss` snapshots may coexist
- Attestations bind to specific `fss_hash` values
- Projections choose "current best" deterministically (e.g., most attestations, latest with attestation)

**Rule:** Never delete history.

---

### 10.2 Attestation Revocation / Change

- Marker publishes a **new attestation fact**
- Projections consider the most recent attestation **from that marker**
- Old attestations remain for audit trail

**Rule:** Attestations are append-only.

---

### 10.3 Missing `fss` Payload

- Attestation recorded as **unverifiable**
- `fss` is not considered verified until payload is retrievable

**Rule:** Verification requires both signature and payload.

---

## 11) Why Attestations Bind to `fss_hash`

### Problem if attestations signed `fss` directly

- `fss` is a large JSON object
- Signing large payloads is cumbersome
- Ambiguity around canonicalization at signing time
- Replay attacks if `fss` is mutable

### Solution: Sign `fss_hash`

- `fss_hash` is a fixed-length, opaque identifier
- Content-addressed: same `fss` → same `fss_hash`
- Tamper-evident: any change to `fss` → new `fss_hash`
- Signatures become compact and unambiguous

**Verification logic:**

1. Hash the claimed `fss` → `computed_hash`
2. Confirm `computed_hash == attested_fss_hash`
3. Verify signature on attestation

This is deterministic and reproducible.

---

## 12) Summary (Kernel Alignment)

This model preserves kernel invariants:

- **Facts are immutable** (stroke facts, corrections, attestations)
- **Snapshots are content-addressed** (`fss_hash`)
- **Attestations are append-only facts**
- **Verification is a derived projection**
- **History is never rewritten**

---

## 13) Explicit Non-Goals (For This Draft)

- No event-kind assignments
- No relay policy
- No UX flows
- No performance optimizations
- No production guarantees

---

## 14) Next Steps (When Implementation Begins)

Before implementation:

- Revisit `fss` schema (exact required fields)
- Confirm canonicalization rules (RFC 8785 JCS)
- Decide minimal vs full bundle strategy
- Write test vectors for `fss` canonicalization and `fss_hash` computation
- Align with current NIP drafts (if applicable)

---

**End of Attestation & Snapshots**
