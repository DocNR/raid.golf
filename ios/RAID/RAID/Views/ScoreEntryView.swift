// ScoreEntryView.swift
// RAID Golf
//
// Hole-by-hole score entry with hybrid layout:
// - Mini scorecard grid at top (tappable for jump-to-hole)
// - Focused hole panel below for score entry (+/- buttons)
// Thin rendering shell — all state and persistence lives in ActiveRoundStore.

import SwiftUI
import GRDB

struct ScoreEntryView: View {
    var store: ActiveRoundStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.nostrService) private var nostrService
    @State private var showScorecard = false

    /// Player labels for the scorecard grid
    private var playerLabels: [Int: String] {
        if store.multiDeviceMode {
            var labels: [Int: String] = [0: "You"]
            for player in store.players where player.playerIndex > 0 {
                labels[player.playerIndex] = store.playerDisplayLabel(for: player.playerIndex)
            }
            return labels
        } else if store.isMultiplayer {
            var labels: [Int: String] = [:]
            for player in store.players {
                labels[player.playerIndex] = store.playerDisplayLabel(for: player.playerIndex)
            }
            return labels
        } else {
            return [0: "You"]
        }
    }

    /// Merge remote scores into the scores dict for display
    private var displayScores: [Int: [Int: Int]] {
        var merged = store.scores
        if store.multiDeviceMode {
            // Add remote players' scores
            for player in store.players where player.playerIndex > 0 {
                if let remoteScores = store.remoteScores[player.playerPubkey] {
                    merged[player.playerIndex] = remoteScores
                }
            }
        }
        return merged
    }

    /// Remote player indices (for dimmed treatment in grid)
    private var remoteIndices: Set<Int> {
        guard store.multiDeviceMode else { return [] }
        return Set(store.players.filter { $0.playerIndex > 0 }.map(\.playerIndex))
    }

    var body: some View {
        VStack(spacing: 0) {
            if !store.isLoaded {
                Spacer()
                ProgressView()
                Spacer()
            } else if let currentHole = store.currentHole {
                // Mini scorecard grid (tappable)
                miniScorecardSection

                Divider()

                // Player picker (same-device multiplayer only)
                if store.isMultiplayer && !store.multiDeviceMode {
                    playerPicker
                }

                // Focused hole panel
                focusedHolePanel(hole: currentHole)

                Spacer(minLength: 0)

                // Finish gating feedback
                if store.isOnLastHole, let reason = store.finishBlockedReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                }

                // Navigation buttons
                navigationButtons
            }
        }
        .navigationTitle("Scoring")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if store.multiDeviceMode {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showScorecard = true
                    } label: {
                        Image(systemName: "list.number")
                    }
                }
                if store.inviteNevent != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            store.showInviteSheet = true
                        } label: {
                            Image(systemName: "qrcode")
                        }
                    }
                }
            }
        }
        .task {
            await store.loadInviteNevent()
            if store.isMultiplayer && store.playerProfiles.isEmpty {
                let pubkeys = store.players.map { $0.playerPubkey }
                if let profiles = try? await nostrService.resolveProfiles(pubkeyHexes: pubkeys) {
                    store.playerProfiles = profiles
                }
            }
        }
        .sheet(isPresented: Bindable(store).showInviteSheet) {
            if let nevent = store.inviteNevent {
                RoundInviteSheet(nevent: nevent)
            }
        }
        .sheet(isPresented: Bindable(store).showReviewSheet) {
            RoundReviewView(store: store, onFinish: dismiss)
        }
        .sheet(isPresented: $showScorecard) {
            LiveScorecardSheet(store: store)
        }
        .alert("Error", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    // MARK: - Mini Scorecard

    private var miniScorecardSection: some View {
        ScorecardGridView(
            holes: store.holes,
            scores: displayScores,
            playerLabels: playerLabels,
            currentHoleIndex: store.currentHoleIndex,
            currentPlayerIndex: store.currentPlayerIndex,
            onHoleTap: { holeIndex in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                store.jumpToHole(index: holeIndex)
            },
            remotePlayerIndices: remoteIndices
        )
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    // MARK: - Player Picker

    private var playerPicker: some View {
        Picker("Player", selection: Binding(
            get: { store.currentPlayerIndex },
            set: { store.switchPlayer(to: $0) }
        )) {
            ForEach(store.players.indices, id: \.self) { index in
                Text(store.playerDisplayLabel(for: index)).tag(index)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Focused Hole Panel

    private func focusedHolePanel(hole: CourseHoleRecord) -> some View {
        VStack(spacing: 12) {
            // Hole number + par
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Hole \(hole.holeNumber)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))

                Text("Par \(hole.par)")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Spacer()

                // Score-to-par badge for this hole
                if let strokes = store.scores[store.currentPlayerIndex]?[hole.holeNumber] {
                    let classification = ScoreRelativeToPar(strokes: strokes, par: hole.par)
                    if classification != .par {
                        Text(classification.accessibilityLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(classification.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(classification.color.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal)

            // Score entry: - [score] +
            HStack(spacing: 0) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    store.decrementStrokes()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 44))
                        .frame(width: ScorecardLayout.minTapTarget, height: ScorecardLayout.minTapTarget)
                }
                .disabled(store.currentStrokes <= 1)

                Spacer()

                // Large score with notation
                ScoreNotationView(
                    strokes: store.currentStrokes,
                    par: hole.par,
                    size: 80
                )

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    store.incrementStrokes()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 44))
                        .frame(width: ScorecardLayout.minTapTarget, height: ScorecardLayout.minTapTarget)
                }
                .disabled(store.currentStrokes >= 20)
            }
            .padding(.horizontal, 32)

            // Running total
            HStack(spacing: 8) {
                Text("Total: \(store.totalStrokes)")
                    .font(.subheadline.weight(.medium))

                let diff = store.totalStrokes - store.totalPar
                Text(diff.scoreToParString)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(diff > 0 ? Color.scoreDouble : (diff < 0 ? Color.scoreEagle : .secondary))

                if store.isMultiplayer {
                    Spacer()

                    // Per-player progress
                    ForEach(Array(store.playerProgress.enumerated()), id: \.offset) { _, progress in
                        HStack(spacing: 2) {
                            Text(progress.label)
                                .font(.caption2.weight(.medium))
                            Text("\(progress.scored)/\(progress.total)")
                                .font(.caption2)
                                .foregroundStyle(progress.scored >= progress.total ? .green : .secondary)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
        }
        .padding(.top, 8)
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack(spacing: 16) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                store.retreatHole()
            } label: {
                Label("Previous", systemImage: "chevron.left")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(store.isOnFirstPosition)

            if store.isOnLastHole {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    store.requestFinish()
                } label: {
                    Label("Finish Round", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.isFinishEnabled)
            } else {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    store.advanceHole()
                } label: {
                    HStack {
                        Text("Next")
                        Image(systemName: "chevron.right")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
    }
}
