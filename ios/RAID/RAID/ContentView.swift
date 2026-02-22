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
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("nostrActivated") private var nostrActivated = false
    @State private var showOnboarding = false
    @State private var selectedTab: Tab = .play

    enum Tab: String {
        case feed, play, courses
    }

    /// Custom binding that detects a tap on the already-selected Feed tab
    /// and posts a scroll-to-top notification.
    private var tabBinding: Binding<Tab> {
        Binding(
            get: { selectedTab },
            set: { newTab in
                if newTab == .feed && selectedTab == .feed {
                    NotificationCenter.default.post(name: .feedScrollToTop, object: nil)
                }
                selectedTab = newTab
            }
        )
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Main content
            TabView(selection: tabBinding) {
                FeedView(dbQueue: dbQueue)
                    .tabItem { Image(systemName: "bubble.left.and.bubble.right.fill") }
                    .tag(Tab.feed)

                RoundsView(dbQueue: dbQueue)
                    .tabItem { Image(systemName: "flag.fill") }
                    .tag(Tab.play)

                CoursesView(dbQueue: dbQueue) { roundId, courseHash, playerPubkeys, isMultiDevice in
                    selectedTab = .play
                    let info = CourseRoundInfo(roundId: roundId, courseHash: courseHash, playerPubkeys: playerPubkeys, isMultiDevice: isMultiDevice)
                    NotificationCenter.default.post(name: .roundCreatedFromCourses, object: info)
                }
                    .tabItem { Image(systemName: "mappin.and.ellipse") }
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
        .sheet(isPresented: Bindable(drawerState).showPeople) {
            PeopleView(dbQueue: dbQueue)
        }
        .sheet(isPresented: Bindable(drawerState).showKeysRelays) {
            NostrProfileView(dbQueue: dbQueue)
        }
        .sheet(isPresented: Bindable(drawerState).showAbout) {
            AboutView()
        }
        // Onboarding full-screen cover
        .fullScreenCover(isPresented: $showOnboarding) {
            WelcomeView { activated in
                nostrActivated = activated
                hasCompletedOnboarding = true
                showOnboarding = false
            }
        }
        .onAppear {
            migrateOnboardingFlags()
            if !hasCompletedOnboarding {
                showOnboarding = true
            }
        }
        .onChange(of: hasCompletedOnboarding) { _, newValue in
            if !newValue {
                // Delay to let drawer/sheet dismiss animations complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    showOnboarding = true
                }
            }
        }
        .task {
            if nostrActivated {
                await fetchOwnProfile()
            }
        }
    }

    /// Migrate from legacy hasSeenFirstRun flag to new onboarding flags.
    /// Existing users who already saw the first-run sheet skip onboarding entirely.
    private func migrateOnboardingFlags() {
        let legacyFlag = UserDefaults.standard.bool(forKey: "hasSeenFirstRun")
        guard legacyFlag, !hasCompletedOnboarding else { return }

        hasCompletedOnboarding = true
        // If user already has a key in Keychain, they've used Nostr features
        if KeyManager.hasExistingKey() {
            nostrActivated = true
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
