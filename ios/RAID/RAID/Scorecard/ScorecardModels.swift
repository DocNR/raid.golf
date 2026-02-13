// ScorecardModels.swift
// Gambit Golf
//
// Data models for the scorecard domain (kernel-adjacent).
// Insert types for write path, Record types for read path.

import Foundation

// MARK: - Insert Types

/// Input for creating a course snapshot (content-addressed)
struct CourseSnapshotInput {
    let courseName: String
    let teeSet: String
    let holes: [HoleDefinition]
}

/// Per-hole definition for a course snapshot
struct HoleDefinition {
    let holeNumber: Int
    let par: Int
}

/// Input for recording a hole score (append-only)
struct HoleScoreInput {
    let holeNumber: Int
    let strokes: Int
}

// MARK: - Read Types

/// Stored course snapshot record
struct CourseSnapshotRecord {
    let courseHash: String
    let courseName: String
    let teeSet: String
    let holeCount: Int
    let canonicalJSON: String
    let createdAt: String
}

/// Stored course hole definition (normalized from snapshot)
struct CourseHoleRecord {
    let courseHash: String
    let holeNumber: Int
    let par: Int
    let handicapIndex: Int?
}

/// Stored round record (immutable creation row)
struct RoundRecord {
    let roundId: Int64
    let courseHash: String
    let roundDate: String
    let createdAt: String
}

/// Round list item (joined query result for display)
struct RoundListItem {
    let roundId: Int64
    let courseName: String
    let teeSet: String
    let roundDate: String
    let holeCount: Int
    let isCompleted: Bool
    let totalStrokes: Int?
    let holesScored: Int
}

/// Stored hole score record (latest-wins resolved)
struct HoleScoreRecord {
    let scoreId: Int64
    let roundId: Int64
    let playerIndex: Int
    let holeNumber: Int
    let strokes: Int
    let recordedAt: String
}

/// Stored round player record (immutable, ordered by player_index)
struct RoundPlayerRecord {
    let roundId: Int64
    let playerPubkey: String
    let playerIndex: Int
    let addedAt: String
}

/// Stored round Nostr metadata (initiation event ID, one per round)
struct RoundNostrRecord {
    let roundId: Int64
    let initiationEventId: String
    let publishedAt: String
}
