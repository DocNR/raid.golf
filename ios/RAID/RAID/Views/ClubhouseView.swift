// ClubhouseView.swift
// RAID Golf
//
// Curated player list. Members are persisted locally (GRDB) and synced
// to/from Nostr via NIP-51 kind 30000 follow set (d="clubhouse").
// Auto-publishes on add/remove — no manual sync buttons.

import SwiftUI
import GRDB
import NostrSDK

struct ClubhouseView: View {
    let dbQueue: DatabaseQueue

    @Environment(\.dismiss) private var dismiss
    @Environment(\.nostrService) private var nostrService

    @State private var members: [NostrProfile] = []
    @State private var memberPubkeys: [String] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    // Add member flows
    @State private var showFollowPicker = false
    @State private var showNpubEntry = false
    @State private var npubInput = ""
    @State private var npubError: String?

    private var creatorPubkeyHex: String? {
        guard UserDefaults.standard.bool(forKey: "nostrActivated"),
              let km = try? KeyManager.loadOrCreate() else { return nil }
        return km.signingKeys().publicKey().toHex()
    }

    var body: some View {
        NavigationStack {
            List {
                membersSection
                addSection
            }
            .navigationTitle("Clubhouse")
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
                await loadMembers()
            }
            .sheet(isPresented: $showFollowPicker) {
                ClubhouseFollowPicker(
                    dbQueue: dbQueue,
                    creatorPubkeyHex: creatorPubkeyHex,
                    existingMembers: Set(memberPubkeys),
                    onAddBatch: { selected in
                        for (hex, profile) in selected {
                            addMember(pubkeyHex: hex, profile: profile)
                        }
                    }
                )
            }
            .sheet(isPresented: $showNpubEntry) {
                npubEntrySheet
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var membersSection: some View {
        if isLoading && members.isEmpty {
            Section {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading...")
                        .foregroundStyle(.secondary)
                }
            }
        } else if members.isEmpty {
            Section {
                Text("No members yet. Add playing partners to your Clubhouse.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } footer: {
                Text("Syncs across your devices automatically.")
            }
        } else {
            Section {
                ForEach(members) { profile in
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
                    }
                }
                .onDelete(perform: deleteMembers)
            } header: {
                Text("Members (\(members.count))")
            } footer: {
                Text("Syncs across your devices automatically.")
            }
        }
    }

    private var addSection: some View {
        Section {
            Button {
                showFollowPicker = true
            } label: {
                Label("Add from Follows", systemImage: "person.crop.circle.badge.plus")
            }

            Button {
                showNpubEntry = true
            } label: {
                Label("Add by npub", systemImage: "key")
                    .foregroundStyle(.secondary)
            }
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
                    Text("Paste a Nostr public key to add someone to your Clubhouse.")
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
                    Button("Add") { addByNpub() }
                        .disabled(npubInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadMembers() async {
        isLoading = true

        // 1. Load from GRDB immediately
        let repo = ClubhouseRepository(dbQueue: dbQueue)
        memberPubkeys = (try? repo.allPubkeyHexes()) ?? []
        await resolveProfiles()

        // 2. Fetch from Nostr in background and merge
        guard let hex = creatorPubkeyHex else {
            isLoading = false
            return
        }

        do {
            let remotePubkeys = try await nostrService.fetchClubhouse(pubkeyHex: hex)
            if !remotePubkeys.isEmpty && Set(remotePubkeys) != Set(memberPubkeys) {
                try? repo.replaceAll(pubkeyHexes: remotePubkeys)
                memberPubkeys = remotePubkeys
                await resolveProfiles()
            }
        } catch {
            // Fetch failure is non-fatal — local data is already shown
            print("[RAID][Clubhouse] Remote fetch failed: \(error)")
        }

        isLoading = false
    }

    private func resolveProfiles() async {
        guard !memberPubkeys.isEmpty else {
            members = []
            return
        }
        let cacheRepo = ProfileCacheRepository(dbQueue: dbQueue)
        if let profiles = try? await nostrService.resolveProfiles(
            pubkeyHexes: memberPubkeys, cacheRepo: cacheRepo
        ) {
            members = memberPubkeys.compactMap { profiles[$0] }
        } else {
            // Fallback: show pubkeys without profile metadata
            members = memberPubkeys.map {
                NostrProfile(pubkeyHex: $0, name: nil, displayName: nil, picture: nil)
            }
        }
    }

    // MARK: - Mutations

    private func addMember(pubkeyHex: String, profile: NostrProfile?) {
        guard !memberPubkeys.contains(pubkeyHex) else { return }

        let repo = ClubhouseRepository(dbQueue: dbQueue)
        try? repo.add(pubkeyHex: pubkeyHex)
        memberPubkeys.append(pubkeyHex)
        members.append(profile ?? NostrProfile(pubkeyHex: pubkeyHex, name: nil, displayName: nil, picture: nil))

        autoPublish()
    }

    private func deleteMembers(at offsets: IndexSet) {
        let repo = ClubhouseRepository(dbQueue: dbQueue)
        for index in offsets {
            let hex = members[index].pubkeyHex
            try? repo.remove(pubkeyHex: hex)
            memberPubkeys.removeAll { $0 == hex }
        }
        members.remove(atOffsets: offsets)

        autoPublish()
    }

    private func autoPublish() {
        Task {
            guard let km = try? KeyManager.loadOrCreate() else { return }
            let keys = km.signingKeys()
            try? await nostrService.publishClubhouse(
                keys: keys,
                memberPubkeyHexes: memberPubkeys
            )
        }
    }

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
            if memberPubkeys.contains(hex) {
                npubError = "Already in your Clubhouse."
                return
            }

            addMember(pubkeyHex: hex, profile: nil)
            npubInput = ""
            showNpubEntry = false

            // Resolve profile in background
            Task {
                let cacheRepo = ProfileCacheRepository(dbQueue: dbQueue)
                if let profiles = try? await nostrService.resolveProfiles(
                    pubkeyHexes: [hex], cacheRepo: cacheRepo
                ), let fetched = profiles[hex] {
                    if let idx = members.firstIndex(where: { $0.pubkeyHex == hex }) {
                        members[idx] = fetched
                    }
                }
            }
        } catch {
            npubError = "Invalid npub or hex key."
        }
    }
}

// MARK: - Follow Picker for Clubhouse

struct ClubhouseFollowPicker: View {
    let dbQueue: DatabaseQueue
    let creatorPubkeyHex: String?
    let existingMembers: Set<String>
    let onAddBatch: ([String: NostrProfile]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.nostrService) private var nostrService

    @State private var selected: [String: NostrProfile] = [:]
    @State private var searchQuery = ""
    @State private var searchResults: [NostrProfile] = []
    @State private var followProfiles: [String: NostrProfile] = [:]
    @State private var followOrder: [String] = []
    @State private var isLoadingFollows = false
    @State private var followLoadError: String?

    var body: some View {
        NavigationStack {
            List {
                selectedSection
                followsContent
            }
            .searchable(
                text: $searchQuery,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search by name or nip05"
            )
            .onChange(of: searchQuery) { _, _ in performSearch() }
            .navigationTitle("Add to Clubhouse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(selected.isEmpty ? "Done" : "Add (\(selected.count))") {
                        onAddBatch(selected)
                        dismiss()
                    }
                }
            }
            .task {
                await loadFollows()
            }
        }
    }

