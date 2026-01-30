"""
Unit tests for RTM-17: Multi-club CSV ingest.

Phase F validation that a single session can contain multiple clubs
and that mixed-club CSVs are correctly parsed and grouped.
"""
import json
import tempfile
from pathlib import Path

import pytest

from raid.canonical import canonicalize
from raid.hashing import compute_template_hash
from raid.repository import Repository


@pytest.fixture
def mixed_club_csv(vectors_dir: Path) -> Path:
    """Path to mixed-club test fixture CSV."""
    return vectors_dir / "sessions" / "rapsodo_mlm2pro_mixed_club_sample.csv"


@pytest.fixture
def temp_db():
    """Create a temporary database for each test."""
    with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as f:
        db_path = f.name
    
    repo = Repository(db_path)
    yield repo
    
    # Cleanup
    Path(db_path).unlink(missing_ok=True)


@pytest.fixture
def templates_7i_5i(temp_db: Repository):
    """
    Create and insert minimal PRD-format KPI templates for 7i and 5i.
    
    Returns dict: {"7i": template_hash, "5i": template_hash}
    """
    templates = {}
    
    # Template for 7i - using thresholds that will classify real shots
    template_7i = {
        "schema_version": "1.0",
        "club": "7i",
        "metrics": {
            "ball_speed": {
                "a_min": 103.0,
                "b_min": 101.0,
                "direction": "higher_is_better"
            },
            "smash_factor": {
                "a_min": 1.33,
                "b_min": 1.30,
                "direction": "higher_is_better"
            },
            "spin_rate": {
                "a_min": 5500,
                "b_min": 5000,
                "direction": "higher_is_better"
            },
            "descent_angle": {
                "a_min": 48.0,
                "b_min": 45.0,
                "direction": "higher_is_better"
            }
        },
        "aggregation_method": "worst_metric"
    }
    
    # Template for 5i
    template_5i = {
        "schema_version": "1.0",
        "club": "5i",
        "metrics": {
            "ball_speed": {
                "a_min": 110.0,
                "b_min": 105.0,
                "direction": "higher_is_better"
            },
            "smash_factor": {
                "a_min": 1.38,
                "b_min": 1.30,
                "direction": "higher_is_better"
            },
            "spin_rate": {
                "a_min": 4500,
                "b_min": 4000,
                "direction": "higher_is_better"
            },
            "descent_angle": {
                "a_min": 42.0,
                "b_min": 38.0,
                "direction": "higher_is_better"
            }
        },
        "aggregation_method": "worst_metric"
    }
    
    # Compute canonical JSON and template hashes
    for club, template in [("7i", template_7i), ("5i", template_5i)]:
        canonical_json = canonicalize(template)
        template_hash = compute_template_hash(canonical_json)
        
        # Insert into repository
        temp_db.insert_template(
            template_hash=template_hash,
            schema_version=template["schema_version"],
            club=club,
            canonical_json=canonical_json,
        )
        
        templates[club] = template_hash
    
    return templates


