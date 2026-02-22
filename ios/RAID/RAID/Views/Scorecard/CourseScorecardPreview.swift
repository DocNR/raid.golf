// CourseScorecardPreview.swift
// RAID Golf
//
// Read-only scorecard preview for a ParsedCourse.
// Shows holes, par, stroke index, and yardage for a selected tee.
// Optionally shows player name rows with empty score cells.
// Mirrors ScorecardSplitView's layout using shared ScorecardLayout tokens.

import SwiftUI

struct CourseScorecardPreview: View {
    let course: ParsedCourse
    let teeName: String
    var playerLabels: [String] = []

    private static let maxPlayerRows = 4

    private var holes: [ParsedCourse.ParsedHole] {
        course.holes.sorted { $0.number < $1.number }
    }
    private var is18Hole: Bool { holes.count > 9 }
    private var frontNine: [ParsedCourse.ParsedHole] { Array(holes.prefix(9)) }
    private var backNine: [ParsedCourse.ParsedHole] { is18Hole ? Array(holes.suffix(from: 9)) : [] }
    private var yardageMap: [Int: Int] { course.yardages(forTee: teeName) }

    /// Player labels to display, capped at maxPlayerRows.
    private var displayedPlayers: [String] {
        if playerLabels.count <= Self.maxPlayerRows {
            return playerLabels
        }
        let shown = Array(playerLabels.prefix(Self.maxPlayerRows - 1))
        let overflow = playerLabels.count - shown.count
        return shown + ["+\(overflow) more"]
    }

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

    private func nineBlock(nine: [ParsedCourse.ParsedHole], summaryLabel: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            // Fixed label column
            VStack(spacing: 0) {
                rowLabel("HOLE", style: .header)
                gridDivider
                rowLabel("Par", style: .sub)

                if nine.contains(where: { $0.handicap > 0 }) {
                    gridDivider
                    rowLabel("SI", style: .sub)
                }

                semanticDivider
                rowLabel("Yds", style: .yardage)

                if !displayedPlayers.isEmpty {
                    gridDivider
                    ForEach(Array(displayedPlayers.enumerated()), id: \.offset) { index, label in
                        if index > 0 {
                            gridDivider
                        }
                        rowLabel(label, style: .player)
                    }
                }
            }
            .frame(width: labelColumnWidth)

            // Hole columns + summary column
            VStack(spacing: 0) {
                holeNumberRow(nine: nine, summaryLabel: summaryLabel)
                gridDivider
                parRow(nine: nine)

                if nine.contains(where: { $0.handicap > 0 }) {
                    gridDivider
                    siRow(nine: nine)
                }

                semanticDivider
                yardageRow(nine: nine)

                if !displayedPlayers.isEmpty {
                    gridDivider
                    ForEach(Array(displayedPlayers.enumerated()), id: \.offset) { index, _ in
                        if index > 0 {
                            gridDivider
                        }
                        emptyPlayerRow(nine: nine)
                    }
                }
            }
        }
    }

    // MARK: - Totals Card

    private var totalsCard: some View {
        VStack(spacing: 0) {
            Text("TOTAL")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .frame(height: ScorecardLayout.headerRowHeight)

            semanticDivider

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Par \(course.totalPar())")
                        .font(.subheadline.weight(.medium))
                    let tee = course.tees.first { $0.name == teeName }
                    if let tee {
                        Text("Rating \(tee.rating, specifier: "%.1f") · Slope \(tee.slope)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                let totalYds = course.totalYardage(forTee: teeName)
                if totalYds > 0 {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(totalYds)")
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                        Text("yards")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
        }
    }

    // MARK: - Row Views

    private func holeNumberRow(nine: [ParsedCourse.ParsedHole], summaryLabel: String) -> some View {
        HStack(spacing: 0) {
            ForEach(nine, id: \.number) { hole in
                Text("\(hole.number)")
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

    private func parRow(nine: [ParsedCourse.ParsedHole]) -> some View {
        HStack(spacing: 0) {
            ForEach(nine, id: \.number) { hole in
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

    private func siRow(nine: [ParsedCourse.ParsedHole]) -> some View {
        HStack(spacing: 0) {
            ForEach(nine, id: \.number) { hole in
                Text(hole.handicap > 0 ? "\(hole.handicap)" : "\u{2013}")
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

    private func yardageRow(nine: [ParsedCourse.ParsedHole]) -> some View {
        let nineYards = nine.reduce(0) { $0 + (yardageMap[$1.number] ?? 0) }

        return HStack(spacing: 0) {
            ForEach(nine, id: \.number) { hole in
                if let yards = yardageMap[hole.number] {
                    Text("\(yards)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.6)
                        .frame(width: ScorecardLayout.holeColumnWidth)
                } else {
                    Text("\u{2013}")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                        .frame(width: ScorecardLayout.holeColumnWidth)
                }
            }
            summaryColumnSeparator
            Text(nineYards > 0 ? "\(nineYards)" : "\u{2013}")
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(.primary)
                .frame(width: ScorecardLayout.summaryColumnWidth)
                .background(Color(.tertiarySystemBackground))
        }
        .frame(height: ScorecardLayout.scoreRowHeight)
    }

    private func emptyPlayerRow(nine: [ParsedCourse.ParsedHole]) -> some View {
        HStack(spacing: 0) {
            ForEach(nine, id: \.number) { _ in
                Text("\u{2013}")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                    .frame(width: ScorecardLayout.holeColumnWidth)
            }
            summaryColumnSeparator
            Text("\u{2013}")
                .font(.caption2)
                .foregroundStyle(.quaternary)
                .frame(width: ScorecardLayout.summaryColumnWidth)
                .background(Color(.tertiarySystemBackground))
        }
        .frame(height: ScorecardLayout.scoreRowHeight)
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

    private var summaryColumnSeparator: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(width: ScorecardLayout.gridSemanticDividerWeight)
    }

    // MARK: - Row Label

    private func rowLabel(_ text: String, style: LabelStyle) -> some View {
        Text(text)
            .font(style.font)
            .foregroundStyle(style.foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: ScorecardLayout.rowLabelWidth, height: style.rowHeight, alignment: .center)
            .padding(.horizontal, ScorecardLayout.cellHPadding)
    }

    private enum LabelStyle {
        case header, sub, yardage, player

        var font: Font {
            switch self {
            case .header: return .caption2.weight(.semibold)
            case .sub: return .caption2.weight(.medium)
            case .yardage: return .caption2.weight(.bold)
            case .player: return .caption.weight(.medium)
            }
        }

        var foreground: Color {
            switch self {
            case .header: return .primary
            case .sub: return .secondary
            case .yardage: return .primary
            case .player: return .primary
            }
        }

        var rowHeight: CGFloat {
            switch self {
            case .header: return ScorecardLayout.headerRowHeight
            case .sub: return ScorecardLayout.parRowHeight
            case .yardage: return ScorecardLayout.scoreRowHeight
            case .player: return ScorecardLayout.scoreRowHeight
            }
        }
    }
}
