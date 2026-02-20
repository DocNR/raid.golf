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

    var body: some View {
        VStack(spacing: 0) {
            if !store.isLoaded {
                Spacer()
                ProgressView()
                Spacer()
            } else if let currentHole = store.currentHole {
                // Mini scorecard strip (tappable, auto-scrolls)
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

                // Player picker (same-device multiplayer only)
                if store.isMultiplayer && !store.multiDeviceMode {
                    playerPicker
                }

                Spacer()

                // Focused hole panel
                focusedHolePanel(hole: currentHole)

                Spacer()

                // Player progress (multiplayer only)
                if store.isMultiplayer {
                    playerProgressRow
                }

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
                }
                .disabled(store.currentStrokes <= 1)
                .accessibilityLabel("Decrease strokes")

                Spacer()

                Text("\(store.currentStrokes)")
                    .font(.system(size: ScorecardLayout.focusedStrokeCountSize, weight: .bold))
                    .monospacedDigit()
                    .frame(minWidth: ScorecardLayout.strokeCountMinWidth)
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .snappy, value: store.currentStrokes)

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
                .accessibilityLabel("Increase strokes")
            }
            .padding(.horizontal, 40)
        }
    }

    // MARK: - Player Progress

    private var playerProgressRow: some View {
        HStack(spacing: 12) {
            Text("Total: \(store.totalStrokes)")
                .font(.caption.weight(.medium))

            let diff = store.totalStrokes - store.totalPar
            Text(diff.scoreToParString)
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(diff > 0 ? Color.scoreDouble : (diff < 0 ? Color.scoreEagle : .secondary))

            Spacer()

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
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
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

            if store.isOnLastHole {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    store.requestFinish()
                } label: {
                    Label("Finish Round", systemImage: "checkmark")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
    }
}
