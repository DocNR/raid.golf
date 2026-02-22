// CoursesView.swift
// RAID Golf
//
// Course discovery and browsing via kind 33501 events.
// Segmented picker: All Courses | My Courses.
// Two-phase load: cache paint → relay sync.
// Includes course request via NIP-17 DM to the RAID bot.

import SwiftUI
import GRDB
import NostrSDK

private enum CourseSegment: String, CaseIterable {
    case myCourses = "My Courses"
    case allCourses = "All Courses"
}

struct CoursesView: View {
    let dbQueue: DatabaseQueue
    let onRoundCreated: (Int64, String, [String], Bool) -> Void

    @Environment(\.nostrService) private var nostrService
    @AppStorage("nostrActivated") private var nostrActivated = false
    @AppStorage("nostrReadOnly") private var nostrReadOnly = false

    @State private var viewModel = CoursesViewModel()
    @State private var showRequestSheet = false
    @State private var requestSent = false
    @State private var errorMessage: String?

    // Favorites state
    @State private var selectedSegment: CourseSegment = .myCourses
    @State private var favoriteIdentifiers: Set<String> = []
    @State private var myCourses: [ParsedCourse] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                segmentedPicker
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                Group {
                    if viewModel.isLoading && viewModel.courses.isEmpty {
                        ProgressView("Loading courses...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        courseContent
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .avatarToolbar()
            .searchable(text: $viewModel.searchQuery, prompt: searchPrompt)
            .task {
                loadFavorites()
                let cacheRepo = CourseCacheRepository(dbQueue: dbQueue)
                await viewModel.loadIfNeeded(nostrService: nostrService, cacheRepo: cacheRepo)
                await syncFavoritesFromRelay()
            }
            .refreshable {
                let cacheRepo = CourseCacheRepository(dbQueue: dbQueue)
                await viewModel.refresh(nostrService: nostrService, cacheRepo: cacheRepo)
                loadFavorites()
            }
            .sheet(isPresented: $showRequestSheet) {
                CourseRequestSheet(
                    nostrService: nostrService,
                    onSuccess: {
                        requestSent = true
                        showRequestSheet = false
                    },
                    onError: { message in
                        errorMessage = message
                        showRequestSheet = false
                    }
                )
            }
            .alert("Request Sent", isPresented: $requestSent) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("You'll receive a DM when the course is ready.")
            }
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Segmented Picker

    private var segmentedPicker: some View {
        Picker("", selection: $selectedSegment) {
            ForEach(CourseSegment.allCases, id: \.self) { segment in
                Text(segment.rawValue).tag(segment)
            }
        }
        .pickerStyle(.segmented)
    }

    private var searchPrompt: String {
        selectedSegment == .myCourses ? "Search My Courses" : "Search All Courses"
    }

    // MARK: - Content

    @ViewBuilder
    private var courseContent: some View {
        switch selectedSegment {
        case .allCourses:
            allCoursesList
        case .myCourses:
            myCoursesList
        }
    }

    // MARK: - All Courses List

    @ViewBuilder
    private var allCoursesList: some View {
        if viewModel.courses.isEmpty {
            emptyState
        } else {
            List {
                if viewModel.isBackgroundRefreshing {
                    backgroundRefreshRow
                }

                ForEach(viewModel.filteredCourses) { course in
                    NavigationLink {
                        CourseDetailView(
                            course: course,
                            dbQueue: dbQueue,
                            onRoundCreated: onRoundCreated,
                            isFavorited: isFavorited(course),
                            onFavoriteToggle: { toggleFavorite(course) }
                        )
                    } label: {
                        courseRow(course)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            toggleFavorite(course)
                        } label: {
                            Label(
                                isFavorited(course) ? "Remove" : "Add",
                                systemImage: isFavorited(course) ? "star.slash" : "star"
                            )
                        }
                        .tint(.orange)
                    }
                }

                courseRequestListSection
            }
        }
    }

    // MARK: - My Courses List

    @ViewBuilder
    private var myCoursesList: some View {
        if myCourses.isEmpty && !viewModel.isLoading {
            myCoursesEmptyState
        } else {
            List {
                ForEach(filteredMyCourses) { course in
                    NavigationLink {
                        CourseDetailView(
                            course: course,
                            dbQueue: dbQueue,
                            onRoundCreated: onRoundCreated,
                            isFavorited: true,
                            onFavoriteToggle: { toggleFavorite(course) }
                        )
                    } label: {
                        courseRow(course)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            toggleFavorite(course)
                        } label: {
                            Label("Remove", systemImage: "star.slash")
                        }
                    }
                }
            }
        }
    }

