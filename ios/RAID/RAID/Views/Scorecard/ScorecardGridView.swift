// ScorecardGridView.swift
// RAID Golf
//
// Classic golf scorecard grid with horizontal scroll.
// Rows: Hole#, Par, SI, Player scores. Columns: holes + OUT/IN/TOTAL.
// Used in RoundDetailView, RoundReviewView, LiveScorecardSheet, and as
// the mini-card header in ScoreEntryView.

import SwiftUI

/// Full classic golf scorecard grid.
/// Displays holes as columns with par, stroke index, and player score rows.
struct ScorecardGridView: View {
    let holes: [CourseHoleRecord]
    /// playerIndex -> (holeNumber -> strokes)
    let scores: [Int: [Int: Int]]
    let playerLabels: [Int: String]

    /// Current hole index for highlighting (nil = no highlight, e.g. read-only views)
    var currentHoleIndex: Int? = nil

    /// Which player index is currently selected (for highlight in multiplayer)
    var currentPlayerIndex: Int = 0

    /// Callback when a hole column is tapped (nil = non-interactive)
    var onHoleTap: ((Int) -> Void)? = nil

    /// Remote player indices (shown with dimmed treatment)
    var remotePlayerIndices: Set<Int> = []

    private var is18Hole: Bool { holes.count > 9 }
    private var frontNine: [CourseHoleRecord] { Array(holes.prefix(9)) }
    private var backNine: [CourseHoleRecord] { is18Hole ? Array(holes.suffix(from: 9)) : [] }

