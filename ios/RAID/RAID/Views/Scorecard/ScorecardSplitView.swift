// ScorecardSplitView.swift
// RAID Golf
//
// Read-only golf scorecard split into front nine and back nine blocks, stacked vertically.
// Front nine block: holes 1-9 + OUT subtotal.
// Back nine block: holes 10-18 + IN subtotal.
// Totals block: prominent summary card with total strokes + score vs par per player.
// Used in RoundReviewView and RoundDetailView. Active scoring uses ScorecardGridView.

import SwiftUI

struct ScorecardSplitView: View {
    let holes: [CourseHoleRecord]
    /// playerIndex -> (holeNumber -> strokes)
    let scores: [Int: [Int: Int]]
    let playerLabels: [Int: String]

    /// Remote player indices (shown with dimmed + italic treatment, no notation)
    var remotePlayerIndices: Set<Int> = []

    private var is18Hole: Bool { holes.count > 9 }
    private var frontNine: [CourseHoleRecord] { Array(holes.prefix(9)) }
    private var backNine: [CourseHoleRecord] { is18Hole ? Array(holes.suffix(from: 9)) : [] }
    private var sortedPlayerIndices: [Int] { playerLabels.keys.sorted() }

    /// Total fixed-column width: frame + horizontal padding on each side.
    private let labelColumnWidth = ScorecardLayout.rowLabelWidth + 2 * ScorecardLayout.cellHPadding

    var body: some View {
        VStack(spacing: 10) {
            nineBlock(nine: frontNine, summaryLabel: is18Hole ? "OUT" : "TOT")
                .scorecardCardStyle()

            if is18Hole {
                nineBlock(nine: backNine, summaryLabel: "IN")
                    .scorecardCardStyle()

                totalsCard
                    .scorecardCardStyle()
            }
        }
    }

    // MARK: - Nine Block

    private func nineBlock(nine: [CourseHoleRecord], summaryLabel: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // Fixed label column
            VStack(spacing: 0) {
                rowLabel("HOLE", style: .header)
                gridDivider
                rowLabel("Par", style: .sub)

                if nine.contains(where: { $0.handicapIndex != nil }) {
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
            .frame(width: labelColumnWidth)

            // Hole columns + summary column (no scroll)
            VStack(spacing: 0) {
                holeNumberRow(nine: nine, summaryLabel: summaryLabel)
                gridDivider
                parRow(nine: nine)

                if nine.contains(where: { $0.handicapIndex != nil }) {
                    gridDivider
                    siRow(nine: nine)
                }

                semanticDivider

                ForEach(sortedPlayerIndices, id: \.self) { playerIndex in
                    if playerIndex != sortedPlayerIndices.first {
                        gridDivider
                    }
                    playerScoreRow(nine: nine, playerIndex: playerIndex)
                }
            }
        }
    }

    // MARK: - Totals Card

    private var totalsCard: some View {
        VStack(spacing: 0) {
            // Header
            Text("TOTAL")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .frame(height: ScorecardLayout.headerRowHeight)

            semanticDivider

            ForEach(sortedPlayerIndices, id: \.self) { playerIndex in
                if playerIndex != sortedPlayerIndices.first {
                    gridDivider
                }
                totalRow(for: playerIndex)
            }
        }
    }

    private func totalRow(for playerIndex: Int) -> some View {
        let playerScores = scores[playerIndex] ?? [:]
        let totalStrokes = holes.reduce(0) { $0 + (playerScores[$1.holeNumber] ?? 0) }
        let totalPar = holes.reduce(0) { $0 + $1.par }
        let diff = totalStrokes - totalPar
        let hasScores = holes.contains { playerScores[$0.holeNumber] != nil }
        let isRemote = remotePlayerIndices.contains(playerIndex)
        let label = playerLabels[playerIndex] ?? "P\(playerIndex + 1)"

        return HStack(spacing: 12) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isRemote ? .secondary : .primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer()

            if hasScores {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(totalStrokes)")
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(isRemote ? .secondary : .primary)
                    Text(diff.scoreToParString)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(
                            diff > 0 ? Color.scoreDouble :
                            diff < 0 ? Color.scoreEagle :
                            .secondary
                        )
                }
            } else {
                Text("\u{2013}")
                    .font(.title2)
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }

    // MARK: - Row Views

    private func holeNumberRow(nine: [CourseHoleRecord], summaryLabel: String) -> some View {
        HStack(spacing: 0) {
            ForEach(nine, id: \.holeNumber) { hole in
                Text("\(hole.holeNumber)")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .frame(width: ScorecardLayout.holeColumnWidth)
            }
            summaryColumnSeparator
            Text(summaryLabel)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: ScorecardLayout.summaryColumnWidth)
                .background(Color(.tertiarySystemBackground))
        }
        .frame(height: ScorecardLayout.headerRowHeight)
    }

