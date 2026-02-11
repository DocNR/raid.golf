// ScoreEntryView.swift
// Gambit Golf
//
// Hole-by-hole score entry.
// Thin rendering shell — all state and persistence lives in ActiveRoundStore.

import SwiftUI
import GRDB

struct ScoreEntryView: View {
    var store: ActiveRoundStore

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            if !store.isLoaded {
                ProgressView()
            } else if let currentHole = store.currentHole {
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
                .padding(.vertical, 40)

                // Running total
                VStack(spacing: 4) {
                    Text("Total: \(store.totalStrokes) (\(store.scoreToPar))")
                        .font(.headline)
                    Text("\(store.holesScored) of \(store.holes.count) holes scored")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)

                Spacer()

                // Navigation buttons
                HStack(spacing: 20) {
                    Button {
                        store.retreatHole()
                    } label: {
                        Label("Previous", systemImage: "chevron.left")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.currentHoleIndex == 0)

                    if store.isOnLastHole {
                        Button {
                            store.requestFinish()
                        } label: {
                            Label("Finish Round", systemImage: "checkmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!store.isFinishEnabled)
                    } else {
                        Button {
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
        .navigationTitle("Hole \(store.currentHoleIndex + 1) of \(store.holes.count)")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Finish Round", isPresented: Bindable(store).showFinishConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Finish") {
                store.finishRound { dismiss() }
            }
        } message: {
            Text("Are you sure you want to end your round?")
        }
    }
}
