# KPI Philosophy and Classification

## 1) Purpose
KPIs exist to define **what good means** in this system. They are standards, not analysis logic. The analysis can evolve, but KPIs are the stable reference that says, “this is the bar.”

KPI changes are intentional, rare, and never automatic. We do not move the standard because a week was great or a week was bad. KPIs are **not** grading curves; they are fixed targets that make performance comparable over time.

## 2) Separation of Concerns
This system separates three distinct responsibilities:

- **KPI generation (measurement):** Historical data is analyzed to propose candidate thresholds.
- **KPI activation (intent):** A human decides when a proposed KPI becomes active.
- **Session analysis (scoring):** Shots are scored against the active KPI version without modifying it.

Algorithms may propose thresholds. Humans decide when those thresholds become active. Session analysis never changes KPI definitions.

## 3) How A / B / C Categories Are Defined (Metric-Level)
**Baseline data selection** uses a single-club session with clean, valid shots (no missing metrics, no summaries, no non-shot rows). This baseline is treated as a stable reference, not a live stream.

**Percentiles are computed per metric** from the baseline dataset. For each metric:

- The **50th percentile** represents the median: half the shots are better, half are worse.
- The **70th percentile** represents a higher standard: only the top ~30% of baseline shots reach it.

These percentiles become fixed per-metric thresholds:

- **A ≥ 70th percentile**
- **B = 50th–70th percentile**
- **C < 50th percentile**

**Important rules:**

- Percentiles are used **only** at KPI generation time.
- Once activated, A/B/C thresholds are fixed and do not move.
- Percentiles are **not** involved during session scoring.

## 4) Shot-Level Classification: The Aggregation Model (CRITICAL)
Each shot is graded per metric (A/B/C). Those grades are combined into a **single shot-level grade** using a **worst-metric (“floor”) model**.

**Current model:**

- A shot’s overall grade equals its **lowest-performing metric**.
- Examples:
  - A, A, B, A → **B**
  - A, A, A, C → **C**
  - A, A, A, A → **A**

**Intent:**

- An A-shot represents **no meaningful weaknesses**.
- A single deficiency is sufficient to downgrade the shot.
- This favors consistency, robustness, and balanced strike quality.

## 5) Rationale for the Worst-Metric Model
This model is intentionally strict:

- It aligns with a **“no weak links”** definition of quality.
- It makes A-shots **meaningful and rare** under strict KPIs.
- It prevents high output in one dimension from masking deficiencies in others.
- It produces conservative, trustworthy classifications.

**Tradeoffs acknowledged:**

- The model is strict by design.
- It favors reliability over generosity.
- It is best for **benchmark** or **ceiling** KPIs rather than permissive baselines.

## 6) Alternative Aggregation Models (Documented, Not Active)
The aggregation rule determines the experience. Changing it changes the meaning of A/B/C. The following models are **not active** today:

- **Majority model:** A if ≥3 of 4 metrics are A. This feels more forgiving and rewards overall trend rather than perfection.
- **Weighted composite:** Metrics are combined into a single score. This creates a smooth continuum but obscures specific weaknesses.
- **“No C’s” rule:** A if all metrics are A/B, and B if any C. This reduces harshness while preserving minimum standards.
- **Profile-based aggregation:** Different aggregation for baseline vs challenge modes. This changes the experience based on intent.

These are documented to show that aggregation is a **deliberate design choice**. Any future change would require a new KPI philosophy decision, not a silent update.

## 7) Why Percentiles Are Used (and What They Are Not)
Percentiles are descriptive, not prescriptive. They ground thresholds in real data so that the system is explainable and repeatable.

Percentiles:

- Prevent arbitrary or emotionally chosen thresholds.
- Preserve provenance (“this came from that baseline”).
- Make candidate KPIs auditable.

Percentiles do **not** automatically redefine “good.” They do **not** promote themselves, and they do **not** imply that A-shots should always be rare. They only propose a candidate standard.

## 8) Why KPI Activation Is Deliberate
Automatic promotion undermines trust. Manual activation preserves meaning and intent. Redefining “good” is a conscious decision.

**Example:** A strict percentile-generated KPI version can exist as a reference. It becomes active only after **sustained improvement**, not after a hot session.

## 9) What This System Intentionally Avoids
This system explicitly avoids:

- Auto-resetting KPIs based on distributions
- Manual tuning of numeric thresholds
- Continuous re-centering of performance bands
- Silent reinterpretation of historical performance

## 10) Practical Mental Model
- **“KPIs are snapshots of standards.”**
- **“Percentiles propose; people decide.”**
- **“Aggregation defines experience; thresholds define rigor.”**
- **“Improvement raises performance, not the bar.”**
