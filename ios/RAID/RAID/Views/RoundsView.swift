// RoundsView.swift
// Gambit Golf
//
// Rounds list view.
// Owns ActiveRoundStore so scoring state survives view recreation.

import SwiftUI
import GRDB

struct RoundsView: View {
    let dbQueue: DatabaseQueue

    @Environment(\.nostrService) private var nostrService
    @State private var rounds: [RoundListItem] = []
    @State private var showingCreateRound = false
    @State private var showingJoinRound = false
    @State private var navigationTarget: NavigationTarget?
    @State private var activeRoundStore: ActiveRoundStore?
    @State private var errorMessage: String?
    @State private var showNostrProfile = false
    @State private var ownProfile: NostrProfile?

    // Multi-device setup sheet state
    @State private var showSetupSheet = false
    @State private var setupRoundId: Int64?
    @State private var setupCourseHash: String?

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
                        ProfileAvatarView(pictureURL: ownProfile?.picture, size: 28)
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingCreateRound = true
                        } label: {
                            Label("New Round", systemImage: "plus")
                        }
                        Button {
                            showingJoinRound = true
                        } label: {
                            Label("Join Round", systemImage: "person.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showNostrProfile, onDismiss: {
                Task { await fetchOwnProfile() }
            }) {
                NostrProfileView()
            }
            .sheet(isPresented: $showingCreateRound) {
                CreateRoundView(dbQueue: dbQueue) { roundId, courseHash, playerPubkeys, isMultiDevice in
                    showingCreateRound = false
                    loadRounds()

                    if isMultiDevice {
                        // Show setup sheet — navigation happens after dismiss
                        setupRoundId = roundId
                        setupCourseHash = courseHash
                        Task { await publishInitiation(roundId: roundId, courseHash: courseHash) }
                        // Small delay to let CreateRound sheet dismiss before presenting setup sheet
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showSetupSheet = true
                        }
                    } else {
                        navigateToScoreEntry(roundId: roundId, courseHash: courseHash, isMultiDevice: false)
                    }
                }
            }
            .sheet(isPresented: $showingJoinRound) {
                JoinRoundView(dbQueue: dbQueue) { roundId, courseHash in
                    loadRounds()
                    navigateToScoreEntry(roundId: roundId, courseHash: courseHash, isMultiDevice: true)
                }
            }
            .sheet(isPresented: $showSetupSheet, onDismiss: {
                if let roundId = setupRoundId, let courseHash = setupCourseHash {
                    navigateToScoreEntry(roundId: roundId, courseHash: courseHash, isMultiDevice: true)
                    setupRoundId = nil
                    setupCourseHash = nil
                }
            }) {
                if let roundId = setupRoundId {
                    RoundSetupSheet(roundId: roundId, dbQueue: dbQueue)
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
            .task {
                loadRounds()
                await fetchOwnProfile()
            }
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
                        let isMultiDevice = fetchIsMultiDevice(forRoundId: round.roundId)
                        navigateToScoreEntry(roundId: round.roundId, courseHash: courseHash, isMultiDevice: isMultiDevice)
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
    private func navigateToScoreEntry(roundId: Int64, courseHash: String, isMultiDevice: Bool = false) {
        // Reuse existing store if same round; otherwise create new one
        if activeRoundStore?.roundId != roundId {
            let store = ActiveRoundStore()
            store.configure(roundId: roundId, courseHash: courseHash, dbQueue: dbQueue, nostrService: nostrService, isMultiDevice: isMultiDevice)
            activeRoundStore = store
        }
        navigationTarget = .scoreEntry(roundId: roundId)
    }

    private func fetchIsMultiDevice(forRoundId roundId: Int64) -> Bool {
        let nostrRepo = RoundNostrRepository(dbQueue: dbQueue)
        guard let record = try? nostrRepo.fetchInitiation(forRound: roundId) else { return false }
        return record.joinedVia == "joined" || record.joinedVia == "created_multi"
    }

    // MARK: - Nostr Publishing

    /// Publish kind 1501 (round initiation) in the background after round creation.
    /// Best-effort: failure is logged but does not affect the round.
    /// If publish fails, RoundDetailView handles fallback (publishes both 1501 + 1502 at share time).
    private func publishInitiation(roundId: Int64, courseHash: String) async {
        do {
            let courseRepo = CourseSnapshotRepository(dbQueue: dbQueue)
            guard let snapshot = try courseRepo.fetchCourseSnapshot(byHash: courseHash) else {
                print("[Gambit] Initiation publish skipped: course snapshot not found")
                return
            }
            let holes = try courseRepo.fetchHoles(forCourse: courseHash)

            let content = NIP101gEventBuilder.buildInitiationContent(snapshot: snapshot, holes: holes)
            let computedCourseHash = try NIP101gEventBuilder.computeCourseHash(content: content)
            let rulesHash = try NIP101gEventBuilder.computeRulesHash(content: content)

            let roundDate: String = try await dbQueue.read { db in
                try String.fetchOne(
                    db,
                    sql: "SELECT round_date FROM rounds WHERE round_id = ?",
                    arguments: [roundId]
                )
            } ?? ISO8601DateFormatter().string(from: Date())

            // Re-read player pubkeys from DB to include creator
            let playerRepo = RoundPlayerRepository(dbQueue: dbQueue)
            let playerPubkeys = try playerRepo.fetchPlayerPubkeys(forRound: roundId)

            let keyManager = try KeyManager.loadOrCreate()
            let keys = keyManager.signingKeys()

            let builder = try NIP101gEventBuilder.buildInitiationEvent(
                content: content,
                courseHash: computedCourseHash,
                rulesHash: rulesHash,
                playerPubkeys: playerPubkeys,
                date: roundDate
            )

            let eventId = try await nostrService.publishEvent(keys: keys, builder: builder)

            let nostrRepo = RoundNostrRepository(dbQueue: dbQueue)
            try nostrRepo.insertInitiation(roundId: roundId, initiationEventId: eventId, joinedVia: "created_multi")
            print("[Gambit] Kind 1501 published for round \(roundId): \(eventId)")
        } catch {
            print("[Gambit] Kind 1501 publish failed for round \(roundId): \(error)")
        }
    }

    // MARK: - Profile

    private func fetchOwnProfile() async {
        guard let keyManager = try? KeyManager.loadOrCreate() else { return }
        let hex = keyManager.signingKeys().publicKey().toHex()
        if let profiles = try? await nostrService.resolveProfiles(pubkeyHexes: [hex]) {
            ownProfile = profiles[hex]
        }
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
