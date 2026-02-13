// ActiveRoundStore.swift
// Gambit Golf
//
// Long-lived view model for active round scoring state.
// Owns holes, scores, navigation index, player state, and persistence logic.
// Created at the RoundsView level so state survives view recreation.
//
// Invariants:
// - Append-only inserts into hole_scores (no UPDATE/DELETE)
// - saveCurrentScore() always persists the displayed value (including default par)
// - Rehydrates from DB on configure() — resume from first unscored hole
// - Supports multi-player scoring: scores keyed by playerIndex -> holeNumber -> strokes
// - Backward compat: solo rounds (no round_players rows) use playerIndex 0

import Foundation
import GRDB

@Observable
class ActiveRoundStore {
    // MARK: - Published State

    var holes: [CourseHoleRecord] = []
    var scores: [Int: [Int: Int]] = [:]  // playerIndex -> (holeNumber -> strokes)
    var players: [RoundPlayerRecord] = []
    var currentHoleIndex: Int = 0
    var currentPlayerIndex: Int = 0
    var isCompleting: Bool = false
    var isLoaded: Bool = false
    var errorMessage: String?

    // MARK: - Identity

    private(set) var roundId: Int64 = 0
    private(set) var courseHash: String = ""
    private var dbQueue: DatabaseQueue?

    // MARK: - Computed Properties

    var currentHole: CourseHoleRecord? {
        guard !holes.isEmpty, currentHoleIndex < holes.count else { return nil }
        return holes[currentHoleIndex]
    }

    var isMultiplayer: Bool {
        players.count > 1
    }

    var currentStrokes: Int {
        guard let hole = currentHole else { return 0 }
        return scores[currentPlayerIndex]?[hole.holeNumber] ?? hole.par
    }

    var holesScored: Int {
        holes.filter { scores[currentPlayerIndex]?[$0.holeNumber] != nil }.count
    }

    var totalStrokes: Int {
        holes.reduce(0) { sum, hole in
            sum + (scores[currentPlayerIndex]?[hole.holeNumber] ?? 0)
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
        guard !holes.isEmpty, !isCompleting else { return false }

        // If multiplayer, all players must have all holes scored
        if isMultiplayer {
            for player in players {
                let playerHolesScored = holes.filter { scores[player.playerIndex]?[$0.holeNumber] != nil }.count
                if playerHolesScored < holes.count {
                    return false
                }
            }
            return true
        } else {
            // Solo: only player 0 needs all holes scored
            let player0HolesScored = holes.filter { scores[0]?[$0.holeNumber] != nil }.count
            return player0HolesScored >= holes.count
        }
    }

    var isOnLastHole: Bool {
        !holes.isEmpty && currentHoleIndex == holes.count - 1
    }

    /// Short label for player (P1, P2, etc.) for segmented picker
    func playerLabel(for index: Int) -> String {
        "P\(index + 1)"
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

        // Ensure player's scores dict exists
        if scores[currentPlayerIndex] == nil {
            scores[currentPlayerIndex] = [:]
        }

        let current = scores[currentPlayerIndex]?[hole.holeNumber] ?? hole.par
        if current < 20 {
            scores[currentPlayerIndex]?[hole.holeNumber] = current + 1
        }
    }

    func decrementStrokes() {
        guard let hole = currentHole else { return }

        // Ensure player's scores dict exists
        if scores[currentPlayerIndex] == nil {
            scores[currentPlayerIndex] = [:]
        }

        let current = scores[currentPlayerIndex]?[hole.holeNumber] ?? hole.par
        if current > 1 {
            scores[currentPlayerIndex]?[hole.holeNumber] = current - 1
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

    func switchPlayer(to index: Int) {
        saveCurrentScore()
        currentPlayerIndex = index
        ensureCurrentHoleHasDefault()
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
            print("[Gambit] Failed to complete round: \(error)")
            errorMessage = "Could not finish round. Please try again."
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
        guard let hole = currentHole else { return }

        // Ensure player's scores dict exists
        if scores[currentPlayerIndex] == nil {
            scores[currentPlayerIndex] = [:]
        }

        // Populate default if not already scored
        if scores[currentPlayerIndex]?[hole.holeNumber] == nil {
            scores[currentPlayerIndex]?[hole.holeNumber] = hole.par
        }
    }

    /// Always persist the displayed value — including default par.
    /// Append-only: each call inserts a new row in hole_scores.
    private func saveCurrentScore() {
        guard let dbQueue = dbQueue, let hole = currentHole else { return }

        let strokes = scores[currentPlayerIndex]?[hole.holeNumber] ?? hole.par

        // Ensure player's scores dict exists and mark as scored
        if scores[currentPlayerIndex] == nil {
            scores[currentPlayerIndex] = [:]
        }
        scores[currentPlayerIndex]?[hole.holeNumber] = strokes

        do {
            let scoreRepo = HoleScoreRepository(dbQueue: dbQueue)
            let input = HoleScoreInput(holeNumber: hole.holeNumber, strokes: strokes)
            _ = try scoreRepo.recordScore(roundId: roundId, playerIndex: currentPlayerIndex, score: input)
        } catch {
            print("[Gambit] Failed to save score: \(error)")
            errorMessage = "Could not save score for this hole."
        }
    }

    /// Load state from DB. Sequential repo calls — no nested reads.
    /// Resumes at first unscored hole for player 0, or last hole if all scored.
    private func loadData() {
        guard let dbQueue = dbQueue else { return }

        do {
            // Load course holes
            let courseRepo = CourseSnapshotRepository(dbQueue: dbQueue)
            holes = try courseRepo.fetchHoles(forCourse: courseHash)

            // Load players (ordered by player_index)
            let playerRepo = RoundPlayerRepository(dbQueue: dbQueue)
            players = try playerRepo.fetchPlayers(forRound: roundId)

            // Load scores
            let scoreRepo = HoleScoreRepository(dbQueue: dbQueue)
            scores = [:]

            if players.count > 1 {
                // Multiplayer: load all players' scores
                let allScores = try scoreRepo.fetchAllPlayersLatestScores(forRound: roundId)
                for (playerIndex, playerScores) in allScores {
                    scores[playerIndex] = [:]
                    for score in playerScores {
                        scores[playerIndex]?[score.holeNumber] = score.strokes
                    }
                }
            } else {
                // Solo or pre-6C rounds: load player 0 only
                let existingScores = try scoreRepo.fetchLatestScores(forRound: roundId, playerIndex: 0)
                scores[0] = [:]
                for score in existingScores {
                    scores[0]?[score.holeNumber] = score.strokes
                }
            }

            // Resume at first unscored hole for player 0; if all scored, stay at last hole
            if let firstUnscored = holes.firstIndex(where: { scores[0]?[$0.holeNumber] == nil }) {
                currentHoleIndex = firstUnscored
            } else if !holes.isEmpty {
                currentHoleIndex = holes.count - 1
            }

            // Populate default par in memory for the starting hole so
            // holesScored/isFinishEnabled reflect it immediately
            ensureCurrentHoleHasDefault()

            isLoaded = true
        } catch {
            print("[Gambit] Failed to load round data: \(error)")
            errorMessage = "Could not load round data."
        }
    }
}
