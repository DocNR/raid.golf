"""
Tests for derived data boundary (RTM-15, RTM-16).

Phase E verifies that projections are regenerable exports that cannot corrupt
authoritative data through import.
"""
import json
import sqlite3
import tempfile
from pathlib import Path

import pytest

from raid.repository import Repository
from raid.projections import (
    generate_projection_for_subsession,
    serialize_projection,
    import_projection,
    ProjectionImportError,
)


@pytest.fixture
def temp_db():
    """Create a temporary database for testing."""
    with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as f:
        db_path = f.name
    yield db_path
    Path(db_path).unlink(missing_ok=True)


@pytest.fixture
def repo_with_data(temp_db):
    """
    Create a repository with sample data:
    - One session
    - One KPI template
    - One subsession with valid data
    """
    repo = Repository(temp_db)
    
    # Insert session
    session_id = repo.insert_session(
        session_date="2026-01-27T17:30:00Z",
        source_file="test_session.csv",
        device_type="Rapsodo MLM2Pro",
        location="Test Range",
    )
    
    # Insert template
    template_hash = "a" * 64  # Mock hash
    repo.insert_template(
        template_hash=template_hash,
        schema_version="1.0",
        club="7i",
        canonical_json='{"test":"template"}',
    )
    
    # Insert subsession
    subsession_id = repo.insert_subsession(
        session_id=session_id,
        club="7i",
        kpi_template_hash=template_hash,
        shot_count=20,
        validity_status="valid",
        a_count=14,
        b_count=4,
        c_count=2,
        a_percentage=70.0,
        avg_carry=164.5,
        avg_ball_speed=120.3,
        avg_spin=6500.0,
        avg_descent=45.2,
    )
    
    return repo, session_id, subsession_id, template_hash


# ============================================================
# RTM-16: Derived Data Isolation
# ============================================================


def test_no_fk_from_authoritative_to_projections(repo_with_data):
    """
    RTM-16: Verify no foreign keys point from authoritative tables to projections.
    
    Authoritative tables (sessions, kpi_templates, club_subsessions) must not
    depend on the projections table.
    """
    repo, _, _, _ = repo_with_data
    
    conn = sqlite3.connect(repo.db_path)
    cursor = conn.cursor()
    
    # Get all foreign keys from authoritative tables
    authoritative_tables = ["sessions", "kpi_templates", "club_subsessions"]
    
    for table in authoritative_tables:
        cursor.execute(f"PRAGMA foreign_key_list({table})")
        fks = cursor.fetchall()
        
        # Each FK is a tuple: (id, seq, table, from, to, on_update, on_delete, match)
        for fk in fks:
            referenced_table = fk[2]
            assert referenced_table != "projections", (
                f"VIOLATION: {table} has FK pointing to projections table. "
                "Authoritative tables must not depend on derived data."
            )
    
    conn.close()


def test_authoritative_reads_without_projection_rows(repo_with_data):
    """
    RTM-16: Authoritative reads must work even if all projections are deleted.
    
    This proves that projections are truly derived and optional.
    """
    repo, session_id, subsession_id, template_hash = repo_with_data
    
    # First, cache a projection (if table exists)
    try:
        projection_dict = generate_projection_for_subsession(repo, subsession_id)
        projection_json = serialize_projection(projection_dict)
        repo.upsert_projection(subsession_id, projection_json, "2026-01-27T18:00:00Z")
    except Exception:
        # Projections might not be implemented yet or table might not exist
        pass
    
    # Delete ALL projection rows
    conn = sqlite3.connect(repo.db_path)
    conn.execute("DELETE FROM projections")
    conn.commit()
    conn.close()
    
    # Verify authoritative reads still work
    session = repo.get_session(session_id)
    assert session is not None
    assert session["session_id"] == session_id
    assert session["source_file"] == "test_session.csv"
    
    template = repo.get_template(template_hash)
    assert template is not None
    assert template["template_hash"] == template_hash
    
    subsession = repo.get_subsession(subsession_id)
    assert subsession is not None
    assert subsession["subsession_id"] == subsession_id
    assert subsession["shot_count"] == 20
    assert subsession["a_percentage"] == 70.0
    
    # List operations also work
    subsessions = repo.list_subsessions_by_session(session_id)
    assert len(subsessions) == 1
    assert subsessions[0]["subsession_id"] == subsession_id


