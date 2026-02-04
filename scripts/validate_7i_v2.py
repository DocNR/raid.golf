#!/usr/bin/env python3
"""
Phase 0.2 Validation Script — 7-Iron v2 Template

This script validates the 7-iron v2 template against real session data.
It uses the exact same classification logic as the production ingest module.

Usage:
    python scripts/validate_7i_v2.py
"""

import csv
import json
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from collections import defaultdict

# Add project root to path
PROJECT_ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from raid.ingest import _parse_rapsodo_csv, _classify_shot, _is_footer_row, _grade_metric


def load_template(template_path: str) -> Dict:
    """Load and parse template JSON."""
    with open(template_path, 'r') as f:
        return json.load(f)


def parse_csv_with_metadata(csv_path: str) -> Tuple[List[Dict], Dict]:
    """
    Parse CSV and return shots plus metadata.
    
    Returns:
        (shots, metadata) where metadata includes:
        - headers
        - total_rows
        - footer_rows
        - shot_count
        - column_mapping
    """
    shots = []
    metadata = {
        'headers': [],
        'total_rows': 0,
        'footer_rows': 0,
        'column_mapping': {},
    }
    
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        
        # Find header
        header = None
        for row_idx, row in enumerate(reader):
            if row_idx >= 3:
                break
            if row and 'Club Type' in row:
                header = row
                metadata['headers'] = header
                break
        
        if not header:
            raise ValueError("Could not find header row")
        
        # Build column mapping
        col_map = {}
        mappings = {
            "club type": "club",
            "carry distance": "carry_distance",
            "ball speed": "ball_speed",
            "smash factor": "smash_factor",
            "spin rate": "spin_rate",
            "descent angle": "descent_angle",
        }
        
        for idx, col_name in enumerate(header):
            col_lower = col_name.strip().lower()
            if col_lower in mappings:
                metric_name = mappings[col_lower]
                col_map[metric_name] = idx
                metadata['column_mapping'][metric_name] = col_name
        
        # Parse data rows
        for row in reader:
            metadata['total_rows'] += 1
            
            if not row:
                continue
            
            if _is_footer_row(row):
                metadata['footer_rows'] += 1
                continue
            
            try:
                club_raw = row[col_map["club"]].strip().strip('"')
                club = club_raw.lower()
                
                if club != '7i':
                    continue
                
                carry_distance = float(row[col_map["carry_distance"]].strip().strip('"'))
                ball_speed = float(row[col_map["ball_speed"]].strip().strip('"'))
                smash_factor = float(row[col_map["smash_factor"]].strip().strip('"'))
                spin_rate = float(row[col_map["spin_rate"]].strip().strip('"'))
                descent_angle = float(row[col_map["descent_angle"]].strip().strip('"'))
                
                shots.append({
                    "club": club,
                    "carry_distance": carry_distance,
                    "ball_speed": ball_speed,
                    "smash_factor": smash_factor,
                    "spin_rate": spin_rate,
                    "descent_angle": descent_angle,
                })
            except (ValueError, KeyError, IndexError):
                continue
    
    metadata['shot_count'] = len(shots)
    
    return shots, metadata


