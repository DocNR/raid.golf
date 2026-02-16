// CreateRoundView.swift
// RAID Golf
//
// Create new round form with optional player selection from Nostr follow list.

import SwiftUI
import GRDB
import NostrSDK

struct CreateRoundView: View {
    let dbQueue: DatabaseQueue
    let onRoundCreated: (Int64, String, [String], Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.nostrService) private var nostrService

    @State private var courseName = ""
    @State private var teeSet = ""
    @State private var holeSelection: HoleSelection = .eighteen
    @State private var pars: [Int] = Array(repeating: 4, count: 18)
    @State private var isCreating = false
    @State private var errorMessage: String?

    // Player selection state
    @State private var hasNostrKeys = false
    @State private var creatorPubkeyHex: String?
    @State private var selectedPlayers: [String: NostrProfile] = [:]
    @State private var followProfiles: [String: NostrProfile] = [:]
    @State private var followOrder: [String] = []
    @State private var isLoadingFollows = false
    @State private var followLoadError: String?
    @State private var npubInput = ""
    @State private var npubError: String?
    @State private var isMultiDevice = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Course Details") {
                    TextField("Course Name", text: $courseName)
                    TextField("Tee Set", text: $teeSet)
                    Picker("Holes", selection: $holeSelection) {
                        Text("Front 9").tag(HoleSelection.front9)
                        Text("Back 9").tag(HoleSelection.back9)
                        Text("18").tag(HoleSelection.eighteen)
                    }
                    .onChange(of: holeSelection) { _, newValue in
                        adjustParsArray(to: newValue.holeCount)
                    }
                }

                playersSection

                Section("Par for Each Hole") {
                    ForEach(0..<holeSelection.holeCount, id: \.self) { index in
                        let holeNumber = holeSelection.startingHole + index
                        HStack {
                            Text("Hole \(holeNumber)")
                                .frame(width: 80, alignment: .leading)
                            Spacer()
                            Stepper(
                                value: Binding(
                                    get: { pars[index] },
                                    set: { pars[index] = $0 }
                                ),
                                in: 3...5
                            ) {
                                Text("Par \(pars[index])")
                                    .frame(width: 60, alignment: .trailing)
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Round")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isCreating)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Start Round") {
                        startRound()
                    }
                    .disabled(courseName.isEmpty || teeSet.isEmpty || isCreating)
                }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
            .task { checkNostrKeys() }
        }
    }

    // MARK: - Players Section

    @ViewBuilder
    private var playersSection: some View {
        Section {
            if !hasNostrKeys {
                Text("Set up Nostr identity to invite players")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                // Manual npub entry
                HStack {
                    TextField("Add player by npub...", text: $npubInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit { addPlayerByNpub() }
                    Button("Add") { addPlayerByNpub() }
                        .disabled(npubInput.isEmpty)
                }
                if let npubError {
                    Text(npubError)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                // Follow list loading
                if followOrder.isEmpty && !isLoadingFollows {
                    Button {
                        Task { await loadFollowList() }
                    } label: {
                        Label("Load Follow List", systemImage: "person.2")
                    }
                }

                if isLoadingFollows {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading follows...")
                            .foregroundStyle(.secondary)
                    }
                }

                if let followLoadError {
                    Text(followLoadError)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                // Follow list (selectable)
                ForEach(followOrder, id: \.self) { pubkeyHex in
                    if let profile = followProfiles[pubkeyHex] {
                        let isSelected = selectedPlayers[pubkeyHex] != nil
                        Button {
                            togglePlayer(pubkeyHex: pubkeyHex, profile: profile)
                        } label: {
                            HStack(spacing: 10) {
                                ProfileAvatarView(pictureURL: profile.picture, size: 32)
                                Text(profile.displayLabel)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }

                // Selected players (manually added, not in follow list)
                let manuallyAdded = selectedPlayers.filter { followProfiles[$0.key] == nil }
                ForEach(Array(manuallyAdded.values)) { profile in
                    Button {
                        selectedPlayers.removeValue(forKey: profile.pubkeyHex)
                    } label: {
                        HStack(spacing: 10) {
                            ProfileAvatarView(pictureURL: profile.picture, size: 32)
                            Text(profile.displayLabel)
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }

                // Multi-device toggle
                if !selectedPlayers.isEmpty {
                    Toggle("Each player uses their own device", isOn: $isMultiDevice)
                }
            }
        } header: {
            HStack {
                Text("Players")
                if !selectedPlayers.isEmpty {
                    Text("(\(selectedPlayers.count))")
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            if hasNostrKeys {
                Text("Optional. Select playing partners or add by npub.")
            }
        }
    }

    // MARK: - Player Actions

    private func checkNostrKeys() {
        do {
            let keyManager = try KeyManager.loadOrCreate()
            let keys = keyManager.signingKeys()
            creatorPubkeyHex = keys.publicKey().toHex()
            hasNostrKeys = true
        } catch {
            hasNostrKeys = false
        }
    }

    private func loadFollowList() async {
        guard let creatorHex = creatorPubkeyHex else { return }
        isLoadingFollows = true
        followLoadError = nil

        do {
            let pubkey = try PublicKey.parse(publicKey: creatorHex)
            let result = try await nostrService.fetchFollowListWithProfiles(pubkey: pubkey)
            followOrder = result.follows
            followProfiles = result.profiles
            // Fill in profiles for follows that had no kind 0
            for hex in result.follows where followProfiles[hex] == nil {
                followProfiles[hex] = NostrProfile(pubkeyHex: hex, name: nil, displayName: nil, picture: nil)
            }
        } catch {
            followLoadError = "Could not load follow list."
            print("[RAID] Follow list load failed: \(error)")
        }

        isLoadingFollows = false
    }

    private func togglePlayer(pubkeyHex: String, profile: NostrProfile) {
        if selectedPlayers[pubkeyHex] != nil {
            selectedPlayers.removeValue(forKey: pubkeyHex)
        } else {
            selectedPlayers[pubkeyHex] = profile
        }
    }

    private func addPlayerByNpub() {
        npubError = nil
        let input = npubInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        do {
            let pubkey = try PublicKey.parse(publicKey: input)
            let hex = pubkey.toHex()

            // Prevent adding self
            if hex == creatorPubkeyHex {
                npubError = "That's your own key."
                return
            }

            // Prevent duplicate
            if selectedPlayers[hex] != nil {
                npubError = "Player already added."
                return
            }

            // Use existing profile if we have it, otherwise create minimal one
            let profile = followProfiles[hex] ?? NostrProfile(pubkeyHex: hex, name: nil, displayName: nil, picture: nil)
            selectedPlayers[hex] = profile
            npubInput = ""

            // Fetch profile from relays in background (if not already known)
            if followProfiles[hex] == nil {
                Task {
                    if let profiles = try? await nostrService.resolveProfiles(pubkeyHexes: [hex]),
                       let fetched = profiles[hex] {
                        selectedPlayers[hex] = fetched
                    }
                }
            }
        } catch {
            npubError = "Invalid npub or hex key."
        }
    }

    // MARK: - Round Creation

    private func adjustParsArray(to newCount: Int) {
        if pars.count < newCount {
            pars.append(contentsOf: Array(repeating: 4, count: newCount - pars.count))
        } else if pars.count > newCount {
            pars = Array(pars.prefix(newCount))
        }
    }

    private func startRound() {
        isCreating = true

        do {
            let startHole = holeSelection.startingHole
            let holes = (0..<holeSelection.holeCount).map { index in
                HoleDefinition(holeNumber: startHole + index, par: pars[index])
            }

            let courseInput = CourseSnapshotInput(
                courseName: courseName,
                teeSet: teeSet,
                holes: holes
            )
            let courseRepo = CourseSnapshotRepository(dbQueue: dbQueue)
            let courseSnapshot = try courseRepo.insertCourseSnapshot(courseInput)

            let roundDate = ISO8601DateFormatter().string(from: Date())
            let roundRepo = RoundRepository(dbQueue: dbQueue)
            let round = try roundRepo.createRound(
                courseHash: courseSnapshot.courseHash,
                roundDate: roundDate
            )

            // Insert round players if Nostr keys are available
            var allPlayerPubkeys: [String] = []
            if let creatorHex = creatorPubkeyHex {
                let otherPubkeys = Array(selectedPlayers.keys)
                let playerRepo = RoundPlayerRepository(dbQueue: dbQueue)
                try playerRepo.insertPlayers(
                    roundId: round.roundId,
                    creatorPubkey: creatorHex,
                    otherPubkeys: otherPubkeys
                )
                allPlayerPubkeys = [creatorHex] + otherPubkeys
            }

            onRoundCreated(round.roundId, courseSnapshot.courseHash, allPlayerPubkeys, isMultiDevice)

        } catch {
            isCreating = false
            errorMessage = error.localizedDescription
        }
    }
}

private enum HoleSelection: Hashable {
    case front9
    case back9
    case eighteen

    var holeCount: Int {
        switch self {
        case .front9, .back9: return 9
        case .eighteen: return 18
        }
    }

    var startingHole: Int {
        switch self {
        case .front9: return 1
        case .back9: return 10
        case .eighteen: return 1
        }
    }
}
