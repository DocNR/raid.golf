// CreateRoundView.swift
// RAID Golf - iOS Port
//
// Scorecard: Create new round form

import SwiftUI
import GRDB

struct CreateRoundView: View {
    let dbQueue: DatabaseQueue
    let onRoundCreated: (Int64, String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var courseName = ""
    @State private var teeSet = ""
    @State private var holeSelection: HoleSelection = .eighteen
    @State private var pars: [Int] = Array(repeating: 4, count: 18)
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Course Details") {
                    TextField("Course Name", text: $courseName)
                    TextField("Tee Set", text: $teeSet)
                    Picker("Holes", selection: $holeSelection) {
                        Text("Front 9").tag(HoleSelection.front9)
                        Text("Back 9").tag(HoleSelection.back9)
                        Text("18").tag(HoleSelection.eighteen)
                    }
                    .onChange(of: holeSelection) { _, newValue in
                        adjustParsArray(to: newValue.holeCount)
                    }
                }

                Section("Par for Each Hole") {
                    ForEach(0..<holeSelection.holeCount, id: \.self) { index in
                        let holeNumber = holeSelection.startingHole + index
                        HStack {
                            Text("Hole \(holeNumber)")
                                .frame(width: 80, alignment: .leading)
                            Spacer()
                            Stepper(
                                value: Binding(
                                    get: { pars[index] },
                                    set: { pars[index] = $0 }
                                ),
                                in: 3...5
                            ) {
                                Text("Par \(pars[index])")
                                    .frame(width: 60, alignment: .trailing)
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Round")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isCreating)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Start Round") {
                        startRound()
                    }
                    .disabled(courseName.isEmpty || teeSet.isEmpty || isCreating)
                }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
            }
        }
    }

    private func adjustParsArray(to newCount: Int) {
        if pars.count < newCount {
            pars.append(contentsOf: Array(repeating: 4, count: newCount - pars.count))
        } else if pars.count > newCount {
            pars = Array(pars.prefix(newCount))
        }
    }

    private func startRound() {
        isCreating = true

        do {
            let startHole = holeSelection.startingHole
            let holes = (0..<holeSelection.holeCount).map { index in
                HoleDefinition(holeNumber: startHole + index, par: pars[index])
            }

            let courseInput = CourseSnapshotInput(
                courseName: courseName,
                teeSet: teeSet,
                holes: holes
            )
            let courseRepo = CourseSnapshotRepository(dbQueue: dbQueue)
            let courseSnapshot = try courseRepo.insertCourseSnapshot(courseInput)

            let roundDate = ISO8601DateFormatter().string(from: Date())
            let roundRepo = RoundRepository(dbQueue: dbQueue)
            let round = try roundRepo.createRound(
                courseHash: courseSnapshot.courseHash,
                roundDate: roundDate
            )

            onRoundCreated(round.roundId, courseSnapshot.courseHash)

        } catch {
            isCreating = false
            errorMessage = error.localizedDescription
        }
    }
}

private enum HoleSelection: Hashable {
    case front9
    case back9
    case eighteen

    var holeCount: Int {
        switch self {
        case .front9, .back9: return 9
        case .eighteen: return 18
        }
    }

    var startingHole: Int {
        switch self {
        case .front9: return 1
        case .back9: return 10
        case .eighteen: return 1
        }
    }
}
