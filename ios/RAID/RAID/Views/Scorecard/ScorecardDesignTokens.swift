// ScorecardDesignTokens.swift
// RAID Golf
//
// Design tokens for the golf scorecard UI.
// All grid measurements, score colors, and notation helpers live here.
// No scorecard view file should contain magic numbers.

import SwiftUI

// MARK: - Score Notation Colors

extension Color {
    /// Green for eagle or better (-2 or less)
    static let scoreEagle = Color(red: 0.18, green: 0.49, blue: 0.20)

    /// Green for birdie (-1) — slightly lighter than eagle
    static let scoreBirdie = Color(red: 0.22, green: 0.55, blue: 0.16)

    /// Amber/orange for bogey (+1)
    static let scoreBogey = Color(red: 0.83, green: 0.33, blue: 0.00)

    /// Red for double bogey or worse (+2 or more)
    static let scoreDouble = Color(red: 0.78, green: 0.00, blue: 0.00)
}

// MARK: - Scorecard Layout Constants

enum ScorecardLayout {
    // -- Grid column widths --

    /// Fixed width of the row label column (Hole/Par/SI/player name). Non-scrolling.
    static let rowLabelWidth: CGFloat = 48

    /// Fixed width of each individual hole column in the scrolling grid.
    static let holeColumnWidth: CGFloat = 30

    /// Fixed width of OUT, IN, and TOTAL summary columns.
    static let summaryColumnWidth: CGFloat = 36

    // -- Grid cell padding --

    /// Left + right padding within each cell.
    static let cellHPadding: CGFloat = 3

    /// Top + bottom padding within each cell.
    static let cellVPadding: CGFloat = 7

    // -- Grid row heights --

    /// Height of the hole-number header row.
    static let headerRowHeight: CGFloat = 28

    /// Height of each player score row (accommodates notation overlays).
    static let scoreRowHeight: CGFloat = 36

    /// Height of the Par row.
    static let parRowHeight: CGFloat = 26

    /// Height of the Stroke Index (handicap) row.
    static let siRowHeight: CGFloat = 22

    // -- Grid visual --

    /// Stroke weight for internal grid dividers.
    static let gridLineWeight: CGFloat = 0.5

    /// Heavier stroke for the semantic break between course definition and scores.
    static let gridSemanticDividerWeight: CGFloat = 1.0

    /// Gap between 9-hole block and OUT/IN/TOT column.
    static let sectionGap: CGFloat = 4

    // -- Mini scorecard (Layout B header) --

    /// Height of the MiniScorecardView strip.
    static let miniCardHeight: CGFloat = 72

    /// Diameter of the current-hole indicator dot.
    static let currentHoleDotSize: CGFloat = 4

    /// Corner radius for the mini-card container.
    static let miniCardCornerRadius: CGFloat = 12

    // -- Score notation geometry --

    /// Outer diameter of notation circle / side of notation square.
    static let notationOuterSize: CGFloat = 28

    /// Inner ring size for double-circle/double-square.
    static let notationInnerSize: CGFloat = 20

    /// Stroke weight for all outline notation shapes.
    static let notationStrokeWeight: CGFloat = 1.5

    /// Corner radius for bogey/double-bogey squares.
    static let notationSquareRadius: CGFloat = 2

    // -- General --

    /// Minimum accessible tap target size (Apple HIG).
    static let minTapTarget: CGFloat = 44

    /// Corner radius for focused hole panel.
    static let focusedPanelCornerRadius: CGFloat = 16

    /// Font size for the focused hole number display.
    static let focusedHoleNumberSize: CGFloat = 48

    /// Font size for the focused stroke count display.
    static let focusedStrokeCountSize: CGFloat = 72

    /// Minimum frame width for stroke count to prevent layout shift on digit change.
    static let strokeCountMinWidth: CGFloat = 120
}

// MARK: - Score Classification

enum ScoreRelativeToPar: Equatable {
    case albatross      // -3 or better
    case eagle          // -2
    case birdie         // -1
    case par            // 0
    case bogey          // +1
    case doubleBogey    // +2
    case triplePlus     // +3 or worse

    init(strokes: Int, par: Int) {
        let diff = strokes - par
        switch diff {
        case ...(-3): self = .albatross
        case -2: self = .eagle
        case -1: self = .birdie
        case 0: self = .par
        case 1: self = .bogey
        case 2: self = .doubleBogey
        default: self = .triplePlus
        }
    }

    var color: Color {
        switch self {
        case .albatross, .eagle: return .scoreEagle
        case .birdie: return .scoreBirdie
        case .par: return .primary
        case .bogey: return .scoreBogey
        case .doubleBogey, .triplePlus: return .scoreDouble
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .albatross: return "Albatross"
        case .eagle: return "Eagle"
        case .birdie: return "Birdie"
        case .par: return "Par"
        case .bogey: return "Bogey"
        case .doubleBogey: return "Double Bogey"
        case .triplePlus: return "Triple Bogey or worse"
        }
    }
}

// MARK: - Score-to-Par Formatting

extension Int {
    /// Format as score-to-par string: "E", "+3", "-2"
    var scoreToParString: String {
        if self == 0 { return "E" }
        return self > 0 ? "+\(self)" : "\(self)"
    }
}

// MARK: - Scorecard Card Style

extension View {
    func scorecardCardStyle() -> some View {
        self
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: ScorecardLayout.miniCardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: ScorecardLayout.miniCardCornerRadius)
                    .strokeBorder(Color(.separator), lineWidth: ScorecardLayout.gridLineWeight)
            )
    }
}
