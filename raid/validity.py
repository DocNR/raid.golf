"""
Validity computation for club sub-sessions (RTM-07, RTM-08).

Phase 0 thresholds are fixed per PRD:
- shot_count < 5   -> invalid_insufficient_data
- 5 <= shot_count < 15 -> valid_low_sample_warning
- shot_count >= 15 -> valid
"""
from typing import Optional


def compute_validity_status(shot_count: int) -> str:
    """
    Compute validity status based on shot count.

    Args:
        shot_count: Total valid shots for a club sub-session.

    Returns:
        validity_status string enum.
    """
    if shot_count < 5:
        return "invalid_insufficient_data"
    if shot_count < 15:
        return "valid_low_sample_warning"
    return "valid"


def compute_a_percentage(
    a_count: int,
    shot_count: int,
    validity_status: str,
) -> Optional[float]:
    """
    Compute A% if validity allows it.

    Args:
        a_count: Number of A-grade shots.
        shot_count: Total valid shots.
        validity_status: Computed validity status.

    Returns:
        A% as float or None if invalid.
    """
    if validity_status == "invalid_insufficient_data":
        return None
    if shot_count <= 0:
        return None
    return (a_count / shot_count) * 100.0