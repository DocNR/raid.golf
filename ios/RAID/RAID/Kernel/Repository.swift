// Repository.swift
// RAID Golf - iOS Port
//
// Phase 2.4: Data Access Layer
//
// Purpose:
// - Insert path: canonicalize → hash → store (hash computed once)
// - Read path: return stored hash directly (never recompute)
// - Enforce "no re-hash on read" via dependency injection + behavioral tests
//
// Invariants:
// - template_hash is required column
// - No save(updatedTemplate) method exists
// - Canonicalize/hash only callable from insert path
// - Repository owns hash computation (callers provide raw JSON bytes)
//
// RTM-04: Read path MUST NOT call canonicalize or hash functions

import Foundation
import GRDB

// MARK: - Database Factory

extension DatabaseQueue {
    /// Create database with explicit FK enforcement
    /// Phase 2.4 acceptance requirement: FK enforcement must be explicit
    static func createRAIDDatabase(at path: String) throws -> DatabaseQueue {
        var config = Configuration()
        config.foreignKeysEnabled = true  // Explicit (not relying on defaults)
        let dbQueue = try DatabaseQueue(path: path, configuration: config)
        try Schema.install(in: dbQueue)
        return dbQueue
    }
}

// MARK: - Template Record

struct TemplateRecord {
    let hash: String
    let schemaVersion: String
    let club: String
    let canonicalJSON: String
    let createdAt: String
}

// MARK: - Template Repository Errors

enum TemplateRepositoryError: Error {
    case missingRequiredFields(String)
    case utf8EncodingFailed
}

// MARK: - Template Repository

class TemplateRepository {
    private let dbQueue: DatabaseQueue
    private let canonicalizer: Canonicalizing
    private let hasher: Hashing
    
    init(dbQueue: DatabaseQueue,
         canonicalizer: Canonicalizing = RAIDCanonicalizer(),
         hasher: Hashing = RAIDHasher()) {
        self.dbQueue = dbQueue
        self.canonicalizer = canonicalizer
        self.hasher = hasher
    }
    
    // MARK: - Insert Path (hash computed once)
    
    /// Insert a new KPI template
    /// Repository owns canonicalization and hashing (computed once at insert)
    /// - Parameter rawJSON: Raw JSON bytes (UTF-8)
    /// - Returns: Template record with computed hash
    /// - Throws: TemplateRepositoryError or database error
    func insertTemplate(rawJSON: Data) throws -> TemplateRecord {
        // 1. Canonicalize (kernel v2 rules, preserve -0.0)
        let canonicalData = try canonicalizer.canonicalize(rawJSON)
        
        // 2. Hash canonical bytes
        let hash = hasher.sha256Hex(canonicalData)
        
        // 3. Parse to extract metadata
        guard let jsonObject = try? JSONSerialization.jsonObject(with: rawJSON) as? [String: Any],
              let schemaVersion = jsonObject["schema_version"] as? String,
              let club = jsonObject["club"] as? String else {
            throw TemplateRepositoryError.missingRequiredFields("schema_version, club")
        }
        
        // 4. Convert canonical data to UTF-8 string (no forced unwrap)
        guard let canonicalString = String(data: canonicalData, encoding: .utf8) else {
            throw TemplateRepositoryError.utf8EncodingFailed
        }
        
        let now = ISO8601DateFormatter().string(from: Date())
        
        // 5. Store in database with imported_at
        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO kpi_templates (template_hash, schema_version, club, canonical_json, created_at, imported_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [hash, schemaVersion, club, canonicalString, now, now]
            )
        }
        
        return TemplateRecord(
            hash: hash,
            schemaVersion: schemaVersion,
            club: club,
            canonicalJSON: canonicalString,
            createdAt: now
        )
    }
    
    // MARK: - Read Path (returns stored hash, never recomputes)
    
    /// Fetch a template by its stored hash
    /// RTM-04: This method MUST NOT call canonicalize or hash functions
    /// - Parameter hash: The template hash (already computed)
    /// - Returns: Template record, or nil if not found
    /// - Throws: Database error
    func fetchTemplate(byHash hash: String) throws -> TemplateRecord? {
        return try dbQueue.read { db in
            guard let row = try Row.fetchOne(db,
                sql: "SELECT * FROM kpi_templates WHERE template_hash = ?",
                arguments: [hash]) else {
                return nil
            }
            
            return TemplateRecord(
                hash: row["template_hash"],
                schemaVersion: row["schema_version"],
                club: row["club"],
                canonicalJSON: row["canonical_json"],
                createdAt: row["created_at"]
            )
        }
    }
    
    /// Fetch the latest template for a given club
    /// RTM-04: This method MUST NOT call canonicalize or hash functions
    /// Uses deterministic ordering: imported_at DESC (with created_at fallback), then rowid DESC
    /// - Parameter club: Club identifier (e.g., "7i", "PW")
    /// - Returns: Latest template record for club, or nil if none exists
    /// - Throws: Database error
    func fetchLatestTemplate(forClub club: String) throws -> TemplateRecord? {
        return try dbQueue.read { db in
            guard let row = try Row.fetchOne(db,
                sql: """
                SELECT template_hash, schema_version, club, canonical_json, created_at
                FROM kpi_templates
                WHERE club = ?
                ORDER BY COALESCE(imported_at, created_at) DESC, rowid DESC
                LIMIT 1
                """,
                arguments: [club]) else {
                return nil
            }
            
            return TemplateRecord(
                hash: row["template_hash"],
                schemaVersion: row["schema_version"],
                club: row["club"],
                canonicalJSON: row["canonical_json"],
                createdAt: row["created_at"]
            )
        }
    }
}

