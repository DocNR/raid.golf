// TrendsView.swift
// RAID Golf
//
// Trends view
// Phase 4C: Empty state keyed on session count

import SwiftUI
import GRDB

enum TemplateFilter: Hashable {
    case all          // Show all points (current behavior)
    case activeOnly   // Filter to active template hash only
    case specific(String) // Filter to a specific template hash
}

struct TrendsView: View {
    let dbQueue: DatabaseQueue

    @State private var selectedClub: String = "7i"
    @State private var selectedMetric: TrendMetric = .carry
    @State private var allShotsPoints: [TrendPoint] = []
    @State private var aOnlyPoints: [TrendPoint] = []
    @State private var hasSessions: Bool = false
    @State private var errorMessage: String?
    @State private var templateFilter: TemplateFilter = .all
    @State private var activeTemplateHash: String?
    @State private var templatePreferences: [String: TemplatePreference] = [:]

    var body: some View {
        NavigationStack {
            Group {
                if !hasSessions {
                    ContentUnavailableView {
                        Label("No Trends Yet", systemImage: "chart.line.uptrend.xyaxis")
                    } description: {
                        Text("Trends appear after you import practice sessions. Head to the Sessions tab to import a Rapsodo CSV.")
                    }
                } else {
                    trendsList
                }
            }
            .navigationTitle("Trends")
            .task { await loadTrends() }
            .refreshable { await loadTrends() }
        }
    }

    private var trendsList: some View {
        List {
            Section("Filters") {
                HStack {
                    Text("Club")
                    Spacer()
                    Text(selectedClub)
                        .foregroundStyle(.secondary)
                }

                Picker("Metric", selection: $selectedMetric) {
                    ForEach(TrendMetric.allCases, id: \.self) { metric in
                        Text(metric.label).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedMetric) { _, _ in
                    Task { await loadTrends() }
                }

                Picker("Template", selection: $templateFilter) {
                    Text("All Templates").tag(TemplateFilter.all)
                    Text("Active Only").tag(TemplateFilter.activeOnly)
                    ForEach(distinctTemplateHashes, id: \.self) { hash in
                        Text(templateDisplayName(hash)).tag(TemplateFilter.specific(hash))
                    }
                }
            }

            if let errorMessage {
                Section("Error") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section("All Shots") {
                if allShotsPoints.isEmpty {
                    Text("No trend data")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(allShotsPoints, id: \.sessionId) { point in
                        TrendPointRow(point: point)
                    }
                }
            }

            Section("A-only") {
                if filteredAOnlyPoints.isEmpty {
                    Text("No trend data")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredAOnlyPoints, id: \.sessionId) { point in
                        TrendPointRow(point: point)
                    }
                }
            }
        }
    }

    private var filteredAOnlyPoints: [TrendPoint] {
        switch templateFilter {
        case .all:
            return aOnlyPoints
        case .activeOnly:
            guard let activeHash = activeTemplateHash else { return aOnlyPoints }
            return aOnlyPoints.filter { $0.templateHash == activeHash }
        case .specific(let hash):
            return aOnlyPoints.filter { $0.templateHash == hash }
        }
    }

    private var distinctTemplateHashes: [String] {
        Array(Set(aOnlyPoints.compactMap { $0.templateHash })).sorted()
    }

    private func templateDisplayName(_ hash: String) -> String {
        if let pref = templatePreferences[hash], let name = pref.displayName, !name.isEmpty {
            return name
        }
        return String(hash.prefix(8))
    }

    @MainActor
    private func loadTrends() async {
        do {
            let sessionRepo = SessionRepository(dbQueue: dbQueue)
            hasSessions = try sessionRepo.sessionCount() > 0

            guard hasSessions else { return }

            let trendsRepository = TrendsRepository(dbQueue: dbQueue)
            allShotsPoints = try trendsRepository.fetchTrendPoints(
                club: selectedClub,
                metric: selectedMetric,
                seriesType: .allShots
            )
            aOnlyPoints = try trendsRepository.fetchTrendPoints(
                club: selectedClub,
                metric: selectedMetric,
                seriesType: .aOnly
            )

            // Fetch active template for this club
            let prefsRepo = TemplatePreferencesRepository(dbQueue: dbQueue)
            let activeTemplate = try prefsRepo.fetchActiveTemplate(forClub: selectedClub)
            activeTemplateHash = activeTemplate?.hash

            // Fetch preferences for all distinct template hashes (sequential reads)
            let distinctHashes = Array(Set(aOnlyPoints.compactMap { $0.templateHash }))
            var prefs: [String: TemplatePreference] = [:]
            for hash in distinctHashes {
                if let pref = try prefsRepo.fetchPreference(forHash: hash) {
                    prefs[hash] = pref
                }
            }
            templatePreferences = prefs

            // Set default filter: activeOnly if active template exists, otherwise all
            templateFilter = activeTemplateHash != nil ? .activeOnly : .all

            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct TrendPointRow: View {
    let point: TrendPoint

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(formatDate(point.sessionDate))
                Spacer()
                Text("n=\(point.nShots)")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text(point.meanValue.map { String(format: "%.2f", $0) } ?? "—")
                    .font(.headline)
                Spacer()
                if let templateHash = point.templateHash {
                    Text("tpl: \(templateHash.prefix(8))…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func formatDate(_ isoDate: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoDate) else { return isoDate }
        let display = DateFormatter()
        display.dateStyle = .medium
        return display.string(from: date)
    }
}
