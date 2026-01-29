"""
Shared pytest fixtures for RAID Phase 0 tests.
"""
import json
from pathlib import Path
from typing import Any, Dict

import pytest


@pytest.fixture(scope="session")
def vectors_dir() -> Path:
    """Path to test vectors directory."""
    return Path(__file__).parent / "vectors"


@pytest.fixture(scope="session")
def templates_dir(vectors_dir: Path) -> Path:
    """Path to template fixtures directory."""
    return vectors_dir / "templates"


@pytest.fixture(scope="session")
def expected_dir(vectors_dir: Path) -> Path:
    """Path to expected outputs directory."""
    return vectors_dir / "expected"


@pytest.fixture(scope="session")
def fixture_a(templates_dir: Path) -> Dict[str, Any]:
    """Load fixture_a.json - minimal template."""
    with open(templates_dir / "fixture_a.json", "r", encoding="utf-8") as f:
        return json.load(f)


@pytest.fixture(scope="session")
def fixture_b(templates_dir: Path) -> Dict[str, Any]:
    """Load fixture_b.json - nested keys ordering test."""
    with open(templates_dir / "fixture_b.json", "r", encoding="utf-8") as f:
        return json.load(f)


@pytest.fixture(scope="session")
def fixture_c(templates_dir: Path) -> Dict[str, Any]:
    """Load fixture_c.json - numeric edge cases."""
    with open(templates_dir / "fixture_c.json", "r", encoding="utf-8") as f:
        return json.load(f)


@pytest.fixture(scope="session")
def golden_hashes(expected_dir: Path) -> Dict[str, str]:
    """Load golden hash values (frozen after Phase A implementation)."""
    with open(expected_dir / "template_hashes.json", "r", encoding="utf-8") as f:
        data = json.load(f)
    # Return only the actual hash values, not metadata fields
    return {k: v for k, v in data.items() if not k.startswith("_")}