def compute_stats(shots: List[Dict], field: str) -> Tuple[float, float, float]:
    """Compute min, median, max for a field."""
    values = sorted([shot[field] for shot in shots])
    if not values:
        return 0.0, 0.0, 0.0
    
    n = len(values)
    median = values[n // 2] if n % 2 == 1 else (values[n // 2 - 1] + values[n // 2]) / 2
    
    return values[0], median, values[-1]


def classify_shots(shots: List[Dict], template: Dict) -> List[Tuple[Dict, str, Dict]]:
    """
    Classify shots and return (shot, grade, metric_grades).
    
    metric_grades is a dict mapping metric_name -> grade (A/B/C)
    """
    results = []
    
    for shot in shots:
        grade = _classify_shot(shot, template)
        
        # Compute per-metric grades
        metric_grades = {}
        metrics = template.get("metrics", {})
        metric_field_map = {
            "ball_speed": "ball_speed",
            "smash_factor": "smash_factor",
            "spin_rate": "spin_rate",
            "descent_angle": "descent_angle",
        }
        
        for metric_name, thresholds in metrics.items():
            if metric_name not in metric_field_map:
                continue
            
            field_name = metric_field_map[metric_name]
            value = shot.get(field_name)
            
            if value is None:
                metric_grades[metric_name] = "C"
            else:
                metric_grades[metric_name] = _grade_metric(value, thresholds)
        
        results.append((shot, grade, metric_grades))
    
    return results


def analyze_failure_causes(results: List[Tuple[Dict, str, Dict]]) -> Dict[str, int]:
    """Count how many C-shots failed on each metric."""
    failure_counts = defaultdict(int)
    
    for shot, grade, metric_grades in results:
        if grade == "C":
            for metric_name, metric_grade in metric_grades.items():
                if metric_grade == "C":
                    failure_counts[metric_name] += 1
    
    return dict(failure_counts)


def analyze_temporal_distribution(results: List[Tuple[Dict, str, Dict]]) -> Dict[str, List[str]]:
    """Analyze A/B/C distribution by session quarter."""
    total = len(results)
    quarter_size = total // 4
    
    quarters = {
        "Q1 (early)": [],
        "Q2": [],
        "Q3": [],
        "Q4 (late)": [],
    }
    
    for idx, (shot, grade, metric_grades) in enumerate(results):
        if idx < quarter_size:
            quarters["Q1 (early)"].append(grade)
        elif idx < 2 * quarter_size:
            quarters["Q2"].append(grade)
        elif idx < 3 * quarter_size:
            quarters["Q3"].append(grade)
        else:
            quarters["Q4 (late)"].append(grade)
    
    return quarters


def generate_report(
    session_name: str,
    csv_path: str,
    template_path: str,
    template: Dict,
    shots: List[Dict],
    metadata: Dict,
    results: List[Tuple[Dict, str, Dict]],
    is_primary: bool,
) -> str:
    """Generate markdown report for one session."""
    
    # Count grades
    grade_counts = {"A": 0, "B": 0, "C": 0}
    for shot, grade, metric_grades in results:
        grade_counts[grade] += 1
    
    total = len(results)
    a_pct = (grade_counts["A"] / total * 100) if total > 0 else 0
    b_pct = (grade_counts["B"] / total * 100) if total > 0 else 0
    c_pct = (grade_counts["C"] / total * 100) if total > 0 else 0
    
    # Compute stats
    smash_stats = compute_stats(shots, "smash_factor")
    ball_speed_stats = compute_stats(shots, "ball_speed")
    spin_stats = compute_stats(shots, "spin_rate")
    descent_stats = compute_stats(shots, "descent_angle")
    
    # Analyze failures
    failure_causes = analyze_failure_causes(results)
    
    # Temporal analysis
    quarters = analyze_temporal_distribution(results)
    
    # Build report
    report = []
    
    if is_primary:
        report.append("# Phase 0.2 Validation Report — 7-Iron v2 Template")
        report.append("")
        report.append("**Status:** Read-only validation (no templates or thresholds modified)")
        report.append("")
        report.append("---")
        report.append("")
    
    report.append(f"## {session_name}")
    report.append("")
    report.append(f"**CSV:** `{Path(csv_path).name}`")
    report.append(f"**Template:** `{Path(template_path).name}`")
    report.append(f"**Role:** {'Authoritative (used for readiness assessment)' if is_primary else 'Stress test (observational only)'}")
    report.append("")
    
    # CSV Sanity Panel
    report.append("### CSV Sanity Panel")
    report.append("")
    report.append("**Headers detected:**")
    report.append("```")
    report.append(", ".join(metadata['headers']))
    report.append("```")
    report.append("")
    report.append("**Column mapping (judgment metrics):**")
    for metric, col_name in metadata['column_mapping'].items():
        report.append(f"- `{metric}` → `{col_name}`")
    report.append("")
    report.append(f"**Total rows:** {metadata['total_rows']}")
    report.append(f"**Footer rows removed:** {metadata['footer_rows']}")
    report.append(f"**Final shot count:** {metadata['shot_count']}")
    report.append("")
    report.append("**Metric ranges (min / median / max):**")
    report.append(f"- Smash Factor: {smash_stats[0]:.2f} / {smash_stats[1]:.2f} / {smash_stats[2]:.2f}")
    report.append(f"- Ball Speed: {ball_speed_stats[0]:.1f} / {ball_speed_stats[1]:.1f} / {ball_speed_stats[2]:.1f} mph")
    report.append(f"- Spin Rate: {spin_stats[0]:.0f} / {spin_stats[1]:.0f} / {spin_stats[2]:.0f} rpm")
    report.append(f"- Descent Angle: {descent_stats[0]:.1f} / {descent_stats[1]:.1f} / {descent_stats[2]:.1f}°")
    report.append("")
    report.append("**Template loaded:**")
    report.append(f"- Path: `{template_path}`")
    report.append(f"- Schema version: {template.get('schema_version', 'unknown')}")
    report.append(f"- Club: {template.get('club', 'unknown')}")
    report.append(f"- Aggregation method: {template.get('aggregation_method', 'unknown')}")
    report.append("")
    report.append("**Template thresholds:**")
    metrics = template.get("metrics", {})
    for metric_name, thresholds in metrics.items():
        direction = thresholds.get("direction", "unknown")
        a_min = thresholds.get("a_min", "N/A")
        b_min = thresholds.get("b_min", "N/A")
        a_max = thresholds.get("a_max", "N/A")
        b_max = thresholds.get("b_max", "N/A")
        
        if direction == "higher_is_better":
            report.append(f"- `{metric_name}`: A ≥ {a_min}, B ≥ {b_min}, C < {b_min} (higher is better)")
        elif direction == "lower_is_better":
            report.append(f"- `{metric_name}`: A ≤ {a_max}, B ≤ {b_max}, C > {b_max} (lower is better)")
        else:
            report.append(f"- `{metric_name}`: {thresholds}")
    report.append("")
    
    # Summary Table
    report.append("### Summary Table")
    report.append("")
    report.append("| Grade | Count | Percentage |")
    report.append("|-------|-------|------------|")
    report.append(f"| **A** | {grade_counts['A']} | {a_pct:.1f}% |")
    report.append(f"| **B** | {grade_counts['B']} | {b_pct:.1f}% |")
    report.append(f"| **C** | {grade_counts['C']} | {c_pct:.1f}% |")
    report.append(f"| **Total** | {total} | 100.0% |")
    report.append("")
    
    # Failure Cause Breakdown
    report.append("### Failure Cause Breakdown")
    report.append("")
    report.append(f"**Total C-shots:** {grade_counts['C']}")
    report.append("")
    if grade_counts['C'] > 0:
        report.append("**Metrics responsible for C-grade (% of C-shots):**")
        report.append("")
        for metric_name in ["ball_speed", "smash_factor", "spin_rate", "descent_angle"]:
            count = failure_causes.get(metric_name, 0)
            pct = (count / grade_counts['C'] * 100) if grade_counts['C'] > 0 else 0
            report.append(f"- `{metric_name}`: {count} / {grade_counts['C']} ({pct:.1f}%)")
        report.append("")
        report.append("*Note: A shot can fail on multiple metrics simultaneously.*")
    else:
        report.append("No C-shots in this session.")
    report.append("")
    
    # Temporal Distribution
    report.append("### Temporal Distribution (Session Quarters)")
    report.append("")
    for quarter_name, grades in quarters.items():
        a_count = grades.count("A")
        b_count = grades.count("B")
        c_count = grades.count("C")
        total_q = len(grades)
        a_pct_q = (a_count / total_q * 100) if total_q > 0 else 0
        report.append(f"**{quarter_name}:** {a_count}A / {b_count}B / {c_count}C (A% = {a_pct_q:.1f}%)")
    report.append("")
    
    # Observed vs Expected (primary only)
    if is_primary:
        report.append("### Observed vs Expected Behavior")
        report.append("")
        report.append("**Expected A% range:** 40–60%")
        report.append(f"**Observed A%:** {a_pct:.1f}%")
        report.append("")
        
        if 40 <= a_pct <= 60:
            report.append("✅ **A% is within expected range (40–60%).**")
        elif 60 < a_pct <= 70:
            report.append("⚠️ **A% is in exceptional range (60–70%).** Template may be slightly loose, but this is not necessarily a problem.")
        elif a_pct > 70:
            report.append("❌ **A% is above 70%.** Template thresholds may be too loose; template is not discriminating.")
        elif 30 <= a_pct < 40:
            report.append("⚠️ **A% is below expected range (30–40%).** Template may be slightly strict, or performance has regressed.")
        else:
            report.append("❌ **A% is below 30%.** Template thresholds may be too strict, or technique has significantly regressed.")
        report.append("")
        
        report.append("**B-shot presence:**")
        if grade_counts['B'] > 0:
            report.append(f"✅ **B-shots are present ({grade_counts['B']} shots, {b_pct:.1f}%).** Template is discriminating between borderline and clear failures.")
        else:
            report.append("⚠️ **No B-shots.** This may indicate thresholds are too strict (no borderline zone) or too loose (no failures).")
        report.append("")
        
        report.append("**C-shot explainability:**")
        if grade_counts['C'] > 0:
            dominant_metric = max(failure_causes, key=failure_causes.get) if failure_causes else None
            if dominant_metric:
                dominant_count = failure_causes[dominant_metric]
                dominant_pct = (dominant_count / grade_counts['C'] * 100)
                
                if dominant_pct > 80:
                    report.append(f"⚠️ **Single metric dominates failures:** `{dominant_metric}` causes {dominant_pct:.1f}% of C-shots. This may indicate that metric's threshold is misaligned.")
                else:
                    report.append(f"✅ **Failures are distributed across metrics.** No single metric dominates.")
        report.append("")
    
    # Readiness Assessment (primary only)
    if is_primary:
        report.append("### Template v1.0 Readiness Checklist")
        report.append("")
        report.append("**Prerequisites:**")
        report.append("- ⚠️ Minimum 3 full sessions (≥15 shots each): **Cannot assess with single session**")
        report.append("- ⚠️ Minimum 25 A-shots accumulated: **Cannot assess with single session**")
        report.append("- ⚠️ Template used for ≥2 weeks: **Cannot assess with single session**")
        report.append("- ⚠️ No threshold changes in last 5 sessions: **Cannot assess with single session**")
        report.append("")
        report.append("**A% Range Assessment:**")
        if 40 <= a_pct <= 60:
            report.append(f"- ✅ A% is in normal range (40–60%): {a_pct:.1f}%")
        elif 60 < a_pct <= 70:
            report.append(f"- ✅ A% is in exceptional range (60–70%): {a_pct:.1f}%")
        else:
            report.append(f"- ❌ A% is outside acceptable ranges: {a_pct:.1f}%")
        report.append("")
        report.append("**Failure Pattern Assessment:**")
        if grade_counts['B'] > 0 and grade_counts['C'] > 0:
            report.append("- ✅ Mix of B-shots and C-shots present")
        else:
            report.append("- ❌ No mix of B-shots and C-shots")
        
        if failure_causes:
            dominant_metric = max(failure_causes, key=failure_causes.get)
            dominant_pct = (failure_causes[dominant_metric] / grade_counts['C'] * 100) if grade_counts['C'] > 0 else 0
            if dominant_pct <= 80:
                report.append("- ✅ Failures are distributed across metrics")
            else:
                report.append(f"- ❌ Single metric dominates failures: `{dominant_metric}` ({dominant_pct:.1f}%)")
        report.append("")
        report.append("**Single-Session Readiness Judgment:**")
        report.append("")
        report.append("⚠️ **This is a single-session validation.** Full readiness cannot be assessed without:")
        report.append("- Additional sessions (minimum 3 total)")
        report.append("- Session-to-session stability analysis")
        report.append("- Multi-week usage history")
        report.append("")
        report.append("**However, this session suggests:**")
        if 40 <= a_pct <= 60 and grade_counts['B'] > 0:
            report.append("- ✅ Template behavior is **consistent with expectations** for this session")
            report.append("- ✅ A% is in normal range and B-shots are present")
            report.append("- ✅ Template appears ready for **continued validation** with additional sessions")
        else:
            report.append("- ⚠️ Template behavior requires **further investigation** before validation")
        report.append("")
    else:
        # Stress test analysis
        report.append("### Stress Test Analysis")
        report.append("")
        report.append("**Question:** Does the template correctly identify degraded strike quality when the swing is compromised?")
        report.append("")
        report.append(f"**Answer:** {'✅ Yes' if a_pct < 20 else '⚠️ Partially' if a_pct < 40 else '❌ No'}")
        report.append("")
        report.append(f"- A% dropped to {a_pct:.1f}% (expected: significantly below baseline)")
        report.append(f"- C% increased to {c_pct:.1f}% (expected: significantly above baseline)")
        report.append("")
        if a_pct < 20:
            report.append("✅ **Template successfully discriminates degraded performance.** The sore-elbow session produced a drastically lower A%, confirming the template correctly identifies compromised strike quality.")
        elif a_pct < 40:
            report.append("⚠️ **Template shows some sensitivity to degraded performance,** but the difference may not be as dramatic as expected.")
        else:
            report.append("❌ **Template may not be sensitive enough** to degraded performance.")
        report.append("")
    
    return "\n".join(report)


def main():
    # Paths
    template_path = "data/templates/v2/template_7i_v2_unvalidated.json"
    csv_primary = "/Users/danielwyler/Downloads/mlm2pro_shotexport_012726.csv"
    csv_stress = "/Users/danielwyler/Downloads/mlm2pro_shotexport_020326.csv"
    output_path = "data/summaries/phase02_validation_report.md"
    
    # Load template
    template = load_template(template_path)
    
    # Process primary session
    print("Processing primary session (healthy, Jan 27)...")
    shots_primary, metadata_primary = parse_csv_with_metadata(csv_primary)
    results_primary = classify_shots(shots_primary, template)
    
    report_primary = generate_report(
        session_name="Run A — Authoritative Session (Jan 27, 2026)",
        csv_path=csv_primary,
        template_path=template_path,
        template=template,
        shots=shots_primary,
        metadata=metadata_primary,
        results=results_primary,
        is_primary=True,
    )
    
    # Process stress test session
    print("Processing stress test session (sore elbow, Feb 3)...")
    shots_stress, metadata_stress = parse_csv_with_metadata(csv_stress)
    results_stress = classify_shots(shots_stress, template)
    
    report_stress = generate_report(
        session_name="Run B — Stress Test Session (Feb 3, 2026)",
        csv_path=csv_stress,
        template_path=template_path,
        template=template,
        shots=shots_stress,
        metadata=metadata_stress,
        results=results_stress,
        is_primary=False,
    )
    
    # Combine reports
    full_report = report_primary + "\n\n---\n\n" + report_stress
    
    # Add footer
    full_report += "\n\n---\n\n"
    full_report += "## Practice Plan Gap vs Phase 0 Grading Model\n\n"
    full_report += "**This is a schema limitation, not a template bug.**\n\n"
    full_report += "The Strike Quality Practice Session Plan includes threshold \"gaps\" that cannot be represented in the Phase 0 template schema:\n\n"
    full_report += "**Practice Plan (prose):**\n"
    full_report += "- Descent C-shot: < 43°\n"
    full_report += "- Spin C-shot: < 4,100 rpm\n\n"
    full_report += "**Template (Phase 0 schema):**\n"
    full_report += "- Descent C-shot: < `b_min` (44.0°)\n"
    full_report += "- Spin C-shot: < `b_min` (4,200 rpm)\n\n"
    full_report += "In Phase 0, there is no way to encode a separate C threshold. The grading model is:\n"
    full_report += "- A: value meets `a_min` (or `a_max` for lower-is-better)\n"
    full_report += "- B: value meets `b_min` (or `b_max`) but not A\n"
    full_report += "- C: value fails `b_min` (or `b_max`)\n\n"
    full_report += "This makes the template **slightly stricter** than the documented Practice Plan thresholds.\n\n"
    full_report += "**Recommendation:** Treat this as a documentation alignment issue for later phases. No changes to the template are proposed at this time.\n\n"
    full_report += "---\n\n"
    full_report += "## Confirmation Statement\n\n"
    full_report += "**No thresholds, rules, or templates were modified during this analysis.**\n\n"
    full_report += "This validation was read-only. All classification logic was imported directly from `raid/ingest.py` and used without modification.\n"
    
    # Write report
    with open(output_path, 'w') as f:
        f.write(full_report)
    
    print(f"\nValidation report written to: {output_path}")
    print("\nSummary:")
    print(f"  Primary session (Jan 27): {len(shots_primary)} shots")
    grade_counts_primary = {"A": 0, "B": 0, "C": 0}
    for _, grade, _ in results_primary:
        grade_counts_primary[grade] += 1
    print(f"    A: {grade_counts_primary['A']} ({grade_counts_primary['A']/len(shots_primary)*100:.1f}%)")
    print(f"    B: {grade_counts_primary['B']} ({grade_counts_primary['B']/len(shots_primary)*100:.1f}%)")
    print(f"    C: {grade_counts_primary['C']} ({grade_counts_primary['C']/len(shots_primary)*100:.1f}%)")
    
    print(f"\n  Stress test (Feb 3): {len(shots_stress)} shots")
    grade_counts_stress = {"A": 0, "B": 0, "C": 0}
    for _, grade, _ in results_stress:
        grade_counts_stress[grade] += 1
    print(f"    A: {grade_counts_stress['A']} ({grade_counts_stress['A']/len(shots_stress)*100:.1f}%)")
    print(f"    B: {grade_counts_stress['B']} ({grade_counts_stress['B']/len(shots_stress)*100:.1f}%)")
    print(f"    C: {grade_counts_stress['C']} ({grade_counts_stress['C']/len(shots_stress)*100:.1f}%)")


if __name__ == "__main__":
    main()