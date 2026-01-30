"""
Rapsodo CSV ingest for RAID Phase 0.

Handles multi-club session ingest with footer row exclusion and shot classification.
"""
import csv
import json
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional

from raid.repository import Repository
from raid.validity import compute_validity_status, compute_a_percentage


def ingest_rapsodo_csv(
    repo: Repository,
    csv_path: str,
    template_hash_by_club: Dict[str, str],
    device_type: str = "Rapsodo MLM2Pro",
    location: Optional[str] = None,
    session_date: Optional[str] = None,
) -> int:
    """
    Ingest a Rapsodo MLM2Pro CSV with multiple clubs.
    
    Args:
        repo: Repository instance
        csv_path: Path to CSV file
        template_hash_by_club: Dict mapping club -> template_hash
        device_type: Device type string
        location: Practice location (optional)
        session_date: ISO-8601 timestamp (defaults to now)
    
    Returns:
        session_id of created session
    """
    if session_date is None:
        session_date = datetime.utcnow().isoformat() + 'Z'
    
    # Parse CSV
    shots_by_club = _parse_rapsodo_csv(csv_path)
    
    # Create session
    source_file = Path(csv_path).name
    session_id = repo.insert_session(
        session_date=session_date,
        source_file=source_file,
        device_type=device_type,
        location=location,
    )
    
    # Process each club
    for club, shots in shots_by_club.items():
        if club not in template_hash_by_club:
            # Skip clubs without templates
            continue
        
        template_hash = template_hash_by_club[club]
        
        # Load template for classification
        template_row = repo.get_template(template_hash)
        if not template_row:
            raise ValueError(f"Template hash {template_hash} not found for club {club}")
        
        template = json.loads(template_row["canonical_json"])
        
        # Classify shots
        a_count = 0
        b_count = 0
        c_count = 0
        
        for shot in shots:
            grade = _classify_shot(shot, template)
            if grade == "A":
                a_count += 1
            elif grade == "B":
                b_count += 1
            else:
                c_count += 1
        
        shot_count = len(shots)
        
        # Compute validity
        validity_status = compute_validity_status(shot_count)
        a_percentage = compute_a_percentage(a_count, shot_count, validity_status)
        
        # Compute averages
        avg_carry = _compute_average(shots, "carry_distance")
        avg_ball_speed = _compute_average(shots, "ball_speed")
        avg_spin = _compute_average(shots, "spin_rate")
        avg_descent = _compute_average(shots, "descent_angle")
        
        # Insert subsession
        repo.insert_subsession(
            session_id=session_id,
            club=club,
            kpi_template_hash=template_hash,
            shot_count=shot_count,
            validity_status=validity_status,
            a_count=a_count,
            b_count=b_count,
            c_count=c_count,
            a_percentage=a_percentage,
            avg_carry=avg_carry,
            avg_ball_speed=avg_ball_speed,
            avg_spin=avg_spin,
            avg_descent=avg_descent,
        )
    
    return session_id


def _parse_rapsodo_csv(csv_path: str) -> Dict[str, List[Dict[str, float]]]:
    """
    Parse Rapsodo CSV and group shots by club.
    
    Returns:
        Dict mapping normalized club name -> list of shot dicts
    """
    shots_by_club = defaultdict(list)
    
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        
        # Find header (search rows 1-3)
        header = None
        header_row_idx = None
        for row_idx, row in enumerate(reader):
            if row_idx >= 3:
                break
            if _is_header_row(row):
                header = row
                header_row_idx = row_idx
                break
        
        if header is None:
            raise ValueError("Could not find header row in first 3 rows")
        
        # Build column mapping
        col_map = _build_column_map(header)
        
        # Parse data rows
        for row in reader:
            if not row:
                continue
            
            # Skip footer rows
            if _is_footer_row(row):
                continue
            
            # Try to parse shot
            try:
                shot = _parse_shot_row(row, col_map)
                if shot:
                    club = shot["club"]
                    shots_by_club[club].append(shot)
            except (ValueError, IndexError):
                # Skip malformed rows silently (counted internally but not exposed yet)
                continue
    
    return dict(shots_by_club)


def _is_header_row(row: List[str]) -> bool:
    """Check if row is a header row."""
    # Header must contain these required columns
    required_cols = {"Club Type", "Ball Speed", "Smash Factor", "Spin Rate", "Descent Angle"}
    row_upper = {col.strip() for col in row if col}
    return required_cols.issubset(row_upper)


