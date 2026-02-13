// RoundDetailView.swift
// Gambit Golf
//
// Completed round scorecard display

import SwiftUI
import GRDB

struct RoundDetailView: View {
    let roundId: Int64
    let dbQueue: DatabaseQueue

    @State private var round: RoundRecord?
    @State private var courseSnapshot: CourseSnapshotRecord?
    @State private var holes: [CourseHoleRecord] = []
    @State private var scores: [Int: Int] = [:] // holeNumber -> strokes

    // Share state
    @State private var isPublishing = false
    @State private var errorMessage: String?
    @State private var showPublishSuccess = false

    var body: some View {
        Group {
            if let course = courseSnapshot {
                scorecardView
                    .navigationTitle(course.courseName)
            } else {
                ProgressView()
                    .navigationTitle("Scorecard")
            }
        }
        .toolbar {
            if courseSnapshot != nil, !scores.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    shareMenu
                }
            }
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Posted!", isPresented: $showPublishSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your round has been posted to Nostr.")
        }
        .task { loadData() }
    }

    private var scorecardView: some View {
        List {
            if holes.count == 18 {
                nineHoleSection(title: "Front 9", holes: Array(holes.prefix(9)))
                nineHoleSection(title: "Back 9", holes: Array(holes.suffix(9)))
            } else {
                nineHoleSection(title: "Scorecard", holes: holes)
            }

            totalSection
        }
    }

    private func nineHoleSection(title: String, holes: [CourseHoleRecord]) -> some View {
        Section(title) {
            ForEach(holes, id: \.holeNumber) { hole in
                HStack {
                    Text("Hole \(hole.holeNumber)")
                        .frame(width: 60, alignment: .leading)

                    Text("Par \(hole.par)")
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .leading)

                    Spacer()

                    if let strokes = scores[hole.holeNumber] {
                        let diff = strokes - hole.par

                        HStack(spacing: 8) {
                            Text("\(strokes)")
                                .font(.headline)

                            if diff != 0 {
                                Text(diff > 0 ? "+\(diff)" : "\(diff)")
                                    .font(.caption)
                                    .foregroundStyle(diff > 0 ? .red : .green)
                            }
                        }
                    } else {
                        Text("-")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Subtotal for this nine
            let ninePar = holes.reduce(0) { $0 + $1.par }
            let nineStrokes = holes.reduce(0) { sum, hole in
                sum + (scores[hole.holeNumber] ?? 0)
            }
            let nineDiff = nineStrokes - ninePar

            HStack {
                Text("Subtotal")
                    .font(.headline)
                Spacer()
                HStack(spacing: 8) {
                    Text("\(nineStrokes)")
                        .font(.headline)
                    Text("(\(nineDiff > 0 ? "+" : "")\(nineDiff))")
                        .font(.caption)
                        .foregroundStyle(nineDiff > 0 ? .red : (nineDiff < 0 ? .green : .secondary))
                }
            }
        }
    }

    private var totalSection: some View {
        Section {
            HStack {
                Text("Total Par")
                Spacer()
                Text("\(totalPar)")
            }

            HStack {
                Text("Total Strokes")
                Spacer()
                Text("\(totalStrokes)")
                    .font(.headline)
            }

            HStack {
                Text("Score")
                Spacer()
                let diff = totalStrokes - totalPar
                Text(diff == 0 ? "Even" : (diff > 0 ? "+\(diff)" : "\(diff)"))
                    .font(.headline)
                    .foregroundStyle(diff > 0 ? .red : (diff < 0 ? .green : .primary))
            }
        }
    }

    private var totalPar: Int {
        holes.reduce(0) { $0 + $1.par }
    }

    private var totalStrokes: Int {
        holes.reduce(0) { sum, hole in
            sum + (scores[hole.holeNumber] ?? 0)
        }
    }

    // MARK: - Share

    private var shareMenu: some View {
        Menu {
            Button {
                Task { await publishToNostr() }
            } label: {
                Label(isPublishing ? "Posting..." : "Post to Nostr", systemImage: "paperplane")
            }
            .disabled(isPublishing)

            Button {
                copySummary()
            } label: {
                Label("Copy Summary", systemImage: "doc.on.doc")
            }
        } label: {
            if isPublishing {
                ProgressView()
            } else {
                Image(systemName: "square.and.arrow.up")
            }
        }
    }

    private func publishToNostr() async {
        guard let course = courseSnapshot else { return }

        isPublishing = true
        defer { isPublishing = false }

        do {
            let keyManager = try KeyManager.loadOrCreate()
            let keys = keyManager.signingKeys()
            let pubkey = try keys.publicKey().toHex()

            // Build NIP-101g initiation content
            let content = NIP101gEventBuilder.buildInitiationContent(
                snapshot: course,
                holes: holes
            )
            let courseHash = try NIP101gEventBuilder.computeCourseHash(content: content)
            let rulesHash = try NIP101gEventBuilder.computeRulesHash(content: content)

            let dateString = round?.roundDate ?? ISO8601DateFormatter().string(from: Date())

            // 1) Publish round initiation (kind 1501) — get back event ID
            let initiationBuilder = try NIP101gEventBuilder.buildInitiationEvent(
                content: content,
                courseHash: courseHash,
                rulesHash: rulesHash,
                playerPubkeys: [pubkey],
                date: dateString
            )
            let initiationEventId = try await NostrClient.publishEvent(
                keys: keys,
                builder: initiationBuilder
            )

            // 2) Publish final round record (kind 1502) — references initiation
            let scoreList = holes
                .sorted { $0.holeNumber < $1.holeNumber }
                .compactMap { hole -> (holeNumber: Int, strokes: Int)? in
                    guard let strokes = scores[hole.holeNumber] else { return nil }
                    return (holeNumber: hole.holeNumber, strokes: strokes)
                }
            let total = scoreList.reduce(0) { $0 + $1.strokes }

            let finalBuilder = try NIP101gEventBuilder.buildFinalRecordEvent(
                initiationEventId: initiationEventId,
                scores: scoreList,
                total: total,
                playerPubkeys: [pubkey],
                notes: nil
            )
            _ = try await NostrClient.publishEvent(
                keys: keys,
                builder: finalBuilder
            )

            showPublishSuccess = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func copySummary() {
        guard let course = courseSnapshot else { return }

        let text = RoundShareBuilder.summaryText(
            course: course.courseName,
            tees: course.teeSet,
            date: round?.roundDate ?? "",
            holes: holes,
            scores: scores
        )
        UIPasteboard.general.string = text
    }

    // MARK: - Data Loading

    private func loadData() {
        do {
            // Fetch round record — standalone read, no nesting
            let fetchedRound = try dbQueue.read { db in
                try Row.fetchOne(
                    db,
                    sql: "SELECT round_id, course_hash, round_date, created_at FROM rounds WHERE round_id = ?",
                    arguments: [roundId]
                )
            }

            guard let row = fetchedRound else { return }
            let courseHash: String = row["course_hash"]
            round = RoundRecord(
                roundId: row["round_id"],
                courseHash: courseHash,
                roundDate: row["round_date"],
                createdAt: row["created_at"]
            )

            // Sequential repo calls — each owns its own dbQueue.read
            let courseRepo = CourseSnapshotRepository(dbQueue: dbQueue)
            courseSnapshot = try courseRepo.fetchCourseSnapshot(byHash: courseHash)
            holes = try courseRepo.fetchHoles(forCourse: courseHash)

            let scoreRepo = HoleScoreRepository(dbQueue: dbQueue)
            let scoreRecords = try scoreRepo.fetchLatestScores(forRound: roundId)
            for score in scoreRecords {
                scores[score.holeNumber] = score.strokes
            }
        } catch {
            print("[Gambit] Failed to load round detail: \(error)")
        }
    }
}
