"""
Unit tests for canonical JSON transformation (RTM-11, RTM-12, RTM-13).

These tests validate that the canonicalization process produces deterministic,
cross-platform compatible JSON suitable for content-addressing.
"""
from decimal import Decimal
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


class TestNumericNormalization:
    """RTM-13: Numeric values must be normalized deterministically."""

    def test_strip_trailing_zeros(self):
        """108.920 should normalize to 108.92"""
        input_dict = {"value": Decimal("108.920")}
        canonical = canonicalize(input_dict)
        
        assert "108.92" in canonical
        assert "108.920" not in canonical

    def test_strip_decimal_for_integers(self):
        """1.0 should normalize to 1"""
        input_dict = {"value": Decimal("1.0")}
        canonical = canonicalize(input_dict)
        
        import json
        parsed = json.loads(canonical)
        
        # Should be serialized as integer 1, not 1.0
        assert parsed["value"] == 1
        assert "1.0" not in canonical or '"1.0"' in canonical  # If present, must be in string

    def test_preserve_fractional_parts(self):
        """106.6 should stay 106.6, not become 106.60 or 106"""
        input_dict = {"value": Decimal("106.6")}
        canonical = canonicalize(input_dict)
        
        assert "106.6" in canonical

    def test_small_decimal_normalization(self):
        """0.001 should preserve leading zero and precision"""
        input_dict = {"value": Decimal("0.001")}
        canonical = canonicalize(input_dict)
        
        assert "0.001" in canonical
        # Verify it doesn't start with period (must have leading zero)
        import json
        parsed = json.loads(canonical)
        assert parsed["value"] == 0.001

    def test_negative_zero_normalization(self):
        """-0.0 should normalize to 0"""
        input_dict = {"value": Decimal("-0.0")}
        canonical = canonicalize(input_dict)
        
        import json
        parsed = json.loads(canonical)
        assert parsed["value"] == 0
        assert "-0" not in canonical

    def test_no_scientific_notation(self):
        """Large numbers should not use scientific notation"""
        input_dict = {"value": Decimal("10000")}
        canonical = canonicalize(input_dict)
        
        assert "10000" in canonical
        assert "1e" not in canonical.lower()
        assert "1E" not in canonical

    def test_fixture_c_numeric_edge_cases(self, fixture_c: Dict[str, Any]):
        """
        Fixture C contains: 1.0, 1, 100, 0.001
        All must be normalized correctly.
        """
        canonical = canonicalize(fixture_c)
        
        import json
        parsed = json.loads(canonical)
        
        # Both 1.0 and 1 should normalize to integer 1
        # Find the metric values
        spin_rate_a_min = parsed["metrics"]["spin_rate"]["a_min"]
        spin_rate_b_min = parsed["metrics"]["spin_rate"]["b_min"]
        
        # These are both logically 1, should be same after normalization
        assert spin_rate_a_min == 1
        assert spin_rate_b_min == 1
        
        # 0.001 should be preserved
        descent_a_min = parsed["metrics"]["descent_angle"]["a_min"]
        assert descent_a_min == 0.001
        
        # 100 should be integer
        descent_b_min = parsed["metrics"]["descent_angle"]["b_min"]
        assert descent_b_min == 100

    def test_binary_float_problem_cases(self):
        """
        Test values that expose binary float representation issues.
        
        0.1 and 0.3 are not exactly representable in binary float.
        These must be handled via Decimal to ensure cross-platform determinism.
        """
        test_cases = {
            "point_one": Decimal("0.1"),
            "point_three": Decimal("0.3"),
            "sum": Decimal("0.1") + Decimal("0.2"),  # Should be exactly 0.3
        }
        
        canonical = canonicalize(test_cases)
        
        # Verify canonical form
        assert "0.1" in canonical
        assert "0.3" in canonical
        
        # Verify parse back
        import json
        parsed = json.loads(canonical)
        
        # These must be exact
        assert parsed["point_one"] == 0.1
        assert parsed["point_three"] == 0.3
        assert parsed["sum"] == 0.3

    def test_scientific_notation_never_emitted(self):
        """
        Large and small numbers must never use scientific notation.
        """
        test_cases = {
            "big": Decimal("1000000000"),  # 1e9
            "tiny": Decimal("0.0000000001"),  # 1e-10
        }
        
        canonical = canonicalize(test_cases)
        
        # Should contain full representations (not scientific notation)
        assert "1000000000" in canonical, \
            f"Large number not in fixed-point format: {canonical}"
        assert "0.0000000001" in canonical, \
            f"Small number not in fixed-point format: {canonical}"
        
        # Must not contain scientific notation patterns like '1e9' or '1E-10'
        # Check for 'e' or 'E' followed by digits (scientific notation pattern)
        import re
        sci_pattern = re.compile(r'\d[eE][+-]?\d')
        assert not sci_pattern.search(canonical), \
            f"Scientific notation detected in: {canonical}"
        
        # Verify parse back
        import json
        parsed = json.loads(canonical)
        assert parsed["big"] == 1000000000
        assert parsed["tiny"] == 0.0000000001


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
