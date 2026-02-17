# Attestation Strategy Review — Nostr Constraints & Reconciliation

**Status:** REVIEW DOCUMENT
**Date:** 2026-02-17
**Input:** Conversation transcript (multiplayer finalization & attestation design), existing kernel docs, codebase analysis
**Purpose:** Reconcile conversation-level design decisions with existing specs, identify gaps, and flag Nostr-specific constraints that drove the design

---

## 1) Context

A design conversation explored how multiplayer score attestation should work in RAID Golf over Nostr. Three strategies were compared:

1. **Semantic Hash Consensus** — all participants publish identical content-addressed hash
2. **Two-Phase Commit** — explicit "ready" phase before finalization
3. **Version Chain Model** — sequential versioning with fork detection

The conversation converged on **Semantic Hash Consensus** as the preferred strategy. This review evaluates that decision against the existing kernel design documents and Nostr protocol realities.

---

## 2) What the Conversation Got Right

### 2.1 Content-Addressed Consensus Over Ordering

The core insight — use a deterministic hash of shared score state for consensus rather than relying on timestamps or version chains — is sound and aligns with the kernel's established pattern:

- `template` → `template_hash` (compute once, immutable)
- `course_snapshot` → `course_hash` (embedded in initiation, never re-resolved)
- `fss` → `fss_hash` (content-addressed score identity)

**Why this matters for Nostr:** Nostr event timestamps (`created_at`) are self-reported by the publishing client. A user can set any timestamp. Ordering-based strategies (version chains, "keep latest") are therefore vulnerable to manipulation. Content-addressed hashing sidesteps this entirely — the hash either matches or it doesn't, regardless of when events were published.

### 2.2 Symmetric Authority

The conversation's preference for symmetric authority — both players publish their own 1502, neither is "primary" — is correct for Nostr's decentralized model. There is no coordinator, no server, no authority hierarchy. Each participant signs their own assertion independently.

### 2.3 Finish vs Finalize Distinction

- **Finish** = all holes scored, draft complete (addressable scorecard, kind 30501, mutable)
- **Finalize** = publish immutable final record (kind 1502, regular event, cannot be replaced)

This maps cleanly to the existing implementation:
- `ActiveRoundStore.finishRound()` → triggers 1502 publication
- Kind 30501 (addressable replaceable) serves as the mutable "finished" state
- Kind 1502 (regular event) serves as the immutable commit

### 2.4 Local DB as Truth, Relays as Transport

"Relay deletions do not remove local truth" — this matches `mental_model.md` exactly. Relays are a broadcast medium with zero authority.

---

## 3) Nostr Constraints That Drove the Design

The conversation's concerns were not theoretical — they address real protocol-level constraints that the existing codebase handles inadequately.

### 3.1 Multiple 1502 Events Per User Per Round

**Nostr constraint:** Any user can publish any number of regular events with any kind number. There is no protocol-level enforcement of "one 1502 per round per user."

**Current codebase handling:** Deduplication by `created_at` — keep newest per author. No content-based resolution.

**Problem:** If User A publishes two conflicting 1502 events (different scores), the current logic picks the one with the later `created_at`. Since `created_at` is self-reported, this is trivially manipulable.

**Conversation's solution:** Semantic hash consensus. The hash is the identity, not the event. Multiple 1502s with the same hash are redundant (same assertion). Multiple 1502s with different hashes are a conflict (fork). This is a sound resolution strategy.

### 3.2 Timestamp Manipulation

**Nostr constraint:** `created_at` is a Unix timestamp set by the client. Relays may enforce rough bounds but are not required to. A client can backdate or future-date events.

**Current codebase handling:** `created_at` is trusted for:
- Deduplication (keep latest per author)
- Profile freshness (replaceable kind 0)
- Live scorecard updates (addressable replaceable kind 30501)

No validation against:
- Future-dated events
- Backdated events
- Monotonic ordering violations

