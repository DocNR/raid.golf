// KPITemplate.swift
// Gambit Golf
//
// Typed KPI Template Model
//
// Purpose:
// - Strongly-typed representation of KPI template for classification
// - Avoids [String: Any] in classification logic
// - Parsed from canonical_json stored in database

import Foundation

/// Typed KPI template for shot classification
struct KPITemplate: Codable {
    let schemaVersion: String
    let club: String
    let aggregationMethod: String
    let metrics: [String: MetricThresholds]
    
    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case club
        case aggregationMethod = "aggregation_method"
        case metrics
    }
}

/// Thresholds for a single metric
struct MetricThresholds: Codable {
    let direction: Direction
    let aMin: Double?
    let bMin: Double?
    let aMax: Double?
    let bMax: Double?
    
    enum CodingKeys: String, CodingKey {
        case direction
        case aMin = "a_min"
        case bMin = "b_min"
        case aMax = "a_max"
        case bMax = "b_max"
    }
    
    enum Direction: String, Codable {
        case higherIsBetter = "higher_is_better"
        case lowerIsBetter = "lower_is_better"
    }
}

/// Shot grade (A/B/C)
enum ShotGrade: String {
    case a = "A"
    case b = "B"
    case c = "C"
    
    /// Worst grade comparison (C > B > A)
    static func worst(_ g1: ShotGrade, _ g2: ShotGrade) -> ShotGrade {
        if g1 == .c || g2 == .c { return .c }
        if g1 == .b || g2 == .b { return .b }
        return .a
    }
}
