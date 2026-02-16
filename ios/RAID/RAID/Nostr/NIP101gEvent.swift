// RAID Golf — NIP-101g Event Data Structures
// Pure data models for round initiation and final record content.
// See: docs/nips/nip101g_round_wip.md

import Foundation

// MARK: - Round Initiation Content (kind 1501)

/// JSON content embedded in a Round Initiation event.
/// The embedded snapshot is authoritative — any 33501 reference is informational only.
struct RoundInitiationContent: Codable, Equatable {
    let courseSnapshot: CourseSnapshotContent
    let rulesTemplate: RulesTemplateContent

    enum CodingKeys: String, CodingKey {
        case courseSnapshot = "course_snapshot"
        case rulesTemplate = "rules_template"
    }
}

/// Authoritative course snapshot for a round.
/// Matches the NIP-101g WIP spec: course_name, tee_set, hole_count, holes.
struct CourseSnapshotContent: Codable, Equatable {
    let courseName: String
    let teeSet: String
    let holeCount: Int
    let holes: [NIP101gHoleDefinition]

    enum CodingKeys: String, CodingKey {
        case courseName = "course_name"
        case teeSet = "tee_set"
        case holeCount = "hole_count"
        case holes
    }
}

/// Per-hole definition in a NIP-101g course snapshot.
/// Separate from ScorecardModels.HoleDefinition to include handicap_index.
struct NIP101gHoleDefinition: Codable, Equatable {
    let holeNumber: Int
    let par: Int
    let handicapIndex: Int?

    enum CodingKeys: String, CodingKey {
        case holeNumber = "hole_number"
        case par
        case handicapIndex = "handicap_index"
    }

    /// Always encode handicap_index (as null when nil) to match
    /// CourseSnapshotRepository's canonical JSON which uses NSNull().
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(holeNumber, forKey: .holeNumber)
        try container.encode(par, forKey: .par)
        try container.encode(handicapIndex, forKey: .handicapIndex)
    }
}

/// Rules template for a round. MVP: stroke play only.
struct RulesTemplateContent: Codable, Equatable {
    let format: String
}
