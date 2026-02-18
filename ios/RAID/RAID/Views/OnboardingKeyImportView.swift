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
                TextField("nsec1... or hex secret key", text: $nsecInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
            } header: {
                Text("Paste your secret key to restore your account.")
            } footer: {
                Text("Enter nsec1... (bech32) or a 64-character hex secret key from another app.")
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

        // Reject non-nsec bech32 prefixes
        let lower = input.lowercased()
        let badPrefixes = ["npub1", "nevent1", "nprofile1", "note1", "naddr1", "nrelay1"]
        for prefix in badPrefixes {
            if lower.hasPrefix(prefix) {
                errorMessage = "Expected nsec1... or hex secret key, not \(prefix)..."
                return
            }
        }

        // Validate key format
        do {
            _ = try Keys.parse(secretKey: input)
        } catch {
            errorMessage = "Invalid key. Enter an nsec1... or 64-character hex secret key."
            return
        }

        isImporting = true
        defer { isImporting = false }

        do {
            // No orphan warning — auto-generated key was never used during onboarding
            let keyManager = try KeyManager.importKey(nsec: input)
            let pubkeyHex = keyManager.signingKeys().publicKey().toHex()

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
