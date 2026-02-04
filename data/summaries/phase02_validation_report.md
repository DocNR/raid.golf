# Phase 0.2 Validation Report — 7-Iron v2 Template

**Status:** Read-only validation (no templates or thresholds modified)

---

## Run A — Authoritative Session (Jan 27, 2026)

**CSV:** `mlm2pro_shotexport_012726.csv`
**Template:** `template_7i_v2_unvalidated.json`
**Role:** Authoritative (used for readiness assessment)

### CSV Sanity Panel

**Headers detected:**
```
Club Type, Club Brand, Club Model, Carry Distance, Total Distance, Ball Speed, Launch Angle, Launch Direction, Apex, Side Carry, Club Speed, Smash Factor, Descent Angle, Attack Angle, Club Path, Club Data Est Type, Spin Rate, Spin Axis
```

**Column mapping (judgment metrics):**
- `club` → `Club Type`
- `carry_distance` → `Carry Distance`
- `ball_speed` → `Ball Speed`
- `smash_factor` → `Smash Factor`
- `descent_angle` → `Descent Angle`
- `spin_rate` → `Spin Rate`

**Total rows:** 61
**Footer rows removed:** 2
**Final shot count:** 59

**Metric ranges (min / median / max):**
- Smash Factor: 1.12 / 1.29 / 1.36
- Ball Speed: 94.5 / 106.6 / 112.0 mph
- Spin Rate: 3276 / 4669 / 5652 rpm
- Descent Angle: 34.8 / 46.3 / 52.8°

**Template loaded:**
- Path: `data/templates/v2/template_7i_v2_unvalidated.json`
- Schema version: 1.0
- Club: 7i
- Aggregation method: worst_metric

**Template thresholds:**
- `ball_speed`: A ≥ 104.0, B ≥ 104.0, C < 104.0 (higher is better)
- `smash_factor`: A ≥ 1.25, B ≥ 1.22, C < 1.22 (higher is better)
- `spin_rate`: A ≥ 4300.0, B ≥ 4200.0, C < 4200.0 (higher is better)
- `descent_angle`: A ≥ 45.0, B ≥ 44.0, C < 44.0 (higher is better)

### Summary Table

| Grade | Count | Percentage |
|-------|-------|------------|
| **A** | 32 | 54.2% |
| **B** | 3 | 5.1% |
| **C** | 24 | 40.7% |
| **Total** | 59 | 100.0% |

### Failure Cause Breakdown

**Total C-shots:** 24

**Metrics responsible for C-grade (% of C-shots):**

- `ball_speed`: 16 / 24 (66.7%)
- `smash_factor`: 6 / 24 (25.0%)
- `spin_rate`: 11 / 24 (45.8%)
- `descent_angle`: 16 / 24 (66.7%)

*Note: A shot can fail on multiple metrics simultaneously.*

### Temporal Distribution (Session Quarters)

**Q1 (early):** 7A / 0B / 7C (A% = 50.0%)
**Q2:** 10A / 1B / 3C (A% = 71.4%)
**Q3:** 6A / 2B / 6C (A% = 42.9%)
**Q4 (late):** 9A / 0B / 8C (A% = 52.9%)

### Observed vs Expected Behavior

**Expected A% range:** 40–60%
**Observed A%:** 54.2%

✅ **A% is within expected range (40–60%).**

**B-shot presence:**
✅ **B-shots are present (3 shots, 5.1%).** Template is discriminating between borderline and clear failures.

**C-shot explainability:**
✅ **Failures are distributed across metrics.** No single metric dominates.

### Template v1.0 Readiness Checklist

**Prerequisites:**
- ⚠️ Minimum 3 full sessions (≥15 shots each): **Cannot assess with single session**
- ⚠️ Minimum 25 A-shots accumulated: **Cannot assess with single session**
- ⚠️ Template used for ≥2 weeks: **Cannot assess with single session**
- ⚠️ No threshold changes in last 5 sessions: **Cannot assess with single session**

**A% Range Assessment:**
- ✅ A% is in normal range (40–60%): 54.2%

**Failure Pattern Assessment:**
- ✅ Mix of B-shots and C-shots present
- ✅ Failures are distributed across metrics

**Single-Session Readiness Judgment:**

⚠️ **This is a single-session validation.** Full readiness cannot be assessed without:
- Additional sessions (minimum 3 total)
- Session-to-session stability analysis
- Multi-week usage history

**However, this session suggests:**
- ✅ Template behavior is **consistent with expectations** for this session
- ✅ A% is in normal range and B-shots are present
- ✅ Template appears ready for **continued validation** with additional sessions


