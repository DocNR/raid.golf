# Template Design — Phase 0.1 (Groundwork)

**Status:** Design-only (no new data required)  
**Purpose:** Define metric intent, cross-club consistency, and readiness criteria before validation  
**Authority:** Subordinate to Strike Quality Practice Session Plan and Kernel Contract v2

---

## Cross-Club Metric Role Matrix

This matrix documents the **role** of each metric across club classes. Roles determine whether a metric drives A/B/C grading (judgmental) or provides context only (diagnostic).

| Metric | Short Irons (9i–PW) | Mid Irons (7i–8i) | Long Irons/Hybrids (5i–6i, 4h–5h) | Wedges (GW–LW) |
|--------|---------------------|-------------------|-----------------------------------|----------------|
| **smash_factor** | Judgmental | Judgmental | Judgmental | Judgmental |
| **ball_speed** | Judgmental | Judgmental | Judgmental | Judgmental |
| **spin_rate** | Judgmental | Judgmental | **Diagnostic** | Judgmental |
| **descent_angle** | Judgmental | Judgmental | Judgmental | **Diagnostic** |
| **carry_distance** | Diagnostic | Diagnostic | Diagnostic | Diagnostic |
| **launch_angle** | Diagnostic | Diagnostic | Diagnostic | Diagnostic |

### Key Decisions

#### 1. Smash Factor & Ball Speed (Universal Judgmental)
- **Role:** Judgmental across all club classes
- **Rationale:** These are the most direct indicators of strike quality (center contact and energy transfer)
- **Consistency:** No cross-club confusion; always grade-driving

#### 2. Spin Rate (Conditional Judgmental)
- **Short Irons & Mid Irons:** Judgmental
  - High spin is critical for stopping power and trajectory control
  - Low spin indicates thin/topped contact or delofting
- **Long Irons/Hybrids:** **Diagnostic**
  - Acceptable spin range is wider and player-dependent
  - Some players intentionally produce lower spin for penetrating flight
  - Downgrading to diagnostic prevents over-penalizing valid technique variations
- **Wedges:** Judgmental
  - Maximum spin is non-negotiable for wedge play
  - Any spin deficiency is a critical failure

**Risk:** If spin remains judgmental for long irons, A% will be artificially low for players with naturally lower spin profiles. This creates cross-club trend instability.

#### 3. Descent Angle (Conditional Judgmental)
- **Short Irons, Mid Irons, Long Irons/Hybrids:** Judgmental
  - Adequate descent is required for predictable landing and distance control
  - Shallow descent indicates launch or spin issues
- **Wedges:** **Diagnostic**
  - Wedges naturally produce steep descent angles
  - Risk of saturation: most/all shots will be near maximum descent
  - Downgrading to diagnostic prevents metric from becoming non-discriminating

**Risk:** If descent remains judgmental for wedges, it may fail to differentiate between shots (all A-grade on descent), reducing template usefulness.

---

## Cross-Club Consistency Risks

### Risk 1: Spin Rate Drift
- **Issue:** Spin thresholds vary widely across clubs (wedges ~8000+ rpm, long irons ~3500 rpm)
- **Impact:** Trends that aggregate across clubs will be noisy
- **Mitigation:** Always filter trends by club; never aggregate spin across club classes

### Risk 2: Descent Angle Saturation (Wedges)
- **Issue:** Wedges naturally produce 50°+ descent; most shots will cluster near max
- **Impact:** If judgmental, descent becomes non-discriminating (all A-grade)
- **Mitigation:** Downgrade to diagnostic for wedges; use spin as primary quality indicator

### Risk 3: Ball Speed Scaling
- **Issue:** Ball speed ranges differ dramatically (wedges ~70 mph, long irons ~120+ mph)
- **Impact:** Absolute thresholds must be club-specific; no universal "good" ball speed
- **Mitigation:** Templates are always club-specific; no cross-club ball speed comparisons

### Risk 4: Judgment Metric Count Variation
- **Issue:** Different club classes have different numbers of judgment metrics:
  - Short/Mid Irons: 4 judgment metrics
  - Long Irons/Hybrids: 3 judgment metrics
  - Wedges: 3 judgment metrics
- **Impact:** A% may not be directly comparable across club classes (fewer metrics = easier to achieve all-A)
- **Mitigation:** Accept this as intentional design; A% is club-specific, not universal

---

## Template v1.0 Readiness Checklist

This checklist defines when a template is ready for "v1.0" status (validated and stable). It includes explicit **stop conditions** to prevent over-optimization.

### Prerequisites (Must Be True)
- [ ] Minimum 3 full sessions with this club (≥15 shots each)
- [ ] Minimum 25 A-shots accumulated across all sessions
- [ ] Template has been used for at least 2 weeks (prevents hot-streak bias)
- [ ] No threshold changes in the last 5 sessions (stability requirement)

### A% Range Assessment
- [ ] **Normal range:** 40–60% A-shots per session
  - This indicates thresholds are challenging but achievable
  - Variance across sessions is expected and acceptable
- [ ] **Exceptional range:** 60–70% A-shots per session
  - This indicates strong performance or potentially loose thresholds
  - Review thresholds for rigor; consider tightening if sustained
