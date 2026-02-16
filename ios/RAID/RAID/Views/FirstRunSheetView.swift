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
                        Text("Track your practice, score your rounds, and measure what matters.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 24)

                    // Feature cards
                    VStack(spacing: 16) {
                        FeatureCard(
                            icon: "chart.line.uptrend.xyaxis",
                            color: .blue,
                            title: "Practice",
                            description: "Import Rapsodo CSV files to track your range sessions. Shots are graded A/B/C against your KPI templates."
                        )

                        FeatureCard(
                            icon: "flag.fill",
                            color: .green,
                            title: "Rounds",
                            description: "Score your rounds hole-by-hole. Track your scores over time."
                        )

                        FeatureCard(
                            icon: "list.clipboard",
                            color: .orange,
                            title: "Templates",
                            description: "KPI templates define what makes an A, B, or C shot. A starter template for 7-iron is already set up."
                        )
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
