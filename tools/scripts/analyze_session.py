#!/usr/bin/env python3
import argparse
import csv
import datetime as dt
import io
import json
import statistics
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

DEVICE_COLUMNS = {
    "rapsodo": {
        "club": ["Club Type", "Club"],
        "carry": ["Carry Distance", "Carry"],
        "ball_speed": ["Ball Speed"],
        "spin": ["Spin Rate"],
        "descent": ["Descent Angle"],
        "smash": ["Smash Factor"],
    },
    "trackman": {
        "club": ["Club", "Club Type"],
        "carry": ["Carry", "Carry Distance"],
        "ball_speed": ["Ball Speed"],
        "spin": ["Spin Rate"],
        "descent": ["Descent Angle"],
        "smash": ["Smash Factor"],
    },
}

SUMMARY_HEADERS = [
    "Date",
    "Location",
    "Club",
    "TotalShots",
    "A",
    "B",
    "C",
    "A%",
    "Avg_A_Carry",
    "Avg_A_BallSpeed",
    "Avg_A_Spin",
    "Avg_A_Descent",
    "KPI_Version",
    "kpi_version",
    "SourceFile",
]

TRENDS_HEADERS = [
    "Date",
    "Club",
    "A%",
    "Avg_A_Carry",
    "Rolling3_A_Pct",
    "Rolling3_Avg_A_Carry",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Analyze a session CSV and write summaries.")
    parser.add_argument("csv_path", type=Path, help="Path to the session CSV file")
    parser.add_argument("--device", choices=DEVICE_COLUMNS.keys(), default="rapsodo")
    parser.add_argument("--location", default="", help="Optional location label")
    parser.add_argument("--kpis", type=Path, default=Path("tools/kpis.json"))
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


def extract_session_date(lines: list[str]) -> str:
    for line in lines[:5]:
        if "-" in line:
            for token in line.split("-"):
                token = token.strip().strip("\"")
                try:
                    date = dt.datetime.strptime(token, "%m/%d/%Y %I:%M %p")
                    return date.strftime("%Y-%m-%d")
                except ValueError:
                    try:
                        date = dt.datetime.strptime(token, "%m/%d/%Y")
                        return date.strftime("%Y-%m-%d")
                    except ValueError:
                        continue
    return dt.datetime.now().strftime("%Y-%m-%d")


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


def meets_a_thresholds(shot: dict, a: dict) -> bool:
    required = ["smash_min", "ball_speed_min", "spin_min", "descent_min"]
    if not all(key in a for key in required):
        return False
    return (
        shot["smash"] >= a["smash_min"]
        and shot["ball_speed"] >= a["ball_speed_min"]
        and shot["spin"] >= a["spin_min"]
        and shot["descent"] >= a["descent_min"]
    )


def is_c_shot(shot: dict, c: dict) -> bool:
    checks = []
    if "smash_max" in c:
        checks.append(shot["smash"] < c["smash_max"])
    if "spin_max" in c:
        checks.append(shot["spin"] < c["spin_max"])
    if "descent_max" in c:
        checks.append(shot["descent"] < c["descent_max"])
    return any(checks)


def meets_b_thresholds(shot: dict, b: dict) -> bool:
    if not b:
        return False
    if "smash_min" in b and shot["smash"] < b["smash_min"]:
        return False
    if "smash_max" in b and shot["smash"] > b["smash_max"]:
        return False
    if "spin_min" in b and shot["spin"] < b["spin_min"]:
        return False
    if "descent_min" in b and shot["descent"] < b["descent_min"]:
        return False
    return True


def classify_shot(shot: dict, thresholds: dict | None) -> str:
    if thresholds is None:
        return "unclassified"
    a = thresholds.get("a", {})
    b = thresholds.get("b", {})
    c = thresholds.get("c", {})

    if meets_a_thresholds(shot, a):
        return "A"
    if is_c_shot(shot, c):
        return "C"
    if meets_b_thresholds(shot, b):
        return "B"
    return "C"


def mean(values: list[float]) -> float | None:
    if not values:
        return None
    return statistics.mean(values)


def ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def write_csv(path: Path, headers: list[str], rows: list[dict]) -> None:
    ensure_parent(path)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=headers)
        writer.writeheader()
        writer.writerows(rows)


