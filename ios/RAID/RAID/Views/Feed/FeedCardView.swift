// FeedCardView.swift
// RAID Golf
//
// Individual feed item card: text note or rich scorecard.

import SwiftUI

struct FeedCardView: View {
    let item: FeedItem
    let profile: NostrProfile?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: avatar + name + time
            HStack(alignment: .top, spacing: 10) {
                ProfileAvatarView(pictureURL: profile?.picture, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile?.displayLabel ?? String(item.pubkeyHex.prefix(8)) + "...")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }

                Spacer()

                Text(relativeTime(item.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Content
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
        }
        .padding(.vertical, 12)
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
