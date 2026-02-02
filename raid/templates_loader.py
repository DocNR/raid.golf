"""
Template loader for RAID Phase 0.1.

Loads KPI templates from tools/kpis.json and stores them in the database
using the canonical template format with content-addressed hashing.

Kernel-safe:
- Uses existing canonical.py and hashing.py without modification
- Hashes templates ONCE at insert time
- Insert-only (no-op if template hash already exists)
- Never updates templates in-place
"""
import json
from pathlib import Path
from typing import Dict, List, Any, Optional

from raid.canonical import canonicalize
from raid.hashing import compute_template_hash
from raid.repository import Repository


# Canonical metric directions (single source of truth)
# Must match evaluator expectations in raid/ingest.py
METRIC_DIRECTIONS = {
    "ball_speed": "higher_is_better",
    "smash_factor": "higher_is_better",
    "spin_rate": "higher_is_better",
    "descent_angle": "higher_is_better",
}

# Supported canonical metric names (must match evaluator)
SUPPORTED_METRICS = set(METRIC_DIRECTIONS.keys())


def load_templates_from_kpis_json(
    repo: Repository,
    kpis_path: str = "tools/kpis.json",
    version: Optional[str] = None,
) -> Dict[str, List[str]]:
    """
    Load KPI templates from tools/kpis.json into the database.
    
    Args:
        repo: Repository instance
        kpis_path: Path to kpis.json file
        version: Specific version to load (None = use active version per club)
    
    Returns:
        Dict with keys:
        - "inserted": List of template_hashes that were inserted
        - "existing": List of template_hashes that already existed
        - "skipped": List of (club, reason) tuples for skipped clubs
    
    Raises:
        FileNotFoundError: If kpis.json doesn't exist
        ValueError: If kpis.json is malformed or contains unsupported data
    """
    kpis_file = Path(kpis_path)
    if not kpis_file.exists():
        raise FileNotFoundError(f"KPI file not found: {kpis_path}")
    
    with open(kpis_file, 'r', encoding='utf-8') as f:
        kpis_data = json.load(f)
    
    inserted = []
    existing = []
    skipped = []
    
    clubs = kpis_data.get("clubs", {})
    
    for club_name, club_data in clubs.items():
        # Determine which version to use
        if version is not None:
            # Specific version requested
            versions = club_data.get("versions", {})
            if version not in versions:
                # Skip clubs that don't have this version
                skipped.append((club_name, f"version {version} not found"))
                continue
            version_data = versions[version]
            thresholds = version_data.get("thresholds", {})
            kpi_version = version_data.get("kpi_version", version)
        else:
            # Use active version (top-level a/b/c thresholds)
            thresholds = {
                "a": club_data.get("a", {}),
                "b": club_data.get("b", {}),
                "c": club_data.get("c", {}),
            }
            kpi_version = club_data.get("kpi_version", kpis_data.get("default_kpi_version", "v1.0"))
        
        # Convert to canonical template format
        # Note: C thresholds in kpis.json are ignored - evaluator uses implicit C (below B)
        try:
            template = _convert_to_canonical_template(
                club=club_name,
                thresholds=thresholds,
                schema_version="1.0",
                kpi_version=kpi_version,
            )
        except ValueError as e:
            skipped.append((club_name, str(e)))
            continue
        
        # Canonicalize and hash (ONCE, at insert time per kernel rules)
        canonical_json = canonicalize(template)
        template_hash = compute_template_hash(canonical_json)
        
        # Check if template already exists
        existing_template = repo.get_template(template_hash)
        
        if existing_template is not None:
            # Template already exists → no-op (idempotent per kernel rules)
            existing.append(template_hash)
        else:
            # Insert new template
            repo.insert_template(
                template_hash=template_hash,
                schema_version="1.0",
                club=club_name,
                canonical_json=canonical_json,
            )
            inserted.append(template_hash)
    
    return {
        "inserted": inserted,
        "existing": existing,
        "skipped": skipped,
    }


def _convert_to_canonical_template(
    club: str,
    thresholds: Dict[str, Dict[str, float]],
    schema_version: str = "1.0",
    kpi_version: str = "v1.0",
) -> Dict[str, Any]:
    """
    Convert kpis.json threshold format to canonical template format.
    
    Args:
        club: Club identifier
        thresholds: Dict with "a", "b" threshold dictionaries (c is ignored)
        schema_version: Template schema version
        kpi_version: Source KPI version for provenance
    
    Returns:
        Canonical template dict
    
    Raises:
        ValueError: If thresholds contain unsupported metrics
    """
    a_thresholds = thresholds.get("a", {})
    b_thresholds = thresholds.get("b", {})
    # Note: C thresholds are intentionally ignored - evaluator infers C as below B
    
    metrics = {}
    
    # Map kpis.json keys to canonical metric names
    # A-grade threshold mappings
    a_metric_mappings = {
        "ball_speed_min": ("ball_speed", "a_min"),
        "smash_min": ("smash_factor", "a_min"),
        "spin_min": ("spin_rate", "a_min"),
        "descent_min": ("descent_angle", "a_min"),
    }
    
    # Process A-grade thresholds
    for kpi_key, (metric_name, threshold_key) in a_metric_mappings.items():
        if kpi_key in a_thresholds:
            if metric_name not in metrics:
                # Assign direction from canonical mapping (no inference)
                direction = METRIC_DIRECTIONS[metric_name]
                metrics[metric_name] = {"direction": direction}
            metrics[metric_name][threshold_key] = a_thresholds[kpi_key]
    
    # B-grade threshold mappings
    b_metric_mappings = {
        "ball_speed_min": ("ball_speed", "b_min"),
        "ball_speed_max": ("ball_speed", "b_max"),
        "smash_min": ("smash_factor", "b_min"),
        "smash_max": ("smash_factor", "b_max"),
        "spin_min": ("spin_rate", "b_min"),
        "spin_max": ("spin_rate", "b_max"),
        "descent_min": ("descent_angle", "b_min"),
        "descent_max": ("descent_angle", "b_max"),
    }
    
    # Process B-grade thresholds
    for kpi_key, (metric_name, threshold_key) in b_metric_mappings.items():
        if kpi_key in b_thresholds:
            if metric_name not in metrics:
                # Assign direction from canonical mapping (no inference)
                direction = METRIC_DIRECTIONS[metric_name]
                metrics[metric_name] = {"direction": direction}
            metrics[metric_name][threshold_key] = b_thresholds[kpi_key]
    
    # Validate all metrics are supported
    for metric_name in metrics.keys():
        if metric_name not in SUPPORTED_METRICS:
            raise ValueError(
                f"Unsupported metric '{metric_name}'. "
                f"Canonical schema supports: {sorted(SUPPORTED_METRICS)}"
            )
    
    # Build canonical template with provenance
    template = {
        "schema_version": schema_version,
        "club": club,
        "metrics": metrics,
        "aggregation_method": "worst_metric",
        "source": "tools/kpis.json",
        "kpi_version": kpi_version,
    }
    
    return template