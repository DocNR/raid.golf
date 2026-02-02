#!/usr/bin/env python3
"""
RAID Phase 0.1 CLI

Kernel-safe command-line interface for RAID Golf.
- Read-only queries on authoritative data
- Insert-only operations (ingest, template load)
- No mutations of fact tables
"""
import argparse
import sys
from pathlib import Path
from typing import Optional

from raid.repository import Repository
from raid.ingest import ingest_rapsodo_csv
from raid.templates_loader import load_templates_from_kpis_json
from raid.projections import generate_projection_for_subsession, serialize_projection
from raid.trends import compute_club_trend


def cmd_ingest(args):
    """Ingest a Rapsodo CSV file into the database."""
    csv_path = args.csv
    db_path = args.db
    
    if not Path(csv_path).exists():
        print(f"Error: CSV file not found: {csv_path}", file=sys.stderr)
        return 1
    
    repo = Repository(db_path)
    
    # Get all clubs that have templates
    clubs = repo.list_template_clubs()
    if not clubs:
        print("Error: No templates found. Run 'raid templates load' first.", file=sys.stderr)
        return 1
    
    # Use the most recent template for each club
    template_hash_by_club = {}
    for club in clubs:
        club_templates = repo.list_templates_by_club(club)
        if club_templates:
            # Use most recent template (last in created_at order)
            template_hash_by_club[club] = club_templates[-1]["template_hash"]
    
    try:
        session_id = ingest_rapsodo_csv(
            repo=repo,
            csv_path=csv_path,
            template_hash_by_club=template_hash_by_club,
            device_type=args.device or "Rapsodo MLM2Pro",
            location=args.location,
        )
        print(f"✅ Session {session_id} ingested from {Path(csv_path).name}")
        return 0
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


def cmd_sessions(args):
    """List all sessions."""
    db_path = args.db
    repo = Repository(db_path)
    
    sessions = repo.list_sessions()
    
    if not sessions:
        print("No sessions found.")
        return 0
    
    # Print header
    print(f"{'ID':<4} {'Date':<19} {'Source':<35} {'Clubs':<6} {'Device':<20}")
    print("=" * 90)
    
    # Print sessions
    for session in sessions:
        session_id = session["session_id"]
        session_date = session["session_date"][:19]  # Trim to datetime
        source_file = session["source_file"][:33] + ".." if len(session["source_file"]) > 35 else session["source_file"]
        device_type = session["device_type"] or "Unknown"
        
        # Count clubs in this session
        subsessions = repo.list_subsessions_by_session(session_id)
        club_count = len(subsessions)
        
        print(f"{session_id:<4} {session_date:<19} {source_file:<35} {club_count:<6} {device_type:<20}")
    
    return 0


def cmd_show(args):
    """Show details for a specific session."""
    db_path = args.db
    session_id = args.session_id
    repo = Repository(db_path)
    
    session = repo.get_session(session_id)
    if not session:
        print(f"Error: Session {session_id} not found.", file=sys.stderr)
        return 1
    
    subsessions = repo.list_subsessions_by_session(session_id)
    
    # Print session header
    print(f"Session: {session_id} ({session['session_date'][:19]})")
    print(f"Source: {session['source_file']}")
    print(f"Device: {session['device_type'] or 'Unknown'}")
    if session['location']:
        print(f"Location: {session['location']}")
    print()
    
    if not subsessions:
        print("No subsessions found.")
        return 0
    
    # Print subsession table
    print(f"{'Club':<6} {'Shots':<6} {'A':<4} {'B':<4} {'C':<4} {'A%':<7} {'Status':<25} {'Carry':<7} {'Speed':<7} {'Spin':<7} {'Descent':<7}")
    print("=" * 105)
    
    for sub in subsessions:
        club = sub["club"]
        shots = sub["shot_count"]
        a = sub["a_count"]
        b = sub["b_count"]
        c = sub["c_count"]
        a_pct = f"{sub['a_percentage']:.1f}%" if sub['a_percentage'] is not None else "N/A"
        status = sub["validity_status"]
        carry = f"{sub['avg_carry']:.1f}" if sub['avg_carry'] is not None else "N/A"
        speed = f"{sub['avg_ball_speed']:.1f}" if sub['avg_ball_speed'] is not None else "N/A"
        spin = f"{sub['avg_spin']:.0f}" if sub['avg_spin'] is not None else "N/A"
        descent = f"{sub['avg_descent']:.1f}" if sub['avg_descent'] is not None else "N/A"
        
        print(f"{club:<6} {shots:<6} {a:<4} {b:<4} {c:<4} {a_pct:<7} {status:<25} {carry:<7} {speed:<7} {spin:<7} {descent:<7}")
    
    return 0


def cmd_templates_list(args):
    """List all KPI templates."""
    db_path = args.db
    repo = Repository(db_path)
    
    # Get all clubs that have templates
    clubs = repo.list_template_clubs()
    
    if not clubs:
        print("No templates found. Run 'raid templates load' to load from tools/kpis.json")
        return 0
    
    # Get all templates for all clubs
    all_templates = []
    for club in clubs:
        templates = repo.list_templates_by_club(club)
        all_templates.extend(templates)
    
    print(f"{'Club':<6} {'Hash (first 16)':<18} {'Version':<10} {'Created':<19}")
    print("=" * 60)
    
    for template in all_templates:
        club = template["club"]
        hash_short = template["template_hash"][:16]
        version = template["schema_version"]
        created = template["created_at"][:19]
        
        print(f"{club:<6} {hash_short:<18} {version:<10} {created:<19}")
    
    return 0