    private func parRow(nine: [CourseHoleRecord]) -> some View {
        HStack(spacing: 0) {
            ForEach(nine, id: \.holeNumber) { hole in
                Text("\(hole.par)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: ScorecardLayout.holeColumnWidth)
            }
            let ninePar = nine.reduce(0) { $0 + $1.par }
            summaryColumnSeparator
            Text("\(ninePar)")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: ScorecardLayout.summaryColumnWidth)
                .background(Color(.tertiarySystemBackground))
        }
        .frame(height: ScorecardLayout.parRowHeight)
    }

    private func siRow(nine: [CourseHoleRecord]) -> some View {
        HStack(spacing: 0) {
            ForEach(nine, id: \.holeNumber) { hole in
                Text(hole.handicapIndex.map { "\($0)" } ?? "\u{2013}")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .minimumScaleFactor(0.7)
                    .frame(width: ScorecardLayout.holeColumnWidth)
            }
            summaryColumnSeparator
            Color(.tertiarySystemBackground)
                .frame(width: ScorecardLayout.summaryColumnWidth)
        }
        .frame(height: ScorecardLayout.siRowHeight)
    }

    private func playerScoreRow(nine: [CourseHoleRecord], playerIndex: Int) -> some View {
        let playerScores = scores[playerIndex] ?? [:]
        let isRemote = remotePlayerIndices.contains(playerIndex)
        let nineStrokes = nine.reduce(0) { $0 + (playerScores[$1.holeNumber] ?? 0) }
        let ninePar = nine.reduce(0) { $0 + $1.par }
        let hasScores = nine.contains { playerScores[$0.holeNumber] != nil }

        return HStack(spacing: 0) {
            ForEach(nine, id: \.holeNumber) { hole in
                scoreCell(hole: hole, playerScores: playerScores, isRemote: isRemote)
            }
            summaryColumnSeparator
            summaryCell(strokes: nineStrokes, par: ninePar, isRemote: isRemote, hasScores: hasScores)
        }
        .frame(height: ScorecardLayout.scoreRowHeight)
    }

    // MARK: - Cell Views

    private func scoreCell(hole: CourseHoleRecord, playerScores: [Int: Int], isRemote: Bool) -> some View {
        let strokes = playerScores[hole.holeNumber]

        return Group {
            if let strokes {
                if isRemote {
                    Text("\(strokes)")
                        .font(.callout.weight(.medium).monospacedDigit())
                        .italic()
                        .foregroundStyle(.secondary)
                        .frame(width: ScorecardLayout.notationOuterSize, height: ScorecardLayout.notationOuterSize)
                } else {
                    ScoreNotationView(strokes: strokes, par: hole.par, size: ScorecardLayout.notationOuterSize)
                }
            } else {
                Text("\u{2013}")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                    .frame(width: ScorecardLayout.notationOuterSize, height: ScorecardLayout.notationOuterSize)
            }
        }
        .frame(width: ScorecardLayout.holeColumnWidth)
    }

    private func summaryCell(strokes: Int, par: Int, isRemote: Bool, hasScores: Bool) -> some View {
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

    /// Vertical separator between hole columns and OUT/IN/TOT summary column.
    private var summaryColumnSeparator: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(width: ScorecardLayout.gridSemanticDividerWeight)
    }

    // MARK: - Row Label

    private func rowLabel(_ text: String, style: LabelStyle, isRemote: Bool = false) -> some View {
        Text(text)
            .font(style.font)
            .foregroundStyle(isRemote ? .secondary : style.foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: ScorecardLayout.rowLabelWidth, height: style.rowHeight, alignment: .center)
            .padding(.horizontal, ScorecardLayout.cellHPadding)
    }

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

