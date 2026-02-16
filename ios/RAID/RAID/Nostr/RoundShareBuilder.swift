// RAID Golf — Round Share Builder
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
            return "Shot \(totalStrokes) on \(nineLabel) at \(course) (\(tees) tees) (\(scoreToParText))\n\n#golf #raidgolf"
        }

        // 18-hole round — show front 9 / back 9 subtotals
        let front9 = holes.filter { $0.holeNumber <= 9 }
        let back9 = holes.filter { $0.holeNumber > 9 }

        let frontTotal = front9.compactMap { scores[$0.holeNumber] }.reduce(0, +)
        let backTotal = back9.compactMap { scores[$0.holeNumber] }.reduce(0, +)

        return "Shot \(totalStrokes) at \(course) (\(tees) tees) — Front 9: \(frontTotal), Back 9: \(backTotal) (\(scoreToParText))\n\n#golf #raidgolf"
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
        lines.append("RAID Golf — Round Summary")
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

    // MARK: - Multi-Player Variants

    /// Build a human-readable note for posting to Nostr (kind 1) — multiplayer.
    static func noteText(
        course: String,
        tees: String,
        holes: [CourseHoleRecord],
        playerScores: [(label: String, scores: [Int: Int])]
    ) -> String {
        let totalPar = holes.reduce(0) { $0 + $1.par }
        let holeCount = holes.count

        let scoreSummaries = playerScores.map { player in
            let total = holes.compactMap { player.scores[$0.holeNumber] }.reduce(0, +)
            let diff = total - totalPar
            return "\(player.label): \(total) (\(formatScoreToPar(diff)))"
        }

        let totals = playerScores.map { player in
            String(holes.compactMap { player.scores[$0.holeNumber] }.reduce(0, +))
        }

        if holeCount <= 9 {
            let label = nineLabel(for: holes)
            return "Shot \(totals.joined(separator: "/")) on \(label) at \(course) (\(tees) tees) — \(scoreSummaries.joined(separator: ", "))\n\n#golf #raidgolf"
        }

        return "Shot \(totals.joined(separator: "/")) at \(course) (\(tees) tees) — \(scoreSummaries.joined(separator: ", "))\n\n#golf #raidgolf"
    }

    /// Build a plain-text summary for the share sheet / clipboard — multiplayer.
    static func summaryText(
        course: String,
        tees: String,
        date: String,
        holes: [CourseHoleRecord],
        playerScores: [(label: String, scores: [Int: Int])]
    ) -> String {
        let totalPar = holes.reduce(0) { $0 + $1.par }

        var lines: [String] = []
        lines.append("RAID Golf — Round Summary")
        lines.append("")
        lines.append("Course: \(course)")
        lines.append("Tees: \(tees)")
        lines.append("Date: \(date)")
        lines.append("Holes: \(holes.count)")
        lines.append("Players: \(playerScores.count)")
        lines.append("")

        let playerLabels = playerScores.map(\.label).joined(separator: "/")
        for hole in holes.sorted(by: { $0.holeNumber < $1.holeNumber }) {
            let strokesText = playerScores.map { player in
                player.scores[hole.holeNumber].map(String.init) ?? "-"
            }.joined(separator: "/")
            lines.append("Hole \(hole.holeNumber): Par \(hole.par), Scores (\(playerLabels)) \(strokesText)")
        }

        lines.append("")
        for player in playerScores {
            let total = holes.compactMap { player.scores[$0.holeNumber] }.reduce(0, +)
            let diff = total - totalPar
            lines.append("\(player.label) Total: \(total) (Par \(totalPar), \(formatScoreToPar(diff)))")
        }

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
