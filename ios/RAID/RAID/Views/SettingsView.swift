// SettingsView.swift
// RAID Golf
//
// Settings sheet consolidating account, about, and sign-out actions.
// Sign-out flow is delegated back to SideDrawerView via onSignOut closure.

import SwiftUI
import GRDB

struct SettingsView: View {
    let dbQueue: DatabaseQueue
    var onSignOut: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @AppStorage("nostrActivated") private var nostrActivated = false

    // WelcomeView activation sheet
    @State private var showActivation = false

    var body: some View {
        NavigationStack {
            List {
                // Account section
                Section("Account") {
                    if nostrActivated {
                        NavigationLink("Edit Profile") {
                            EditProfileView()
                        }
                        NavigationLink("Keys & Relays") {
                            NostrProfileView(dbQueue: dbQueue)
                        }
                    } else {
                        Button("Create Account or Sign In") {
                            showActivation = true
                        }
                    }
                }

                // About section
                Section("About") {
                    NavigationLink("About RAID") {
                        AboutView()
                    }
                }

                // Sign out — only when activated
                if nostrActivated {
                    Section {
                        Button("Sign Out", role: .destructive) {
                            dismiss()
                            // Slight delay so sheet dismisses before alert appears
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                onSignOut?()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showActivation) {
                WelcomeView { activated in
                    UserDefaults.standard.set(activated, forKey: "nostrActivated")
                    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                    showActivation = false
                }
            }
        }
    }
}
