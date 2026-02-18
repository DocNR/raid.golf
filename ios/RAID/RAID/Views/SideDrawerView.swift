// SideDrawerView.swift
// RAID Golf
//
// Damus-style left drawer. Shows profile header + menu items.
// Menu taps close the drawer and present the corresponding sheet.

import SwiftUI
import GRDB

struct SideDrawerView: View {
    let dbQueue: DatabaseQueue

    @Environment(\.drawerState) private var drawerState

    @AppStorage("nostrActivated") private var nostrActivated = false
    @State private var showActivationAlert = false
    @State private var showActivation = false

    // Sign-out two-step alerts
    @State private var showKeyBackupAlert = false
    @State private var showSignOutConfirm = false

    // Danger zone
    @State private var showDangerZone = false
    @State private var showDeleteKeyBackupAlert = false
    @State private var showDeleteConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            profileHeader
                .padding(.horizontal, 20)
                .padding(.top, 60)
                .padding(.bottom, 20)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                drawerMenuItem(icon: "person.circle", label: "Profile") {
                    if nostrActivated {
                        drawerState.close()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                drawerState.showProfile = true
                            }
                        }
                    } else {
                        showActivationAlert = true
                    }
                }

                drawerMenuItem(icon: "sportscourt", label: "Practice") {
                    presentSheet { drawerState.showPractice = true }
                }

                drawerMenuItem(icon: "person.2", label: "Clubhouse") {
                    if nostrActivated {
                        presentSheet { drawerState.showClubhouse = true }
                    } else {
                        showActivationAlert = true
                    }
                }

                drawerMenuItem(icon: "key.horizontal", label: "Keys & Relays") {
                    if nostrActivated {
                        presentSheet { drawerState.showKeysRelays = true }
                    } else {
                        showActivationAlert = true
                    }
                }

                drawerMenuItem(icon: "info.circle", label: "About") {
                    presentSheet { drawerState.showAbout = true }
                }

                if !nostrActivated {
                    drawerMenuItem(icon: "person.badge.plus", label: "Create Account") {
                        presentSheet { showActivation = true }
                    }
                }
            }
            .padding(.top, 8)

            Spacer()

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                if nostrActivated {
                    drawerMenuItem(icon: "rectangle.portrait.and.arrow.right", label: "Sign Out") {
                        showKeyBackupAlert = true
                    }
                }

                drawerMenuItem(icon: "exclamationmark.triangle", label: "Danger Zone", tint: .red) {
                    presentSheet { showDangerZone = true }
                }
            }
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .nostrActivationAlert(
            isPresented: $showActivationAlert,
            message: "Create an account to view your profile and share rounds.",
            onActivate: { showActivation = true }
        )
        .fullScreenCover(isPresented: $showActivation) {
            WelcomeView { activated in
                UserDefaults.standard.set(activated, forKey: "nostrActivated")
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                showActivation = false
            }
        }
        // Sign Out — Step 1: key backup warning
        .alert("Have You Saved Your Secret Key?", isPresented: $showKeyBackupAlert) {
            Button("Copy Secret Key") {
                copySecretKey()
                // Re-show this alert so they can proceed after copying
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showKeyBackupAlert = true
                }
            }
            Button("I've Saved It") {
                showSignOutConfirm = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Without your secret key, you cannot recover this account. There is no reset or recovery option.")
        }
        // Sign Out — Step 2: final confirmation
        .alert("Sign Out?", isPresented: $showSignOutConfirm) {
            Button("Sign Out", role: .destructive) {
                performSignOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to create a new account or sign in again to use social features.")
        }
        // Danger Zone sheet
        .sheet(isPresented: $showDangerZone) {
            dangerZoneSheet
        }
    }

    // MARK: - Danger Zone Sheet

    private var dangerZoneSheet: some View {
        NavigationStack {
            List {
                Section {
                    Label {
                        Text("These actions are permanent and cannot be undone.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteKeyBackupAlert = true
                    } label: {
                        Label("Delete All Data & Sign Out", systemImage: "trash")
                    }
                } footer: {
                    Text("Permanently deletes all practice sessions, rounds, templates, and your account. The app will close.")
                }
            }
            .navigationTitle("Danger Zone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showDangerZone = false }
                }
            }
            // Delete All Data — Step 1: key backup warning
            .alert("Have You Saved Your Secret Key?", isPresented: $showDeleteKeyBackupAlert) {
                Button("Copy Secret Key") {
                    copySecretKey()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        showDeleteKeyBackupAlert = true
                    }
                }
                Button("I've Saved It") {
                    showDeleteConfirm = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Without your secret key, you cannot recover this account. There is no reset or recovery option.")
            }
            // Delete All Data — Step 2: final confirmation
            .alert("Delete Everything?", isPresented: $showDeleteConfirm) {
                Button("Delete All Data", role: .destructive) {
                    performDeleteAllData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all practice sessions, rounds, and templates. The app will close and you'll start fresh.")
            }
        }
    }

    // MARK: - Profile Header

    @ViewBuilder
    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            if nostrActivated {
                ProfileAvatarView(
                    pictureURL: drawerState.ownProfile?.picture,
                    size: 56
                )

                if let profile = drawerState.ownProfile {
                    if let displayName = profile.displayName, !displayName.isEmpty {
                        Text(displayName)
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                    if let name = profile.name, !name.isEmpty {
                        Text("@\(name)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if let npub = try? KeyManager.loadOrCreate().publicKeyBech32() {
                    Text(String(npub.prefix(20)) + "...")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            } else {
                ProfileAvatarView(pictureURL: nil, size: 56)
                Text("Guest")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Create an account to share rounds")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Menu Item

    private func drawerMenuItem(icon: String, label: String, tint: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .frame(width: 24)
                    .foregroundStyle(tint)
                Text(label)
                    .font(.body)
                    .foregroundStyle(tint)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func copySecretKey() {
        do {
            let keyManager = try KeyManager.loadOrCreate()
            try keyManager.copySecretKeyToPasteboard()
        } catch {
            // Silently fail — user can still use Keys & Relays to copy
        }
    }

    private func performSignOut() {
        KeyManager.deleteKey()
        UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        UserDefaults.standard.set(false, forKey: "nostrActivated")
        drawerState.ownProfile = nil
        drawerState.close()
    }

    private func performDeleteAllData() {
        // Delete SQLite database file
        if let supportDir = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) {
            let dbURL = supportDir.appendingPathComponent("raid_ios.sqlite")
            try? FileManager.default.removeItem(at: dbURL)
            // Also remove WAL and SHM files
            try? FileManager.default.removeItem(at: dbURL.appendingPathExtension("wal"))
            try? FileManager.default.removeItem(at: dbURL.appendingPathExtension("shm"))
        }

        // Delete Keychain key
        KeyManager.deleteKey()

        // Clear all UserDefaults
        if let bundleId = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleId)
        }

        // Exit app — relaunch creates fresh database
        exit(0)
    }

    // MARK: - Helpers

    private func presentSheet(_ show: @escaping () -> Void) {
        drawerState.close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            show()
        }
    }
}
