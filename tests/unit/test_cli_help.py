"""
Test CLI help rendering (regression test for argparse % escaping).

This test prevents the argparse ValueError crash caused by unescaped
percent signs in help strings.
"""
import subprocess
import sys


def test_cli_main_help():
    """Test that main --help renders without crashing."""
    result = subprocess.run(
        [sys.executable, "-m", "raid.cli", "--help"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"--help failed: {result.stderr}"
    assert "RAID Golf" in result.stdout


def test_cli_trend_help():
    """Test that trend --help renders without crashing (contains A%)."""
    result = subprocess.run(
        [sys.executable, "-m", "raid.cli", "trend", "--help"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"trend --help failed: {result.stderr}"
    assert "trend" in result.stdout.lower()


def test_cli_templates_help():
    """Test that templates --help renders without crashing."""
    result = subprocess.run(
        [sys.executable, "-m", "raid.cli", "templates", "--help"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"templates --help failed: {result.stderr}"
    assert "templates" in result.stdout.lower()


def test_cli_ingest_help():
    """Test that ingest --help renders without crashing."""
    result = subprocess.run(
        [sys.executable, "-m", "raid.cli", "ingest", "--help"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"ingest --help failed: {result.stderr}"
    assert "ingest" in result.stdout.lower()


def test_cli_sessions_help():
    """Test that sessions --help renders without crashing."""
    result = subprocess.run(
        [sys.executable, "-m", "raid.cli", "sessions", "--help"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"sessions --help failed: {result.stderr}"
    assert "sessions" in result.stdout.lower() or "session" in result.stdout.lower()


def test_cli_show_help():
    """Test that show --help renders without crashing."""
    result = subprocess.run(
        [sys.executable, "-m", "raid.cli", "show", "--help"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"show --help failed: {result.stderr}"
    assert "show" in result.stdout.lower() or "session" in result.stdout.lower()


def test_cli_export_help():
    """Test that export --help renders without crashing."""
    result = subprocess.run(
        [sys.executable, "-m", "raid.cli", "export", "--help"],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"export --help failed: {result.stderr}"
    assert "export" in result.stdout.lower()
