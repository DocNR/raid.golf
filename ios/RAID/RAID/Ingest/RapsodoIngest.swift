// RapsodoIngest.swift
// RAID Golf
//
// CSV Parsing and Session Ingest
//
// Purpose:
// - Parse Rapsodo MLM2 Pro CSV exports
// - Header detection (rows 1-3)
// - Footer exclusion (Average, Std. Dev.)
// - Multi-club session support
// - Persist session + shots to database
//
// Reference: raid/ingest.py, docs/PRD_Phase_0_MVP.md
//
// source_row_index semantics:
// - 0-based index among imported shot rows (not raw CSV line number)
// - First valid shot row after header = index 0
// - Footer rows excluded from indexing

import Foundation

/// Rapsodo CSV parser and session ingester
struct RapsodoIngest {
    
    /// Ingest a Rapsodo CSV file into the database
    /// - Parameters:
    ///   - csvURL: URL to the CSV file
    ///   - sessionRepository: Session repository
    ///   - shotRepository: Shot repository
    ///   - sessionDate: ISO-8601 session date (defaults to now)
    ///   - deviceType: Device type string (default: "Rapsodo MLM2Pro")
    ///   - location: Practice location (optional)
    /// - Returns: IngestResult with session ID, imported count, and skipped count
    /// - Throws: Parsing error if CSV is malformed
    static func ingest(
        csvURL: URL,
        sessionRepository: SessionRepository,
        shotRepository: ShotRepository,
        sessionDate: String? = nil,
        deviceType: String = "Rapsodo MLM2Pro",
        location: String? = nil
    ) throws -> IngestResult {
        // Parse CSV with skipped row tracking
        let parseResult = try parseCSV(csvURL: csvURL)
        
        // Create session
        let sourceFile = csvURL.lastPathComponent
        let finalSessionDate = sessionDate ?? ISO8601DateFormatter().string(from: Date())
        
        let sessionRecord = try sessionRepository.insertSession(
            sessionDate: finalSessionDate,
            sourceFile: sourceFile,
            deviceType: deviceType,
            location: location
        )
        
        // Prepare shots for batch insert
        var shotsForInsert: [ShotInsertData] = []

        for (index, shot) in parseResult.shots.enumerated() {
            // Encode raw JSON
            guard let rawJSON = try? JSONSerialization.data(withJSONObject: shot.rawDict, options: []),
                  let rawJSONString = String(data: rawJSON, encoding: .utf8) else {
                throw IngestError.jsonEncodingFailed("Failed to encode shot at index \(index)")
            }

            shotsForInsert.append(ShotInsertData(
                rowIndex: index,
                club: shot.club,
                rawJSON: rawJSONString,
                carry: shot.carry,
                ballSpeed: shot.ballSpeed,
                smashFactor: shot.smashFactor,
                spinRate: shot.spinRate,
                descentAngle: shot.descentAngle,
                totalDistance: shot.totalDistance,
                launchAngle: shot.launchAngle,
                launchDirection: shot.launchDirection,
                apex: shot.apex,
                sideCarry: shot.sideCarry,
                clubSpeed: shot.clubSpeed,
                attackAngle: shot.attackAngle,
                clubPath: shot.clubPath,
                spinAxis: shot.spinAxis
            ))
        }
        
        // Batch insert shots
        try shotRepository.insertShots(
            shotsForInsert,
            sessionId: sessionRecord.sessionId,
            sourceFormat: "rapsodo_mlm2pro_shotexport_v1"
        )
        
        return IngestResult(
            sessionId: sessionRecord.sessionId,
            importedCount: parseResult.shots.count,
            skippedCount: parseResult.skippedCount
        )
    }
    
    /// Parse Rapsodo CSV file
    /// - Parameter csvURL: URL to CSV file
    /// - Returns: ParseResult with shots and skipped count
    /// - Throws: Parsing error
    private static func parseCSV(csvURL: URL) throws -> ParseResult {
        let csvString = try String(contentsOf: csvURL, encoding: .utf8)
        let lines = csvString.components(separatedBy: .newlines)
        
        // Find header (search rows 0-2, 0-indexed)
        var headerRow: [String]?
        var headerIndex: Int?
        
        for (index, line) in lines.prefix(3).enumerated() {
            let row = parseCSVLine(line)
            if isHeaderRow(row) {
                headerRow = row
                headerIndex = index
                break
            }
        }
        
        guard let header = headerRow, let headerIdx = headerIndex else {
            throw IngestError.headerNotFound
        }
        
        // Build column map
        let columnMap = buildColumnMap(header: header)
        
        // Parse data rows (skip header + 1)
        var shots: [ParsedShot] = []
        var skippedCount = 0
        
        for line in lines.dropFirst(headerIdx + 1) {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                continue
            }
            
            let row = parseCSVLine(line)
            
            // Skip footer rows
            if isFooterRow(row) {
                continue
            }
            
            // Try to parse shot
            if let shot = try? parseShot(row: row, columnMap: columnMap) {
                shots.append(shot)
            } else {
                // Track skipped/malformed rows
                skippedCount += 1
            }
        }
        
