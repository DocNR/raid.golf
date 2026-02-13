# NIP-101g: Golf Rounds, Course Containers, and Peer Attestation (WIP / Deferred)

`draft` `optional` `work-in-progress`

> **Status:** This specification is **deferred** and **not part of the current MVP**.  
> The MVP scope is focused on **launch monitor practice analytics and KPI standards**, not on-course scoring or course discovery.  
> This document is maintained for future expansion once the MVP is validated.

## Abstract

This NIP defines event shapes for:
1) sharing **course container** metadata for discovery (mutable, addressable),
2) initiating a **round context** that is *self-contained and verifiable* (immutable, regular),
3) optionally publishing **live scorecard state** (addressable replaceable, UX-only),
4) publishing a **final round record** (immutable, regular),
5) publishing **peer attestations** over the final record (immutable, regular).

This design explicitly separates **discovery** (course container) from **authority** (embedded course snapshot and rules inside initiation).

## Kind Range Conventions (NIP-01)

This NIP follows the kind-range conventions described in NIP-01:

- **Regular (stored):** `1000 <= n < 10000` or `4 <= n < 45` or `n == 1` or `n == 2`
- **Replaceable:** `10000 <= n < 20000` or `n == 0` or `n == 3`
- **Ephemeral:** `20000 <= n < 30000`
- **Parameterized replaceable (addressable):** `30000 <= n < 40000` (addressable by `kind`, `pubkey`, and `d`)

