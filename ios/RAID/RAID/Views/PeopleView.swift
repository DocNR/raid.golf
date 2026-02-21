// PeopleView.swift
// RAID Golf
//
// Combined Following + Clubhouse management with segmented tabs.
// Following: NIP-02 kind 3 contact list. Clubhouse: NIP-51 kind 30000 follow set.
// Swipe left to unfollow/remove. Swipe right on Following to add to Clubhouse.

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
    @State private var showNpubEntry = false
    @State private var showClubhouseFollowPicker = false

    // Npub entry
    @State private var npubInput = ""
    @State private var npubError: String?
    @State private var selectedPubkeyHex: String = ""
    @State private var showUserProfile = false

    @State private var searchText = ""
    @State private var errorMessage: String?

    private var creatorPubkeyHex: String? {
        guard UserDefaults.standard.bool(forKey: "nostrActivated"),
              let km = try? KeyManager.loadOrCreate() else { return nil }
        return km.signingKeys().publicKey().toHex()
    }

    private enum PeopleTab: String, CaseIterable {
        case following = "Following"
        case clubhouse = "Clubhouse"
    }

    private var filteredFollowOrder: [String] {
        guard !searchText.isEmpty else { return followOrder }
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
            .searchable(text: $searchText, prompt: "Search by name or npub")
            .onChange(of: selectedTab) { _, _ in searchText = "" }
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
            .sheet(isPresented: $showNpubEntry) {
                npubEntrySheet
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

    // MARK: - Following Tab

    @ViewBuilder
    private var followingList: some View {
        if isLoadingFollows && followOrder.isEmpty {
            loadingState
        } else if followOrder.isEmpty {
            emptyState(
                icon: "person.2",
                title: "No Follows",
                message: "You're not following anyone yet. Add people by their Nostr public key."
            )
        } else {
            List {
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

                addByNpubButton(target: .following)
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
        if isLoadingClubhouse && clubhouseMembers.isEmpty {
            loadingState
        } else if clubhouseMembers.isEmpty {
            emptyState(
                icon: "star",
                title: "No Clubhouse Members",
                message: "Your curated playing partners. Add people from your follows or by their public key."
            )
        } else {
            List {
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

                Section {
                    Button {
                        showClubhouseFollowPicker = true
                    } label: {
                        Label("Add from Follows", systemImage: "person.crop.circle.badge.plus")
                    }

                    addByNpubButton(target: .clubhouse)
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

    private func addByNpubButton(target: PeopleTab) -> some View {
        Section {
            Button {
                showNpubEntry = true
            } label: {
                Label(
                    target == .following ? "Follow by npub" : "Add by npub",
                    systemImage: target == .following ? "person.badge.plus" : "key"
                )
            }
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

    // MARK: - Npub Entry Sheet

    private var npubEntrySheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("npub1... or hex key", text: $npubInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if let error = npubError {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                } footer: {
                    switch selectedTab {
                    case .following:
                        Text("Paste a Nostr public key to follow them.")
                    case .clubhouse:
                        Text("Paste a Nostr public key to add them to your Clubhouse.")
                    }
                }
            }
            .navigationTitle("Add by Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        npubInput = ""
                        npubError = nil
                        showNpubEntry = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addByNpub()
                    }
                    .disabled(npubInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
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
                // Merge — don't replace — to preserve Phase A cached profiles
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
        autoPublishFollowList()
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
        clubhouseMembers.append(profile ?? NostrProfile(pubkeyHex: pubkeyHex, name: nil, displayName: nil, picture: nil))
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

    // MARK: - Add by Npub

    private func addByNpub() {
        npubError = nil
        let input = npubInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        do {
            let pubkey = try PublicKey.parse(publicKey: input)
            let hex = pubkey.toHex()

            if hex == creatorPubkeyHex {
                npubError = "That's your own key."
                return
            }

            switch selectedTab {
            case .following:
                if followOrder.contains(hex) {
                    npubError = "Already following."
                    return
                }
                addToFollowing(pubkeyHex: hex)
            case .clubhouse:
                if clubhousePubkeys.contains(hex) {
                    npubError = "Already in your Clubhouse."
                    return
                }
                addToClubhouse(pubkeyHex: hex, profile: nil)
            }

            npubInput = ""
            showNpubEntry = false

            // Resolve profile in background
            Task {
                let cacheRepo = ProfileCacheRepository(dbQueue: dbQueue)
                if let profiles = try? await nostrService.resolveProfiles(
                    pubkeyHexes: [hex], cacheRepo: cacheRepo
                ), let fetched = profiles[hex] {
                    switch selectedTab {
                    case .following:
                        followProfiles[hex] = fetched
                    case .clubhouse:
                        if let idx = clubhouseMembers.firstIndex(where: { $0.pubkeyHex == hex }) {
                            clubhouseMembers[idx] = fetched
                        }
                    }
                }
            }
        } catch {
            npubError = "Invalid npub or hex key."
        }
    }
}
