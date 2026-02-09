// RoundDetailView.swift
// RAID Golf - iOS Port
//
// Scorecard: Completed round scorecard display

import SwiftUI
import GRDB

struct RoundDetailView: View {
    let roundId: Int64
    let dbQueue: DatabaseQueue

    @State private var round: RoundRecord?
    @State private var courseSnapshot: CourseSnapshotRecord?
    @State private var holes: [CourseHoleRecord] = []
    @State private var scores: [Int: Int] = [:] // holeNumber -> strokes

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

    private func loadData() {
        do {
            // Fetch courseHash — standalone read, no nesting
            let courseHashValue = try dbQueue.read { db in
                try String.fetchOne(
                    db,
                    sql: "SELECT course_hash FROM rounds WHERE round_id = ?",
                    arguments: [roundId]
                )
            }

            guard let courseHash = courseHashValue else { return }

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
            print("[RAID] Failed to load round detail: \(error)")
        }
    }
}
