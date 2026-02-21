// OnboardingKeyImportView.swift
// RAID Golf
//
// "Sign In" onboarding path (O-3).
// Imports an existing nsec, fetches profile from relays.

import SwiftUI
import NostrSDK

struct OnboardingKeyImportView: View {
    let onComplete: (_ activated: Bool) -> Void

    @Environment(\.nostrService) private var nostrService
    @Environment(\.drawerState) private var drawerState

    @State private var nsecInput = ""
    @State private var isImporting = false
    @State private var errorMessage: String?

    private var canImport: Bool {
        !nsecInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField("nsec1... or npub1...", text: $nsecInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
            } header: {
                Text("Paste your key to restore your account.")
            } footer: {
                Text("Enter nsec1... (secret key) or npub1... (public key, read-only).")
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
        .navigationTitle("Sign In")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isImporting {
                    ProgressView()
                } else {
                    Button("Sign In") {
                        Task { await performImport() }
                    }
                    .disabled(!canImport)
                }
            }
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

    private func performImport() async {
        let input = nsecInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }

        let lower = input.lowercased()

        // npub path — read-only sign-in
        if lower.hasPrefix("npub1") {
            isImporting = true
            defer { isImporting = false }

            do {
                let pubkeyHex = try KeyManager.importPublicKey(npub: input)
                UserDefaults.standard.set(true, forKey: "nostrReadOnly")
                UserDefaults.standard.set(true, forKey: "nostrActivated")

                // Best-effort profile fetch from relays
                if let profiles = try? await nostrService.resolveProfiles(pubkeyHexes: [pubkeyHex]) {
                    drawerState.ownProfile = profiles[pubkeyHex]
                }

                onComplete(true)
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }

        // Reject other non-nsec bech32 prefixes
        let badPrefixes = ["nevent1", "nprofile1", "note1", "naddr1", "nrelay1"]
        for prefix in badPrefixes {
            if lower.hasPrefix(prefix) {
                errorMessage = "Expected nsec1... or npub1..., not \(prefix)..."
                return
            }
        }

        // nsec / hex secret key path
        // Validate key format
        do {
            _ = try Keys.parse(secretKey: input)
        } catch {
            errorMessage = "Invalid key. Enter an nsec1... or npub1... key."
            return
        }

        isImporting = true
        defer { isImporting = false }

        do {
            // No orphan warning — auto-generated key was never used during onboarding
            let keyManager = try KeyManager.importKey(nsec: input)
            let pubkeyHex = keyManager.signingKeys().publicKey().toHex()

            // Explicitly mark as NOT read-only
            UserDefaults.standard.set(false, forKey: "nostrReadOnly")

            // Open gate before relay operations so NostrService connections are active
            UserDefaults.standard.set(true, forKey: "nostrActivated")

            // Best-effort profile fetch from relays
            if let profiles = try? await nostrService.resolveProfiles(pubkeyHexes: [pubkeyHex]) {
                drawerState.ownProfile = profiles[pubkeyHex]
            }

            onComplete(true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
