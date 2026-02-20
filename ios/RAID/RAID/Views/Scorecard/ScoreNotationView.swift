// ScoreNotationView.swift
// RAID Golf
//
// Golf scorecard notation overlays: circles for under-par, squares for over-par.
// Shape is the primary signal (accessibility-safe); color is supplementary.

import SwiftUI

/// Displays a score number with standard golf notation overlay.
/// - Circle: birdie (-1)
/// - Double circle: eagle (-2) or albatross (-3)
/// - Square: bogey (+1)
/// - Double square: double bogey (+2)
/// - Filled square: triple bogey or worse (+3+)
/// - No decoration: par (0)
struct ScoreNotationView: View {
    let strokes: Int
    let par: Int
    let size: CGFloat

    private var classification: ScoreRelativeToPar {
        ScoreRelativeToPar(strokes: strokes, par: par)
    }

    var body: some View {
        ZStack {
            notationShape
            scoreText
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(strokes), \(classification.accessibilityLabel)")
    }

    @ViewBuilder
    private var scoreText: some View {
        let isFilled = classification == .triplePlus
        Text("\(strokes)")
            .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(isFilled ? .white : classification.color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    @ViewBuilder
    private var notationShape: some View {
        switch classification {
        case .albatross:
            // Double concentric circles
            ZStack {
                Circle()
                    .strokeBorder(classification.color, lineWidth: 1.5)
                Circle()
                    .strokeBorder(classification.color, lineWidth: 1.5)
                    .padding(3)
            }

        case .eagle:
            // Single circle (thicker to distinguish from birdie)
            Circle()
                .strokeBorder(classification.color, lineWidth: 2)

        case .birdie:
            // Single circle
            Circle()
                .strokeBorder(classification.color, lineWidth: 1.5)

        case .par:
            // No decoration
            EmptyView()

        case .bogey:
            // Single square
            RoundedRectangle(cornerRadius: ScorecardLayout.notationCornerRadius)
                .strokeBorder(classification.color, lineWidth: 1.5)

        case .doubleBogey:
            // Double concentric squares
            ZStack {
                RoundedRectangle(cornerRadius: ScorecardLayout.notationCornerRadius)
                    .strokeBorder(classification.color, lineWidth: 1.5)
                RoundedRectangle(cornerRadius: ScorecardLayout.notationCornerRadius)
                    .strokeBorder(classification.color, lineWidth: 1.5)
                    .padding(3)
            }

        case .triplePlus:
            // Filled square
            RoundedRectangle(cornerRadius: ScorecardLayout.notationCornerRadius)
                .fill(classification.color)
        }
    }
}

/// Simplified notation for compact contexts (mini scorecard).
/// Shows just the number with a small color indicator dot.
struct CompactScoreView: View {
    let strokes: Int
    let par: Int

    private var classification: ScoreRelativeToPar {
        ScoreRelativeToPar(strokes: strokes, par: par)
    }

    var body: some View {
        Text("\(strokes)")
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(classification.color)
            .accessibilityLabel("\(strokes), \(classification.accessibilityLabel)")
    }
}
