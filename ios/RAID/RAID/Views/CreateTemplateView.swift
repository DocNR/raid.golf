// CreateTemplateView.swift
// Gambit Golf
//
// Create / duplicate template
//
// Purpose:
// - Form for creating new KPI templates or duplicating existing ones
// - Builds template JSON, calls insertTemplate(rawJSON:)
// - Handles PK collisions, validation, and preference setup

import SwiftUI
import GRDB

struct CreateTemplateView: View {
    let dbQueue: DatabaseQueue
    var sourceTemplate: TemplateRecord?
    var onCreated: (() -> Void)?

    @State private var club: String = "7i"
    @State private var displayName: String = ""
    @State private var metrics: [EditableMetric] = []
    @State private var errorMessage: String?
    @State private var showingError = false
    @State private var clubChoices: [String] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                clubSection
                displayNameSection
                metricsSection
            }
            .navigationTitle(sourceTemplate == nil ? "Create Template" : "Duplicate Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTemplate()
                    }
                    .disabled(!isValid)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
            .task {
                loadSourceTemplate()
            }
        }
    }

    // MARK: - Sections

    private var clubSection: some View {
        Section {
            Picker("Club", selection: $club) {
                ForEach(clubChoices, id: \.self) { clubName in
                    Text(clubName).tag(clubName)
                }
            }
        } footer: {
            Text("Must match the club name in your Rapsodo CSV exports.")
        }
    }

    private var displayNameSection: some View {
        Section {
            TextField("Display Name (Optional)", text: $displayName)
                .textInputAutocapitalization(.words)
        } footer: {
            Text("Leave empty to use default name (club + hash).")
        }
    }

    private var metricsSection: some View {
        Section {
            ForEach(metrics) { metric in
                metricRow(metric: metric)
            }
            .onDelete { indices in
                metrics.remove(atOffsets: indices)
            }

            Button {
                addMetric()
            } label: {
                Label("Add Metric", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Metrics")
        } footer: {
            Text("Define grade thresholds for each metric. At least one metric required.")
        }
    }

    private func metricRow(metric: EditableMetric) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Metric name picker
            Picker("Metric", selection: bindingForMetric(metric, keyPath: \.name)) {
                ForEach(availableMetrics, id: \.self) { metricName in
                    Text(formatMetricName(metricName))
                        .tag(metricName)
                }
            }

            // Direction picker
            Picker("Direction", selection: bindingForMetric(metric, keyPath: \.direction)) {
                Text("Higher is better").tag(MetricThresholds.Direction.higherIsBetter)
                Text("Lower is better").tag(MetricThresholds.Direction.lowerIsBetter)
            }
            .pickerStyle(.segmented)

            // Thresholds
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("A Threshold")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Required", text: bindingForMetric(metric, keyPath: \.aThreshold))
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("B Threshold")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Optional", text: bindingForMetric(metric, keyPath: \.bThreshold))
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Validation

    private var isValid: Bool {
        guard !club.isEmpty else {
            return false
        }
        guard !metrics.isEmpty else {
            return false
        }
        // Each metric must have a name and A threshold
        for metric in metrics {
            if metric.name.isEmpty {
                return false
            }
            if metric.aThreshold.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
            // Validate A threshold is a number
            if Double(metric.aThreshold.trimmingCharacters(in: .whitespacesAndNewlines)) == nil {
                return false
            }
            // If B threshold is provided, validate it's a number
            let bTrimmed = metric.bThreshold.trimmingCharacters(in: .whitespacesAndNewlines)
            if !bTrimmed.isEmpty {
                if Double(bTrimmed) == nil {
                    return false
                }
            }
        }
        return true
    }

    // MARK: - Actions

    private func loadSourceTemplate() {
        loadClubChoices()

        guard let source = sourceTemplate else {
            // New template — add one empty metric
            metrics = [EditableMetric()]
            return
        }

        // Duplicate — pre-fill from source
        club = source.club

        // Parse canonical JSON to get metrics
        guard let data = source.canonicalJSON.data(using: .utf8),
              let kpiTemplate = try? JSONDecoder().decode(KPITemplate.self, from: data) else {
            metrics = [EditableMetric()]
            return
        }

        // Convert to editable metrics
        metrics = kpiTemplate.metrics.map { (name, thresholds) in
            var metric = EditableMetric()
            metric.name = name
            metric.direction = thresholds.direction

            // Populate thresholds based on direction
            if thresholds.direction == .higherIsBetter {
                if let aMin = thresholds.aMin {
                    metric.aThreshold = String(format: "%.1f", aMin)
                }
                if let bMin = thresholds.bMin {
                    metric.bThreshold = String(format: "%.1f", bMin)
                }
            } else {
                if let aMax = thresholds.aMax {
                    metric.aThreshold = String(format: "%.1f", aMax)
                }
                if let bMax = thresholds.bMax {
                    metric.bThreshold = String(format: "%.1f", bMax)
                }
            }

            return metric
        }.sorted(by: { $0.name < $1.name })
    }

    private func addMetric() {
        metrics.append(EditableMetric())
    }

    private func saveTemplate() {
        do {
            // Build template JSON
            var metricsDict: [String: [String: Any]] = [:]

            for metric in metrics {
                guard let aValue = Double(metric.aThreshold.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    continue
                }

                let bTrimmed = metric.bThreshold.trimmingCharacters(in: .whitespacesAndNewlines)
                let bValue = bTrimmed.isEmpty ? nil : Double(bTrimmed)

                var metricDict: [String: Any] = [
                    "direction": metric.direction.rawValue
                ]

                // Set min/max based on direction
                if metric.direction == .higherIsBetter {
                    metricDict["a_min"] = aValue
                    if let b = bValue {
                        metricDict["b_min"] = b
                    }
                } else {
                    metricDict["a_max"] = aValue
                    if let b = bValue {
                        metricDict["b_max"] = b
                    }
                }

                metricsDict[metric.name] = metricDict
            }

            let templateDict: [String: Any] = [
                "schema_version": "1.0",
                "club": club.trimmingCharacters(in: .whitespacesAndNewlines),
                "aggregation_method": "worst_metric",
                "metrics": metricsDict
            ]

            // Serialize to JSON
            let jsonData = try JSONSerialization.data(withJSONObject: templateDict, options: [])

            // Insert template
            let templateRepo = TemplateRepository(dbQueue: dbQueue)
            let templateRecord = try templateRepo.insertTemplate(rawJSON: jsonData)

            // Create preference row
            let prefsRepo = TemplatePreferencesRepository(dbQueue: dbQueue)
            try prefsRepo.ensurePreferenceExists(forHash: templateRecord.hash, club: templateRecord.club)

            // Set display name if provided
            let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedName.isEmpty {
                try prefsRepo.setDisplayName(templateHash: templateRecord.hash, name: trimmedName)
            }

            // Set as active
            try prefsRepo.setActive(templateHash: templateRecord.hash, club: templateRecord.club)

            // Success
            onCreated?()
            dismiss()
        } catch let error as DatabaseError {
            // Check for PK collision
            if error.resultCode == .SQLITE_CONSTRAINT {
                errorMessage = "A template with these exact thresholds already exists for this club. Change at least one threshold to create a new version."
                showingError = true
            } else {
                errorMessage = "Failed to create template: \(error.localizedDescription)"
                showingError = true
            }
        } catch {
            errorMessage = "Failed to create template: \(error.localizedDescription)"
            showingError = true
        }
    }

    // MARK: - Club List

    private static let defaultClubs = [
        "Driver", "3w", "5w", "7w",
        "3h", "4h", "5h",
        "3i", "4i", "5i", "6i", "7i", "8i", "9i",
        "PW", "GW", "SW", "LW"
    ]

    private func loadClubChoices() {
        // Start with defaults keyed by lowercase for dedup
        var clubsByLower: [String: String] = [:]
        for c in Self.defaultClubs {
            clubsByLower[c.lowercased()] = c
        }

        // Imported clubs override defaults (use exact casing from CSV)
        if let importedClubs = try? dbQueue.read({ db in
            try String.fetchAll(db, sql: "SELECT DISTINCT club FROM shots")
        }) {
            for c in importedClubs {
                clubsByLower[c.lowercased()] = c
            }
        }

        // Ensure source club is always present when duplicating
        if let source = sourceTemplate {
            clubsByLower[source.club.lowercased()] = source.club
        }

        clubChoices = clubsByLower.values.sorted { lhs, rhs in
            clubSortKey(lhs) < clubSortKey(rhs)
        }
    }

    private func clubSortKey(_ club: String) -> (Int, Int, String) {
        let lower = club.lowercased()
        if lower == "driver" { return (0, 0, club) }
        if lower.hasSuffix("w") && !lower.hasSuffix("pw") && !lower.hasSuffix("gw") && !lower.hasSuffix("sw") && !lower.hasSuffix("lw") {
            let num = Int(lower.dropLast()) ?? 99
            return (1, num, club)
        }
        if lower.hasSuffix("h") {
            let num = Int(lower.dropLast()) ?? 99
            return (2, num, club)
        }
        if lower.hasSuffix("i") {
            let num = Int(lower.dropLast()) ?? 99
            return (3, num, club)
        }
        // Wedges
        let wedgeOrder = ["pw": 0, "gw": 1, "sw": 2, "lw": 3]
        if let order = wedgeOrder[lower] {
            return (4, order, club)
        }
        return (5, 0, club)
    }

    // MARK: - Helpers

    private let availableMetrics = [
        "ball_speed",
        "carry",
        "total_distance",
        "club_speed",
        "launch_angle",
        "spin_rate",
        "spin_axis",
        "apex",
        "descent_angle",
        "smash_factor",
        "attack_angle",
        "club_path",
        "side_carry",
        "launch_direction"
    ]

    private func formatMetricName(_ name: String) -> String {
        name.split(separator: "_")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private func bindingForMetric<T>(_ metric: EditableMetric, keyPath: WritableKeyPath<EditableMetric, T>) -> Binding<T> {
        guard let index = metrics.firstIndex(where: { $0.id == metric.id }) else {
            fatalError("Metric not found in array")
        }
        return Binding(
            get: { metrics[index][keyPath: keyPath] },
            set: { metrics[index][keyPath: keyPath] = $0 }
        )
    }
}

// MARK: - Editable Metric

struct EditableMetric: Identifiable {
    let id = UUID()
    var name: String = "ball_speed"
    var direction: MetricThresholds.Direction = .higherIsBetter
    var aThreshold: String = ""
    var bThreshold: String = ""
}
