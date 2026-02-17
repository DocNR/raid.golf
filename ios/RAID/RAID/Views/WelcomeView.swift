// WelcomeView.swift
// RAID Golf
//
// Onboarding root — 3-path welcome screen (O-1).
// Replaces FirstRunSheetView.

import SwiftUI

struct WelcomeView: View {
    let onComplete: (_ activated: Bool) -> Void

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
                            description: "See rounds and posts from golfers you follow."
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

                    // CTAs
                    VStack(spacing: 12) {
                        NavigationLink {
                            OnboardingProfileSetupView(onComplete: onComplete)
                        } label: {
                            Text("Create Account")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        NavigationLink {
                            OnboardingKeyImportView(onComplete: onComplete)
                        } label: {
                            Text("Sign In")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                        Button {
                            onComplete(false)
                        } label: {
                            Text("Skip for Now")
                                .font(.subheadline)
                        }
                        .padding(.top, 4)
                    }

                    Text("No email or password required.\nYour data stays on your device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
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
