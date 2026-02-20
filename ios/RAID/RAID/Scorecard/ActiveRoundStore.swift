// ActiveRoundStore.swift
// RAID Golf
//
// Long-lived view model for active round scoring state.
// Owns holes, scores, navigation index, player state, and persistence logic.
// Created at the RoundsView level so state survives view recreation.
//
// Invariants:
// - Append-only inserts into hole_scores (no UPDATE/DELETE)
// - saveCurrentScore() always persists the displayed value (including default par)
// - Rehydrates from DB on configure() — resume from first unscored hole
// - Supports multi-player scoring: scores keyed by playerIndex -> holeNumber -> strokes
// - Backward compat: solo rounds (no round_players rows) use playerIndex 0

import Foundation
import GRDB
import NostrSDK

@Observable
class ActiveRoundStore {
    // MARK: - Published State

    var holes: [CourseHoleRecord] = []
    var scores: [Int: [Int: Int]] = [:]  // playerIndex -> (holeNumber -> strokes)
    var players: [RoundPlayerRecord] = []
    var currentHoleIndex: Int = 0
    var currentPlayerIndex: Int = 0
    var isCompleting: Bool = false
    var isLoaded: Bool = false
    var errorMessage: String?
    var playerProfiles: [String: NostrProfile] = [:]

    // MARK: - Identity

    private(set) var roundId: Int64 = 0
    private(set) var courseHash: String = ""
    private(set) var multiDeviceMode: Bool = false
    private var dbQueue: DatabaseQueue?
    private var nostrService: NostrService?

    // MARK: - Computed Properties

    var currentHole: CourseHoleRecord? {
        guard !holes.isEmpty, currentHoleIndex < holes.count else { return nil }
        return holes[currentHoleIndex]
    }

    var isMultiplayer: Bool {
        players.count > 1
    }

    var currentStrokes: Int {
        guard let hole = currentHole else { return 0 }
        return scores[currentPlayerIndex]?[hole.holeNumber] ?? hole.par
    }

    /// True if the current hole has an explicitly recorded score (confirmed by user interaction).
    var currentHoleConfirmed: Bool {
        guard let hole = currentHole else { return false }
        return scores[currentPlayerIndex]?[hole.holeNumber] != nil
    }

    var holesScored: Int {
        holes.filter { scores[currentPlayerIndex]?[$0.holeNumber] != nil }.count
    }

    var totalStrokes: Int {
        holes.reduce(0) { sum, hole in
            sum + (scores[currentPlayerIndex]?[hole.holeNumber] ?? 0)
        }
    }

    var totalPar: Int {
        holes.reduce(0) { $0 + $1.par }
    }

    var scoreToPar: String {
        let diff = totalStrokes - totalPar
        if diff == 0 { return "E" }
        return diff > 0 ? "+\(diff)" : "\(diff)"
    }

    var isFinishEnabled: Bool {
        guard !holes.isEmpty, !isCompleting else { return false }

        // If same-device multiplayer, all players must have all holes scored
        if shouldCyclePlayers {
            for player in players {
                let playerHolesScored = holes.filter { scores[player.playerIndex]?[$0.holeNumber] != nil }.count
                if playerHolesScored < holes.count {
                    return false
                }
            }
            return true
        } else {
            // Solo or multi-device: only player 0 needs all holes scored
            let player0HolesScored = holes.filter { scores[0]?[$0.holeNumber] != nil }.count
            return player0HolesScored >= holes.count
        }
    }

    var isOnLastHole: Bool {
        guard !holes.isEmpty else { return false }
        if shouldCyclePlayers {
            return currentHoleIndex == holes.count - 1 && currentPlayerIndex == players.count - 1
        }
        return currentHoleIndex == holes.count - 1
    }

    var isOnFirstPosition: Bool {
        currentHoleIndex == 0 && currentPlayerIndex == 0
    }

    var playerProgress: [(label: String, scored: Int, total: Int)] {
        if shouldCyclePlayers {
            return players.map { player in
                let scored = holes.filter { scores[player.playerIndex]?[$0.holeNumber] != nil }.count
                return (label: playerDisplayLabel(for: player.playerIndex), scored: scored, total: holes.count)
            }
        } else {
            return [(label: "You", scored: holesScored, total: holes.count)]
        }
    }

