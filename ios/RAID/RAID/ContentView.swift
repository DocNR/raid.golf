// ContentView.swift
// RAID Golf
//
// 3-tab layout (Feed, Play, Courses) with side drawer overlay.

import SwiftUI
import GRDB

struct ContentView: View {
    let dbQueue: DatabaseQueue

    @Environment(\.drawerState) private var drawerState
    @Environment(\.nostrService) private var nostrService
    @AppStorage("hasSeenFirstRun") private var hasSeenFirstRun = false
    @State private var showFirstRun = false
    @State private var selectedTab: Tab = .play

    enum Tab: String {
        case feed, play, courses
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Main content
            TabView(selection: $selectedTab) {
                FeedView()
                    .tabItem {
                        Label("Feed", systemImage: "bubble.left.and.bubble.right.fill")
                    }
                    .tag(Tab.feed)

                RoundsView(dbQueue: dbQueue)
                    .tabItem {
                        Label("Play", systemImage: "flag.fill")
                    }
                    .tag(Tab.play)

                CoursesView()
                    .tabItem {
                        Label("Courses", systemImage: "mappin.and.ellipse")
                    }
                    .tag(Tab.courses)
            }
            .disabled(drawerState.isOpen)

            // Scrim (tap to dismiss drawer)
            if drawerState.isOpen {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        drawerState.close()
                    }
            }

            // Side drawer
            SideDrawerView(dbQueue: dbQueue)
                .frame(width: 280)
                .offset(x: drawerState.isOpen ? 0 : -280)
                .ignoresSafeArea(edges: .vertical)
            // Full-screen profile (slides from trailing)
            if drawerState.showProfile {
                ProfileView(dbQueue: dbQueue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemBackground))
                    .transition(.move(edge: .trailing))
                    .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: drawerState.showProfile)
        // Drawer-driven sheets (presented at root level)
        .sheet(isPresented: Bindable(drawerState).showPractice) {
            PracticeView(dbQueue: dbQueue)
        }
        .sheet(isPresented: Bindable(drawerState).showKeysRelays) {
            NostrProfileView()
        }
        .sheet(isPresented: Bindable(drawerState).showAbout) {
            AboutView()
        }
        // First-run sheet
        .sheet(isPresented: $showFirstRun, onDismiss: {
            hasSeenFirstRun = true
        }) {
            FirstRunSheetView()
        }
        .onAppear {
            if !hasSeenFirstRun {
                showFirstRun = true
            }
        }
        .task {
            await fetchOwnProfile()
        }
    }

    private func fetchOwnProfile() async {
        guard let keyManager = try? KeyManager.loadOrCreate() else { return }
        let hex = keyManager.signingKeys().publicKey().toHex()
        if let profiles = try? await nostrService.resolveProfiles(pubkeyHexes: [hex]) {
            drawerState.ownProfile = profiles[hex]
        }
    }
}

#Preview {
    let dbQueue = try! DatabaseQueue.createRAIDDatabase(at: ":memory:")
    return ContentView(dbQueue: dbQueue)
}
