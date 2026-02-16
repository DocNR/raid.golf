// LiveScorecardSheet.swift
// RAID Golf
//
// Live scorecard view for multi-device rounds.
// Shows local player's scores alongside all other players from round_players.
// Remote scores populated via 30501 relay fetches.

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

    var body: some View {
        NavigationStack {
            List {
                Section {
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
                    }
                    .disabled(store.isFetchingRemoteScores)
                }

                Section("Scorecard") {
                    // Column headers
                    HStack(spacing: 12) {
                        Text("Hole")
                            .frame(width: 30, alignment: .leading)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("Par")
                            .frame(width: 50, alignment: .leading)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("You")
                            .frame(width: 40, alignment: .center)
                            .font(.caption2)
                            .fontWeight(.medium)
                        ForEach(otherPlayers, id: \.playerPubkey) { player in
                            Text(playerDisplayLabel(for: player.playerIndex))
                                .frame(width: 40, alignment: .center)
                                .font(.caption2)
                                .fontWeight(.medium)
                        }
                    }

                    ForEach(store.holes, id: \.holeNumber) { hole in
                        HStack(spacing: 12) {
                            Text("\(hole.holeNumber)")
                                .frame(width: 30, alignment: .leading)
                                .font(.headline)

                            Text("Par \(hole.par)")
                                .frame(width: 50, alignment: .leading)
                                .foregroundStyle(.secondary)
                                .font(.caption)

                            Spacer()

                            // My score
                            Text(myScores[hole.holeNumber].map { "\($0)" } ?? "-")
                                .frame(width: 40, alignment: .center)
                                .font(.headline)

                            // Other players' scores
                            ForEach(otherPlayers, id: \.playerPubkey) { player in
                                let pScores = store.remoteScores[player.playerPubkey] ?? [:]
                                Text(pScores[hole.holeNumber].map { "\($0)" } ?? "-")
                                    .frame(width: 40, alignment: .center)
                                    .font(.caption)
                                    .foregroundStyle(pScores[hole.holeNumber] != nil ? .primary : .secondary)
                            }
                        }
                    }
                }

                Section("Totals") {
                    HStack(spacing: 12) {
                        Text("Total")
                            .font(.headline)

                        Spacer()

                        // My total
                        VStack(spacing: 2) {
                            Text("\(myTotal)")
                                .font(.headline)
                            let myDiff = myTotal - totalPar
                            Text(myDiff == 0 ? "E" : (myDiff > 0 ? "+\(myDiff)" : "\(myDiff)"))
                                .font(.caption2)
                                .foregroundStyle(myDiff > 0 ? .red : (myDiff < 0 ? .green : .secondary))
                        }
                        .frame(width: 40, alignment: .center)

                        // Other players' totals
                        ForEach(otherPlayers, id: \.playerPubkey) { player in
                            let pScores = store.remoteScores[player.playerPubkey] ?? [:]
                            let total = pScores.values.reduce(0, +)
                            let diff = total - totalPar
                            VStack(spacing: 2) {
                                Text(pScores.isEmpty ? "-" : "\(total)")
                                    .font(.caption)
                                if !pScores.isEmpty {
                                    Text(diff == 0 ? "E" : (diff > 0 ? "+\(diff)" : "\(diff)"))
                                        .font(.caption2)
                                        .foregroundStyle(diff > 0 ? .red : (diff < 0 ? .green : .secondary))
                                }
                            }
                            .frame(width: 40, alignment: .center)
                        }
                    }
                }

                Section("Players") {
                    HStack {
                        Text("You")
                            .font(.headline)
                        Spacer()
                        Text("\(myScores.count)/\(store.holes.count) holes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(otherPlayers, id: \.playerPubkey) { player in
                        let pScores = store.remoteScores[player.playerPubkey] ?? [:]
                        HStack {
                            Text(playerDisplayLabel(for: player.playerIndex))
                                .font(.headline)
                            Spacer()
                            Text("\(pScores.count)/\(store.holes.count) holes")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
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
