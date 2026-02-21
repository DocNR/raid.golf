// DrawerState.swift
// RAID Golf
//
// Shared observable for side drawer state, accessible from all tabs.

import SwiftUI

@Observable
class DrawerState {
    var isOpen: Bool = false
    var ownProfile: NostrProfile?

    // Navigation state
    var showProfile: Bool = false

    // Sheet presentation state (driven from drawer menu taps)
    var showPractice: Bool = false
    var showPeople: Bool = false
    var showKeysRelays: Bool = false
    var showAbout: Bool = false

    func toggle() {
        withAnimation(.easeInOut(duration: 0.25)) {
            isOpen.toggle()
        }
    }

    func close() {
        guard isOpen else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            isOpen = false
        }
    }
}

// MARK: - Environment Key

private struct DrawerStateKey: EnvironmentKey {
    static let defaultValue = DrawerState()
}

extension EnvironmentValues {
    var drawerState: DrawerState {
        get { self[DrawerStateKey.self] }
        set { self[DrawerStateKey.self] = newValue }
    }
}
