// NostrProfileView.swift
// Gambit Golf
//
// Minimal Nostr identity sheet: npub display, nsec backup, relay info.

import SwiftUI

struct NostrProfileView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var npub: String?
    @State private var errorMessage: String?
    @State private var showCopyNsecConfirm = false
    @State private var copiedNpub = false
    @State private var copiedNsec = false

    var body: some View {
        NavigationStack {
            List {
                identitySection
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
            .task { loadIdentity() }
        }
    }

    // MARK: - Sections

    private var identitySection: some View {
        Section("Identity") {
            if let npub {
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

    // MARK: - Actions

    private func loadIdentity() {
        do {
            let keyManager = try KeyManager.loadOrCreate()
            npub = try keyManager.publicKeyBech32()
        } catch {
            // No error — just means no identity yet
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
}
