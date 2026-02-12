// RoundsView.swift
// Gambit Golf
//
// Rounds list view.
// Owns ActiveRoundStore so scoring state survives view recreation.

import SwiftUI
import GRDB

struct RoundsView: View {
    let dbQueue: DatabaseQueue

    @State private var rounds: [RoundListItem] = []
    @State private var showingCreateRound = false
    @State private var navigationTarget: NavigationTarget?
    @State private var activeRoundStore: ActiveRoundStore?
    @State private var errorMessage: String?
    @State private var showNostrProfile = false

    var body: some View {
        NavigationStack {
            Group {
                if rounds.isEmpty {
                    emptyState
                } else {
                    roundsList
                }
            }
            .navigationTitle("Rounds")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showNostrProfile = true
                    } label: {
                        Image(systemName: "person.circle")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreateRound = true
                    } label: {
                        Label("New Round", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showNostrProfile) {
                NostrProfileView()
            }
            .sheet(isPresented: $showingCreateRound) {
                CreateRoundView(dbQueue: dbQueue) { roundId, courseHash in
                    showingCreateRound = false
                    loadRounds()
                    navigateToScoreEntry(roundId: roundId, courseHash: courseHash)
                }
            }
            .navigationDestination(item: $navigationTarget) { target in
                switch target {
                case .scoreEntry:
                    if let store = activeRoundStore {
                        ScoreEntryView(store: store)
                    }
                case .roundDetail(let roundId):
                    RoundDetailView(roundId: roundId, dbQueue: dbQueue)
                }
            }
            .task { loadRounds() }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Rounds", systemImage: "tray")
        } description: {
            Text("Track your on-course scores hole-by-hole. Tap + to start a new round.")
        } actions: {
            Button("New Round") {
                showingCreateRound = true
            }
        }
    }

    private var roundsList: some View {
        List(rounds, id: \.roundId) { round in
            Button {
                if round.isCompleted {
                    navigationTarget = .roundDetail(roundId: round.roundId)
                } else {
                    if let courseHash = fetchCourseHash(forRoundId: round.roundId) {
                        navigateToScoreEntry(roundId: round.roundId, courseHash: courseHash)
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(round.courseName)
                            .font(.headline)
                        Spacer()
                        if round.isCompleted, let totalStrokes = round.totalStrokes {
                            Text("\(totalStrokes)")
                                .foregroundStyle(.primary)
                        } else {
                            Text("(\(round.holesScored)/\(round.holeCount)) In Progress")
                                .foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text(formatDate(round.roundDate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\u{2022}")
                            .foregroundStyle(.secondary)
                        Text(round.teeSet)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\u{2022}")
                            .foregroundStyle(.secondary)
                        Text("\(round.holeCount) holes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .refreshable { loadRounds() }
    }

    // MARK: - Navigation

    /// Create or reconfigure the store for a specific round, then navigate.
    private func navigateToScoreEntry(roundId: Int64, courseHash: String) {
        // Reuse existing store if same round; otherwise create new one
        if activeRoundStore?.roundId != roundId {
            let store = ActiveRoundStore()
            store.configure(roundId: roundId, courseHash: courseHash, dbQueue: dbQueue)
            activeRoundStore = store
        }
        navigationTarget = .scoreEntry(roundId: roundId)
    }

    // MARK: - Data Loading

    private func loadRounds() {
        do {
            let repo = RoundRepository(dbQueue: dbQueue)
            rounds = try repo.listRounds()
        } catch {
            print("[Gambit] Failed to load rounds: \(error)")
        }
    }

    private func formatDate(_ isoDate: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoDate) else { return isoDate }
        let display = DateFormatter()
        display.dateStyle = .medium
        return display.string(from: date)
    }

    private func fetchCourseHash(forRoundId roundId: Int64) -> String? {
        do {
            return try dbQueue.read { db in
                try String.fetchOne(
                    db,
                    sql: "SELECT course_hash FROM rounds WHERE round_id = ?",
                    arguments: [roundId]
                )
            }
        } catch {
            print("[Gambit] Failed to fetch courseHash: \(error)")
            errorMessage = "Could not load round data."
            return nil
        }
    }
}

private enum NavigationTarget: Identifiable, Hashable {
    case scoreEntry(roundId: Int64)
    case roundDetail(roundId: Int64)

    var id: String {
        switch self {
        case .scoreEntry(let roundId):
            return "score-\(roundId)"
        case .roundDetail(let roundId):
            return "detail-\(roundId)"
        }
    }
}
