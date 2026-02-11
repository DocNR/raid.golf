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
