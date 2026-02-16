// FirstRunSheetView.swift
// RAID Golf
//
// One-time welcome sheet shown on first launch.

import SwiftUI

struct FirstRunSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Welcome to RAID Golf")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        Text("Score your rounds, follow golfers, and discover courses.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 24)

                    // Feature cards
                    VStack(spacing: 16) {
                        FeatureCard(
                            icon: "bubble.left.and.bubble.right.fill",
                            color: .blue,
                            title: "Feed",
                            description: "See rounds and posts from golfers you follow on Nostr."
                        )

                        FeatureCard(
                            icon: "flag.fill",
                            color: .green,
                            title: "Play",
                            description: "Score your rounds hole-by-hole. Invite friends to play together across devices."
                        )

                        FeatureCard(
                            icon: "mappin.and.ellipse",
                            color: .orange,
                            title: "Courses",
                            description: "Browse courses, check tee sets, and see who's playing."
                        )

                        Text("Practice sessions, trends, and templates are in the side menu.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    // CTA
                    Button {
                        dismiss()
                    } label: {
                        Text("Get Started")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .interactiveDismissDisabled()
    }
}

// MARK: - Feature Card

private struct FeatureCard: View {
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
