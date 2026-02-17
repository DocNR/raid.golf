// FeedView.swift
// RAID Golf
//
// Social feed from followed users. Shows kind 1 text notes and kind 1502 scorecards.

import SwiftUI

struct FeedView: View {
    @Environment(\.nostrService) private var nostrService
    @State private var viewModel = FeedViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    ProgressView("Loading feed...")
                } else if let error = viewModel.errorMessage {
                    ContentUnavailableView {
                        Label("Couldn't Load Feed", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try Again") {
                            Task { await viewModel.refresh(nostrService: nostrService) }
                        }
                    }
                } else {
                    switch viewModel.loadState {
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
                    }
                }
            }
            .navigationTitle("Feed")
            .avatarToolbar()
            .refreshable { await viewModel.refresh(nostrService: nostrService) }
            .task { await viewModel.loadIfNeeded(nostrService: nostrService) }
        }
    }

    private var feedList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.items) { item in
                    FeedCardView(
                        item: item,
                        profile: nostrService.profileCache[item.pubkeyHex]
                    )
                    .padding(.horizontal)

                    Divider()
                        .padding(.leading, 56)
                }
            }
        }
    }
}
