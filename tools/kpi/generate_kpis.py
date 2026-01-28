#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import datetime as dt
import io
import json
from pathlib import Path
FOOTER_LABELS = {
    "average",
    "avg",
    "std. dev.",
    "std dev",
    "std dev.",
    "st. dev.",
    "st dev",
    "standard deviation",
}

RAPSODO_COLUMNS = {
    "club": ["Club Type", "Club"],
    "ball_speed": ["Ball Speed"],
    "spin_rate": ["Spin Rate"],
    "descent_angle": ["Descent Angle"],
    "smash_factor": ["Smash Factor"],
}

METRIC_KEYS = ("ball_speed", "smash_factor", "descent_angle", "spin_rate")
PERCENTILE_METHOD = "linear_interpolation_p0_70_p0_50"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate KPI thresholds from MLM2Pro CSVs.")
    parser.add_argument("csv_path", type=Path, help="Path to the session CSV file")
    parser.add_argument("--club", required=True, help="Club label to target (e.g., 7i)")
    parser.add_argument("--kpis", type=Path, default=Path("tools/kpis.json"))
    parser.add_argument("--kpi-version", required=True, help="New KPI version id (e.g., v2.1)")
    parser.add_argument(
        "--set-active",
        action="store_true",
        help="Update clubs.<club>.kpi_version to new version",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=None,
        help="Optional output path for updated kpis.json (defaults to in-place)",
    )
    return parser.parse_args()


def read_lines(path: Path) -> list[str]:
    content = path.read_text(encoding="utf-8", errors="ignore")
    content = content.lstrip("\ufeff")
    return content.splitlines()


def find_header_index(lines: list[str]) -> int:
    for idx, line in enumerate(lines):
        if "Club Type" in line and "Ball Speed" in line:
            return idx
        if line.startswith("\"Club\"") and "Ball Speed" in line:
            return idx
    raise ValueError("Could not find header row with club and ball speed columns.")


def normalize_column(row: dict, options: list[str]) -> str | None:
    for key in options:
        if key in row:
            return row.get(key)
    return None


def parse_float(value: str | None) -> float | None:
    if value is None:
        return None
    value = value.strip()
    if not value:
        return None
    try:
        return float(value)
    except ValueError:
        return None


def load_kpis(path: Path) -> dict:
    if not path.exists():
        return {"default_kpi_version": "unknown", "clubs": {}}
    return json.loads(path.read_text(encoding="utf-8"))


def percentile(values: list[float], pct: float) -> float:
    if not values:
        raise ValueError("Cannot compute percentile on empty list")
    ordered = sorted(values)
    rank = (len(ordered) - 1) * pct
    lower_idx = int(rank)
    upper_idx = min(lower_idx + 1, len(ordered) - 1)
    weight = rank - lower_idx
    if lower_idx == upper_idx:
        return ordered[lower_idx]
    return ordered[lower_idx] * (1 - weight) + ordered[upper_idx] * weight


def iter_valid_rows(lines: list[str], club_target: str) -> tuple[list[dict], dict[str, int]]:
    header_idx = find_header_index(lines)
    data_stream = io.StringIO("\n".join(lines[header_idx:]))
    reader = csv.DictReader(data_stream)

    counts: dict[str, int] = {
        "rows_total": 0,
        "rows_valid": 0,
        "missing_club": 0,
        "footer": 0,
        "non_numeric": 0,
        "wrong_club": 0,
    }
    shots: list[dict] = []
    club_target_lower = club_target.strip().lower()

    for row in reader:
        counts["rows_total"] += 1
        club = normalize_column(row, RAPSODO_COLUMNS["club"])
        if club is None:
            counts["missing_club"] += 1
            continue
        club = club.strip()
        if not club:
            counts["missing_club"] += 1
            continue
        if club.lower() in FOOTER_LABELS:
            counts["footer"] += 1
            continue
        if club.lower() != club_target_lower:
            counts["wrong_club"] += 1
            continue

        parsed: dict[str, float] = {}
        for key in METRIC_KEYS:
            raw_value = normalize_column(row, RAPSODO_COLUMNS[key])
            numeric = parse_float(raw_value)
            if numeric is None:
                counts["non_numeric"] += 1
                break
            parsed[key] = numeric
        else:
            counts["rows_valid"] += 1
            shots.append(parsed)

    return shots, counts


