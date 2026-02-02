"""
Unit tests for canonical JSON transformation (RTM-11, RTM-12, RTM-13).

These tests validate that the canonicalization process produces deterministic,
cross-platform compatible JSON suitable for content-addressing.

Version: 2.0 (Kernel v2.0 - RFC 8785 JCS)
"""
import json
from decimal import Decimal
from pathlib import Path
from typing import Any, Dict

import pytest

from raid.canonical import canonicalize


class TestKeyOrdering:
    """RTM-11: Canonical JSON must sort keys at all nesting levels."""

    def test_top_level_key_ordering(self):
        """Keys at top level must be sorted alphabetically."""
        input_dict = {"z": 1, "a": 2, "m": 3}
        canonical = canonicalize(input_dict)
        
        # Parse back to verify ordering
        import json
        parsed = json.loads(canonical)
        keys = list(parsed.keys())
        
        assert keys == ["a", "m", "z"], "Top-level keys must be alphabetically sorted"

    def test_nested_key_ordering(self):
        """Keys at all nesting levels must be sorted alphabetically."""
        input_dict = {
            "z": {"y": 1, "x": 2},
            "a": {"c": 3, "b": 4}
        }
        canonical = canonicalize(input_dict)
        
        import json
        parsed = json.loads(canonical)
        
        # Check top level
        assert list(parsed.keys()) == ["a", "z"]
        
        # Check nested levels
        assert list(parsed["a"].keys()) == ["b", "c"]
        assert list(parsed["z"].keys()) == ["x", "y"]

    def test_fixture_b_key_ordering(self, fixture_b: Dict[str, Any]):
        """
        Fixture B has intentionally unsorted keys to test ordering.
        Original has: club, schema_version, metrics (unsorted)
        Canonical must have all keys sorted at every level.
        """
        canonical = canonicalize(fixture_b)
        
        import json
        parsed = json.loads(canonical)
        
        # Top level should be sorted
        top_keys = list(parsed.keys())
        assert top_keys == sorted(top_keys), "Top-level keys must be sorted"
        
        # Metrics should be sorted
        metrics_keys = list(parsed["metrics"].keys())
        assert metrics_keys == sorted(metrics_keys), "Metrics keys must be sorted"
        
        # Individual metric keys should be sorted
        for metric_name, metric_def in parsed["metrics"].items():
            metric_keys = list(metric_def.keys())
            assert metric_keys == sorted(metric_keys), \
                f"Keys in {metric_name} must be sorted"


class TestWhitespaceElimination:
    """RTM-12: Canonical JSON must be compact and UTF-8 without BOM."""

    def test_no_whitespace_in_output(self):
        """Canonical JSON must have no spaces, newlines, or indentation."""
        input_dict = {"a": 1, "b": 2}
        canonical = canonicalize(input_dict)
        
        # Check for no spaces (except inside string values)
        assert " " not in canonical, "Canonical JSON must not contain spaces"
        assert "\n" not in canonical, "Canonical JSON must not contain newlines"
        assert "\t" not in canonical, "Canonical JSON must not contain tabs"

    def test_compact_format(self):
        """Output should be compact with separators=',' and ':'."""
        input_dict = {"key": "value", "number": 42}
        canonical = canonicalize(input_dict)
        
        # Should use compact separators
        assert '","' in canonical or '":' in canonical
        assert '" :' not in canonical  # No space after colon
        assert ', ' not in canonical   # No space after comma

    def test_utf8_encoding(self):
        """Canonical output must be UTF-8 encodable without BOM."""
        input_dict = {"unicode": "Test™ 中文"}
        canonical = canonicalize(input_dict)
        
        # Should encode to UTF-8 without BOM
        encoded = canonical.encode('utf-8')
        assert not encoded.startswith(b'\xef\xbb\xbf'), "Must not have UTF-8 BOM"
        
        # Should decode back correctly
        assert canonical == encoded.decode('utf-8')


