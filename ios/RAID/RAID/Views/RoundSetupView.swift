// RoundSetupView.swift
// RAID Golf
//
// Unified round setup. Two modes:
// - Course mode (course != nil): read-only course info, tee picker, course holes
// - Manual mode (course == nil): text fields for course name/tee, hole picker, tap-to-cycle par grid
// Presented as a sheet from CourseDetailView, CoursesView, and RoundsView.

import SwiftUI
import GRDB
import NostrSDK

struct RoundSetupView: View {
    let dbQueue: DatabaseQueue
    let course: ParsedCourse?
    let preselectedTee: ParsedCourse.ParsedTee?
    let onRoundCreated: (Int64, String, [String], Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.nostrService) private var nostrService

    // Manual mode state
    @State private var courseName = ""
    @State private var teeSet = ""
    @State private var holeSelection: HoleSelection = .eighteen
    @State private var pars: [Int] = Array(repeating: 4, count: 18)

    // Course mode state
    @State private var selectedTee: ParsedCourse.ParsedTee?

    // Shared state
    @State private var selectedPlayers: [String: NostrProfile] = [:]
    @State private var isMultiDevice = false
    @State private var showPlayerPicker = false
    @State private var hasNostrKeys = false
    @State private var creatorPubkeyHex: String?
    @State private var isCreating = false
    @State private var errorMessage: String?

    private var isCourseMode: Bool { course != nil }

