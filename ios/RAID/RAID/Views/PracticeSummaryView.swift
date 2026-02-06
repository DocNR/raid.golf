// PracticeSummaryView.swift
// RAID Golf - iOS Port
//
// Phase 3.3: Minimal Practice Summary UI
//
// Purpose:
// - Display session summary with A/B/C breakdown
// - Show A-only averages
// - Compute classifications in-memory (no persistence)
//
// Phase 3.5: Wire classification with latest template selection

import SwiftUI
import GRDB

struct PracticeSummaryView: View {
    let sessionId: Int64
    let dbQueue: DatabaseQueue
    
    @State private var summary: SessionSummary?
    @State private var isLoading = true
    @State private var errorMessage: String?
    
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
            } else if let summary = summary {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Session header
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Practice Session")
                                .font(.title)
                                .fontWeight(.bold)
                            Text(formatDate(summary.sessionDate))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            if let location = summary.location {
                                Text(location)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Divider()
                        
                        // Club summaries
                        ForEach(summary.clubSummaries, id: \.club) { clubSummary in
                            ClubSummaryCard(clubSummary: clubSummary)
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
    }
    
    private func loadSession() async {
        do {
            let sessionRepo = SessionRepository(dbQueue: dbQueue)
            let shotRepo = ShotRepository(dbQueue: dbQueue)
            let templateRepo = TemplateRepository(dbQueue: dbQueue)
            
            guard let sessionRecord = try sessionRepo.fetchSession(byId: sessionId) else {
                errorMessage = "Session not found"
                isLoading = false
                return
            }
            
            // Fetch shots
            let shots = try shotRepo.fetchShots(forSession: sessionId)
            
            // Group by club
            let shotsByClub = Dictionary(grouping: shots, by: { $0.club })
            
            // Compute summaries for each club
            var clubSummaries: [ClubSummary] = []
            
            for (club, clubShots) in shotsByClub.sorted(by: { $0.key < $1.key }) {
                // Fetch latest template for club
                guard let templateRecord = try templateRepo.fetchLatestTemplate(forClub: club) else {
                    // No template for this club → show "no template" state
                    let clubSummary = ClubSummary(
                        club: club,
                        totalShots: clubShots.count,
                        aCount: nil,
                        bCount: nil,
                        cCount: nil,
                        aPercentage: nil,
                        avgCarry: nil,
                        avgBallSpeed: nil,
                        avgSpin: nil,
                        avgDescent: nil,
                        templateHash: nil
                    )
                    clubSummaries.append(clubSummary)
                    continue
                }
                
                // Decode KPITemplate from canonical_json
                guard let templateData = templateRecord.canonicalJSON.data(using: .utf8),
                      let kpiTemplate = try? JSONDecoder().decode(KPITemplate.self, from: templateData) else {
                    errorMessage = "Failed to decode template for \(club)"
                    isLoading = false
                    return
                }
                
                // Classify shots
                let classifications = try ShotClassifier.classify(clubShots, using: kpiTemplate)
                
                // Aggregate
                let aggregated = ShotClassifier.aggregate(classifications, shots: clubShots)
                
                // Debug log (integration check)
                print("✅ Club \(club): \(clubShots.count) shots, template \(templateRecord.hash.prefix(8)), A/B/C: \(aggregated.aCount)/\(aggregated.bCount)/\(aggregated.cCount)")
                
                // Verify counts sum to total
                assert(aggregated.aCount + aggregated.bCount + aggregated.cCount == aggregated.totalShots,
                       "A/B/C counts must sum to totalShots")
                
                let clubSummary = ClubSummary(
                    club: club,
                    totalShots: aggregated.totalShots,
                    aCount: aggregated.aCount,
                    bCount: aggregated.bCount,
                    cCount: aggregated.cCount,
                    aPercentage: aggregated.aPercentage,
                    avgCarry: aggregated.avgCarry,
                    avgBallSpeed: aggregated.avgBallSpeed,
                    avgSpin: aggregated.avgSpin,
                    avgDescent: aggregated.avgDescent,
                    templateHash: templateRecord.hash
                )
                clubSummaries.append(clubSummary)
            }
            
            summary = SessionSummary(
                sessionDate: sessionRecord.sessionDate,
                location: sessionRecord.location,
                clubSummaries: clubSummaries
            )
            isLoading = false
            
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
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

struct ClubSummaryCard: View {
    let clubSummary: ClubSummary
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Club header
            HStack {
                Text(clubSummary.club.uppercased())
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                Text("\(clubSummary.totalShots) shots")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Check if template exists
            if clubSummary.templateHash == nil {
                Text("⚠️ No template for this club")
                    .font(.caption)
                    .foregroundColor(.orange)
            } else if clubSummary.totalShots >= 5, let aCount = clubSummary.aCount, let bCount = clubSummary.bCount, let cCount = clubSummary.cCount {
                // A/B/C breakdown
                HStack(spacing: 16) {
                    GradeBox(grade: "A", count: aCount, color: .green)
                    GradeBox(grade: "B", count: bCount, color: .orange)
                    GradeBox(grade: "C", count: cCount, color: .red)
                }
                
                if let aPercentage = clubSummary.aPercentage {
                    Text("A-shots: \(String(format: "%.1f", aPercentage))%")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                // A-only averages
                if aCount > 0 {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("A-Shot Averages")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let avgCarry = clubSummary.avgCarry {
                            MetricRow(label: "Carry", value: String(format: "%.1f yds", avgCarry))
                        }
                        if let avgBallSpeed = clubSummary.avgBallSpeed {
                            MetricRow(label: "Ball Speed", value: String(format: "%.1f mph", avgBallSpeed))
                        }
                        if let avgSpin = clubSummary.avgSpin {
                            MetricRow(label: "Spin", value: String(format: "%.0f rpm", avgSpin))
                        }
                        if let avgDescent = clubSummary.avgDescent {
                            MetricRow(label: "Descent", value: String(format: "%.1f°", avgDescent))
                        }
                    }
                }
            } else {
                Text("⚠️ Insufficient data (< 5 shots)")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

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

struct SessionSummary {
    let sessionDate: String
    let location: String?
    let clubSummaries: [ClubSummary]
}

struct ClubSummary {
    let club: String
    let totalShots: Int
    let aCount: Int?
    let bCount: Int?
    let cCount: Int?
    let aPercentage: Double?
    let avgCarry: Double?
    let avgBallSpeed: Double?
    let avgSpin: Double?
    let avgDescent: Double?
    let templateHash: String?
}
