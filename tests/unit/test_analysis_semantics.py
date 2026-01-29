"""
Unit tests for analysis semantics (RTM-05, RTM-06).

These tests validate duplicate analysis prevention and re-analysis
with different templates.
"""
import sqlite3
import tempfile
from pathlib import Path

import pytest

from raid.canonical import canonicalize
from raid.hashing import compute_template_hash
from raid.repository import Repository


class TestDuplicateAnalysisPrevention:
    """RTM-05: Duplicate analysis must be prevented by UNIQUE constraint."""
    
    def test_duplicate_subsession_insert_rejected(self, tmp_path):
        """
        Attempting to insert a sub-session with the same
        (session_id, club, kpi_template_hash) tuple must fail.
        """
        db_path = str(tmp_path / "test.db")
        repo = Repository(db_path)
        
        # Create session and template
        session_id = repo.insert_session(
            session_date="2026-01-28T17:00:00Z",
            source_file="test.csv"
        )
        
        template_dict = {"club": "7i", "schema_version": "1.0"}
        canonical_json = canonicalize(template_dict)
        template_hash = compute_template_hash(template_dict)
        
        repo.insert_template(
            template_hash=template_hash,
            schema_version="1.0",
            club="7i",
            canonical_json=canonical_json
        )
        
        # Insert first sub-session
        subsession_id_1 = repo.insert_subsession(
            session_id=session_id,
            club="7i",
            kpi_template_hash=template_hash,
            shot_count=20,
            validity_status="valid",
            a_count=10,
            b_count=8,
            c_count=2,
            a_percentage=50.0
        )
        
        assert subsession_id_1 is not None
        
        # Attempt duplicate insert - should fail with UNIQUE constraint violation
        with pytest.raises(sqlite3.IntegrityError) as exc_info:
            repo.insert_subsession(
                session_id=session_id,
                club="7i",
                kpi_template_hash=template_hash,
                shot_count=25,  # Different data, but same unique key
                validity_status="valid",
                a_count=15,
                b_count=8,
                c_count=2,
                a_percentage=60.0
            )
        
        # Assert it's a UNIQUE constraint violation
        assert "UNIQUE" in str(exc_info.value).upper()
    
    def test_original_row_unchanged_after_duplicate_attempt(self, tmp_path):
        """
        After a failed duplicate insert, the original row must be unchanged.
        """
        db_path = str(tmp_path / "test.db")
        repo = Repository(db_path)
        
        # Create session and template
        session_id = repo.insert_session(
            session_date="2026-01-28T17:00:00Z",
            source_file="test.csv"
        )
        
        template_dict = {"club": "7i", "schema_version": "1.0"}
        canonical_json = canonicalize(template_dict)
        template_hash = compute_template_hash(template_dict)
        
        repo.insert_template(
            template_hash=template_hash,
            schema_version="1.0",
            club="7i",
            canonical_json=canonical_json
        )
        
        # Insert first sub-session
        subsession_id = repo.insert_subsession(
            session_id=session_id,
            club="7i",
            kpi_template_hash=template_hash,
            shot_count=20,
            validity_status="valid",
            a_count=10,
            b_count=8,
            c_count=2,
            a_percentage=50.0,
            avg_carry=150.5,
            avg_ball_speed=110.2
        )
        
        # Capture original row
        original_row = repo.get_subsession(subsession_id)
        
        # Attempt duplicate insert
        try:
            repo.insert_subsession(
                session_id=session_id,
                club="7i",
                kpi_template_hash=template_hash,
                shot_count=999,  # Completely different data
                validity_status="invalid_insufficient_data",
                a_count=0,
                b_count=0,
                c_count=999,
                a_percentage=None
            )
        except sqlite3.IntegrityError:
            pass  # Expected
        
        # Verify original row is unchanged
        current_row = repo.get_subsession(subsession_id)
        assert current_row == original_row
        assert current_row['shot_count'] == 20
        assert current_row['a_count'] == 10
        assert current_row['a_percentage'] == 50.0
    
    def test_duplicate_prevention_different_clubs_allowed(self, tmp_path):
        """
        Same session + template but different club should succeed.
        This validates the constraint is on the full tuple, not partial match.
        """
        db_path = str(tmp_path / "test.db")
        repo = Repository(db_path)
        
        # Create session and template
        session_id = repo.insert_session(
            session_date="2026-01-28T17:00:00Z",
            source_file="test.csv"
        )
        
        # Template for 7i
        template_dict = {"club": "7i", "schema_version": "1.0"}
        canonical_json = canonicalize(template_dict)
        template_hash = compute_template_hash(template_dict)
        
        repo.insert_template(
            template_hash=template_hash,
            schema_version="1.0",
            club="7i",
            canonical_json=canonical_json
        )
        
        # Insert sub-session for 7i
        subsession_id_7i = repo.insert_subsession(
            session_id=session_id,
            club="7i",
            kpi_template_hash=template_hash,
            shot_count=20,
            validity_status="valid",
            a_count=10,
            b_count=8,
            c_count=2,
            a_percentage=50.0
        )
        
        # Insert sub-session for PW with same template - should succeed
        # (different club breaks the UNIQUE constraint tuple)
        subsession_id_pw = repo.insert_subsession(
            session_id=session_id,
            club="PW",  # Different club
            kpi_template_hash=template_hash,
            shot_count=15,
            validity_status="valid",
            a_count=8,
            b_count=5,
            c_count=2,
            a_percentage=53.3
        )
        
        # Both inserts should succeed
        assert subsession_id_7i is not None
        assert subsession_id_pw is not None
        assert subsession_id_7i != subsession_id_pw
        
        # Verify both rows exist
        assert repo.get_subsession(subsession_id_7i)['club'] == "7i"
        assert repo.get_subsession(subsession_id_pw)['club'] == "PW"