    var body: some View {
        NavigationStack {
            Form {
                courseInfoSection
                playersFormSection
                if !isCourseMode {
                    parGridSection
                }
            }
            .navigationTitle("New Round")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isCreating)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Start Round") { startRound() }
                        .disabled(!canStart || isCreating)
                }
            }
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let error = errorMessage { Text(error) }
            }
            .task {
                checkNostrKeys()
                seedProfileCache()
                if let tee = preselectedTee {
                    selectedTee = tee
                } else if let first = course?.tees.first {
                    selectedTee = first
                }
            }
            .sheet(isPresented: $showPlayerPicker) {
                PlayerPickerSheet(
                    dbQueue: dbQueue,
                    creatorPubkeyHex: creatorPubkeyHex,
                    selectedPlayers: $selectedPlayers
                )
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Can Start

    private var canStart: Bool {
        if isCourseMode {
            return selectedTee != nil
        } else {
            return !courseName.isEmpty && !teeSet.isEmpty
        }
    }

    // MARK: - Course Info Section

    @ViewBuilder
    private var courseInfoSection: some View {
        if let course = course {
            Section("Course") {
                LabeledContent("Course", value: course.title)
                LabeledContent("Location", value: course.location)
                LabeledContent("Holes", value: "\(course.holes.count)")

                Picker("Tees", selection: $selectedTee) {
                    ForEach(course.tees, id: \.self) { tee in
                        Text(tee.name).tag(Optional(tee))
                    }
                }

                if let tee = selectedTee {
                    HStack(spacing: 16) {
                        Text("Rating \(tee.rating, specifier: "%.1f")")
                        Text("Slope \(tee.slope)")
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
        } else {
            Section("Course Details") {
                TextField("Course Name", text: $courseName)
                TextField("Tee Set", text: $teeSet)
                Picker("Holes", selection: $holeSelection) {
                    Text("Front 9").tag(HoleSelection.front9)
                    Text("Back 9").tag(HoleSelection.back9)
                    Text("18").tag(HoleSelection.eighteen)
                }
                .onChange(of: holeSelection) { _, newValue in
                    adjustParsArray(to: newValue.holeCount)
                }
            }
        }
    }

    // MARK: - Players (Form Section)

    @ViewBuilder
    private var playersFormSection: some View {
        Section {
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
                }
            }
        } header: {
            HStack {
                Text("Players")
                if !selectedPlayers.isEmpty {
                    Text("(\(selectedPlayers.count))")
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            if hasNostrKeys {
                Text("Optional. Select playing partners or add by npub.")
            }
        }
    }

    // MARK: - Player Summary

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

    // MARK: - Par Grid (Manual Mode Only)

    @ViewBuilder
    private var parGridSection: some View {
        Section {
            parEntryGrid
        } header: {
            Text("Par for Each Hole")
        } footer: {
            Text("Tap a par value to cycle 3 → 4 → 5")
        }
    }

    @ViewBuilder
    private var parEntryGrid: some View {
        let startHole = holeSelection.startingHole
        let count = holeSelection.holeCount
        let labelColumnWidth = ScorecardLayout.rowLabelWidth + 2 * ScorecardLayout.cellHPadding

        VStack(spacing: 10) {
            parEntryNineBlock(
                startIndex: 0,
                count: min(count, 9),
                startHole: startHole,
                summaryLabel: count > 9 ? "OUT" : "TOT",
                labelColumnWidth: labelColumnWidth
            )

            if count > 9 {
                parEntryNineBlock(
                    startIndex: 9,
                    count: count - 9,
                    startHole: startHole + 9,
                    summaryLabel: "IN",
                    labelColumnWidth: labelColumnWidth
                )

                parEntryTotalsRow(count: count, labelColumnWidth: labelColumnWidth)
            }
        }
    }

    @ViewBuilder
    private func parEntryNineBlock(startIndex: Int, count: Int, startHole: Int, summaryLabel: String, labelColumnWidth: CGFloat) -> some View {
        let ninePar = (startIndex..<startIndex + count).reduce(0) { $0 + pars[$1] }

        HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                parEntryRowLabel("HOLE", font: .caption2.weight(.semibold), foreground: .primary, height: ScorecardLayout.headerRowHeight, labelColumnWidth: labelColumnWidth)
                parEntryGridDivider
                parEntryRowLabel("Par", font: .caption2.weight(.bold), foreground: .primary, height: ScorecardLayout.scoreRowHeight, labelColumnWidth: labelColumnWidth)
            }
            .frame(width: labelColumnWidth)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(0..<count, id: \.self) { i in
                        Text("\(startHole + i)")
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                            .frame(width: ScorecardLayout.holeColumnWidth)
                    }
                    parEntrySummarySeparator
                    Text(summaryLabel)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: ScorecardLayout.summaryColumnWidth)
                        .background(Color(.tertiarySystemBackground))
                }
                .frame(height: ScorecardLayout.headerRowHeight)

                parEntryGridDivider

                HStack(spacing: 0) {
                    ForEach(0..<count, id: \.self) { i in
                        let index = startIndex + i
                        Button {
                            cyclePar(at: index)
                        } label: {
                            Text("\(pars[index])")
                                .font(.callout.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.primary)
                                .frame(width: ScorecardLayout.holeColumnWidth, height: ScorecardLayout.scoreRowHeight)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Hole \(startHole + i) par \(pars[index])")
                        .accessibilityAdjustableAction { direction in
                            switch direction {
                            case .increment:
                                pars[index] = pars[index] >= 5 ? 3 : pars[index] + 1
                            case .decrement:
                                pars[index] = pars[index] <= 3 ? 5 : pars[index] - 1
                            @unknown default: break
                            }
                        }
                    }
                    parEntrySummarySeparator
                    Text("\(ninePar)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.primary)
                        .frame(width: ScorecardLayout.summaryColumnWidth)
                        .background(Color(.tertiarySystemBackground))
                }
                .frame(height: ScorecardLayout.scoreRowHeight)
            }
        }
        .scorecardCardStyle()
    }

    @ViewBuilder
    private func parEntryTotalsRow(count: Int, labelColumnWidth: CGFloat) -> some View {
        let totalPar = pars.prefix(count).reduce(0, +)

        HStack {
            Text("TOTAL")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("Par \(totalPar)")
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 16)
        .frame(height: ScorecardLayout.headerRowHeight + 12)
        .scorecardCardStyle()
    }

    private func cyclePar(at index: Int) {
        pars[index] = pars[index] >= 5 ? 3 : pars[index] + 1
    }

    private var parEntryGridDivider: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(height: ScorecardLayout.gridLineWeight)
    }

    private var parEntrySummarySeparator: some View {
        Rectangle()
            .fill(Color(.separator))
            .frame(width: ScorecardLayout.gridSemanticDividerWeight)
    }

    private func parEntryRowLabel(_ text: String, font: Font, foreground: Color, height: CGFloat, labelColumnWidth: CGFloat) -> some View {
        Text(text)
            .font(font)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .frame(width: ScorecardLayout.rowLabelWidth, height: height, alignment: .center)
            .padding(.horizontal, ScorecardLayout.cellHPadding)
    }

    // MARK: - Helpers

    private func seedProfileCache() {
        let profiles = nostrService.profileCache
        guard !profiles.isEmpty else { return }
        let repo = ProfileCacheRepository(dbQueue: dbQueue)
        try? repo.upsertProfiles(Array(profiles.values))
    }

    private func checkNostrKeys() {
        guard UserDefaults.standard.bool(forKey: "nostrActivated") else {
            hasNostrKeys = false
            return
        }
        creatorPubkeyHex = KeyManager.publicKeyHex()
        hasNostrKeys = creatorPubkeyHex != nil
    }

    private func adjustParsArray(to newCount: Int) {
        if pars.count < newCount {
            pars.append(contentsOf: Array(repeating: 4, count: newCount - pars.count))
        } else if pars.count > newCount {
            pars = Array(pars.prefix(newCount))
        }
    }

    // MARK: - Round Creation

    private func startRound() {
        isCreating = true

        do {
            let holes: [HoleDefinition]
            let name: String
            let tee: String

            if let course = course, let selectedTee = selectedTee {
                // Course mode
                name = course.title
                tee = selectedTee.name
                holes = course.holes.map {
                    HoleDefinition(holeNumber: $0.number, par: $0.par)
                }
            } else {
                // Manual mode
                name = courseName
                tee = teeSet
                let startHole = holeSelection.startingHole
                holes = (0..<holeSelection.holeCount).map { index in
                    HoleDefinition(holeNumber: startHole + index, par: pars[index])
                }
            }

            let courseInput = CourseSnapshotInput(
                courseName: name,
                teeSet: tee,
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
