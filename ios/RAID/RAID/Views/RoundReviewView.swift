// RoundReviewView.swift
// RAID Golf
//
// Pre-finish review scorecard. Shown as a sheet before committing the round.
// Uses the classic scorecard grid. Lets the user inspect all scores and go back to correct mistakes.

import SwiftUI

struct RoundReviewView: View {
    var store: ActiveRoundStore
    let onFinish: DismissAction

    @Environment(\.dismiss) private var dismissSheet

    /// Player labels for the scorecard grid
    private var gridPlayerLabels: [Int: String] {
        if store.isMultiplayer && !store.multiDeviceMode {
            var labels: [Int: String] = [:]
            for player in store.players {
                labels[player.playerIndex] = store.playerDisplayLabel(for: player.playerIndex)
            }
            return labels
        } else {
            return [0: "You"]
        }
    }

    private var totalPar: Int {
        store.holes.reduce(0) { $0 + $1.par }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Scorecard grid
                    ScorecardGridView(
                        holes: store.holes,
                        scores: store.scores,
                        playerLabels: gridPlayerLabels
                    )
                    .padding(.horizontal, 8)

                    // Player summary
                    if store.isMultiplayer && !store.multiDeviceMode {
                        allPlayersSummary
                    } else {
                        soloSummary
                    }
                }
                .padding(.vertical, 8)
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

    // MARK: - Summary Sections

    private var allPlayersSummary: some View {
        VStack(spacing: 0) {
            ForEach(store.players.indices, id: \.self) { index in
                let playerScores = store.scores[index] ?? [:]
                let strokes = store.holes.reduce(0) { sum, hole in
                    sum + (playerScores[hole.holeNumber] ?? 0)
                }
                let diff = strokes - totalPar

                HStack {
                    Text(store.playerDisplayLabel(for: index))
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(strokes)")
                        .font(.headline.monospacedDigit())
                    let diffColor: Color = diff > 0 ? .scoreDouble : (diff < 0 ? .scoreEagle : .secondary)
                    Text(diff.scoreToParString)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(diffColor)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                if index < store.players.count - 1 {
                    Divider().padding(.horizontal)
                }
            }
        }
        .padding(.vertical, 4)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 8)
    }

    private var soloSummary: some View {
        let playerScores = store.scores[0] ?? [:]
        let totalStrokes = store.holes.reduce(0) { sum, hole in
            sum + (playerScores[hole.holeNumber] ?? 0)
        }
        let diff = totalStrokes - totalPar
        let diffColor: Color = diff > 0 ? .scoreDouble : (diff < 0 ? .scoreEagle : .primary)

        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Total")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(totalStrokes)")
                    .font(.title.weight(.bold).monospacedDigit())
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("Score")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(diff == 0 ? "Even" : diff.scoreToParString)
                    .font(.title.weight(.bold).monospacedDigit())
                    .foregroundStyle(diffColor)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 8)
    }
}
