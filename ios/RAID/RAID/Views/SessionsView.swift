// SessionsView.swift
// Gambit Golf
//
// Sessions list + CSV import

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
            NavigationLink {
                PracticeSummaryView(sessionId: session.sessionId, dbQueue: dbQueue)
            } label: {
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
        }
        .refreshable { loadSessions() }
    }

    private func loadSessions() {
        do {
            let repo = SessionRepository(dbQueue: dbQueue)
            sessions = try repo.listSessions()
        } catch {
            print("[Gambit] Failed to load sessions: \(error)")
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

                // Phase 4B v2: auto-analyze to pin template_hash for A-only trends
                analyzeImportedSession(sessionId: ingestResult.sessionId, shotRepo: shotRepo)

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

    /// Post-import analysis: create club_subsessions rows to pin template_hash.
    /// Non-fatal: if analysis fails, import still succeeded but A-only trends
    /// won't include this session until re-analysis.
    private func analyzeImportedSession(sessionId: Int64, shotRepo: ShotRepository) {
        let templateRepo = TemplateRepository(dbQueue: dbQueue)
        let prefsRepo = TemplatePreferencesRepository(dbQueue: dbQueue)
        let subsessionRepo = SubsessionRepository(dbQueue: dbQueue)

        do {
            let allShots = try shotRepo.fetchShots(forSession: sessionId)
            let clubGroups = Dictionary(grouping: allShots, by: { $0.club })

            for (club, shots) in clubGroups {
                // Try active template first, fall back to latest
                guard let templateRecord = try prefsRepo.fetchActiveTemplate(forClub: club)
                    ?? templateRepo.fetchLatestTemplate(forClub: club),
                      let templateData = templateRecord.canonicalJSON.data(using: .utf8) else {
                    continue
                }
                let template = try JSONDecoder().decode(KPITemplate.self, from: templateData)
                try subsessionRepo.analyzeSessionClub(
                    sessionId: sessionId,
                    club: club,
                    shots: shots,
                    template: template,
                    templateHash: templateRecord.hash
                )
            }
        } catch {
            print("[Gambit] Post-import analysis failed: \(error)")
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
