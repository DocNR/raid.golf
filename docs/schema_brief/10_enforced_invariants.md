# 10. Summary of Enforced Invariants

[← Back to Index](00_index.md)

---

## 10.1 Overview

This section consolidates all mandatory rules from the preceding sections into a single "Constitution" of non-negotiable invariants. These rules MUST be enforced by all implementations.

---

## 10.2 Data Immutability (MUST)

1. **Sessions MUST be immutable after creation** — all fields frozen at ingestion
2. **Club sub-sessions MUST be immutable after creation** — analysis results never change
3. **KPI templates MUST be immutable forever** — no field modifications allowed
4. **Template hashes MUST NOT be recomputed after storage** — stored hash is authoritative truth
5. **"Editing" MUST create new records** — never mutate existing entities
6. **Original CSV provenance MUST be preserved** — source_file field is audit trail

---

## 10.3 Identity & Addressing (MUST)

7. **KPI templates MUST be content-addressed** — identity = SHA-256(canonical_json)
8. **Template hashes MUST be lowercase 64-character hex** — standardized format
9. **Canonical JSON MUST have sorted keys** — alphabetically at all nesting levels
10. **Numeric values MUST be normalized deterministically** — cross-platform consistency required
11. **Hash computation MUST be identical across Python and Swift** — validation required
12. **Sessions MUST use system-assigned integer IDs** — auto-increment primary keys
13. **Sub-sessions MUST reference template by hash** — not by name or alias

---

## 10.4 Referential Integrity (MUST)

14. **Each sub-session MUST belong to exactly one session** — enforced by foreign key
15. **Each sub-session MUST reference exactly one KPI template** — enforced by foreign key
16. **Templates referenced by sub-sessions MUST NOT be deletable** — RESTRICT constraint
17. **Orphaned sub-sessions MUST NOT exist** — cascading rules prevent
18. **Derived tables MUST NOT be referenced by authoritative tables** — one-way dependency

---

## 10.5 Data Validation (MUST)

19. **Shot counts MUST be positive** — shot_count > 0
20. **Classification counts MUST sum to shot_count** — a_count + b_count + c_count = shot_count
21. **A percentage MUST be NULL if status is invalid_insufficient_data** — no false precision
22. **Validity status MUST reflect configured thresholds** — < 5 invalid, 5-14 warning, ≥ 15 valid
23. **Timestamps MUST include timezone information** — ISO-8601 with timezone
24. **Ingestion MUST NOT predate session** — ingested_at >= session_date
25. **Analysis MUST NOT predate session** — analyzed_at >= session_date

---

## 10.6 Sample Size Handling (MUST)

26. **Invalid/low-sample sessions MUST be stored** — never silently discard
27. **Validity status MUST be present in all query results** — queryable field, not hidden
28. **Query filters MUST be explicit** — documented in query parameters and result metadata
29. **Validity status MUST enable consumers to distinguish data quality levels** — invalid vs warning vs valid
30. **Thresholds MUST be configurable** — not hardcoded magic numbers

---

## 10.7 Projection & Export (MUST)

31. **Projections MUST be regenerable** — derived from authoritative data
32. **Projections MUST NOT be imported as authoritative** — export-only artifacts
33. **Regeneration MUST produce identical analytical results** — deterministic
34. **Projections MAY be deleted without data loss** — cache not source
35. **Export formats MUST derive from SQLite** — single source of truth

---

## 10.8 Cardinality & Structure (MUST)

36. **A session MAY contain multiple clubs** — 1:N relationship to sub-sessions
37. **Mixed-club CSV files MUST be supported** — single file, multiple sub-sessions
38. **Sub-sessions MUST NOT be shared across sessions** — strict parent-child relationship
39. **Duplicate analysis MUST be prevented** — unique (session, club, template_hash)
40. **Re-analysis with different template MUST create new sub-session** — original preserved

---

## 10.9 Template Management (MUST)

41. **Template import MUST be idempotent** — same content → same hash → deduplicated
42. **Template aliases MUST be local metadata only** — not exported
43. **Alias changes MUST NOT affect template identity** — hash unchanged
44. **Multiple authors MAY publish identical template** — same hash, different signatures
45. **Template schema version MUST be part of content** — included in hash

---

## 10.10 Forward Compatibility (MUST)

46. **Schema MUST support iOS without structural changes** — SQLite portable
47. **Template JSON MUST map to Swift Codable** — no impedance mismatch
48. **Historical analyses MUST remain valid indefinitely** — immutability guarantee
49. **Phase 1+ changes MUST be additive only** — no breaking changes
50. **Cross-platform hashing MUST be validated** — Python ↔ Swift test suite

---

## 10.11 Prohibited Operations (MUST NOT)

51. **MUST NOT modify immutable fields** — UPDATE operations rejected
52. **MUST NOT merge or split sessions** — discrete events preserved
53. **MUST NOT swap template references** — no retroactive template changes
54. **MUST NOT silently exclude data** — transparency required
55. **MUST NOT recompute hashes on read** — trust stored values
56. **MUST NOT auto-upgrade templates** — explicit user action required
57. **MUST NOT implement sync in Phase 0** — deferred to Phase 1+
58. **MUST NOT add multi-user auth** — single-user system
59. **MUST NOT auto-tune KPI thresholds** — standards are deliberate
60. **MUST NOT implement collaborative editing** — conflicts with immutability

