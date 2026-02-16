// PracticeSummaryView.swift
// RAID Golf
//
// Session detail view with persisted analysis
//
// Purpose:
// - Display session summary using persisted analyses from club_subsessions
// - Show multiple analyses per club (different templates)
// - Support re-analysis with active template
//
// Design:
// - No on-the-fly classification (use persisted data)
// - Multiple analyses per club = multiple cards
// - "Active" badge for current active template
// - "Analyze" button for clubs with no analysis

import SwiftUI
import GRDB

struct PracticeSummaryView: View {
    let sessionId: Int64
    let dbQueue: DatabaseQueue

    @State private var sessionInfo: SessionInfo?
    @State private var clubAnalyses: [String: [AnalysisInfo]] = [:]
    @State private var clubsWithoutAnalysis: Set<String> = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isAnalyzing = false
    @State private var analyzeError: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading session...")
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    Text("Error Loading Session")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else if let info = sessionInfo {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Session header
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Practice Session")
                                .font(.title)
                                .fontWeight(.bold)
                            Text(formatDate(info.sessionDate))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            if let location = info.location {
                                Text(location)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Divider()

                        // Club analyses grouped by club
                        let sortedClubs = Array(clubAnalyses.keys).sorted()
                        ForEach(sortedClubs, id: \.self) { club in
                            if let analyses = clubAnalyses[club] {
                                VStack(alignment: .leading, spacing: 12) {
                                    // Club header
                                    Text(club.uppercased())
                                        .font(.headline)
                                        .fontWeight(.bold)

                                    // Show all analyses for this club
                                    ForEach(analyses, id: \.subsessionId) { analysis in
                                        AnalysisCard(analysis: analysis)
                                    }
                                }
                            }
                        }

                        // Clubs without analysis
                        ForEach(Array(clubsWithoutAnalysis).sorted(), id: \.self) { club in
                            UnanalyzedClubCard(
                                club: club,
                                shotCount: info.clubShotCounts[club] ?? 0,
                                isAnalyzing: isAnalyzing
                            ) {
                                analyzeClub(club)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Session Summary")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadSession()
        }
        .alert("Error", isPresented: Binding(
            get: { analyzeError != nil },
            set: { if !$0 { analyzeError = nil } }
        )) {
            Button("OK") { analyzeError = nil }
        } message: {
            Text(analyzeError ?? "")
        }
    }

    private func loadSession() async {
        do {
            let sessionRepo = SessionRepository(dbQueue: dbQueue)
            let shotRepo = ShotRepository(dbQueue: dbQueue)
            let subsessionRepo = SubsessionRepository(dbQueue: dbQueue)
            let prefsRepo = TemplatePreferencesRepository(dbQueue: dbQueue)

            guard let sessionRecord = try sessionRepo.fetchSession(byId: sessionId) else {
                errorMessage = "Session not found"
                isLoading = false
                return
            }

            // Fetch all shots for the session
            let allShots = try shotRepo.fetchShots(forSession: sessionId)
            let clubShotCounts = Dictionary(grouping: allShots, by: { $0.club })
                .mapValues { $0.count }

            // Fetch all persisted subsessions
            let subsessions = try subsessionRepo.fetchSubsessions(forSession: sessionId)

            // Get active template hashes for each club
            var activeTemplateHashes: [String: String] = [:]
            for club in clubShotCounts.keys {
                if let activeTemplate = try prefsRepo.fetchActiveTemplate(forClub: club) {
                    activeTemplateHashes[club] = activeTemplate.hash
                }
            }

            // Group subsessions by club and fetch template preferences
            var clubAnalysesDict: [String: [AnalysisInfo]] = [:]
            var analyzedClubs = Set<String>()

            for subsession in subsessions {
                analyzedClubs.insert(subsession.club)

                // Get template name (display_name or fallback)
                let pref = try? prefsRepo.fetchPreference(forHash: subsession.kpiTemplateHash)
                let templateName: String
                if let displayName = pref?.displayName, !displayName.isEmpty {
                    templateName = displayName
                } else {
                    let shortHash = String(subsession.kpiTemplateHash.prefix(8))
                    templateName = "\(subsession.club) \(shortHash)"
                }

                let isActive = activeTemplateHashes[subsession.club] == subsession.kpiTemplateHash

                let analysis = AnalysisInfo(
                    subsessionId: subsession.subsessionId,
                    club: subsession.club,
                    templateName: templateName,
                    templateHash: subsession.kpiTemplateHash,
                    shotCount: subsession.shotCount,
                    validityStatus: subsession.validityStatus,
                    aCount: subsession.aCount,
                    bCount: subsession.bCount,
                    cCount: subsession.cCount,
                    aPercentage: subsession.aPercentage,
                    avgCarry: subsession.avgCarry,
                    avgBallSpeed: subsession.avgBallSpeed,
                    avgSpin: subsession.avgSpin,
                    avgDescent: subsession.avgDescent,
                    analyzedAt: subsession.analyzedAt,
                    isActive: isActive
                )

                clubAnalysesDict[subsession.club, default: []].append(analysis)
            }

            // Identify clubs without analysis
            let allClubs = Set(clubShotCounts.keys)
            let unanalyzedClubs = allClubs.subtracting(analyzedClubs)

            sessionInfo = SessionInfo(
                sessionDate: sessionRecord.sessionDate,
                location: sessionRecord.location,
                clubShotCounts: clubShotCounts
            )
            clubAnalyses = clubAnalysesDict
            clubsWithoutAnalysis = unanalyzedClubs
            isLoading = false

        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func analyzeClub(_ club: String) {
        guard !isAnalyzing else { return }
        isAnalyzing = true

        Task {
            do {
                let shotRepo = ShotRepository(dbQueue: dbQueue)
                let templateRepo = TemplateRepository(dbQueue: dbQueue)
                let prefsRepo = TemplatePreferencesRepository(dbQueue: dbQueue)
                let subsessionRepo = SubsessionRepository(dbQueue: dbQueue)

                // Fetch shots for this club
                let allShots = try shotRepo.fetchShots(forSession: sessionId)
                let clubShots = allShots.filter { $0.club == club }

                guard !clubShots.isEmpty else {
                    isAnalyzing = false
                    return
                }

                // Get active template (with fallback to latest)
                guard let templateRecord = try prefsRepo.fetchActiveTemplate(forClub: club)
                    ?? templateRepo.fetchLatestTemplate(forClub: club),
                      let templateData = templateRecord.canonicalJSON.data(using: .utf8) else {
                    isAnalyzing = false
                    return
                }

                let template = try JSONDecoder().decode(KPITemplate.self, from: templateData)

                // Analyze and persist
                try subsessionRepo.analyzeSessionClub(
                    sessionId: sessionId,
                    club: club,
                    shots: clubShots,
                    template: template,
                    templateHash: templateRecord.hash
                )

                // Reload view
                isAnalyzing = false
                await loadSession()

            } catch {
                print("[RAID] Analysis failed: \(error)")
                analyzeError = "Analysis failed. Please try again."
                isAnalyzing = false
            }
        }
    }

    private func formatDate(_ isoDate: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: isoDate) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        return isoDate
    }
}

// MARK: - Analysis Card

struct AnalysisCard: View {
    let analysis: AnalysisInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Template header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(analysis.templateName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(String(analysis.templateHash.prefix(8)))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospaced()
                }
                Spacer()
                if analysis.isActive {
                    Text("ACTIVE")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue)
                        .cornerRadius(4)
                }
            }

            // Shot count and validity status
            HStack {
                Text("\(analysis.shotCount) shots")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if analysis.validityStatus == "invalid_insufficient_data" {
                    Text("Insufficient data (< 5 shots)")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else if analysis.validityStatus == "valid_low_sample_warning" {
                    Text("Low sample warning (< 15 shots)")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            // A/B/C breakdown (if valid)
            if analysis.validityStatus != "invalid_insufficient_data" {
                HStack(spacing: 16) {
                    GradeBox(grade: "A", count: analysis.aCount, color: .green)
                    GradeBox(grade: "B", count: analysis.bCount, color: .orange)
                    GradeBox(grade: "C", count: analysis.cCount, color: .red)
                }

                if let aPercentage = analysis.aPercentage {
                    Text("A-shots: \(String(format: "%.1f", aPercentage))%")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                // A-only averages
                if analysis.aCount > 0 {
                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("A-Shot Averages")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if let avgCarry = analysis.avgCarry {
                            MetricRow(label: "Carry", value: String(format: "%.1f yds", avgCarry))
                        }
                        if let avgBallSpeed = analysis.avgBallSpeed {
                            MetricRow(label: "Ball Speed", value: String(format: "%.1f mph", avgBallSpeed))
                        }
                        if let avgSpin = analysis.avgSpin {
                            MetricRow(label: "Spin", value: String(format: "%.0f rpm", avgSpin))
                        }
                        if let avgDescent = analysis.avgDescent {
                            MetricRow(label: "Descent", value: String(format: "%.1f°", avgDescent))
                        }
                    }
                }
            }

            // Analyzed timestamp
            Text("Analyzed: \(formatDate(analysis.analyzedAt))")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func formatDate(_ isoDate: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: isoDate) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .short
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        return isoDate
    }
}

// MARK: - Unanalyzed Club Card

struct UnanalyzedClubCard: View {
    let club: String
    let shotCount: Int
    let isAnalyzing: Bool
    let onAnalyze: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Club header
            HStack {
                Text(club.uppercased())
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                Text("\(shotCount) shots")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Text("Not yet analyzed")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button(action: onAnalyze) {
                if isAnalyzing {
                    HStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                        Text("Analyzing...")
                    }
                } else {
                    Text("Analyze")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isAnalyzing)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Supporting Components (reused from original)

struct GradeBox: View {
    let grade: String
    let count: Int
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(grade)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text("\(count)")
                .font(.title3)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

struct MetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Data Models

struct SessionInfo {
    let sessionDate: String
    let location: String?
    let clubShotCounts: [String: Int]
}

struct AnalysisInfo {
    let subsessionId: Int64
    let club: String
    let templateName: String
    let templateHash: String
    let shotCount: Int
    let validityStatus: String
    let aCount: Int
    let bCount: Int
    let cCount: Int
    let aPercentage: Double?
    let avgCarry: Double?
    let avgBallSpeed: Double?
    let avgSpin: Double?
    let avgDescent: Double?
    let analyzedAt: String
    let isActive: Bool
}
