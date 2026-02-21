// PracticeView.swift
// RAID Golf
//
// Consolidated practice hub. Accessed from the side drawer.
// Combines Sessions (with CSV import), Trends, and Templates via segmented control.
// Each child view keeps its own NavigationStack — zero modifications to existing views.

import SwiftUI
import GRDB

struct PracticeView: View {
    let dbQueue: DatabaseQueue

    @Environment(\.dismiss) private var dismiss
    @State private var selectedSection = 0

    // Guest activation prompt
    @AppStorage("nostrActivated") private var nostrActivated = false
    @AppStorage("backupDataPromptDismissals") private var backupDataDismissCount = 0
    @State private var sessionCount = 0
    @State private var showActivation = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $selectedSection) {
                    Text("Sessions").tag(0)
                    Text("Trends").tag(1)
                    Text("Templates").tag(2)
                }
                .pickerStyle(.segmented)

                Button("Done") { dismiss() }
                    .padding(.leading, 8)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))

            if !nostrActivated && sessionCount >= 5 && backupDataDismissCount < 3 {
                ActivationPromptCard(
                    icon: "icloud.and.arrow.up",
                    headline: "Back up Your Data",
                    subtitle: "Create an account to back up your practice data to Nostr."
                ) {
                    showActivation = true
                } onDismiss: {
                    backupDataDismissCount += 1
                }
                .padding(.top, 8)
            }

            switch selectedSection {
            case 0: SessionsView(dbQueue: dbQueue)
            case 1: TrendsView(dbQueue: dbQueue)
            default: TemplateListView(dbQueue: dbQueue)
            }
        }
        .task {
            do {
                let repo = SessionRepository(dbQueue: dbQueue)
                sessionCount = try repo.sessionCount()
            } catch {
                print("[RAID] PracticeView: failed to load session count: \(error)")
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
