// NostrProfileView.swift
// RAID Golf
//
// Nostr identity sheet: own profile display, key import, nsec backup, relay management.
//
// Profile state lives in DrawerState (single source of truth).
// This view reads from drawerState.ownProfile — no local duplicate.
// Relay list is loaded from GRDB cache then refreshed from relays.

import SwiftUI
import NostrSDK
import GRDB

struct NostrProfileView: View {
    let dbQueue: DatabaseQueue

    @Environment(\.dismiss) private var dismiss
    @Environment(\.nostrService) private var nostrService
    @Environment(\.drawerState) private var drawerState

    @State private var npub: String?
    @State private var errorMessage: String?
    @State private var showCopyNsecConfirm = false
    @State private var copiedNpub = false
    @State private var copiedNsec = false
    @State private var isLoadingProfile = false

    // Import state
    @State private var showImportSheet = false
    @State private var nsecInput = ""
    @State private var importError: String?
    @State private var showOrphanWarning = false

    // Relay state
    @State private var relays: [CachedRelayEntry] = []
    @State private var isLoadingRelays = false
    @State private var showAddRelay = false
    @State private var newRelayURL = ""
    @State private var newRelayMarker: String? = nil
    @State private var addRelayError: String?

    /// Single source of truth — reads from shared DrawerState, not local @State.
    private var profile: NostrProfile? { drawerState.ownProfile }

    var body: some View {
        NavigationStack {
            List {
                identitySection
                importSection
                relaySection
                warningSection
            }
            .navigationTitle("Keys & Relays")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Copy Secret Key?", isPresented: $showCopyNsecConfirm) {
                Button("Copy", role: .destructive) { copyNsec() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your secret key controls this Nostr identity. Keep it safe and never share it.")
            }
            .alert("Replace Current Key?", isPresented: $showOrphanWarning) {
                Button("Cancel", role: .cancel) {}
                Button("Replace", role: .destructive) { performImportConfirmed() }
            } message: {
                Text("Rounds published with your current identity will remain on Nostr but won't be linked to this app.")
            }
            .task {
                loadIdentity()
                if profile == nil {
                    await refreshProfile()
                }
                await loadRelays()
            }
            .sheet(isPresented: $showImportSheet) {
                importSheet
            }
            .sheet(isPresented: $showAddRelay) {
                addRelaySheet
            }
        }
    }

    // MARK: - Sections