class TestReAnalysisDifferentTemplate:
    """RTM-06: Re-analysis with different template must create new sub-session."""
    
    def test_reanalysis_different_template_succeeds(self, tmp_path):
        """
        Same session_id + club with different template_hash creates new row.
        """
        db_path = str(tmp_path / "test.db")
        repo = Repository(db_path)
        
        # Create session
        session_id = repo.insert_session(
            session_date="2026-01-28T17:00:00Z",
            source_file="test.csv"
        )
        
        # Create template version 1
        template_v1 = {"club": "7i", "version": "1"}
        canonical_v1 = canonicalize(template_v1)
        hash_v1 = compute_template_hash(template_v1)
        repo.insert_template(hash_v1, "1.0", "7i", canonical_v1)
        
        # Create template version 2
        template_v2 = {"club": "7i", "version": "2"}
        canonical_v2 = canonicalize(template_v2)
        hash_v2 = compute_template_hash(template_v2)
        repo.insert_template(hash_v2, "1.0", "7i", canonical_v2)
        
        # Insert sub-session with template v1
        subsession_id_v1 = repo.insert_subsession(
            session_id=session_id,
            club="7i",
            kpi_template_hash=hash_v1,
            shot_count=20,
            validity_status="valid",
            a_count=10,
            b_count=8,
            c_count=2,
            a_percentage=50.0
        )
        
        # Re-analyze same session+club with template v2 - should succeed
        subsession_id_v2 = repo.insert_subsession(
            session_id=session_id,
            club="7i",
            kpi_template_hash=hash_v2,
            shot_count=20,
            validity_status="valid",
            a_count=12,  # Different results with new template
            b_count=6,
            c_count=2,
            a_percentage=60.0
        )
        
        # Both should succeed and be different rows
        assert subsession_id_v1 is not None
        assert subsession_id_v2 is not None
        assert subsession_id_v1 != subsession_id_v2
    
    def test_original_subsession_unchanged_after_reanalysis(self, tmp_path):
        """
        Original sub-session remains intact after re-analysis with new template.
        """
        db_path = str(tmp_path / "test.db")
        repo = Repository(db_path)
        
        # Create session
        session_id = repo.insert_session(
            session_date="2026-01-28T17:00:00Z",
            source_file="test.csv"
        )
        
        # Create two templates
        template_v1 = {"club": "7i", "version": "1"}
        canonical_v1 = canonicalize(template_v1)
        hash_v1 = compute_template_hash(template_v1)
        repo.insert_template(hash_v1, "1.0", "7i", canonical_v1)
        
        template_v2 = {"club": "7i", "version": "2"}
        canonical_v2 = canonicalize(template_v2)
        hash_v2 = compute_template_hash(template_v2)
        repo.insert_template(hash_v2, "1.0", "7i", canonical_v2)
        
        # Insert first sub-session
        subsession_id_v1 = repo.insert_subsession(
            session_id=session_id,
            club="7i",
            kpi_template_hash=hash_v1,
            shot_count=20,
            validity_status="valid",
            a_count=10,
            b_count=8,
            c_count=2,
            a_percentage=50.0,
            avg_carry=150.5
        )
        
        # Capture original row
        original_row = repo.get_subsession(subsession_id_v1)
        
        # Re-analyze with different template
        subsession_id_v2 = repo.insert_subsession(
            session_id=session_id,
            club="7i",
            kpi_template_hash=hash_v2,
            shot_count=20,
            validity_status="valid",
            a_count=15,  # Different results
            b_count=4,
            c_count=1,
            a_percentage=75.0,
            avg_carry=155.0
        )
        
        # Verify original row is unchanged
        current_row = repo.get_subsession(subsession_id_v1)
        assert current_row == original_row
        assert current_row['a_count'] == 10
        assert current_row['a_percentage'] == 50.0
        assert current_row['kpi_template_hash'] == hash_v1
    
    def test_both_subsessions_exist_and_distinguishable(self, tmp_path):
        """
        Query both rows and verify they're distinct by template hash.
        """
        db_path = str(tmp_path / "test.db")
        repo = Repository(db_path)
        
        # Create session
        session_id = repo.insert_session(
            session_date="2026-01-28T17:00:00Z",
            source_file="test.csv"
        )
        
        # Create two templates
        template_v1 = {"club": "7i", "version": "1"}
        canonical_v1 = canonicalize(template_v1)
        hash_v1 = compute_template_hash(template_v1)
        repo.insert_template(hash_v1, "1.0", "7i", canonical_v1)
        
        template_v2 = {"club": "7i", "version": "2"}
        canonical_v2 = canonicalize(template_v2)
        hash_v2 = compute_template_hash(template_v2)
        repo.insert_template(hash_v2, "1.0", "7i", canonical_v2)
        
        # Insert both sub-sessions
        subsession_id_v1 = repo.insert_subsession(
            session_id=session_id,
            club="7i",
            kpi_template_hash=hash_v1,
            shot_count=20,
            validity_status="valid",
            a_count=10,
            b_count=8,
            c_count=2,
            a_percentage=50.0
        )
        
        subsession_id_v2 = repo.insert_subsession(
            session_id=session_id,
            club="7i",
            kpi_template_hash=hash_v2,
            shot_count=20,
            validity_status="valid",
            a_count=12,
            b_count=6,
            c_count=2,
            a_percentage=60.0
        )
        
        # List all sub-sessions for this session
        subsessions = repo.list_subsessions_by_session(session_id)
        
        # Should have exactly 2
        assert len(subsessions) == 2
        
        # Both should be for same club
        assert all(s['club'] == "7i" for s in subsessions)
        
        # But different template hashes
        hashes = {s['kpi_template_hash'] for s in subsessions}
        assert len(hashes) == 2
        assert hash_v1 in hashes
        assert hash_v2 in hashes
        
        # And different subsession_ids
        ids = {s['subsession_id'] for s in subsessions}
        assert len(ids) == 2
        assert subsession_id_v1 in ids
        assert subsession_id_v2 in ids
    
    def test_multiple_template_versions_per_club(self, tmp_path):
        """
        Support >2 template versions for same session/club.
        """
        db_path = str(tmp_path / "test.db")
        repo = Repository(db_path)
        
        # Create session
        session_id = repo.insert_session(
            session_date="2026-01-28T17:00:00Z",
            source_file="test.csv"
        )
        
        # Create 4 different templates
        subsession_ids = []
        template_hashes = []
        
        for version in range(1, 5):
            template = {"club": "7i", "version": str(version)}
            canonical = canonicalize(template)
            hash_val = compute_template_hash(template)
            repo.insert_template(hash_val, "1.0", "7i", canonical)
            template_hashes.append(hash_val)
            
            # Insert sub-session (ensure counts sum to shot_count)
            subsession_id = repo.insert_subsession(
                session_id=session_id,
                club="7i",
                kpi_template_hash=hash_val,
                shot_count=20,
                validity_status="valid",
                a_count=10 + version,
                b_count=8 - version,  # Adjust so sum remains 20
                c_count=2,
                a_percentage=50.0 + version
            )
            subsession_ids.append(subsession_id)
        
        # All 4 should succeed
        assert len(subsession_ids) == 4
        assert len(set(subsession_ids)) == 4  # All unique
        
        # Verify all 4 exist in database
        subsessions = repo.list_subsessions_by_session(session_id)
        assert len(subsessions) == 4
        
        # All same club, all different templates
        assert all(s['club'] == "7i" for s in subsessions)
        found_hashes = {s['kpi_template_hash'] for s in subsessions}
        assert found_hashes == set(template_hashes)
    
    def test_reanalysis_rows_remain_immutable(self, tmp_path):
        """
        Both the original and re-analyzed rows remain immutable.
        """
        db_path = str(tmp_path / "test.db")
        repo = Repository(db_path)
        
        # Create session and templates
        session_id = repo.insert_session(
            session_date="2026-01-28T17:00:00Z",
            source_file="test.csv"
        )
        
        template_v1 = {"club": "7i", "version": "1"}
        canonical_v1 = canonicalize(template_v1)
        hash_v1 = compute_template_hash(template_v1)
        repo.insert_template(hash_v1, "1.0", "7i", canonical_v1)
        
        template_v2 = {"club": "7i", "version": "2"}
        canonical_v2 = canonicalize(template_v2)
        hash_v2 = compute_template_hash(template_v2)
        repo.insert_template(hash_v2, "1.0", "7i", canonical_v2)
        
        # Insert both sub-sessions
        subsession_id_v1 = repo.insert_subsession(
            session_id=session_id,
            club="7i",
            kpi_template_hash=hash_v1,
            shot_count=20,
            validity_status="valid",
            a_count=10,
            b_count=8,
            c_count=2,
            a_percentage=50.0
        )
        
        subsession_id_v2 = repo.insert_subsession(
            session_id=session_id,
            club="7i",
            kpi_template_hash=hash_v2,
            shot_count=20,
            validity_status="valid",
            a_count=12,
            b_count=6,
            c_count=2,
            a_percentage=60.0
        )
        
        # Attempt to update first sub-session - should fail
        conn = None
        try:
            with pytest.raises(sqlite3.IntegrityError) as exc_info:
                conn = sqlite3.connect(db_path)
                conn.execute("PRAGMA foreign_keys = ON")
                conn.execute(
                    "UPDATE club_subsessions SET a_count = ? WHERE subsession_id = ?",
                    (999, subsession_id_v1)
                )
                conn.commit()
            assert "immutable" in str(exc_info.value).lower()
        finally:
            if conn:
                conn.close()
        
        # Attempt to update second sub-session - should also fail
        conn = None
        try:
            with pytest.raises(sqlite3.IntegrityError) as exc_info:
                conn = sqlite3.connect(db_path)
                conn.execute("PRAGMA foreign_keys = ON")
                conn.execute(
                    "UPDATE club_subsessions SET a_count = ? WHERE subsession_id = ?",
                    (999, subsession_id_v2)
                )
                conn.commit()
            assert "immutable" in str(exc_info.value).lower()
        finally:
            if conn:
                conn.close()
        
        # Verify both rows unchanged
        row_v1 = repo.get_subsession(subsession_id_v1)
        row_v2 = repo.get_subsession(subsession_id_v2)
        assert row_v1['a_count'] == 10
        assert row_v2['a_count'] == 12


@pytest.fixture
def tmp_path():
    """Provide a temporary directory for test databases."""
    with tempfile.TemporaryDirectory() as tmpdir:
        yield Path(tmpdir)
