// TrendsView.swift
// RAID Golf - iOS Port
//
// Phase 4B: Trends v1 (minimal UI)
// Phase 4C: Empty state keyed on session count

import SwiftUI
import GRDB

struct TrendsView: View {
    let dbQueue: DatabaseQueue

    @State private var selectedClub: String = "7i"
    @State private var selectedMetric: TrendMetric = .carry
    @State private var allShotsPoints: [TrendPoint] = []
    @State private var aOnlyPoints: [TrendPoint] = []
    @State private var hasSessions: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if !hasSessions {
                    ContentUnavailableView {
                        Label("No Trends Yet", systemImage: "chart.line.uptrend.xyaxis")
                    } description: {
                        Text("Import a session from the Sessions tab to see trends.")
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
                if aOnlyPoints.isEmpty {
                    Text("No trend data")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(aOnlyPoints, id: \.sessionId) { point in
                        TrendPointRow(point: point)
                    }
                }
            }
        }
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
