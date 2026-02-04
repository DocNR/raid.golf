# Course Identity and Snapshot Model

Status: Kernel-adjacent specification
Applies to: On-course rounds, multiplayer initiation, attestations, competitions
First referenced in: Milestone 4 (On-Course Scoring)
Authority: Subordinate to KERNEL_CONTRACT_v2.md

---

1. Purpose

This document defines how golf courses are represented, identified, and frozen in time so that:

* rounds remain reproducible forever
* attestations retain semantic meaning
* historical comparisons remain valid
* course updates do not silently rewrite the past

This specification separates:

* course discovery and sharing
* course authority for rounds
* playable configurations used for scoring

---

2. Core Principle (Non-Negotiable)

Rounds are evaluated against immutable course snapshots, not mutable course definitions.

Network-distributed course definitions may change.
Rounds must not.

---

3. Concepts

3.1 Course Container

A course container represents a real-world golf facility as a discoverable entity.

It is a superset definition and may include:

* course name
* location metadata
* hole definitions (1–18)
* par and handicap indices
* all available tee sets
* ratings, slopes, yardages
* descriptive metadata

Properties:

* Mutable over time
* Intended for discovery and UX
* Not authoritative for historical rounds
* Must never be relied upon for reproducibility

In Nostr contexts, this typically maps to:

* a parameterized replaceable course event (e.g. kind 33501)
* identified by a stable course handle (`d` tag)

---

3.2 Course Snapshot

A course snapshot represents a specific, playable configuration of a course at the moment a round is initiated.

A snapshot includes only scoring-relevant data, such as:

* course name (human label)
* selected tee set
* holes played (e.g. front 9, back 9, full 18)
* par per hole
* handicap index per hole
* any other attributes required for scoring or competition rules

Properties:

* Immutable
* Canonicalized
* Content-addressed
* Authoritative for rounds, analytics, and attestations

Once referenced by a round, a snapshot is frozen forever.

---

4. Identity and Hashing

4.1 Snapshot Identity

Each course snapshot has a deterministic identity:

course_hash = SHA-256( UTF-8( JCS( CourseSnapshot JSON ) ) )

Where:

* JCS is RFC 8785 JSON Canonicalization Scheme
* UTF-8 encoding is used without BOM
* SHA-256 output is lowercase hexadecimal

Any change to snapshot content produces a new course_hash.

---

4.2 Stable Course Handle

A stable course handle (e.g. `course_d`) may be used for:

* discovery
* grouping related versions
* human-friendly identification

The handle:

* must not be used as authoritative identity
* must not imply immutability
* must not be used to reproduce rounds

---

5. Usage Rules

5.1 Round Initiation (Authoritative)

Every round initiation must declare exactly one course snapshot.

The initiation event must include:

* the canonical CourseSnapshot JSON
* the derived course_hash

The initiation event may additionally include:

* a reference to a course container (e.g. 33501 event)
* human-readable course metadata

When both are present, the snapshot is authoritative.

---

5.2 Attestations

Attestations implicitly attest to:

* the scores
* the participants
* the exact course snapshot referenced by course_hash

An attestation without a pinned course snapshot is semantically incomplete.

---

5.3 Analytics and Competitions

All round-based analytics, competitions, and evaluations must:

* operate against the snapshot referenced by course_hash
* treat the snapshot as immutable input
* remain reproducible even if course containers change

---

6. Network Distribution

Network-distributed course containers:

* exist for discovery only
* may be replaceable or updated
* must not be treated as authoritative facts

Clients may:

* import containers
* derive course snapshots
* embed snapshots directly in initiation events
* store snapshots locally for verification

No verification flow may depend on resolving a “latest” course definition.

---

7. Forbidden Behaviors

The following violate this specification:

* Referencing a mutable course container directly from a round
* Re-resolving a course definition after a round is initiated
* Treating “latest course version” as authoritative
* Mutating snapshot data after reference
* Inferring course identity from network event IDs

---

8. Rationale

Without snapshot-level identity:

* course edits silently change historical semantics
* handicap allocation becomes ambiguous
* competitions become disputable
* attestations lose meaning
* long-term analytics drift over time

By separating:

* container (discovery)
* snapshot (authority)

the system preserves historical truth while allowing courses to evolve.

---

9. Summary

* One course container represents the real-world course
* Many immutable snapshots represent playable configurations
* Rounds always bind to a snapshot hash
* Network distribution never implies authority

Discovery can change.
History cannot.

---