def test_projection_deletion_does_not_affect_authoritative(repo_with_data):
    """
    RTM-16: Deleting projections must not affect authoritative data integrity.
    """
    repo, session_id, subsession_id, _ = repo_with_data
    
    # Generate and cache a projection
    projection_dict = generate_projection_for_subsession(repo, subsession_id)
    projection_json = serialize_projection(projection_dict)
    repo.upsert_projection(subsession_id, projection_json, "2026-01-27T18:00:00Z")
    
    # Verify projection was stored
    cached = repo.get_projection(subsession_id)
    assert cached is not None
    
    # Delete the projection
    deleted = repo.delete_projection(subsession_id)
    assert deleted is True
    
    # Verify projection is gone
    cached = repo.get_projection(subsession_id)
    assert cached is None
    
    # Verify authoritative data is unchanged
    subsession = repo.get_subsession(subsession_id)
    assert subsession is not None
    assert subsession["shot_count"] == 20
    assert subsession["a_percentage"] == 70.0


# ============================================================
# RTM-15: Projection Regeneration + No Import
# ============================================================


def test_projection_generation(repo_with_data):
    """
    RTM-15: Verify projection can be generated from authoritative data.
    """
    repo, _, subsession_id, _ = repo_with_data
    
    projection = generate_projection_for_subsession(repo, subsession_id)
    
    # Verify projection contains expected fields
    assert "session_date" in projection
    assert "club" in projection
    assert "shot_count" in projection
    assert "validity_status" in projection
    assert "a_count" in projection
    assert "b_count" in projection
    assert "c_count" in projection
    assert "a_percentage" in projection
    assert "kpi_template_hash" in projection
    assert "analyzed_at" in projection
    assert "generated_at" in projection
    
    # Verify values match subsession
    assert projection["club"] == "7i"
    assert projection["shot_count"] == 20
    assert projection["validity_status"] == "valid"
    assert projection["a_count"] == 14
    assert projection["b_count"] == 4
    assert projection["c_count"] == 2
    assert projection["a_percentage"] == 70.0


def test_projection_regeneration_identical(repo_with_data):
    """
    RTM-15: Regenerating a projection must produce identical analytical results.
    
    The only difference should be the generated_at timestamp.
    """
    repo, _, subsession_id, _ = repo_with_data
    
    # Generate first projection
    projection1 = generate_projection_for_subsession(repo, subsession_id)
    
    # Cache it
    json1 = serialize_projection(projection1)
    repo.upsert_projection(subsession_id, json1, projection1["generated_at"])
    
    # Delete the cached projection
    repo.delete_projection(subsession_id)
    
    # Regenerate projection
    projection2 = generate_projection_for_subsession(repo, subsession_id)
    
    # Compare projections (excluding generated_at)
    assert "generated_at" in projection1
    assert "generated_at" in projection2
    
    # Copy projections and remove generated_at for comparison
    proj1_compare = {k: v for k, v in projection1.items() if k != "generated_at"}
    proj2_compare = {k: v for k, v in projection2.items() if k != "generated_at"}
    
    assert proj1_compare == proj2_compare, (
        "Regenerated projection must have identical analytical values"
    )


def test_projection_serialization_deterministic(repo_with_data):
    """
    RTM-15: Projection serialization must be deterministic.
    """
    repo, _, subsession_id, _ = repo_with_data
    
    projection = generate_projection_for_subsession(repo, subsession_id)
    
    # Serialize multiple times
    json1 = serialize_projection(projection)
    json2 = serialize_projection(projection)
    json3 = serialize_projection(projection)
    
    # All serializations must be identical
    assert json1 == json2 == json3
    
    # Verify it's compact JSON (no whitespace)
    assert "\n" not in json1
    assert "  " not in json1  # No double spaces
    
    # Verify it parses back correctly
    parsed = json.loads(json1)
    assert parsed == projection


def test_import_projection_raises_error(repo_with_data):
    """
    RTM-15: Importing a projection must fail with explicit error.
    
    Projections are read-only exports and cannot be imported as authoritative data.
    """
    repo, _, subsession_id, _ = repo_with_data
    
    # Generate a projection
    projection = generate_projection_for_subsession(repo, subsession_id)
    projection_json = serialize_projection(projection)
    
    # Attempt to import should raise ProjectionImportError
    with pytest.raises(ProjectionImportError) as exc_info:
        import_projection(projection_json)
    
    # Verify error message is clear
    error_msg = str(exc_info.value)
    assert "read-only" in error_msg.lower() or "cannot be imported" in error_msg.lower()
    assert "CSV" in error_msg or "csv" in error_msg  # Suggests correct path


