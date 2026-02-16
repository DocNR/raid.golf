// ProfileView.swift
// RAID Golf
//
// Damus-style profile page: banner, avatar, identity, bio, stats, activity feed.
// Presented as a full-screen slide-in overlay (not a sheet).

import SwiftUI
import GRDB

struct ProfileView: View {
    let dbQueue: DatabaseQueue

    @Environment(\.drawerState) private var drawerState

    @State private var npub: String?
    @State private var rounds: [RoundListItem] = []
    @State private var partnerCount: Int = 0
    @State private var showEditProfile = false
    @State private var copiedNpub = false

    private var profile: NostrProfile? { drawerState.ownProfile }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    bannerSection
                    identitySection
                    statsSection

                    Divider()
                        .padding(.top, 8)

                    activityFeed
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            drawerState.showProfile = false
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                }
            }
            .sheet(isPresented: $showEditProfile) {
                EditProfileView()
            }
            .navigationDestination(for: Int64.self) { roundId in
                RoundDetailView(roundId: roundId, dbQueue: dbQueue)
            }
            .task {
                loadIdentity()
                loadRounds()
                loadPartnerCount()
            }
        }
    }

    // MARK: - Banner + Avatar

    private var bannerSection: some View {
        ZStack(alignment: .bottomLeading) {
            if let bannerURL = profile?.banner, let url = URL(string: bannerURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        bannerPlaceholder
                    }
                }
                .frame(height: 150)
                .clipped()
            } else {
                bannerPlaceholder
            }

            HStack(alignment: .bottom) {
                ProfileAvatarView(pictureURL: profile?.picture, size: 80)
                    .overlay(
                        Circle().stroke(Color(.systemBackground), lineWidth: 3)
                    )

                Spacer()

                Button {
                    showEditProfile = true
                } label: {
                    Text("Edit")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.secondary.opacity(0.5), lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, 16)
            .offset(y: 40)
        }
        .padding(.bottom, 48)
    }

    private var bannerPlaceholder: some View {
        LinearGradient(
            colors: [Color(.systemGray4), Color(.systemGray5)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(height: 150)
    }

    // MARK: - Identity

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let displayName = profile?.displayName, !displayName.isEmpty {
                Text(displayName)
                    .font(.title2)
                    .fontWeight(.bold)
            }

            if let name = profile?.name, !name.isEmpty {
                Text("@\(name)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let npub {
                Button {
                    UIPasteboard.general.string = npub
                    copiedNpub = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copiedNpub = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(String(npub.prefix(20)) + "...")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Image(systemName: copiedNpub ? "checkmark" : "doc.on.doc")
                            .font(.caption2)
                            .foregroundStyle(copiedNpub ? .green : .secondary)
                    }
                }
                .buttonStyle(.plain)
            }

            if let about = profile?.about, !about.isEmpty {
                Text(about)
                    .font(.subheadline)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    // MARK: - Stats

    private var statsSection: some View {
        HStack(spacing: 16) {
            statItem(count: rounds.count, label: "Rounds")
            statItem(count: partnerCount, label: "Partners")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private func statItem(count: Int, label: String) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Activity Feed

    private var activityFeed: some View {
        LazyVStack(spacing: 0) {
            if rounds.isEmpty {
                ContentUnavailableView {
                    Label("No Activity", systemImage: "tray")
                } description: {
                    Text("Your rounds and posts will appear here.")
                }
                .padding(.top, 40)
            } else {
                ForEach(rounds, id: \.roundId) { round in
                    NavigationLink(value: round.roundId) {
                        roundRow(round)
                    }
                    .buttonStyle(.plain)
                    Divider().padding(.leading, 16)
                }
            }
        }
    }

    private func roundRow(_ round: RoundListItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(round.courseName)
                    .font(.body)
                    .fontWeight(.medium)
                HStack(spacing: 4) {
                    Text(formatDate(round.roundDate))
                    Text("\u{2022}")
                    Text(round.teeSet)
                    Text("\u{2022}")
                    Text("\(round.holeCount) holes")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if round.isCompleted, let total = round.totalStrokes {
                Text("\(total)")
                    .font(.title3)
                    .fontWeight(.semibold)
            } else {
                Text("In Progress")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Data Loading

    private func loadIdentity() {
        do {
            let keyManager = try KeyManager.loadOrCreate()
            npub = try keyManager.publicKeyBech32()
        } catch {
            npub = nil
        }
    }

    private func loadRounds() {
        do {
            let repo = RoundRepository(dbQueue: dbQueue)
            rounds = try repo.listRounds()
        } catch {
            print("[RAID] ProfileView: failed to load rounds: \(error)")
        }
    }

    private func loadPartnerCount() {
        guard let km = try? KeyManager.loadOrCreate() else { return }
        let myHex = km.signingKeys().publicKey().toHex()
        do {
            partnerCount = try dbQueue.read { db in
                try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(DISTINCT player_pubkey) FROM round_players WHERE player_pubkey != ?",
                    arguments: [myHex]
                ) ?? 0
            }
        } catch {
            print("[RAID] ProfileView: failed to load partner count: \(error)")
        }
    }

    private func formatDate(_ isoDate: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: isoDate) else { return isoDate }
        let display = DateFormatter()
        display.dateStyle = .medium
        return display.string(from: date)
    }
}
