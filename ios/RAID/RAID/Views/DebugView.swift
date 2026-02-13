// DebugView.swift
// Gambit Golf
//
// Read-only diagnostic screen for debug builds
//
// Purpose:
// - Display kernel facts (counts), product state, Nostr identity, build info
// - Accessible via long-press on Templates tab title
// - All diagnostic data loaded via simple SQL COUNT queries

#if DEBUG

import SwiftUI
import GRDB

struct DebugView: View {
    let dbQueue: DatabaseQueue

    @Environment(\.dismiss) private var dismiss
    @State private var diagnostics: Diagnostics?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let diag = diagnostics {
                    diagnosticsList(diag)
                } else {
                    ProgressView("Loading diagnostics...")
                }
            }
            .navigationTitle("Debug Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task { loadDiagnostics() }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let message = errorMessage {
                    Text(message)
                }
            }
        }
    }

    private func diagnosticsList(_ diag: Diagnostics) -> some View {
        List {
            Section("Kernel Facts") {
                DiagnosticRow(label: "Sessions", value: "\(diag.sessionCount)")
                DiagnosticRow(label: "Shots", value: "\(diag.shotCount)")
                DiagnosticRow(label: "KPI Templates", value: "\(diag.templateCount)")
                DiagnosticRow(label: "Club Subsessions", value: "\(diag.subsessionCount)")
            }

            Section("Scorecard Facts") {
                DiagnosticRow(label: "Rounds", value: "\(diag.roundCount)")
                DiagnosticRow(label: "Course Snapshots", value: "\(diag.courseSnapshotCount)")
                DiagnosticRow(label: "Hole Scores", value: "\(diag.holeScoreCount)")
                DiagnosticRow(label: "Round Events", value: "\(diag.roundEventCount)")
            }

            Section("Product State") {
                DiagnosticRow(label: "Template Preferences", value: "\(diag.preferenceCount)")
                DiagnosticRow(label: "DB File Size", value: diag.dbFileSizeMB)
            }

            Section("Nostr Identity") {
                DiagnosticRow(label: "npub (truncated)", value: diag.npubTruncated)
                DiagnosticRow(label: "Public Key (hex)", value: diag.publicKeyHex)
            }

            Section("Build Info") {
                DiagnosticRow(label: "App Version", value: diag.appVersion)
                DiagnosticRow(label: "Build Number", value: diag.buildNumber)
                DiagnosticRow(label: "Kernel Version", value: "v2")
            }
        }
        .listStyle(.insetGrouped)
    }

    private func loadDiagnostics() {
        do {
            // Load all diagnostic data
            var diag = Diagnostics()

            // Kernel + Scorecard + Product counts (single read block)
            try dbQueue.read { db in
                diag.sessionCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sessions") ?? 0
                diag.shotCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM shots") ?? 0
                diag.templateCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM kpi_templates") ?? 0
                diag.subsessionCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM club_subsessions") ?? 0

                diag.roundCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM rounds") ?? 0
                diag.courseSnapshotCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM course_snapshots") ?? 0
                diag.holeScoreCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM hole_scores") ?? 0
                diag.roundEventCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM round_events") ?? 0

                diag.preferenceCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM template_preferences") ?? 0
            }

            // DB file size
            let supportDir = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )
            let dbURL = supportDir.appendingPathComponent("raid_ios.sqlite")

            if let attrs = try? FileManager.default.attributesOfItem(atPath: dbURL.path),
               let fileSize = attrs[.size] as? Int64 {
                let sizeMB = Double(fileSize) / 1_048_576.0
                diag.dbFileSizeMB = String(format: "%.2f MB", sizeMB)
            } else {
                diag.dbFileSizeMB = "Unknown"
            }

            // Nostr identity
            do {
                let keyManager = try KeyManager.loadOrCreate()
                let npub = try keyManager.publicKeyBech32()

                // Truncate npub (keep first 16 chars: "npub1" + 12 chars)
                if npub.count > 16 {
                    diag.npubTruncated = String(npub.prefix(16)) + "..."
                } else {
                    diag.npubTruncated = npub
                }

                // Get hex public key (first 12 chars)
                // NostrSDK PublicKey doesn't expose .hex directly, so we decode from bech32
                let pubkey = keyManager.signingKeys().publicKey()
                let pubkeyHex = pubkey.toHex()
                diag.publicKeyHex = String(pubkeyHex.prefix(12)) + "..."

            } catch {
                diag.npubTruncated = "Not available"
                diag.publicKeyHex = "Not available"
            }

            // Build info (from Bundle)
            diag.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
            diag.buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"

            diagnostics = diag

        } catch {
            errorMessage = "Failed to load diagnostics: \(error.localizedDescription)"
        }
    }
}

// MARK: - Diagnostic Data

private struct Diagnostics {
    var sessionCount: Int = 0
    var shotCount: Int = 0
    var templateCount: Int = 0
    var subsessionCount: Int = 0

    var roundCount: Int = 0
    var courseSnapshotCount: Int = 0
    var holeScoreCount: Int = 0
    var roundEventCount: Int = 0

    var preferenceCount: Int = 0
    var dbFileSizeMB: String = "Unknown"

    var npubTruncated: String = "Not available"
    var publicKeyHex: String = "Not available"

    var appVersion: String = "Unknown"
    var buildNumber: String = "Unknown"
}

// MARK: - Diagnostic Row

private struct DiagnosticRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .font(.system(.body, design: .monospaced))
        }
    }
}

#endif