def test_import_projection_does_not_modify_authoritative(repo_with_data):
    """
    RTM-15: Failed import attempt must not modify authoritative tables.
    """
    repo, session_id, subsession_id, _ = repo_with_data
    
    # Generate a projection
    projection = generate_projection_for_subsession(repo, subsession_id)
    projection_json = serialize_projection(projection)
    
    # Count rows before import attempt
    conn = sqlite3.connect(repo.db_path)
    cursor = conn.cursor()
    
    cursor.execute("SELECT COUNT(*) FROM sessions")
    session_count_before = cursor.fetchone()[0]
    
    cursor.execute("SELECT COUNT(*) FROM club_subsessions")
    subsession_count_before = cursor.fetchone()[0]
    
    conn.close()
    
    # Attempt import (should fail)
    try:
        import_projection(projection_json)
    except ProjectionImportError:
        pass  # Expected
    
    # Verify counts are unchanged
    conn = sqlite3.connect(repo.db_path)
    cursor = conn.cursor()
    
    cursor.execute("SELECT COUNT(*) FROM sessions")
    session_count_after = cursor.fetchone()[0]
    
    cursor.execute("SELECT COUNT(*) FROM club_subsessions")
    subsession_count_after = cursor.fetchone()[0]
    
    conn.close()
    
    assert session_count_before == session_count_after
    assert subsession_count_before == subsession_count_after
    
    # Verify existing subsession is unchanged
    subsession = repo.get_subsession(subsession_id)
    assert subsession["shot_count"] == 20
    assert subsession["a_percentage"] == 70.0


# ============================================================
# Edge Cases & Integration
# ============================================================


def test_projection_with_null_averages(temp_db):
    """
    Verify projections handle NULL average values correctly.
    """
    repo = Repository(temp_db)
    
    session_id = repo.insert_session(
        session_date="2026-01-27T17:30:00Z",
        source_file="test.csv",
    )
    
    template_hash = "b" * 64
    repo.insert_template(
        template_hash=template_hash,
        schema_version="1.0",
        club="7i",
        canonical_json='{"test":"template"}',
    )
    
    # Subsession with NULL averages
    subsession_id = repo.insert_subsession(
        session_id=session_id,
        club="7i",
        kpi_template_hash=template_hash,
        shot_count=20,
        validity_status="valid",
        a_count=14,
        b_count=4,
        c_count=2,
        a_percentage=70.0,
        avg_carry=None,  # NULL
        avg_ball_speed=None,  # NULL
        avg_spin=None,  # NULL
        avg_descent=None,  # NULL
    )
    
    # Should generate without error
    projection = generate_projection_for_subsession(repo, subsession_id)
    
    assert projection["avg_carry"] is None
    assert projection["avg_ball_speed"] is None
    assert projection["avg_spin"] is None
    assert projection["avg_descent"] is None
    
    # Should serialize without error
    json_str = serialize_projection(projection)
    assert "null" in json_str  # JSON null representation


def test_projection_with_invalid_status(temp_db):
    """
    Verify projections handle invalid status (a_percentage NULL) correctly.
    """
    repo = Repository(temp_db)
    
    session_id = repo.insert_session(
        session_date="2026-01-27T17:30:00Z",
        source_file="test.csv",
    )
    
    template_hash = "c" * 64
    repo.insert_template(
        template_hash=template_hash,
        schema_version="1.0",
        club="7i",
        canonical_json='{"test":"template"}',
    )
    
    # Subsession with invalid status
    subsession_id = repo.insert_subsession(
        session_id=session_id,
        club="7i",
        kpi_template_hash=template_hash,
        shot_count=3,
        validity_status="invalid_insufficient_data",
        a_count=2,
        b_count=1,
        c_count=0,
        a_percentage=None,  # NULL for invalid
    )
    
    projection = generate_projection_for_subsession(repo, subsession_id)
    
    assert projection["validity_status"] == "invalid_insufficient_data"
    assert projection["a_percentage"] is None
    assert projection["shot_count"] == 3
