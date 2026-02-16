// RoundReviewView.swift
// RAID Golf
//
// Pre-finish review scorecard. Shown as a sheet before committing the round.
// Lets the user inspect all scores and go back to correct mistakes.

import SwiftUI

struct RoundReviewView: View {
    var store: ActiveRoundStore
    let onFinish: DismissAction

    @Environment(\.dismiss) private var dismissSheet
    @State private var selectedPlayerIndex: Int = 0

    private var scores: [Int: Int] {
        store.scores[selectedPlayerIndex] ?? [:]
    }

    var body: some View {
        NavigationStack {
            List {
                if store.isMultiplayer && !store.multiDeviceMode {
                    Section {
                        Picker("Player", selection: $selectedPlayerIndex) {
                            ForEach(store.players.indices, id: \.self) { index in
                                Text(store.playerDisplayLabel(for: index)).tag(index)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                if store.holes.count == 18 {
                    nineHoleSection(title: "Front 9", holes: Array(store.holes.prefix(9)))
                    nineHoleSection(title: "Back 9", holes: Array(store.holes.suffix(9)))
                } else {
                    nineHoleSection(title: "Scorecard", holes: store.holes)
                }

                totalSection

                if store.isMultiplayer && !store.multiDeviceMode {
                    allPlayersSummary
                }
            }
            .navigationTitle("Review Round")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Go Back") {
                        dismissSheet()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    store.finishRound {
                        dismissSheet()
                        onFinish()
                    }
                } label: {
                    Text("Finish Round")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
                .background(.bar)
            }
        }
    }

    // MARK: - Scorecard Sections

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

    private var allPlayersSummary: some View {
        Section("All Players") {
            ForEach(store.players.indices, id: \.self) { index in
                let playerScores = store.scores[index] ?? [:]
                let strokes = store.holes.reduce(0) { sum, hole in
                    sum + (playerScores[hole.holeNumber] ?? 0)
                }
                let diff = strokes - totalPar

                HStack {
                    Text(store.playerDisplayLabel(for: index))
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(strokes)")
                        .font(.headline)
                    Text("(\(diff > 0 ? "+" : "")\(diff))")
                        .font(.caption)
                        .foregroundStyle(diff > 0 ? .red : (diff < 0 ? .green : .secondary))
                }
            }
        }
    }

    // MARK: - Computed

    private var totalPar: Int {
        store.holes.reduce(0) { $0 + $1.par }
    }

    private var totalStrokes: Int {
        store.holes.reduce(0) { sum, hole in
            sum + (scores[hole.holeNumber] ?? 0)
        }
    }
}