def append_csv(path: Path, headers: list[str], rows: list[dict]) -> None:
    ensure_parent(path)
    file_exists = path.exists()
    with path.open("a", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=headers)
        if not file_exists:
            writer.writeheader()
        writer.writerows(rows)


def build_trends(summary_rows: list[dict]) -> list[dict]:
    grouped: dict[str, list[dict]] = {}
    for row in summary_rows:
        club = row.get("Club", "")
        if not club:
            continue
        grouped.setdefault(club, []).append(row)

    trends: list[dict] = []
    for club, rows in grouped.items():
        rows.sort(key=lambda r: r.get("Date", ""))
        history: list[dict] = []
        for row in rows:
            a_pct = row.get("A%")
            avg_carry = row.get("Avg_A_Carry")
            if a_pct and avg_carry:
                history.append({"a_pct": float(a_pct), "avg_carry": float(avg_carry)})
            window = history[-3:]
            rolling_a = mean([item["a_pct"] for item in window]) if len(window) == 3 else None
            rolling_carry = (
                mean([item["avg_carry"] for item in window]) if len(window) == 3 else None
            )

            trends.append(
                {
                    "Date": row.get("Date", ""),
                    "Club": club,
                    "A%": a_pct or "",
                    "Avg_A_Carry": avg_carry or "",
                    "Rolling3_A_Pct": f"{rolling_a:.1f}" if rolling_a is not None else "",
                    "Rolling3_Avg_A_Carry": f"{rolling_carry:.1f}" if rolling_carry is not None else "",
                }
            )
    return trends


def append_ingest_report(path: Path, report: str) -> None:
    ensure_parent(path)
    timestamp = dt.datetime.now().strftime("%Y-%m-%d %H:%M")
    with path.open("a", encoding="utf-8") as handle:
        handle.write(f"## Ingest Report — {timestamp}\n\n")
        handle.write(report.strip())
        handle.write("\n\n")


def summarize_counts(classifications: list[str]) -> dict:
    return {label: classifications.count(label) for label in ("A", "B", "C")}