    var finishBlockedReason: String? {
        guard !holes.isEmpty, !isCompleting else { return nil }
        if shouldCyclePlayers {
            let incomplete = players.compactMap { player -> String? in
                let scored = holes.filter { scores[player.playerIndex]?[$0.holeNumber] != nil }.count
                guard scored < holes.count else { return nil }
                return "\(playerDisplayLabel(for: player.playerIndex)): \(scored)/\(holes.count)"
            }
            return incomplete.isEmpty ? nil : "Missing scores: \(incomplete.joined(separator: ", "))"
        } else {
            return holesScored < holes.count ? "\(holesScored) of \(holes.count) holes scored" : nil
        }
    }


    /// Short label for player (P1, P2, etc.) for segmented picker
    func playerLabel(for index: Int) -> String {
        "P\(index + 1)"
    }

    /// Display label with Nostr profile name, falling back to P1/P2.
    func playerDisplayLabel(for index: Int) -> String {
        if multiDeviceMode && index == 0 { return "You" }
        guard index < players.count else { return "P\(index + 1)" }
        return playerProfiles[players[index].playerPubkey]?.displayLabel ?? "P\(index + 1)"
    }

    private var shouldCyclePlayers: Bool {
        isMultiplayer && !multiDeviceMode
    }

    // MARK: - Configuration

    /// Configure the store for a specific round. Loads state from DB.
    /// Call once per active round — do not call again unless roundId changes.
    func configure(roundId: Int64, courseHash: String, dbQueue: DatabaseQueue, nostrService: NostrService, isMultiDevice: Bool = false) {
        // Skip reconfigure if already loaded for this round
        guard self.roundId != roundId else { return }

        self.roundId = roundId
        self.courseHash = courseHash
        self.dbQueue = dbQueue
        self.nostrService = nostrService
        self.multiDeviceMode = isMultiDevice
        self.isLoaded = false

        loadData()
    }

    // MARK: - Actions

    func incrementStrokes() {
        guard let hole = currentHole else { return }

        // Ensure player's scores dict exists
        if scores[currentPlayerIndex] == nil {
            scores[currentPlayerIndex] = [:]
        }

        let current = scores[currentPlayerIndex]?[hole.holeNumber] ?? hole.par
        if current < 20 {
            scores[currentPlayerIndex]?[hole.holeNumber] = current + 1
        }
    }

    func decrementStrokes() {
        guard let hole = currentHole else { return }

        // Ensure player's scores dict exists
        if scores[currentPlayerIndex] == nil {
            scores[currentPlayerIndex] = [:]
        }

        let current = scores[currentPlayerIndex]?[hole.holeNumber] ?? hole.par
        if current > 1 {
            scores[currentPlayerIndex]?[hole.holeNumber] = current - 1
        }
    }

    func advanceHole() {
        saveCurrentScore()
        if multiDeviceMode {
            let confirmedScores = scores[0] ?? [:]
            Task { [confirmedScores] in await publishLiveScorecard(overrideScores: confirmedScores) }
            if !isFetchingRemoteScores { Task { await fetchRemoteScores() } }
        }
        if shouldCyclePlayers && currentPlayerIndex < players.count - 1 {
            currentPlayerIndex += 1
        } else if currentHoleIndex < holes.count - 1 {
            currentHoleIndex += 1
            currentPlayerIndex = 0
        }
    }

    func retreatHole() {
        saveCurrentScore()
        if multiDeviceMode {
            let confirmedScores = scores[0] ?? [:]
            Task { [confirmedScores] in await publishLiveScorecard(overrideScores: confirmedScores) }
            if !isFetchingRemoteScores { Task { await fetchRemoteScores() } }
        }
        if shouldCyclePlayers && currentPlayerIndex > 0 {
            currentPlayerIndex -= 1
        } else if currentHoleIndex > 0 {
            currentHoleIndex -= 1
            currentPlayerIndex = shouldCyclePlayers ? players.count - 1 : 0
        }
    }

    /// Confirms the current hole at par without changing the stroke count.
    /// Called when the user taps the dimmed score display in the focused hole panel.
    func confirmCurrentHoleAtPar() {
        guard let hole = currentHole else { return }
        if scores[currentPlayerIndex] == nil {
            scores[currentPlayerIndex] = [:]
        }
        if scores[currentPlayerIndex]?[hole.holeNumber] == nil {
            scores[currentPlayerIndex]?[hole.holeNumber] = hole.par
        }
    }

    func switchPlayer(to index: Int) {
        saveCurrentScore()
        currentPlayerIndex = index
    }

