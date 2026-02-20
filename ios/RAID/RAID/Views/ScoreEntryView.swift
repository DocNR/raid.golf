// ScoreEntryView.swift
// RAID Golf
//
// Hole-by-hole score entry with hybrid layout (Layout B):
// - MiniScorecardView at top (compact strip, tappable for jump-to-hole, auto-scrolls)
// - Focused hole panel below for score entry (+/- buttons)
// Thin rendering shell — all state and persistence lives in ActiveRoundStore.

import SwiftUI
import GRDB

struct ScoreEntryView: View {
    var store: ActiveRoundStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.nostrService) private var nostrService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showScorecard = false

    /// Current player's scores for the mini card (shows only persisted scores, not default par)
    private var currentPlayerScores: [Int: Int] {
        store.scores[store.currentPlayerIndex] ?? [:]
    }

    /// Use inline ScorecardGridView (all players) instead of MiniScorecardView for
    /// multi-device rounds with ≤ 4 players. Larger groups fall back to the sheet.
    private var useInlineGrid: Bool {
        store.multiDeviceMode && store.players.count <= 4
    }

    /// Merged scores for the inline grid: local player (index 0) + remote players.
    private var inlineGridScores: [Int: [Int: Int]] {
        var merged: [Int: [Int: Int]] = [0: store.scores[0] ?? [:]]
        for player in store.players where player.playerIndex > 0 {
            if let remote = store.remoteScores[player.playerPubkey] {
                merged[player.playerIndex] = remote
            }
        }
        return merged
    }

    /// Player label map for the inline grid.
    private var inlineGridPlayerLabels: [Int: String] {
        var labels: [Int: String] = [0: "You"]
        for player in store.players where player.playerIndex > 0 {
            labels[player.playerIndex] = store.playerDisplayLabel(for: player.playerIndex)
        }
        return labels
    }

    /// Remote player indices for dimmed italic treatment in the inline grid.
    private var inlineRemotePlayerIndices: Set<Int> {
        Set(store.players.filter { $0.playerIndex > 0 }.map(\.playerIndex))
    }

    var body: some View {
        VStack(spacing: 0) {
            if !store.isLoaded {
                Spacer()
                ProgressView()
                Spacer()
            } else if let currentHole = store.currentHole {
                // Scorecard strip — inline grid for multi-device ≤4 players, mini strip otherwise
                if useInlineGrid {
                    ScorecardGridView(
                        holes: store.holes,
                        scores: inlineGridScores,
                        playerLabels: inlineGridPlayerLabels,
                        currentHoleIndex: store.currentHoleIndex,
                        currentPlayerIndex: 0,
                        onHoleTap: { holeIndex in
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            store.jumpToHole(index: holeIndex)
                        },
                        remotePlayerIndices: inlineRemotePlayerIndices
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                } else {
                    MiniScorecardView(
                        holes: store.holes,
                        scores: currentPlayerScores,
                        currentHoleIndex: store.currentHoleIndex,
                        onHoleTap: { holeIndex in
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            store.jumpToHole(index: holeIndex)
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                // Player picker (same-device multiplayer only)
                if store.isMultiplayer && !store.multiDeviceMode {
                    playerPicker
                }

                Spacer()

                // Focused hole panel
                focusedHolePanel(hole: currentHole)

                Spacer()

                // Progress row
                progressRow


                // Navigation buttons
                navigationButtons
            }
        }
        .navigationTitle("Scoring")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if store.multiDeviceMode {
                // Sheet button only needed when player count exceeds the inline grid threshold
                if store.players.count > 4 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showScorecard = true
                        } label: {
                            Image(systemName: "list.number")
                        }
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
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - Focused Hole Panel

    private func focusedHolePanel(hole: CourseHoleRecord) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                // Hole identity
                Text("Hole \(hole.holeNumber)")
                    .font(.system(size: ScorecardLayout.focusedHoleNumberSize, weight: .bold, design: .rounded))

                HStack(spacing: 8) {
                    Text("Par \(hole.par)")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    // Score-to-par badge
                    let classification = ScoreRelativeToPar(strokes: store.currentStrokes, par: hole.par)
                    if classification != .par {
                        Text(classification.accessibilityLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(classification.color)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(classification.color.opacity(0.12))
                            .clipShape(Capsule())
                            .accessibilityLabel("Score to par: \(classification.accessibilityLabel)")
                    }
                }
            }
            .padding(.top, 16)

            // Score stepper
            HStack(spacing: 0) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    store.decrementStrokes()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 44))
                        .frame(width: ScorecardLayout.minTapTarget, height: ScorecardLayout.minTapTarget)
                        .opacity(store.currentHoleConfirmed ? 1.0 : 0.25)
                }
                .disabled(store.currentStrokes <= 1)
                .accessibilityLabel("Decrease strokes")

                Spacer()

                scoreDisplay(hole: hole)

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    store.incrementStrokes()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 44))
                        .frame(width: ScorecardLayout.minTapTarget, height: ScorecardLayout.minTapTarget)
                        .opacity(store.currentHoleConfirmed ? 1.0 : 0.25)
                }
                .disabled(store.currentStrokes >= 20)
                .accessibilityLabel("Increase strokes")
            }
            .padding(.horizontal, 40)
        }
    }

    // MARK: - Score Display

    /// Large stroke-count number. Dimmed with a dashed border when unconfirmed;
    /// tapping it confirms the hole at par and activates the +/- controls.
    @ViewBuilder
    private func scoreDisplay(hole: CourseHoleRecord) -> some View {
        let confirmed = store.currentHoleConfirmed

        Text("\(store.currentStrokes)")
            .font(.system(size: ScorecardLayout.focusedStrokeCountSize, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(confirmed ? Color.primary : Color.secondary.opacity(0.35))
            .frame(minWidth: ScorecardLayout.strokeCountMinWidth)
            .contentTransition(.numericText())
            .animation(reduceMotion ? nil : .snappy, value: store.currentStrokes)
            .padding(12)
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        Color.secondary.opacity(0.4),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                    )
                    .opacity(confirmed ? 0 : 1)
            }
            .animation(.easeInOut(duration: 0.15), value: confirmed)
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .onTapGesture {
                if confirmed {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } else {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    store.confirmCurrentHoleAtPar()
                }
            }
            .accessibilityLabel(confirmed
                ? "\(store.currentStrokes) strokes"
                : "Par \(hole.par), not scored. Tap to score at par."
            )
            .accessibilityAddTraits(confirmed ? [] : .isButton)
    }

    // MARK: - Progress Row

    private var progressRow: some View {
        HStack(spacing: 12) {
            let scored = store.holesScored
            Text("\(store.totalStrokes) through \(scored) hole\(scored == 1 ? "" : "s")")
                .font(.caption.weight(.medium))

            Spacer()

            if store.isMultiplayer {
                ForEach(Array(store.playerProgress.enumerated()), id: \.offset) { _, progress in
                    HStack(spacing: 4) {
                        Text(progress.label)
                            .font(.caption.weight(.medium))
                        Text("\(progress.scored)/\(progress.total)")
                            .font(.caption)
                            .foregroundStyle(progress.scored >= progress.total ? .green : .secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    store.retreatHole()
                } label: {
                    Label("Previous", systemImage: "chevron.left")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(store.isOnFirstPosition)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    store.advanceHole()
                } label: {
                    HStack {
                        Text("Next")
                        Image(systemName: "chevron.right")
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isOnLastHole)
            }

            // Finish Round — appears once all holes are scored, from any hole
            if store.isFinishEnabled {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    store.requestFinish()
                } label: {
                    Label("Review & Finalize", systemImage: "checkmark")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else if let reason = store.finishBlockedReason {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
    }
}
