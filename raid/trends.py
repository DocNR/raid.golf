"""
Trend analysis for RAID Phase 0.1.

Kernel-safe trend computation using subsession aggregates only.
- No shot-level persistence required
- Derived projections (regenerable)
- Explicit validity filtering
"""
from dataclasses import dataclass
from typing import List, Optional, Dict, Any

from raid.repository import Repository


@dataclass
class TrendDataPoint:
    """Single data point in a trend."""
    session_date: str
    a_percentage: Optional[float]
    shot_count: int
    validity_status: str
    session_id: int
    subsession_id: int


@dataclass
class TrendResult:
    """Result of a trend computation."""
    club: str
    data_points: List[TrendDataPoint]
    weighted_avg_a_percent: Optional[float]
    total_sessions: int
    total_shots: int
    min_validity_filter: str


def compute_club_trend(
    repo: Repository,
    club: str,
    min_validity: str = "valid_low_sample_warning",
    window: Optional[int] = None,
    weighted: bool = True,
) -> TrendResult:
    """
    Compute A% trend over time for a club.
    
    This is a derived projection - trends are regenerable from authoritative data.
    
    Args:
        repo: Repository instance
        club: Club identifier
        min_validity: Minimum validity status to include
            - "invalid_insufficient_data": include all
            - "valid_low_sample_warning": include warning + valid
            - "valid": include only valid
        window: Optional rolling window (last N sessions by session_date)
        weighted: If True, compute shot-weighted average A%
    
    Returns:
        TrendResult with data points and aggregated statistics
    
    Raises:
        ValueError: If no data found for club with given filters
    """
    # Get subsessions for this club with validity filtering
    subsessions = repo.list_subsessions_by_club(club, min_validity=min_validity)
    
    if not subsessions:
        raise ValueError(
            f"No data found for club '{club}' with min_validity='{min_validity}'"
        )
    
    # Join with session data to get session_date for ordering
    data_points = []
    for sub in subsessions:
        session = repo.get_session(sub["session_id"])
        if not session:
            continue  # Skip if session not found (shouldn't happen)
        
        data_points.append(
            TrendDataPoint(
                session_date=session["session_date"],
                a_percentage=sub["a_percentage"],
                shot_count=sub["shot_count"],
                validity_status=sub["validity_status"],
                session_id=sub["session_id"],
                subsession_id=sub["subsession_id"],
            )
        )
    
    # Sort by session_date (chronological order)
    data_points.sort(key=lambda dp: dp.session_date)
    
    # Apply rolling window if specified (last N sessions)
    if window is not None and window > 0:
        # Get unique session dates
        session_dates = sorted(set(dp.session_date for dp in data_points))
        if len(session_dates) > window:
            # Keep only last N session dates
            cutoff_date = session_dates[-window]
            data_points = [dp for dp in data_points if dp.session_date >= cutoff_date]
    
    # Compute weighted average A%
    if weighted:
        # Only include data points with non-null A%
        valid_points = [dp for dp in data_points if dp.a_percentage is not None]
        if valid_points:
            total_weighted = sum(dp.a_percentage * dp.shot_count for dp in valid_points)
            total_shots_valid = sum(dp.shot_count for dp in valid_points)
            weighted_avg = total_weighted / total_shots_valid if total_shots_valid > 0 else None
        else:
            weighted_avg = None
    else:
        # Simple average (not recommended - ignores sample size)
        valid_points = [dp for dp in data_points if dp.a_percentage is not None]
        weighted_avg = (
            sum(dp.a_percentage for dp in valid_points) / len(valid_points)
            if valid_points
            else None
        )
    
    # Count unique sessions
    unique_sessions = len(set(dp.session_id for dp in data_points))
    total_shots = sum(dp.shot_count for dp in data_points)
    
    return TrendResult(
        club=club,
        data_points=data_points,
        weighted_avg_a_percent=weighted_avg,
        total_sessions=unique_sessions,
        total_shots=total_shots,
        min_validity_filter=min_validity,
    )