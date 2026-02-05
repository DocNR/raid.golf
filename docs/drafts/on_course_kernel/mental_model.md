# Mental Model — Kernel-First On-Course Rounds

**Status:** DRAFT / NON-NORMATIVE / PLANNING ONLY  
**Purpose:** Conceptual clarity for future implementation  

---

## 1) Core Principle

**Local database is the canonical source of truth.**

- All round facts originate locally
- Nostr is projection + distribution only
- Nothing published to Nostr can mutate local truth

---

## 2) End-to-End Data Flow

```
┌─────────────────────────────────────────────────┐
│            LOCAL DEVICE (TRUTH)                 │
└─────────────────────────────────────────────────┘

    ┌─────────────────┐
    │  Course Facts   │  ← local cache or embedded
    │  (local cache)  │     snapshot in initiation
    └────────┬────────┘
             │
             │ references
             ▼
    ┌─────────────────┐
    │  Round Facts    │  ← immutable
    │  (initiation)   │     (participants, course_hash, etc.)
    └────────┬────────┘
             │
             │ append-only
             ▼
    ┌─────────────────┐
    │  Stroke Facts   │  ← immutable
    │  + Corrections  │     (hole scores, putts, etc.)
    └────────┬────────┘
             │
             │ pure function (derived)
             ▼
    ┌─────────────────────────────────┐
    │  fss (Final Score Snapshot)     │  ← canonical JSON
    │  - per-player completed state   │     data object
    │  - content-addressed            │
    │  - fss_hash = SHA-256(JCS(fss)) │
    └────────┬────────────────────────┘
             │
             │ attested-by
             ▼
    ┌─────────────────────────────────┐
    │  Attestation Facts              │  ← immutable
    │  (marker signatures)            │     (marker signs fss_hash)
    └────────┬────────────────────────┘
             │
             │ derived (pure function)
             ▼
    ┌─────────────────────────────────┐
    │  Verification Projection        │  ← derived
    │  (verified / unverified)        │     (not authoritative)
    └────────┬────────────────────────┘
             │
             │ optional publish
             ▼

┌─────────────────────────────────────────────────┐
│        NOSTR (PROJECTION & DISTRIBUTION)        │
└─────────────────────────────────────────────────┘

    ┌─────────────────┐
    │  Course Events  │  (e.g. kind 33501)
    │  (discovery)    │  (addressable, mutable)
    └─────────────────┘

    ┌─────────────────┐
    │  Snapshot       │  (fss JSON payload)
    │  Bundle         │  (retrievable for verification)
    └─────────────────┘

    ┌─────────────────┐
    │  Attestation    │  (marker events)
    │  Events         │  (signatures binding to fss_hash)
    └─────────────────┘

    ┌─────────────────┐
    │  Round Summary  │  (scores, metadata, refs)
    │  Projection     │  (human-readable display)
    └─────────────────┘
```

---

## 3) Trust Boundaries (Critical)

### Boundary 1: Authoritative Local Data

**What lives here:**

- Round initiation facts (immutable)
- Stroke facts (immutable, append-only)
- Correction facts (append-only, reference prior facts)
- `fss` objects (derived from facts, canonical JSON)
- `fss_hash` values (content-addressed identity)
- Attestation facts (immutable signatures)

**Properties:**

- Never mutated in place
- Never deleted
- Always regenerable from facts (for `fss`)
- Tamper-evident (via hashing and signatures)

**Authority:** This is the only source of truth.

---

### Boundary 2: Derived Projections

**What lives here:**

- Verification status (verified / unverified)
- Scorecards (visual representations)
- Leaderboards
- Round summaries
- Analytics

**Properties:**

- Computed from authoritative data
- Regenerable at any time
- Never imported back into authoritative tables
- Can change as new attestations arrive
- Deletion does not affect authoritative reads

**Authority:** None. These are conveniences.

---

### Boundary 3: Nostr Transport

**What lives here:**

- Course discovery events
- Snapshot bundles (retrievable payloads)
- Attestation events (distributed signatures)
- Round summary events (projections)

**Properties:**

- Distribution only, never truth
- May be partial, unavailable, or conflicting
- Relays provide no guarantees
- Cannot change local authoritative data

**Authority:** Zero. Nostr is a broadcast medium.

---

## 4) Key Mental Anchors

### Anchor 1: "Left side = truth, right side = broadcast"

- Left (local DB): authoritative, immutable, append-only
- Right (Nostr): projection, distribution, optional

Nothing on the right can change the left.

---

### Anchor 2: "Attestations sign identity, not data"

- Markers sign **`fss_hash`** (content-addressed identity)
- They do NOT sign `fss` (the data object)
- This makes verification deterministic

If `fss` changes → new `fss_hash` → new attestation required.

---

### Anchor 3: "Verification is a projection"

- Verification status is computed from facts
- It is NOT a fact itself
- Same facts + same attestations → same verification result
- New attestations → recompute verification projection

---

### Anchor 4: "Nostr events are inputs, not truth"

- Fetching attestation events from Nostr provides **inputs** to verification
- The verification logic runs locally
- Relays cannot forge signatures
- But relays can withhold, reorder, or provide partial data

Trust comes from signatures, not from relays.

---

## 5) What Happens When...

### Scenario A: Player finalizes a round

1. Local app computes `fss` (canonical JSON) from stroke facts
2. Local app computes `fss_hash = SHA-256(UTF-8(JCS(fss)))`
3. `fss` and `fss_hash` stored locally (or `fss` cached as derived)
4. Optionally: publish `fss` as a snapshot bundle to Nostr

**Result:** Round is finalized locally. Nostr publication is optional.

---

### Scenario B: Marker attests

1. Marker reviews `fss` (the data)
2. Marker signs attestation fact binding their pubkey to `fss_hash`
3. Attestation fact stored locally (immutable)
4. Optionally: publish attestation event to Nostr

**Result:** Attestation is a local fact. Nostr publication makes it discoverable.

---

### Scenario C: Third party verifies

1. Fetch `fss` payload (from bundle or local cache)
2. Canonicalize and hash: confirm `fss_hash` matches
3. Fetch attestation events (from Nostr or local)
4. Verify signatures on attestations
5. Compute verification projection: verified / unverified

**Result:** Verification is deterministic and reproducible.

---

### Scenario D: Player corrects a score

1. Player publishes a **new stroke fact** (correction)
2. Correction references the prior fact it supersedes
3. A **new `fss`** is derived from updated facts
4. A **new `fss_hash`** is computed
5. New attestations required for the new `fss_hash`

**Result:** History is preserved. Old `fss_hash` + attestations remain valid for old state.

---

## 6) What Does NOT Happen

### ❌ Round facts are never edited in place

Corrections are append-only new facts.

### ❌ `fss_hash` is never recomputed on read

It is computed once and stored.

### ❌ Attestations never reference mutable objects

They bind to `fss_hash`, which is immutable.

### ❌ Nostr events do not override local truth

Local DB is authoritative. Nostr is distribution.

### ❌ Verification status is not stored as a fact

It is a projection, recomputed as needed.

---

## 7) Summary (One-Sentence Mental Model)

> **Rounds are immutable facts; `fss` snapshots are immutable interpretations; attestations are immutable signatures; verification is a projection; Nostr is distribution.**

---

**End of Mental Model**