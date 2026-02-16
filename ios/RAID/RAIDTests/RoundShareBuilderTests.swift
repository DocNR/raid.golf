// RoundShareBuilderTests.swift
// RAID Golf
//
// Tests for RoundShareBuilder note formatting.

import XCTest
@testable import RAID

final class RoundShareBuilderTests: XCTestCase {

    // MARK: - Helpers

    private func makeHoles(count: Int, startingHole: Int = 1, par: Int = 4) -> [CourseHoleRecord] {
        (0..<count).map { i in
            CourseHoleRecord(
                courseHash: "test",
                holeNumber: startingHole + i,
                par: par,
                handicapIndex: nil
            )
        }
    }

    private func makeScores(holes: [CourseHoleRecord], strokes: Int) -> [Int: Int] {
        var scores: [Int: Int] = [:]
        for hole in holes {
            scores[hole.holeNumber] = strokes
        }
        return scores
    }

    // MARK: - 18-Hole Notes

    func testNoteText18Hole_OverPar() {
        let holes = makeHoles(count: 18)
        // All par 4, shoot 5 on each = 90 total, 72 par, +18
        let scores = makeScores(holes: holes, strokes: 5)

        let note = RoundShareBuilder.noteText(
            course: "Pebble Beach",
            tees: "Blue",
            holes: holes,
            scores: scores
        )

        XCTAssertTrue(note.contains("Shot 90 at Pebble Beach (Blue tees)"))
        XCTAssertTrue(note.contains("Front 9: 45"))
        XCTAssertTrue(note.contains("Back 9: 45"))
        XCTAssertTrue(note.contains("(+18)"))
        XCTAssertTrue(note.contains("#golf"))
        XCTAssertTrue(note.contains("#raidgolf"))
    }

    func testNoteText18Hole_UnderPar() {
        let holes = makeHoles(count: 18)
        // All par 4, shoot 3 on each = 54 total, 72 par, -18
        let scores = makeScores(holes: holes, strokes: 3)

        let note = RoundShareBuilder.noteText(
            course: "Augusta National",
            tees: "Championship",
            holes: holes,
            scores: scores
        )

        XCTAssertTrue(note.contains("Shot 54 at Augusta National"))
        XCTAssertTrue(note.contains("(-18)"))
    }

    func testNoteText18Hole_Even() {
        let holes = makeHoles(count: 18)
        let scores = makeScores(holes: holes, strokes: 4) // par on every hole

        let note = RoundShareBuilder.noteText(
            course: "St Andrews",
            tees: "White",
            holes: holes,
            scores: scores
        )

        XCTAssertTrue(note.contains("Shot 72 at St Andrews"))
        XCTAssertTrue(note.contains("(Even)"))
    }

    // MARK: - 9-Hole Notes

    func testNoteTextFront9() {
        let holes = makeHoles(count: 9, startingHole: 1)
        let scores = makeScores(holes: holes, strokes: 5)

        let note = RoundShareBuilder.noteText(
            course: "Fowler's Mill",
            tees: "Silver M",
            holes: holes,
            scores: scores
        )

        XCTAssertTrue(note.contains("Shot 45 on the Front 9 at Fowler's Mill (Silver M tees)"))
        XCTAssertTrue(note.contains("(+9)"))
        XCTAssertFalse(note.contains("Back 9"))
    }

    func testNoteTextBack9() {
        let holes = makeHoles(count: 9, startingHole: 10)
        let scores = makeScores(holes: holes, strokes: 4)

        let note = RoundShareBuilder.noteText(
            course: "Fowler's Mill",
            tees: "Black",
            holes: holes,
            scores: scores
        )

        XCTAssertTrue(note.contains("on the Back 9 at Fowler's Mill"))
        XCTAssertTrue(note.contains("(Even)"))
    }

    // MARK: - Hashtags

    func testNoteTextContainsHashtags() {
        let holes = makeHoles(count: 9)
        let scores = makeScores(holes: holes, strokes: 4)

        let note = RoundShareBuilder.noteText(
            course: "Test",
            tees: "Test",
            holes: holes,
            scores: scores
        )

        XCTAssertTrue(note.contains("#golf"))
        XCTAssertTrue(note.contains("#raidgolf"))
    }

    // MARK: - Summary Text

    func testSummaryTextContainsAllFields() {
        let holes = makeHoles(count: 9)
        let scores = makeScores(holes: holes, strokes: 5)

        let summary = RoundShareBuilder.summaryText(
            course: "Pebble Beach",
            tees: "Blue",
            date: "2026-02-12",
            holes: holes,
            scores: scores
        )

        XCTAssertTrue(summary.contains("RAID Golf"))
        XCTAssertTrue(summary.contains("Course: Pebble Beach"))
        XCTAssertTrue(summary.contains("Tees: Blue"))
        XCTAssertTrue(summary.contains("Date: 2026-02-12"))
        XCTAssertTrue(summary.contains("Holes: 9"))
        XCTAssertTrue(summary.contains("Hole 1: Par 4, Score 5"))
        XCTAssertTrue(summary.contains("Total: 45 (Par 36, +9)"))
    }

    func testSummaryTextHolesSortedByNumber() {
        // Create holes out of order
        let holes = [
            CourseHoleRecord(courseHash: "x", holeNumber: 3, par: 4, handicapIndex: nil),
            CourseHoleRecord(courseHash: "x", holeNumber: 1, par: 3, handicapIndex: nil),
            CourseHoleRecord(courseHash: "x", holeNumber: 2, par: 5, handicapIndex: nil),
        ]
        let scores: [Int: Int] = [1: 3, 2: 5, 3: 4]

        let summary = RoundShareBuilder.summaryText(
            course: "Test",
            tees: "Test",
            date: "2026-01-01",
            holes: holes,
            scores: scores
        )

        // Verify holes appear in order
        let hole1Index = summary.range(of: "Hole 1")!.lowerBound
        let hole2Index = summary.range(of: "Hole 2")!.lowerBound
        let hole3Index = summary.range(of: "Hole 3")!.lowerBound
        XCTAssertTrue(hole1Index < hole2Index)
        XCTAssertTrue(hole2Index < hole3Index)
    }
}
