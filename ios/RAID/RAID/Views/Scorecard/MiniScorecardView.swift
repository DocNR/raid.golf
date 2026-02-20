// MiniScorecardView.swift
// RAID Golf
//
// Compact scorecard strip for Layout B (active scoring).
// Shows hole numbers, par, and current player's scores in a horizontally scrollable strip.
// Tappable cells for jump-to-hole. Auto-scrolls to keep current hole visible.

import SwiftUI

struct MiniScorecardView: View {
    let holes: [CourseHoleRecord]
    /// Current player's scores: holeNumber -> strokes
    let scores: [Int: Int]
    let currentHoleIndex: Int
    let onHoleTap: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var is18Hole: Bool { holes.count > 9 }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    // Front 9 (or all holes for 9-hole round)
                    let frontNine = Array(holes.prefix(9))
                    ForEach(frontNine, id: \.holeNumber) { hole in
                        miniHoleColumn(hole: hole)
                            .id(hole.holeNumber)
                    }

                    // OUT summary (18-hole) or TOT (9-hole)
                    if is18Hole {
                        miniSummaryColumn(
                            label: "OUT",
                            strokes: Array(holes.prefix(9)).reduce(0) { $0 + (scores[$1.holeNumber] ?? 0) },
                            hasScores: Array(holes.prefix(9)).contains { scores[$0.holeNumber] != nil }
                        )
                    }

                    // Back 9 (18-hole only)
                    if is18Hole {
                        let backNine = Array(holes.suffix(from: 9))
                        ForEach(backNine, id: \.holeNumber) { hole in
                            miniHoleColumn(hole: hole)
                                .id(hole.holeNumber)
                        }

                        // IN summary
                        miniSummaryColumn(
                            label: "IN",
                            strokes: Array(holes.suffix(from: 9)).reduce(0) { $0 + (scores[$1.holeNumber] ?? 0) },
                            hasScores: Array(holes.suffix(from: 9)).contains { scores[$0.holeNumber] != nil }
                        )
                    }

                    // TOT summary
                    miniSummaryColumn(
                        label: "TOT",
                        strokes: holes.reduce(0) { $0 + (scores[$1.holeNumber] ?? 0) },
                        hasScores: scores.values.count > 0
                    )
                }
            }
            .onChange(of: currentHoleIndex) { _, newIndex in
                guard newIndex >= 0, newIndex < holes.count else { return }
                let holeNumber = holes[newIndex].holeNumber
                if reduceMotion {
                    proxy.scrollTo(holeNumber, anchor: .center)
                } else {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(holeNumber, anchor: .center)
                    }
                }
            }
        }
        .frame(height: ScorecardLayout.miniCardHeight)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: ScorecardLayout.miniCardCornerRadius))
    }

    // MARK: - Hole Column

    private func miniHoleColumn(hole: CourseHoleRecord) -> some View {
        let holeIndex = holes.firstIndex(where: { $0.holeNumber == hole.holeNumber })
        let isCurrent = holeIndex == currentHoleIndex
        let strokes = scores[hole.holeNumber]

        return VStack(spacing: 2) {
            // Hole number
            Text("\(hole.holeNumber)")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(isCurrent ? Color.accentColor : .primary)

            // Par
            Text("\(hole.par)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            // Score or dash
            if let strokes {
                ScoreNotationView(
                    strokes: strokes,
                    par: hole.par,
                    size: ScorecardLayout.notationOuterSize
                )
            } else {
                Text("\u{2013}") // en-dash
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.quaternary)
                    .frame(width: ScorecardLayout.notationOuterSize, height: ScorecardLayout.notationOuterSize)
            }

            // Current hole indicator dot
            Circle()
                .fill(Color.accentColor)
                .frame(width: ScorecardLayout.currentHoleDotSize, height: ScorecardLayout.currentHoleDotSize)
                .opacity(isCurrent ? 1 : 0)
        }
        .frame(width: ScorecardLayout.holeColumnWidth)
        .padding(.vertical, 4)
        .background(isCurrent ? Color.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            if let idx = holeIndex {
                onHoleTap(idx)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hole \(hole.holeNumber), par \(hole.par)\(strokes.map { ", \($0) strokes" } ?? ", not scored")")
        .accessibilityHint("Double-tap to go to this hole")
    }

    // MARK: - Summary Column

    private func miniSummaryColumn(label: String, strokes: Int, hasScores: Bool) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Text(hasScores ? "\(strokes)" : "\u{2013}")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(hasScores ? .primary : .quaternary)

            // Placeholder for alignment with dot space
            Spacer()
                .frame(height: ScorecardLayout.currentHoleDotSize)
        }
        .frame(width: ScorecardLayout.summaryColumnWidth)
        .padding(.vertical, 4)
        .background(Color(.tertiarySystemBackground))
    }
}