    /// Jump directly to a specific hole index (0-based).
    /// Saves the current hole's score before jumping, then ensures the target hole has a default.
    /// Semantically identical to calling advanceHole()/retreatHole() — no new completion model needed.
    func jumpToHole(index: Int) {
        guard index >= 0, index < holes.count, index != currentHoleIndex else { return }
        saveCurrentScore()
        if multiDeviceMode {
            let confirmedScores = scores[0] ?? [:]
            Task { [confirmedScores] in await publishLiveScorecard(overrideScores: confirmedScores) }
            if !isFetchingRemoteScores { Task { await fetchRemoteScores() } }
        }
        currentHoleIndex = index
        if shouldCyclePlayers {
            currentPlayerIndex = 0
        }
    }

    func finishRound(dismiss: @escaping () -> Void) {
        guard let dbQueue = dbQueue else { return }
        isCompleting = true

        saveCurrentScore()

        do {
            let roundRepo = RoundRepository(dbQueue: dbQueue)
            try roundRepo.completeRound(roundId: roundId)

            // Fire-and-forget: publish kind 1502 final records to Nostr
            Task { [self] in await publishFinalRecords() }

            dismiss()
        } catch {
            print("[RAID] Failed to complete round: \(error)")
            errorMessage = "Could not finish round. Please try again."
            isCompleting = false
        }
    }

    /// Whether the review sheet should be shown before finishing.
    var showReviewSheet: Bool = false

    /// Whether the invite sheet should be shown.
    var showInviteSheet: Bool = false

    /// The nevent string for round invite sharing, nil if no initiation published yet.
    var inviteNevent: String?

    /// Whether the invite nevent is being loaded (initiation publish may be in flight).
    var isLoadingInvite: Bool = false

    /// Called when user taps Finish — shows review scorecard first.
    func requestFinish() {
        saveCurrentScore()
        if multiDeviceMode {
            // Publish final live scorecard including the last hole's score
            let confirmedScores = scores[0] ?? [:]
            Task { [confirmedScores] in await publishLiveScorecard(overrideScores: confirmedScores) }
        }
        showReviewSheet = true
    }

    // MARK: - Invite

    /// Load the invite nevent for this round (if initiation was published).
    /// Polls every 2 seconds (up to 5 attempts) for round_nostr record — the background
    /// 1501 publish may still be in flight when ScoreEntryView appears.
    /// Auto-shows invite sheet for creator after successful load.
    func loadInviteNevent() async {
        guard let dbQueue = dbQueue, inviteNevent == nil, multiDeviceMode else { return }

        isLoadingInvite = true
        defer { isLoadingInvite = false }

        let nostrRepo = RoundNostrRepository(dbQueue: dbQueue)

        for _ in 1...5 {
            do {
                if let record = try nostrRepo.fetchInitiation(forRound: roundId) {
                    inviteNevent = try RoundInviteBuilder.buildNevent(
                        eventIdHex: record.initiationEventId,
                        relays: NostrService.defaultPublishRelays
                    )
                    return
                }
            } catch {
                print("[RAID] Invite nevent build error: \(error)")
                return
            }

            // Wait 2 seconds before retrying (graceful cancellation)
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            } catch {
                return  // Task cancelled — exit gracefully
            }
        }

