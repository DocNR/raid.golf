// Repository.swift
// Gambit Golf
//
// Data Access Layer
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
    let importedAt: String?
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
            createdAt: now,
            importedAt: now
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
                createdAt: row["created_at"],
                importedAt: row["imported_at"]
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
                SELECT template_hash, schema_version, club, canonical_json, created_at, imported_at
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
                createdAt: row["created_at"],
                importedAt: row["imported_at"]
            )
        }
    }

    /// List all non-hidden templates for a given club, ordered by recency
    /// - Parameter club: Club identifier (e.g., "7i", "PW")
    /// - Returns: Array of template records ordered by recency (most recent first)
    /// - Throws: Database error
    func listTemplates(forClub club: String) throws -> [TemplateRecord] {
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT t.template_hash, t.schema_version, t.club, t.canonical_json, t.created_at, t.imported_at
                FROM kpi_templates t
                LEFT JOIN template_preferences tp ON t.template_hash = tp.template_hash
                WHERE t.club = ? AND (tp.is_hidden IS NULL OR tp.is_hidden = 0)
                ORDER BY COALESCE(t.imported_at, t.created_at) DESC, t.rowid DESC
                """, arguments: [club])

            return rows.map { row in
                TemplateRecord(
                    hash: row["template_hash"],
                    schemaVersion: row["schema_version"],
                    club: row["club"],
                    canonicalJSON: row["canonical_json"],
                    createdAt: row["created_at"],
                    importedAt: row["imported_at"]
                )
            }
        }
    }

    /// List all non-hidden templates grouped by club (club ASC, then recency DESC)
    /// - Returns: Array of template records ordered by club ASC, then recency DESC
    /// - Throws: Database error
    func listAllTemplates() throws -> [TemplateRecord] {
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT t.template_hash, t.schema_version, t.club, t.canonical_json, t.created_at, t.imported_at
                FROM kpi_templates t
                LEFT JOIN template_preferences tp ON t.template_hash = tp.template_hash
                WHERE (tp.is_hidden IS NULL OR tp.is_hidden = 0)
                ORDER BY t.club ASC, COALESCE(t.imported_at, t.created_at) DESC, t.rowid DESC
                """)

            return rows.map { row in
                TemplateRecord(
                    hash: row["template_hash"],
                    schemaVersion: row["schema_version"],
                    club: row["club"],
                    canonicalJSON: row["canonical_json"],
                    createdAt: row["created_at"],
                    importedAt: row["imported_at"]
                )
            }
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

    /// List all sessions with shot counts, newest first.
    /// Single grouped query (no N+1).
    func listSessions() throws -> [SessionListItem] {
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT s.session_id, s.session_date, s.source_file, s.device_type, s.location, s.ingested_at,
                       COUNT(sh.shot_id) AS shot_count
                FROM sessions s
                LEFT JOIN shots sh ON sh.session_id = s.session_id
                GROUP BY s.session_id
                ORDER BY s.session_date DESC, s.session_id DESC
                """)
            return rows.map { row in
                SessionListItem(
                    sessionId: row["session_id"],
                    sessionDate: row["session_date"],
                    sourceFile: row["source_file"],
                    deviceType: row["device_type"],
                    location: row["location"],
                    ingestedAt: row["ingested_at"],
                    shotCount: row["shot_count"]
                )
            }
        }
    }

    /// Total session count (for empty-state checks).
    func sessionCount() throws -> Int {
        return try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sessions") ?? 0
        }
    }
}

// MARK: - Session List Item

struct SessionListItem {
    let sessionId: Int64
    let sessionDate: String
    let sourceFile: String
    let deviceType: String?
    let location: String?
    let ingestedAt: String
    let shotCount: Int
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

// MARK: - Shot Insert Data

struct ShotInsertData {
    let rowIndex: Int
    let club: String
    let rawJSON: String
    let carry: Double?
    let ballSpeed: Double?
    let smashFactor: Double?
    let spinRate: Double?
    let descentAngle: Double?
    let totalDistance: Double?
    let launchAngle: Double?
    let launchDirection: Double?
    let apex: Double?
    let sideCarry: Double?
    let clubSpeed: Double?
    let attackAngle: Double?
    let clubPath: Double?
    let spinAxis: Double?
}

// MARK: - Shot Repository

class ShotRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// Insert shots in batch (all normalized metric columns)
    func insertShots(_ shots: [ShotInsertData],
                    sessionId: Int64,
                    sourceFormat: String) throws {
        let importedAt = ISO8601DateFormatter().string(from: Date())

        try dbQueue.write { db in
            for shot in shots {
                try db.execute(
                    sql: """
                    INSERT INTO shots (session_id, source_row_index, source_format, imported_at, raw_json, club,
                                       carry, ball_speed, smash_factor, spin_rate, descent_angle,
                                       total_distance, launch_angle, launch_direction, apex, side_carry,
                                       club_speed, attack_angle, club_path, spin_axis)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [sessionId, shot.rowIndex, sourceFormat, importedAt, shot.rawJSON, shot.club,
                               shot.carry, shot.ballSpeed, shot.smashFactor, shot.spinRate, shot.descentAngle,
                               shot.totalDistance, shot.launchAngle, shot.launchDirection, shot.apex, shot.sideCarry,
                               shot.clubSpeed, shot.attackAngle, shot.clubPath, shot.spinAxis]
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

// MARK: - Trends Domain

enum TrendMetric: String, CaseIterable {
    case carry
    case ballSpeed
    case spinRate
    case descentAngle
    
    var columnName: String {
        switch self {
        case .carry: return "carry"
        case .ballSpeed: return "ball_speed"
        case .spinRate: return "spin_rate"
        case .descentAngle: return "descent_angle"
        }
    }
    
    var label: String {
        switch self {
        case .carry: return "Carry"
        case .ballSpeed: return "Ball Speed"
        case .spinRate: return "Spin"
        case .descentAngle: return "Descent"
        }
    }
}

enum TrendSeriesType {
    case allShots
    case aOnly
}

struct TrendPoint: Equatable {
    let sessionDate: String
    let sessionId: Int64
    let metric: TrendMetric
    let meanValue: Double?
    let nShots: Int
    let templateHash: String?
}

// MARK: - Trends Repository (Phase 4B)

class TrendsRepository {
    private let dbQueue: DatabaseQueue
    private let templateRepository: TemplateRepository
    
    init(dbQueue: DatabaseQueue, templateRepository: TemplateRepository? = nil) {
        self.dbQueue = dbQueue
        self.templateRepository = templateRepository ?? TemplateRepository(dbQueue: dbQueue)
    }
    
    /// Fetch deterministic trend points for a club + metric + series.
    /// Ordering is always: session_date ASC, session_id ASC.
    func fetchTrendPoints(club: String,
                          metric: TrendMetric,
                          seriesType: TrendSeriesType) throws -> [TrendPoint] {
        switch seriesType {
        case .allShots:
            return try fetchAllShotsTrendPoints(club: club, metric: metric)
        case .aOnly:
            return try fetchAOnlyTrendPoints(club: club, metric: metric)
        }
    }
    
    // MARK: allShots (SQL-only)
    
    /// SQL-only series using AVG(metric) and COUNT(metric).
    /// COUNT(metric) aligns with non-null metric values.
    private func fetchAllShotsTrendPoints(club: String,
                                          metric: TrendMetric) throws -> [TrendPoint] {
        let metricColumn = metric.columnName
        
        let sql = """
            SELECT
                sessions.session_date AS session_date,
                sessions.session_id AS session_id,
                AVG(shots.\(metricColumn)) AS mean_value,
                COUNT(shots.\(metricColumn)) AS n_shots
            FROM shots
            INNER JOIN sessions ON sessions.session_id = shots.session_id
            WHERE shots.club = ?
            GROUP BY sessions.session_date, sessions.session_id
            ORDER BY sessions.session_date ASC, sessions.session_id ASC
            """
        
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: sql, arguments: [club])
            return rows.map { row in
                TrendPoint(
                    sessionDate: row["session_date"],
                    sessionId: row["session_id"],
                    metric: metric,
                    meanValue: row["mean_value"],
                    nShots: row["n_shots"],
                    templateHash: nil
                )
            }
        }
    }
    
    // MARK: aOnly (Swift-computed, pinned template)

    /// Phase 4B v2 semantics:
    /// - Use template_hash persisted in club_subsessions at analysis time
    /// - Never resolves "latest template" — historical points are stable
    /// - Sessions without a club_subsessions row are excluded
    private func fetchAOnlyTrendPoints(club: String,
                                       metric: TrendMetric) throws -> [TrendPoint] {
        // Phase 4B v2: sessions with persisted analysis context
        struct SessionContext {
            let sessionDate: String
            let sessionId: Int64
            let templateHash: String
        }

        let sessionContexts: [SessionContext] = try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT sessions.session_date, sessions.session_id, cs.kpi_template_hash
                FROM club_subsessions cs
                INNER JOIN sessions ON sessions.session_id = cs.session_id
                WHERE cs.club = ?
                ORDER BY sessions.session_date ASC, sessions.session_id ASC
                """, arguments: [club])
            return rows.map {
                SessionContext(sessionDate: $0["session_date"],
                              sessionId: $0["session_id"],
                              templateHash: $0["kpi_template_hash"])
            }
        }

        guard !sessionContexts.isEmpty else { return [] }

        // Fetch each unique template once
        let uniqueHashes = Set(sessionContexts.map { $0.templateHash })
        var templates: [String: KPITemplate] = [:]
        for hash in uniqueHashes {
            guard let record = try templateRepository.fetchTemplate(byHash: hash),
                  let data = record.canonicalJSON.data(using: .utf8) else {
                continue
            }
            templates[hash] = try JSONDecoder().decode(KPITemplate.self, from: data)
        }

        // Fetch all shots for these sessions in one query
        let sessionIds = sessionContexts.map { $0.sessionId }
        let placeholders = Array(repeating: "?", count: sessionIds.count).joined(separator: ",")
        let sql = """
            SELECT
                shots.shot_id, shots.session_id, shots.source_row_index,
                shots.source_format, shots.imported_at, shots.raw_json,
                shots.club, shots.carry, shots.ball_speed,
                shots.smash_factor, shots.spin_rate, shots.descent_angle
            FROM shots
            WHERE shots.club = ?
              AND shots.session_id IN (\(placeholders))
            ORDER BY shots.session_id ASC, shots.source_row_index ASC
            """

        var shotArgs: [DatabaseValueConvertible] = [club]
        shotArgs.append(contentsOf: sessionIds)

        let rows = try dbQueue.read { db in
            try Row.fetchAll(db, sql: sql, arguments: StatementArguments(shotArgs))
        }

        var shotsBySession: [Int64: [ShotRecord]] = [:]
        for row in rows {
            let shot = ShotRecord(
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
            shotsBySession[shot.sessionId, default: []].append(shot)
        }

        return try sessionContexts.compactMap { context in
            guard let template = templates[context.templateHash] else { return nil }

            let shots = shotsBySession[context.sessionId] ?? []
            let classifications = try ShotClassifier.classify(shots, using: template)
            let aShotIds = Set(classifications.filter { $0.grade == .a }.map { $0.shotId })

            let aMetricValues = shots
                .filter { aShotIds.contains($0.shotId) }
                .compactMap { shotMetricValue($0, metric: metric) }

            let mean: Double? = aMetricValues.isEmpty
                ? nil
                : aMetricValues.reduce(0.0, +) / Double(aMetricValues.count)

            return TrendPoint(
                sessionDate: context.sessionDate,
                sessionId: context.sessionId,
                metric: metric,
                meanValue: mean,
                nShots: aMetricValues.count,
                templateHash: context.templateHash
            )
        }
    }
    
    private func shotMetricValue(_ shot: ShotRecord, metric: TrendMetric) -> Double? {
        switch metric {
        case .carry: return shot.carry
        case .ballSpeed: return shot.ballSpeed
        case .spinRate: return shot.spinRate
        case .descentAngle: return shot.descentAngle
        }
    }
}

// MARK: - Subsession Record

struct SubsessionRecord {
    let subsessionId: Int64
    let sessionId: Int64
    let club: String
    let kpiTemplateHash: String
    let shotCount: Int
    let validityStatus: String
    let aCount: Int
    let bCount: Int
    let cCount: Int
    let aPercentage: Double?
    let avgCarry: Double?
    let avgBallSpeed: Double?
    let avgSpin: Double?
    let avgDescent: Double?
    let analyzedAt: String
}

// MARK: - Subsession Repository (Phase 4B v2)

class SubsessionRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    /// Create a club_subsessions record for a session+club+template.
    /// Performs classification and aggregation, persists the analysis context.
    /// Idempotent: UNIQUE(session_id, club, kpi_template_hash) silently ignores duplicates.
    func analyzeSessionClub(
        sessionId: Int64,
        club: String,
        shots: [ShotRecord],
        template: KPITemplate,
        templateHash: String
    ) throws {
        let classifications = try ShotClassifier.classify(shots, using: template)
        let shotCount = classifications.count

        guard shotCount > 0 else { return }

        let aCount = classifications.filter { $0.grade == .a }.count
        let bCount = classifications.filter { $0.grade == .b }.count
        let cCount = classifications.filter { $0.grade == .c }.count

        // Validity status (Phase D thresholds)
        let validityStatus: String
        if shotCount < 5 {
            validityStatus = "invalid_insufficient_data"
        } else if shotCount < 15 {
            validityStatus = "valid_low_sample_warning"
        } else {
            validityStatus = "valid"
        }

        // A percentage (nil when invalid)
        let aPercentage: Double?
        if validityStatus == "invalid_insufficient_data" {
            aPercentage = nil
        } else {
            aPercentage = Double(aCount) / Double(shotCount) * 100.0
        }

        // Average metrics for A-shots
        let aShotIds = Set(classifications.filter { $0.grade == .a }.map { $0.shotId })
        let aShots = shots.filter { aShotIds.contains($0.shotId) }
        let avgCarry = average(aShots.compactMap { $0.carry })
        let avgBallSpeed = average(aShots.compactMap { $0.ballSpeed })
        let avgSpin = average(aShots.compactMap { $0.spinRate })
        let avgDescent = average(aShots.compactMap { $0.descentAngle })

        let now = ISO8601DateFormatter().string(from: Date())

        try dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT OR IGNORE INTO club_subsessions
                    (session_id, club, kpi_template_hash, shot_count, validity_status,
                     a_count, b_count, c_count, a_percentage,
                     avg_carry, avg_ball_speed, avg_spin, avg_descent, analyzed_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    sessionId, club, templateHash, shotCount, validityStatus,
                    aCount, bCount, cCount, aPercentage,
                    avgCarry, avgBallSpeed, avgSpin, avgDescent, now
                ]
            )
        }
    }

    /// Fetch all subsession records for a session, ordered by club ASC, analyzed_at DESC
    /// - Parameter sessionId: Session ID to fetch subsessions for
    /// - Returns: Array of subsession records ordered by club ASC, analyzed_at DESC
    /// - Throws: Database error
    func fetchSubsessions(forSession sessionId: Int64) throws -> [SubsessionRecord] {
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT subsession_id, session_id, club, kpi_template_hash, shot_count,
                       validity_status, a_count, b_count, c_count, a_percentage,
                       avg_carry, avg_ball_speed, avg_spin, avg_descent, analyzed_at
                FROM club_subsessions
                WHERE session_id = ?
                ORDER BY club ASC, analyzed_at DESC
                """, arguments: [sessionId])

            return rows.map { row in
                SubsessionRecord(
                    subsessionId: row["subsession_id"],
                    sessionId: row["session_id"],
                    club: row["club"],
                    kpiTemplateHash: row["kpi_template_hash"],
                    shotCount: row["shot_count"],
                    validityStatus: row["validity_status"],
                    aCount: row["a_count"],
                    bCount: row["b_count"],
                    cCount: row["c_count"],
                    aPercentage: row["a_percentage"],
                    avgCarry: row["avg_carry"],
                    avgBallSpeed: row["avg_ball_speed"],
                    avgSpin: row["avg_spin"],
                    avgDescent: row["avg_descent"],
                    analyzedAt: row["analyzed_at"]
                )
            }
        }
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0.0, +) / Double(values.count)
    }
}
