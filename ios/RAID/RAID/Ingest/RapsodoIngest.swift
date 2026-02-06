// RapsodoIngest.swift
// RAID Golf - iOS Port
//
// Phase 3: CSV Parsing and Session Ingest
//
// Purpose:
// - Parse Rapsodo MLM2 Pro CSV exports
// - Header detection (rows 1-3)
// - Footer exclusion (Average, Std. Dev.)
// - Multi-club session support
// - Shot classification (worst_metric aggregation)
//
// Reference: raid/ingest.py, docs/PRD_Phase_0_MVP.md

import Foundation

/// Rapsodo CSV parser and session ingester
struct RapsodoIngest {
    // TODO: Phase 3 - Implement Rapsodo CSV parsing
    // See: docs/PRD_Phase_0_MVP.md
    // Reference: raid/ingest.py
    
    /// Parse a Rapsodo CSV file
    /// - Parameter csvURL: URL to the CSV file
    /// - Returns: Parsed session data ready for persistence
    /// - Throws: Parsing error if CSV is malformed
    static func parse(csvURL: URL) throws -> ParsedSession {
        // TODO: Implement
        // 1. Detect headers (rows 1-3)
        // 2. Filter out footer rows (Average, Std. Dev.)
        // 3. Parse shot rows
        // 4. Classify shots (A/B/C) using KPI template
        // 5. Group by club
        fatalError("Not implemented - Phase 3")
    }
}

/// Intermediate structure for parsed session data
struct ParsedSession {
    // TODO: Define structure for parsed data
    // - session metadata
    // - club subsessions with shot counts
    // - classification results
}