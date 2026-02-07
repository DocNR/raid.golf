// SessionsView.swift
// RAID Golf - iOS Port
//
// Phase 4C: Sessions list + CSV import

import SwiftUI
import GRDB
import UniformTypeIdentifiers

struct SessionsView: View {
    let dbQueue: DatabaseQueue

    @State private var sessions: [SessionListItem] = []
    @State private var showingImporter = false
    @State private var importResult: ImportResultInfo?
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    emptyState
                } else {
                    sessionsList
                }
            }
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingImporter = true
                    } label: {
                        Label("Import CSV", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [UTType.commaSeparatedText],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .alert("Import Complete",
                   isPresented: Binding(
                    get: { importResult != nil },
                    set: { if !$0 { importResult = nil } }
                   )
            ) {
                Button("OK") { importResult = nil }
            } message: {
                if let info = importResult {
                    Text("\(info.imported) shots imported, \(info.skipped) skipped\nFile: \(info.fileName)")
                }
            }
            .alert("Import Failed",
                   isPresented: Binding(
                    get: { importError != nil },
                    set: { if !$0 { importError = nil } }
                   )
            ) {
                Button("OK") { importError = nil }
            } message: {
                if let error = importError {
                    Text(error)
                }
            }
            .task { loadSessions() }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Sessions", systemImage: "tray")
        } description: {
            Text("Import a Rapsodo CSV to get started.")
        } actions: {
            Button("Import CSV") {
                showingImporter = true
            }
        }
    }

    private var sessionsList: some View {
        List(sessions, id: \.sessionId) { session in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(formatDate(session.sessionDate))
                        .font(.headline)
                    Spacer()
                    Text("\(session.shotCount) shots")
                        .foregroundStyle(.secondary)
                }
                Text(session.sourceFile)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .refreshable { loadSessions() }
    }

    private func loadSessions() {
        do {
            let repo = SessionRepository(dbQueue: dbQueue)
            sessions = try repo.listSessions()
        } catch {
            print("[RAID] Failed to load sessions: \(error)")
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            // Security-scoped resource access for files from document picker
            guard url.startAccessingSecurityScopedResource() else {
                importError = "Cannot access file: permission denied."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let sessionRepo = SessionRepository(dbQueue: dbQueue)
                let shotRepo = ShotRepository(dbQueue: dbQueue)
                let ingestResult = try RapsodoIngest.ingest(
                    csvURL: url,
                    sessionRepository: sessionRepo,
                    shotRepository: shotRepo
                )
                importResult = ImportResultInfo(
                    imported: ingestResult.importedCount,
                    skipped: ingestResult.skippedCount,
                    fileName: url.lastPathComponent
                )
                loadSessions()
            } catch {
                importError = error.localizedDescription
            }

        case .failure(let error):
            importError = error.localizedDescription
        }
    }

    private func formatDate(_ isoDate: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoDate) else { return isoDate }
        let display = DateFormatter()
        display.dateStyle = .medium
        display.timeStyle = .short
        return display.string(from: date)
    }
}

private struct ImportResultInfo {
    let imported: Int
    let skipped: Int
    let fileName: String
}
