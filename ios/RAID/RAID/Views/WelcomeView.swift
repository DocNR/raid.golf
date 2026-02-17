// WelcomeView.swift
// RAID Golf
//
// Onboarding root — 3-path welcome screen (O-1).

import SwiftUI

struct WelcomeView: View {
    let onComplete: (_ activated: Bool) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 40) {
                Spacer()

                // Logo area
                VStack(spacing: 12) {
                    Text("RAID")
                        .font(.system(size: 48, weight: .bold, design: .default))
                    Text("Golf, on Nostr.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Spacer()

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
                        Text("Skip")
                            .font(.subheadline)
                    }
                    .padding(.top, 4)
                }

                Text("No email or password needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
        }
        .interactiveDismissDisabled()
    }
}
