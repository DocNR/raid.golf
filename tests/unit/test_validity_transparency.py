"""
Unit tests for validity computation and transparency guarantees (RTM-07 to RTM-10).
"""
import sqlite3

import pytest

from raid.canonical import canonicalize
from raid.hashing import compute_template_hash
from raid.repository import Repository
from raid.validity import compute_a_percentage, compute_validity_status


def _setup_repo(tmp_path):
    db_path = str(tmp_path / "test.db")
    repo = Repository(db_path)

    session_id = repo.insert_session(
        session_date="2026-01-29T12:00:00Z",
        source_file="test.csv",
        device_type="Rapsodo",
        location="Range A",
    )

    def add_template(suffix: str = ""):
        template_dict = {"club": "7i", "schema_version": "1.0", "suffix": suffix}
        canonical_json = canonicalize(template_dict)
        template_hash = compute_template_hash(template_dict)
        repo.insert_template(
            template_hash=template_hash,
            schema_version="1.0",
            club="7i",
            canonical_json=canonical_json,
        )
        return template_hash

    return repo, session_id, add_template


def _insert_subsession(
    repo,
    session_id,
    template_hash,
    shot_count,
    validity_status,
    a_count,
    b_count,
    c_count,
    a_percentage,
    club="7i",
):
    return repo.insert_subsession(
        session_id=session_id,
        club=club,
        kpi_template_hash=template_hash,
        shot_count=shot_count,
        validity_status=validity_status,
        a_count=a_count,
        b_count=b_count,
        c_count=c_count,
        a_percentage=a_percentage,
    )


class TestValidityThresholds:
    """RTM-07: Validity thresholds at boundary values."""

    @pytest.mark.parametrize(
        "shot_count,expected",
        [
            (4, "invalid_insufficient_data"),
            (5, "valid_low_sample_warning"),
            (14, "valid_low_sample_warning"),
            (15, "valid"),
        ],
    )
    def test_validity_status_boundaries(self, shot_count, expected):
        assert compute_validity_status(shot_count) == expected


class TestAPercentageNullWhenInvalid:
    """RTM-08: A% must be NULL when invalid."""

    def test_a_percentage_null_when_invalid(self, tmp_path):
        repo, session_id, add_template = _setup_repo(tmp_path)
        template_hash = add_template("invalid")

        shot_count = 4
        a_count, b_count, c_count = 1, 1, 2
        validity_status = compute_validity_status(shot_count)
        a_percentage = compute_a_percentage(a_count, shot_count, validity_status)

        assert validity_status == "invalid_insufficient_data"
        assert a_percentage is None

        subsession_id = _insert_subsession(
            repo,
            session_id,
            template_hash,
            shot_count=shot_count,
            validity_status=validity_status,
            a_count=a_count,
            b_count=b_count,
            c_count=c_count,
            a_percentage=a_percentage,
        )

        stored = repo.get_subsession(subsession_id)
        assert stored is not None
        assert stored["a_percentage"] is None
        assert stored["validity_status"] == "invalid_insufficient_data"

    def test_invalid_with_non_null_a_percentage_rejected(self, tmp_path):
        repo, session_id, add_template = _setup_repo(tmp_path)
        template_hash = add_template("invalid")

        with pytest.raises(sqlite3.IntegrityError):
            _insert_subsession(
                repo,
                session_id,
                template_hash,
                shot_count=4,
                validity_status="invalid_insufficient_data",
                a_count=1,
                b_count=1,
                c_count=2,
                a_percentage=25.0,
            )


class TestLowAndInvalidStored:
    """RTM-09: Low/invalid sub-sessions are stored and queryable."""

    def test_low_and_invalid_persisted(self, tmp_path):
        repo, session_id, add_template = _setup_repo(tmp_path)
        invalid_hash = add_template("invalid")
        warning_hash = add_template("warning")

        invalid_id = _insert_subsession(
            repo,
            session_id,
            invalid_hash,
            shot_count=4,
            validity_status="invalid_insufficient_data",
            a_count=1,
            b_count=1,
            c_count=2,
            a_percentage=None,
        )

        warning_id = _insert_subsession(
            repo,
            session_id,
            warning_hash,
            shot_count=5,
            validity_status="valid_low_sample_warning",
            a_count=2,
            b_count=2,
            c_count=1,
            a_percentage=40.0,
        )

        invalid_row = repo.get_subsession(invalid_id)
        warning_row = repo.get_subsession(warning_id)

        assert invalid_row is not None
        assert warning_row is not None
        assert invalid_row["validity_status"] == "invalid_insufficient_data"
        assert warning_row["validity_status"] == "valid_low_sample_warning"

        rows = repo.list_subsessions_by_session(session_id)
        statuses = {row["validity_status"] for row in rows}
        assert statuses == {"invalid_insufficient_data", "valid_low_sample_warning"}


class TestNoSilentFiltering:
    """RTM-10: Filtering must be explicit and visible."""

    def test_list_subsessions_by_session_includes_validity_status(self, tmp_path):
        repo, session_id, add_template = _setup_repo(tmp_path)
        template_hash = add_template("valid")

        _insert_subsession(
            repo,
            session_id,
            template_hash,
            shot_count=15,
            validity_status="valid",
            a_count=5,
            b_count=5,
            c_count=5,
            a_percentage=33.3,
        )

        rows = repo.list_subsessions_by_session(session_id)
        assert rows
        assert "validity_status" in rows[0]

    def test_list_subsessions_by_club_explicit_filtering(self, tmp_path):
        repo, session_id, add_template = _setup_repo(tmp_path)
        invalid_hash = add_template("invalid")
        warning_hash = add_template("warning")
        valid_hash = add_template("valid")

        _insert_subsession(
            repo,
            session_id,
            invalid_hash,
            shot_count=4,
            validity_status="invalid_insufficient_data",
            a_count=1,
            b_count=1,
            c_count=2,
            a_percentage=None,
        )
        _insert_subsession(
            repo,
            session_id,
            warning_hash,
            shot_count=8,
            validity_status="valid_low_sample_warning",
            a_count=3,
            b_count=3,
            c_count=2,
            a_percentage=37.5,
        )
        _insert_subsession(
            repo,
            session_id,
            valid_hash,
            shot_count=15,
            validity_status="valid",
            a_count=6,
            b_count=6,
            c_count=3,
            a_percentage=40.0,
        )

        all_rows = repo.list_subsessions_by_club("7i")
        all_statuses = {row["validity_status"] for row in all_rows}
        assert all_statuses == {
            "invalid_insufficient_data",
            "valid_low_sample_warning",
            "valid",
        }

        warning_and_valid = repo.list_subsessions_by_club(
            "7i",
            min_validity="valid_low_sample_warning",
        )
        warning_statuses = {row["validity_status"] for row in warning_and_valid}
        assert warning_statuses == {"valid_low_sample_warning", "valid"}

        valid_only = repo.list_subsessions_by_club("7i", min_validity="valid")
        valid_statuses = {row["validity_status"] for row in valid_only}
        assert valid_statuses == {"valid"}