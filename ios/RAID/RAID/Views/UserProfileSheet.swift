// UserProfileSheet.swift
// RAID Golf
//
// Lightweight profile sheet for viewing another user.
// Shows avatar, name, bio, npub + Follow/Unfollow and Clubhouse actions.
// Presented from PeopleView rows, feed threads, or any player tap.

import SwiftUI
import GRDB
import NostrSDK

struct UserProfileSheet: View {
    let pubkeyHex: String
    let dbQueue: DatabaseQueue

    @Environment(\.dismiss) private var dismiss
    @Environment(\.nostrService) private var nostrService

    @State private var profile: NostrProfile?
    @State private var npub: String?
    @State private var copiedNpub = false

    @State private var isFollowing = false
    @State private var isInClubhouse = false
    @State private var isTogglingFollow = false
    @State private var isTogglingClubhouse = false
    @State private var isLoading = true

    // Activation gate
    @State private var showActivationAlert = false
    @State private var showActivation = false

    private var isActivated: Bool {
        UserDefaults.standard.bool(forKey: "nostrActivated")
    }

    private var myPubkeyHex: String? {
        guard isActivated, let km = try? KeyManager.loadOrCreate() else { return nil }
        return km.signingKeys().publicKey().toHex()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    bannerSection
                    identitySection
                    actionButtons
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await loadProfile()
                loadState()
            }
            .nostrActivationAlert(
                isPresented: $showActivationAlert,
                message: "Create an account to follow people and manage your Clubhouse.",
                onActivate: { showActivation = true }
            )
            .fullScreenCover(isPresented: $showActivation) {
                WelcomeView { activated in
                    UserDefaults.standard.set(activated, forKey: "nostrActivated")
                    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                    showActivation = false
                    loadState()
                }
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
                .frame(height: 120)
                .clipped()
            } else {
                bannerPlaceholder
            }

            ProfileAvatarView(pictureURL: profile?.picture, size: 72)
                .overlay(
                    Circle().stroke(Color(.systemBackground), lineWidth: 3)
                )
                .padding(.horizontal, 16)
                .offset(y: 36)
        }
        .padding(.bottom, 44)
    }

    private var bannerPlaceholder: some View {
        LinearGradient(
            colors: [Color(.systemGray4), Color(.systemGray5)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(height: 120)
    }

    // MARK: - Identity

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isLoading {
                ProgressView()
                    .padding(.top, 8)
            } else {
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

                if let nip05 = profile?.nip05 {
                    Text(nip05)
                        .font(.caption)
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
                    .padding(.top, 2)
                }

                if let about = profile?.about, !about.isEmpty {
                    Text(about)
                        .font(.subheadline)
                        .padding(.top, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                guard isActivated else {
                    showActivationAlert = true
                    return
                }
                toggleFollow()
            } label: {
                HStack(spacing: 4) {
                    if isTogglingFollow {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: isFollowing ? "person.badge.minus" : "person.badge.plus")
                    }
                    Text(isFollowing ? "Unfollow" : "Follow")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(isFollowing ? Color(.systemGray4) : .accentColor)
            .disabled(isTogglingFollow)

            Button {
                guard isActivated else {
                    showActivationAlert = true
                    return
                }
                toggleClubhouse()
            } label: {
                HStack(spacing: 4) {
                    if isTogglingClubhouse {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: isInClubhouse ? "person.crop.circle.badge.minus" : "person.crop.circle.badge.plus")
                    }
                    Text(isInClubhouse ? "Remove" : "Clubhouse")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .disabled(isTogglingClubhouse)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    // MARK: - Data Loading

    private func loadProfile() async {
        isLoading = true

        // Compute npub
        if let pk = try? PublicKey.parse(publicKey: pubkeyHex) {
            npub = try? pk.toBech32()
        }

        // Resolve profile from cache then relay
        let cacheRepo = ProfileCacheRepository(dbQueue: dbQueue)
        if let profiles = try? await nostrService.resolveProfiles(
            pubkeyHexes: [pubkeyHex], cacheRepo: cacheRepo
        ) {
            profile = profiles[pubkeyHex]
        }

        if profile == nil {
            profile = NostrProfile(pubkeyHex: pubkeyHex, name: nil, displayName: nil, picture: nil)
        }

        isLoading = false
    }

    private func loadState() {
        guard let myHex = myPubkeyHex else { return }
        let followRepo = FollowListCacheRepository(dbQueue: dbQueue)
        isFollowing = (try? followRepo.isFollowing(ownerPubkeyHex: myHex, targetPubkeyHex: pubkeyHex)) ?? false

        let clubhouseRepo = ClubhouseRepository(dbQueue: dbQueue)
        isInClubhouse = (try? clubhouseRepo.isMember(pubkeyHex: pubkeyHex)) ?? false
    }

    // MARK: - Follow/Unfollow

    private func toggleFollow() {
        isTogglingFollow = true
        Task {
            guard let km = try? KeyManager.loadOrCreate() else {
                isTogglingFollow = false
                return
            }
            let keys = km.signingKeys()
            let myHex = keys.publicKey().toHex()

            // Load current follow list
            let repo = FollowListCacheRepository(dbQueue: dbQueue)
            var follows = (try? repo.fetch(pubkeyHex: myHex))?.follows ?? []

            if isFollowing {
                follows.removeAll { $0 == pubkeyHex }
            } else {
                if !follows.contains(pubkeyHex) {
                    follows.append(pubkeyHex)
                }
            }

            try? await nostrService.publishFollowList(keys: keys, followedPubkeyHexes: follows)
            try? repo.updateLocalFollowList(pubkeyHex: myHex, follows: follows)

            isFollowing.toggle()
            isTogglingFollow = false
        }
    }

    // MARK: - Clubhouse

    private func toggleClubhouse() {
        isTogglingClubhouse = true
        Task {
            guard let km = try? KeyManager.loadOrCreate() else {
                isTogglingClubhouse = false
                return
            }
            let keys = km.signingKeys()
            let repo = ClubhouseRepository(dbQueue: dbQueue)

            if isInClubhouse {
                try? repo.remove(pubkeyHex: pubkeyHex)
            } else {
                try? repo.add(pubkeyHex: pubkeyHex)
            }

            let allMembers = (try? repo.allPubkeyHexes()) ?? []
            try? await nostrService.publishClubhouse(keys: keys, memberPubkeyHexes: allMembers)

            isInClubhouse.toggle()
            isTogglingClubhouse = false
        }
    }
}