        return ParseResult(shots: shots, skippedCount: skippedCount)
    }
    
    /// Check if row is a header row
    private static func isHeaderRow(_ row: [String]) -> Bool {
        let requiredColumns: Set<String> = ["Club Type", "Ball Speed", "Smash Factor", "Spin Rate", "Descent Angle"]
        let rowSet = Set(row.map { $0.trimmingCharacters(in: .whitespaces) })
        return requiredColumns.isSubset(of: rowSet)
    }
    
    /// Check if row is a footer row
    private static func isFooterRow(_ row: [String]) -> Bool {
        guard let firstCell = row.first else { return false }
        let trimmed = firstCell.trimmingCharacters(in: .whitespaces)
        return trimmed == "Average" || trimmed == "Std. Dev." || trimmed == "Std Dev"
    }
    
    /// Build column name → index mapping
    private static func buildColumnMap(header: [String]) -> [String: Int] {
        var map: [String: Int] = [:]
        
        let mappings: [String: String] = [
            "Club Type": "club",
            "Carry Distance": "carry",
            "Ball Speed": "ball_speed",
            "Smash Factor": "smash_factor",
            "Spin Rate": "spin_rate",
            "Descent Angle": "descent_angle",
            "Total Distance": "total_distance",
            "Launch Angle": "launch_angle",
            "Launch Direction": "launch_direction",
            "Apex": "apex",
            "Side Carry": "side_carry",
            "Club Speed": "club_speed",
            "Attack Angle": "attack_angle",
            "Club Path": "club_path",
            "Spin Axis": "spin_axis"
        ]
        
        for (index, col) in header.enumerated() {
            let trimmed = col.trimmingCharacters(in: .whitespaces)
            if let metricName = mappings[trimmed] {
                map[metricName] = index
            }
        }
        
        return map
    }
    
    /// Parse a single shot row
    private static func parseShot(row: [String], columnMap: [String: Int]) throws -> ParsedShot {
        guard let clubIdx = columnMap["club"] else {
            throw IngestError.missingColumn("club")
        }
        
        // TODO(B-001): Normalize club name here (e.g. "7 Iron" → "7i") once alias table exists
        let club = row[clubIdx].trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        
        // Parse numeric fields (all optional except club)
        let carry = parseDouble(row: row, columnMap: columnMap, key: "carry")
        let ballSpeed = parseDouble(row: row, columnMap: columnMap, key: "ball_speed")
        let smashFactor = parseDouble(row: row, columnMap: columnMap, key: "smash_factor")
        let spinRate = parseDouble(row: row, columnMap: columnMap, key: "spin_rate")
        let descentAngle = parseDouble(row: row, columnMap: columnMap, key: "descent_angle")
        let totalDistance = parseDouble(row: row, columnMap: columnMap, key: "total_distance")
        let launchAngle = parseDouble(row: row, columnMap: columnMap, key: "launch_angle")
        let launchDirection = parseDouble(row: row, columnMap: columnMap, key: "launch_direction")
        let apex = parseDouble(row: row, columnMap: columnMap, key: "apex")
        let sideCarry = parseDouble(row: row, columnMap: columnMap, key: "side_carry")
        let clubSpeed = parseDouble(row: row, columnMap: columnMap, key: "club_speed")
        let attackAngle = parseDouble(row: row, columnMap: columnMap, key: "attack_angle")
        let clubPath = parseDouble(row: row, columnMap: columnMap, key: "club_path")
        let spinAxis = parseDouble(row: row, columnMap: columnMap, key: "spin_axis")
        
        // Build raw dict for JSON storage
        var rawDict: [String: Any] = ["club": club]
        if let v = carry { rawDict["carry"] = v }
        if let v = ballSpeed { rawDict["ball_speed"] = v }
        if let v = smashFactor { rawDict["smash_factor"] = v }
        if let v = spinRate { rawDict["spin_rate"] = v }
        if let v = descentAngle { rawDict["descent_angle"] = v }
        if let v = totalDistance { rawDict["total_distance"] = v }
        if let v = launchAngle { rawDict["launch_angle"] = v }
        if let v = launchDirection { rawDict["launch_direction"] = v }
        if let v = apex { rawDict["apex"] = v }
        if let v = sideCarry { rawDict["side_carry"] = v }
        if let v = clubSpeed { rawDict["club_speed"] = v }
        if let v = attackAngle { rawDict["attack_angle"] = v }
        if let v = clubPath { rawDict["club_path"] = v }
        if let v = spinAxis { rawDict["spin_axis"] = v }
        
        return ParsedShot(
            club: club,
            carry: carry,
            ballSpeed: ballSpeed,
            smashFactor: smashFactor,
            spinRate: spinRate,
            descentAngle: descentAngle,
            totalDistance: totalDistance,
            launchAngle: launchAngle,
            launchDirection: launchDirection,
            apex: apex,
            sideCarry: sideCarry,
            clubSpeed: clubSpeed,
            attackAngle: attackAngle,
            clubPath: clubPath,
            spinAxis: spinAxis,
            rawDict: rawDict
        )
    }
    
    /// Parse double from row
    private static func parseDouble(row: [String], columnMap: [String: Int], key: String) -> Double? {
        guard let idx = columnMap[key], idx < row.count else { return nil }
        let cell = row[idx].trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return Double(cell)
    }
    
    /// Parse CSV line (simple comma-split, handles quoted fields)
    private static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var currentField = ""
        var inQuotes = false
        
        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(currentField)
                currentField = ""
            } else {
                currentField.append(char)
            }
        }
        fields.append(currentField)
        
        return fields
    }
}

/// Parsed shot (intermediate structure)
struct ParsedShot {
    let club: String
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
    let rawDict: [String: Any]
}

/// Parse result with skipped row tracking
struct ParseResult {
    let shots: [ParsedShot]
    let skippedCount: Int
}

/// Ingest errors
enum IngestError: Error {
    case headerNotFound
    case missingColumn(String)
    case jsonEncodingFailed(String)
}

/// Ingest result with skipped row count
struct IngestResult {
    let sessionId: Int64
    let importedCount: Int
    let skippedCount: Int
}
