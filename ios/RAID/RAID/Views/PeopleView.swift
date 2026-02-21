// PeopleView.swift
// RAID Golf
//
// Combined Following + Clubhouse management with segmented tabs.
// Following: NIP-02 kind 3 contact list. Clubhouse: NIP-51 kind 30000 follow set.
// Swipe left to unfollow/remove. Swipe right on Following to add to Clubhouse.
// Paste an npub into the search bar to follow or add someone new.

import SwiftUI
import GRDB
import NostrSDK

struct PeopleView: View {
    let dbQueue: DatabaseQueue

    @Environment(\.dismiss) private var dismiss
    @Environment(\.nostrService) private var nostrService

    @State private var selectedTab: PeopleTab = .following

    // Following state
    @State private var followOrder: [String] = []
    @State private var followProfiles: [String: NostrProfile] = [:]
    @State private var isLoadingFollows = false

    // Clubhouse state
    @State private var clubhouseMembers: [NostrProfile] = []
    @State private var clubhousePubkeys: [String] = []
    @State private var isLoadingClubhouse = false

    // Sheet state
    @State private var showClubhouseFollowPicker = false
    @State private var selectedPubkeyHex: String = ""
    @State private var showUserProfile = false

    @State private var searchText = ""
    @State private var errorMessage: String?

    // Resolved profile for npub pasted into search bar
    @State private var searchKeyProfile: NostrProfile?
    @State private var isResolvingSearchKey = false

    private var creatorPubkeyHex: String? {
        guard UserDefaults.standard.bool(forKey: "nostrActivated"),
              let km = try? KeyManager.loadOrCreate() else { return nil }
        return km.signingKeys().publicKey().toHex()
    }

    private enum PeopleTab: String, CaseIterable {
        case following = "Following"
        case clubhouse = "Clubhouse"
    }

    /// If the search text is a valid npub or hex pubkey, returns the hex.
    private var parsedSearchKeyHex: String? {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let pk = try? PublicKey.parse(publicKey: trimmed) else { return nil }
        let hex = pk.toHex()
        if hex == creatorPubkeyHex { return nil }
        return hex
    }

    private var filteredFollowOrder: [String] {
        guard !searchText.isEmpty else { return followOrder }
        // If search is a valid key, don't filter — show the add-key row instead
        if parsedSearchKeyHex != nil { return [] }
        let query = searchText.lowercased()
        return followOrder.filter { hex in
            guard let p = followProfiles[hex] else {
                return hex.lowercased().contains(query)
            }
            return profileMatches(p, query: query)
        }
    }

    private var filteredClubhouseMembers: [NostrProfile] {
        guard !searchText.isEmpty else { return clubhouseMembers }
        if parsedSearchKeyHex != nil { return [] }
        let query = searchText.lowercased()
        return clubhouseMembers.filter { profileMatches($0, query: query) }
    }