def cmd_templates_load(args):
    """Load KPI templates from tools/kpis.json."""
    db_path = args.db
    kpis_path = args.from_path
    repo = Repository(db_path)
    
    try:
        result = load_templates_from_kpis_json(repo, kpis_path)
        
        print(f"✅ Template load complete:")
        print(f"  Inserted: {len(result['inserted'])} templates")
        print(f"  Existing: {len(result['existing'])} templates (skipped)")
        
        if result['skipped']:
            print(f"  Skipped: {len(result['skipped'])} clubs")
            for club, reason in result['skipped']:
                print(f"    - {club}: {reason}")
        
        return 0
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1


def cmd_trend(args):
    """Show A% trend for a club."""
    db_path = args.db
    club = args.club
    min_validity = args.min_validity or "valid_low_sample_warning"
    window = args.window
    repo = Repository(db_path)
    
    try:
        result = compute_club_trend(
            repo=repo,
            club=club,
            min_validity=min_validity,
            window=window,
            weighted=True,
        )
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        return 1
    
    # Print header
    print(f"Club: {result.club}")
    print(f"Sessions: {result.total_sessions} ({min_validity} or better)")
    print(f"Total shots: {result.total_shots}")
    if window:
        print(f"Window: Last {window} sessions")
    print()
    
    # Print data table
    print(f"{'Date':<19} {'A%':<7} {'Shots':<6} {'Status':<25}")
    print("=" * 60)
    
    for dp in result.data_points:
        date_str = dp.session_date[:19]
        a_pct_str = f"{dp.a_percentage:.1f}%" if dp.a_percentage is not None else "N/A"
        shots = dp.shot_count
        status = dp.validity_status
        
        print(f"{date_str:<19} {a_pct_str:<7} {shots:<6} {status:<25}")
    
    print()
    if result.weighted_avg_a_percent is not None:
        print(f"Weighted Average A%: {result.weighted_avg_a_percent:.1f}%")
    else:
        print("Weighted Average A%: N/A (no valid data)")
    
    return 0


def cmd_export(args):
    """Export projections for a session."""
    db_path = args.db
    session_id = args.session_id
    output_format = args.format
    repo = Repository(db_path)
    
    session = repo.get_session(session_id)
    if not session:
        print(f"Error: Session {session_id} not found.", file=sys.stderr)
        return 1
    
    subsessions = repo.list_subsessions_by_session(session_id)
    if not subsessions:
        print(f"Error: No subsessions found for session {session_id}.", file=sys.stderr)
        return 1
    
    # Generate projections for all subsessions
    projections = []
    for sub in subsessions:
        subsession_id = sub["subsession_id"]
        projection = generate_projection_for_subsession(repo, subsession_id)
        projections.append(projection)
    
    if output_format == "json":
        import json
        print(json.dumps(projections, indent=2))
    else:
        print(f"Error: Unsupported format '{output_format}'", file=sys.stderr)
        return 1
    
    return 0


def main():
    """Main CLI entrypoint."""
    parser = argparse.ArgumentParser(
        prog="raid",
        description="RAID Golf - Practice session analysis and tracking"
    )
    parser.add_argument(
        "--db",
        default="./raid.db",
        help="Database path (default: ./raid.db)"
    )
    
    subparsers = parser.add_subparsers(dest="command", help="Available commands")
    
    # === ingest ===
    parser_ingest = subparsers.add_parser("ingest", help="Ingest a Rapsodo CSV file")
    parser_ingest.add_argument("csv", help="Path to CSV file")
    parser_ingest.add_argument("--device", help="Device type (default: Rapsodo MLM2Pro)")
    parser_ingest.add_argument("--location", help="Practice location")
    parser_ingest.set_defaults(func=cmd_ingest)
    
    # === sessions ===
    parser_sessions = subparsers.add_parser("sessions", help="List all sessions")
    parser_sessions.set_defaults(func=cmd_sessions)
    
    # === show ===
    parser_show = subparsers.add_parser("show", help="Show session details")
    parser_show.add_argument("session_id", type=int, help="Session ID")
    parser_show.set_defaults(func=cmd_show)
    
    # === trend ===
    parser_trend = subparsers.add_parser("trend", help="Show A%% trend for a club")
    parser_trend.add_argument("club", help="Club identifier (e.g., 7i)")
    parser_trend.add_argument("--min-validity", dest="min_validity", 
                              choices=["invalid_insufficient_data", "valid_low_sample_warning", "valid"],
                              help="Minimum validity status to include")
    parser_trend.add_argument("--window", type=int, help="Rolling window (last N sessions)")
    parser_trend.set_defaults(func=cmd_trend)
    
    # === export ===
    parser_export = subparsers.add_parser("export", help="Export session projections")
    parser_export.add_argument("session_id", type=int, help="Session ID")
    parser_export.add_argument("--format", default="json", choices=["json"], help="Output format")
    parser_export.set_defaults(func=cmd_export)
    
    # === templates ===
    parser_templates = subparsers.add_parser("templates", help="Manage KPI templates")
    templates_subparsers = parser_templates.add_subparsers(dest="templates_command")
    
    parser_templates_list = templates_subparsers.add_parser("list", help="List all templates")
    parser_templates_list.set_defaults(func=cmd_templates_list)
    
    parser_templates_load = templates_subparsers.add_parser("load", help="Load templates from tools/kpis.json")
    parser_templates_load.add_argument("--from", dest="from_path", default="tools/kpis.json", help="Path to kpis.json")
    parser_templates_load.set_defaults(func=cmd_templates_load)
    
    # Parse and execute
    args = parser.parse_args()
    
    if not hasattr(args, 'func'):
        parser.print_help()
        return 1
    
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())