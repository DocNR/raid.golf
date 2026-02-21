// PeopleView.swift
// RAID Golf
//
// Combined Following + Clubhouse management.
// Accessed from ProfileView ("X Following" stat) or drawer ("People" menu item).
// Following: NIP-02 kind 3 contact list. Clubhouse: NIP-51 kind 30000 follow set.

import SwiftUI
import GRDB
import NostrSDK

struct PeopleView: View {
    let dbQueue: DatabaseQueue

    @Environment(\.dismiss) private var dismiss
    @Environment(\.nostrService) private var nostrService

    // Following state
    @State private var followOrder: [String] = []
    @State private var followProfiles: [String: NostrProfile] = [:]
    @State private var isLoadingFollows = false

    // Clubhouse state
    @State private var clubhouseMembers: [NostrProfile] = []
    @State private var clubhousePubkeys: [String] = []
    @State private var isLoadingClubhouse = false

    // Sheet state
    @State private var showFollowNpubEntry = false
    @State private var showClubhouseFollowPicker = false
    @State private var showClubhouseNpubEntry = false

    // Npub entry
    @State private var npubInput = ""
    @State private var npubError: String?
    @State private var npubTarget: NpubTarget = .following
    @State private var selectedPubkeyHex: String = ""
    @State private var showUserProfile = false

    @State private var errorMessage: String?

    private var creatorPubkeyHex: String? {
        guard UserDefaults.standard.bool(forKey: "nostrActivated"),
              let km = try? KeyManager.loadOrCreate() else { return nil }
        return km.signingKeys().publicKey().toHex()
    }

    private enum NpubTarget {
        case following, clubhouse
    }

    var body: some View {
        NavigationStack {
            List {
                followingSection
                followingAddSection

                clubhouseSection
                clubhouseAddSection
            }
            .navigationTitle("People")
            .navigationBarTitleDisplayMode(.inline)
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
                await loadFollows()
                await loadClubhouse()
            }
            .sheet(isPresented: $showFollowNpubEntry) {
                npubEntrySheet(target: .following)
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
            .sheet(isPresented: $showClubhouseNpubEntry) {
                npubEntrySheet(target: .clubhouse)
            }
            .sheet(isPresented: $showUserProfile) {
                UserProfileSheet(pubkeyHex: selectedPubkeyHex, dbQueue: dbQueue)
            }
        }
    }

    // MARK: - Following Section