    @ViewBuilder
    private var selectedSection: some View {
        if !selected.isEmpty {
            Section("Selected") {
                ForEach(Array(selected.values).sorted { $0.displayLabel < $1.displayLabel }) { profile in
                    HStack(spacing: 10) {
                        ProfileAvatarView(pictureURL: profile.picture, size: 36)
                        Text(profile.displayLabel)
                            .foregroundStyle(.primary)
                        Spacer()
                        Button {
                            selected.removeValue(forKey: profile.pubkeyHex)
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
    private var followsContent: some View {
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
                followsList
            }
        }
    }

    @ViewBuilder
    private var followsList: some View {
        let allExcluded = existingMembers.union(Set(selected.keys))
        let displayList: [NostrProfile] = searchQuery.count >= 2
            ? searchResults.filter { !allExcluded.contains($0.pubkeyHex) && $0.pubkeyHex != creatorPubkeyHex }
            : followOrder.compactMap { followProfiles[$0] }
                .filter { !allExcluded.contains($0.pubkeyHex) }

        if displayList.isEmpty && searchQuery.count >= 2 {
            Text("No results.")
                .foregroundStyle(.secondary)
                .font(.caption)
        }

        ForEach(displayList, id: \.pubkeyHex) { profile in
            Button {
                selected[profile.pubkeyHex] = profile
            } label: {
                followRowLabel(profile: profile)
            }
        }
    }

    private func followRowLabel(profile: NostrProfile) -> some View {
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
            Image(systemName: "plus.circle")
                .foregroundStyle(Color.accentColor)
        }
    }

    private func performSearch() {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { searchResults = []; return }
        let repo = ProfileCacheRepository(dbQueue: dbQueue)
        searchResults = (try? repo.searchProfiles(query: q, limit: 20)) ?? []
    }

    private func loadFollows() async {
        guard let creatorHex = creatorPubkeyHex else { return }
        isLoadingFollows = true
        followLoadError = nil

        do {
            let pubkey = try PublicKey.parse(publicKey: creatorHex)
            let result = try await nostrService.fetchFollowListWithProfiles(pubkey: pubkey)
            followOrder = result.follows
            followProfiles = result.profiles
            for hex in result.follows where followProfiles[hex] == nil {
                followProfiles[hex] = NostrProfile(pubkeyHex: hex, name: nil, displayName: nil, picture: nil)
            }
        } catch {
            followLoadError = "Could not load follow list."
            print("[RAID] Follow list load failed: \(error)")
        }

        isLoadingFollows = false
    }
}
