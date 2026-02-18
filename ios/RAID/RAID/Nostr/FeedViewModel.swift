// RAID Golf — Feed View Model
// Owns feed state, fetch logic, event processing, and dedup.

import Foundation
import NostrSDK

@Observable
class FeedViewModel {

    // MARK: - Public State

    var items: [FeedItem] = []
    var isLoading = false
    var errorMessage: String?

    enum LoadState {
        case idle
        case guest
        case noKey
        case noFollows
        case loaded
    }
    var loadState: LoadState = .idle

    private var hasLoaded = false

    // MARK: - Load

    func loadIfNeeded(nostrService: NostrService) async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await refresh(nostrService: nostrService)
    }

    func refresh(nostrService: NostrService) async {
        guard nostrService.isActivated else {
            loadState = .guest
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            // 1. Get user's pubkey
            guard KeyManager.hasExistingKey() else {
                loadState = .noKey
                isLoading = false
                return
            }
            let keyManager = try KeyManager.loadOrCreate()
            let pubkey = keyManager.signingKeys().publicKey()

            // 2. Fetch follow list + profiles in one connection
            let (follows, _) = try await nostrService.fetchFollowListWithProfiles(pubkey: pubkey)

            guard !follows.isEmpty else {
                loadState = .noFollows
                isLoading = false
                return
            }

            // 3. Fetch feed events
            let events = try await nostrService.fetchFeedEvents(followedPubkeys: follows)

            // 4. Process into FeedItems
            let processed = await processEvents(events, nostrService: nostrService)
            items = processed
            loadState = .loaded

            // 5. Resolve profiles for all authors
            let pubkeyHexes = Array(Set(items.map(\.pubkeyHex)))
            let uncached = pubkeyHexes.filter { nostrService.profileCache[$0] == nil }
            if !uncached.isEmpty {
                _ = try? await nostrService.resolveProfiles(pubkeyHexes: uncached)
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Event Processing

    private func processEvents(_ events: [Event], nostrService: NostrService) async -> [FeedItem] {
        var feedItems: [FeedItem] = []
        var quotedScorecardIds: Set<String> = []

        // First pass: identify kind 1 notes that reference a 1502 via `e` tag
        // and collect the referenced 1502 IDs for dedup
        var kind1Events: [Event] = []
        var kind1502Events: [Event] = []

        for event in events {
            let kind = event.kind().asU16()
            if kind == 1 {
                kind1Events.append(event)
                // Check for e tag referencing a 1502
                let tags = event.tags().toVec().map { $0.asVec() }
                if let eTag = tags.first(where: { $0.count >= 2 && $0[0] == "e" }) {
                    quotedScorecardIds.insert(eTag[1])
                }
            } else if kind == NIP101gKind.finalRoundRecord {
                kind1502Events.append(event)
            }
        }

        // Process kind 1 events
        for event in kind1Events {
            let id = event.id().toHex()
            let pubkey = event.author().toHex()
            let createdAt = Date(timeIntervalSince1970: TimeInterval(event.createdAt().asSecs()))
            let content = event.content()
            let tags = event.tags().toVec().map { $0.asVec() }

            // Check if this kind 1 references a 1502 via e tag
            if let eTagValue = tags.first(where: { $0.count >= 2 && $0[0] == "e" })?[1] {
                // Try to fetch the referenced 1502 and build a scorecard item
                if let scorecardItem = await fetchScorecardForQuote(
                    noteId: id, notePubkey: pubkey, noteContent: content,
                    noteCreatedAt: createdAt, referencedEventId: eTagValue,
                    nostrService: nostrService
                ) {
                    feedItems.append(scorecardItem)
                    continue
                }
            }

            // Plain text note
            feedItems.append(.textNote(
                id: id, pubkeyHex: pubkey, content: content, createdAt: createdAt
            ))
        }

        // Process kind 1502 events (skip those already quoted by a kind 1)
        for event in kind1502Events {
            let id = event.id().toHex()
            guard !quotedScorecardIds.contains(id) else { continue }

            let pubkey = event.author().toHex()
            let createdAt = Date(timeIntervalSince1970: TimeInterval(event.createdAt().asSecs()))
            let tags = event.tags().toVec().map { $0.asVec() }

            guard let record = NIP101gEventParser.parseFinalRecord(
                tagArrays: tags, authorPubkeyHex: pubkey, content: event.content()
            ) else { continue }

            // Fetch 1501 for course info
            let courseInfo = await fetchCourseInfo(
                initiationEventId: record.initiationEventId, nostrService: nostrService
            )

            feedItems.append(.scorecard(
                id: id, pubkeyHex: pubkey, commentary: nil,
                record: record, courseInfo: courseInfo, createdAt: createdAt
            ))
        }

        // Sort by createdAt descending
        return feedItems.sorted { $0.createdAt > $1.createdAt }
    }

    /// Fetch a 1502 event referenced by a kind 1 quote note and build a scorecard FeedItem.
    private func fetchScorecardForQuote(
        noteId: String, notePubkey: String, noteContent: String,
        noteCreatedAt: Date, referencedEventId: String,
        nostrService: NostrService
    ) async -> FeedItem? {
        guard let referencedEvent = try? await nostrService.fetchEvent(eventIdHex: referencedEventId) else {
            return nil
        }

        // Verify the referenced event is actually a 1502
        guard referencedEvent.kind().asU16() == NIP101gKind.finalRoundRecord else {
            return nil
        }

        let refTags = referencedEvent.tags().toVec().map { $0.asVec() }
        let refPubkey = referencedEvent.author().toHex()

        guard let record = NIP101gEventParser.parseFinalRecord(
            tagArrays: refTags, authorPubkeyHex: refPubkey, content: referencedEvent.content()
        ) else {
            return nil
        }

        // Fetch 1501 for course info
        let courseInfo = await fetchCourseInfo(
            initiationEventId: record.initiationEventId, nostrService: nostrService
        )

        return .scorecard(
            id: noteId, pubkeyHex: notePubkey, commentary: noteContent,
            record: record, courseInfo: courseInfo, createdAt: noteCreatedAt
        )
    }

    /// Fetch a 1501 initiation event and parse course snapshot from it.
    private func fetchCourseInfo(
        initiationEventId: String?, nostrService: NostrService
    ) async -> CourseSnapshotContent? {
        guard let eventId = initiationEventId else { return nil }
        guard let event = try? await nostrService.fetchEvent(eventIdHex: eventId) else { return nil }
        guard let content = try? NIP101gEventParser.parseInitiationContent(json: event.content()) else { return nil }
        return content.courseSnapshot
    }
}

// MARK: - FeedItem

enum FeedItem: Identifiable {
    case textNote(id: String, pubkeyHex: String, content: String, createdAt: Date)
    case scorecard(id: String, pubkeyHex: String, commentary: String?,
                   record: FinalRecordData, courseInfo: CourseSnapshotContent?, createdAt: Date)

    var id: String {
        switch self {
        case .textNote(let id, _, _, _): return id
        case .scorecard(let id, _, _, _, _, _): return id
        }
    }

    var createdAt: Date {
        switch self {
        case .textNote(_, _, _, let date): return date
        case .scorecard(_, _, _, _, _, let date): return date
        }
    }

    var pubkeyHex: String {
        switch self {
        case .textNote(_, let pk, _, _): return pk
        case .scorecard(_, let pk, _, _, _, _): return pk
        }
    }
}