    @ViewBuilder
    private var followingSection: some View {
        if isLoadingFollows && followOrder.isEmpty {
            Section("Following") {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading...")
                        .foregroundStyle(.secondary)
                }
            }
        } else if followOrder.isEmpty {
            Section("Following") {
                Text("You're not following anyone yet.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        } else {
            Section {
                ForEach(followOrder, id: \.self) { hex in
                    Button {
                        selectedPubkeyHex = hex
                        showUserProfile = true
                    } label: {
                        profileRow(for: hex, profiles: followProfiles)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: unfollowAt)
            } header: {
                Text("Following (\(followOrder.count))")
            } footer: {
                Text("Your Nostr contact list (kind 3). Syncs with other Nostr clients.")
            }
        }
    }

    private var followingAddSection: some View {
        Section {
            Button {
                npubTarget = .following
                showFollowNpubEntry = true
            } label: {
                Label("Follow by npub", systemImage: "person.badge.plus")
            }
        }
    }

    // MARK: - Clubhouse Section

    @ViewBuilder
    private var clubhouseSection: some View {
        if isLoadingClubhouse && clubhouseMembers.isEmpty {
            Section("Clubhouse") {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading...")
                        .foregroundStyle(.secondary)
                }
            }
        } else if clubhouseMembers.isEmpty {
            Section("Clubhouse") {
                Text("Your curated playing partners. Add people to quickly invite them to rounds.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        } else {
            Section {
                ForEach(clubhouseMembers) { profile in
                    Button {
                        selectedPubkeyHex = profile.pubkeyHex
                        showUserProfile = true
                    } label: {
                        profileRow(for: profile.pubkeyHex, profiles: [profile.pubkeyHex: profile])
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: removeFromClubhouseAt)
            } header: {
                Text("Clubhouse (\(clubhouseMembers.count))")
            } footer: {
                Text("Syncs across your devices via Nostr (NIP-51).")
            }
        }
    }

    private var clubhouseAddSection: some View {
        Section {
            Button {
                showClubhouseFollowPicker = true
            } label: {
                Label("Add from Follows", systemImage: "person.crop.circle.badge.plus")
            }

            Button {
                npubTarget = .clubhouse
                showClubhouseNpubEntry = true
            } label: {
                Label("Add by npub", systemImage: "key")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Shared Row

    private func profileRow(for hex: String, profiles: [String: NostrProfile]) -> some View {
        let profile = profiles[hex]
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
        }
    }

    // MARK: - Npub Entry Sheet

    private func npubEntrySheet(target: NpubTarget) -> some View {
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
                    switch target {
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
                        showFollowNpubEntry = false
                        showClubhouseNpubEntry = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addByNpub(target: target)
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
            // Synchronous GRDB read — instant profiles with names/avatars
            if let cachedProfiles = try? profileRepo.fetchProfiles(pubkeyHexes: cached.follows) {
                followProfiles = cachedProfiles
                // Fill stubs for any follows not yet in profile cache
                for hex in cached.follows where followProfiles[hex] == nil {
                    followProfiles[hex] = NostrProfile(pubkeyHex: hex, name: nil, displayName: nil, picture: nil)
                }
            }
        }

        // Phase B: relay refresh in background
        do {
            let pubkey = try PublicKey.parse(publicKey: myHex)
            let result = try await nostrService.fetchFollowListWithProfiles(pubkey: pubkey)
            followOrder = result.follows
            // Merge relay results into existing cache — don't replace, or
            // profiles loaded from GRDB in Phase A get wiped if relay
            // returns fewer results (timeout, etc.)
            for (hex, profile) in result.profiles {
                followProfiles[hex] = profile
            }
            for hex in result.follows where followProfiles[hex] == nil {
                followProfiles[hex] = NostrProfile(pubkeyHex: hex, name: nil, displayName: nil, picture: nil)
            }
            // Persist relay-fetched profiles to shared GRDB cache
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
            // Resolve all profiles (memory → GRDB → relay) and persist
            let cacheRepo = ProfileCacheRepository(dbQueue: dbQueue)
            if let profiles = try? await nostrService.resolveProfiles(
                pubkeyHexes: clubhousePubkeys, cacheRepo: cacheRepo
            ) {
                clubhouseMembers = clubhousePubkeys.compactMap { profiles[$0] }
            }
        } catch {
            print("[RAID][People] Clubhouse relay fetch failed: \(error)")
        }

        isLoadingClubhouse = false
    }

    // MARK: - Following Mutations

    private func unfollowAt(offsets: IndexSet) {
        for index in offsets {
            followOrder.remove(at: index)
        }
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

    private func removeFromClubhouseAt(offsets: IndexSet) {
        let repo = ClubhouseRepository(dbQueue: dbQueue)
        for index in offsets {
            let hex = clubhouseMembers[index].pubkeyHex
            try? repo.remove(pubkeyHex: hex)
            clubhousePubkeys.removeAll { $0 == hex }
        }
        clubhouseMembers.remove(atOffsets: offsets)
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

    private func addByNpub(target: NpubTarget) {
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

            switch target {
            case .following:
                if followOrder.contains(hex) {
                    npubError = "Already following."
                    return
                }
                addToFollowing(pubkeyHex: hex)
                showFollowNpubEntry = false
            case .clubhouse:
                if clubhousePubkeys.contains(hex) {
                    npubError = "Already in your Clubhouse."
                    return
                }
                addToClubhouse(pubkeyHex: hex, profile: nil)
                showClubhouseNpubEntry = false
            }

            npubInput = ""

            // Resolve profile in background
            Task {
                let cacheRepo = ProfileCacheRepository(dbQueue: dbQueue)
                if let profiles = try? await nostrService.resolveProfiles(
                    pubkeyHexes: [hex], cacheRepo: cacheRepo
                ), let fetched = profiles[hex] {
                    switch target {
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
