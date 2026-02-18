// NostrActivationAlert.swift
// RAID Golf
//
// Reusable activation prompt for guest users attempting Nostr features.

import SwiftUI

struct NostrActivationAlert: ViewModifier {
    @Binding var isPresented: Bool
    let message: String
    let onActivate: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("Enable Nostr", isPresented: $isPresented) {
                Button("Set Up") { onActivate() }
                Button("Not Now", role: .cancel) { }
            } message: {
                Text(message)
            }
    }
}

extension View {
    func nostrActivationAlert(
        isPresented: Binding<Bool>,
        message: String,
        onActivate: @escaping () -> Void
    ) -> some View {
        modifier(NostrActivationAlert(
            isPresented: isPresented,
            message: message,
            onActivate: onActivate
        ))
    }
}
