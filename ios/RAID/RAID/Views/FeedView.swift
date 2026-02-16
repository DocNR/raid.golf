// FeedView.swift
// RAID Golf
//
// Social feed from followed users.
// Placeholder for future kind 1 + kind 1502 golf content from follows.

import SwiftUI

struct FeedView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Feed", systemImage: "bubble.left.and.bubble.right")
            } description: {
                Text("See rounds and posts from golfers you follow. Coming soon.")
            }
            .navigationTitle("Feed")
            .avatarToolbar()
        }
    }
}
