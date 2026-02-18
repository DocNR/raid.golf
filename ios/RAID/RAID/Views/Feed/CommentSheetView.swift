// CommentSheetView.swift
// RAID Golf
//
// Threaded comments on a feed item (NIP-22, kind 1111).

import SwiftUI
import GRDB
import NostrSDK

struct CommentSheetView: View {
    let eventId: String
    let rawEvent: Event?
    let dbQueue: DatabaseQueue

    @Environment(\.dismiss) private var dismiss
    @Environment(\.nostrService) private var nostrService

    @State private var comments: [CommentRow] = []
    @State private var profiles: [String: NostrProfile] = [:]
    @State private var commentText = ""
    @State private var isLoading = false
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading && comments.isEmpty {
                    Spacer()
                    ProgressView("Loading comments...")
                    Spacer()
                } else if comments.isEmpty {
                    Spacer()
                    ContentUnavailableView {
                        Label("No Comments", systemImage: "bubble.left")
                    } description: {
                        Text("Be the first to comment.")
                    }
                    Spacer()
                } else {
                    commentList
                }

                Divider()
                inputBar
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let error = errorMessage { Text(error) }
            }
            .task { await loadComments() }
        }
    }

    // MARK: - Comment List

    private var commentList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(comments) { comment in
                    commentRow(comment)
                }
            }
            .padding()
        }
    }

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
            TextField("Add a comment...", text: $commentText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)

            Button {
                Task { await sendComment() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : Color.accentColor)
            }
            .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Data

    private func loadComments() async {
        isLoading = true
        do {
            let events = try await nostrService.fetchComments(eventId: eventId)
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

            comments = rows

            // Resolve profiles
            if !pubkeys.isEmpty {
                let cacheRepo = ProfileCacheRepository(dbQueue: dbQueue)
                if let resolved = try? await nostrService.resolveProfiles(
                    pubkeyHexes: Array(pubkeys), cacheRepo: cacheRepo
                ) {
                    profiles = resolved
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func sendComment() async {
        let text = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let event = rawEvent else { return }

        isSending = true
        do {
            let keys = try KeyManager.loadOrCreate().signingKeys()
            try await nostrService.publishComment(keys: keys, content: text, targetEvent: event)

            // Optimistic append
            let ownHex = keys.publicKey().toHex()
            comments.append(CommentRow(
                id: UUID().uuidString,
                pubkeyHex: ownHex,
                content: text,
                createdAt: Date()
            ))
            commentText = ""
        } catch {
            errorMessage = "Failed to post comment."
        }
        isSending = false
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
}

// MARK: - Comment Row Model

private struct CommentRow: Identifiable {
    let id: String
    let pubkeyHex: String
    let content: String
    let createdAt: Date
}
