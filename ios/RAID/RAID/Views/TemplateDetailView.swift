// TemplateDetailView.swift
// RAID Golf - iOS Port
//
// KPI Template UX Sprint - Task 4
//
// Purpose:
// - Detail view for a single template
// - Show identity, metrics, and actions
// - Support renaming, hiding, and activating templates

import SwiftUI
import GRDB

struct TemplateDetailView: View {
    let templateHash: String
    let dbQueue: DatabaseQueue
    var onUpdate: (() -> Void)?

    @State private var template: TemplateRecord?
    @State private var preference: TemplatePreference?
    @State private var kpiTemplate: KPITemplate?
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var showingSetActiveAlert = false
    @State private var showingDuplicate = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if template == nil {
                ContentUnavailableView("Template Not Found", systemImage: "exclamationmark.triangle")
            } else {
                Form {
                    headerSection
                    identitySection
                    if let kpi = kpiTemplate {
                        metricsSection(kpi: kpi)
                    }
                    actionsSection
                }
            }
        }
        .navigationTitle("Template Details")
        .navigationBarTitleDisplayMode(.inline)
        .task { loadTemplate() }
        .alert("Set as Active Template", isPresented: $showingSetActiveAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Set Active") {
                setActive()
            }
        } message: {
            Text("Used for new imports only. Past sessions are not affected.")
        }
        .sheet(isPresented: $isRenaming) {
            renameSheet
        }
        .sheet(isPresented: $showingDuplicate) {
            CreateTemplateView(dbQueue: dbQueue, sourceTemplate: template) {
                loadTemplate()
                onUpdate?()
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
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

                HStack {
                    Text(template?.club ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.gray.opacity(0.2), in: Capsule())
                }
            }
        }
    }

    private var identitySection: some View {
        Section("Identity") {
            LabeledContent("Hash") {
                Text(shortHash)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if let created = template?.createdAt {
                LabeledContent("Created") {
                    Text(formatDate(created))
                        .foregroundStyle(.secondary)
                }
            }

            if let imported = template?.importedAt {
                LabeledContent("Imported") {
                    Text(formatDate(imported))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func metricsSection(kpi: KPITemplate) -> some View {
        Section("Metrics (\(kpi.metrics.count))") {
            ForEach(sortedMetrics(kpi.metrics), id: \.key) { metricName, thresholds in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(formatMetricName(metricName))
                            .font(.subheadline)
                        Spacer()
                        directionIcon(for: thresholds.direction)
                    }

                    HStack(spacing: 16) {
                        if let aMin = thresholds.aMin {
                            ThresholdLabel("A", value: aMin)
                        }
                        if let bMin = thresholds.bMin {
                            ThresholdLabel("B", value: bMin)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var actionsSection: some View {
        Section("Actions") {
            if preference?.isActive != true {
                Button("Set Active") {
                    showingSetActiveAlert = true
                }
            }

            Button("Rename") {
                renameText = preference?.displayName ?? ""
                isRenaming = true
            }

            Button(preference?.isHidden == true ? "Unhide" : "Hide") {
                toggleHidden()
            }

            Button("Duplicate") {
                showingDuplicate = true
            }
        }
    }

    // MARK: - Rename Sheet

    private var renameSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Display Name", text: $renameText)
                        .textInputAutocapitalization(.words)
                } footer: {
                    Text("Leave empty to use default name (club + hash).")
                }
            }
            .navigationTitle("Rename Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isRenaming = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveDisplayName()
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var displayName: String {
        if let name = preference?.displayName, !name.isEmpty {
            return name
        }
        guard let template = template else { return "" }
        return "\(template.club) \(shortHash)"
    }

    private var shortHash: String {
        String(templateHash.prefix(8))
    }

    private func sortedMetrics(_ metrics: [String: MetricThresholds]) -> [(key: String, value: MetricThresholds)] {
        metrics.sorted(by: { $0.key < $1.key })
    }

    private func formatMetricName(_ name: String) -> String {
        name.split(separator: "_")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private func directionIcon(for direction: MetricThresholds.Direction) -> some View {
        Image(systemName: direction == .higherIsBetter ? "arrow.up" : "arrow.down")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func formatDate(_ isoDate: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoDate) else { return isoDate }
        let display = DateFormatter()
        display.dateStyle = .medium
        return display.string(from: date)
    }

    // MARK: - Data Loading

    private func loadTemplate() {
        do {
            let templateRepo = TemplateRepository(dbQueue: dbQueue)
            let prefsRepo = TemplatePreferencesRepository(dbQueue: dbQueue)

            // Fetch template and preference in separate read blocks (no nesting)
            guard let fetchedTemplate = try templateRepo.fetchTemplate(byHash: templateHash) else {
                template = nil
                return
            }

            let fetchedPreference = try prefsRepo.fetchPreference(forHash: templateHash)

            // Decode KPI template from canonical JSON
            guard let data = fetchedTemplate.canonicalJSON.data(using: .utf8) else {
                template = fetchedTemplate
                preference = fetchedPreference
                kpiTemplate = nil
                return
            }

            let fetchedKPI = try JSONDecoder().decode(KPITemplate.self, from: data)

            template = fetchedTemplate
            preference = fetchedPreference
            kpiTemplate = fetchedKPI
        } catch {
            print("[RAID] Failed to load template: \(error)")
        }
    }

    // MARK: - Actions

    private func setActive() {
        guard let template = template else { return }
        do {
            let prefsRepo = TemplatePreferencesRepository(dbQueue: dbQueue)
            try prefsRepo.setActive(templateHash: templateHash, club: template.club)
            loadTemplate()
            onUpdate?()
        } catch {
            print("[RAID] Failed to set active: \(error)")
        }
    }

    private func saveDisplayName() {
        do {
            let prefsRepo = TemplatePreferencesRepository(dbQueue: dbQueue)

            // Ensure preference row exists first
            if let template = template {
                try prefsRepo.ensurePreferenceExists(forHash: templateHash, club: template.club)
            }

            // Set display name (nil if empty string)
            let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
            try prefsRepo.setDisplayName(templateHash: templateHash, name: name.isEmpty ? nil : name)

            isRenaming = false
            loadTemplate()
            onUpdate?()
        } catch {
            print("[RAID] Failed to save display name: \(error)")
        }
    }

    private func toggleHidden() {
        guard let template = template else { return }
        do {
            let prefsRepo = TemplatePreferencesRepository(dbQueue: dbQueue)

            // Ensure preference row exists first
            try prefsRepo.ensurePreferenceExists(forHash: templateHash, club: template.club)

            // Toggle hidden state
            let newHiddenState = !(preference?.isHidden ?? false)
            try prefsRepo.setHidden(templateHash: templateHash, hidden: newHiddenState)

            loadTemplate()
            onUpdate?()
        } catch {
            print("[RAID] Failed to toggle hidden: \(error)")
        }
    }
}

// MARK: - Threshold Label

private struct ThresholdLabel: View {
    let grade: String
    let value: Double

    init(_ grade: String, value: Double) {
        self.grade = grade
        self.value = value
    }

    var body: some View {
        HStack(spacing: 4) {
            Text("\(grade):")
                .fontWeight(.medium)
            Text(String(format: "%.1f", value))
        }
    }
}
