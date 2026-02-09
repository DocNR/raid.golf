// ActiveRoundStore.swift
// RAID Golf - Scorecard v0
//
// Long-lived view model for active round scoring state.
// Owns holes, scores, navigation index, and persistence logic.
// Created at the RoundsView level so state survives view recreation.
//
// Invariants:
// - Append-only inserts into hole_scores (no UPDATE/DELETE)
// - saveCurrentScore() always persists the displayed value (including default par)
// - Rehydrates from DB on configure() — resume from first unscored hole
// - No new schema; uses existing ScorecardRepository methods

import Foundation
import GRDB

@Observable
class ActiveRoundStore {
    // MARK: - Published State

    var holes: [CourseHoleRecord] = []
    var scores: [Int: Int] = [:]  // holeNumber -> strokes
    var currentHoleIndex: Int = 0
    var isCompleting: Bool = false
    var isLoaded: Bool = false

    // MARK: - Identity

    private(set) var roundId: Int64 = 0
    private(set) var courseHash: String = ""
    private var dbQueue: DatabaseQueue?

    // MARK: - Computed Properties

    var currentHole: CourseHoleRecord? {
        guard !holes.isEmpty, currentHoleIndex < holes.count else { return nil }
        return holes[currentHoleIndex]
    }

    var currentStrokes: Int {
        guard let hole = currentHole else { return 0 }
        return scores[hole.holeNumber] ?? hole.par
    }

    var holesScored: Int {
        holes.filter { scores[$0.holeNumber] != nil }.count
    }

    var totalStrokes: Int {
        holes.reduce(0) { sum, hole in
            sum + (scores[hole.holeNumber] ?? 0)
        }
    }

    var totalPar: Int {
        holes.reduce(0) { $0 + $1.par }
    }

    var scoreToPar: String {
        let diff = totalStrokes - totalPar
        if diff == 0 { return "E" }
        return diff > 0 ? "+\(diff)" : "\(diff)"
    }

    var isFinishEnabled: Bool {
        !holes.isEmpty && holesScored >= holes.count && !isCompleting
    }

    var isOnLastHole: Bool {
        !holes.isEmpty && currentHoleIndex == holes.count - 1
    }

    // MARK: - Configuration

    /// Configure the store for a specific round. Loads state from DB.
    /// Call once per active round — do not call again unless roundId changes.
    func configure(roundId: Int64, courseHash: String, dbQueue: DatabaseQueue) {
        // Skip reconfigure if already loaded for this round
        guard self.roundId != roundId else { return }

        self.roundId = roundId
        self.courseHash = courseHash
        self.dbQueue = dbQueue
        self.isLoaded = false

        loadData()
    }

    // MARK: - Actions

    func incrementStrokes() {
        guard let hole = currentHole else { return }
        let current = scores[hole.holeNumber] ?? hole.par
        if current < 20 {
            scores[hole.holeNumber] = current + 1
        }
    }

    func decrementStrokes() {
        guard let hole = currentHole else { return }
        let current = scores[hole.holeNumber] ?? hole.par
        if current > 1 {
            scores[hole.holeNumber] = current - 1
        }
    }

    func advanceHole() {
        saveCurrentScore()
        if currentHoleIndex < holes.count - 1 {
            currentHoleIndex += 1
            ensureCurrentHoleHasDefault()
        }
    }

    func retreatHole() {
        saveCurrentScore()
        if currentHoleIndex > 0 {
            currentHoleIndex -= 1
            ensureCurrentHoleHasDefault()
        }
    }

    func finishRound(dismiss: @escaping () -> Void) {
        guard let dbQueue = dbQueue else { return }
        isCompleting = true

        saveCurrentScore()

        do {
            let roundRepo = RoundRepository(dbQueue: dbQueue)
            try roundRepo.completeRound(roundId: roundId)
            dismiss()
        } catch {
            print("[RAID] Failed to complete round: \(error)")
            isCompleting = false
        }
    }

    /// Whether the finish confirmation alert should be shown.
    var showFinishConfirmation: Bool = false

    /// Called when user taps Finish — shows confirmation first.
    func requestFinish() {
        saveCurrentScore()
        showFinishConfirmation = true
    }

    // MARK: - Persistence

    /// Populate the current hole's default par in memory if no entry exists.
    /// This ensures holesScored and isFinishEnabled reflect the current hole
    /// immediately on arrival, not just after navigating away.
    private func ensureCurrentHoleHasDefault() {
        guard let hole = currentHole, scores[hole.holeNumber] == nil else { return }
        scores[hole.holeNumber] = hole.par
    }

    /// Always persist the displayed value — including default par.
    /// Append-only: each call inserts a new row in hole_scores.
    private func saveCurrentScore() {
        guard let dbQueue = dbQueue, let hole = currentHole else { return }

        let strokes = scores[hole.holeNumber] ?? hole.par
        scores[hole.holeNumber] = strokes  // Mark as scored in memory

        do {
            let scoreRepo = HoleScoreRepository(dbQueue: dbQueue)
            let input = HoleScoreInput(holeNumber: hole.holeNumber, strokes: strokes)
            _ = try scoreRepo.recordScore(roundId: roundId, score: input)
        } catch {
            print("[RAID] Failed to save score: \(error)")
        }
    }

    /// Load state from DB. Sequential repo calls — no nested reads.
    /// Resumes at first unscored hole, or last hole if all scored.
    private func loadData() {
        guard let dbQueue = dbQueue else { return }

        do {
            let courseRepo = CourseSnapshotRepository(dbQueue: dbQueue)
            holes = try courseRepo.fetchHoles(forCourse: courseHash)

            let scoreRepo = HoleScoreRepository(dbQueue: dbQueue)
            let existingScores = try scoreRepo.fetchLatestScores(forRound: roundId)

            scores = [:]
            for score in existingScores {
                scores[score.holeNumber] = score.strokes
            }

            // Resume at first unscored hole; if all scored, stay at last hole
            if let firstUnscored = holes.firstIndex(where: { scores[$0.holeNumber] == nil }) {
                currentHoleIndex = firstUnscored
            } else if !holes.isEmpty {
                currentHoleIndex = holes.count - 1
            }

            // Populate default par in memory for the starting hole so
            // holesScored/isFinishEnabled reflect it immediately
            ensureCurrentHoleHasDefault()

            isLoaded = true
        } catch {
            print("[RAID] Failed to load round data: \(error)")
        }
    }
}