def _is_footer_row(row: List[str]) -> bool:
    """Check if row is a footer row (Average, Std Dev, etc.)."""
    if not row:
        return False
    first_cell = row[0].strip()
    return first_cell in ("Average", "Std. Dev.", "Std Dev")


def _build_column_map(header: List[str]) -> Dict[str, int]:
    """
    Build mapping from normalized column name to index.
    
    Returns:
        Dict mapping metric_name -> column_index
    """
    col_map = {}
    
    # Define column mappings (case-insensitive)
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
    
    return col_map


def _parse_shot_row(row: List[str], col_map: Dict[str, int]) -> Optional[Dict[str, float]]:
    """
    Parse a single shot row.
    
    Returns:
        Dict with shot metrics, or None if invalid
    """
    try:
        # Extract club
        club_raw = row[col_map["club"]].strip().strip('"')
        club = club_raw.lower()  # Normalize to lowercase
        
        # Parse required numeric fields
        carry_distance = float(row[col_map["carry_distance"]].strip().strip('"'))
        ball_speed = float(row[col_map["ball_speed"]].strip().strip('"'))
        smash_factor = float(row[col_map["smash_factor"]].strip().strip('"'))
        spin_rate = float(row[col_map["spin_rate"]].strip().strip('"'))
        descent_angle = float(row[col_map["descent_angle"]].strip().strip('"'))
        
        return {
            "club": club,
            "carry_distance": carry_distance,
            "ball_speed": ball_speed,
            "smash_factor": smash_factor,
            "spin_rate": spin_rate,
            "descent_angle": descent_angle,
        }
    except (ValueError, KeyError, IndexError):
        return None


def _classify_shot(shot: Dict[str, float], template: Dict) -> str:
    """
    Classify a shot as A, B, or C using worst_metric aggregation.
    
    Args:
        shot: Dict with shot metrics
        template: KPI template dict
    
    Returns:
        "A", "B", or "C"
    """
    metrics = template.get("metrics", {})
    aggregation_method = template.get("aggregation_method", "worst_metric")
    
    if aggregation_method != "worst_metric":
        raise ValueError(f"Unsupported aggregation method: {aggregation_method}")
    
    # Map template metric names to shot field names
    metric_field_map = {
        "ball_speed": "ball_speed",
        "smash_factor": "smash_factor",
        "spin_rate": "spin_rate",
        "descent_angle": "descent_angle",
    }
    
    worst_grade = "A"
    
    for metric_name, thresholds in metrics.items():
        if metric_name not in metric_field_map:
            continue
        
        field_name = metric_field_map[metric_name]
        value = shot.get(field_name)
        
        if value is None:
            worst_grade = "C"
            continue
        
        # Determine grade for this metric
        grade = _grade_metric(value, thresholds)
        
        # Update worst grade
        if grade == "C":
            worst_grade = "C"
        elif grade == "B" and worst_grade != "C":
            worst_grade = "B"
    
    return worst_grade


def _grade_metric(value: float, thresholds: Dict) -> str:
    """
    Grade a single metric value.
    
    Args:
        value: Metric value
        thresholds: Dict with a_min, b_min, b_max, etc.
    
    Returns:
        "A", "B", or "C"
    """
    direction = thresholds.get("direction", "higher_is_better")
    
    if direction == "higher_is_better":
        # A: value >= a_min
        # B: b_min <= value < a_min (or b_min <= value <= b_max if b_max defined)
        # C: value < b_min
        
        a_min = thresholds.get("a_min")
        b_min = thresholds.get("b_min")
        
        if a_min is not None and value >= a_min:
            return "A"
        
        if b_min is not None and value >= b_min:
            return "B"
        
        return "C"
    
    elif direction == "lower_is_better":
        # A: value <= a_max
        # B: a_max < value <= b_max
        # C: value > b_max
        
        a_max = thresholds.get("a_max")
        b_max = thresholds.get("b_max")
        
        if a_max is not None and value <= a_max:
            return "A"
        
        if b_max is not None and value <= b_max:
            return "B"
        
        return "C"
    
    else:
        raise ValueError(f"Unsupported direction: {direction}")


def _compute_average(shots: List[Dict[str, float]], field: str) -> Optional[float]:
    """Compute average for a field across shots."""
    values = [shot[field] for shot in shots if field in shot]
    if not values:
        return None
    return sum(values) / len(values)
