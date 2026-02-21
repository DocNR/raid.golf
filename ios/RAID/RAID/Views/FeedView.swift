// FeedView.swift
// RAID Golf
//
// Social feed from followed users. Shows kind 1 text notes and kind 1502 scorecards.

import SwiftUI
import GRDB

struct FeedView: View {
    let dbQueue: DatabaseQueue

    @Environment(\.nostrService) private var nostrService
    @State private var viewModel = FeedViewModel()
    @AppStorage("nostrActivated") private var nostrActivated = false
    @State private var showActivation = false
    @State private var selectedItem: FeedItem?
    @State private var profileSheetPubkey: String?

    // Scroll-to-hide chrome
    @State private var barsVisible = true
    @State private var scrollCheckpoint: CGFloat = 0

    // Custom pull-to-refresh
    @State private var pullTriggered = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    FeedLoadingView(
                        stage: viewModel.refreshStage,
                        progress: viewModel.refreshProgress
                    )
                } else if let error = viewModel.errorMessage {
                    ContentUnavailableView {
                        Label("Couldn't Load Feed", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again") {
                            Task { await viewModel.refresh(nostrService: nostrService, dbQueue: dbQueue) }
                        }
                    }
                } else {
                    switch viewModel.loadState {
                    case .guest:
                        guestState
                    case .noKey:
                        ContentUnavailableView {
                            Label("No Nostr Key", systemImage: "key")
                        } description: {
                            Text("Import or create a Nostr key to see your feed.")
                        }
                    case .noFollows:
                        ContentUnavailableView {
                            Label("No Follows", systemImage: "person.2")
                        } description: {
                            Text("Follow golfers on Nostr to see their rounds and posts here.")
                        }
                    case .loaded where viewModel.items.isEmpty:
                        ContentUnavailableView {
                            Label("No Posts Yet", systemImage: "bubble.left.and.bubble.right")
                        } description: {
                            Text("People you follow haven't posted any golf content yet.")
                        }
                    default:
                        feedList
                            .toolbarVisibility(barsVisible ? .visible : .hidden, for: .navigationBar)
                            .toolbarVisibility(barsVisible ? .visible : .hidden, for: .tabBar)
                            .animation(.spring(duration: 0.45, bounce: 0), value: barsVisible)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .avatarToolbar()
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "raid" && url.host == "profile" {
                    profileSheetPubkey = url.lastPathComponent
                    return .handled
                }
                return .systemAction
            })
            .task { await viewModel.loadIfNeeded(nostrService: nostrService, dbQueue: dbQueue) }
            .onReceive(NotificationCenter.default.publisher(for: .nostrSignedOut)) { _ in
                viewModel.reset()
            }
            .onChange(of: nostrActivated) { _, newValue in
                if newValue {
                    Task { await viewModel.refresh(nostrService: nostrService, dbQueue: dbQueue) }
                }
            }
            .sheet(isPresented: Binding(
                get: { profileSheetPubkey != nil },
                set: { if !$0 { profileSheetPubkey = nil } }
            )) {
                if let hex = profileSheetPubkey {
                    UserProfileSheet(
                        pubkeyHex: hex,
                        dbQueue: dbQueue,
                        initialProfile: viewModel.resolvedProfiles[hex]
                    )
                }
            }
            .fullScreenCover(isPresented: $showActivation) {
                WelcomeView { activated in
                    nostrActivated = activated
                    showActivation = false
                    if activated {
                        Task { await viewModel.refresh(nostrService: nostrService, dbQueue: dbQueue) }
                    }
                }
            }
        }
    }

    // MARK: - Guest State

    private var guestState: some View {
        ZStack(alignment: .bottom) {
            // Background: scrollable dimmed feed
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Self.mockPosts) { post in
                        mockPostView(post)
                        Divider()
                    }
                }
            }
            .opacity(0.5)
            .allowsHitTesting(false)

            // Foreground: gradient fade + CTA
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color(.systemBackground).opacity(0), Color(.systemBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)

                VStack(spacing: 12) {
                    Text("See your friends' rounds")
                        .font(.headline)
                    Text("Create an account or sign in to see golf posts from people you follow.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Get Started") {
                        showActivation = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
                .background(Color(.systemBackground))
            }
        }
    }

    // MARK: - Mock Post Data

    private struct MockPost: Identifiable {
        let id: Int
        let name: String
        let time: String
        let picture: String?
        let content: String
        let scorecard: MockScorecard?
    }

    private struct MockScorecard {
        let course: String
        let score: Int
        let par: Int
        let holes: Int
    }

    private static let mockPosts: [MockPost] = [
        MockPost(
            id: 1, name: "jack", time: "1h",
            picture: "https://image.nostr.build/26867ce34e4b11f0a1d083114919a9f4eca699f3b007454c396ef48c43628315.jpg",
            content: "Perfect weather for 18 at Pebble Beach today.",
            scorecard: MockScorecard(course: "Pebble Beach Golf Links", score: 78, par: 72, holes: 18)
        ),
        MockPost(
            id: 2, name: "fiatjaf", time: "2h",
            picture: "https://fiatjaf.com/static/favicon.jpg",
            content: "The beauty of golf scoring on Nostr is that every round is cryptographically verifiable. No more inflated handicaps.",
            scorecard: nil
        ),
        MockPost(
            id: 3, name: "ODELL", time: "3h",
            picture: "https://m.primal.net/NcKe.jpg",
            content: "Broke 80 for the first time. Freedom tech on the golf course.",
            scorecard: MockScorecard(course: "Bethpage Black", score: 79, par: 71, holes: 18)
        ),
        MockPost(
            id: 4, name: "Lyn Alden", time: "4h",
            picture: "https://m.primal.net/LtjB.jpg",
            content: "Guest day at Augusta. Amen Corner lived up to the hype.",
            scorecard: MockScorecard(course: "Augusta National Golf Club", score: 85, par: 72, holes: 18)
        ),
        MockPost(
            id: 5, name: "PABLOF7z", time: "5h",
            picture: "https://m.primal.net/KwlG.jpg",
            content: "Bucket list course checked off. Wind was brutal on the back nine.",
            scorecard: MockScorecard(course: "St Andrews Old Course", score: 82, par: 72, holes: 18)
        ),
        MockPost(
            id: 6, name: "Jeff Booth", time: "6h",
            picture: "https://pbs.twimg.com/profile_images/1362957991410954241/spiaMAg2_400x400.jpg",
            content: "Golf is the ultimate proof of work. No shortcuts, no faking it.",
            scorecard: nil
        ),
        MockPost(
            id: 7, name: "jb55", time: "8h",
            picture: "https://cdn.jb55.com/img/red-me.jpg",
            content: "Windy but worth it.",
            scorecard: MockScorecard(course: "Bandon Dunes", score: 74, par: 72, holes: 18)
        ),
        MockPost(
            id: 8, name: "miljan", time: "12h",
            picture: "https://m.primal.net/HgUk.jpg",
            content: "Working on some new features for golf stat tracking. Stay tuned.",
            scorecard: nil
        ),
        MockPost(
            id: 9, name: "Vitor Pamplona", time: "1d",
            picture: "https://vitorpamplona.com/images/me_300.jpg",
            content: "Decentralized golf scoring means your rounds belong to you, forever. No platform can take that away.",
            scorecard: nil
        ),
    ]

    // MARK: - Mock Post View

    @ViewBuilder
    private func mockPostView(_ post: MockPost) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header: avatar + name · time
            HStack(spacing: 10) {
                ProfileAvatarView(pictureURL: post.picture, size: 40)

                Text(post.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text("·")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(post.time)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            // Content — indented under name
            VStack(alignment: .leading, spacing: 8) {
                Text(post.content)
                    .font(.subheadline)

                if let sc = post.scorecard {
                    mockScorecardCard(sc)
                }
            }
            .padding(.leading, 50)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func mockScorecardCard(_ sc: MockScorecard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(sc.course)
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(sc.score)")
                    .font(.title.weight(.bold))

                let delta = sc.score - sc.par
                Text(delta == 0 ? "Even" : (delta > 0 ? "+\(delta)" : "\(delta)"))
                    .font(.title3.weight(.medium))
                    .foregroundStyle(delta < 0 ? .red : .primary)

                Spacer()

                Text("\(sc.holes) holes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Feed List

    private var feedList: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(spacing: 0) {
                Color.clear.frame(height: nostrService.isReadOnly ? 28 : 0).id("feedTop")

                // Pull-to-refresh indicator — inline, pushes content down
                if viewModel.isBackgroundRefreshing {
                    MiniCartProgressBar(progress: viewModel.refreshProgress)
                        .padding(.bottom, 8)
                }

                ForEach(viewModel.items) { item in
                    NavigationLink {
                        ThreadDetailView(
                            item: item,
                            profile: viewModel.resolvedProfiles[item.pubkeyHex],
                            rawEvent: viewModel.rawEvents[item.id],
                            dbQueue: dbQueue,
                            resolvedProfiles: viewModel.resolvedProfiles,
                            reactionCount: viewModel.reactionCounts[item.id] ?? 0,
                            hasReacted: viewModel.ownReactions.contains(item.id),
                            isReadOnly: nostrService.isReadOnly,
                            onReact: {
                                viewModel.react(itemId: item.id, nostrService: nostrService)
                            }
                        )
                    } label: {
                        FeedCardView(
                            item: item,
                            profile: viewModel.resolvedProfiles[item.pubkeyHex],
                            profiles: viewModel.resolvedProfiles,
                            reactionCount: viewModel.reactionCounts[item.id] ?? 0,
                            hasReacted: viewModel.ownReactions.contains(item.id),
                            commentCount: viewModel.commentCounts[item.id] ?? 0,
                            isReadOnly: nostrService.isReadOnly,
                            onReact: {
                                viewModel.react(itemId: item.id, nostrService: nostrService)
                            },
                            onProfileTap: {
                                profileSheetPubkey = item.pubkeyHex
                            }
                        )
                        .padding(.horizontal)
                    }
                    .buttonStyle(.plain)

                    Divider()
                }

                // Pagination: load older events when scrolled to bottom
                if viewModel.hasMoreEvents && !viewModel.items.isEmpty {
                    if viewModel.isLoadingMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    } else {
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                Task {
                                    await viewModel.loadNextPage(
                                        nostrService: nostrService,
                                        dbQueue: dbQueue
                                    )
                                }
                            }
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            if nostrService.isReadOnly {
                HStack(spacing: 6) {
                    Image(systemName: "eye")
                    Text("Read-only mode")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .feedScrollToTop)) { _ in
            withAnimation { proxy.scrollTo("feedTop", anchor: .top) }
        }
        .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { _, new in
            // Pull-to-refresh: trigger immediately when pulled past threshold
            if new < 0 {
                if -new > 80 && !pullTriggered && !viewModel.isBackgroundRefreshing {
                    pullTriggered = true
                    Task { await viewModel.refresh(nostrService: nostrService, dbQueue: dbQueue) }
                }
            } else {
                pullTriggered = false
            }

            // Scroll-to-hide chrome
            if new < 50 {
                // Near top — always show bars
                if !barsVisible { barsVisible = true }
                scrollCheckpoint = new
            } else {
                let delta = new - scrollCheckpoint
                if delta > 40 {
                    // Scrolled down — hide bars
                    if barsVisible { barsVisible = false }
                    scrollCheckpoint = new
                } else if delta < -40 {
                    // Scrolled up — show bars
                    if !barsVisible { barsVisible = true }
                    scrollCheckpoint = new
                }
            }
        }
        } // ScrollViewReader
    }
}

// MARK: - Mini Cart Progress Bar (pull-to-refresh + background refresh)

private struct MiniCartProgressBar: View {
    let progress: Double

    var body: some View {
        let cartHeight: CGFloat = 24
        let cartWidth: CGFloat = cartHeight * (800 / 600.7)

        GeometryReader { geo in
            if geo.size.width > 0 {
                let trackWidth = geo.size.width
                let fillWidth = trackWidth * progress
                let cartX = fillWidth - cartWidth

                ZStack(alignment: .leading) {
                    // Track
                    Capsule()
                        .fill(.quaternary)
                        .frame(height: 3)
                        .frame(maxHeight: .infinity, alignment: .bottom)

                    // Fill
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(3, fillWidth), height: 3)
                        .frame(maxHeight: .infinity, alignment: .bottom)

                    // Golf cart — starts off-screen left, drives in
                    Image("GolfCart")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: cartHeight)
                        .foregroundStyle(Color.accentColor)
                        .offset(x: cartX)
                }
                .animation(.easeInOut(duration: 0.5), value: progress)
            }
        }
        .clipped()
        .frame(height: cartHeight + 3)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

// MARK: - Feed Loading View

private struct FeedLoadingView: View {
    let stage: String
    let progress: Double

    // Golf cart position tracks progress
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Golf cart driving along progress bar
            VStack(spacing: 0) {
                let cartHeight: CGFloat = 54
                let cartWidth: CGFloat = cartHeight * (800 / 600.7) // match SVG aspect ratio

                GeometryReader { geo in
                    if geo.size.width > 0 {
                        let trackWidth = geo.size.width
                        let fillWidth = trackWidth * progress
                        let cartX = fillWidth - cartWidth

                        Image("GolfCart")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: cartHeight)
                            .foregroundStyle(Color.accentColor)
                            .offset(x: cartX)
                            .animation(.easeInOut(duration: 0.6), value: progress)
                    }
                }
                .clipped()
                .frame(height: cartHeight)

                // Track bar below
                GeometryReader { geo in
                    if geo.size.width > 0 {
                        let trackWidth = geo.size.width
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(.quaternary)
                                .frame(height: 4)

                            Capsule()
                                .fill(Color.accentColor)
                                .frame(width: max(4, trackWidth * progress), height: 4)
                        }
                    }
                }
                .frame(height: 4)
                .padding(.top, 4)
            }
            .padding(.horizontal, 32)

            // Stage message
            Text(stage.isEmpty ? "Loading feed..." : stage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.3), value: stage)

            Spacer()
            Spacer()
        }
    }
}

extension Notification.Name {
    static let feedScrollToTop = Notification.Name("feedScrollToTop")
    static let nostrSignedOut = Notification.Name("nostrSignedOut")
}
