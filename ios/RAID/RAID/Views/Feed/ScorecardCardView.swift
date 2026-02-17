// ScorecardCardView.swift
// RAID Golf
//
// Rich scorecard card for feed items. Shows course, score, and par delta.

import SwiftUI

struct ScorecardCardView: View {
    let record: FinalRecordData
    let courseInfo: CourseSnapshotContent?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Course name + tee set
            HStack {
                Text(courseInfo?.courseName ?? "Golf Round")
                    .font(.subheadline.weight(.semibold))
                if let tees = courseInfo?.teeSet {
                    Text("(\(tees))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            // Total score + par delta
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(record.total)")
                    .font(.title.weight(.bold))

                if let parDelta = scoreToPar {
                    Text(formatScoreToPar(parDelta))
                        .font(.title3.weight(.medium))
                        .foregroundStyle(parDeltaColor(parDelta))
                }

                Spacer()

                // Hole count badge
                if let holeCount = courseInfo?.holeCount {
                    Text("\(holeCount) holes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Front 9 / Back 9 subtotals for 18-hole rounds
            if let courseInfo, courseInfo.holeCount > 9 {
                let (front, back) = nineSubtotals
                HStack(spacing: 16) {
                    Label("Front 9: \(front)", systemImage: "flag")
                    Label("Back 9: \(back)", systemImage: "flag.fill")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Computed

    private var scoreToPar: Int? {
        guard let courseInfo else { return nil }
        let totalPar = courseInfo.holes.reduce(0) { $0 + $1.par }
        guard totalPar > 0 else { return nil }
        return record.total - totalPar
    }

    private var nineSubtotals: (front: Int, back: Int) {
        let front = record.scores.filter { $0.holeNumber <= 9 }.reduce(0) { $0 + $1.strokes }
        let back = record.scores.filter { $0.holeNumber > 9 }.reduce(0) { $0 + $1.strokes }
        return (front, back)
    }

    private func formatScoreToPar(_ delta: Int) -> String {
        if delta == 0 { return "Even" }
        if delta > 0 { return "+\(delta)" }
        return "\(delta)"
    }

    private func parDeltaColor(_ delta: Int) -> Color {
        if delta < 0 { return .red }
        if delta == 0 { return .primary }
        return .primary
    }
}
