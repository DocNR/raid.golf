// AboutView.swift
// Gambit Golf
//
// In-app about screen.

import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Gambit Golf")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Version \(appVersion)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Practice analytics for golfers")
                            .font(.body)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    LabeledContent("Data Storage") {
                        Text("Local")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Social Sharing") {
                        Text("Nostr")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("All data stored locally on your device")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("Nostr-powered social sharing (opt-in)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var appVersion: String {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            return version
        }
        return "Unknown"
    }
}
