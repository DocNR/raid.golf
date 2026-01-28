# 8. Non-Goals at the Schema Layer

[← Back to Index](00_index.md)

---

## 8.1 Overview

This section explicitly defines capabilities that the Phase 0 schema **must not** support. These are not future work items — they are **prohibited features** that would violate core architectural principles or introduce premature complexity.

---

## 8.2 KPI Template Mutation

### 8.2.1 Prohibited Capability

**MUST NOT:** Modify KPI templates after creation.

**Rationale:**
- Templates are content-addressed (hash = identity)
- Modifying content would invalidate hash
- Historical analyses would reference incorrect templates
- Reproducibility would be compromised

### 8.2.2 Correct Alternative

"Editing" creates a **new template** with a new hash. The original remains unchanged.

### 8.2.3 Schema Enforcement

**No UPDATE operations** on immutable fields in `kpi_templates` table.

---

## 8.3 Template Auto-Upgrade

### 8.3.1 Prohibited Capability

**MUST NOT:** Automatically update historical sub-sessions to reference newer template versions.

**Example of prohibited behavior:**

```python
# WRONG — DO NOT DO THIS
def upgrade_template(old_hash, new_hash):
    db.execute("""
        UPDATE club_subsessions
        SET kpi_template_hash = ?
        WHERE kpi_template_hash = ?
    """, (new_hash, old_hash))
```

**Rationale:**
- Destroys historical provenance
- Makes past analyses non-reproducible
- Violates immutability of sub-sessions
- Creates false audit trail

### 8.3.2 Correct Alternative

Historical sub-sessions remain unchanged. New analyses use the new template. Queries can filter by template version.

---

## 8.4 Cross-Session Merges

### 8.4.1 Prohibited Capability

**MUST NOT:** Combine multiple sessions into a single session.

**Rationale:**
- Sessions represent discrete practice events
- Merging loses temporal structure
- Violates session immutability
- Complicates trend analysis

### 8.4.2 Schema Enforcement

No merge operation in schema. Sessions are immutable after creation.

---

## 8.5 Multi-User Authentication

### 8.5.1 Prohibited Capability

**MUST NOT:** Support user accounts, authentication, or authorization at the schema level.

**Phase 0 assumption:** Single-user, local-only system.

**Rationale:**
- Multi-user adds complexity (user tables, permissions)
- Authentication requires security infrastructure
- Phase 0 validates core value proposition first
- iOS deployment is single-user by nature

### 8.5.2 Schema Impact

No `users` table, no `owner_id` foreign keys, no permission flags.

---

## 8.6 Sync Semantics

### 8.6.1 Prohibited Capabilities

**MUST NOT** implement in Phase 0:

- Conflict resolution logic
- Last-write-wins timestamps
- Merge strategies
- Sync state tracking
- Version vectors or CRDTs

**Rationale:**
- Sync is a Phase 1+ concern
- Local-first architecture prioritizes offline functionality
- Premature sync implementation complicates schema

### 8.6.2 Schema Impact

No sync-related fields:
- No `sync_status` columns
- No `remote_id` mappings
- No conflict markers
- No sync timestamps

### 8.6.3 Future Consideration

When sync is added (Phase 1+):
- May add optional sync metadata columns
- Will not affect core data model
- Local database remains authoritative

---

## 8.7 Collaborative Editing

### 8.7.1 Prohibited Capability

**MUST NOT:** Support real-time collaborative editing of templates or sessions.

**Rationale:**
- Immutability prevents collaborative editing anyway
- Operational transform is complex
- Phase 0 is single-user

### 8.7.2 Sharing Model

Phase 0 sharing is **read-only projection export**, not collaborative editing.

---

## 8.8 KPI Auto-Tuning

### 8.8.1 Prohibited Capability

**MUST NOT:** Automatically adjust KPI thresholds based on performance trends.

**Example of prohibited behavior:**

```python
# WRONG — DO NOT DO THIS
def auto_tune_template(club):
    recent_sessions = get_recent_sessions(club, limit=20)
    new_thresholds = compute_percentiles(recent_sessions)
    
    # WRONG: Silently updating template
    old_template = get_active_template(club)
    new_template = update_thresholds(old_template, new_thresholds)
    set_active_template(club, new_template)  # Silent change!
```

**Rationale:**
- KPI standards are **deliberate**, not reactive
- Auto-tuning would prevent assessment of actual improvement
- Users would "teach to the test" (optimize for KPIs, not real skill)
- Standards should be stable for meaningful trend analysis

### 8.8.2 Correct Alternative

Users **explicitly** create new templates when they want to adjust standards. The change is visible and intentional.

---

## 8.9 Advanced Statistical Smoothing

### 8.9.1 Prohibited Capability

**MUST NOT** implement in Phase 0:

- Bayesian inference
- Kalman filtering
- Weighted moving averages beyond simple rolling window
- Outlier detection and removal
- Regression analysis

**Rationale:**
- Adds complexity and "black box" behavior
- Obscures raw data
- Creates trust issues for users
- Simple rolling averages are sufficient for MVP

### 8.9.2 Schema Impact

No storage of:
- Model parameters
- Confidence intervals
- Smoothing coefficients
- Statistical metadata

