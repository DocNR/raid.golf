# Template Artifacts — Documentation

**Purpose:** Define and document template-related artifacts in the RAID system  
**Authority:** Subordinate to Kernel Contract v2 and PRD Phase 0

---

## Template Types

### 1. KPI Templates (Kernel-Governed)

**What they are:**
- Immutable, content-addressed rule documents that define A/B/C classification thresholds
- Stored in the database with `template_hash` as primary key (SHA-256 of canonical JSON)
- Used by the evaluator to classify shots during session analysis

**Key properties:**
- **Immutable:** Once created, templates never change (editing creates a new template with new hash)
- **Content-addressed:** Identity is derived from content via RFC 8785 JCS + SHA-256
- **Ingestable:** Can be loaded into the database and referenced by subsessions
- **Kernel-governed:** Changes to template structure or hashing rules require kernel versioning

**Schema fields (Phase 0):**
```json
{
  "schema_version": "1.0",
  "club": "7i",
  "metrics": {
    "metric_name": {
      "a_min": <threshold>,
      "b_min": <threshold>,
      "direction": "higher_is_better"
    }
  },
  "aggregation_method": "worst_metric"
}
```

**Location:**
- Active templates: `data/templates/v2/` (or loaded from `tools/kpis.json`)
- Historical templates: Preserved in database; never deleted if referenced by subsessions

**Governance:**
- Template identity rules are frozen (Kernel v2.0)
- Template schema may evolve (new schema_version), but existing templates remain valid
- See `docs/private/kernel/KERNEL_CONTRACT_v2.md` for full governance rules

---

### 2. Template Skeletons (Design-Only Artifacts)

**What they are:**
- Design documents that define **metric intent** and **failure semantics** for club classes
- Used to plan and document template structure **before** setting numeric thresholds
- **Not ingestable:** Skeletons are not templates and cannot be used for shot classification

**What they are NOT:**
- Not dormant templates waiting for thresholds
- Not stored in the database
- Not referenced by subsessions
- Not hashed or content-addressed
- Not subject to kernel governance

**Key properties:**
- **Design-only:** Exist to document intent, not to classify shots
- **No thresholds:** Contain no numeric A/B/C cutoffs
- **No aggregation logic:** Do not define how metrics combine into shot grades
- **Outside kernel:** Changes to skeletons do not require kernel versioning

**Schema fields:**
```json
{
  "artifact_type": "template_skeleton",
  "club_class": "short_irons",
  "clubs": ["9i", "PW"],
  "judgment_metrics": [
    {
      "metric": "smash_factor",
      "role": "judgmental",
      "direction": "higher_is_better",
      "rationale": "..."
    }
  ],
  "diagnostic_metrics": [...],
  "excluded_metrics": [...],
  "c_definition": "...",
  "notes": "..."
}
```

**Location:**
- `docs/templates/skeletons/`

**Purpose:**
- Document which metrics are judgmental vs diagnostic vs excluded
- Define what "C-shot" means for each club class
- Identify cross-club consistency risks before validation
- Provide a blueprint for creating actual templates once thresholds are determined

**Lifecycle:**
1. Create skeleton (design phase)
2. Collect baseline data
3. Compute thresholds (percentile-based or manual)
4. Promote skeleton → template (add thresholds, aggregation, hash)
5. Validate template with real sessions
6. Mark template as `validated: true`

**Why skeletons exist:**
- Separates **intent** (what metrics matter) from **tuning** (what thresholds to use)
- Prevents premature threshold setting before sufficient data is collected
- Documents cross-club metric role decisions explicitly
- Reduces risk of over-optimization (thresholds are set once, not iteratively tuned)

---

## Artifact Comparison

| Property | KPI Template | Template Skeleton |
|----------|--------------|-------------------|
| **Purpose** | Classify shots (A/B/C) | Document metric intent |
| **Ingestable** | Yes | No |
| **Hashed** | Yes (SHA-256) | No |
| **Stored in DB** | Yes | No |
| **Contains thresholds** | Yes | No |
| **Contains aggregation** | Yes | No |
| **Kernel-governed** | Yes | No |
| **Immutable** | Yes | No (design doc) |
| **Location** | `data/templates/v2/` or DB | `docs/templates/skeletons/` |

