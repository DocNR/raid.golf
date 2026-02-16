// ShotClassifier.swift
// RAID Golf
//
// Pure Shot Classification Logic
//
// Purpose:
// - Pure function: shots × template → classifications
// - No database writes, no side effects
// - Fully deterministic
//
// Edge Cases (locked semantics):
// - Missing required metric in shot → treat as C (conservative)
// - Metric not in template → ignore (not evaluated)
// - Overall grade = worst of evaluated metrics

import Foundation

/// Classification errors
enum ClassifierError: Error {
    case unsupportedAggregation(String)
}

/// Pure shot classifier (no side effects)
struct ShotClassifier {
    
    /// Classify shots using worst_metric aggregation
    /// - Parameters:
    ///   - shots: Array of shot records
    ///   - template: KPI template with metric thresholds
    /// - Returns: Array of shot classifications
    /// - Throws: ClassifierError if aggregation method is unsupported
    static func classify(_ shots: [ShotRecord], using template: KPITemplate) throws -> [ShotClassification] {
        guard template.aggregationMethod == "worst_metric" else {
            throw ClassifierError.unsupportedAggregation(template.aggregationMethod)
        }
        
        return shots.map { shot in
            let grade = classifyShot(shot, using: template)
            return ShotClassification(shotId: shot.shotId, grade: grade)
        }
    }
    
    /// Classify a single shot
    private static func classifyShot(_ shot: ShotRecord, using template: KPITemplate) -> ShotGrade {
        var worstGrade: ShotGrade = .a
        
        // Evaluate each metric in template
        for (metricName, thresholds) in template.metrics {
            // Get shot value for this metric
            let metricValue = getMetricValue(from: shot, metricName: metricName)
            
            // Unknown metric key → ignore (not evaluated)
            if !metricValue.supported {
                continue
            }
            
            // Supported metric but missing value → conservative C
            guard let value = metricValue.value else {
                worstGrade = .c
                continue
            }
            
            // Grade this metric
            let grade = gradeMetric(value: value, thresholds: thresholds)
            
            // Update worst grade
            worstGrade = ShotGrade.worst(worstGrade, grade)
        }
        
        return worstGrade
    }
    
    /// Extract metric value from shot record
    /// - Returns: (supported: Bool, value: Double?) tuple
    ///   - supported=false: unknown metric key → ignore (not evaluated)
    ///   - supported=true, value=nil: known metric but missing value → conservative C
    ///   - supported=true, value=X: known metric with value → grade normally
    private static func getMetricValue(from shot: ShotRecord, metricName: String) -> (supported: Bool, value: Double?) {
        switch metricName {
        case "ball_speed":
            return (true, shot.ballSpeed)
        case "smash_factor":
            return (true, shot.smashFactor)
        case "spin_rate":
            return (true, shot.spinRate)
        case "descent_angle":
            return (true, shot.descentAngle)
        case "carry":
            return (true, shot.carry)
        default:
            // Unknown metric key → not supported by app schema
            return (false, nil)
        }
    }
    
    /// Grade a single metric value
    private static func gradeMetric(value: Double, thresholds: MetricThresholds) -> ShotGrade {
        switch thresholds.direction {
        case .higherIsBetter:
            // A: value >= a_min
            // B: b_min <= value < a_min
            // C: value < b_min
            if let aMin = thresholds.aMin, value >= aMin {
                return .a
            }
            if let bMin = thresholds.bMin, value >= bMin {
                return .b
            }
            return .c
            
        case .lowerIsBetter:
            // A: value <= a_max
            // B: a_max < value <= b_max
            // C: value > b_max
            if let aMax = thresholds.aMax, value <= aMax {
                return .a
            }
            if let bMax = thresholds.bMax, value <= bMax {
                return .b
            }
            return .c
        }
    }
    
    /// Aggregate classifications into summary statistics
    /// - Parameter classifications: Array of shot classifications
    /// - Returns: Summary with counts and percentages
    static func aggregate(_ classifications: [ShotClassification], shots: [ShotRecord]) -> ClassificationSummary {
        let totalShots = classifications.count
        
        let aCount = classifications.filter { $0.grade == .a }.count
        let bCount = classifications.filter { $0.grade == .b }.count
        let cCount = classifications.filter { $0.grade == .c }.count
        
        // A percentage (nil if < 5 shots)
        let aPercentage: Double? = totalShots >= 5 ? (Double(aCount) / Double(totalShots) * 100.0) : nil
        
        // Compute averages for A-shots only
        let aShotIds = Set(classifications.filter { $0.grade == .a }.map { $0.shotId })
        let aShots = shots.filter { aShotIds.contains($0.shotId) }
        
        let avgCarry = computeAverage(aShots.compactMap { $0.carry })
        let avgBallSpeed = computeAverage(aShots.compactMap { $0.ballSpeed })
        let avgSpin = computeAverage(aShots.compactMap { $0.spinRate })
        let avgDescent = computeAverage(aShots.compactMap { $0.descentAngle })
        
        return ClassificationSummary(
            totalShots: totalShots,
            aCount: aCount,
            bCount: bCount,
            cCount: cCount,
            aPercentage: aPercentage,
            avgCarry: avgCarry,
            avgBallSpeed: avgBallSpeed,
            avgSpin: avgSpin,
            avgDescent: avgDescent
        )
    }
    
    /// Compute average of non-nil values
    private static func computeAverage(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0.0, +) / Double(values.count)
    }
}

/// Shot classification result
struct ShotClassification {
    let shotId: Int64
    let grade: ShotGrade
}

/// Classification summary (derived, not persisted)
struct ClassificationSummary {
    let totalShots: Int
    let aCount: Int
    let bCount: Int
    let cCount: Int
    let aPercentage: Double?  // nil if < 5 shots
    let avgCarry: Double?
    let avgBallSpeed: Double?
    let avgSpin: Double?
    let avgDescent: Double?
}