---

## Run B — Stress Test Session (Feb 3, 2026)

**CSV:** `mlm2pro_shotexport_020326.csv`
**Template:** `template_7i_v2_unvalidated.json`
**Role:** Stress test (observational only)

### CSV Sanity Panel

**Headers detected:**
```
Club Type, Club Brand, Club Model, Carry Distance, Total Distance, Ball Speed, Launch Angle, Launch Direction, Apex, Side Carry, Club Speed, Smash Factor, Descent Angle, Attack Angle, Club Path, Club Data Est Type, Spin Rate, Spin Axis
```

**Column mapping (judgment metrics):**
- `club` → `Club Type`
- `carry_distance` → `Carry Distance`
- `ball_speed` → `Ball Speed`
- `smash_factor` → `Smash Factor`
- `descent_angle` → `Descent Angle`
- `spin_rate` → `Spin Rate`

**Total rows:** 42
**Footer rows removed:** 2
**Final shot count:** 40

**Metric ranges (min / median / max):**
- Smash Factor: 0.95 / 1.27 / 1.37
- Ball Speed: 74.4 / 100.8 / 107.8 mph
- Spin Rate: 2646 / 4114 / 5160 rpm
- Descent Angle: 4.2 / 39.5 / 46.4°

**Template loaded:**
- Path: `data/templates/v2/template_7i_v2_unvalidated.json`
- Schema version: 1.0
- Club: 7i
- Aggregation method: worst_metric

**Template thresholds:**
- `ball_speed`: A ≥ 104.0, B ≥ 104.0, C < 104.0 (higher is better)
- `smash_factor`: A ≥ 1.25, B ≥ 1.22, C < 1.22 (higher is better)
- `spin_rate`: A ≥ 4300.0, B ≥ 4200.0, C < 4200.0 (higher is better)
- `descent_angle`: A ≥ 45.0, B ≥ 44.0, C < 44.0 (higher is better)

### Summary Table

| Grade | Count | Percentage |
|-------|-------|------------|
| **A** | 2 | 5.0% |
| **B** | 1 | 2.5% |
| **C** | 37 | 92.5% |
| **Total** | 40 | 100.0% |

### Failure Cause Breakdown

**Total C-shots:** 37

**Metrics responsible for C-grade (% of C-shots):**

- `ball_speed`: 27 / 37 (73.0%)
- `smash_factor`: 13 / 37 (35.1%)
- `spin_rate`: 22 / 37 (59.5%)
- `descent_angle`: 32 / 37 (86.5%)

*Note: A shot can fail on multiple metrics simultaneously.*

### Temporal Distribution (Session Quarters)

**Q1 (early):** 0A / 0B / 10C (A% = 0.0%)
**Q2:** 1A / 0B / 9C (A% = 10.0%)
**Q3:** 0A / 0B / 10C (A% = 0.0%)
**Q4 (late):** 1A / 1B / 8C (A% = 10.0%)

### Stress Test Analysis

**Question:** Does the template correctly identify degraded strike quality when the swing is compromised?

**Answer:** ✅ Yes

- A% dropped to 5.0% (expected: significantly below baseline)
- C% increased to 92.5% (expected: significantly above baseline)

✅ **Template successfully discriminates degraded performance.** The sore-elbow session produced a drastically lower A%, confirming the template correctly identifies compromised strike quality.


---

## Practice Plan Gap vs Phase 0 Grading Model

**This is a schema limitation, not a template bug.**

The Strike Quality Practice Session Plan includes threshold "gaps" that cannot be represented in the Phase 0 template schema:

**Practice Plan (prose):**
- Descent C-shot: < 43°
- Spin C-shot: < 4,100 rpm

**Template (Phase 0 schema):**
- Descent C-shot: < `b_min` (44.0°)
- Spin C-shot: < `b_min` (4,200 rpm)

In Phase 0, there is no way to encode a separate C threshold. The grading model is:
- A: value meets `a_min` (or `a_max` for lower-is-better)
- B: value meets `b_min` (or `b_max`) but not A
- C: value fails `b_min` (or `b_max`)

This makes the template **slightly stricter** than the documented Practice Plan thresholds.

**Recommendation:** Treat this as a documentation alignment issue for later phases. No changes to the template are proposed at this time.

---

## Confirmation Statement

**No thresholds, rules, or templates were modified during this analysis.**

This validation was read-only. All classification logic was imported directly from `raid/ingest.py` and used without modification.
