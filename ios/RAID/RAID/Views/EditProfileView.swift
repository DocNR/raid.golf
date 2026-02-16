// EditProfileView.swift
// RAID Golf
//
// Edit and publish kind 0 profile metadata to Nostr relays.

import SwiftUI
import NostrSDK

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.nostrService) private var nostrService
    @Environment(\.drawerState) private var drawerState

    @State private var name: String = ""
    @State private var displayName: String = ""
    @State private var about: String = ""
    @State private var pictureURL: String = ""
    @State private var bannerURL: String = ""
    @State private var isPublishing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Display Name") {
                    TextField("Display Name", text: $displayName)
                }

                Section("Username") {
                    TextField("username (no @)", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("About") {
                    TextEditor(text: $about)
                        .frame(minHeight: 80)
                }

                Section("Avatar URL") {
                    TextField("https://...", text: $pictureURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    if !pictureURL.isEmpty {
                        ProfileAvatarView(pictureURL: pictureURL, size: 60)
                            .frame(maxWidth: .infinity)
                    }
                }

                Section("Banner URL") {
                    TextField("https://...", text: $bannerURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isPublishing {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task { await publishProfile() }
                        }
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
            .task { loadCurrentProfile() }
        }
    }

    private func loadCurrentProfile() {
        if let profile = drawerState.ownProfile {
            name = profile.name ?? ""
            displayName = profile.displayName ?? ""
            about = profile.about ?? ""
            pictureURL = profile.picture ?? ""
            bannerURL = profile.banner ?? ""
        }
    }

    private func publishProfile() async {
        isPublishing = true
        defer { isPublishing = false }

        do {
            let keyManager = try KeyManager.loadOrCreate()
            let keys = keyManager.signingKeys()

            var json: [String: String] = [:]
            if !name.isEmpty { json["name"] = name }
            if !displayName.isEmpty { json["display_name"] = displayName }
            if !about.isEmpty { json["about"] = about }
            if !pictureURL.isEmpty { json["picture"] = pictureURL }
            if !bannerURL.isEmpty { json["banner"] = bannerURL }

            let content = String(
                data: try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]),
                encoding: .utf8
            ) ?? "{}"

            let builder = EventBuilder(kind: Kind(kind: 0), content: content)
            _ = try await nostrService.publishEvent(keys: keys, builder: builder)

            // Update cached profile
            let pubkeyHex = keys.publicKey().toHex()
            drawerState.ownProfile = NostrProfile(
                pubkeyHex: pubkeyHex,
                name: name.isEmpty ? nil : name,
                displayName: displayName.isEmpty ? nil : displayName,
                picture: pictureURL.isEmpty ? nil : pictureURL,
                about: about.isEmpty ? nil : about,
                banner: bannerURL.isEmpty ? nil : bannerURL
            )

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