def compute_thresholds(shots: list[dict]) -> dict:
    metrics: dict[str, list[float]] = {key: [] for key in METRIC_KEYS}
    for shot in shots:
        for key in METRIC_KEYS:
            metrics[key].append(shot[key])

    thresholds = {
        "a": {},
        "b": {},
        "c": {},
    }
    for key, values in metrics.items():
        p70 = percentile(values, 0.70)
        p50 = percentile(values, 0.50)
        if key == "ball_speed":
            thresholds["a"]["ball_speed_min"] = round(p70, 2)
            thresholds["b"]["ball_speed_min"] = round(p50, 2)
            thresholds["b"]["ball_speed_max"] = round(p70, 2)
            thresholds["c"]["ball_speed_max"] = round(p50, 2)
        elif key == "smash_factor":
            thresholds["a"]["smash_min"] = round(p70, 2)
            thresholds["b"]["smash_min"] = round(p50, 2)
            thresholds["b"]["smash_max"] = round(p70, 2)
            thresholds["c"]["smash_max"] = round(p50, 2)
        elif key == "descent_angle":
            thresholds["a"]["descent_min"] = round(p70, 2)
            thresholds["b"]["descent_min"] = round(p50, 2)
            thresholds["b"]["descent_max"] = round(p70, 2)
            thresholds["c"]["descent_max"] = round(p50, 2)
        elif key == "spin_rate":
            thresholds["a"]["spin_min"] = round(p70, 0)
            thresholds["b"]["spin_min"] = round(p50, 0)
            thresholds["b"]["spin_max"] = round(p70, 0)
            thresholds["c"]["spin_max"] = round(p50, 0)
    return thresholds


def ensure_versions(club_payload: dict) -> dict:
    versions = club_payload.get("versions")
    if versions is None:
        versions = {}
        club_payload["versions"] = versions
    return versions


def build_filters_applied(counts: dict[str, int]) -> list[str]:
    filters = []
    if counts.get("missing_club"):
        filters.append("missing_club")
    if counts.get("footer"):
        filters.append("footer_rows")
    if counts.get("wrong_club"):
        filters.append("wrong_club")
    if counts.get("non_numeric"):
        filters.append("non_numeric")
    if not filters:
        filters.append("none")
    return filters


def render_summary(thresholds: dict) -> str:
    lines = ["Generated KPI thresholds:"]
    for bucket in ("a", "b", "c"):
        lines.append(f"{bucket.upper()}:")
        for key, value in thresholds[bucket].items():
            lines.append(f"  - {key}: {value}")
    return "\n".join(lines)


def main() -> None:
    args = parse_args()
    if args.kpi_version == "v2.0":
        raise SystemExit("Refusing to generate v2.0 (manual locked).")

    lines = read_lines(args.csv_path)
    shots, counts = iter_valid_rows(lines, args.club)
    if not shots:
        raise SystemExit("No valid shots found after filtering.")

    kpis = load_kpis(args.kpis)
    clubs = kpis.setdefault("clubs", {})
    club_key = args.club.strip().lower()
    club_payload = clubs.setdefault(club_key, {"kpi_version": kpis.get("default_kpi_version")})
    versions = ensure_versions(club_payload)

    if args.kpi_version in versions:
        raise SystemExit(f"KPI version {args.kpi_version} already exists for club {club_key}.")

    thresholds = compute_thresholds(shots)
    created_at = dt.datetime.now(dt.timezone.utc).isoformat()
    version_block = {
        "kpi_version": args.kpi_version,
        "created_at": created_at,
        "method": "percentile_baseline",
        "source_session": str(args.csv_path),
        "club": club_key,
        "n_shots_total": counts.get("rows_total"),
        "n_shots_used": len(shots),
        "filters_applied": build_filters_applied(counts),
        "percentile_method": PERCENTILE_METHOD,
        "thresholds": thresholds,
    }
    versions[args.kpi_version] = version_block

    if args.set_active:
        club_payload["kpi_version"] = args.kpi_version
        for bucket in ("a", "b", "c"):
            club_payload[bucket] = thresholds[bucket]

    output_path = args.output or args.kpis
    output_path.write_text(json.dumps(kpis, indent=2, sort_keys=False), encoding="utf-8")

    print(render_summary(thresholds))
    print(
        f"Shots: total {counts.get('rows_total')} | used {len(shots)} | "
        f"filtered {counts.get('rows_total', 0) - len(shots)}"
    )
    print(f"Added version {args.kpi_version} for club {club_key}.")
    if args.set_active:
        print(f"Active KPI version updated to {args.kpi_version}.")


if __name__ == "__main__":
    main()