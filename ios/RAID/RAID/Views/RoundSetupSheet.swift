// RoundSetupSheet.swift
// Gambit Golf
//
// Shown after creating a multi-device round, before navigating to scoring.
// Polls for the kind 1501 initiation publish, then displays the invite QR.
// Dismissal triggers navigation to ScoreEntryView.

import SwiftUI
import GRDB

struct RoundSetupSheet: View {
    let roundId: Int64
    let dbQueue: DatabaseQueue

    @Environment(\.dismiss) private var dismiss
    @State private var inviteNevent: String?
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Group {
                if let nevent = inviteNevent {
                    inviteReadyView(nevent: nevent)
                } else {
                    loadingView
                }
            }
            .navigationTitle("Round Setup")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(inviteNevent == nil)
        .task { await pollForInvite() }
    }

    // MARK: - Loading State

    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Setting up your round...")
                .font(.headline)
            Text("This will just take a moment")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Invite Ready State

    private func inviteReadyView(nevent: String) -> some View {
        VStack(spacing: 20) {
            Text("Share this invite with other players so they can join your round.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // QR Code
            let uri = RoundInviteBuilder.buildNostrURI(nevent: nevent)
            if let image = QRCodeGenerator.generate(from: uri, size: 200) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .padding()
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Invite code + copy
            VStack(spacing: 8) {
                Text("Invite Code")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(nevent)
                    .font(.system(.caption2, design: .monospaced))
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                HStack(spacing: 12) {
                    Button {
                        UIPasteboard.general.string = nevent
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                    } label: {
                        Label(copied ? "Copied!" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.bordered)

                    ShareLink(item: nevent) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Start Scoring")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)
            .padding(.bottom)
        }
        .padding(.top)
    }

    // MARK: - Polling

    private func pollForInvite() async {
        let nostrRepo = RoundNostrRepository(dbQueue: dbQueue)

        for _ in 1...10 {
            do {
                if let record = try nostrRepo.fetchInitiation(forRound: roundId) {
                    inviteNevent = try RoundInviteBuilder.buildNevent(
                        eventIdHex: record.initiationEventId,
                        relays: NostrService.defaultPublishRelays
                    )
                    return
                }
            } catch {
                print("[Gambit] Setup sheet poll error: \(error)")
                return
            }

            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            } catch {
                return  // Task cancelled
            }
        }

        print("[Gambit] Setup sheet: round_nostr not found after polling for round \(roundId)")
    }
}