// MARK: - Session Record

struct SessionRecord {
    let sessionId: Int64
    let sessionDate: String
    let sourceFile: String
    let deviceType: String?
    let location: String?
    let ingestedAt: String
}

// MARK: - Session Repository

class SessionRepository {
    private let dbQueue: DatabaseQueue
    
    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }
    
    /// Insert a new session
    func insertSession(sessionDate: String,
                      sourceFile: String,
                      deviceType: String? = nil,
                      location: String? = nil) throws -> SessionRecord {
        let ingestedAt = ISO8601DateFormatter().string(from: Date())
        
        let sessionId = try dbQueue.write { db -> Int64 in
            try db.execute(
                sql: """
                INSERT INTO sessions (session_date, source_file, device_type, location, ingested_at)
                VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [sessionDate, sourceFile, deviceType, location, ingestedAt]
            )
            return db.lastInsertedRowID
        }
        
        return SessionRecord(
            sessionId: sessionId,
            sessionDate: sessionDate,
            sourceFile: sourceFile,
            deviceType: deviceType,
            location: location,
            ingestedAt: ingestedAt
        )
    }
    
    /// Fetch a session by ID
    func fetchSession(byId sessionId: Int64) throws -> SessionRecord? {
        return try dbQueue.read { db in
            guard let row = try Row.fetchOne(db,
                sql: "SELECT * FROM sessions WHERE session_id = ?",
                arguments: [sessionId]) else {
                return nil
            }
            
            return SessionRecord(
                sessionId: row["session_id"],
                sessionDate: row["session_date"],
                sourceFile: row["source_file"],
                deviceType: row["device_type"],
                location: row["location"],
                ingestedAt: row["ingested_at"]
            )
        }
    }
}

// MARK: - Shot Record

struct ShotRecord {
    let shotId: Int64
    let sessionId: Int64
    let sourceRowIndex: Int
    let sourceFormat: String
    let importedAt: String
    let rawJSON: String
    let club: String
    let carry: Double?
    let ballSpeed: Double?
    let smashFactor: Double?
    let spinRate: Double?
    let descentAngle: Double?
}

// MARK: - Shot Repository

class ShotRepository {
    private let dbQueue: DatabaseQueue
    
    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }
    
    /// Insert shots in batch
    func insertShots(_ shots: [(rowIndex: Int, club: String, rawJSON: String, carry: Double?, ballSpeed: Double?)],
                    sessionId: Int64,
                    sourceFormat: String) throws {
        let importedAt = ISO8601DateFormatter().string(from: Date())
        
        try dbQueue.write { db in
            for shot in shots {
                try db.execute(
                    sql: """
                    INSERT INTO shots (session_id, source_row_index, source_format, imported_at, raw_json, club, carry, ball_speed)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [sessionId, shot.rowIndex, sourceFormat, importedAt, shot.rawJSON, shot.club, shot.carry, shot.ballSpeed]
                )
            }
        }
    }
    
    /// Fetch shots for a session
    func fetchShots(forSession sessionId: Int64) throws -> [ShotRecord] {
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db,
                sql: """
                SELECT shot_id, session_id, source_row_index, source_format, imported_at, raw_json, 
                       club, carry, ball_speed, smash_factor, spin_rate, descent_angle
                FROM shots 
                WHERE session_id = ? 
                ORDER BY source_row_index
                """,
                arguments: [sessionId])
            
            return rows.map { row in
                ShotRecord(
                    shotId: row["shot_id"],
                    sessionId: row["session_id"],
                    sourceRowIndex: row["source_row_index"],
                    sourceFormat: row["source_format"],
                    importedAt: row["imported_at"],
                    rawJSON: row["raw_json"],
                    club: row["club"],
                    carry: row["carry"],
                    ballSpeed: row["ball_speed"],
                    smashFactor: row["smash_factor"],
                    spinRate: row["spin_rate"],
                    descentAngle: row["descent_angle"]
                )
            }
        }
    }
}
