// CreateRoundView.swift
// RAID Golf
//
// Create new round form. Player selection via sheet with search + follow browse.

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
    @State private var isMultiDevice = false
    @State private var showPlayerPicker = false

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
                    Button("Cancel") { dismiss() }
                        .disabled(isCreating)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Start Round") { startRound() }
                        .disabled(courseName.isEmpty || teeSet.isEmpty || isCreating)
                }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let error = errorMessage { Text(error) }
            }
            .task {
                checkNostrKeys()
                seedProfileCache()
            }
            .sheet(isPresented: $showPlayerPicker) {
                PlayerPickerSheet(
                    dbQueue: dbQueue,
                    creatorPubkeyHex: creatorPubkeyHex,
                    selectedPlayers: $selectedPlayers
                )
            }
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
                Button {
                    showPlayerPicker = true
                } label: {
                    HStack(spacing: 10) {
                        if selectedPlayers.isEmpty {
                            Label("Add Playing Partners", systemImage: "person.badge.plus")
                        } else {
                            playerSummaryRow
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.primary)
                }

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

    private func playerSummaryLabel() -> String {
        let sorted = Array(selectedPlayers.values).sorted { $0.displayLabel < $1.displayLabel }
        let names: [String] = sorted.prefix(2).map { $0.displayLabel }
        let overflow = sorted.count - 2
        if overflow > 0 {
            return names.joined(separator: ", ") + " +\(overflow) more"
        }
        return names.joined(separator: ", ")
    }

    private func playerSummaryAvatars() -> [NostrProfile] {
        Array(selectedPlayers.values)
            .sorted { $0.displayLabel < $1.displayLabel }
            .prefix(3)
            .map { $0 }
    }

    private var playerSummaryRow: some View {
        HStack(spacing: 6) {
            HStack(spacing: -8) {
                ForEach(playerSummaryAvatars()) { profile in
                    ProfileAvatarView(pictureURL: profile.picture, size: 28)
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
                }
            }
            Text(playerSummaryLabel())
                .font(.subheadline)
                .lineLimit(1)
        }
    }

    // MARK: - Helpers

    private func seedProfileCache() {
        let profiles = nostrService.profileCache
        guard !profiles.isEmpty else { return }
        let repo = ProfileCacheRepository(dbQueue: dbQueue)
        try? repo.upsertProfiles(Array(profiles.values))
    }

    private func checkNostrKeys() {
        guard UserDefaults.standard.bool(forKey: "nostrActivated") else {
            hasNostrKeys = false
            return
        }
        creatorPubkeyHex = KeyManager.publicKeyHex()
        hasNostrKeys = creatorPubkeyHex != nil
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

// MARK: - Player Picker Sheet

private struct PlayerPickerSheet: View {
    let dbQueue: DatabaseQueue
    let creatorPubkeyHex: String?
    @Binding var selectedPlayers: [String: NostrProfile]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.nostrService) private var nostrService

    @State private var searchQuery = ""
    @State private var searchResults: [NostrProfile] = []
    @State private var followProfiles: [String: NostrProfile] = [:]
    @State private var followOrder: [String] = []
    @State private var isLoadingFollows = false
    @State private var followLoadError: String?
    // Clubhouse members (loaded from GRDB)
    @State private var clubhouseProfiles: [NostrProfile] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search by name or npub", text: $searchQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !searchQuery.isEmpty {
                        Button { searchQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 4)

                List {
                    selectedSection
                    clubhouseSection
                    followsSection
                    addByKeySection
                }
            }
            .onChange(of: searchQuery) { _, _ in performSearch() }
            .navigationTitle("Add Players")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(selectedPlayers.isEmpty ? "Done" : "Done (\(selectedPlayers.count))") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadClubhouseMembers()
                await loadFollowList()
            }
        }
    }

    // MARK: - Extracted Sections

    @ViewBuilder
    private var selectedSection: some View {
        if !selectedPlayers.isEmpty {
            Section("In This Round") {
                ForEach(sortedSelected) { profile in
                    HStack(spacing: 10) {
                        ProfileAvatarView(pictureURL: profile.picture, size: 36)
                        Text(profile.displayLabel)
                            .foregroundStyle(.primary)
                        Spacer()
                        Button {
                            selectedPlayers.removeValue(forKey: profile.pubkeyHex)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var clubhouseSection: some View {
        if !clubhouseProfiles.isEmpty {
            Section("Favorites") {
                ForEach(clubhouseProfiles) { profile in
                    followRow(profile: profile)
                }
            }
        }
    }

    @ViewBuilder
    private var followsSection: some View {
        Section("Follows") {
            if isLoadingFollows && followOrder.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading follows...")
                        .foregroundStyle(.secondary)
                }
            } else if let error = followLoadError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            } else {
                followsListContent
            }
        }
    }

    @ViewBuilder
    private var followsListContent: some View {
        let displayList: [NostrProfile] = searchQuery.count >= 2
            ? searchResults
            : followOrder.compactMap { followProfiles[$0] }

        if displayList.isEmpty && searchQuery.count >= 2 {
            Text("No results. Try adding by npub below.")
                .foregroundStyle(.secondary)
                .font(.caption)
        }

        ForEach(displayList, id: \.pubkeyHex) { profile in
            followRow(profile: profile)
        }
    }

    private func followRow(profile: NostrProfile) -> some View {
        let isSelected = selectedPlayers[profile.pubkeyHex] != nil
        return Button {
            togglePlayer(pubkeyHex: profile.pubkeyHex, profile: profile)
        } label: {
            HStack(spacing: 10) {
                ProfileAvatarView(pictureURL: profile.picture, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayLabel)
                        .foregroundStyle(.primary)
                    if let nip05 = profile.nip05 {
                        Text(nip05)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    /// If the search text is a valid npub or hex pubkey, returns the hex.
    private var parsedSearchKeyHex: String? {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let pk = try? PublicKey.parse(publicKey: trimmed) else { return nil }
        let hex = pk.toHex()
        if hex == creatorPubkeyHex { return nil }
        return hex
    }

    @ViewBuilder
    private var addByKeySection: some View {
        if let hex = parsedSearchKeyHex {
            let profile = followProfiles[hex]
            let alreadySelected = selectedPlayers[hex] != nil

            Section("Key Match") {
                Button {
                    if !alreadySelected {
                        let p = profile ?? NostrProfile(pubkeyHex: hex, name: nil, displayName: nil, picture: nil)
                        selectedPlayers[hex] = p
                        searchQuery = ""
                        // Resolve in background if needed
                        if profile == nil {
                            Task {
                                let cacheRepo = ProfileCacheRepository(dbQueue: dbQueue)
                                if let profiles = try? await nostrService.resolveProfiles(
                                    pubkeyHexes: [hex], cacheRepo: cacheRepo
                                ), let fetched = profiles[hex] {
                                    selectedPlayers[hex] = fetched
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        ProfileAvatarView(pictureURL: profile?.picture, size: 36)
                        Text(profile?.displayLabel ?? String(hex.prefix(12)) + "...")
                            .foregroundStyle(.primary)
                        Spacer()
                        if alreadySelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        } else {
                            Text("Add")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Helpers

    private var sortedSelected: [NostrProfile] {
        Array(selectedPlayers.values).sorted { $0.displayLabel < $1.displayLabel }
    }

    private func performSearch() {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { searchResults = []; return }
        let repo = ProfileCacheRepository(dbQueue: dbQueue)
        searchResults = (try? repo.searchProfiles(query: q, limit: 20)) ?? []
    }

    private func togglePlayer(pubkeyHex: String, profile: NostrProfile) {
        if selectedPlayers[pubkeyHex] != nil {
            selectedPlayers.removeValue(forKey: pubkeyHex)
        } else {
            selectedPlayers[pubkeyHex] = profile
        }
    }


    private func loadClubhouseMembers() async {
        let repo = ClubhouseRepository(dbQueue: dbQueue)
        guard let pubkeys = try? repo.allPubkeyHexes(), !pubkeys.isEmpty else { return }
        let profileRepo = ProfileCacheRepository(dbQueue: dbQueue)

        // Phase A: instant paint from GRDB cache
        let filtered = pubkeys.filter { $0 != creatorPubkeyHex }
        if let cached = try? profileRepo.fetchProfiles(pubkeyHexes: filtered) {
            clubhouseProfiles = filtered.map { hex in
                cached[hex] ?? NostrProfile(pubkeyHex: hex, name: nil, displayName: nil, picture: nil)
            }
        } else {
            clubhouseProfiles = filtered.map {
                NostrProfile(pubkeyHex: $0, name: nil, displayName: nil, picture: nil)
            }
        }

        // Phase B: resolve uncached profiles from relay
        let unresolved = filtered.filter { hex in
            guard let p = clubhouseProfiles.first(where: { $0.pubkeyHex == hex }) else { return true }
            return p.name == nil && p.displayName == nil && p.picture == nil
        }
        if !unresolved.isEmpty {
            if let resolved = try? await nostrService.resolveProfiles(
                pubkeyHexes: unresolved, cacheRepo: profileRepo
            ) {
                for (hex, profile) in resolved {
                    if let idx = clubhouseProfiles.firstIndex(where: { $0.pubkeyHex == hex }) {
                        clubhouseProfiles[idx] = profile
                    }
                }
            }
        }
    }

    private func loadFollowList() async {
        guard let creatorHex = creatorPubkeyHex else { return }
        isLoadingFollows = true
        followLoadError = nil

        let followRepo = FollowListCacheRepository(dbQueue: dbQueue)
        let profileRepo = ProfileCacheRepository(dbQueue: dbQueue)

        // Phase A: cache-first instant paint from GRDB
        if let cached = try? followRepo.fetch(pubkeyHex: creatorHex) {
            followOrder = cached.follows
            if let cachedProfiles = try? profileRepo.fetchProfiles(pubkeyHexes: cached.follows) {
                followProfiles = cachedProfiles
                for hex in cached.follows where followProfiles[hex] == nil {
                    followProfiles[hex] = NostrProfile(pubkeyHex: hex, name: nil, displayName: nil, picture: nil)
                }
            }
        }

        // Phase B: fetch just the follow list (kind 3) — fast, single event
        do {
            let pubkey = try PublicKey.parse(publicKey: creatorHex)
            let remoteFollows = try await nostrService.fetchFollowList(pubkey: pubkey)
            if !remoteFollows.isEmpty {
                followOrder = remoteFollows
                for hex in remoteFollows where followProfiles[hex] == nil {
                    followProfiles[hex] = NostrProfile(pubkeyHex: hex, name: nil, displayName: nil, picture: nil)
                }
                try? followRepo.updateLocalFollowList(pubkeyHex: creatorHex, follows: remoteFollows)
            }
        } catch {
            if followOrder.isEmpty {
                followLoadError = "Could not load follow list."
            }
            print("[RAID] Follow list load failed: \(error)")
        }

        // Show list immediately
        isLoadingFollows = false

        // Phase C: resolve profiles via 3-layer cache
        let unresolved = followOrder.filter { hex in
            guard let p = followProfiles[hex] else { return true }
            return p.name == nil && p.displayName == nil && p.picture == nil
        }
        if !unresolved.isEmpty {
            if let resolved = try? await nostrService.resolveProfiles(
                pubkeyHexes: unresolved, cacheRepo: profileRepo
            ) {
                for (hex, profile) in resolved {
                    followProfiles[hex] = profile
                }
            }
        }
    }
}

// MARK: - Hole Selection

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
