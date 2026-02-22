// CourseDetailView.swift
// RAID Golf
//
// Course detail with hero image, tee picker, collapsible scorecard, and Start Round.
// Derives CourseSnapshotInput from ParsedCourse + selected tee,
// then creates round via frozen kernel path.

import SwiftUI
import GRDB
import NostrSDK

struct CourseDetailView: View {
    let course: ParsedCourse
    let dbQueue: DatabaseQueue
    let onRoundCreated: (Int64, String, [String], Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.nostrService) private var nostrService

    @State private var selectedTee: ParsedCourse.ParsedTee?
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var showScorecard = false

    // Player selection
    @State private var hasNostrKeys = false
    @State private var creatorPubkeyHex: String?
    @State private var selectedPlayers: [String: NostrProfile] = [:]
    @State private var isMultiDevice = false
    @State private var showPlayerPicker = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                heroImage
                courseMetadata
                teePickerCard
                scorecardSection
                playersCard
                startRoundButton
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(course.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedTee == nil, let first = course.tees.first {
                selectedTee = first
            }
            checkNostrKeys()
        }
        .sheet(isPresented: $showPlayerPicker) {
            PlayerPickerSheet(
                dbQueue: dbQueue,
                creatorPubkeyHex: creatorPubkeyHex,
                selectedPlayers: $selectedPlayers
            )
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

    // MARK: - Player Labels for Scorecard

    private var playerLabelsForScorecard: [String] {
        guard !selectedPlayers.isEmpty else { return [] }
        return Array(selectedPlayers.values)
            .sorted { $0.displayLabel < $1.displayLabel }
            .map { $0.displayLabel }
    }

    // MARK: - Hero Image

    @ViewBuilder
    private var heroImage: some View {
        if let urlString = course.imageURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 200)
                        .clipped()
                case .failure:
                    imagePlaceholder
                case .empty:
                    imagePlaceholder
                        .overlay(ProgressView())
                @unknown default:
                    imagePlaceholder
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: ScorecardLayout.miniCardCornerRadius))
        }
    }

    @ViewBuilder
    private var imagePlaceholder: some View {
        LinearGradient(
            colors: [Color.green.opacity(0.3), Color.green.opacity(0.1)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(height: 200)
    }

    // MARK: - Course Metadata (inline, no card)

    @ViewBuilder
    private var courseMetadata: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(course.location)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let content = course.content, !content.isEmpty {
                Text(content)
                    .font(.subheadline)
            }

            HStack(spacing: 16) {
                if let architect = course.architect {
                    Label(architect, systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let year = course.established {
                    Label(year, systemImage: "calendar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let website = course.website, let url = URL(string: website) {
                    Link(destination: url) {
                        Label("Website", systemImage: "globe")
                            .font(.caption)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Tee Picker Card

    @ViewBuilder
    private var teePickerCard: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Tees")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Picker("Tees", selection: $selectedTee) {
                    ForEach(course.tees, id: \.self) { tee in
                        Text(tee.name).tag(Optional(tee))
                    }
                }
                .pickerStyle(.menu)
                .tint(.primary)
            }

            if let tee = selectedTee {
                HStack(spacing: 16) {
                    Label("Rating \(tee.rating, specifier: "%.1f")", systemImage: "chart.bar")
                    Label("Slope \(tee.slope)", systemImage: "arrow.up.right")
                    Spacer()
                    let yards = course.totalYardage(forTee: tee.name)
                    if yards > 0 {
                        Text("\(yards) yds")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .scorecardCardStyle()
    }

    // MARK: - Scorecard (Collapsible)

    @ViewBuilder
    private var scorecardSection: some View {
        if let tee = selectedTee {
            DisclosureGroup("Scorecard", isExpanded: $showScorecard) {
                CourseScorecardPreview(
                    course: course,
                    teeName: tee.name,
                    playerLabels: playerLabelsForScorecard
                )
                .padding(.top, 8)
            }
            .font(.subheadline.weight(.medium))
            .tint(.secondary)
            .padding()
            .scorecardCardStyle()
        }
    }

    // MARK: - Players Card

    @ViewBuilder
    private var playersCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Players")
                    .font(.subheadline.weight(.medium))
                if !selectedPlayers.isEmpty {
                    Text("(\(selectedPlayers.count))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if !hasNostrKeys {
                Text("Set up Nostr identity to invite players")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                Button {
                    showPlayerPicker = true
                } label: {
                    HStack(spacing: 10) {
                        if selectedPlayers.isEmpty {
                            Label("Add Playing Partners", systemImage: "person.badge.plus")
                        } else {
                            playerSummaryRow
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.primary)
                }

                if !selectedPlayers.isEmpty {
                    Toggle("Each player uses their own device", isOn: $isMultiDevice)
                        .font(.subheadline)
                }
            }

            if hasNostrKeys {
                Text("Optional. Select playing partners or add by npub.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .scorecardCardStyle()
    }

    // MARK: - Player Summary Row

    private var playerSummaryRow: some View {
        HStack(spacing: 6) {
            HStack(spacing: -8) {
                ForEach(playerSummaryAvatars()) { profile in
                    ProfileAvatarView(pictureURL: profile.picture, size: 28)
                        .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 1.5))
                }
            }
            Text(playerSummaryLabel())
                .font(.subheadline)
                .lineLimit(1)
        }
    }

    private func playerSummaryLabel() -> String {
        let sorted = Array(selectedPlayers.values).sorted { $0.displayLabel < $1.displayLabel }
        let names: [String] = sorted.prefix(2).map { $0.displayLabel }
        let overflow = sorted.count - 2
        if overflow > 0 {
            return names.joined(separator: ", ") + " +\(overflow) more"
        }
        return names.joined(separator: ", ")
    }

    private func playerSummaryAvatars() -> [NostrProfile] {
        Array(selectedPlayers.values)
            .sorted { $0.displayLabel < $1.displayLabel }
            .prefix(3)
            .map { $0 }
    }

    // MARK: - Start Round Button

    @ViewBuilder
    private var startRoundButton: some View {
        Button {
            startRound()
        } label: {
            if isCreating {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                Text("Start Round")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .controlSize(.large)
        .disabled(selectedTee == nil || isCreating)
    }

    // MARK: - Actions

    private func checkNostrKeys() {
        hasNostrKeys = KeyManager.hasExistingKey()
        if hasNostrKeys {
            creatorPubkeyHex = (try? KeyManager.loadOrCreate())?.signingKeys().publicKey().toHex()
        }
    }

    private func startRound() {
        guard let tee = selectedTee else { return }
        isCreating = true

        do {
            let holes = course.holes.map {
                HoleDefinition(holeNumber: $0.number, par: $0.par)
            }
            let courseInput = CourseSnapshotInput(
                courseName: course.title,
                teeSet: tee.name,
                holes: holes
            )
            let courseRepo = CourseSnapshotRepository(dbQueue: dbQueue)
            let courseSnapshot = try courseRepo.insertCourseSnapshot(courseInput)

            let roundDate = ISO8601DateFormatter().string(from: Date())
            let roundRepo = RoundRepository(dbQueue: dbQueue)
            let round = try roundRepo.createRound(
                courseHash: courseSnapshot.courseHash,
                roundDate: roundDate
            )

            var allPlayerPubkeys: [String] = []
            if let creatorHex = creatorPubkeyHex {
                let otherPubkeys = Array(selectedPlayers.keys)
                let playerRepo = RoundPlayerRepository(dbQueue: dbQueue)
                try playerRepo.insertPlayers(
                    roundId: round.roundId,
                    creatorPubkey: creatorHex,
                    otherPubkeys: otherPubkeys
                )
                allPlayerPubkeys = [creatorHex] + otherPubkeys
            }

            onRoundCreated(round.roundId, courseSnapshot.courseHash, allPlayerPubkeys, isMultiDevice)

        } catch {
            isCreating = false
            errorMessage = error.localizedDescription
        }
    }
}
