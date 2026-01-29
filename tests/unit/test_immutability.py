"""
Unit tests for immutability enforcement (RTM-01 through RTM-04).

These tests validate that schema-level triggers prevent mutation
of authoritative entities after creation.
"""
import json
import sqlite3
import tempfile
from pathlib import Path
from unittest.mock import patch

import pytest

from raid.canonical import canonicalize
from raid.hashing import compute_template_hash
from raid.repository import Repository


class TestSessionImmutability:
    """RTM-01: Sessions must be immutable after creation."""
    
    def test_session_update_rejected(self, tmp_path):
        """Attempt to update any field on a session must be rejected."""
        db_path = str(tmp_path / "test.db")
        repo = Repository(db_path)
        
        # Create a session
        session_id = repo.insert_session(
            session_date="2026-01-28T17:00:00Z",
            source_file="test.csv",
            device_type="Rapsodo",
            location="Range A"
        )
        
        # Verify it was created
        session = repo.get_session(session_id)
        assert session is not None
        assert session['source_file'] == "test.csv"
        
        # Attempt to update source_file - should fail with trigger error
        with pytest.raises(sqlite3.IntegrityError) as exc_info:
            conn = sqlite3.connect(db_path)
            conn.execute("PRAGMA foreign_keys = ON")
            conn.execute(
                "UPDATE sessions SET source_file = ? WHERE session_id = ?",
                ("modified.csv", session_id)
            )
            conn.commit()
            conn.close()
        
        assert "immutable" in str(exc_info.value).lower()
        
        # Verify original value unchanged
        session_after = repo.get_session(session_id)
        assert session_after['source_file'] == "test.csv"
    
    def test_session_update_all_fields_rejected(self, tmp_path):
        """Test that ALL fields are immutable, not just some."""
        db_path = str(tmp_path / "test.db")
        repo = Repository(db_path)
        
        session_id = repo.insert_session(
            session_date="2026-01-28T17:00:00Z",
            source_file="test.csv"
        )
        
        fields_to_test = [
            ("session_date", "2026-01-29T17:00:00Z"),
            ("device_type", "TrackMan"),
            ("location", "Indoor"),
        ]
        
        for field_name, new_value in fields_to_test:
            conn = None
            try:
                with pytest.raises(sqlite3.IntegrityError):
                    conn = sqlite3.connect(db_path)
                    conn.execute("PRAGMA foreign_keys = ON")
                    conn.execute(
                        f"UPDATE sessions SET {field_name} = ? WHERE session_id = ?",
                        (new_value, session_id)
                    )
                    conn.commit()
            finally:
                if conn:
                    conn.close()


