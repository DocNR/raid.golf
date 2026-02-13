# Gambit Golf — Backlog

Known issues and deferred improvements, roughly prioritized.

## B-001: Club Name Normalization

**Priority:** Medium (post-Milestone 1)
**Area:** Ingest, Templates, Analysis

Club-to-template matching is an exact, case-sensitive string comparison.
Different data sources (or even different Rapsodo firmware versions) may emit
different representations of the same club:

| Equivalent names | Current behavior |
|---|---|
| `7i`, `7 Iron`, `7-iron`, `7I` | Treated as four separate clubs |

### Impact
- Templates created for `7i` won't match shots imported as `7 Iron`.
- Trends and analysis silently miss data from the "other" spelling.
- Within a single Rapsodo setup this is mitigated by the club Picker, which
  sources its list from previously imported shot data.

### Proposed fix
Add a club alias / canonical-name mapping layer:
1. Canonical club names table (`canonical_clubs`) with aliases.
2. Normalize on ingest (`RapsodoIngest.parseShot`) — map raw name → canonical.
3. Template and analysis lookups already use exact match, so normalization at
   ingest time is sufficient.

### Code pointers
- `ios/RAID/RAID/Ingest/RapsodoIngest.swift` — `parseShot()` (raw club name)
- `ios/RAID/RAID/Views/CreateTemplateView.swift` — `loadClubChoices()` (picker)
- `ios/RAID/RAID/Views/SessionsView.swift` — `analyzeImportedSession()` (exact match lookup)

---

## B-002: Template Versioning

**Priority:** Low (post-Milestone 1)
**Area:** Templates, Analysis

Adding or removing a metric from a template creates a new `template_hash`.
Existing `club_subsessions` rows referencing the old hash remain unchanged.
There is no migration or "upgrade" path from one template version to another.

### Impact
- Historical analyses remain pinned to the template version used at the time.
- Re-analysis with a new template creates a new `club_subsessions` row.
- Users may accumulate multiple template versions for the same club.

### Proposed fix
- Add template lifecycle UI: mark templates as deprecated, show lineage
- Optionally allow re-analysis of all sessions with a new template (batch operation)

---

## B-003: Shot Editing

**Priority:** Low (post-Milestone 1)
**Area:** Ingest, Shots

Shots table has immutability triggers (no UPDATE/DELETE).
If a user imports incorrect data, there is no in-app way to correct it.

### Impact
- Bad data (e.g., Rapsodo sensor glitch) cannot be edited.
- Only workaround: re-import corrected CSV as a new session.

### Proposed fix
- Append-only correction model: INSERT a correction row with FK to original shot.
- Analysis queries prefer correction rows over originals where present.
- Alternatively: relax immutability for shots (not recommended; breaks audit trail).

---

## B-004: Course Editing

**Priority:** Low (post-Milestone 1)
**Area:** Scorecard, Courses

Course snapshots have immutability triggers (no UPDATE/DELETE).
If a user creates a course with incorrect hole data, they cannot edit it.

### Impact
- Typos or incorrect par values cannot be fixed.
- Only workaround: create a new course and hide the old one.

### Proposed fix
- Add hide/archive flag for course snapshots (similar to templates).
- Alternatively: relax immutability for course snapshots (not recommended).
