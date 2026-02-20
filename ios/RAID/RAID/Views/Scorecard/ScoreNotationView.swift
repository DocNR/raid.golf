// ScoreNotationView.swift
// RAID Golf
//
// Golf scorecard notation overlays: circles for under-par, squares for over-par.
// Shape is the primary signal (accessibility-safe); color is supplementary.

import SwiftUI

/// Displays a score number with standard golf notation overlay.
/// - Single circle: birdie (-1)
/// - Double circle: eagle (-2)
/// - Triple circle: albatross (-3 or better)
/// - No decoration: par (0)
/// - Single square: bogey (+1)
/// - Double square: double bogey (+2)
/// - Triple square: triple bogey or worse (+3+)
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
        Text("\(strokes)")
            .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    @ViewBuilder
    private var notationShape: some View {
        let strokeWeight = ScorecardLayout.notationStrokeWeight
        let cornerRadius = ScorecardLayout.notationSquareRadius

        switch classification {
        case .albatross:
            // Triple concentric circles
            ZStack {
                Circle()
                    .strokeBorder(classification.color, lineWidth: strokeWeight)
                Circle()
                    .strokeBorder(classification.color, lineWidth: strokeWeight)
                    .frame(width: innerSize, height: innerSize)
                Circle()
                    .strokeBorder(classification.color, lineWidth: strokeWeight)
                    .frame(width: innerSize * 0.55, height: innerSize * 0.55)
            }

        case .eagle:
            // Double concentric circles
            ZStack {
                Circle()
                    .strokeBorder(classification.color, lineWidth: strokeWeight)
                Circle()
                    .strokeBorder(classification.color, lineWidth: strokeWeight)
                    .frame(width: innerSize, height: innerSize)
            }

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
            // Triple concentric squares
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(classification.color, lineWidth: strokeWeight)
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(classification.color, lineWidth: strokeWeight)
                    .frame(width: innerSize, height: innerSize)
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(classification.color, lineWidth: strokeWeight)
                    .frame(width: innerSize * 0.55, height: innerSize * 0.55)
            }
        }
    }
}
