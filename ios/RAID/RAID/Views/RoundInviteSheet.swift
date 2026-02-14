// RoundInviteSheet.swift
// Gambit Golf
//
// Displays a round invite as a QR code + copyable nevent string.
// Used during active rounds to share the invite with other players.

import SwiftUI

struct RoundInviteSheet: View {
    let nevent: String
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var nostrURI: String {
        RoundInviteBuilder.buildNostrURI(nevent: nevent)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Share this invite with other players so they can join your round.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                // QR Code
                if let image = QRCodeGenerator.generate(from: nostrURI, size: 200) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .padding()
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Copyable nevent string
                VStack(spacing: 8) {
                    Text("Invite Code")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(nevent)
                        .font(.system(.caption2, design: .monospaced))
                        .lineLimit(3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button {
                        UIPasteboard.general.string = nevent
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copied = false
                        }
                    } label: {
                        Label(copied ? "Copied!" : "Copy Invite Code", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                // System share sheet
                ShareLink(item: nevent) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .padding(.bottom)
            }
            .padding(.top)
            .navigationTitle("Round Invite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
