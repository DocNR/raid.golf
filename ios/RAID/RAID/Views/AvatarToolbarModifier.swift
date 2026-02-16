// AvatarToolbarModifier.swift
// RAID Golf
//
// ViewModifier that adds the profile avatar button to any NavigationStack's toolbar.
// Tapping opens the side drawer.

import SwiftUI

struct AvatarToolbarModifier: ViewModifier {
    @Environment(\.drawerState) private var drawerState

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        drawerState.toggle()
                    } label: {
                        ProfileAvatarView(
                            pictureURL: drawerState.ownProfile?.picture,
                            size: 28
                        )
                    }
                }
            }
    }
}

extension View {
    func avatarToolbar() -> some View {
        modifier(AvatarToolbarModifier())
    }
}
