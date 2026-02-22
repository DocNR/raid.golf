// CoursesView.swift
// RAID Golf
//
// Course discovery and browsing via kind 33501 events.
// Two-phase load: cache paint → relay sync.
// Includes course request via NIP-17 DM to the RAID bot.

import SwiftUI
import GRDB
import NostrSDK

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

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.courses.isEmpty {
                    ProgressView("Loading courses...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.courses.isEmpty {
                    emptyState
                } else {
                    courseList
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .avatarToolbar()
            .searchable(text: $viewModel.searchQuery, prompt: "Search courses")
            .task {
                let cacheRepo = CourseCacheRepository(dbQueue: dbQueue)
                await viewModel.loadIfNeeded(nostrService: nostrService, cacheRepo: cacheRepo)
            }
            .refreshable {
                let cacheRepo = CourseCacheRepository(dbQueue: dbQueue)
                await viewModel.refresh(nostrService: nostrService, cacheRepo: cacheRepo)
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

    // MARK: - Course List

    @ViewBuilder
    private var courseList: some View {
        List {
            if viewModel.isBackgroundRefreshing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Updating...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
            }

            ForEach(viewModel.filteredCourses) { course in
                NavigationLink {
                    CourseDetailView(
                        course: course,
                        dbQueue: dbQueue,
                        onRoundCreated: onRoundCreated
                    )
                } label: {
                    courseRow(course)
                }
            }

            courseRequestListSection
        }
    }

    @ViewBuilder
    private func courseRow(_ course: ParsedCourse) -> some View {
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
