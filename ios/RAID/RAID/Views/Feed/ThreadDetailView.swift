// ThreadDetailView.swift
// RAID Golf
//
// Damus/Nostur-style thread view — pushed via NavigationStack.
// Shows the original post at top, replies/comments below, input bar at bottom.
// Kind 1 text notes → NIP-10 kind 1 reply.
// Scorecards (kind 1502) → NIP-22 kind 1111 comment.

import SwiftUI
import GRDB
import NostrSDK

struct ThreadDetailView: View {
    let item: FeedItem
    let profile: NostrProfile?
    let rawEvent: Event?
    let dbQueue: DatabaseQueue

    var reactionCount: Int = 0
    var hasReacted: Bool = false
    var onReact: (() -> Void)?
    var focusReply: Bool = false

    @Environment(\.nostrService) private var nostrService

    @State private var comments: [CommentRow] = []
    @State private var profiles: [String: NostrProfile] = [:]
    @State private var commentText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var isInputFocused: Bool

    private var isTextNote: Bool {
        if case .textNote = item { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Original post
                    originalPost
                        .padding(.horizontal)
                        .padding(.vertical, 10)

                    Divider()

                    // Replies / comments
                    if isLoading && comments.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding(.vertical, 32)
                            Spacer()
                        }
                    } else if comments.isEmpty {
                        HStack {
                            Spacer()
                            Text(isTextNote ? "No replies yet" : "No comments yet")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 32)
                            Spacer()
                        }
                    } else {
                        ForEach(comments) { comment in
                            commentRow(comment)
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                            Divider()
                        }
                    }
                }
            }

            Divider()
            inputBar
        }
        .navigationTitle(isTextNote ? "Post" : "Scorecard")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            if let error = errorMessage { Text(error) }
        }
        .task {
            await loadComments()
            if focusReply {
                isInputFocused = true
            }
        }
    }

    // MARK: - Original Post

    private let avatarSize: CGFloat = 40
    private let avatarSpacing: CGFloat = 10

    private var originalPost: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: avatar + name
            HStack(spacing: avatarSpacing) {
                ProfileAvatarView(pictureURL: profile?.picture, size: avatarSize)

                VStack(alignment: .leading, spacing: 1) {
                    Text(profile?.displayLabel ?? String(item.pubkeyHex.prefix(8)) + "...")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Text(formattedDate(item.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            // Content (not indented — full width in detail view)
            switch item {
            case .textNote(_, _, let content, _):
                Text(content)
                    .font(.body)

            case .scorecard(_, _, let commentary, let record, let courseInfo, _):
                if let commentary, !commentary.isEmpty {
                    Text(commentary)
                        .font(.body)
                }
                ScorecardCardView(record: record, courseInfo: courseInfo)
            }

            // Reaction bar
            HStack(spacing: 16) {
                Button {
                    onReact?()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: hasReacted ? "heart.fill" : "heart")
                            .foregroundStyle(hasReacted ? .red : .secondary)
                        if reactionCount > 0 {
                            Text("\(reactionCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(hasReacted)

                Button {
                    isInputFocused = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left")
                            .foregroundStyle(.secondary)
                        if !comments.isEmpty {
                            Text("\(comments.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .font(.subheadline)
            .padding(.top, 4)
        }
    }

    // MARK: - Comment Row

    private func commentRow(_ comment: CommentRow) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ProfileAvatarView(
                pictureURL: profiles[comment.pubkeyHex]?.picture,
                size: 32
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(profiles[comment.pubkeyHex]?.displayLabel
                         ?? String(comment.pubkeyHex.prefix(8)) + "...")
                        .font(.caption.weight(.semibold))
                    Text(relativeTime(comment.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text(comment.content)
                    .font(.subheadline)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField(isTextNote ? "Reply..." : "Comment...", text: $commentText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .focused($isInputFocused)

            Button {
                Task { await sendComment() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : Color.accentColor)
            }
            .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Data

    private func loadComments() async {
        isLoading = true
        do {
            let events = isTextNote
                ? try await nostrService.fetchReplies(eventId: item.id)
                : try await nostrService.fetchComments(eventId: item.id)
            var rows: [CommentRow] = []
            var pubkeys: Set<String> = []

            for event in events {
                let hex = event.author().toHex()
                pubkeys.insert(hex)
                rows.append(CommentRow(
                    id: event.id().toHex(),
                    pubkeyHex: hex,
                    content: event.content(),
                    createdAt: Date(timeIntervalSince1970: TimeInterval(event.createdAt().asSecs()))
                ))
            }

            comments = rows.sorted { $0.createdAt < $1.createdAt }

            // Pre-seed profiles from in-memory cache (instant, no relay call)
            for hex in pubkeys {
                if let cached = nostrService.profileCache[hex] {
                    profiles[hex] = cached
                }
            }

            // Stop spinner — comments are visible with cached profiles
            isLoading = false

            // Resolve any remaining uncached profiles in the background
            let uncached = pubkeys.filter { nostrService.profileCache[$0] == nil }
            if !uncached.isEmpty {
                let cacheRepo = ProfileCacheRepository(dbQueue: dbQueue)
                if let resolved = try? await nostrService.resolveProfiles(
                    pubkeyHexes: Array(uncached), cacheRepo: cacheRepo
                ) {
                    for (key, value) in resolved {
                        profiles[key] = value
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func sendComment() async {
        let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let event = rawEvent else { return }

        let keys: Keys
        do {
            keys = try KeyManager.loadOrCreate().signingKeys()
        } catch {
            errorMessage = "Could not load keys."
            return
        }

        // Optimistic: append immediately, clear input
        let ownHex = keys.publicKey().toHex()
        let tempId = UUID().uuidString
        comments.append(CommentRow(
            id: tempId,
            pubkeyHex: ownHex,
            content: text,
            createdAt: Date()
        ))

        // Ensure own profile is in the lookup
        if profiles[ownHex] == nil, let cached = nostrService.profileCache[ownHex] {
            profiles[ownHex] = cached
        }

        commentText = ""
        isInputFocused = false

        // Publish in background (fire-and-forget)
        Task {
            do {
                if isTextNote {
                    try await nostrService.publishReply(keys: keys, content: text, replyTo: event)
                } else {
                    try await nostrService.publishComment(keys: keys, content: text, targetEvent: event)
                }
            } catch {
                // Remove optimistic comment on failure
                comments.removeAll { $0.id == tempId }
                errorMessage = "Failed to post."
            }
        }
    }

    // MARK: - Helpers

    private func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        if interval < 604800 { return "\(Int(interval / 86400))d" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Comment Row Model

private struct CommentRow: Identifiable {
    let id: String
    let pubkeyHex: String
    let content: String
    let createdAt: Date
}
