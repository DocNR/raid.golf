// LiveScorecardSheet.swift
// RAID Golf
//
// Live scorecard view for multi-device rounds.
// Shows local player's scores alongside all other players from round_players.
// Remote scores populated via 30501 relay fetches.
// Uses the classic scorecard grid layout.

import SwiftUI

struct LiveScorecardSheet: View {
    var store: ActiveRoundStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.nostrService) private var nostrService
    @State private var lastRefreshed: Date?
    @State private var playerProfiles: [String: NostrProfile] = [:]

    private var myScores: [Int: Int] {
        store.scores[0] ?? [:]
    }

    /// Other players in this round (index > 0)
    private var otherPlayers: [RoundPlayerRecord] {
        store.players.filter { $0.playerIndex > 0 }
    }

    private var totalPar: Int {
        store.holes.reduce(0) { $0 + $1.par }
    }

    private var myTotal: Int {
        myScores.values.reduce(0, +)
    }

    /// All scores merged (local + remote) for the grid
    private var mergedScores: [Int: [Int: Int]] {
        var merged: [Int: [Int: Int]] = [0: myScores]
        for player in otherPlayers {
            if let remoteScores = store.remoteScores[player.playerPubkey] {
                merged[player.playerIndex] = remoteScores
            }
        }
        return merged
    }

    /// Player labels for the grid
    private var gridPlayerLabels: [Int: String] {
        var labels: [Int: String] = [0: "You"]
        for player in otherPlayers {
            labels[player.playerIndex] = playerDisplayLabel(for: player.playerIndex)
        }
        return labels
    }

    /// Remote player indices for dimmed treatment
    private var remotePlayerIndices: Set<Int> {
        Set(otherPlayers.map(\.playerIndex))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Refresh button
                    Button {
                        Task {
                            await store.fetchRemoteScores()
                            lastRefreshed = Date()
                        }
                    } label: {
                        HStack {
                            Label("Refresh Scores", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if store.isFetchingRemoteScores {
                                ProgressView()
                            } else if lastRefreshed != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                    }
                    .disabled(store.isFetchingRemoteScores)

                    // Classic scorecard grid
                    ScorecardGridView(
                        holes: store.holes,
                        scores: mergedScores,
                        playerLabels: gridPlayerLabels,
                        currentHoleIndex: store.currentHoleIndex,
                        currentPlayerIndex: 0,
                        remotePlayerIndices: remotePlayerIndices
                    )
                    .padding(.horizontal, 8)

                    // Player progress section
                    VStack(spacing: 0) {
                        HStack {
                            Text("You")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text("\(myScores.count)/\(store.holes.count) holes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !myScores.isEmpty {
                                let diff = myTotal - totalPar
                                Text(diff.scoreToParString)
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(diff > 0 ? Color.scoreDouble : (diff < 0 ? Color.scoreEagle : .secondary))
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)

                        ForEach(otherPlayers, id: \.playerPubkey) { player in
                            Divider().padding(.horizontal)

                            let pScores = store.remoteScores[player.playerPubkey] ?? [:]
                            let total = pScores.values.reduce(0, +)
                            let diff = total - totalPar

                            HStack {
                                Text(playerDisplayLabel(for: player.playerIndex))
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                                Text("\(pScores.count)/\(store.holes.count) holes")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !pScores.isEmpty {
                                    Text(diff.scoreToParString)
                                        .font(.caption.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(diff > 0 ? Color.scoreDouble : (diff < 0 ? Color.scoreEagle : .secondary))
                                }
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        }
                    }
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 8)
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("Live Scorecard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                if !store.players.isEmpty && playerProfiles.isEmpty {
                    let pubkeys = store.players.map { $0.playerPubkey }
                    if let profiles = try? await nostrService.resolveProfiles(pubkeyHexes: pubkeys) {
                        playerProfiles = profiles
                    }
                }
            }
        }
    }

    private func playerDisplayLabel(for index: Int) -> String {
        if index == 0 { return "You" }
        guard index < store.players.count else { return "P\(index + 1)" }
        return playerProfiles[store.players[index].playerPubkey]?.displayLabel ?? "P\(index + 1)"
    }
}