### 8.9.3 Transparency Requirement

Phase 0 prioritizes **transparent, reproducible calculations** over sophisticated statistical methods.

---

## 8.10 UI Beyond Minimal CLI

### 8.10.1 Prohibited Capability

**MUST NOT** include in Phase 0 schema:

- UI state persistence
- User preferences (beyond template aliases)
- View configurations
- Dashboard layouts
- Custom report definitions

**Rationale:**
- Phase 0 validates data model, not UI
- CLI is sufficient for MVP
- UI concerns are separate from schema design

### 8.10.2 Schema Impact

No UI-specific tables or columns.

---

## 8.11 On-Course Scoring

### 8.11.1 Prohibited Capability

**MUST NOT:** Support on-course round tracking, scorekeeping, or handicap calculation.

**Rationale:**
- Different product class (scoring vs. practice analytics)
- Different data model (holes, strokes, penalties)
- Different use case (real-time vs. post-session analysis)
- Phase 3+ concern per PRD

### 8.11.2 Schema Impact

No golf course data:
- No courses, holes, or tees
- No scores or handicaps
- No GPS locations or shot tracking

---

## 8.12 Real-Time Data Streaming

### 8.12.1 Prohibited Capability

**MUST NOT:** Support live streaming of shot data from launch monitor.

**Rationale:**
- Batch CSV import is sufficient for MVP
- Real-time requires different architecture (WebSocket, buffering)
- Adds deployment complexity
- Not required for core value proposition

### 8.12.2 Schema Impact

No streaming metadata:
- No buffer tables
- No sequence numbers
- No partial session states

---

## 8.13 Multiple Device Sync

### 8.13.1 Prohibited Capability

**MUST NOT:** Support automatic sync between devices (e.g., Mac ↔ iPhone).

**Rationale:**
- Phase 0 is single-device
- Sync is complex (conflicts, offline edits)
- File export/import is acceptable for MVP

### 8.13.2 Future Path

Phase 1+ may add:
- iCloud document sync
- Nostr-based event sync
- Manual export/import

But Phase 0 schema does not support these.

---

## 8.14 Machine Learning / AI

### 8.14.1 Prohibited Capabilities

**MUST NOT** implement:

- Predictive models
- Swing classification
- Anomaly detection
- Clustering or pattern recognition
- Neural networks

**Rationale:**
- Requires training data infrastructure
- Black box behavior reduces trust
- Validation is complex
- Not part of Phase 0 scope

### 8.14.2 Schema Impact

No ML metadata:
- No model versions
- No training datasets
- No prediction confidence scores

---

## 8.15 Social Features

### 8.15.1 Prohibited Capabilities

**MUST NOT** implement:

- Friends/followers
- Leaderboards
- Competitions
- Comments or annotations from others
- Activity feeds

**Rationale:**
- Phase 0 is personal analytics tool
- Social features require multi-user infrastructure
- Deferred to Phase 1+ if valuable

### 8.15.2 Schema Impact

No social tables:
- No user relationships
- No public profiles
- No social interactions

---

## 8.16 External Service Integration

### 8.16.1 Prohibited Capabilities

**MUST NOT** integrate with:

- Cloud storage (Google Drive, Dropbox)
- Third-party analytics services
- Launch monitor APIs (except CSV export)
- Social media platforms (except Nostr in Phase 1+)

**Rationale:**
- Local-first architecture prioritizes offline
- External services add failure points
- Phase 0 validates core without dependencies

### 8.16.2 Schema Impact

No external service metadata:
- No API tokens
- No service connection status
- No external IDs

---

## 8.17 Summary of Prohibited Features

The following are **explicitly prohibited** in Phase 0 schema design:

| Feature | Prohibition | Rationale |
|---------|-------------|-----------|
| KPI mutation | MUST NOT modify templates | Breaks content-addressing |
| Template auto-upgrade | MUST NOT update historical refs | Destroys provenance |
| Session merging | MUST NOT combine sessions | Violates immutability |
| Multi-user auth | MUST NOT add user accounts | Single-user system |
| Sync semantics | MUST NOT implement sync | Local-first priority |
| Collaborative editing | MUST NOT support | Conflicts with immutability |
| KPI auto-tuning | MUST NOT auto-adjust | Standards are deliberate |
| Advanced statistics | MUST NOT add complex models | Transparency priority |
| UI persistence | MUST NOT store UI state | CLI sufficient for MVP |
| On-course scoring | MUST NOT track rounds | Different product |
| Real-time streaming | MUST NOT support live data | Batch import sufficient |
| Device sync | MUST NOT auto-sync | Single-device |
| Machine learning | MUST NOT add ML | Validation complexity |
| Social features | MUST NOT add social | Personal tool |
| External services | MUST NOT integrate | Local-first |

---

## 8.18 Enforcement Strategy

These non-goals are enforced by:

1. **Exclusion from schema** — prohibited features have no supporting tables/columns
2. **Code review** — reject implementations of prohibited features
3. **PRD alignment** — features not in PRD are out of scope
4. **This document** — explicit statement of non-goals prevents creep

---

[Next: Forward-Compatibility Guarantees →](09_forward_compatibility.md)
