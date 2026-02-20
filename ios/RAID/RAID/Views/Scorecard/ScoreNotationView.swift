// ScoreNotationView.swift
// RAID Golf
//
// Golf scorecard notation overlays: circles for under-par, squares for over-par.
// Shape is the primary signal (accessibility-safe); color is supplementary.

import SwiftUI

/// Displays a score number with standard golf notation overlay.
/// - Circle: birdie (-1), eagle (-2)
/// - Double circle: albatross (-3 or better)
/// - Square: bogey (+1)
/// - Double square: double bogey (+2)
/// - Filled square: triple bogey or worse (+3+)
/// - No decoration: par (0)
struct ScoreNotationView: View {
    let strokes: Int
    let par: Int
    /// Outer size of the notation shape. Score text scales to fit.
    let size: CGFloat

    private var classification: ScoreRelativeToPar {
        ScoreRelativeToPar(strokes: strokes, par: par)
    }

    /// Inner ring size for double-circle/double-square (proportional).
    private var innerSize: CGFloat {
        size * (CGFloat(ScorecardLayout.notationInnerSize) / CGFloat(ScorecardLayout.notationOuterSize))
    }

    var body: some View {
        ZStack {
            notationShape
            scoreText
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hole, \(strokes) strokes, \(classification.accessibilityLabel)")
    }

    @ViewBuilder
    private var scoreText: some View {
        let isFilled = classification == .triplePlus
        Text("\(strokes)")
            .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(isFilled ? .white : classification.color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    @ViewBuilder
    private var notationShape: some View {
        let strokeWeight = ScorecardLayout.notationStrokeWeight
        let cornerRadius = ScorecardLayout.notationSquareRadius

        switch classification {
        case .albatross:
            // Double concentric circles
            ZStack {
                Circle()
                    .strokeBorder(classification.color, lineWidth: strokeWeight)
                Circle()
                    .strokeBorder(classification.color, lineWidth: strokeWeight)
                    .frame(width: innerSize, height: innerSize)
            }

        case .eagle:
            // Single circle
            Circle()
                .strokeBorder(classification.color, lineWidth: strokeWeight)

        case .birdie:
            // Single circle
            Circle()
                .strokeBorder(classification.color, lineWidth: strokeWeight)

        case .par:
            // No decoration
            EmptyView()

        case .bogey:
            // Single rounded square
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(classification.color, lineWidth: strokeWeight)

        case .doubleBogey:
            // Double concentric squares
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(classification.color, lineWidth: strokeWeight)
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(classification.color, lineWidth: strokeWeight)
                    .frame(width: innerSize, height: innerSize)
            }

        case .triplePlus:
            // Filled square
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(classification.color)
        }
    }
}