**Conversation's solution:** Don't rely on timestamps for truth. Use content-addressed hashing for consensus. Timestamps become metadata, not trust anchors. This matches the identifier glossary's classification of timestamps as Tier 3 (transport artifacts).

### 3.3 Relay Deletion (NIP-09)

**Nostr constraint:** Users can publish kind 5 delete request events. Relays MAY honor them by removing the referenced events. Other relays may not. The original event may already be cached by other clients.

**Current codebase handling:** NIP-09 is not implemented. Stale cache persists indefinitely in `remote_scores_cache`.

**Conversation's solution:** Local DB must persist all events seen. Deletion events should be tracked as tombstones. Relays are transport, not durability. This is architecturally correct — the existing `RemoteScoresRepository` cache already accomplishes half of this by persisting scores locally, but lacks tombstone tracking.

### 3.4 Event ID vs Semantic Identity

**Nostr constraint:** Event IDs are computed from the serialized event (including metadata, timestamp, tags). Two events with identical score content but different timestamps produce different event IDs.

**Current codebase handling:** The WIP attestation spec (`nip101g_round_wip.md` section 5) references the final round record by its event ID (`["e", "<final_round_record_event_id>"]`). This creates a binding between attestation and a specific publication, not the score content.

**Conversation's concern:** If a user re-publishes the same scores (e.g., to a different relay set), the new event has a different ID. Attestations bound to the old event ID don't transfer. Content-addressed hashing solves this — `fss_hash` identifies the score meaning, not the publication.

---

## 4) Where the Conversation Oversimplified

### 4.1 "score_hash" vs "fss_hash" — Naming and Scope

The conversation used `score_hash` to mean "hash of the shared snapshot." The existing kernel docs define `fss_hash` as a **per-player** construct:

```
fss_hash = SHA-256(UTF-8(JCS(fss_json)))
```

Where `fss_json` describes **one player's** completed score in **one round**.

A multiplayer round with 4 players produces 4 `fss` documents and 4 `fss_hash` values. The conversation's "shared snapshot hash" is a **round-level aggregate** — a hash of all participants' combined scores. This is a different construct.

**Recommendation:** Keep `fss_hash` as per-player (aligns with existing docs). If round-level consensus is needed, define separately:

```
round_snapshot_hash = SHA-256(UTF-8(JCS({
  "round_uid": "...",
  "scores": [
    { "player": "<pubkey_1>", "fss_hash": "<hash_1>" },
    { "player": "<pubkey_2>", "fss_hash": "<hash_2>" }
  ]
})))
```

This keeps per-player attestation intact while enabling round-level consensus as an additional layer.

### 4.2 Liveness — What If Someone Never Publishes?

The conversation's clean model says "Consensus = all participants publish identical hash." But what if a player:
- Loses connectivity
- Quits the app
- Refuses to finalize

This creates a permanently "unfinalized" round under the binary model.

**Existing docs handle this better:** Verification is a **projection** with configurable policies (basic / strict / stricter). A round can be "verified by 3 of 4 participants" rather than requiring unanimity. The conversation's binary finalized/disputed model should be softened to a spectrum.

### 4.3 Score Publication vs Attestation — Unified in the 1502

The conversation treats "publishing your 1502" and "attesting" as similar acts. On reflection, this is correct for the multiplayer case:

- **1502 with `scored_by=self`** = self-assertion ("these are my scores")
- **1502 with `scored_by=other_player`** = attestation ("I confirm Player X's scores")

Both are Schnorr-signed 1502 events containing `fss_hash`. The `scored_by` tag distinguishes self-assertion from peer attestation. Self-assertions carry less weight than peer attestations — a player signing their own scores proves nothing about accuracy, only about what they claim.

**Consensus emerges naturally:** when multiple participants publish 1502 events with matching `fss_hash` for the same scored player, that IS multi-party attestation without a separate event kind.

A separate attestation kind would only be needed for non-participants (tournament officials, witnesses) or after-the-fact dispute resolution — deferred to a future phase.

