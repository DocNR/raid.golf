// TemplateListView.swift
// Gambit Golf
//
// Template Library (4th tab)
//
// Purpose:
// - List view showing all non-hidden templates grouped by club
// - 4th tab in main TabView
// - Navigation to detail view on tap

import SwiftUI
import GRDB

struct TemplateListView: View {
    let dbQueue: DatabaseQueue

    @State private var templates: [TemplateRecord] = []
    @State private var preferences: [String: TemplatePreference] = [:] // keyed by hash
    @State private var showingCreateTemplate = false

    var body: some View {
        NavigationStack {
            Group {
                if templates.isEmpty {
                    emptyState
                } else {
                    templatesList
                }
            }
            .navigationTitle("Templates")
            .navigationDestination(for: String.self) { hash in
                TemplateDetailView(templateHash: hash, dbQueue: dbQueue) {
                    loadTemplates()
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreateTemplate = true
                    } label: {
                        Label("Create Template", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingCreateTemplate) {
                CreateTemplateView(dbQueue: dbQueue) {
                    loadTemplates()
                }
            }
            .task { loadTemplates() }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Templates", systemImage: "list.clipboard")
        } description: {
            Text("Templates define what makes an A, B, or C shot. Tap + to create one.")
        } actions: {
            Button("Create Template") {
                showingCreateTemplate = true
            }
        }
    }

    private var templatesList: some View {
        List {
            ForEach(groupedByClub, id: \.key) { club, clubTemplates in
                Section(header: Text(club.uppercased())) {
                    ForEach(clubTemplates, id: \.hash) { template in
                        NavigationLink(value: template.hash) {
                            TemplateRow(template: template, preference: preferences[template.hash])
                        }
                    }
                }
            }
        }
        .refreshable { loadTemplates() }
    }

    /// Group templates by club (templates already ordered by club ASC from repository)
    private var groupedByClub: [(key: String, value: [TemplateRecord])] {
        let grouped = Dictionary(grouping: templates, by: { $0.club })
        return grouped.sorted(by: { $0.key < $1.key })
    }

    private func loadTemplates() {
        do {
            let templateRepo = TemplateRepository(dbQueue: dbQueue)
            let prefsRepo = TemplatePreferencesRepository(dbQueue: dbQueue)

            // Fetch templates and preferences in separate read blocks (no nesting)
            let fetchedTemplates = try templateRepo.listAllTemplates()

            var fetchedPreferences: [String: TemplatePreference] = [:]
            for template in fetchedTemplates {
                if let pref = try prefsRepo.fetchPreference(forHash: template.hash) {
                    fetchedPreferences[template.hash] = pref
                }
            }

            templates = fetchedTemplates
            preferences = fetchedPreferences
        } catch {
            print("[Gambit] Failed to load templates: \(error)")
        }
    }
}

// MARK: - Template Row

private struct TemplateRow: View {
    let template: TemplateRecord
    let preference: TemplatePreference?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(displayName)
                    .font(.headline)
                Spacer()
                if preference?.isActive == true {
                    Text("Active")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.blue, in: Capsule())
                }
            }

            HStack(spacing: 8) {
                Text(shortHash)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("\u{2022}")
                    .foregroundStyle(.secondary)
                Text("\(metricCount) metrics")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\u{2022}")
                    .foregroundStyle(.secondary)
                Text(formatDate(template.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var displayName: String {
        if let name = preference?.displayName, !name.isEmpty {
            return name
        }
        return "\(template.club) \(shortHash)"
    }

    private var shortHash: String {
        String(template.hash.prefix(8))
    }

    private var metricCount: Int {
        guard let data = template.canonicalJSON.data(using: .utf8),
              let kpiTemplate = try? JSONDecoder().decode(KPITemplate.self, from: data) else {
            return 0
        }
        return kpiTemplate.metrics.count
    }

    private func formatDate(_ isoDate: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoDate) else { return isoDate }
        let display = DateFormatter()
        display.dateStyle = .medium
        return display.string(from: date)
    }
}
