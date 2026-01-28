import unittest
from pathlib import Path

from tools.kpi.generate_kpis import compute_thresholds, iter_valid_rows, load_kpis


class TestKpiGenerator(unittest.TestCase):
    def setUp(self) -> None:
        self.repo_root = Path(__file__).resolve().parents[1]
        self.kpis_path = self.repo_root / "tools" / "kpis.json"
        self.sample_csv = self.repo_root / "data" / "session_logs" / "sample_session_log.csv"

    def test_v2_thresholds_unchanged(self) -> None:
        kpis = load_kpis(self.kpis_path)
        club = kpis["clubs"]["7i"]
        self.assertEqual(club["kpi_version"], "v2.0")
        self.assertEqual(club["a"], {
            "smash_min": 1.25,
            "ball_speed_min": 104.0,
            "spin_min": 4300.0,
            "descent_min": 45.0,
        })
        self.assertEqual(club["b"], {
            "smash_min": 1.22,
            "smash_max": 1.24,
            "spin_min": 4200.0,
            "descent_min": 44.0,
        })
        self.assertEqual(club["c"], {
            "smash_max": 1.22,
            "spin_max": 4100.0,
            "descent_max": 43.0,
        })

    def test_append_version_metadata(self) -> None:
        kpis = load_kpis(self.kpis_path)
        club = kpis["clubs"]["7i"]
        versions = club.get("versions", {})
        self.assertIn("v2.0", versions)
        self.assertEqual(versions["v2.0"]["method"], "manual_locked")
        self.assertIn("thresholds", versions["v2.0"])

        lines = self.sample_csv.read_text(encoding="utf-8").splitlines()
        shots, counts = iter_valid_rows(lines, "7i")
        thresholds = compute_thresholds(shots)
        version_block = {
            "kpi_version": "v2.1",
            "created_at": "2026-01-01T00:00:00Z",
            "method": "percentile_baseline",
            "source_session": str(self.sample_csv),
            "club": "7i",
            "n_shots_total": counts.get("rows_total"),
            "n_shots_used": len(shots),
            "filters_applied": ["none"],
            "percentile_method": "linear_interpolation_p0_70_p0_50",
            "thresholds": thresholds,
        }
        versions["v2.1"] = version_block
        self.assertIn("v2.1", versions)
        self.assertIn("percentile_method", versions["v2.1"])
        for key in (
            "kpi_version",
            "created_at",
            "method",
            "source_session",
            "club",
            "n_shots_total",
            "n_shots_used",
            "filters_applied",
            "thresholds",
        ):
            self.assertIn(key, versions["v2.1"])

    def test_compute_thresholds_structure(self) -> None:
        shots = [
            {
                "ball_speed": 100.0,
                "smash_factor": 1.2,
                "descent_angle": 45.0,
                "spin_rate": 4500.0,
            },
            {
                "ball_speed": 110.0,
                "smash_factor": 1.3,
                "descent_angle": 50.0,
                "spin_rate": 4700.0,
            },
        ]
        thresholds = compute_thresholds(shots)
        self.assertIn("a", thresholds)
        self.assertIn("b", thresholds)
        self.assertIn("c", thresholds)
        self.assertIn("ball_speed_min", thresholds["a"])
        self.assertIn("smash_min", thresholds["a"])
        self.assertIn("spin_min", thresholds["a"])
        self.assertIn("descent_min", thresholds["a"])


if __name__ == "__main__":
    unittest.main()