### 4.4 Correction Flow — Not Addressed

The conversation doesn't cover what happens when a player discovers an error after finalization. The existing kernel model handles this via append-only corrections:

1. Player publishes correction fact
2. New `fss` derived from updated facts
3. New `fss_hash` computed
4. Previous attestations remain valid for the old `fss_hash`
5. New attestations required for the new `fss_hash`

This should be preserved in any implementation.

---

## 5) Gap Analysis: Current 1502 vs Attestation-Ready 1502

The current `NIP101gEventBuilder.buildFinalRecordEvent()` produces a kind 1502 with:

```
Tags: [e, initiation_id], [total, N], [score, hole, strokes]..., [p, pubkey]...
Content: optional notes string
```

**What's missing for attestation:**

| Missing Element | Why It Matters |
|---|---|
| `fss_hash` tag | No content-addressed identity for attestation to bind to |
| `course_hash` tag | Final record doesn't prove which course snapshot was used |
| `scored_by` as semantic anchor | Currently used for attribution but not for attestation binding |
| Canonical score payload | Content is free-text notes, not a canonical JSON snapshot |

**What an attestation-ready 1502 would need:**

```
Tags:
  [e, initiation_id]          — round reference
  [course_hash, <hex>]        — course identity (from initiation)
  [fss_hash, <hex>]           — content-addressed score identity
  [scored_by, <pubkey>]       — whose scores these are
  [total, N]                  — total strokes
  [score, hole, strokes]...   — per-hole scores
  [p, pubkey]...              — participants

Content: canonical fss JSON (the snapshot payload)
```

A separate attestation event kind is **not needed** for the common case. See section 6 for why.

---

## 6) Recommended Strategy: 1502-as-Attestation (Simplified Model)

### 6.1 Key Insight: The 1502 IS the Attestation

A separate attestation event kind is unnecessary for multiplayer rounds. When Player A publishes a kind 1502 with `scored_by=PlayerB` and `fss_hash=X`, that IS an attestation: "I, Player A, Schnorr-sign that Player B's score is X."

**Why this works:**

- Each participant publishes 1502 events for each player in the round
- Each 1502 contains `fss_hash` — the content-addressed score identity
- Each 1502 is Schnorr-signed by the publisher
- If two participants' 1502s for the same scored player contain the same `fss_hash`, that's cryptographic consensus — two independent signatures over the same hash

**The 30501 "finished" status adds an additional signal:** it proves the player reviewed and accepted the scores before the immutable 1502 was published. The sequence (30501 status=finished → 1502 published) establishes informed consent.

### 6.2 Flow

```
1. PLAY      All participants score on their devices
                (live scorecards via kind 30501, UX-only, non-authoritative)

2. FINISH    Each participant marks their 30501 as status=finished
                (signals: "I've reviewed these scores, they're complete")
                (30501 is still addressable/replaceable — this is a UX signal, not a commit)

3. COMPUTE   Each device computes per-player fss + fss_hash
                fss_hash = SHA-256(UTF-8(JCS(fss_json)))
                One fss per player per round

4. FINALIZE  Each participant publishes kind 1502 with fss_hash per scored player
                (immutable regular event — the commit)
                (1502 with scored_by=<other_player> IS the attestation)

5. VERIFY    Verification is a local projection:
                - fss_hash matches recomputed hash? (integrity)
                - Schnorr signature valid? (authenticity)
                - Publisher is a listed participant? (authorization)
                - Multiple participants published same fss_hash? (consensus)
```

### 6.3 Consensus Detection

```
Round status = projection derived from collected 1502 events:

- PENDING:     Not all participants have published 1502
- CONSISTENT:  All 1502s for the same scored player agree on fss_hash
- DISPUTED:    Multiple fss_hash values exist for the same scored player
- FINALIZED:   Consistent + all participants have published
```