class TestSubSessionImmutability:
    """RTM-02: Club sub-sessions must be immutable after creation."""
    
    def test_subsession_update_rejected(self, tmp_path):
        """Attempt to update any field on a sub-session must be rejected."""
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
        
        # Create sub-session
        subsession_id = repo.insert_subsession(
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
        
        # Attempt to update a_count - should fail
        with pytest.raises(sqlite3.IntegrityError) as exc_info:
            conn = sqlite3.connect(db_path)
            conn.execute("PRAGMA foreign_keys = ON")
            conn.execute(
                "UPDATE club_subsessions SET a_count = ? WHERE subsession_id = ?",
                (15, subsession_id)
            )
            conn.commit()
            conn.close()
        
        assert "immutable" in str(exc_info.value).lower()
        
        # Verify original value unchanged
        subsession = repo.get_subsession(subsession_id)
        assert subsession['a_count'] == 10
    
    def test_subsession_template_swap_rejected(self, tmp_path):
        """Attempting to change kpi_template_hash must fail."""
        db_path = str(tmp_path / "test.db")
        repo = Repository(db_path)
        
        session_id = repo.insert_session(
            session_date="2026-01-28T17:00:00Z",
            source_file="test.csv"
        )
        
        # Create two templates
        template1 = {"club": "7i", "version": "1"}
        canonical1 = canonicalize(template1)
        hash1 = compute_template_hash(template1)
        repo.insert_template(hash1, "1.0", "7i", canonical1)
        
        template2 = {"club": "7i", "version": "2"}
        canonical2 = canonicalize(template2)
        hash2 = compute_template_hash(template2)
        repo.insert_template(hash2, "1.0", "7i", canonical2)
        
        # Create sub-session with template1
        subsession_id = repo.insert_subsession(
            session_id=session_id,
            club="7i",
            kpi_template_hash=hash1,
            shot_count=20,
            validity_status="valid",
            a_count=10,
            b_count=8,
            c_count=2,
            a_percentage=50.0
        )
        
        # Attempt to swap to template2
        with pytest.raises(sqlite3.IntegrityError):
            conn = sqlite3.connect(db_path)
            conn.execute("PRAGMA foreign_keys = ON")
            conn.execute(
                "UPDATE club_subsessions SET kpi_template_hash = ? WHERE subsession_id = ?",
                (hash2, subsession_id)
            )
            conn.commit()
            conn.close()
        
        # Verify original template reference unchanged
        subsession = repo.get_subsession(subsession_id)
        assert subsession['kpi_template_hash'] == hash1


class TestTemplateImmutability:
    """RTM-03: KPI templates must be immutable forever."""
    
    def test_template_update_rejected(self, tmp_path):
        """Attempt to update any field on a template must be rejected."""
        db_path = str(tmp_path / "test.db")
        repo = Repository(db_path)
        
        template_dict = {"club": "7i", "schema_version": "1.0"}
        canonical_json = canonicalize(template_dict)
        template_hash = compute_template_hash(template_dict)
        
        repo.insert_template(
            template_hash=template_hash,
            schema_version="1.0",
            club="7i",
            canonical_json=canonical_json
        )
        
        # Attempt to update canonical_json - should fail
        with pytest.raises(sqlite3.IntegrityError) as exc_info:
            conn = sqlite3.connect(db_path)
            conn.execute("PRAGMA foreign_keys = ON")
            conn.execute(
                "UPDATE kpi_templates SET canonical_json = ? WHERE template_hash = ?",
                ('{"modified": true}', template_hash)
            )
            conn.commit()
            conn.close()
        
        assert "immutable" in str(exc_info.value).lower()
        
        # Verify original value unchanged
        template = repo.get_template(template_hash)
        assert template['canonical_json'] == canonical_json
    
    def test_template_all_fields_rejected(self, tmp_path):
        """Test that ALL template fields are immutable."""
        db_path = str(tmp_path / "test.db")
        repo = Repository(db_path)
        
        template_dict = {"club": "7i", "schema_version": "1.0"}
        canonical_json = canonicalize(template_dict)
        template_hash = compute_template_hash(template_dict)
        
        repo.insert_template(
            template_hash=template_hash,
            schema_version="1.0",
            club="7i",
            canonical_json=canonical_json
        )
        
        fields_to_test = [
            ("schema_version", "2.0"),
            ("club", "PW"),
            ("canonical_json", '{"modified":true}'),
        ]
        
        for field_name, new_value in fields_to_test:
            conn = None
            try:
                with pytest.raises(sqlite3.IntegrityError):
                    conn = sqlite3.connect(db_path)
                    conn.execute("PRAGMA foreign_keys = ON")
                    conn.execute(
                        f"UPDATE kpi_templates SET {field_name} = ? WHERE template_hash = ?",
                        (new_value, template_hash)
                    )
                    conn.commit()
            finally:
                if conn:
                    conn.close()


class TestHashNotRecomputedOnRead:
    """RTM-04: Template hashes must NOT be recomputed on read path."""
    
    def test_get_template_does_not_call_canonicalize(self, tmp_path):
        """
        Verify that get_template() does not call canonicalize().
        
        Uses monkeypatch/spy to assert canonicalize is never called
        during normal repository read operations.
        """
        db_path = str(tmp_path / "test.db")
        repo = Repository(db_path)
        
        # Insert a template
        template_dict = {"club": "7i", "schema_version": "1.0"}
        canonical_json = canonicalize(template_dict)
        template_hash = compute_template_hash(template_dict)
        
        repo.insert_template(
            template_hash=template_hash,
            schema_version="1.0",
            club="7i",
            canonical_json=canonical_json
        )
        
        # Patch canonicalize to detect if it's called
        with patch('raid.canonical.canonicalize') as mock_canonicalize:
            # Perform read operation
            retrieved = repo.get_template(template_hash)
            
            # Assert canonicalize was NOT called
            mock_canonicalize.assert_not_called()
        
        # Verify we got the data
        assert retrieved is not None
        assert retrieved['template_hash'] == template_hash
    
    def test_get_template_does_not_call_hash_function(self, tmp_path):
        """
        Verify that get_template() does not call compute_template_hash().
        
        The stored hash is authoritative; no recomputation on read.
        """
        db_path = str(tmp_path / "test.db")
        repo = Repository(db_path)
        
        # Insert a template
        template_dict = {"club": "7i", "schema_version": "1.0"}
        canonical_json = canonicalize(template_dict)
        template_hash = compute_template_hash(template_dict)
        
        repo.insert_template(
            template_hash=template_hash,
            schema_version="1.0",
            club="7i",
            canonical_json=canonical_json
        )
        
        # Patch compute_template_hash to detect if it's called
        with patch('raid.hashing.compute_template_hash') as mock_hash:
            # Perform read operation
            retrieved = repo.get_template(template_hash)
            
            # Assert hash function was NOT called
            mock_hash.assert_not_called()
        
        # Verify we got the data
        assert retrieved is not None
        assert retrieved['canonical_json'] == canonical_json
    
    def test_list_templates_does_not_rehash(self, tmp_path):
        """
        Verify that list_templates_by_club() also avoids rehashing.
        """
        db_path = str(tmp_path / "test.db")
        repo = Repository(db_path)
        
        # Insert multiple templates
        for i in range(3):
            template_dict = {"club": "7i", "version": str(i)}
            canonical_json = canonicalize(template_dict)
            template_hash = compute_template_hash(template_dict)
            
            repo.insert_template(
                template_hash=template_hash,
                schema_version="1.0",
                club="7i",
                canonical_json=canonical_json
            )
        
        # Patch both functions
        with patch('raid.canonical.canonicalize') as mock_canon, \
             patch('raid.hashing.compute_template_hash') as mock_hash:
            # List templates
            templates = repo.list_templates_by_club("7i")
            
            # Assert neither was called
            mock_canon.assert_not_called()
            mock_hash.assert_not_called()
        
        # Verify we got the data
        assert len(templates) == 3


@pytest.fixture
def tmp_path():
    """Provide a temporary directory for test databases."""
    with tempfile.TemporaryDirectory() as tmpdir:
        yield Path(tmpdir)
