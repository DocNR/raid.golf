// NostrProfileView.swift
// Gambit Golf
//
// Nostr identity sheet: own profile display, key import, nsec backup, relay info.

import SwiftUI
import NostrSDK

struct NostrProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.nostrService) private var nostrService

    @State private var npub: String?
    @State private var errorMessage: String?
    @State private var showCopyNsecConfirm = false
    @State private var copiedNpub = false
    @State private var copiedNsec = false

    // Own profile state
    @State private var ownProfile: NostrProfile?
    @State private var isLoadingProfile = false

    // Import state
    @State private var showImportSheet = false
    @State private var nsecInput = ""
    @State private var importError: String?
    @State private var showOrphanWarning = false

    var body: some View {
        NavigationStack {
            List {
                identitySection
                importSection
                relaySection
                warningSection
            }
            .navigationTitle("Nostr Profile")
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
                await fetchOwnProfile()
            }
            .sheet(isPresented: $showImportSheet) {
                importSheet
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
                } else if let profile = ownProfile {
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
        Section("Relays") {
            ForEach(NostrService.defaultPublishRelays, id: \.self) { relay in
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(.secondary)
                    Text(relay)
                        .font(.system(.body, design: .monospaced))
                }
            }
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

    private func fetchOwnProfile() async {
        guard let km = try? KeyManager.loadOrCreate() else { return }
        let pubkeyHex = km.signingKeys().publicKey().toHex()

        isLoadingProfile = true
        defer { isLoadingProfile = false }

        if let profiles = try? await nostrService.resolveProfiles(pubkeyHexes: [pubkeyHex]) {
            ownProfile = profiles[pubkeyHex]
        }
    }

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
            ownProfile = nil
            Task { await fetchOwnProfile() }
            showImportSheet = false
            nsecInput = ""
            importError = nil
        } catch {
            importError = error.localizedDescription
        }
    }
}
