// SideDrawerView.swift
// RAID Golf
//
// Damus-style left drawer. Shows profile header + menu items.
// Menu taps close the drawer and present the corresponding sheet.

import SwiftUI
import GRDB

struct SideDrawerView: View {
    let dbQueue: DatabaseQueue

    @Environment(\.drawerState) private var drawerState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            profileHeader
                .padding(.horizontal, 20)
                .padding(.top, 60)
                .padding(.bottom, 20)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                drawerMenuItem(icon: "person.circle", label: "Profile") {
                    drawerState.close()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            drawerState.showProfile = true
                        }
                    }
                }

                drawerMenuItem(icon: "sportscourt", label: "Practice") {
                    presentSheet { drawerState.showPractice = true }
                }

                drawerMenuItem(icon: "key.horizontal", label: "Keys & Relays") {
                    presentSheet { drawerState.showKeysRelays = true }
                }

                drawerMenuItem(icon: "info.circle", label: "About") {
                    presentSheet { drawerState.showAbout = true }
                }

                // Debug view accessible via Practice → Templates long-press
            }
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
    }

    // MARK: - Profile Header

    @ViewBuilder
    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProfileAvatarView(
                pictureURL: drawerState.ownProfile?.picture,
                size: 56
            )

            if let profile = drawerState.ownProfile {
                if let displayName = profile.displayName, !displayName.isEmpty {
                    Text(displayName)
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                if let name = profile.name, !name.isEmpty {
                    Text("@\(name)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let npub = try? KeyManager.loadOrCreate().publicKeyBech32() {
                Text(String(npub.prefix(20)) + "...")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Menu Item

    private func drawerMenuItem(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .frame(width: 24)
                    .foregroundStyle(.primary)
                Text(label)
                    .font(.body)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func presentSheet(_ show: @escaping () -> Void) {
        drawerState.close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            show()
        }
    }
}