    private var identitySection: some View {
        Section("Identity") {
            if let npub {
                // Profile display (avatar + name)
                if isLoadingProfile {
                    HStack {
                        Spacer()
                        ProgressView()
                        Text("Loading profile...")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                } else if let profile {
                    VStack(spacing: 12) {
                        ProfileAvatarView(pictureURL: profile.picture, size: 80)

                        if let displayName = profile.displayName, !displayName.isEmpty {
                            Text(displayName)
                                .font(.title3)
                                .fontWeight(.semibold)
                        }

                        if let name = profile.name, !name.isEmpty, name != profile.displayName {
                            Text("@\(name)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Public Key (npub)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(npub)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(2)
                        .textSelection(.enabled)
                }

                Button {
                    UIPasteboard.general.string = npub
                    copiedNpub = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copiedNpub = false
                    }
                } label: {
                    Label(copiedNpub ? "Copied!" : "Copy Public Key", systemImage: copiedNpub ? "checkmark" : "doc.on.doc")
                }

                Button {
                    showCopyNsecConfirm = true
                } label: {
                    Label(copiedNsec ? "Copied!" : "Copy Secret Key", systemImage: copiedNsec ? "checkmark" : "key")
                        .foregroundStyle(.red)
                }
            } else {
                Text("No identity yet. Post a round to generate one.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var importSection: some View {
        Section {
            Button {
                showImportSheet = true
            } label: {
                Label("Import Existing Key", systemImage: "key.horizontal")
            }
        } footer: {
            Text("Replace your current identity with an existing Nostr key.")
        }
    }

    private var relaySection: some View {
        Section {
            if isLoadingRelays {
                HStack {
                    Spacer()
                    ProgressView()
                    Text("Loading relays...")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else if relays.isEmpty {
                Text("No relay list published.")
                    .foregroundStyle(.secondary)

                Button {
                    bootstrapDefaults()
                } label: {
                    Label("Publish Default Relay List", systemImage: "antenna.radiowaves.left.and.right")
                }
            } else {
                ForEach(Array(relays.enumerated()), id: \.element.url) { _, relay in
                    relayRow(relay)
                }
                .onDelete(perform: deleteRelays)
            }

            Button {
                showAddRelay = true
            } label: {
                Label("Add Relay", systemImage: "plus.circle")
            }
        } header: {
            Text("Relays")
        } footer: {
            if relays.count > 5 {
                Text("NIP-65 recommends 2\u{2013}4 relays per category.")
            }
        }
    }

    @ViewBuilder
    private func relayRow(_ relay: CachedRelayEntry) -> some View {
        HStack {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.secondary)
            Text(relay.url)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
            Spacer()
            Text(markerLabel(relay.marker))
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(markerColor(relay.marker).opacity(0.15))
                .foregroundStyle(markerColor(relay.marker))
                .clipShape(Capsule())
        }
    }

    private func markerLabel(_ marker: String?) -> String {
        switch marker {
        case nil: return "R/W"
        case "read": return "Read"
        case "write": return "Write"
        default: return marker ?? ""
        }
    }

    private func markerColor(_ marker: String?) -> Color {
        switch marker {
        case nil: return .blue
        case "read": return .green
        case "write": return .orange
        default: return .secondary
        }
    }

    private var warningSection: some View {
        Section {
            Label {
                Text("This key is generated locally and not recoverable unless you copy it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Import Sheet

    private var importSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("nsec1... or hex", text: $nsecInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))

                    if let error = importError {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                } header: {
                    Text("Paste Secret Key")
                } footer: {
                    Text("Enter nsec1... (bech32) or hex secret key from another Nostr client.")
                }

                Section {
                    Label {
                        Text("Your key never leaves this device. It's stored in your device's secure keychain.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("Import Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showImportSheet = false
                        nsecInput = ""
                        importError = nil
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Import") {
                        performImport()
                    }
                    .disabled(nsecInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: - Add Relay Sheet

    private var addRelaySheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("wss://relay.example.com", text: $newRelayURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.system(.body, design: .monospaced))

                    if let error = addRelayError {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                } header: {
                    Text("Relay URL")
                }

                Section {
                    Picker("Direction", selection: $newRelayMarker) {
                        Text("Read & Write").tag(nil as String?)
                        Text("Read Only").tag("read" as String?)
                        Text("Write Only").tag("write" as String?)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Relay Type")
                }
            }
            .navigationTitle("Add Relay")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        newRelayURL = ""
                        newRelayMarker = nil
                        addRelayError = nil
                        showAddRelay = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addRelay() }
                        .disabled(newRelayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: - Actions

    private func loadIdentity() {
        do {
            let keyManager = try KeyManager.loadOrCreate()
            npub = try keyManager.publicKeyBech32()
        } catch {
            npub = nil
        }
    }

    private func copyNsec() {
        do {
            let keyManager = try KeyManager.loadOrCreate()
            try keyManager.copySecretKeyToPasteboard()
            copiedNsec = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                copiedNsec = false
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Fetch profile from relays and update the single source of truth (DrawerState).
    private func refreshProfile() async {
        guard let km = try? KeyManager.loadOrCreate() else { return }
        let pubkeyHex = km.signingKeys().publicKey().toHex()

        isLoadingProfile = true
        defer { isLoadingProfile = false }

        if let profiles = try? await nostrService.resolveProfiles(pubkeyHexes: [pubkeyHex]) {
            drawerState.ownProfile = profiles[pubkeyHex]
        }
    }

    // MARK: - Relay Actions

    private func loadRelays() async {
        guard let km = try? KeyManager.loadOrCreate() else { return }
        let pubkeyHex = km.signingKeys().publicKey().toHex()

        isLoadingRelays = true
        defer { isLoadingRelays = false }

        let cacheRepo = RelayCacheRepository(dbQueue: dbQueue)

        // Load from GRDB first (instant)
        if let cached = try? cacheRepo.fetchRelayList(pubkeyHex: pubkeyHex) {
            relays = cached.relays
        }

        // Then fetch from relays in background (overwrites if newer)
        if let resolved = try? await nostrService.resolveRelayLists(
            pubkeyHexes: [pubkeyHex], cacheRepo: cacheRepo
        ), let entries = resolved[pubkeyHex] {
            relays = entries
        }
    }

    private func addRelay() {
        let url = newRelayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        guard url.hasPrefix("wss://") || url.hasPrefix("ws://") else {
            addRelayError = "URL must start with wss:// or ws://"
            return
        }
        guard !relays.contains(where: { $0.url == url }) else {
            addRelayError = "Relay already in list"
            return
        }

        let entry = CachedRelayEntry(url: url, marker: newRelayMarker)
        relays.append(entry)
        persistAndPublish()

        newRelayURL = ""
        newRelayMarker = nil
        addRelayError = nil
        showAddRelay = false
    }

    private func deleteRelays(at offsets: IndexSet) {
        relays.remove(atOffsets: offsets)
        persistAndPublish()
    }

    private func bootstrapDefaults() {
        relays = NostrService.defaultPublishRelays.map {
            CachedRelayEntry(url: $0, marker: nil)
        }
        persistAndPublish()
    }

    private func persistAndPublish() {
        guard let km = try? KeyManager.loadOrCreate() else { return }
        let pubkeyHex = km.signingKeys().publicKey().toHex()
        let repo = RelayCacheRepository(dbQueue: dbQueue)
        let list = CachedRelayList(pubkeyHex: pubkeyHex, relays: relays, cachedAt: Date())
        try? repo.upsertRelayList(list)

        // Auto-publish fire-and-forget
        Task {
            let keys = km.signingKeys()
            try? await nostrService.publishRelayList(keys: keys, relays: relays)
        }
    }

    // MARK: - Import Actions

    private func performImport() {
        importError = nil
        let input = nsecInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        // Validate key format before asking about replacement
        let lower = input.lowercased()
        let badPrefixes = ["npub1", "nevent1", "nprofile1", "note1", "naddr1", "nrelay1"]
        for prefix in badPrefixes {
            if lower.hasPrefix(prefix) {
                importError = "Expected nsec1... or hex secret key, not \(prefix)..."
                return
            }
        }

        // Quick parse check — does the SDK accept it as a secret key?
        do {
            _ = try Keys.parse(secretKey: input)
        } catch {
            importError = "Invalid key. Enter an nsec1... or 64-character hex secret key."
            return
        }

        // Key is valid — check if replacing existing key
        if npub != nil {
            showOrphanWarning = true
        } else {
            performImportConfirmed()
        }
    }

    private func performImportConfirmed() {
        let input = nsecInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        do {
            _ = try KeyManager.importKey(nsec: input)
            loadIdentity()
            // Clear the single source of truth — triggers UI update everywhere
            drawerState.ownProfile = nil
            Task { await refreshProfile() }
            showImportSheet = false
            nsecInput = ""
            importError = nil
        } catch {
            importError = error.localizedDescription
        }
    }
}
