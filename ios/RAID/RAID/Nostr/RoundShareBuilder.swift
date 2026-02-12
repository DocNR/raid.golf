// Gambit Golf — Round Share Builder
// Pure functions to format round data for sharing. No database queries.

import Foundation

enum RoundShareBuilder {

    /// Build a human-readable note for posting to Nostr (kind 1).
    ///
    /// - Parameters:
    ///   - course: Course name (e.g., "Fowler's Mill Golf Course")
    ///   - tees: Tee set label (e.g., "Silver M")
    ///   - holes: Hole definitions with par values
    ///   - scores: Resolved holeNumber → strokes map
    /// - Returns: Formatted note text with hashtags
    static func noteText(
        course: String,
        tees: String,
        holes: [CourseHoleRecord],
        scores: [Int: Int]
    ) -> String {
        let totalStrokes = holes.compactMap { scores[$0.holeNumber] }.reduce(0, +)
        let totalPar = holes.reduce(0) { $0 + $1.par }
        let scoreToPar = totalStrokes - totalPar
        let scoreToParText = formatScoreToPar(scoreToPar)

        let holeCount = holes.count

        if holeCount <= 9 {
            // 9-hole round — no front/back split
            let nineLabel = nineLabel(for: holes)
            return "Shot \(totalStrokes) on \(nineLabel) at \(course) (\(tees) tees) (\(scoreToParText))\n\n#golf #gambitgolf"
        }

        // 18-hole round — show front 9 / back 9 subtotals
        let front9 = holes.filter { $0.holeNumber <= 9 }
        let back9 = holes.filter { $0.holeNumber > 9 }

        let frontTotal = front9.compactMap { scores[$0.holeNumber] }.reduce(0, +)
        let backTotal = back9.compactMap { scores[$0.holeNumber] }.reduce(0, +)

        return "Shot \(totalStrokes) at \(course) (\(tees) tees) — Front 9: \(frontTotal), Back 9: \(backTotal) (\(scoreToParText))\n\n#golf #gambitgolf"
    }

    /// Build a plain-text summary for the share sheet / clipboard.
    static func summaryText(
        course: String,
        tees: String,
        date: String,
        holes: [CourseHoleRecord],
        scores: [Int: Int]
    ) -> String {
        let totalStrokes = holes.compactMap { scores[$0.holeNumber] }.reduce(0, +)
        let totalPar = holes.reduce(0) { $0 + $1.par }
        let scoreToPar = totalStrokes - totalPar
        let scoreToParText = formatScoreToPar(scoreToPar)

        var lines: [String] = []
        lines.append("Gambit Golf — Round Summary")
        lines.append("")
        lines.append("Course: \(course)")
        lines.append("Tees: \(tees)")
        lines.append("Date: \(date)")
        lines.append("Holes: \(holes.count)")
        lines.append("")

        // Hole-by-hole
        for hole in holes.sorted(by: { $0.holeNumber < $1.holeNumber }) {
            let strokes = scores[hole.holeNumber].map(String.init) ?? "-"
            lines.append("Hole \(hole.holeNumber): Par \(hole.par), Score \(strokes)")
        }

        lines.append("")
        lines.append("Total: \(totalStrokes) (Par \(totalPar), \(scoreToParText))")

        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private static func formatScoreToPar(_ scoreToPar: Int) -> String {
        if scoreToPar == 0 { return "Even" }
        if scoreToPar > 0 { return "+\(scoreToPar)" }
        return "\(scoreToPar)"
    }

    private static func nineLabel(for holes: [CourseHoleRecord]) -> String {
        let minHole = holes.map(\.holeNumber).min() ?? 1
        if minHole <= 1 { return "the Front 9" }
        return "the Back 9"
    }
}
