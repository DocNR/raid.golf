// RoundDetailView.swift
// Gambit Golf
//
// Completed round scorecard display

import SwiftUI
import GRDB
import NostrSDK

struct RoundDetailView: View {
    let roundId: Int64
    let dbQueue: DatabaseQueue

    @State private var round: RoundRecord?
    @State private var courseSnapshot: CourseSnapshotRecord?
    @State private var holes: [CourseHoleRecord] = []
    @State private var allPlayerScores: [Int: [Int: Int]] = [:] // playerIndex -> (holeNumber -> strokes)
    @State private var players: [RoundPlayerRecord] = []
    @State private var selectedPlayerIndex: Int = 0

    // Share state
    @State private var isPublishing = false
    @State private var errorMessage: String?
    @State private var showPublishSuccess = false

    // Multi-device state
    @State private var nostrRecord: RoundNostrRecord?
    @State private var isFetchingRemote = false
    @State private var remoteFetchDone = false

    private var isJoinedRound: Bool {
        nostrRecord?.joinedVia == "joined"
    }

    // Derived scores for the currently selected player
    private var scores: [Int: Int] {
        allPlayerScores[selectedPlayerIndex] ?? [:]
    }

    private var isMultiplayer: Bool {
        players.count > 1
    }

    var body: some View {
        Group {
            if let course = courseSnapshot {
                scorecardView
                    .navigationTitle(course.courseName)
            } else {
                ProgressView()
                    .navigationTitle("Scorecard")
            }
        }
        .toolbar {
            if courseSnapshot != nil, !scores.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    shareMenu
                }
            }
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .alert("Posted!", isPresented: $showPublishSuccess) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your round has been posted to Nostr.")
        }
        .task { loadData() }
    }

    private var scorecardView: some View {
        List {
            if isMultiplayer {
                Section {
                    Picker("Player", selection: $selectedPlayerIndex) {
                        ForEach(players.indices, id: \.self) { index in
                            Text("P\(index + 1)").tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            // Fetch remote scores for joined rounds
            if isJoinedRound {
                Section {
                    Button {
                        Task { await fetchRemoteFinalRecords() }
                    } label: {
                        HStack {
                            Label("Fetch Other Players' Scores", systemImage: "arrow.triangle.2.circlepath")
                            Spacer()
                            if isFetchingRemote {
                                ProgressView()
                            } else if remoteFetchDone {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .disabled(isFetchingRemote)
                }
            }

            if holes.count == 18 {
                nineHoleSection(title: "Front 9", holes: Array(holes.prefix(9)))
                nineHoleSection(title: "Back 9", holes: Array(holes.suffix(9)))
            } else {
                nineHoleSection(title: "Scorecard", holes: holes)
            }

            totalSection
        }
    }

    private func nineHoleSection(title: String, holes: [CourseHoleRecord]) -> some View {
        Section(title) {
            ForEach(holes, id: \.holeNumber) { hole in
                HStack {
                    Text("Hole \(hole.holeNumber)")
                        .frame(width: 60, alignment: .leading)

                    Text("Par \(hole.par)")
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .leading)

                    Spacer()

                    if let strokes = scores[hole.holeNumber] {
                        let diff = strokes - hole.par

                        HStack(spacing: 8) {
                            Text("\(strokes)")
                                .font(.headline)

                            if diff != 0 {
                                Text(diff > 0 ? "+\(diff)" : "\(diff)")
                                    .font(.caption)
                                    .foregroundStyle(diff > 0 ? .red : .green)
                            }
                        }
                    } else {
                        Text("-")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Subtotal for this nine
            let ninePar = holes.reduce(0) { $0 + $1.par }
            let nineStrokes = holes.reduce(0) { sum, hole in
                sum + (scores[hole.holeNumber] ?? 0)
            }
            let nineDiff = nineStrokes - ninePar

            HStack {
                Text("Subtotal")
                    .font(.headline)
                Spacer()
                HStack(spacing: 8) {
                    Text("\(nineStrokes)")
                        .font(.headline)
                    Text("(\(nineDiff > 0 ? "+" : "")\(nineDiff))")
                        .font(.caption)
                        .foregroundStyle(nineDiff > 0 ? .red : (nineDiff < 0 ? .green : .secondary))
                }
            }
        }
    }

    private var totalSection: some View {
        Section {
            HStack {
                Text("Total Par")
                Spacer()
                Text("\(totalPar)")
            }

            HStack {
                Text("Total Strokes")
                Spacer()
                Text("\(totalStrokes)")
                    .font(.headline)
            }

            HStack {
                Text("Score")
                Spacer()
                let diff = totalStrokes - totalPar
                Text(diff == 0 ? "Even" : (diff > 0 ? "+\(diff)" : "\(diff)"))
                    .font(.headline)
                    .foregroundStyle(diff > 0 ? .red : (diff < 0 ? .green : .primary))
            }
        }
    }

    private var totalPar: Int {
        holes.reduce(0) { $0 + $1.par }
    }

    private var totalStrokes: Int {
        holes.reduce(0) { sum, hole in
            sum + (scores[hole.holeNumber] ?? 0)
        }
    }

    // MARK: - Share

    private var shareMenu: some View {
        Menu {
            Button {
                Task { await publishToNostr() }
            } label: {
                Label(isPublishing ? "Posting..." : "Post to Nostr", systemImage: "paperplane")
            }
            .disabled(isPublishing)

            Button {
                copySummary()
            } label: {
                Label("Copy Summary", systemImage: "doc.on.doc")
            }
        } label: {
            if isPublishing {
                ProgressView()
            } else {
                Image(systemName: "square.and.arrow.up")
            }
        }
    }

    private func publishToNostr() async {
        guard let course = courseSnapshot else { return }

        isPublishing = true
        defer { isPublishing = false }

        do {
            let keyManager = try KeyManager.loadOrCreate()
            let keys = keyManager.signingKeys()
            let pubkey = try keys.publicKey().toHex()

            // Check for stored initiation (published at round creation)
            let nostrRepo = RoundNostrRepository(dbQueue: dbQueue)
            let playerRepo = RoundPlayerRepository(dbQueue: dbQueue)
            let existingInitiation = try nostrRepo.fetchInitiation(forRound: roundId)

            // Get player pubkeys: from round_players if available, else solo
            var playerPubkeys = try playerRepo.fetchPlayerPubkeys(forRound: roundId)
            if playerPubkeys.isEmpty {
                playerPubkeys = [pubkey]
            }

            let initiationEventId: String
            if let existing = existingInitiation {
                initiationEventId = existing.initiationEventId
            } else {
                // Fallback: publish initiation now (offline round or failed background publish)
                let content = NIP101gEventBuilder.buildInitiationContent(
                    snapshot: course,
                    holes: holes
                )
                let courseHash = try NIP101gEventBuilder.computeCourseHash(content: content)
                let rulesHash = try NIP101gEventBuilder.computeRulesHash(content: content)
                let dateString = round?.roundDate ?? ISO8601DateFormatter().string(from: Date())

                let initiationBuilder = try NIP101gEventBuilder.buildInitiationEvent(
                    content: content,
                    courseHash: courseHash,
                    rulesHash: rulesHash,
                    playerPubkeys: playerPubkeys,
                    date: dateString
                )
                initiationEventId = try await NostrClient.publishEvent(
                    keys: keys,
                    builder: initiationBuilder
                )
                try nostrRepo.insertInitiation(roundId: roundId, initiationEventId: initiationEventId)
            }

            // Publish final round records (kind 1502)
            var myFinalEventId: String = ""

            if isJoinedRound {
                // Multi-device: publish only MY kind 1502, signed by my key
                let myScores = allPlayerScores[0] ?? [:] // Local player uses index 0
                let scoreList = holes
                    .sorted { $0.holeNumber < $1.holeNumber }
                    .compactMap { hole -> (holeNumber: Int, strokes: Int)? in
                        guard let strokes = myScores[hole.holeNumber] else { return nil }
                        return (holeNumber: hole.holeNumber, strokes: strokes)
                    }
                let total = scoreList.reduce(0) { $0 + $1.strokes }

                let finalBuilder = try NIP101gEventBuilder.buildFinalRecordEvent(
                    initiationEventId: initiationEventId,
                    scores: scoreList,
                    total: total,
                    scoredPlayerPubkey: pubkey,
                    playerPubkeys: playerPubkeys,
                    notes: nil
                )
                myFinalEventId = try await NostrClient.publishEvent(
                    keys: keys,
                    builder: finalBuilder
                )
            } else if isMultiplayer {
                // Same-device: one 1502 per player, all signed by creator
                for player in players {
                    let playerScores = allPlayerScores[player.playerIndex] ?? [:]
                    let scoreList = holes
                        .sorted { $0.holeNumber < $1.holeNumber }
                        .compactMap { hole -> (holeNumber: Int, strokes: Int)? in
                            guard let strokes = playerScores[hole.holeNumber] else { return nil }
                            return (holeNumber: hole.holeNumber, strokes: strokes)
                        }
                    let total = scoreList.reduce(0) { $0 + $1.strokes }

                    let finalBuilder = try NIP101gEventBuilder.buildFinalRecordEvent(
                        initiationEventId: initiationEventId,
                        scores: scoreList,
                        total: total,
                        scoredPlayerPubkey: player.playerPubkey,
                        playerPubkeys: playerPubkeys,
                        notes: nil
                    )
                    let eventId = try await NostrClient.publishEvent(
                        keys: keys,
                        builder: finalBuilder
                    )
                    if player.playerIndex == 0 {
                        myFinalEventId = eventId
                    }
                }
            } else {
                // Solo: single 1502
                let scoreList = holes
                    .sorted { $0.holeNumber < $1.holeNumber }
                    .compactMap { hole -> (holeNumber: Int, strokes: Int)? in
                        guard let strokes = scores[hole.holeNumber] else { return nil }
                        return (holeNumber: hole.holeNumber, strokes: strokes)
                    }
                let total = scoreList.reduce(0) { $0 + $1.strokes }

                let finalBuilder = try NIP101gEventBuilder.buildFinalRecordEvent(
                    initiationEventId: initiationEventId,
                    scores: scoreList,
                    total: total,
                    playerPubkeys: playerPubkeys,
                    notes: nil
                )
                myFinalEventId = try await NostrClient.publishEvent(
                    keys: keys,
                    builder: finalBuilder
                )
            }

            // Publish companion kind 1 social note with njump link
            let noteText: String
            if isMultiplayer {
                let playerScoreList = players.map { player in
                    (label: "P\(player.playerIndex + 1)", scores: allPlayerScores[player.playerIndex] ?? [:])
                }
                noteText = RoundShareBuilder.noteText(
                    course: course.courseName,
                    tees: course.teeSet,
                    holes: holes,
                    playerScores: playerScoreList
                )
            } else {
                noteText = RoundShareBuilder.noteText(
                    course: course.courseName,
                    tees: course.teeSet,
                    holes: holes,
                    scores: scores
                )
            }

            let eventId1502 = try EventId.parse(id: myFinalEventId)
            let nevent = try Nip19Event(eventId: eventId1502).toBech32()

            // Mention other players via nostr:npub1... (clients render as profile links)
            let otherPubkeys = playerPubkeys.filter { $0 != pubkey }
            var socialContent = noteText
            if !otherPubkeys.isEmpty {
                let mentions = try otherPubkeys.map { hex in
                    let pk = try PublicKey.parse(publicKey: hex)
                    return "nostr:\(try pk.toBech32())"
                }
                socialContent += "\n\nPlayed with \(mentions.joined(separator: " "))"
            }
            socialContent += "\n\nhttps://njump.me/\(nevent)"

            var socialTagArrays: [[String]] = [
                ["e", myFinalEventId],
                ["t", "golf"],
                ["t", "gambitgolf"],
                ["client", "gambit-golf-ios"]
            ]
            for pk in playerPubkeys {
                socialTagArrays.append(["p", pk])
            }
            let socialTags = try socialTagArrays.map { try Tag.parse(data: $0) }

            let socialBuilder = EventBuilder(kind: Kind(kind: 1), content: socialContent)
                .tags(tags: socialTags)
            _ = try await NostrClient.publishEvent(keys: keys, builder: socialBuilder)

            showPublishSuccess = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func copySummary() {
        guard let course = courseSnapshot else { return }

        let text: String
        if isMultiplayer {
            let playerScoreList = players.map { player in
                (label: "P\(player.playerIndex + 1)", scores: allPlayerScores[player.playerIndex] ?? [:])
            }
            text = RoundShareBuilder.summaryText(
                course: course.courseName,
                tees: course.teeSet,
                date: round?.roundDate ?? "",
                holes: holes,
                playerScores: playerScoreList
            )
        } else {
            text = RoundShareBuilder.summaryText(
                course: course.courseName,
                tees: course.teeSet,
                date: round?.roundDate ?? "",
                holes: holes,
                scores: scores
            )
        }
        UIPasteboard.general.string = text
    }

    // MARK: - Remote Final Records

    /// Fetch other players' kind 1502 final records from relays.
    /// Merges remote scores into allPlayerScores by matching pubkey → player_index.
    private func fetchRemoteFinalRecords() async {
        guard let record = nostrRecord else { return }

        isFetchingRemote = true
        defer {
            isFetchingRemote = false
            remoteFetchDone = true
        }

        do {
            let events = try await NostrClient.fetchFinalRecords(
                initiationEventId: record.initiationEventId
            )

            // Build pubkey → player_index lookup from round_players
            var pubkeyToIndex: [String: Int] = [:]
            for player in players {
                pubkeyToIndex[player.playerPubkey] = player.playerIndex
            }

            // Parse each event and merge into allPlayerScores
            for event in events {
                let authorHex = event.author().toHex()
                let tags = event.tags().toVec().map { $0.asVec() }

                guard let finalData = NIP101gEventParser.parseFinalRecord(
                    tagArrays: tags,
                    authorPubkeyHex: authorHex,
                    content: event.content()
                ) else { continue }

                // Find this author's player_index
                guard let playerIndex = pubkeyToIndex[authorHex] else { continue }

                // Skip if we already have local scores for this player (creator's same-device scores)
                if !isJoinedRound && allPlayerScores[playerIndex] != nil { continue }

                // Merge remote scores
                var remoteScores: [Int: Int] = [:]
                for score in finalData.scores {
                    remoteScores[score.holeNumber] = score.strokes
                }
                allPlayerScores[playerIndex] = remoteScores
            }

            // Also cache in remote_scores_cache for offline viewing
            let remoteRepo = RemoteScoresRepository(dbQueue: dbQueue)
            for event in events {
                let authorHex = event.author().toHex()
                let tags = event.tags().toVec().map { $0.asVec() }
                guard let finalData = NIP101gEventParser.parseFinalRecord(
                    tagArrays: tags,
                    authorPubkeyHex: authorHex,
                    content: event.content()
                ) else { continue }

                var scoreDict: [Int: Int] = [:]
                for score in finalData.scores {
                    scoreDict[score.holeNumber] = score.strokes
                }
                try remoteRepo.upsertScores(roundId: roundId, playerPubkey: authorHex, scores: scoreDict)
            }
        } catch {
            errorMessage = "Could not fetch remote scores. Check your connection."
            print("[Gambit] Failed to fetch remote final records: \(error)")
        }
    }

    // MARK: - Data Loading

    private func loadData() {
        do {
            // Fetch round record — standalone read, no nesting
            let fetchedRound = try dbQueue.read { db in
                try Row.fetchOne(
                    db,
                    sql: "SELECT round_id, course_hash, round_date, created_at FROM rounds WHERE round_id = ?",
                    arguments: [roundId]
                )
            }

            guard let row = fetchedRound else { return }
            let courseHash: String = row["course_hash"]
            round = RoundRecord(
                roundId: row["round_id"],
                courseHash: courseHash,
                roundDate: row["round_date"],
                createdAt: row["created_at"]
            )

            // Load round_nostr record (if any) to detect joined vs created
            let nostrRepo = RoundNostrRepository(dbQueue: dbQueue)
            nostrRecord = try nostrRepo.fetchInitiation(forRound: roundId)

            // Sequential repo calls — each owns its own dbQueue.read
            let courseRepo = CourseSnapshotRepository(dbQueue: dbQueue)
            courseSnapshot = try courseRepo.fetchCourseSnapshot(byHash: courseHash)
            holes = try courseRepo.fetchHoles(forCourse: courseHash)

            let scoreRepo = HoleScoreRepository(dbQueue: dbQueue)
            let playerRepo = RoundPlayerRepository(dbQueue: dbQueue)
            players = try playerRepo.fetchPlayers(forRound: roundId)

            if isJoinedRound {
                // Joined round: load player_index 0 (my local scores)
                let myScores = try scoreRepo.fetchLatestScores(forRound: roundId, playerIndex: 0)
                allPlayerScores[0] = [:]
                for score in myScores {
                    allPlayerScores[0]?[score.holeNumber] = score.strokes
                }

                // Load cached remote scores (if previously fetched)
                let remoteRepo = RemoteScoresRepository(dbQueue: dbQueue)
                let cached = try remoteRepo.fetchRemoteScores(forRound: roundId)
                var pubkeyToIndex: [String: Int] = [:]
                for player in players {
                    pubkeyToIndex[player.playerPubkey] = player.playerIndex
                }
                for (pubkey, remoteScores) in cached {
                    if let index = pubkeyToIndex[pubkey] {
                        allPlayerScores[index] = remoteScores
                    }
                }
            } else if players.count > 1 {
                // Same-device multiplayer: load all players' scores
                let allScores = try scoreRepo.fetchAllPlayersLatestScores(forRound: roundId)
                for (playerIndex, playerScores) in allScores {
                    allPlayerScores[playerIndex] = [:]
                    for score in playerScores {
                        allPlayerScores[playerIndex]?[score.holeNumber] = score.strokes
                    }
                }
            } else {
                // Solo or pre-6C: load player 0 only
                let scoreRecords = try scoreRepo.fetchLatestScores(forRound: roundId)
                allPlayerScores[0] = [:]
                for score in scoreRecords {
                    allPlayerScores[0]?[score.holeNumber] = score.strokes
                }
            }
        } catch {
            print("[Gambit] Failed to load round detail: \(error)")
        }
    }
}