---

## Design Workflow (Phase 0.1)

### Step 1: Define Skeletons
- Create skeleton JSON for each club class
- Document judgment vs diagnostic metrics
- Define C-shot failure semantics
- Identify cross-club consistency risks

### Step 2: Collect Baseline Data
- Hit 50+ shots with target club
- Export CSV from launch monitor
- Ensure clean data (no footer rows, no missing metrics)

### Step 3: Generate Thresholds
- Use `tools/kpi/generate_kpis.py` (percentile-based)
- Or manually set thresholds based on baseline review
- Document provenance (source session, method, date)

### Step 4: Create Template
- Combine skeleton structure + thresholds + aggregation
- Canonicalize JSON (RFC 8785 JCS)
- Compute hash (SHA-256)
- Store in database or `data/templates/v2/`

### Step 5: Validate Template
- Use template for 3+ sessions (≥15 shots each)
- Accumulate 25+ A-shots
- Check A% range (40–60% is normal)
- Assess failure patterns and stability
- See `docs/templates/template_design_phase01.md` for full checklist

### Step 6: Mark as Validated
- **Validation status is tracked externally** (in documentation, README, or a separate registry)
- **Template content and hash identity do not change**
- Freeze thresholds (no further tuning)
- Any future threshold changes create a new template (new hash)
- External tracking options:
  - Update `docs/templates/README.md` "Current Artifacts" section
  - Add entry to a validation registry (if implemented)
  - Document in `docs/templates/template_design_phase01.md`

---

## Current Artifacts (Phase 0.1)

### Templates
- **7i v2 (unvalidated):** `data/templates/v2/template_7i_v2_unvalidated.json`
  - Re-expression of v1 logic under Kernel v2 (RFC 8785 JCS + SHA-256)
  - Same thresholds as Strike Quality Practice Session Plan
  - **Status:** Unvalidated (no new data collected; awaiting real-world validation)
  - **Hash:** `27a3da06991da8bf6f66287c59717acff0c435f5f760e849eafab90ea3e9c0b0`

### Skeletons
- **Short Irons:** `docs/templates/skeletons/short_irons.json`
- **Mid Irons:** `docs/templates/skeletons/mid_irons.json`
- **Long Irons/Hybrids:** `docs/templates/skeletons/long_irons_hybrids.json`
- **Wedges:** `docs/templates/skeletons/wedges.json`

### Design Documentation
- **Template Design Phase 0.1:** `docs/templates/template_design_phase01.md`
  - Cross-club metric role matrix
  - Consistency risks
  - Template v1.0 readiness checklist (with stop conditions)

---

## FAQ

**Q: Can I edit a template?**  
A: No. Templates are immutable. To "edit" a template, create a new template with the desired changes. The new template will have a different hash.

**Q: Can I convert a skeleton into a template?**  
A: Not directly. Skeletons lack thresholds and aggregation logic. You must add these fields, canonicalize the JSON, compute the hash, and store it as a new template.

**Q: Why are skeletons separate from templates?**  
A: Skeletons document **intent** before thresholds are known. This prevents premature threshold setting and over-optimization. Once thresholds are validated, the skeleton is "promoted" to a template.

**Q: Can I delete a template?**  
A: Only if it's not referenced by any subsessions. Templates referenced by subsessions are protected by RESTRICT foreign key constraints.

**Q: What happens if I change a skeleton?**  
A: Nothing. Skeletons are design documents, not operational artifacts. Changes to skeletons do not affect existing templates or subsessions.

**Q: How do I know when a template is ready for validation?**  
A: See the "Template v1.0 Readiness Checklist" in `docs/templates/template_design_phase01.md`.

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-02-02 | Initial documentation (Phase 0.1) |
