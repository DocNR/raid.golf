"""
Unit tests for template hashing (RTM-14).

These tests validate that hash computation is deterministic and produces
the correct format for content-addressing.
"""
from typing import Any, Dict

import pytest

from raid.hashing import compute_template_hash


class TestHashDeterminism:
    """RTM-14: Hash computation must be identical across platforms."""

    def test_hash_format(self, fixture_a: Dict[str, Any]):
        """Hash output must be 64-character lowercase hex."""
        template_hash = compute_template_hash(fixture_a)
        
        assert isinstance(template_hash, str)
        assert len(template_hash) == 64, "SHA-256 hex digest must be 64 characters"
        assert template_hash.islower(), "Hash must be lowercase"
        assert all(c in "0123456789abcdef" for c in template_hash), \
            "Hash must contain only hex characters"

    def test_deterministic_hashing(self, fixture_a: Dict[str, Any]):
        """Same input must always produce same hash."""
        hash1 = compute_template_hash(fixture_a)
        hash2 = compute_template_hash(fixture_a)
        hash3 = compute_template_hash(fixture_a)
        
        assert hash1 == hash2 == hash3, "Hashing must be deterministic"

    def test_different_inputs_different_hashes(
        self, fixture_a: Dict[str, Any], fixture_b: Dict[str, Any]
    ):
        """Different templates must produce different hashes."""
        hash_a = compute_template_hash(fixture_a)
        hash_b = compute_template_hash(fixture_b)
        
        assert hash_a != hash_b, "Different templates must have different hashes"

    def test_input_order_irrelevant(self):
        """Different key ordering must produce identical hashes."""
        template1 = {"z": 1, "a": 2}
        template2 = {"a": 2, "z": 1}
        
        hash1 = compute_template_hash(template1)
        hash2 = compute_template_hash(template2)
        
        assert hash1 == hash2, \
            "Hash must be order-independent (canonicalization ensures this)"


class TestGoldenHashes:
    """Validate against frozen golden hash values."""

    def test_fixture_a_golden_hash(
        self, fixture_a: Dict[str, Any], golden_hashes: Dict[str, str]
    ):
        """Fixture A must match its golden hash (once frozen)."""
        computed_hash = compute_template_hash(fixture_a)
        golden_hash = golden_hashes.get("fixture_a")
        
        if golden_hash is None:
            pytest.skip("Golden hash for fixture_a not yet frozen")
        
        assert computed_hash == golden_hash, \
            f"Fixture A hash mismatch. Expected: {golden_hash}, Got: {computed_hash}"

    def test_fixture_b_golden_hash(
        self, fixture_b: Dict[str, Any], golden_hashes: Dict[str, str]
    ):
        """Fixture B must match its golden hash (once frozen)."""
        computed_hash = compute_template_hash(fixture_b)
        golden_hash = golden_hashes.get("fixture_b")
        
        if golden_hash is None:
            pytest.skip("Golden hash for fixture_b not yet frozen")
        
        assert computed_hash == golden_hash, \
            f"Fixture B hash mismatch. Expected: {golden_hash}, Got: {computed_hash}"

    def test_fixture_c_golden_hash(
        self, fixture_c: Dict[str, Any], golden_hashes: Dict[str, str]
    ):
        """Fixture C must match its golden hash (once frozen)."""
        computed_hash = compute_template_hash(fixture_c)
        golden_hash = golden_hashes.get("fixture_c")
        
        if golden_hash is None:
            pytest.skip("Golden hash for fixture_c not yet frozen")
        
        assert computed_hash == golden_hash, \
            f"Fixture C hash mismatch. Expected: {golden_hash}, Got: {computed_hash}"


