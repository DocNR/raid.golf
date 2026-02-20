// ScorecardGridView.swift
// RAID Golf
//
// Classic golf scorecard grid with horizontal scroll and sticky row labels.
// Left column (Hole/Par/SI/player names) stays fixed while hole columns scroll.
// Rows: Hole#, Par, SI, Player scores. Columns: holes + OUT/IN/TOTAL.
// Used in RoundDetailView, RoundReviewView, LiveScorecardSheet.

import SwiftUI

/// Full classic golf scorecard grid (Layout A).
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

    /// Remote player indices (shown with dimmed + italic treatment, no notation)
    var remotePlayerIndices: Set<Int> = []

    private var is18Hole: Bool { holes.count > 9 }
    private var frontNine: [CourseHoleRecord] { Array(holes.prefix(9)) }
    private var backNine: [CourseHoleRecord] { is18Hole ? Array(holes.suffix(from: 9)) : [] }

    private var sortedPlayerIndices: [Int] {
        playerLabels.keys.sorted()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Fixed left column (row labels — does not scroll)
            VStack(spacing: 0) {
                rowLabel("HOLE", style: .header)
                gridDivider
                rowLabel("Par", style: .sub)

                if holes.contains(where: { $0.handicapIndex != nil }) {
                    gridDivider
                    rowLabel("SI", style: .sub)
                }

                semanticDivider

                ForEach(sortedPlayerIndices, id: \.self) { playerIndex in
                    if playerIndex != sortedPlayerIndices.first {
                        gridDivider
                    }
                    let label = playerLabels[playerIndex] ?? "P\(playerIndex + 1)"
                    let isRemote = remotePlayerIndices.contains(playerIndex)
                    rowLabel(label, style: .player, isRemote: isRemote)
                }
            }
            .frame(width: ScorecardLayout.rowLabelWidth + 2 * ScorecardLayout.cellHPadding)

            // Scrolling right area (hole columns + summary columns)
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    // Hole number row
                    holeNumberRow
                    gridDivider
                    parRow

                    if holes.contains(where: { $0.handicapIndex != nil }) {
                        gridDivider
                        siRow
                    }

                    semanticDivider

                    // Player score rows
                    ForEach(sortedPlayerIndices, id: \.self) { playerIndex in
                        if playerIndex != sortedPlayerIndices.first {
                            gridDivider
                        }
                        playerScoreRow(playerIndex: playerIndex)
                    }
                }
            }
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: ScorecardLayout.miniCardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: ScorecardLayout.miniCardCornerRadius)
                .strokeBorder(Color(.separator), lineWidth: ScorecardLayout.gridLineWeight)
        )
    }

    // MARK: - Dividers

    private var gridDivider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(height: ScorecardLayout.gridLineWeight)
    }

    private var semanticDivider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(height: ScorecardLayout.gridSemanticDividerWeight)
    }

    // MARK: - Row Labels (Fixed Left Column)

    private func rowLabel(_ text: String, style: LabelStyle, isRemote: Bool = false) -> some View {
        Text(text)
            .font(style.font)
            .foregroundStyle(isRemote ? .secondary : style.foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: ScorecardLayout.rowLabelWidth, height: style.rowHeight, alignment: .center)
            .padding(.horizontal, ScorecardLayout.cellHPadding)
    }

    // MARK: - Hole Number Row

    private var holeNumberRow: some View {
        HStack(spacing: 0) {
            ForEach(frontNine, id: \.holeNumber) { hole in
                holeHeaderCell(hole: hole)
            }
            summaryHeaderCell(text: is18Hole ? "OUT" : "TOT")

            if is18Hole {
                ForEach(backNine, id: \.holeNumber) { hole in
                    holeHeaderCell(hole: hole)
                }
                summaryHeaderCell(text: "IN")
                summaryHeaderCell(text: "TOT")
            }
        }
        .frame(height: ScorecardLayout.headerRowHeight)
    }

    // MARK: - Par Row

    private var parRow: some View {
        HStack(spacing: 0) {
            ForEach(frontNine, id: \.holeNumber) { hole in
                valueCell(text: "\(hole.par)", holeNumber: hole.holeNumber)
            }
            let frontPar = frontNine.reduce(0) { $0 + $1.par }
            summaryValueCell(text: "\(frontPar)")

            if is18Hole {
                ForEach(backNine, id: \.holeNumber) { hole in
                    valueCell(text: "\(hole.par)", holeNumber: hole.holeNumber)
                }
                let backPar = backNine.reduce(0) { $0 + $1.par }
                summaryValueCell(text: "\(backPar)")
                let totalPar = holes.reduce(0) { $0 + $1.par }
                summaryValueCell(text: "\(totalPar)")
            }
        }
        .frame(height: ScorecardLayout.parRowHeight)
    }

    // MARK: - SI Row

    private var siRow: some View {
        HStack(spacing: 0) {
            ForEach(frontNine, id: \.holeNumber) { hole in
                valueCell(text: hole.handicapIndex.map { "\($0)" } ?? "\u{2013}", holeNumber: hole.holeNumber, dimmed: true)
            }
            emptySummaryCell()

            if is18Hole {
                ForEach(backNine, id: \.holeNumber) { hole in
                    valueCell(text: hole.handicapIndex.map { "\($0)" } ?? "\u{2013}", holeNumber: hole.holeNumber, dimmed: true)
                }
                emptySummaryCell()
                emptySummaryCell()
            }
        }
        .frame(height: ScorecardLayout.siRowHeight)
    }

    // MARK: - Player Score Row

    private func playerScoreRow(playerIndex: Int) -> some View {
        let playerScores = scores[playerIndex] ?? [:]
        let isRemote = remotePlayerIndices.contains(playerIndex)

        return HStack(spacing: 0) {
            // Front 9 score cells
            ForEach(frontNine, id: \.holeNumber) { hole in
                scoreCell(hole: hole, playerScores: playerScores, playerIndex: playerIndex, isRemote: isRemote)
            }
            // Front 9 subtotal
            nineSubtotalCell(nine: frontNine, playerScores: playerScores, isRemote: isRemote)

            if is18Hole {
                // Back 9 score cells
                ForEach(backNine, id: \.holeNumber) { hole in
                    scoreCell(hole: hole, playerScores: playerScores, playerIndex: playerIndex, isRemote: isRemote)
                }
                // Back 9 subtotal
                nineSubtotalCell(nine: backNine, playerScores: playerScores, isRemote: isRemote)

                // Grand total
                let totalStrokes = holes.reduce(0) { $0 + (playerScores[$1.holeNumber] ?? 0) }
                let totalPar = holes.reduce(0) { $0 + $1.par }
                grandTotalCell(strokes: totalStrokes, par: totalPar, isRemote: isRemote, hasScores: !playerScores.isEmpty)
            }
        }
        .frame(height: ScorecardLayout.scoreRowHeight)
    }

    // MARK: - Cell Views

    private func holeHeaderCell(hole: CourseHoleRecord) -> some View {
        let holeIndex = holes.firstIndex(where: { $0.holeNumber == hole.holeNumber })
        let isCurrent = holeIndex == currentHoleIndex

        return Text("\(hole.holeNumber)")
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(isCurrent ? Color.accentColor : .primary)
            .frame(width: ScorecardLayout.holeColumnWidth)
            .background(isCurrent ? Color.accentColor.opacity(0.12) : Color.clear)
    }

    private func summaryHeaderCell(text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            .frame(width: ScorecardLayout.summaryColumnWidth)
            .background(Color(.tertiarySystemBackground))
    }

    private func valueCell(text: String, holeNumber: Int, dimmed: Bool = false) -> some View {
        let holeIndex = holes.firstIndex(where: { $0.holeNumber == holeNumber })
        let isCurrent = holeIndex == currentHoleIndex

        return Text(text)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(dimmed ? .tertiary : .secondary)
            .minimumScaleFactor(0.7)
            .frame(width: ScorecardLayout.holeColumnWidth)
            .background(isCurrent ? Color.accentColor.opacity(0.12) : Color.clear)
    }

    private func summaryValueCell(text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: ScorecardLayout.summaryColumnWidth)
            .background(Color(.tertiarySystemBackground))
    }

    private func emptySummaryCell() -> some View {
        Color(.tertiarySystemBackground)
            .frame(width: ScorecardLayout.summaryColumnWidth)
    }

    private func scoreCell(hole: CourseHoleRecord, playerScores: [Int: Int], playerIndex: Int, isRemote: Bool) -> some View {
        let holeIndex = holes.firstIndex(where: { $0.holeNumber == hole.holeNumber })
        let isCurrent = holeIndex == currentHoleIndex && playerIndex == currentPlayerIndex
        let strokes = playerScores[hole.holeNumber]

        return Group {
            if let strokes {
                if isRemote {
                    // Remote scores: dimmed text, italic, no notation shapes
                    Text("\(strokes)")
                        .font(.callout.weight(.medium).monospacedDigit())
                        .italic()
                        .foregroundStyle(.secondary)
                        .frame(width: ScorecardLayout.notationOuterSize, height: ScorecardLayout.notationOuterSize)
                } else {
                    // Local scores: full notation
                    ScoreNotationView(strokes: strokes, par: hole.par, size: ScorecardLayout.notationOuterSize)
                }
            } else {
                Text("\u{2013}") // en-dash
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                    .frame(width: ScorecardLayout.notationOuterSize, height: ScorecardLayout.notationOuterSize)
            }
        }
        .frame(width: ScorecardLayout.holeColumnWidth)
        .background(isCurrent ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            if let idx = holeIndex {
                onHoleTap?(idx)
            }
        }
    }

    private func nineSubtotalCell(nine: [CourseHoleRecord], playerScores: [Int: Int], isRemote: Bool) -> some View {
        let nineStrokes = nine.reduce(0) { $0 + (playerScores[$1.holeNumber] ?? 0) }
        let ninePar = nine.reduce(0) { $0 + $1.par }
        let hasScores = nine.contains { playerScores[$0.holeNumber] != nil }

        return grandTotalCell(strokes: nineStrokes, par: ninePar, isRemote: isRemote, hasScores: hasScores)
    }

    private func grandTotalCell(strokes: Int, par: Int, isRemote: Bool, hasScores: Bool) -> some View {
        let diff = strokes - par

        return VStack(spacing: 0) {
            Text(hasScores ? "\(strokes)" : "\u{2013}")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(isRemote ? .secondary : .primary)
            if hasScores && diff != 0 {
                Text(diff.scoreToParString)
                    .font(.system(size: 8, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(diff > 0 ? Color.scoreDouble : Color.scoreEagle)
            }
        }
        .frame(width: ScorecardLayout.summaryColumnWidth)
        .background(Color(.tertiarySystemBackground))
    }

    // MARK: - Label Style

    private enum LabelStyle {
        case header, sub, player

        var font: Font {
            switch self {
            case .header: return .caption2.weight(.semibold)
            case .sub: return .caption2.weight(.medium)
            case .player: return .caption.weight(.medium)
            }
        }

        var foreground: Color {
            switch self {
            case .header: return .primary
            case .sub: return .secondary
            case .player: return .primary
            }
        }

        var rowHeight: CGFloat {
            switch self {
            case .header: return ScorecardLayout.headerRowHeight
            case .sub: return ScorecardLayout.parRowHeight
            case .player: return ScorecardLayout.scoreRowHeight
            }
        }
    }
}
