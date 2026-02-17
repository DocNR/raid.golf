// OnboardingProfileSetupView.swift
// RAID Golf
//
// "Create Account" onboarding path (O-2).
// Publishes kind 0 profile metadata, updates drawerState.ownProfile.

import SwiftUI
import NostrSDK

struct OnboardingProfileSetupView: View {
    let onComplete: (_ activated: Bool) -> Void

    @Environment(\.nostrService) private var nostrService
    @Environment(\.drawerState) private var drawerState

    @State private var displayName = ""
    @State private var name = ""
    @State private var about = ""
    @State private var pictureURL = ""
    @State private var isPublishing = false
    @State private var errorMessage: String?

    private var canCreate: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section("Display Name") {
                TextField("e.g. Tiger Woods", text: $displayName)
            }

            Section("Username (optional)") {
                TextField("e.g. tiger", text: $name)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("About (optional)") {
                TextEditor(text: $about)
                    .frame(minHeight: 80)
            }

            Section("Avatar URL (optional)") {
                TextField("https://...", text: $pictureURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                if !pictureURL.isEmpty {
                    ProfileAvatarView(pictureURL: pictureURL, size: 60)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Set Up Your Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isPublishing {
                    ProgressView()
                } else {
                    Button("Create") {
                        Task { await createProfile() }
                    }
                    .disabled(!canCreate)
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

    private func createProfile() async {
        isPublishing = true
        defer { isPublishing = false }

        do {
            let keyManager = try KeyManager.createNew()
            let keys = keyManager.signingKeys()
            let pubkeyHex = keys.publicKey().toHex()

            // Build kind 0 JSON
            var json: [String: String] = [:]
            let trimmedDisplay = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            json["display_name"] = trimmedDisplay
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedName.isEmpty { json["name"] = trimmedName }
            let trimmedAbout = about.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedAbout.isEmpty { json["about"] = trimmedAbout }
            let trimmedPicture = pictureURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedPicture.isEmpty { json["picture"] = trimmedPicture }

            let content = String(
                data: try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]),
                encoding: .utf8
            ) ?? "{}"

            // Publish kind 0
            let builder = EventBuilder(kind: Kind(kind: 0), content: content)

            do {
                _ = try await nostrService.publishEvent(keys: keys, builder: builder)
            } catch {
                // Offline graceful: publish failed, but save profile locally
                print("[RAID][Onboarding] kind 0 publish failed (offline?): \(error)")
            }

            // Update single source of truth
            drawerState.ownProfile = NostrProfile(
                pubkeyHex: pubkeyHex,
                name: trimmedName.isEmpty ? nil : trimmedName,
                displayName: trimmedDisplay,
                picture: trimmedPicture.isEmpty ? nil : trimmedPicture,
                about: trimmedAbout.isEmpty ? nil : trimmedAbout,
                banner: nil
            )

            onComplete(true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