    private func profileMatches(_ p: NostrProfile, query: String) -> Bool {
        if let name = p.name, name.lowercased().contains(query) { return true }
        if let dn = p.displayName, dn.lowercased().contains(query) { return true }
        if let nip05 = p.nip05, nip05.lowercased().contains(query) { return true }
        if p.pubkeyHex.lowercased().contains(query) { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Tab", selection: $selectedTab) {
                    ForEach(PeopleTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                switch selectedTab {
                case .following:
                    followingList
                case .clubhouse:
                    clubhouseList
                }
            }
            .navigationTitle("People")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search or paste npub")
            .onChange(of: selectedTab) { _, _ in
                searchText = ""
                searchKeyProfile = nil
            }
            .onChange(of: searchText) { _, newValue in
                searchKeyProfile = nil
                if let hex = parsedSearchKeyHex {
                    resolveSearchKey(hex: hex)
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") { dismiss() }
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
                async let f: () = loadFollows()
                async let c: () = loadClubhouse()
                _ = await (f, c)
            }
            .sheet(isPresented: $showClubhouseFollowPicker) {
                ClubhouseFollowPicker(
                    dbQueue: dbQueue,
                    creatorPubkeyHex: creatorPubkeyHex,
                    existingMembers: Set(clubhousePubkeys),
                    onAddBatch: { selected in
                        for (hex, profile) in selected {
                            addToClubhouse(pubkeyHex: hex, profile: profile)
                        }
                    }
                )
            }
            .sheet(isPresented: $showUserProfile) {
                UserProfileSheet(pubkeyHex: selectedPubkeyHex, dbQueue: dbQueue)
            }
        }
    }

    // MARK: - Search Key Row

    @ViewBuilder
    private var searchKeyRow: some View {
        if let hex = parsedSearchKeyHex {
            let profile = searchKeyProfile
            let alreadyFollowing = followOrder.contains(hex)
            let alreadyInClubhouse = clubhousePubkeys.contains(hex)

            Section {
                HStack(spacing: 10) {
                    ProfileAvatarView(pictureURL: profile?.picture, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        if isResolvingSearchKey {
                            HStack(spacing: 6) {
                                Text(String(hex.prefix(12)) + "...")
                                    .foregroundStyle(.primary)
                                ProgressView().controlSize(.mini)
                            }
                        } else {
                            Text(profile?.displayLabel ?? String(hex.prefix(12)) + "...")
                                .foregroundStyle(.primary)
                            if let nip05 = profile?.nip05 {
                                Text(nip05)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer()
                    switch selectedTab {
                    case .following:
                        if alreadyFollowing {
                            Text("Following")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Follow") {
                                addToFollowing(pubkeyHex: hex)
                                searchText = ""
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    case .clubhouse:
                        if alreadyInClubhouse {
                            Text("Added")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Add") {
                                addToClubhouse(pubkeyHex: hex, profile: profile)
                                searchText = ""
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedPubkeyHex = hex
                    showUserProfile = true
                }
            } header: {
                Text("Key Match")
            }
        }
    }

    // MARK: - Following Tab

    @ViewBuilder
    private var followingList: some View {
        if isLoadingFollows && followOrder.isEmpty {
            loadingState
        } else if followOrder.isEmpty && parsedSearchKeyHex == nil {
            emptyState(
                icon: "person.2",
                title: "No Follows",
                message: "Paste an npub into the search bar to follow someone."
            )
        } else {
            List {
                searchKeyRow

                if !filteredFollowOrder.isEmpty {
                    Section {
                        ForEach(filteredFollowOrder, id: \.self) { hex in
                            Button {
                                selectedPubkeyHex = hex
                                showUserProfile = true
                            } label: {
                                followingRow(hex: hex)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    unfollowHex(hex)
                                } label: {
                                    Label("Unfollow", systemImage: "person.badge.minus")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                if !clubhousePubkeys.contains(hex) {
                                    Button {
                                        addToClubhouse(pubkeyHex: hex, profile: followProfiles[hex])
                                    } label: {
                                        Label("Clubhouse", systemImage: "person.crop.circle.badge.plus")
                                    }
                                    .tint(.green)
                                }
                            }
                        }
                    } header: {
                        Text("\(followOrder.count) Following")
                    } footer: {
                        Text("Swipe left to unfollow. Swipe right to add to Clubhouse.")
                    }
                }
            }
        }
    }

    private func followingRow(hex: String) -> some View {
        let profile = followProfiles[hex]
        let inClubhouse = clubhousePubkeys.contains(hex)
        return HStack(spacing: 10) {
            ProfileAvatarView(pictureURL: profile?.picture, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile?.displayLabel ?? String(hex.prefix(12)) + "...")
                    .foregroundStyle(.primary)
                if let nip05 = profile?.nip05 {
                    Text(nip05)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if inClubhouse {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Clubhouse Tab

    @ViewBuilder
    private var clubhouseList: some View {
        if isLoadingClubhouse && clubhouseMembers.isEmpty && parsedSearchKeyHex == nil {
            loadingState
        } else if clubhouseMembers.isEmpty && parsedSearchKeyHex == nil {
            emptyState(
                icon: "star",
                title: "No Clubhouse Members",
                message: "Add people from your follows or paste an npub into the search bar."
            )
        } else {
            List {
                searchKeyRow

                if !filteredClubhouseMembers.isEmpty {
                    Section {
                        ForEach(filteredClubhouseMembers) { profile in
                            Button {
                                selectedPubkeyHex = profile.pubkeyHex
                                showUserProfile = true
                            } label: {
                                profileRow(for: profile.pubkeyHex, profile: profile)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    removeFromClubhouse(pubkeyHex: profile.pubkeyHex)
                                } label: {
                                    Label("Remove", systemImage: "person.badge.minus")
                                }
                            }
                        }
                    } header: {
                        Text("\(clubhouseMembers.count) Members")
                    } footer: {
                        Text("Swipe left to remove. Syncs across devices via Nostr.")
                    }
                }

                if parsedSearchKeyHex == nil {
                    Section {
                        Button {
                            showClubhouseFollowPicker = true
                        } label: {
                            Label("Add from Follows", systemImage: "person.crop.circle.badge.plus")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Shared Views

    private func profileRow(for hex: String, profile: NostrProfile?) -> some View {
        HStack(spacing: 10) {
            ProfileAvatarView(pictureURL: profile?.picture, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile?.displayLabel ?? String(hex.prefix(12)) + "...")
                    .foregroundStyle(.primary)
                if let nip05 = profile?.nip05 {
                    Text(nip05)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var loadingState: some View {
        VStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(message)
        }
    }

    // MARK: - Search Key Resolution

    private func resolveSearchKey(hex: String) {
        // Check GRDB and in-memory cache first (synchronous)
        if let inMemory = nostrService.profileCache[hex] {
            searchKeyProfile = inMemory
            return
        }
        let profileRepo = ProfileCacheRepository(dbQueue: dbQueue)
        if let cached = try? profileRepo.fetchProfile(pubkeyHex: hex) {
            searchKeyProfile = cached
            return
        }

        // Relay resolve
        isResolvingSearchKey = true
        Task {
            let cacheRepo = ProfileCacheRepository(dbQueue: dbQueue)
            if let profiles = try? await nostrService.resolveProfiles(
                pubkeyHexes: [hex], cacheRepo: cacheRepo
            ), let resolved = profiles[hex] {
                // Only update if search text hasn't changed
                if parsedSearchKeyHex == hex {
                    searchKeyProfile = resolved
                }
            }
            isResolvingSearchKey = false
        }
    }

    // MARK: - Data Loading

    private func loadFollows() async {
        isLoadingFollows = true

        guard let myHex = creatorPubkeyHex else {
            isLoadingFollows = false
            return
        }

        // Phase A: cache-first instant paint from GRDB
        let followRepo = FollowListCacheRepository(dbQueue: dbQueue)
        let profileRepo = ProfileCacheRepository(dbQueue: dbQueue)
        if let cached = try? followRepo.fetch(pubkeyHex: myHex) {
            followOrder = cached.follows
            if let cachedProfiles = try? profileRepo.fetchProfiles(pubkeyHexes: cached.follows) {
                followProfiles = cachedProfiles
                for hex in cached.follows where followProfiles[hex] == nil {
                    followProfiles[hex] = NostrProfile(pubkeyHex: hex, name: nil, displayName: nil, picture: nil)
                }
            }
        }

        // Phase B: relay refresh
        do {
            let pubkey = try PublicKey.parse(publicKey: myHex)
            let result = try await nostrService.fetchFollowListWithProfiles(pubkey: pubkey)
            followOrder = result.follows
            for (hex, profile) in result.profiles {
                followProfiles[hex] = profile
            }
            for hex in result.follows where followProfiles[hex] == nil {
                followProfiles[hex] = NostrProfile(pubkeyHex: hex, name: nil, displayName: nil, picture: nil)
            }
            let worthCaching = result.profiles.values.filter {
                $0.name != nil || $0.displayName != nil || $0.picture != nil
            }
            if !worthCaching.isEmpty {
                try? profileRepo.upsertProfiles(Array(worthCaching))
            }
        } catch {
            print("[RAID][People] Follow list relay fetch failed: \(error)")
        }

        isLoadingFollows = false
    }

    private func loadClubhouse() async {
        isLoadingClubhouse = true

        let repo = ClubhouseRepository(dbQueue: dbQueue)
        let profileRepo = ProfileCacheRepository(dbQueue: dbQueue)

        // Phase A: GRDB instant paint
        clubhousePubkeys = (try? repo.allPubkeyHexes()) ?? []
        if !clubhousePubkeys.isEmpty {
            if let cachedProfiles = try? profileRepo.fetchProfiles(pubkeyHexes: clubhousePubkeys) {
                clubhouseMembers = clubhousePubkeys.map { hex in
                    cachedProfiles[hex] ?? NostrProfile(pubkeyHex: hex, name: nil, displayName: nil, picture: nil)
                }
            } else {
                clubhouseMembers = clubhousePubkeys.map {
                    NostrProfile(pubkeyHex: $0, name: nil, displayName: nil, picture: nil)
                }
            }
        }

        // Phase B: relay refresh
        guard let hex = creatorPubkeyHex else {
            isLoadingClubhouse = false
            return
        }

        do {
            let remotePubkeys = try await nostrService.fetchClubhouse(pubkeyHex: hex)
            if !remotePubkeys.isEmpty && Set(remotePubkeys) != Set(clubhousePubkeys) {
                try? repo.replaceAll(pubkeyHexes: remotePubkeys)
                clubhousePubkeys = remotePubkeys
            }
            let cacheRepo = ProfileCacheRepository(dbQueue: dbQueue)
            if let profiles = try? await nostrService.resolveProfiles(
                pubkeyHexes: clubhousePubkeys, cacheRepo: cacheRepo
            ) {
                for hex in clubhousePubkeys {
                    if let p = profiles[hex] {
                        if let idx = clubhouseMembers.firstIndex(where: { $0.pubkeyHex == hex }) {
                            clubhouseMembers[idx] = p
                        }
                    }
                }
            }
        } catch {
            print("[RAID][People] Clubhouse relay fetch failed: \(error)")
        }

        isLoadingClubhouse = false
    }

    // MARK: - Following Mutations

    private func unfollowHex(_ hex: String) {
        followOrder.removeAll { $0 == hex }
        autoPublishFollowList()
    }

    private func addToFollowing(pubkeyHex: String) {
        guard !followOrder.contains(pubkeyHex) else { return }
        followOrder.append(pubkeyHex)
        if let p = searchKeyProfile {
            followProfiles[pubkeyHex] = p
        }
        autoPublishFollowList()
        // Resolve profile in background if not already cached
        if followProfiles[pubkeyHex]?.name == nil {
            Task {
                let cacheRepo = ProfileCacheRepository(dbQueue: dbQueue)
                if let profiles = try? await nostrService.resolveProfiles(
                    pubkeyHexes: [pubkeyHex], cacheRepo: cacheRepo
                ), let fetched = profiles[pubkeyHex] {
                    followProfiles[pubkeyHex] = fetched
                }
            }
        }
    }

    private func autoPublishFollowList() {
        Task {
            guard let km = try? KeyManager.loadOrCreate() else { return }
            let keys = km.signingKeys()
            let myHex = keys.publicKey().toHex()
            try? await nostrService.publishFollowList(
                keys: keys,
                followedPubkeyHexes: followOrder
            )
            let repo = FollowListCacheRepository(dbQueue: dbQueue)
            try? repo.updateLocalFollowList(pubkeyHex: myHex, follows: followOrder)
        }
    }

    // MARK: - Clubhouse Mutations

    private func addToClubhouse(pubkeyHex: String, profile: NostrProfile?) {
        guard !clubhousePubkeys.contains(pubkeyHex) else { return }
        let repo = ClubhouseRepository(dbQueue: dbQueue)
        try? repo.add(pubkeyHex: pubkeyHex)
        clubhousePubkeys.append(pubkeyHex)
        let p = profile ?? searchKeyProfile ?? NostrProfile(pubkeyHex: pubkeyHex, name: nil, displayName: nil, picture: nil)
        clubhouseMembers.append(p)
        autoPublishClubhouse()
    }

    private func removeFromClubhouse(pubkeyHex: String) {
        let repo = ClubhouseRepository(dbQueue: dbQueue)
        try? repo.remove(pubkeyHex: pubkeyHex)
        clubhousePubkeys.removeAll { $0 == pubkeyHex }
        clubhouseMembers.removeAll { $0.pubkeyHex == pubkeyHex }
        autoPublishClubhouse()
    }

    private func autoPublishClubhouse() {
        Task {
            guard let km = try? KeyManager.loadOrCreate() else { return }
            let keys = km.signingKeys()
            try? await nostrService.publishClubhouse(
                keys: keys,
                memberPubkeyHexes: clubhousePubkeys
            )
        }
    }
}