        print("[RAID] Invite nevent: round_nostr not found after 5 attempts for round \(roundId)")
    }

    // MARK: - Remote Score Sync

    /// Remote players' scores fetched from relays, keyed by pubkey -> (hole -> strokes).
    var remoteScores: [String: [Int: Int]] = [:]

    /// Whether a remote score fetch is in progress.
    var isFetchingRemoteScores: Bool = false

    /// Fetch remote players' live scorecard events from relays and cache locally.
    /// Manual refresh — called from UI "Refresh" button.
    func fetchRemoteScores() async {
        guard let dbQueue = dbQueue, let nostrService = nostrService else { return }

        // Need round_nostr record with initiation_event_id
        let nostrRepo = RoundNostrRepository(dbQueue: dbQueue)
        guard let record = try? nostrRepo.fetchInitiation(forRound: roundId) else { return }

        isFetchingRemoteScores = true

        do {
            let events = try await nostrService.fetchLiveScorecards(
                initiationEventId: record.initiationEventId
            )

            // Get my pubkey to filter out own events (we already have local scores)
            let myPubkeyHex: String? = {
                guard let km = try? KeyManager.loadOrCreate() else { return nil }
                return km.signingKeys().publicKey().toHex()
            }()

            // Load authorized player list for this round (B-004)
            let playerRepo = RoundPlayerRepository(dbQueue: dbQueue)
            let authorizedPubkeys = try playerRepo.fetchPlayerPubkeys(forRound: roundId)

            let remoteRepo = RemoteScoresRepository(dbQueue: dbQueue)

            // Parse and cache each player's scores
            // Keep newest per author (addressable replaceable — relay should dedup, but be safe)
            var newestByAuthor: [String: (scores: [Int: Int], createdAt: UInt64)] = [:]

            for event in events {
                let authorHex = event.author().toHex()

                // Skip own events — local scores are authoritative
                if authorHex == myPubkeyHex { continue }

                // Reject events from unauthorized authors (B-004)
                guard isAuthorizedPlayer(authorHex, allowedPubkeys: authorizedPubkeys) else {
                    print("[RAID][Auth] Rejected 30501 from unauthorized author \(authorHex.prefix(12))...")
                    continue
                }

                let tags = event.tags().toVec().map { $0.asVec() }
                guard let data = NIP101gEventParser.parseLiveScorecard(
                    tagArrays: tags,
                    authorPubkeyHex: authorHex
                ) else { continue }

                let createdAt = event.createdAt().asSecs()
                if let existing = newestByAuthor[authorHex], existing.createdAt >= createdAt {
                    continue  // Keep newer
                }
                newestByAuthor[authorHex] = (scores: data.scores, createdAt: createdAt)
            }

            // Cache to local DB and update in-memory state
            var fetched: [String: [Int: Int]] = [:]
            for (pubkey, entry) in newestByAuthor {
                try remoteRepo.upsertScores(roundId: roundId, playerPubkey: pubkey, scores: entry.scores)
                fetched[pubkey] = entry.scores
            }

            remoteScores = fetched
            for (pubkey, pScores) in fetched {
                let holeList = pScores.keys.sorted().map { "\($0):\(pScores[$0]!)" }.joined(separator: ", ")
                print("[RAID][Remote] Cached \(pubkey.prefix(8))...: [\(holeList)]")
            }
            isFetchingRemoteScores = false
        } catch {
            print("[RAID] Failed to fetch remote scores: \(error)")
            isFetchingRemoteScores = false
        }
    }

    /// Publish the current player's live scorecard to relays (fire-and-forget, debounce-friendly).
    /// Called after score save. Only publishes if this is a multi-device round (joined_via != nil).
    /// If overrideScores is provided, publishes those instead of reading from in-memory state
    /// (used to avoid publishing unconfirmed default-par for the just-arrived-at hole).
    func publishLiveScorecard(overrideScores: [Int: Int]? = nil) async {
        guard let dbQueue = dbQueue, let nostrService = nostrService else { return }

        let nostrRepo = RoundNostrRepository(dbQueue: dbQueue)
        guard let record = try? nostrRepo.fetchInitiation(forRound: roundId) else { return }

        // Only publish for multi-device rounds
        guard record.joinedVia == "joined" || record.joinedVia == "created_multi" else { return }

        // Use provided snapshot (confirmed scores only) or fall back to in-memory state
        let myScores = overrideScores ?? scores[0] ?? [:]
        guard !myScores.isEmpty else { return }

        let playerPubkeys: [String]
        do {
            let playerRepo = RoundPlayerRepository(dbQueue: dbQueue)
            playerPubkeys = try playerRepo.fetchPlayerPubkeys(forRound: roundId)
        } catch {
            return
        }

        do {
            let keyManager = try KeyManager.loadOrCreate()
            let keys = keyManager.signingKeys()

            let builder = try NIP101gEventBuilder.buildLiveScorecardEvent(
                initiationEventId: record.initiationEventId,
                scores: myScores,
                status: "in_progress",
                playerPubkeys: playerPubkeys
            )

            _ = try await nostrService.publishEvent(keys: keys, builder: builder)
            let holeList = myScores.keys.sorted().map { "\($0):\(myScores[$0]!)" }.joined(separator: ", ")
            print("[RAID][Publish] Kind 30501 round \(roundId): [\(holeList)]")
        } catch {
            print("[RAID] Kind 30501 publish failed: \(error)")
        }
    }

    // MARK: - Final Record Publishing

    /// Publish kind 1502 final records to Nostr (fire-and-forget).
    /// Called automatically from finishRound(). Handles solo, same-device multiplayer,
    /// and multi-device modes. Includes fallback 1501 publish if no initiation exists.
    /// Caches the 1502 event ID in UserDefaults to prevent duplicate publishes.
    func publishFinalRecords() async {
        guard let dbQueue = dbQueue, let nostrService = nostrService else { return }

        let cached1502Key = "1502_event_\(roundId)"
        if UserDefaults.standard.string(forKey: cached1502Key) != nil {
            print("[RAID] Kind 1502 already published for round \(roundId), skipping")
            return
        }

        do {
            let keyManager = try KeyManager.loadOrCreate()
            let keys = keyManager.signingKeys()
            let pubkey = keys.publicKey().toHex()

            let nostrRepo = RoundNostrRepository(dbQueue: dbQueue)
            let playerRepo = RoundPlayerRepository(dbQueue: dbQueue)
            let courseRepo = CourseSnapshotRepository(dbQueue: dbQueue)

            var playerPubkeys = try playerRepo.fetchPlayerPubkeys(forRound: roundId)
            if playerPubkeys.isEmpty { playerPubkeys = [pubkey] }

            // Get or publish initiation
            let initiationEventId: String
            if let existing = try nostrRepo.fetchInitiation(forRound: roundId) {
                initiationEventId = existing.initiationEventId
            } else {
                // Fallback: publish 1501 now (offline round or failed background publish)
                guard let snapshot = try courseRepo.fetchCourseSnapshot(byHash: courseHash) else {
                    print("[RAID] Kind 1502 auto-publish skipped: course snapshot not found")
                    return
                }
                let content = NIP101gEventBuilder.buildInitiationContent(snapshot: snapshot, holes: holes)
                let computedCourseHash = try NIP101gEventBuilder.computeCourseHash(content: content)
                let rulesHash = try NIP101gEventBuilder.computeRulesHash(content: content)
                let roundDate = try await dbQueue.read { db in
                    try String.fetchOne(db, sql: "SELECT round_date FROM rounds WHERE round_id = ?", arguments: [roundId])
                } ?? ISO8601DateFormatter().string(from: Date())

                var builder = try NIP101gEventBuilder.buildInitiationEvent(
                    content: content, courseHash: computedCourseHash, rulesHash: rulesHash,
                    playerPubkeys: playerPubkeys, date: roundDate)
                builder = builder.allowSelfTagging()
                initiationEventId = try await nostrService.publishEvent(keys: keys, builder: builder)
                try nostrRepo.insertInitiation(roundId: roundId, initiationEventId: initiationEventId)
                print("[RAID] Kind 1501 fallback published for round \(roundId)")
            }

            // Publish 1502s
            var myFinalEventId: String = ""

            if multiDeviceMode {
                // Multi-device: only MY 1502
                let myScores = scores[0] ?? [:]
                let scoreList = holes.sorted { $0.holeNumber < $1.holeNumber }
                    .compactMap { hole -> (holeNumber: Int, strokes: Int)? in
                        guard let strokes = myScores[hole.holeNumber] else { return nil }
                        return (holeNumber: hole.holeNumber, strokes: strokes)
                    }
                let total = scoreList.reduce(0) { $0 + $1.strokes }
                let finalBuilder = try NIP101gEventBuilder.buildFinalRecordEvent(
                    initiationEventId: initiationEventId, scores: scoreList, total: total,
                    scoredPlayerPubkey: pubkey, playerPubkeys: playerPubkeys, notes: nil)
                myFinalEventId = try await nostrService.publishEvent(keys: keys, builder: finalBuilder)
            } else if isMultiplayer {
                // Same-device: one 1502 per player, all signed by creator
                for player in players {
                    let playerScores = scores[player.playerIndex] ?? [:]
                    let scoreList = holes.sorted { $0.holeNumber < $1.holeNumber }
                        .compactMap { hole -> (holeNumber: Int, strokes: Int)? in
                            guard let strokes = playerScores[hole.holeNumber] else { return nil }
                            return (holeNumber: hole.holeNumber, strokes: strokes)
                        }
                    let total = scoreList.reduce(0) { $0 + $1.strokes }
                    let finalBuilder = try NIP101gEventBuilder.buildFinalRecordEvent(
                        initiationEventId: initiationEventId, scores: scoreList, total: total,
                        scoredPlayerPubkey: player.playerPubkey, playerPubkeys: playerPubkeys, notes: nil)
                    let eventId = try await nostrService.publishEvent(keys: keys, builder: finalBuilder)
                    if player.playerIndex == 0 { myFinalEventId = eventId }
                }
            } else {
                // Solo: single 1502
                let myScores = scores[0] ?? [:]
                let scoreList = holes.sorted { $0.holeNumber < $1.holeNumber }
                    .compactMap { hole -> (holeNumber: Int, strokes: Int)? in
                        guard let strokes = myScores[hole.holeNumber] else { return nil }
                        return (holeNumber: hole.holeNumber, strokes: strokes)
                    }
                let total = scoreList.reduce(0) { $0 + $1.strokes }
                let finalBuilder = try NIP101gEventBuilder.buildFinalRecordEvent(
                    initiationEventId: initiationEventId, scores: scoreList, total: total,
                    playerPubkeys: playerPubkeys, notes: nil)
                myFinalEventId = try await nostrService.publishEvent(keys: keys, builder: finalBuilder)
            }

            // Cache event ID to prevent duplicate publishes
            UserDefaults.standard.set(myFinalEventId, forKey: cached1502Key)
            print("[RAID] Kind 1502 auto-published for round \(roundId): \(myFinalEventId)")
        } catch {
            print("[RAID] Kind 1502 auto-publish failed for round \(roundId): \(error)")
        }
    }

    // MARK: - Persistence

    /// Persists the current hole's score only if it has been explicitly confirmed.
    /// No-op for unconfirmed holes (nil in scores dict). Append-only into hole_scores.
    private func saveCurrentScore() {
        guard let dbQueue = dbQueue, let hole = currentHole else { return }
        guard let strokes = scores[currentPlayerIndex]?[hole.holeNumber] else { return }

        do {
            let scoreRepo = HoleScoreRepository(dbQueue: dbQueue)
            let input = HoleScoreInput(holeNumber: hole.holeNumber, strokes: strokes)
            _ = try scoreRepo.recordScore(roundId: roundId, playerIndex: currentPlayerIndex, score: input)
            print("[RAID][Score] Saved hole \(hole.holeNumber)=\(strokes) player=\(currentPlayerIndex) round=\(roundId)")
        } catch {
            print("[RAID] Failed to save score: \(error)")
            errorMessage = "Could not save score for this hole."
        }
    }

    /// Load state from DB. Sequential repo calls — no nested reads.
    /// Resumes at first unscored hole for player 0, or last hole if all scored.
    private func loadData() {
        guard let dbQueue = dbQueue else { return }

        do {
            // Load course holes
            let courseRepo = CourseSnapshotRepository(dbQueue: dbQueue)
            holes = try courseRepo.fetchHoles(forCourse: courseHash)

            // Load players (ordered by player_index)
            let playerRepo = RoundPlayerRepository(dbQueue: dbQueue)
            players = try playerRepo.fetchPlayers(forRound: roundId)

            // Load scores
            let scoreRepo = HoleScoreRepository(dbQueue: dbQueue)
            scores = [:]

            if players.count > 1 {
                // Multiplayer: load all players' scores
                let allScores = try scoreRepo.fetchAllPlayersLatestScores(forRound: roundId)
                for (playerIndex, playerScores) in allScores {
                    scores[playerIndex] = [:]
                    for score in playerScores {
                        scores[playerIndex]?[score.holeNumber] = score.strokes
                    }
                }
            } else {
                // Solo or pre-6C rounds: load player 0 only
                let existingScores = try scoreRepo.fetchLatestScores(forRound: roundId, playerIndex: 0)
                scores[0] = [:]
                for score in existingScores {
                    scores[0]?[score.holeNumber] = score.strokes
                }
            }

            // Resume at first unscored hole for player 0; if all scored, stay at last hole
            if let firstUnscored = holes.firstIndex(where: { scores[0]?[$0.holeNumber] == nil }) {
                currentHoleIndex = firstUnscored
            } else if !holes.isEmpty {
                currentHoleIndex = holes.count - 1
            }

            // Holes with no entry in scores dict are "unconfirmed" — they display par
            // via the currentStrokes fallback but are not persisted. Confirmation requires
            // an explicit user gesture (tap dimmed score, or +/-).

            // Debug logging
            let loadedScores = scores[0] ?? [:]
            let holeList = loadedScores.keys.sorted().map { "\($0):\(loadedScores[$0]!)" }.joined(separator: ", ")
            print("[RAID][Load] Round \(roundId): \(holes.count) holes, \(players.count) players, multiDevice=\(multiDeviceMode), scores=[\(holeList)]")

            isLoaded = true
        } catch {
            print("[RAID] Failed to load round data: \(error)")
            errorMessage = "Could not load round data."
        }
    }
}
