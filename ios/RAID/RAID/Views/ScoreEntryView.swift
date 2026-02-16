// ScoreEntryView.swift
// RAID Golf
//
// Hole-by-hole score entry.
// Thin rendering shell — all state and persistence lives in ActiveRoundStore.

import SwiftUI
import GRDB

struct ScoreEntryView: View {
    var store: ActiveRoundStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.nostrService) private var nostrService
    @State private var showScorecard = false

    var body: some View {
        VStack(spacing: 20) {
            if !store.isLoaded {
                ProgressView()
            } else if let currentHole = store.currentHole {
                // Prominent hole number
                VStack(spacing: 2) {
                    Text("Hole \(currentHole.holeNumber)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                    Text("of \(store.holes.count)")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                // Player picker (same-device multiplayer only)
                if store.isMultiplayer && !store.multiDeviceMode {
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
                }

                VStack(spacing: 8) {
                    Text("Par \(currentHole.par)")
                        .font(.title2)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button {
                            store.decrementStrokes()
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 44))
                        }
                        .disabled(store.currentStrokes <= 1)

                        Spacer()

                        Text("\(store.currentStrokes)")
                            .font(.system(size: 72, weight: .bold, design: .rounded))
                            .frame(minWidth: 120)

                        Spacer()

                        Button {
                            store.incrementStrokes()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 44))
                        }
                        .disabled(store.currentStrokes >= 20)
                    }
                    .padding(.horizontal, 40)
                }
                .padding(.vertical, 20)

                // Per-player progress
                VStack(spacing: 4) {
                    Text("Total: \(store.totalStrokes) (\(store.scoreToPar))")
                        .font(.headline)

                    HStack(spacing: 12) {
                        ForEach(Array(store.playerProgress.enumerated()), id: \.offset) { _, progress in
                            HStack(spacing: 4) {
                                Text(progress.label)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text("\(progress.scored)/\(progress.total)")
                                    .font(.caption)
                                    .foregroundStyle(progress.scored >= progress.total ? .green : .secondary)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)

                Spacer()

                // Finish gating feedback
                if store.isOnLastHole, let reason = store.finishBlockedReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.horizontal)
                }

                // Navigation buttons
                HStack(spacing: 20) {
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
}