- [ ] **Concerning range:** <30% or >75% A-shots per session
  - <30%: Thresholds may be too strict or technique has regressed
  - >75%: Thresholds may be too loose; template is not discriminating

**Stop Condition:** If A% is in normal range (40–60%) and stable across 3+ sessions, **do not tighten thresholds further**. Chasing higher A% leads to over-optimization.

### Failure Pattern Assessment
- [ ] **Acceptable failure patterns:**
  - Mix of B-shots and C-shots (indicates thresholds are well-calibrated)
  - C-shots are distributed across metrics (no single metric dominates failures)
- [ ] **Concerning failure patterns:**
  - All failures are C-shots (no B-shots): Thresholds may be too strict
  - All failures are B-shots (no C-shots): Thresholds may be too loose
  - One metric dominates failures (e.g., 80% of C-shots are low spin): Threshold for that metric may be misaligned

**Stop Condition:** If failure patterns are acceptable and stable, **do not adjust thresholds**. Some variance in failure modes is expected.

### Session-to-Session Stability
- [ ] A% variance across last 5 sessions is ≤15 percentage points
  - Example: If sessions are 45%, 52%, 48%, 50%, 47%, variance is 7 points (acceptable)
- [ ] No single session is an outlier (>20 points from median)
  - Outliers indicate fatigue, environmental factors, or intent changes (not template issues)

**Stop Condition:** If variance is ≤15 points, **do not adjust thresholds**. Some session-to-session variance is normal and expected.

### Stop Tuning Conditions (Critical)
Stop adjusting thresholds if **any** of the following are true:

1. **A% is stable in normal range (40–60%) across 3+ sessions**
   - Further tightening is over-optimization
   - Accept that some sessions will be better/worse than others

2. **Thresholds have been adjusted 3+ times in the last 10 sessions**
   - You are chasing noise, not signal
   - Template is unstable; lock current version and collect more data

3. **A% improvement is <5 percentage points after threshold change**
   - Change is not meaningful; revert to previous version
   - Small improvements may be noise or placebo

4. **Fatigue or technique changes are suspected**
   - Do not adjust template to compensate for temporary performance changes
   - Wait for performance to stabilize before re-evaluating

5. **You are tuning to a single "hot" session**
   - One great session does not justify tightening thresholds
   - Wait for sustained improvement across multiple sessions

### Validation Criteria (All Must Be True)
- [ ] All prerequisites met
- [ ] A% is in normal or exceptional range
- [ ] Failure patterns are acceptable
- [ ] Session-to-session stability is acceptable
- [ ] No stop conditions are triggered
- [ ] Template has been reviewed and approved by user

**Once validated:** Update external documentation (README, design doc) to mark template as validated. Template content and hash remain unchanged. Create a new template (new hash) for any future threshold adjustments.

---

## Notes on Over-Optimization

**Key Principle:** Some A% variance is **expected and acceptable**. Not every session will be 60%+ A-shots, and that's okay.

**Warning Signs of Over-Optimization:**
- Constantly adjusting thresholds after every session
- Chasing a specific A% target (e.g., "I want 70% A-shots")
- Tightening thresholds after a single great session
- Ignoring fatigue, environmental factors, or intent changes
- Treating B-shots as failures (they are borderline, not bad)

**Healthy Mindset:**
- A-shots represent **no meaningful weaknesses**
- B-shots represent **borderline performance** (acceptable, not ideal)
- C-shots represent **clear deficiencies** (exclude from gapping)
- A% will vary session-to-session; focus on trends, not single sessions
- Template stability is more valuable than marginal A% improvements

---

## Phase 0 Schema Limitation: B/C Threshold Gap

**This is a schema limitation, not a template bug.**

The Strike Quality Practice Session Plan includes threshold "gaps" (e.g., B ≥ 44° but C < 43°) that cannot be represented in the Phase 0 template schema.

**Practice Plan (prose):**
- Descent C-shot: < 43°
- Spin C-shot: < 4,100 rpm

**Phase 0 Template Schema:**
- Descent C-shot: < `b_min` (44.0°)
- Spin C-shot: < `b_min` (4,200 rpm)

In Phase 0, there is no way to encode a separate C threshold. The grading model is:
- **A:** value meets `a_min` (or `a_max` for lower-is-better)
- **B:** value meets `b_min` (or `b_max`) but not A
- **C:** value fails `b_min` (or `b_max`)

This makes Phase 0 templates **slightly stricter** than the documented Practice Plan thresholds. This is acceptable and expected. Future schema versions may support explicit C thresholds if needed.

**Key Takeaway:** The B/C gap is a documentation alignment issue, not a template error. Templates are correct per the Phase 0 schema.

---

## Skeleton Artifacts

The following skeleton JSONs define metric intent and structure for each club class. These are **design-only artifacts** and are not ingestable templates.

- `docs/templates/skeletons/short_irons.json`
- `docs/templates/skeletons/mid_irons.json`
- `docs/templates/skeletons/long_irons_hybrids.json`
- `docs/templates/skeletons/wedges.json`

See `docs/templates/README.md` for skeleton concept documentation.