class TestRTM17MultiClubIngest:
    """RTM-17: Multi-club ingest tests."""
    
    def test_one_session_created(self, temp_db, mixed_club_csv, templates_7i_5i):
        """RTM-17: One session row is created for mixed-club CSV."""
        from raid.ingest import ingest_rapsodo_csv
        
        session_id = ingest_rapsodo_csv(
            repo=temp_db,
            csv_path=str(mixed_club_csv),
            template_hash_by_club=templates_7i_5i,
            session_date="2025-11-30T10:00:00Z"
        )
        
        # Verify session created
        session = temp_db.get_session(session_id)
        assert session is not None
        assert session["session_id"] == session_id
        assert session["session_date"] == "2025-11-30T10:00:00Z"
        assert "mlm2pro_mixed_club_sample.csv" in session["source_file"]
    
    def test_one_subsession_per_club(self, temp_db, mixed_club_csv, templates_7i_5i):
        """RTM-17: One sub-session per club is created."""
        from raid.ingest import ingest_rapsodo_csv
        
        session_id = ingest_rapsodo_csv(
            repo=temp_db,
            csv_path=str(mixed_club_csv),
            template_hash_by_club=templates_7i_5i,
            session_date="2025-11-30T10:00:00Z"
        )
        
        # Get all subsessions for this session
        subsessions = temp_db.list_subsessions_by_session(session_id)
        
        # Should have exactly 2 subsessions (7i and 5i)
        assert len(subsessions) == 2
        
        clubs = {sub["club"] for sub in subsessions}
        assert clubs == {"7i", "5i"}
    
    def test_same_session_id_shared(self, temp_db, mixed_club_csv, templates_7i_5i):
        """RTM-17: All sub-sessions share the same session_id."""
        from raid.ingest import ingest_rapsodo_csv
        
        session_id = ingest_rapsodo_csv(
            repo=temp_db,
            csv_path=str(mixed_club_csv),
            template_hash_by_club=templates_7i_5i,
            session_date="2025-11-30T10:00:00Z"
        )
        
        subsessions = temp_db.list_subsessions_by_session(session_id)
        
        # All subsessions must have the same session_id
        for sub in subsessions:
            assert sub["session_id"] == session_id
    
    def test_shot_count_excludes_footer_rows(self, temp_db, mixed_club_csv, templates_7i_5i):
        """RTM-17: shot_count excludes footer rows (Average, Std. Dev.)."""
        from raid.ingest import ingest_rapsodo_csv
        
        session_id = ingest_rapsodo_csv(
            repo=temp_db,
            csv_path=str(mixed_club_csv),
            template_hash_by_club=templates_7i_5i,
            session_date="2025-11-30T10:00:00Z"
        )
        
        subsessions = temp_db.list_subsessions_by_session(session_id)
        subsessions_by_club = {sub["club"]: sub for sub in subsessions}
        
        # 7i has 6 shots in fixture (not +2 from footer)
        assert subsessions_by_club["7i"]["shot_count"] == 6
        
        # 5i has 9 shots in fixture (not +2 from footer)
        assert subsessions_by_club["5i"]["shot_count"] == 9
    
    def test_abc_counts_computed_per_club(self, temp_db, mixed_club_csv, templates_7i_5i):
        """RTM-17: A/B/C counts are computed per club using club-specific templates."""
        from raid.ingest import ingest_rapsodo_csv
        
        session_id = ingest_rapsodo_csv(
            repo=temp_db,
            csv_path=str(mixed_club_csv),
            template_hash_by_club=templates_7i_5i,
            session_date="2025-11-30T10:00:00Z"
        )
        
        subsessions = temp_db.list_subsessions_by_session(session_id)
        
        for sub in subsessions:
            # All shots must be classified
            assert sub["a_count"] + sub["b_count"] + sub["c_count"] == sub["shot_count"]
            
            # At least some shots should be classified
            assert sub["a_count"] >= 0
            assert sub["b_count"] >= 0
            assert sub["c_count"] >= 0
    
    def test_validity_status_computed(self, temp_db, mixed_club_csv, templates_7i_5i):
        """RTM-17: Validity status is computed based on shot count."""
        from raid.ingest import ingest_rapsodo_csv
        
        session_id = ingest_rapsodo_csv(
            repo=temp_db,
            csv_path=str(mixed_club_csv),
            template_hash_by_club=templates_7i_5i,
            session_date="2025-11-30T10:00:00Z"
        )
        
        subsessions = temp_db.list_subsessions_by_session(session_id)
        subsessions_by_club = {sub["club"]: sub for sub in subsessions}
        
        # 7i: 6 shots -> valid_low_sample_warning (5 <= count < 15)
        assert subsessions_by_club["7i"]["validity_status"] == "valid_low_sample_warning"
        assert subsessions_by_club["7i"]["a_percentage"] is not None  # Should have A%
        
        # 5i: 9 shots -> valid_low_sample_warning (5 <= count < 15)
        assert subsessions_by_club["5i"]["validity_status"] == "valid_low_sample_warning"
        assert subsessions_by_club["5i"]["a_percentage"] is not None  # Should have A%
    
    def test_club_normalization(self, temp_db, mixed_club_csv, templates_7i_5i):
        """RTM-17: Club names are normalized (lowercase, trimmed)."""
        from raid.ingest import ingest_rapsodo_csv
        
        session_id = ingest_rapsodo_csv(
            repo=temp_db,
            csv_path=str(mixed_club_csv),
            template_hash_by_club=templates_7i_5i,
            session_date="2025-11-30T10:00:00Z"
        )
        
        subsessions = temp_db.list_subsessions_by_session(session_id)
        clubs = {sub["club"] for sub in subsessions}
        
        # All clubs should be normalized to lowercase
        assert all(club.islower() for club in clubs)
        assert clubs == {"7i", "5i"}
    
    def test_footer_rows_skipped(self, temp_db, mixed_club_csv, templates_7i_5i):
        """RTM-17: Footer rows (Average, Std. Dev.) are skipped during parsing."""
        from raid.ingest import ingest_rapsodo_csv
        
        # This test is validated by shot_count being correct
        # If footer rows were included, counts would be wrong
        session_id = ingest_rapsodo_csv(
            repo=temp_db,
            csv_path=str(mixed_club_csv),
            template_hash_by_club=templates_7i_5i,
            session_date="2025-11-30T10:00:00Z"
        )
        
        subsessions = temp_db.list_subsessions_by_session(session_id)
        total_shots = sum(sub["shot_count"] for sub in subsessions)
        
        # Total should be 15 (6 + 9), not 19 (6 + 9 + 2 + 2)
        assert total_shots == 15
    
    def test_template_hash_referenced(self, temp_db, mixed_club_csv, templates_7i_5i):
        """RTM-17: Sub-sessions correctly reference template_hash."""
        from raid.ingest import ingest_rapsodo_csv
        
        session_id = ingest_rapsodo_csv(
            repo=temp_db,
            csv_path=str(mixed_club_csv),
            template_hash_by_club=templates_7i_5i,
            session_date="2025-11-30T10:00:00Z"
        )
        
        subsessions = temp_db.list_subsessions_by_session(session_id)
        
        for sub in subsessions:
            club = sub["club"]
            # Each subsession should reference the correct template
            assert sub["kpi_template_hash"] == templates_7i_5i[club]
            
            # Template should exist in kpi_templates table
            template = temp_db.get_template(sub["kpi_template_hash"])
            assert template is not None
            assert template["club"] == club
    
    def test_averages_computed(self, temp_db, mixed_club_csv, templates_7i_5i):
        """RTM-17: Average metrics are computed for each club."""
        from raid.ingest import ingest_rapsodo_csv
        
        session_id = ingest_rapsodo_csv(
            repo=temp_db,
            csv_path=str(mixed_club_csv),
            template_hash_by_club=templates_7i_5i,
            session_date="2025-11-30T10:00:00Z"
        )
        
        subsessions = temp_db.list_subsessions_by_session(session_id)
        
        for sub in subsessions:
            # All averages should be populated
            assert sub["avg_carry"] is not None
            assert sub["avg_ball_speed"] is not None
            assert sub["avg_spin"] is not None
            assert sub["avg_descent"] is not None
            
            # Sanity check - values should be reasonable
            assert sub["avg_carry"] > 0
            assert sub["avg_ball_speed"] > 0
            assert sub["avg_spin"] > 0
            assert sub["avg_descent"] > 0
