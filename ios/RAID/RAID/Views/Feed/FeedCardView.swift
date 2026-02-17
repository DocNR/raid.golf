// FeedCardView.swift
// RAID Golf
//
// Individual feed item card: text note or rich scorecard.

import SwiftUI

struct FeedCardView: View {
    let item: FeedItem
    let profile: NostrProfile?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ProfileAvatarView(pictureURL: profile?.picture, size: 40)

            VStack(alignment: .leading, spacing: 4) {
                // Name · time
                HStack(spacing: 4) {
                    Text(profile?.displayLabel ?? String(item.pubkeyHex.prefix(8)) + "...")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Text("·")
                        .foregroundStyle(.secondary)

                    Text(relativeTime(item.createdAt))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()
                }

                // Content
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
