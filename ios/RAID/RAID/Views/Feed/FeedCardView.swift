// FeedCardView.swift
// RAID Golf
//
// Individual feed item card: text note or rich scorecard.

import SwiftUI

struct FeedCardView: View {
    let item: FeedItem
    let profile: NostrProfile?

    private let avatarSize: CGFloat = 40
    private let avatarSpacing: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header: avatar + name · time (center-aligned row)
            HStack(spacing: avatarSpacing) {
                ProfileAvatarView(pictureURL: profile?.picture, size: avatarSize)

                Text(profile?.displayLabel ?? String(item.pubkeyHex.prefix(8)) + "...")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text("·")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(relativeTime(item.createdAt))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            // Content — indented to align under the name
            Group {
                switch item {
                case .textNote(_, _, let content, _):
                    Text(content)
                        .font(.subheadline)

                case .scorecard(_, _, let commentary, let record, let courseInfo, _):
                    if let commentary, !commentary.isEmpty {
                        Text(commentary)
                            .font(.subheadline)
                    }
                    ScorecardCardView(record: record, courseInfo: courseInfo)
                }
            }
            .padding(.leading, avatarSize + avatarSpacing)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Relative Time

    private func relativeTime(_ date: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(date)

        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        if interval < 172800 { return "Yesterday" }
        if interval < 604800 { return "\(Int(interval / 86400))d" }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
}