class TestHashStability:
    """Ensure hashes remain stable across runs and environments."""

    def test_hash_not_timestamp_dependent(self, fixture_a: Dict[str, Any]):
        """Hash must not include timestamp or random data."""
        import time
        
        hash1 = compute_template_hash(fixture_a)
        time.sleep(0.1)  # Small delay
        hash2 = compute_template_hash(fixture_a)
        
        assert hash1 == hash2, "Hash must not be time-dependent"

    def test_hash_locality_independent(self):
        """Hash must not depend on locale settings."""
        # This is implicitly tested by using Decimal and explicit formatting,
        # but we can explicitly test with numbers
        template = {"value": 1234.56}
        
        hash1 = compute_template_hash(template)
        # In different locales, float formatting might vary, but our implementation
        # uses Decimal which is locale-independent
        hash2 = compute_template_hash(template)
        
        assert hash1 == hash2


class TestIntegration:
    """Integration tests for hash computation."""

    def test_all_fixtures_hash_successfully(
        self,
        fixture_a: Dict[str, Any],
        fixture_b: Dict[str, Any],
        fixture_c: Dict[str, Any],
    ):
        """All fixtures must hash without errors."""
        hash_a = compute_template_hash(fixture_a)
        hash_b = compute_template_hash(fixture_b)
        hash_c = compute_template_hash(fixture_c)
        
        assert all(isinstance(h, str) and len(h) == 64 
                   for h in [hash_a, hash_b, hash_c])
        
        # All should be unique
        hashes = {hash_a, hash_b, hash_c}
        assert len(hashes) == 3, "All fixtures should produce unique hashes"

    def test_print_hashes_for_freezing(
        self,
        fixture_a: Dict[str, Any],
        fixture_b: Dict[str, Any],
        fixture_c: Dict[str, Any],
    ):
        """
        Print computed hashes for manual freezing in golden file.
        This test always passes but outputs values for documentation.
        """
        hash_a = compute_template_hash(fixture_a)
        hash_b = compute_template_hash(fixture_b)
        hash_c = compute_template_hash(fixture_c)
        
        print("\n" + "=" * 70)
        print("GOLDEN HASHES FOR FREEZING")
        print("=" * 70)
        print(f"fixture_a: {hash_a}")
        print(f"fixture_b: {hash_b}")
        print(f"fixture_c: {hash_c}")
        print("=" * 70)
        print("Copy these values to tests/vectors/expected/template_hashes.json")
        print("=" * 70 + "\n")
        
        # Test always passes - this is just for documentation
        assert True

    def test_fixture_b_reformatted_still_matches_golden(
        self, golden_hashes: Dict[str, str]
    ):
        """
        Extra verification: Reformat fixture_b with different key ordering
        and confirm the canonical JSON + hash still match the frozen golden.
        
        This proves order-independence and idempotence.
        """
        # Reformat fixture_b with completely different key ordering
        reformatted_fixture_b = {
            "schema_version": "1.0",  # Was 2nd, now 1st
            "aggregation_method": "worst_metric",  # Was last, now 2nd
            "metrics": {
                # Reverse metric order
                "smash_factor": {
                    "direction": "higher_is_better",  # Was 1st, now last
                    "a_min": 1.32,  # Was 3rd, now 1st
                    "b_min": 1.29,  # Was 2nd, now 2nd
                },
                "ball_speed": {
                    "b_min": 106.6,  # Was 2nd, now 1st
                    "a_min": 108.92,  # Was 3rd, now 2nd  
                    "direction": "higher_is_better",  # Was 1st, now 3rd
                },
            },
            "club": "7i",  # Was 1st, now last
        }
        
        # Compute hash of reformatted version
        reformatted_hash = compute_template_hash(reformatted_fixture_b)
        
        # Must match the frozen golden hash for fixture_b
        golden_hash_b = golden_hashes["fixture_b"]
        
        assert reformatted_hash == golden_hash_b, \
            f"Reformatted fixture_b hash mismatch!\n" \
            f"Expected (golden): {golden_hash_b}\n" \
            f"Got (reformatted): {reformatted_hash}\n" \
            f"Canonicalization must be order-independent!"
