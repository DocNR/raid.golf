"""
Projection generation and serialization for RAID Phase 0.

Projections are derived, regenerable exports of sub-session analysis results.
They CANNOT be imported as authoritative data (RTM-15, RTM-16).
"""
import json
from datetime import datetime, timezone
from typing import TYPE_CHECKING, Dict, Any

if TYPE_CHECKING:
    from raid.repository import Repository


class ProjectionImportError(Exception):
    """
    Raised when attempting to import a projection as authoritative data.
    
    Projections are read-only exports. To import session data, use the
    original CSV source file instead.
    """
    pass


def generate_projection_for_subsession(
    repo: "Repository",
    subsession_id: int
) -> Dict[str, Any]:
    """
    Generate a projection from authoritative SQLite data.
    
    A projection is a regenerable JSON export containing summary statistics
    for a club sub-session. It is derived from authoritative tables only.
    
    RTM-15: This function reads from authoritative tables and generates
    projections on-demand. Projections can be deleted and regenerated
    without information loss.
    
    Args:
        repo: Repository instance
        subsession_id: Sub-session to generate projection for
    
    Returns:
        Dict containing projection fields:
        - session_date: ISO-8601 timestamp from parent session
        - club: Club identifier
        - shot_count: Total shots analyzed
        - validity_status: Data quality indicator
        - a_count, b_count, c_count: Grade distributions
        - a_percentage: A-shot percentage (NULL if invalid)
        - avg_carry, avg_ball_speed, avg_spin, avg_descent: Averages
        - kpi_template_hash: Template used for analysis
        - analyzed_at: Analysis timestamp
        - generated_at: Projection generation timestamp (now)
    
    Raises:
        ValueError: If subsession_id not found
    """
    # Fetch subsession (authoritative)
    subsession = repo.get_subsession(subsession_id)
    if subsession is None:
        raise ValueError(f"Subsession {subsession_id} not found")
    
    # Fetch parent session (authoritative)
    session = repo.get_session(subsession["session_id"])
    if session is None:
        raise ValueError(
            f"Session {subsession['session_id']} not found for subsession {subsession_id}"
        )
    
    # Construct projection from authoritative data
    projection = {
        "session_date": session["session_date"],
        "club": subsession["club"],
        "shot_count": subsession["shot_count"],
        "validity_status": subsession["validity_status"],
        "a_count": subsession["a_count"],
        "b_count": subsession["b_count"],
        "c_count": subsession["c_count"],
        "a_percentage": subsession["a_percentage"],
        "avg_carry": subsession["avg_carry"],
        "avg_ball_speed": subsession["avg_ball_speed"],
        "avg_spin": subsession["avg_spin"],
        "avg_descent": subsession["avg_descent"],
        "kpi_template_hash": subsession["kpi_template_hash"],
        "analyzed_at": subsession["analyzed_at"],
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    }
    
    return projection


def serialize_projection(projection_dict: Dict[str, Any]) -> str:
    """
    Serialize a projection to deterministic JSON.
    
    RTM-15: Serialization must be deterministic for testing and caching.
    Multiple serializations of the same projection produce identical strings.
    
    Args:
        projection_dict: Projection dictionary
    
    Returns:
        Compact JSON string (sorted keys, no whitespace)
    """
    # Deterministic serialization:
    # - sort_keys=True: Alphabetically ordered keys
    # - separators: Compact format (no spaces)
    # - ensure_ascii=False: UTF-8 encoding
    return json.dumps(
        projection_dict,
        sort_keys=True,
        separators=(',', ':'),
        ensure_ascii=False
    )


def import_projection(projection_json: str) -> None:
    """
    Import a projection as authoritative data.
    
    RTM-15: This operation is PROHIBITED and always raises an error.
    
    Projections are read-only exports. They cannot be imported because:
    1. They lack raw shot-level data (information loss)
    2. They lose provenance (original CSV file reference)
    3. They would create duplicate records
    4. They bypass validation and integrity checks
    
    To import session data, use the original CSV source file instead.
    
    Args:
        projection_json: JSON projection string (ignored)
    
    Raises:
        ProjectionImportError: Always raised (import is prohibited)
    """
    raise ProjectionImportError(
        "Projections are read-only exports and cannot be imported as "
        "authoritative data. Import the original CSV source file instead."
    )
