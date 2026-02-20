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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Split scorecard (front nine / back nine / totals)
                    ScorecardSplitView(
                        holes: store.holes,
                        scores: store.scores,
                        playerLabels: gridPlayerLabels
                    )
                    .padding(.horizontal, 8)

                }
                .padding(.vertical, 8)
            }
            .navigationTitle("Finalize Round")
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
                    Text("Finalize Round")
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

}
