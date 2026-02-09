#!/usr/bin/env python3
"""
Generate Phase 4A.2 aggregate parity golden fixture.

Golden scope:
- Per-club metric parity (count + sum) for mixed-club session fixture
- 7i classification parity (A/B/C) using fixture_a template
- Fixed numeric policy: sums rounded to 6 decimals, serialized as strings
"""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any, Dict, List


REPO_ROOT = Path(__file__).resolve().parents[2]

# Ensure script works when executed directly via absolute path.
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from raid.hashing import compute_template_hash
from raid.ingest import _classify_shot, _parse_rapsodo_csv

DEFAULT_CSV = REPO_ROOT / "tests" / "vectors" / "sessions" / "rapsodo_mlm2pro_mixed_club_sample.csv"
DEFAULT_TEMPLATE = REPO_ROOT / "tests" / "vectors" / "templates" / "fixture_a.json"
DEFAULT_EXPECTED_HASHES = REPO_ROOT / "tests" / "vectors" / "expected" / "template_hashes.json"
DEFAULT_GOLDEN = REPO_ROOT / "tests" / "vectors" / "goldens" / "aggregate_parity_mixed_club_sample.json"
DEFAULT_IOS_COPY = REPO_ROOT / "ios" / "RAID" / "RAIDTests" / "aggregate_parity_mixed_club_sample.json"

ROUND_DECIMALS = 6


def _rounded_sum_string(values: List[float], decimals: int = ROUND_DECIMALS) -> str:
    return f"{round(sum(values), decimals):.{decimals}f}"


def _metric_summary(shots: List[Dict[str, Any]], shot_field: str) -> Dict[str, Any]:
    values = [shot[shot_field] for shot in shots if shot.get(shot_field) is not None]
    return {
        "count": len(values),
        "sum": _rounded_sum_string(values),
    }


def generate_golden() -> Dict[str, Any]:
    template = json.loads(DEFAULT_TEMPLATE.read_text(encoding="utf-8"))
    expected_hashes = json.loads(DEFAULT_EXPECTED_HASHES.read_text(encoding="utf-8"))
    expected_fixture_a_hash = expected_hashes["fixture_a"]

    # Hash from raw dict (never from canonical JSON string)
    computed_hash = compute_template_hash(template)
    if computed_hash != expected_fixture_a_hash:
        raise ValueError(
            "fixture_a hash mismatch while generating aggregate parity golden: "
            f"expected={expected_fixture_a_hash}, computed={computed_hash}"
        )

    shots_by_club = _parse_rapsodo_csv(str(DEFAULT_CSV))

    field_map = {
        "carry": "carry_distance",
        "ball_speed": "ball_speed",
        "smash_factor": "smash_factor",
        "spin_rate": "spin_rate",
        "descent_angle": "descent_angle",
    }

    clubs: Dict[str, Any] = {}
    for club in sorted(shots_by_club.keys()):
        shots = shots_by_club[club]
        club_payload: Dict[str, Any] = {
            "total_shots": len(shots),
            "metrics": {
                metric_name: _metric_summary(shots, shot_field)
                for metric_name, shot_field in field_map.items()
            },
        }

        # Phase 4A.2 classification parity is template-scoped for 7i only.
        if club == "7i":
            a = b = c = 0
            for shot in shots:
                grade = _classify_shot(shot, template)
                if grade == "A":
                    a += 1
                elif grade == "B":
                    b += 1
                else:
                    c += 1

            club_payload["template_hash"] = computed_hash
            club_payload["abc"] = {"a": a, "b": b, "c": c}

        clubs[club] = club_payload

    return {
        "fixture": DEFAULT_CSV.name,
        "template_fixture": DEFAULT_TEMPLATE.name,
        "numeric_policy": {
            "sum_round_decimals": ROUND_DECIMALS,
            "sum_encoding": "fixed_decimal_string",
        },
        "scope": {
            "classified_clubs": ["7i"],
            "aggregate_only_clubs": [club for club in sorted(clubs.keys()) if club != "7i"],
        },
        "clubs": clubs,
    }


def main() -> None:
    golden = generate_golden()

    DEFAULT_GOLDEN.parent.mkdir(parents=True, exist_ok=True)
    DEFAULT_GOLDEN.write_text(
        json.dumps(golden, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    DEFAULT_IOS_COPY.parent.mkdir(parents=True, exist_ok=True)
    DEFAULT_IOS_COPY.write_text(
        json.dumps(golden, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    print(f"Wrote golden: {DEFAULT_GOLDEN}")
    print(f"Wrote iOS bundle copy: {DEFAULT_IOS_COPY}")


if __name__ == "__main__":
    main()