Source: NIP-01.  (https://nips.nostr.com/1)

**Important:** Kinds listed below are **placeholders** and may change.  
The only hard requirement is: immutable facts should be **regular events** (stored by relays).

## Event Kinds (Placeholders)

- `33501`: Golf Course Container Definition (addressable; discovery only)
- `1xxx`: Round Initiation / Context (regular; immutable fact)  ← choose `1000–9999`
- `3xxxx`: Live Scorecard State (addressable replaceable; UX-only) ← choose `30000–39999`
- `1yyy`: Final Round Record (regular; immutable fact)  ← choose `1000–9999`
- `1zzz`: Round Attestation (regular; immutable fact)  ← choose `1000–9999`

> The prior draft used 11501/1501/1502 as concrete kinds. This revision intentionally treats them as placeholders to preserve flexibility and to align with NIP-01 ranges.

---

# 1) Golf Course Container Definition (kind 33501, addressable)

Course containers are **discoverable, mutable** representations of a real-world golf course.

They are:
- **addressable** (NIP-33) via `kind + pubkey + d`
- **replaceable** by the author
- intended for **discovery and UX**
- **NOT authoritative** for scoring or historical rounds

## Required Tags

- `d`: stable course handle (UUID or slug)
- `name`: course name
- `location`: city, region/state, country
- `hole`: one per hole: (hole_number, par, handicap_index)
- `tee`: one per tee set: (tee_name, course_rating, slope_rating)

## Optional Tags

- `g`: geohash
- `imeta`: media (see NIP-92)
- any additional descriptive tags (website, phone, architect, etc.)

## Example

```json
{
  "kind": 33501,
  "content": "Optional free-text description",
  "tags": [
    ["d", "fowlers-mill-golf-course"],
    ["name", "Fowler's Mill Golf Course"],
    ["location", "Chesterland", "Ohio", "USA"],
    ["hole", "1", "4", "5"],
    ["hole", "2", "4", "15"],
    ["tee", "Silver M", "68.4", "118"],
    ["tee", "Black", "72.8", "133"]
  ]
}
```

---

# 2) Round Initiation / Context (regular, immutable fact)

This is the **authoritative declaration** of:
- the **course snapshot** used for the round,
- the **rule set** used for evaluation,
- the participants and basic round metadata.

**Timing:** The initiation event MUST be published when the round begins (at round creation time), not at round completion. This ensures participants are declared upfront and the course snapshot is immutable from the start.

## Key Design Rule (Critical)

If both are present:
- a reference to a course container (33501), and
- an embedded course snapshot,

then:

> The embedded snapshot is authoritative.  
> The 33501 reference is informational only.

## Snapshot and Rules Hashing

- `course_hash = SHA-256( UTF-8( JCS(course_snapshot_json) ) )`
- `rules_hash  = SHA-256( UTF-8( JCS(rules_template_json) ) )`

## Required Content (Embedded Canonical JSON)

The `content` MUST be a JSON string containing:

```json
{
  "course_snapshot": { ... },
  "rules_template": { ... }
}
```

### `course_snapshot` minimum fields

- `course_name` (label)
- `tee_set` (e.g., "Blue", "Silver M")
- `holes_played` (e.g., [1..18], [1..9], [10..18])
- `holes`: array of per-hole definitions for the holes played:
  - `hole_number`
  - `par`
  - `handicap_index`
  - optional `yardage`

### `rules_template` minimum fields

- `format` (e.g., "stroke_play", "match_play", "skins", "stableford")
- any evaluation rules required to compute outcomes
- optional tie-break rules, handicap application rules, etc.

## Required Tags

- `p`: one per participant pubkey
- `course_hash`: hash of embedded `course_snapshot`
- `rules_hash`: hash of embedded `rules_template`

## Optional Tags

- `a`: reference to course container: `["a", "33501:<author_pubkey>:<course_d>"]`
- `d`: round/group identifier (if you want easier correlation)
- `date`: ISO-8601 date
- `tee`: tee label (redundant; should match snapshot)
- `group`: human label for a group
- `game`: shorthand format label (redundant with rules_template)

## Example

```json
{
  "kind": 1234,
  "content": "{\"course_snapshot\":{\"course_name\":\"Fowler's Mill Golf Course\",\"tee_set\":\"Silver M\",\"holes_played\":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18],\"holes\":[{\"hole_number\":1,\"par\":4,\"handicap_index\":5},{\"hole_number\":2,\"par\":4,\"handicap_index\":15}]},\"rules_template\":{\"format\":\"stroke_play\"}}",
  "tags": [
    ["p", "pk-player-a"],
    ["p", "pk-player-b"],
    ["course_hash", "sha256:<hex>"],
    ["rules_hash", "sha256:<hex>"],
    ["a", "33501:pk-course-author:fowlers-mill-golf-course"],
    ["date", "2026-05-05"]
  ]
}
```

---

# 3) Live Scorecard State (optional; addressable replaceable; UX-only)

Live scoring is an optional projection layer.

- SHOULD be **parameterized replaceable** (`30000–39999`)
- Addressed by: `kind + pubkey + d`
- MUST reference the initiation context (by `e` tag or a stable round id)
- MUST NOT redefine the authoritative course snapshot or rules

## Example (addressable replaceable)

```json
{
  "kind": 30001,
  "content": "Optional status text",
  "tags": [
    ["d", "round-uuid-123"],
    ["e", "<initiation_event_id>"],
    ["status", "in_progress"],
    ["score", "1", "5"],
    ["score", "2", "4"]
  ]
}
```

---

# 4) Final Round Record (regular, immutable fact)

The final round record is an immutable summary of scores.

It MUST reference the initiation context event.

## Required Tags

- `e`: initiation event id
- `score`: one per hole (hole_number, strokes)
- `total`: total strokes
- optional `p`: tag other players

## Example

```json
{
  "kind": 1235,
  "content": "Optional notes",
  "tags": [
    ["e", "<initiation_event_id>"],
    ["score", "1", "5"],
    ["score", "2", "4"],
    ["total", "79"],
    ["p", "pk-player-b"]
  ]
}
```

---

# 5) Round Attestation (regular, immutable fact)

An attestation is an immutable statement by a marker/peer.

It MUST reference the final round record.

## Required Tags

- `e`: final round record event id
- `p`: round author pubkey (or attested player pubkey)
- `status`: `verified` | `disputed`

## Example

```json
{
  "kind": 1236,
  "content": "I can confirm these scores are accurate.",
  "tags": [
    ["e", "<final_round_record_event_id>"],
    ["p", "pk-round-author"],
    ["status", "verified"]
  ]
}
```

---

# Verification (Normative)

A verifier reconstructs the round without consulting mutable course containers:

1) Fetch the initiation event  
2) Parse embedded `course_snapshot` and `rules_template`  
3) Canonicalize (JCS) and hash them  
4) Confirm hashes match `course_hash` and `rules_hash` tags  
5) Fetch final round record and apply rules  
6) Fetch attestations and evaluate verification status

---

# Notes on Naming and Scope

- This document is intentionally marked **WIP / Deferred** to avoid implying standardization.
- If you want to keep the longer, example-heavy draft, consider renaming it to:
  - `nip-101g_draft_expanded.md` (examples-heavy)
  - while this file becomes the “current design” draft.