def main() -> None:
    args = parse_args()
    csv_path = args.csv_path
    if not csv_path.exists():
        raise SystemExit(f"File not found: {csv_path}")

    lines = read_lines(csv_path)
    header_idx = find_header_index(lines)
    session_date = extract_session_date(lines)
    data_stream = io.StringIO("\n".join(lines[header_idx:]))
    reader = csv.DictReader(data_stream)

    columns = DEVICE_COLUMNS[args.device]
    kpis = load_kpis(args.kpis)
    clubs_config = {club.lower(): payload for club, payload in kpis.get("clubs", {}).items()}
    default_kpi_version = kpis.get("default_kpi_version", "unknown")

    shots_by_club: dict[str, list[dict]] = {}
    excluded_rows = 0
    excluded_reasons: dict[str, int] = {}

    for row in reader:
        club = normalize_column(row, columns["club"])
        if club is None:
            excluded_rows += 1
            excluded_reasons["missing_club"] = excluded_reasons.get("missing_club", 0) + 1
            continue
        club = club.strip()
        if not club:
            excluded_rows += 1
            excluded_reasons["empty_club"] = excluded_reasons.get("empty_club", 0) + 1
            continue
        if club.strip().lower() in FOOTER_LABELS:
            excluded_rows += 1
            excluded_reasons["footer"] = excluded_reasons.get("footer", 0) + 1
            continue

        carry = parse_float(normalize_column(row, columns["carry"]))
        ball_speed = parse_float(normalize_column(row, columns["ball_speed"]))
        spin = parse_float(normalize_column(row, columns["spin"]))
        descent = parse_float(normalize_column(row, columns["descent"]))
        smash = parse_float(normalize_column(row, columns["smash"]))

        if None in (carry, ball_speed, spin, descent, smash):
            excluded_rows += 1
            excluded_reasons["non_numeric"] = excluded_reasons.get("non_numeric", 0) + 1
            continue

        shots_by_club.setdefault(club, []).append(
            {
                "carry": carry,
                "ball_speed": ball_speed,
                "spin": spin,
                "descent": descent,
                "smash": smash,
            }
        )

    summary_rows: list[dict] = []
    summary_report_lines: list[str] = []

    for club, shots in shots_by_club.items():
        club_key = club.lower()
        thresholds = clubs_config.get(club_key)
        classifications = [classify_shot(shot, thresholds) for shot in shots]
        total = len(shots)
        counts = summarize_counts(classifications)

        if thresholds is None:
            a_shots = shots
            is_unclassified = True
        else:
            a_shots = [shot for shot, label in zip(shots, classifications) if label == "A"]
            is_unclassified = False

        avg_a_carry = mean([shot["carry"] for shot in a_shots])
        avg_a_ball = mean([shot["ball_speed"] for shot in a_shots])
        avg_a_spin = mean([shot["spin"] for shot in a_shots])
        avg_a_descent = mean([shot["descent"] for shot in a_shots])

        kpi_version = (
            thresholds.get("kpi_version")
            if thresholds and thresholds.get("kpi_version")
            else default_kpi_version
        )
        a_pct = f"{(counts['A'] / total) * 100:.1f}" if total and not is_unclassified else ""

        summary_rows.append(
            {
                "Date": session_date,
                "Location": args.location,
                "Club": club,
                "TotalShots": total,
                "A": "" if is_unclassified else counts["A"],
                "B": "" if is_unclassified else counts["B"],
                "C": "" if is_unclassified else counts["C"],
                "A%": a_pct,
                "Avg_A_Carry": f"{avg_a_carry:.1f}" if avg_a_carry is not None else "",
                "Avg_A_BallSpeed": f"{avg_a_ball:.1f}" if avg_a_ball is not None else "",
                "Avg_A_Spin": f"{avg_a_spin:.0f}" if avg_a_spin is not None else "",
                "Avg_A_Descent": f"{avg_a_descent:.1f}" if avg_a_descent is not None else "",
                "KPI_Version": kpi_version,
                "kpi_version": kpi_version,
                "SourceFile": str(csv_path),
            }
        )

        if is_unclassified:
            summary_report_lines.append(f"- {club}: Total {total} | unclassified (no KPI thresholds)")
        else:
            summary_report_lines.append(
                f"- {club}: Total {total} | A {counts['A']} | B {counts['B']} | C {counts['C']} | A% {a_pct}"
            )

    summary_path = Path("data/summaries/session_summary.csv")
    append_csv(summary_path, SUMMARY_HEADERS, summary_rows)

    all_summary_rows: list[dict] = []
    if summary_path.exists():
        with summary_path.open("r", newline="", encoding="utf-8") as handle:
            reader = csv.DictReader(handle)
            all_summary_rows.extend(reader)

    trends = build_trends(all_summary_rows)
    write_csv(Path("data/summaries/a_shot_trends.csv"), TRENDS_HEADERS, trends)

    report_lines = [
        f"Source file: {csv_path}",
        f"Device: {args.device}",
        f"Session date: {session_date}",
        f"Total shot rows: {sum(len(shots) for shots in shots_by_club.values())}",
        f"Excluded rows: {excluded_rows}",
    ]
    if excluded_reasons:
        report_lines.append("Excluded reasons:")
        for reason, count in sorted(excluded_reasons.items()):
            report_lines.append(f"- {reason}: {count}")
    report_lines.append("Summary:")
    report_lines.extend(summary_report_lines or ["- No valid shot rows parsed."])

    append_ingest_report(Path("data/summaries/ingest_report.md"), "\n".join(report_lines))

    print("Session analysis complete.")
    print("\n".join(summary_report_lines))
    if excluded_reasons:
        print("Excluded rows:")
        for reason, count in sorted(excluded_reasons.items()):
            print(f"- {reason}: {count}")


if __name__ == "__main__":
    main()