    private var filteredMyCourses: [ParsedCourse] {
        let q = viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return myCourses }
        return myCourses.filter {
            $0.title.lowercased().contains(q) || $0.location.lowercased().contains(q)
        }
    }

    // MARK: - My Courses Empty State

    @ViewBuilder
    private var myCoursesEmptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "star")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Saved Courses")
                .font(.title3.bold())

            Text("Browse All Courses to find your home course, then swipe to add it here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                selectedSegment = .allCourses
            } label: {
                Label("Browse All Courses", systemImage: "list.bullet")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)

            Spacer()
        }
    }

    // MARK: - Course Row

    @ViewBuilder
    private func courseRow(_ course: ParsedCourse) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(course.title)
                    .font(.body.weight(.medium))
                Text(course.location)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text("\(course.holes.count) holes")
                    Text("\(course.tees.count) tee\(course.tees.count == 1 ? "" : "s")")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)

            Spacer()

            if selectedSegment == .allCourses && isFavorited(course) {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 24) {
                courseRequestSection
            }
            .padding()
        }
    }

    // MARK: - Course Request (empty state)

    @ViewBuilder
    private var courseRequestSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Courses")
                .font(.title2.bold())

            Text("No courses available yet. Request a course and we'll add it to the database.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            requestButton
        }
        .padding(.top, 40)
    }

    // MARK: - Course Request (list footer)

    @ViewBuilder
    private var courseRequestListSection: some View {
        Section {
            VStack(spacing: 8) {
                Text("Don't see your course?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                requestButton
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var requestButton: some View {
        if nostrActivated && !nostrReadOnly {
            Button {
                showRequestSheet = true
            } label: {
                Label("Request a Course", systemImage: "plus.circle")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        } else if nostrReadOnly {
            Text("Sign in with your secret key to request courses.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("Set up a Nostr identity to request courses.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Background Refresh Row

    private var backgroundRefreshRow: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Updating...")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .listRowBackground(Color.clear)
    }

    // MARK: - Favorites Logic

    private func favoriteKey(_ course: ParsedCourse) -> String {
        "\(course.dTag):\(course.authorHex)"
    }

    private func isFavorited(_ course: ParsedCourse) -> Bool {
        favoriteIdentifiers.contains(favoriteKey(course))
    }

    private func toggleFavorite(_ course: ParsedCourse) {
        let repo = CourseFavoritesRepository(dbQueue: dbQueue)
        let key = favoriteKey(course)

        if favoriteIdentifiers.contains(key) {
            try? repo.remove(dTag: course.dTag, authorHex: course.authorHex)
            favoriteIdentifiers.remove(key)
        } else {
            try? repo.add(dTag: course.dTag, authorHex: course.authorHex)
            favoriteIdentifiers.insert(key)
        }

        // Reload my courses list
        loadMyCourses()

        // Publish to relay (fire-and-forget)
        if nostrActivated && !nostrReadOnly {
            Task {
                guard let keys = try? KeyManager.loadOrCreate().signingKeys() else { return }
                let allFavs = (try? repo.allIdentifiers()) ?? []
                try? await nostrService.publishCourseFavorites(keys: keys, favorites: allFavs)
            }
        }
    }

    private func loadFavorites() {
        let repo = CourseFavoritesRepository(dbQueue: dbQueue)
        if let all = try? repo.fetchAll() {
            favoriteIdentifiers = Set(all.map { "\($0.dTag):\($0.authorHex)" })
        }
        loadMyCourses()
    }

    private func loadMyCourses() {
        let cacheRepo = CourseCacheRepository(dbQueue: dbQueue)
        myCourses = (try? cacheRepo.fetchMyCourses()) ?? []
    }

    private func syncFavoritesFromRelay() async {
        guard nostrActivated else { return }
        guard let pubkeyHex = KeyManager.publicKeyHex() else { return }

        do {
            let remote = try await nostrService.fetchCourseFavorites(pubkeyHex: pubkeyHex)
            guard !remote.isEmpty else { return }

            let repo = CourseFavoritesRepository(dbQueue: dbQueue)
            let localIds = (try? repo.allIdentifiers()) ?? []
            let localSet = Set(localIds.map { "\($0.dTag):\($0.authorHex)" })
            let remoteSet = Set(remote.map { "\($0.dTag):\($0.authorHex)" })

            if localSet != remoteSet {
                try repo.replaceAll(identifiers: remote)
                loadFavorites()
            }
        } catch {
            print("[RAID] Course favorites sync failed: \(error)")
        }
    }
}

// MARK: - Course Request Sheet

private struct CourseRequestSheet: View {
    let nostrService: NostrService
    let onSuccess: () -> Void
    let onError: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var courseName = ""
    @State private var city = ""
    @State private var state = ""
    @State private var website = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Course Name", text: $courseName)
                        .textContentType(.organizationName)
                        .autocorrectionDisabled()
                    TextField("City", text: $city)
                        .textContentType(.addressCity)
                    TextField("State", text: $state)
                        .textContentType(.addressState)
                        .autocapitalization(.allCharacters)
                } header: {
                    Text("Course Details")
                } footer: {
                    Text("Enter the course name and location. We'll look it up and add the full scorecard data.")
                }

                Section {
                    TextField("https://", text: $website)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                } header: {
                    Text("Scorecard Link (Optional)")
                } footer: {
                    Text("Direct link to the course scorecard page helps us add it faster.")
                }
            }
            .navigationTitle("Request a Course")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        Task { await sendRequest() }
                    }
                    .disabled(!isValid)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var isValid: Bool {
        !courseName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !city.trimmingCharacters(in: .whitespaces).isEmpty &&
        !state.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func sendRequest() async {
        guard KeyManager.hasExistingKey() else {
            onError("No Nostr keys found. Please set up your identity first.")
            return
        }

        do {
            let keyManager = try KeyManager.loadOrCreate()
            let keys = keyManager.signingKeys()

            let trimmedWebsite = website.trimmingCharacters(in: .whitespaces)
            let rumor = try CourseRequestBuilder.buildCourseRequestRumor(
                senderPubkey: keys.publicKey(),
                botPubkeyHex: RAIDBot.pubkeyHex,
                courseName: courseName.trimmingCharacters(in: .whitespaces),
                city: city.trimmingCharacters(in: .whitespaces),
                state: state.trimmingCharacters(in: .whitespaces),
                website: trimmedWebsite.isEmpty ? nil : trimmedWebsite
            )

            // Optimistic: dismiss immediately, send in background
            onSuccess()

            let service = nostrService
            Task.detached {
                try? await service.sendGiftWrapDM(
                    senderKeys: keys,
                    receiverPubkeyHex: RAIDBot.pubkeyHex,
                    rumor: rumor
                )
            }
        } catch {
            onError("Failed to build request: \(error.localizedDescription)")
        }
    }
}