---

## 10.12 Data Sovereignty (MUST)

61. **SQLite MUST be the authoritative datastore** — not JSON, not cache
62. **JSON MUST be used only for serialization** — not bidirectional
63. **Local database MUST function offline** — no network dependency
64. **Users MUST own their data** — no external service lock-in
65. **SQLite database file export MUST be lossless** — full database exportable; JSON projections are intentionally lossy summaries

---

## 10.13 Canonicalization (MUST)

66. **Object keys MUST be sorted alphabetically** — at all nesting levels
67. **JSON MUST be compact** — no whitespace in canonical form
68. **Encoding MUST be UTF-8 without BOM** — standardized encoding
69. **Hashing MUST use SHA-256** — no custom algorithms
70. **Array order MUST be preserved** — not sorted like object keys

---

## 10.14 Schema Constraints (MUST)

71. **Foreign keys MUST be enforced** — no orphaned references
72. **Check constraints MUST validate business logic** — schema-level enforcement
73. **NOT NULL constraints MUST be respected** — required fields mandatory
74. **Unique constraints MUST prevent logical duplicates** — data integrity
75. **Enum values MUST be validated** — only defined values accepted

---

## 10.15 Separation of Concerns (MUST)

76. **Authoritative data MUST NOT depend on derived data** — clear boundary
77. **Derived layer MUST be read-only** — queries only, no mutations
78. **Cache tables MUST be clearly named** — signal derived nature
79. **UI state MUST NOT be in core schema** — separate concern
80. **External service metadata MUST NOT be in Phase 0** — local-first

---

## 10.16 Transparency & Auditability (MUST)

81. **Template provenance MUST be recorded** — created_at, imported_at
82. **Analysis timestamp MUST be stored** — analyzed_at
83. **Validity status MUST be computed and stored** — not derived on read
84. **Source file reference MUST be preserved** — original CSV path
85. **Template hash MUST identify exact version used** — audit trail

---

## 10.17 Reproducibility (MUST)

86. **Same input + same template MUST produce identical output** — deterministic
87. **Historical analyses MUST be re-validatable** — rerun with original template
88. **Canonicalization MUST be deterministic** — no random ordering
89. **Hashing MUST be deterministic** — no timestamp in hash
90. **Classification logic MUST be deterministic** — no probabilistic elements

---

## 10.18 Error Handling (MUST)

91. **Invalid JSON MUST be rejected** — parse errors raised immediately
92. **Schema violations MUST cause failure** — no silent acceptance
93. **Immutability violations MUST be rejected with clear errors** — not ignored
94. **Missing required parameters MUST cause failure** — explicit errors
95. **Duplicate template_hash with different canonical_json MUST cause fatal error** — integrity violation (theoretically impossible with SHA-256)

---

## 10.19 Documentation (MUST)

96. **Canonical form MUST be documented with examples** — reference implementation
97. **Cross-platform differences MUST be tested** — validation suite
98. **Schema version MUST be tracked** — future migration support
99. **Breaking changes MUST require PRD update** — no ad-hoc modifications
100. **Implementation MUST document numeric normalization strategy** — cross-platform consistency

---

## 10.20 The Constitution (Summary)

**Core Principles:**

1. **Immutability** — Historical data never changes
2. **Content-Addressing** — Templates identified by hash
3. **Local-First** — SQLite is authoritative, offline-capable
4. **Reproducibility** — Analyses are deterministic and re-validatable
5. **Transparency** — No silent data exclusion or modification
6. **Separation** — Authoritative vs. derived data clearly distinguished
7. **Forward-Compatible** — Schema supports iOS, Nostr, long-term evolution
8. **Explicit** — No magic behavior, clear error messages
9. **Minimal** — No premature features (sync, ML, social)
10. **Trustworthy** — Users can verify and validate all data

---

## 10.21 Compliance Validation

**To verify compliance with this brief:**

1. ✅ Read all 100 invariants above
2. ✅ Review schema implementation against logical schema (Section 3)
3. ✅ Verify immutability enforcement (Section 4)
4. ✅ Validate hashing implementation (Section 5)
5. ✅ Check cardinality constraints (Section 6)
6. ✅ Confirm derived data separation (Section 7)
7. ✅ Audit for prohibited features (Section 8)
8. ✅ Plan for forward compatibility (Section 9)
9. ✅ Test against cross-platform reference cases
10. ✅ Document any implementation-specific decisions

---

## 10.22 Enforcement Authority

This Schema-First Implementation Brief is **subordinate to the PRD**. If any conflict exists:

1. PRD wins
2. Update this brief to align
3. Validate implementation against updated brief

**Change process:**
1. Update PRD (explicit version bump)
2. Regenerate this brief from updated PRD
3. Review diff of brief changes
4. Update implementation to comply
5. Run validation suite

---

## 10.23 Final Note

These 100 invariants represent the **minimum set of non-negotiable rules** for Phase 0. Implementations may add additional constraints, but must never relax these.

**When in doubt:** Consult the PRD, then this brief, then ask.

**When tempted to shortcut:** Remember that data integrity, reproducibility, and user trust are non-negotiable.

**When considering new features:** First ask: "Is this in the PRD?" If no, it's out of scope.

---

[← Back to Index](00_index.md)