### 6.4 Conflict Resolution (When Multiple 1502s Exist)

Since Nostr allows multiple 1502 publications:

1. **Same fss_hash** → redundant, no conflict (same assertion republished)
2. **Different fss_hash, different publishers for same scored player** → dispute
   - Display both versions with their signers
   - No automatic resolution — this is a genuine disagreement
3. **Different fss_hash, same publisher** → fork (user published conflicting finals)
   - The fss_hash that appears in more 1502s from other participants wins
   - Tie-break: deterministic (e.g., lexicographic sort of fss_hash)

**Timestamps are never trusted for truth.** They are a UX convenience for display ordering only.

### 6.5 When a Separate Attestation Event Kind IS Needed (Future)

A dedicated attestation kind (e.g., 1503) would be needed for:

- **Non-participants attesting** (tournament officials, spectators, witnesses)
- **After-the-fact verification** (signing off hours/days later without republishing scores)
- **Dispute resolution** (explicit "I dispute this score" events)
- **Money games / tournaments** (where stronger proof is required)

This can be deferred. The 1502-as-attestation model is sufficient for casual multiplayer.

---

## 7) What This Means for Implementation Priority

### Already Implemented (No Changes Needed)
- Signature verification on all Nostr events
- Author authorization (roster check)
- Hash verification on initiation events
- Local persistence of remote scores
- Immutability triggers on local fact tables

### Needed Before Attestation Can Work
1. **Define `fss` schema** — exact canonical JSON fields for a per-player final score
2. **Implement `fss_hash` computation** — extend `RAIDHashing` for score snapshots
3. **Add `fss_hash` tag to kind 1502** — content-addressed identity in the event
4. **Add canonical `fss` as 1502 content** — payload for verification
5. **Add `status=finished` to kind 30501** — signal review-complete before finalization
6. **Implement dedup by `fss_hash`** — replace timestamp-based dedup
7. **Define verification projection** — consensus detection from collected 1502s

### Deferred
- Separate attestation event kind (for non-participants, tournaments, disputes)
- Round-level consensus hash (aggregate of per-player fss_hashes)
- Full fact bundles for dispute resolution
- NIP-09 tombstone tracking
- Timestamp validation guards

---

## 8) Relationship to Existing Documents

| Document | Relationship |
|---|---|
| `attestation_and_snapshots.md` | **Upstream authority.** This review refines but does not replace it. The fss/fss_hash model, append-only attestation facts, and verification-as-projection are all preserved. |
| `mental_model.md` | **Fully aligned.** Local truth, Nostr as projection, trust boundaries. |
| `identifier_glossary.md` | **Fully aligned.** Three-tier taxonomy confirmed: fss_hash = Tier 1, event IDs = Tier 3, timestamps = Tier 3. |
| `nip101g_round_wip.md` | **Needs extension.** Current 1502 spec lacks fss_hash tag and canonical content. 30501 needs finished status. |
| `NIP101gEventBuilder.swift` | **Needs extension.** `buildFinalRecordEvent()` does not compute or include fss_hash. |

---

## 9) Key Decisions Confirmed

1. **Strategy:** Semantic Hash Consensus (over two-phase commit or version chains)
2. **Hash scope:** Per-player `fss_hash`, not round-level aggregate
3. **Attestation model:** 1502-as-attestation — no separate event kind needed for casual play
4. **Finish → Finalize:** 30501 status=finished (review signal) → 1502 (immutable commit)
5. **Timestamp trust:** Zero for consensus/truth; UX-only for display
6. **Publication model:** Symmetric — all participants publish independently
7. **Verification model:** Projection — consensus when all 1502s agree on fss_hash
8. **Local truth:** DB is authoritative; Nostr is distribution
9. **Conflict resolution:** Display disputes; deterministic fallback for forks
10. **Corrections:** Append-only — new fss, new hash, new 1502 required
11. **Separate attestation kind:** Deferred to tournament/money-game phase

---

**End of Review**
