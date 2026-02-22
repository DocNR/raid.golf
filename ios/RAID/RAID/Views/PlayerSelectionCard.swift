// PlayerSelectionCard.swift
// RAID Golf
//
// Shared player selection component used by RoundSetupView.
// Encapsulates: Nostr key check, player picker button,
// overlapping PFP summary row, multi-device toggle.

import SwiftUI
import GRDB

struct PlayerSelectionCard: View {
    let dbQueue: DatabaseQueue
    @Binding var selectedPlayers: [String: NostrProfile]
    @Binding var isMultiDevice: Bool
    @Binding var showPlayerPicker: Bool

    private var hasNostrKeys: Bool {
        UserDefaults.standard.bool(forKey: "nostrActivated") && KeyManager.publicKeyHex() != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Players")
                    .font(.subheadline.weight(.medium))
                if !selectedPlayers.isEmpty {
                    Text("(\(selectedPlayers.count))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if !hasNostrKeys {
                Text("Set up Nostr identity to invite players")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                Button {
                    showPlayerPicker = true
                } label: {
                    HStack(spacing: 10) {
                        if selectedPlayers.isEmpty {
                            Label("Add Playing Partners", systemImage: "person.badge.plus")
                        } else {
                            playerSummaryRow
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.primary)
                }

                if !selectedPlayers.isEmpty {
                    Toggle("Each player uses their own device", isOn: $isMultiDevice)
                        .font(.subheadline)
                }
            }

            if hasNostrKeys {
                Text("Optional. Select playing partners or add by npub.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .scorecardCardStyle()
    }

    // MARK: - Player Summary

    private var playerSummaryRow: some View {
        HStack(spacing: 6) {
            HStack(spacing: -8) {
                ForEach(playerSummaryAvatars()) { profile in
                    ProfileAvatarView(pictureURL: profile.picture, size: 28)
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
                }
            }
            Text(playerSummaryLabel())
                .font(.subheadline)
                .lineLimit(1)
        }
    }

    private func playerSummaryLabel() -> String {
        let sorted = Array(selectedPlayers.values).sorted { $0.displayLabel < $1.displayLabel }
        let names: [String] = sorted.prefix(2).map { $0.displayLabel }
        let overflow = sorted.count - 2
        if overflow > 0 {
            return names.joined(separator: ", ") + " +\(overflow) more"
        }
        return names.joined(separator: ", ")
    }

    private func playerSummaryAvatars() -> [NostrProfile] {
        Array(selectedPlayers.values)
            .sorted { $0.displayLabel < $1.displayLabel }
            .prefix(3)
            .map { $0 }
    }
}
