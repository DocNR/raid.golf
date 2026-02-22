// CourseDetailView.swift
// RAID Golf
//
// Course detail with tee picker, hole table, and Start Round.
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

    // Player selection
    @State private var hasNostrKeys = false
    @State private var creatorPubkeyHex: String?
    @State private var selectedPlayers: [String: NostrProfile] = [:]
    @State private var isMultiDevice = false
    @State private var showPlayerPicker = false

    var body: some View {
        List {
            headerSection
            teePickerSection
            if selectedTee != nil {
                holeTableSection
            }
            playersSection
            startRoundSection
        }
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

    // MARK: - Sections

    @ViewBuilder
    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
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
                }

                if let website = course.website, let url = URL(string: website) {
                    Link(destination: url) {
                        Label("Website", systemImage: "globe")
                            .font(.caption)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var teePickerSection: some View {
        Section("Tee Set") {
            ForEach(course.tees, id: \.self) { tee in
                Button {
                    selectedTee = tee
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tee.name)
                                .font(.body.weight(selectedTee == tee ? .semibold : .regular))
                            Text("Rating \(tee.rating, specifier: "%.1f") / Slope \(tee.slope)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        let yards = course.totalYardage(forTee: tee.name)
                        if yards > 0 {
                            Text("\(yards) yds")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if selectedTee == tee {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.green)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var holeTableSection: some View {
        if let tee = selectedTee {
            let yardageMap = course.yardages(forTee: tee.name)
            Section {
                holeTableHeader
                ForEach(course.holes, id: \.number) { hole in
                    holeRow(hole: hole, yards: yardageMap[hole.number])
                }
                holeTableFooter(yardageMap: yardageMap)
            } header: {
                Text("Scorecard")
            }
        }
    }

    @ViewBuilder
    private var holeTableHeader: some View {
        HStack {
            Text("Hole")
                .frame(width: 44, alignment: .leading)
            Text("Par")
                .frame(width: 36, alignment: .center)
            Text("Hdcp")
                .frame(width: 40, alignment: .center)
            Text("Yds")
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func holeRow(hole: ParsedCourse.ParsedHole, yards: Int?) -> some View {
        HStack {
            Text("\(hole.number)")
                .frame(width: 44, alignment: .leading)
                .font(.body.monospacedDigit())
            Text("\(hole.par)")
                .frame(width: 36, alignment: .center)
                .font(.body.monospacedDigit())
            Text("\(hole.handicap)")
                .frame(width: 40, alignment: .center)
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
            if let yards {
                Text("\(yards)")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .font(.body.monospacedDigit())
            } else {
                Text("-")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private func holeTableFooter(yardageMap: [Int: Int]) -> some View {
        HStack {
            Text("Total")
                .frame(width: 44, alignment: .leading)
                .font(.body.weight(.semibold))
            Text("\(course.totalPar())")
                .frame(width: 36, alignment: .center)
                .font(.body.weight(.semibold).monospacedDigit())
            Text("")
                .frame(width: 40)
            if let tee = selectedTee {
                let total = course.totalYardage(forTee: tee.name)
                Text(total > 0 ? "\(total)" : "-")
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .font(.body.weight(.semibold).monospacedDigit())
            }
        }
    }

    @ViewBuilder
    private var playersSection: some View {
        Section {
            if !hasNostrKeys {
                Text("Set up Nostr identity to invite players")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                Button {
                    showPlayerPicker = true
                } label: {
                    HStack {
                        if selectedPlayers.isEmpty {
                            Label("Add Playing Partners", systemImage: "person.badge.plus")
                        } else {
                            Text("\(selectedPlayers.count) player\(selectedPlayers.count == 1 ? "" : "s") selected")
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

    @ViewBuilder
    private var startRoundSection: some View {
        Section {
            Button {
                startRound()
            } label: {
                HStack {
                    Spacer()
                    if isCreating {
                        ProgressView()
                    } else {
                        Text("Start Round")
                            .font(.headline)
                    }
                    Spacer()
                }
            }
            .disabled(selectedTee == nil || isCreating)
            .listRowBackground(
                (selectedTee != nil && !isCreating) ? Color.green : Color.gray.opacity(0.3)
            )
            .foregroundColor(.white)
        }
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
