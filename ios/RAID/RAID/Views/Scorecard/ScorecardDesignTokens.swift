// ScorecardDesignTokens.swift
// RAID Golf
//
// Design tokens for the golf scorecard UI.
// Colors, spacing, typography constants used across all scorecard views.

import SwiftUI

// MARK: - Score Notation Colors

extension Color {
    /// Green for eagle or better (-2 or less)
    static let scoreEagle = Color(red: 0.18, green: 0.49, blue: 0.20)

    /// Green for birdie (-1) — slightly lighter than eagle
    static let scoreBirdie = Color(red: 0.22, green: 0.56, blue: 0.24)

    /// Amber/orange for bogey (+1)
    static let scoreBogey = Color(red: 0.83, green: 0.33, blue: 0.00)

    /// Red for double bogey or worse (+2 or more)
    static let scoreDouble = Color(red: 0.78, green: 0.00, blue: 0.00)
}

// MARK: - Scorecard Layout Constants

enum ScorecardLayout {
    /// Fixed width for row labels ("Hole", "Par", "SI", player names)
    static let rowLabelWidth: CGFloat = 48

    /// Fixed width for each hole column
    static let holeColumnWidth: CGFloat = 36

    /// Fixed width for OUT/IN/TOTAL summary columns
    static let summaryColumnWidth: CGFloat = 44

    /// Horizontal padding within each cell
    static let cellHPadding: CGFloat = 2

    /// Vertical padding within each cell
    static let cellVPadding: CGFloat = 6

    /// Gap between grid sections (front 9, summary, back 9)
    static let sectionGap: CGFloat = 2

    /// Height of the mini scorecard strip in Layout B
    static let miniCardHeight: CGFloat = 120

    /// Corner radius for the mini-card container
    static let miniCardCornerRadius: CGFloat = 12

    /// Corner radius for focused hole panel
    static let focusedPanelCornerRadius: CGFloat = 16

    /// Corner radius for score notation overlays
    static let notationCornerRadius: CGFloat = 2

    /// Minimum tap target size (Apple HIG)
    static let minTapTarget: CGFloat = 44

    /// Score cell size (square) in the grid
    static let scoreCellSize: CGFloat = 32

    /// Score cell size in mini card
    static let miniScoreCellSize: CGFloat = 28
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