    private var sortedPlayerIndices: [Int] {
        playerLabels.keys.sorted()
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(spacing: 0) {
                // Hole number row
                gridRow(label: "HOLE", labelStyle: .header) { nine, isFront in
                    ForEach(nine, id: \.holeNumber) { hole in
                        holeHeaderCell(hole: hole)
                    }
                    summaryHeaderCell(text: isFront ? "OUT" : (is18Hole ? "IN" : "TOT"))
                } totalCell: {
                    if is18Hole {
                        summaryHeaderCell(text: "TOT")
                    }
                }

                Divider()

                // Par row
                gridRow(label: "Par", labelStyle: .subheader) { nine, isFront in
                    ForEach(nine, id: \.holeNumber) { hole in
                        valueCell(text: "\(hole.par)")
                    }
                    let ninePar = nine.reduce(0) { $0 + $1.par }
                    summaryValueCell(text: "\(ninePar)")
                } totalCell: {
                    if is18Hole {
                        let totalPar = holes.reduce(0) { $0 + $1.par }
                        summaryValueCell(text: "\(totalPar)")
                    }
                }

                // SI (Stroke Index) row — show if any hole has a handicap index
                if holes.contains(where: { $0.handicapIndex != nil }) {
                    Divider()
                    gridRow(label: "SI", labelStyle: .subheader) { nine, _ in
                        ForEach(nine, id: \.holeNumber) { hole in
                            valueCell(text: hole.handicapIndex.map { "\($0)" } ?? "--", dimmed: true)
                        }
                        emptySummaryCell()
                    } totalCell: {
                        if is18Hole {
                            emptySummaryCell()
                        }
                    }
                }

                // Player score rows
                ForEach(sortedPlayerIndices, id: \.self) { playerIndex in
                    Divider()
                    playerRow(playerIndex: playerIndex)
                }
            }
            .padding(.vertical, 4)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: ScorecardLayout.miniCardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: ScorecardLayout.miniCardCornerRadius)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
    }

    // MARK: - Row Builders

    /// Generic grid row: label + front nine cells + [back nine cells] + [total cell]
    private func gridRow<Content: View, TotalContent: View>(
        label: String,
        labelStyle: LabelStyle,
        @ViewBuilder cells: (_ nine: [CourseHoleRecord], _ isFront: Bool) -> Content,
        @ViewBuilder totalCell: () -> TotalContent
    ) -> some View {
        HStack(spacing: 0) {
            // Row label
            Text(label)
                .font(labelStyle.font)
                .foregroundStyle(labelStyle.color)
                .frame(width: ScorecardLayout.rowLabelWidth, alignment: .leading)
                .padding(.horizontal, ScorecardLayout.cellHPadding)
                .padding(.vertical, ScorecardLayout.cellVPadding)

            // Front 9 (or only 9)
            cells(frontNine, true)

            // Back 9 (if 18-hole)
            if is18Hole {
                cells(backNine, false)
            }

            // Grand total (if 18-hole)
            totalCell()
        }
    }

    private func playerRow(playerIndex: Int) -> some View {
        let playerScores = scores[playerIndex] ?? [:]
        let isRemote = remotePlayerIndices.contains(playerIndex)
        let label = playerLabels[playerIndex] ?? "P\(playerIndex + 1)"

        return HStack(spacing: 0) {
            // Player name label
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(isRemote ? .secondary : .primary)
                .lineLimit(1)
                .frame(width: ScorecardLayout.rowLabelWidth, alignment: .leading)
                .padding(.horizontal, ScorecardLayout.cellHPadding)
                .padding(.vertical, ScorecardLayout.cellVPadding)

            // Front 9 scores
            playerScoreCells(nine: frontNine, playerScores: playerScores, playerIndex: playerIndex, isRemote: isRemote)
            // Front 9 subtotal
            nineSubtotalCell(nine: frontNine, playerScores: playerScores, isRemote: isRemote)

            if is18Hole {
                // Back 9 scores
                playerScoreCells(nine: backNine, playerScores: playerScores, playerIndex: playerIndex, isRemote: isRemote)
                // Back 9 subtotal
                nineSubtotalCell(nine: backNine, playerScores: playerScores, isRemote: isRemote)

                // Grand total
                let totalStrokes = holes.reduce(0) { $0 + (playerScores[$1.holeNumber] ?? 0) }
                let totalPar = holes.reduce(0) { $0 + $1.par }
                let diff = totalStrokes - totalPar
                summaryScoreCell(strokes: totalStrokes, diff: diff, isRemote: isRemote, hasScores: !playerScores.isEmpty)
            }
        }
    }

    private func playerScoreCells(nine: [CourseHoleRecord], playerScores: [Int: Int], playerIndex: Int, isRemote: Bool) -> some View {
        ForEach(nine, id: \.holeNumber) { hole in
            let holeIndex = holes.firstIndex(where: { $0.holeNumber == hole.holeNumber })
            let isCurrentHole = holeIndex == currentHoleIndex
            let strokes = playerScores[hole.holeNumber]

            scoreCell(
                strokes: strokes,
                par: hole.par,
                isCurrentHole: isCurrentHole && playerIndex == currentPlayerIndex,
                isRemote: isRemote,
                onTap: onHoleTap != nil && holeIndex != nil ? { onHoleTap?(holeIndex!) } : nil
            )
        }
    }

    // MARK: - Cell Views

    private func holeHeaderCell(hole: CourseHoleRecord) -> some View {
        let holeIndex = holes.firstIndex(where: { $0.holeNumber == hole.holeNumber })
        let isCurrentHole = holeIndex == currentHoleIndex

        return Text("\(hole.holeNumber)")
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(isCurrentHole ? Color.accentColor : .primary)
            .frame(width: ScorecardLayout.holeColumnWidth)
            .padding(.vertical, ScorecardLayout.cellVPadding)
            .background(isCurrentHole ? Color.accentColor.opacity(0.12) : Color.clear)
    }

    private func summaryHeaderCell(text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            .frame(width: ScorecardLayout.summaryColumnWidth)
            .padding(.vertical, ScorecardLayout.cellVPadding)
            .background(Color(.secondarySystemBackground))
    }

    private func valueCell(text: String, dimmed: Bool = false) -> some View {
        Text(text)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(dimmed ? .tertiary : .secondary)
            .frame(width: ScorecardLayout.holeColumnWidth)
            .padding(.vertical, ScorecardLayout.cellVPadding)
    }

    private func summaryValueCell(text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: ScorecardLayout.summaryColumnWidth)
            .padding(.vertical, ScorecardLayout.cellVPadding)
            .background(Color(.secondarySystemBackground))
    }

    private func emptySummaryCell() -> some View {
        Color(.secondarySystemBackground)
            .frame(width: ScorecardLayout.summaryColumnWidth)
            .frame(maxHeight: .infinity)
    }

    private func scoreCell(
        strokes: Int?,
        par: Int,
        isCurrentHole: Bool,
        isRemote: Bool,
        onTap: (() -> Void)?
    ) -> some View {
        Group {
            if let strokes {
                ScoreNotationView(strokes: strokes, par: par, size: ScorecardLayout.scoreCellSize)
                    .opacity(isRemote ? 0.6 : 1.0)
            } else {
                Text("-")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                    .frame(width: ScorecardLayout.scoreCellSize, height: ScorecardLayout.scoreCellSize)
            }
        }
        .frame(width: ScorecardLayout.holeColumnWidth)
        .padding(.vertical, ScorecardLayout.cellVPadding / 2)
        .background(isCurrentHole ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
    }

    private func nineSubtotalCell(nine: [CourseHoleRecord], playerScores: [Int: Int], isRemote: Bool) -> some View {
        let nineStrokes = nine.reduce(0) { $0 + (playerScores[$1.holeNumber] ?? 0) }
        let ninePar = nine.reduce(0) { $0 + $1.par }
        let diff = nineStrokes - ninePar
        let hasScores = nine.contains { playerScores[$0.holeNumber] != nil }

        return summaryScoreCell(strokes: nineStrokes, diff: diff, isRemote: isRemote, hasScores: hasScores)
    }

    private func summaryScoreCell(strokes: Int, diff: Int, isRemote: Bool, hasScores: Bool) -> some View {
        VStack(spacing: 0) {
            Text(hasScores ? "\(strokes)" : "-")
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(isRemote ? .secondary : .primary)
            if hasScores && diff != 0 {
                Text(diff.scoreToParString)
                    .font(.system(size: 8, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(diff > 0 ? Color.scoreDouble : Color.scoreEagle)
            }
        }
        .frame(width: ScorecardLayout.summaryColumnWidth)
        .padding(.vertical, ScorecardLayout.cellVPadding / 2)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Label Style

    private enum LabelStyle {
        case header, subheader

        var font: Font {
            switch self {
            case .header: return .caption2.weight(.semibold)
            case .subheader: return .caption2
            }
        }

        var color: Color {
            switch self {
            case .header: return .primary
            case .subheader: return .secondary
            }
        }
    }
}