class TestJCSCompliance:
    """
    RFC 8785 JCS compliance tests (Kernel v2.0).
    
    These tests validate that canonicalize() produces RFC 8785-compliant
    canonical JSON by comparing against golden test vectors.
    """

    @pytest.fixture
    def jcs_vectors(self):
        """Load JCS test vectors from tests/vectors/jcs_vectors.json."""
        vectors_path = Path(__file__).parent.parent / "vectors" / "jcs_vectors.json"
        with open(vectors_path, 'r') as f:
            data = json.load(f)
        return data['vectors']

    @pytest.mark.parametrize("vector_name", [
        "simple_key_ordering",
        "nested_key_ordering",
        "whitespace_elimination",
        "integer_vs_decimal",
        "zero_normalization",
        "negative_numbers",
        "unicode_strings",
        "array_order_preserved",
        "nested_arrays_and_objects",
        "empty_structures",
        "boolean_and_null",
        "decimal_precision",
    ])
    def test_jcs_vector_compliance(self, jcs_vectors, vector_name):
        """
        Test that canonicalize() produces RFC 8785 JCS canonical output.
        
        Each test vector includes:
        - input: JSON object
        - canonical: Expected RFC 8785 canonical string
        - sha256: Expected hash (validated in test_hashing.py)
        """
        # Find the vector
        vector = next(v for v in jcs_vectors if v['name'] == vector_name)
        
        # Canonicalize
        actual_canonical = canonicalize(vector['input'])
        expected_canonical = vector['canonical']
        
        # Assert exact match
        assert actual_canonical == expected_canonical, \
            f"JCS vector '{vector_name}' failed:\n" \
            f"Expected: {expected_canonical}\n" \
            f"Actual:   {actual_canonical}"

    def test_non_json_native_types_rejected(self):
        """
        Non-JSON-native types (e.g., Decimal) must raise TypeError.
        
        Templates must use JSON-native types (int, float, str, bool, null, list, dict).
        The canonicaljson library enforces this constraint.
        """
        from decimal import Decimal
        
        with pytest.raises(TypeError, match="Decimal.*not JSON serializable"):
            canonicalize({"value": Decimal("1.0")})

    def test_fixture_c_numeric_edge_cases(self, fixture_c: Dict[str, Any]):
        """
        Fixture C contains: 1.0, 1, 100, 0.001
        All must be normalized correctly per RFC 8785.
        """
        canonical = canonicalize(fixture_c)
        parsed = json.loads(canonical)
        
        # Both 1.0 and 1 should normalize to integer 1
        spin_rate_a_min = parsed["metrics"]["spin_rate"]["a_min"]
        spin_rate_b_min = parsed["metrics"]["spin_rate"]["b_min"]
        
        assert spin_rate_a_min == 1
        assert spin_rate_b_min == 1
        
        # 0.001 should be preserved
        descent_a_min = parsed["metrics"]["descent_angle"]["a_min"]
        assert descent_a_min == 0.001
        
        # 100 should be integer
        descent_b_min = parsed["metrics"]["descent_angle"]["b_min"]
        assert descent_b_min == 100


class TestQuotingRegression:
    """Regression tests to ensure strings are quoted and numbers are not."""

    def test_string_values_stay_quoted(self):
        """
        Verify that string values like "7i" and "1.0" are quoted,
        while numeric values are unquoted.
        
        This is a regression test for the NumericToken wrapper approach.
        """
        template = {
            "club": "7i",  # String - must be quoted
            "schema_version": "1.0",  # String - must be quoted  
            "metrics": {
                "ball_speed": {
                    "a_min": 108.92,  # Number - must NOT be quoted
                    "b_min": 106.6,   # Number - must NOT be quoted
                }
            }
        }
        
        canonical = canonicalize(template)
        
        # String values must be quoted
        assert '"club":"7i"' in canonical, \
            "String value '7i' must be quoted"
        assert '"schema_version":"1.0"' in canonical, \
            "String value '1.0' must be quoted"
        
        # Numeric values must NOT be quoted
        assert '"a_min":108.92' in canonical, \
            "Numeric value 108.92 must NOT be quoted"
        assert '"b_min":106.6' in canonical, \
            "Numeric value 106.6 must NOT be quoted"
        
        # Verify it's valid JSON
        import json
        parsed = json.loads(canonical)
        assert parsed["club"] == "7i"
        assert parsed["schema_version"] == "1.0"
        assert parsed["metrics"]["ball_speed"]["a_min"] == 108.92
        assert parsed["metrics"]["ball_speed"]["b_min"] == 106.6


class TestIntegration:
    """Integration tests combining all canonicalization rules."""

    def test_fixture_a_canonicalization(self, fixture_a: Dict[str, Any]):
        """Fixture A should canonicalize without errors."""
        canonical = canonicalize(fixture_a)
        
        assert isinstance(canonical, str)
        assert len(canonical) > 0
        
        # Should be valid JSON
        import json
        parsed = json.loads(canonical)
        assert parsed is not None

    def test_idempotence(self, fixture_a: Dict[str, Any]):
        """Canonicalizing canonical form should produce identical output."""
        canonical1 = canonicalize(fixture_a)
        
        import json
        parsed = json.loads(canonical1)
        canonical2 = canonicalize(parsed)
        
        assert canonical1 == canonical2, "Canonicalization must be idempotent"

    def test_different_input_order_same_output(self):
        """Different key orderings should produce identical canonical output."""
        dict1 = {"z": 1, "a": 2}
        dict2 = {"a": 2, "z": 1}
        
        canonical1 = canonicalize(dict1)
        canonical2 = canonicalize(dict2)
        
        assert canonical1 == canonical2
