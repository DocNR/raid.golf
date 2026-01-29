"""
Repository layer for RAID Phase 0 MVP.

Provides insert and read operations for authoritative entities.
Critical: Read operations MUST NOT call canonicalize() or compute_template_hash().
The stored template_hash is authoritative (RTM-04).
"""
import sqlite3
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional


class Repository:
    """
    SQLite repository for RAID Phase 0.
    
    Enforces immutability via schema triggers.
    """
    
    def __init__(self, db_path: str):
        """Initialize repository with database path."""
        self.db_path = db_path
        self._ensure_schema()
    
    def _ensure_schema(self):
        """
        Ensure schema exists by running schema.sql if needed.
        
        Verifies all authoritative tables exist and fails loudly if partial schema detected.
        """
        schema_path = Path(__file__).parent / "schema.sql"
        
        conn = sqlite3.connect(self.db_path)
        conn.execute("PRAGMA foreign_keys = ON")
        
        try:
            # Check which authoritative tables exist
            cursor = conn.execute(
                """
                SELECT name FROM sqlite_master 
                WHERE type='table' AND name IN ('sessions', 'kpi_templates', 'club_subsessions')
                ORDER BY name
                """
            )
            existing_tables = {row[0] for row in cursor.fetchall()}
            required_tables = {'sessions', 'kpi_templates', 'club_subsessions'}
            
            if len(existing_tables) == 0:
                # No schema - create it
                with open(schema_path) as f:
                    schema_sql = f.read()
                conn.executescript(schema_sql)
                conn.commit()
            elif existing_tables != required_tables:
                # Partial schema detected - fail loudly
                missing = required_tables - existing_tables
                extra = existing_tables - required_tables
                error_msg = "Partial schema detected. "
                if missing:
                    error_msg += f"Missing tables: {missing}. "
                if extra:
                    error_msg += f"Unexpected tables: {extra}. "
                error_msg += "Drop database or manually fix schema."
                raise RuntimeError(error_msg)
            # else: all required tables exist - good to go
        finally:
            conn.close()
    
    def _get_connection(self) -> sqlite3.Connection:
        """Get a database connection with row factory and foreign keys enabled."""
        conn = sqlite3.connect(self.db_path)
        conn.execute("PRAGMA foreign_keys = ON")
        conn.row_factory = sqlite3.Row
        return conn
    
    # ================================================================
    # SESSION OPERATIONS
    # ================================================================
    
    def insert_session(
        self,
        session_date: str,
        source_file: str,
        device_type: Optional[str] = None,
        location: Optional[str] = None,
        ingested_at: Optional[str] = None
    ) -> int:
        """
        Insert a new session.
        
        Args:
            session_date: ISO-8601 timestamp of session
            source_file: Original CSV filename
            device_type: Launch monitor type (optional)
            location: Practice location (optional)
            ingested_at: Ingest timestamp (defaults to now)
        
        Returns:
            session_id of inserted row
        """
        if ingested_at is None:
            ingested_at = datetime.utcnow().isoformat() + 'Z'
        
        with self._get_connection() as conn:
            cursor = conn.execute(
                """
                INSERT INTO sessions (session_date, source_file, device_type, location, ingested_at)
                VALUES (?, ?, ?, ?, ?)
                """,
                (session_date, source_file, device_type, location, ingested_at)
            )
            conn.commit()
            return cursor.lastrowid
    
    def get_session(self, session_id: int) -> Optional[Dict[str, Any]]:
        """
        Retrieve a session by ID.
        
        Args:
            session_id: Session primary key
        
        Returns:
            Dict of session fields, or None if not found
        """
        with self._get_connection() as conn:
            cursor = conn.execute(
                "SELECT * FROM sessions WHERE session_id = ?",
                (session_id,)
            )
            row = cursor.fetchone()
            return dict(row) if row else None
    
    # ================================================================
    # KPI TEMPLATE OPERATIONS
    # ================================================================
    
    def insert_template(
        self,
        template_hash: str,
        schema_version: str,
        club: str,
        canonical_json: str,
        created_at: Optional[str] = None,
        imported_at: Optional[str] = None
    ) -> str:
        """
        Insert a new KPI template.
        
        CRITICAL: The template_hash is computed ONCE before calling this method.
        This method does NOT recompute the hash.
        
        Args:
            template_hash: Pre-computed SHA-256 hash (64 hex chars)
            schema_version: Template schema version
            club: Target club
            canonical_json: Canonical JSON content
            created_at: Original creation timestamp (defaults to now)
            imported_at: Import timestamp (None if locally created)
        
        Returns:
            template_hash (for convenience)
        """
        if created_at is None:
            created_at = datetime.utcnow().isoformat() + 'Z'
        
        with self._get_connection() as conn:
            conn.execute(
                """
                INSERT INTO kpi_templates 
                (template_hash, schema_version, club, canonical_json, created_at, imported_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (template_hash, schema_version, club, canonical_json, created_at, imported_at)
            )
            conn.commit()
            return template_hash
    
    def get_template(self, template_hash: str) -> Optional[Dict[str, Any]]:
        """
        Retrieve a template by hash.
        
        RTM-04: This method MUST NOT call canonicalize() or compute_template_hash().
        The stored hash is authoritative.
        
        Args:
            template_hash: Template hash to retrieve
        
        Returns:
            Dict of template fields, or None if not found
        """
        with self._get_connection() as conn:
            cursor = conn.execute(
                "SELECT * FROM kpi_templates WHERE template_hash = ?",
                (template_hash,)
            )
            row = cursor.fetchone()
            return dict(row) if row else None
    
    def list_templates_by_club(self, club: str) -> List[Dict[str, Any]]:
        """
        List all templates for a specific club.
        
        Args:
            club: Club identifier
        
        Returns:
            List of template dicts
        """
        with self._get_connection() as conn:
            cursor = conn.execute(
                "SELECT * FROM kpi_templates WHERE club = ? ORDER BY created_at",
                (club,)
            )
            return [dict(row) for row in cursor.fetchall()]
    
    # ================================================================
    # CLUB SUB-SESSION OPERATIONS
    # ================================================================
    
    def insert_subsession(
        self,
        session_id: int,
        club: str,
        kpi_template_hash: str,
        shot_count: int,
        validity_status: str,
        a_count: int,
        b_count: int,
        c_count: int,
        a_percentage: Optional[float],
        avg_carry: Optional[float] = None,
        avg_ball_speed: Optional[float] = None,
        avg_spin: Optional[float] = None,
        avg_descent: Optional[float] = None,
        analyzed_at: Optional[str] = None
    ) -> int:
        """
        Insert a new club sub-session analysis result.
        
        Args:
            session_id: Parent session ID
            club: Club identifier
            kpi_template_hash: Template used for analysis
            shot_count: Total valid shots
            validity_status: 'invalid_insufficient_data', 'valid_low_sample_warning', or 'valid'
            a_count: Number of A-grade shots
            b_count: Number of B-grade shots
            c_count: Number of C-grade shots
            a_percentage: Percentage of A shots (NULL if invalid)
            avg_carry: Average carry distance
            avg_ball_speed: Average ball speed
            avg_spin: Average spin rate
            avg_descent: Average descent angle
            analyzed_at: Analysis timestamp (defaults to now)
        
        Returns:
            subsession_id of inserted row
        """
        if analyzed_at is None:
            analyzed_at = datetime.utcnow().isoformat() + 'Z'
        
        with self._get_connection() as conn:
            cursor = conn.execute(
                """
                INSERT INTO club_subsessions 
                (session_id, club, kpi_template_hash, shot_count, validity_status,
                 a_count, b_count, c_count, a_percentage,
                 avg_carry, avg_ball_speed, avg_spin, avg_descent, analyzed_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (session_id, club, kpi_template_hash, shot_count, validity_status,
                 a_count, b_count, c_count, a_percentage,
                 avg_carry, avg_ball_speed, avg_spin, avg_descent, analyzed_at)
            )
            conn.commit()
            return cursor.lastrowid
    
    def get_subsession(self, subsession_id: int) -> Optional[Dict[str, Any]]:
        """
        Retrieve a sub-session by ID.
        
        Args:
            subsession_id: Sub-session primary key
        
        Returns:
            Dict of sub-session fields, or None if not found
        """
        with self._get_connection() as conn:
            cursor = conn.execute(
                "SELECT * FROM club_subsessions WHERE subsession_id = ?",
                (subsession_id,)
            )
            row = cursor.fetchone()
            return dict(row) if row else None
    
    def list_subsessions_by_session(self, session_id: int) -> List[Dict[str, Any]]:
        """
        List all sub-sessions for a session.
        
        Args:
            session_id: Parent session ID
        
        Returns:
            List of sub-session dicts
        """
        with self._get_connection() as conn:
            cursor = conn.execute(
                "SELECT * FROM club_subsessions WHERE session_id = ? ORDER BY club",
                (session_id,)
            )
            return [dict(row) for row in cursor.fetchall()]

    def list_subsessions_by_club(
        self,
        club: str,
        min_validity: Optional[str] = None,
    ) -> List[Dict[str, Any]]:
        """
        List sub-sessions for a specific club.

        RTM-10: Filtering is explicit via min_validity parameter.
        All results include validity_status.

        Args:
            club: Club identifier
            min_validity: Optional minimum validity threshold.
                None -> include all statuses
                'valid_low_sample_warning' -> include warning + valid
                'valid' -> include valid only

        Returns:
            List of sub-session dicts
        """
        validity_order = {
            "invalid_insufficient_data": 0,
            "valid_low_sample_warning": 1,
            "valid": 2,
        }

        with self._get_connection() as conn:
            if min_validity is None:
                cursor = conn.execute(
                    """
                    SELECT * FROM club_subsessions
                    WHERE club = ?
                    ORDER BY analyzed_at
                    """,
                    (club,),
                )
                return [dict(row) for row in cursor.fetchall()]

            if min_validity not in validity_order:
                raise ValueError(
                    "min_validity must be one of: "
                    "invalid_insufficient_data, valid_low_sample_warning, valid"
                )

            min_rank = validity_order[min_validity]
            allowed_statuses = [
                status for status, rank in validity_order.items() if rank >= min_rank
            ]
            placeholders = ",".join("?" for _ in allowed_statuses)
            query = (
                "SELECT * FROM club_subsessions "
                "WHERE club = ? AND validity_status IN (" + placeholders + ") "
                "ORDER BY analyzed_at"
            )
            cursor = conn.execute(query, (club, *allowed_statuses))
            return [dict(row) for row in cursor.fetchall()]
