// RAID Golf — NIP-101g Event Builder
// Pure transformation: local DB models → NIP-101g Nostr events.
// No database queries, no network calls.
// See: docs/nips/nip101g_round_wip.md

import Foundation
import NostrSDK

// MARK: - Event Kinds (placeholders per WIP spec)

enum NIP101gKind {
    static let roundInitiation: UInt16 = 1501
    static let finalRoundRecord: UInt16 = 1502
    static let liveScorecard: UInt16 = 30501  // Addressable replaceable (30000-39999)
}

// MARK: - Builder

enum NIP101gEventBuilder {

    // MARK: - Content Building

    /// Build initiation content from local database models.
    static func buildInitiationContent(
        snapshot: CourseSnapshotRecord,
        holes: [CourseHoleRecord]
    ) -> RoundInitiationContent {
        let holeDefs = holes
            .sorted { $0.holeNumber < $1.holeNumber }
            .map { hole in
                NIP101gHoleDefinition(
                    holeNumber: hole.holeNumber,
                    par: hole.par,
                    handicapIndex: hole.handicapIndex
                )
            }

        let courseContent = CourseSnapshotContent(
            courseName: snapshot.courseName,
            teeSet: snapshot.teeSet,
            holeCount: snapshot.holeCount,
            holes: holeDefs
        )

        let rulesContent = RulesTemplateContent(format: "stroke_play")

        return RoundInitiationContent(
            courseSnapshot: courseContent,
            rulesTemplate: rulesContent
        )
    }

    // MARK: - Hash Computation

    /// Compute course_hash from initiation content using kernel canonicalization.
    /// Formula: SHA-256(UTF-8(JCS(course_snapshot_json)))
    static func computeCourseHash(
        content: RoundInitiationContent,
        canonicalizer: Canonicalizing = RAIDCanonicalizer(),
        hasher: Hashing = RAIDHasher()
    ) throws -> String {
        let snapshotData = try jsonEncode(content.courseSnapshot)
        let canonical = try canonicalizer.canonicalize(snapshotData)
        return hasher.sha256Hex(canonical)
    }

    /// Compute rules_hash from initiation content using kernel canonicalization.
    /// Formula: SHA-256(UTF-8(JCS(rules_template_json)))
    static func computeRulesHash(
        content: RoundInitiationContent,
        canonicalizer: Canonicalizing = RAIDCanonicalizer(),
        hasher: Hashing = RAIDHasher()
    ) throws -> String {
        let rulesData = try jsonEncode(content.rulesTemplate)
        let canonical = try canonicalizer.canonicalize(rulesData)
        return hasher.sha256Hex(canonical)
    }

    // MARK: - NostrSDK Event Builders

    /// Build a kind 1501 Round Initiation EventBuilder.
    /// Returns the builder — caller signs and publishes via NostrService.
    static func buildInitiationEvent(
        content: RoundInitiationContent,
        courseHash: String,
        rulesHash: String,
        playerPubkeys: [String],
        date: String
    ) throws -> EventBuilder {
        let contentJSON = try jsonEncodeString(content)

        var tagArrays: [[String]] = [
            ["course_hash", courseHash],
            ["rules_hash", rulesHash],
            ["date", date],
            ["t", "golf"],
            ["t", "raidgolf"],
            ["client", "raid-golf-ios"]
        ]

        for pubkey in playerPubkeys {
            tagArrays.append(["p", pubkey])
        }

        let tags = try tagArrays.map { try Tag.parse(data: $0) }

        return EventBuilder(kind: Kind(kind: NIP101gKind.roundInitiation), content: contentJSON)
            .tags(tags: tags)
            .allowSelfTagging()
    }

    /// Build a kind 1502 Final Round Record EventBuilder.
    /// References the initiation event by ID via `e` tag.
    /// For multiplayer: `scoredPlayerPubkey` identifies whose scores these are.
    /// The scored player's `p` tag comes first; a `scored_by` tag is added for unambiguous attribution.
    static func buildFinalRecordEvent(
        initiationEventId: String,
        scores: [(holeNumber: Int, strokes: Int)],
        total: Int,
        scoredPlayerPubkey: String? = nil,
        playerPubkeys: [String],
        notes: String?
    ) throws -> EventBuilder {
        var tagArrays: [[String]] = [
            ["e", initiationEventId],
            ["total", String(total)],
            ["t", "golf"],
            ["t", "raidgolf"],
            ["client", "raid-golf-ios"]
        ]

        for score in scores.sorted(by: { $0.holeNumber < $1.holeNumber }) {
            tagArrays.append(["score", String(score.holeNumber), String(score.strokes)])
        }

        if let scored = scoredPlayerPubkey {
            tagArrays.append(["scored_by", scored])
            // Scored player first, then others
            tagArrays.append(["p", scored])
            for pubkey in playerPubkeys where pubkey != scored {
                tagArrays.append(["p", pubkey])
            }
        } else {
            for pubkey in playerPubkeys {
                tagArrays.append(["p", pubkey])
            }
        }

        let tags = try tagArrays.map { try Tag.parse(data: $0) }
        let content = notes ?? ""

        return EventBuilder(kind: Kind(kind: NIP101gKind.finalRoundRecord), content: content)
            .tags(tags: tags)
            .allowSelfTagging()
    }

    // MARK: - Live Scorecard (kind 30501)

    /// Build tag arrays for a kind 30501 live scorecard event (for testing/inspection).
    /// Exposed separately from `buildLiveScorecardEvent` so tests can verify tag structure
    /// without needing to sign the event.
    static func buildLiveScorecardTagArrays(
        initiationEventId: String,
        scores: [Int: Int],
        status: String,
        playerPubkeys: [String]
    ) -> [[String]] {
        var tagArrays: [[String]] = [
            ["d", initiationEventId],
            ["e", initiationEventId],
            ["status", status],
            ["t", "golf"],
            ["t", "raidgolf"],
            ["client", "raid-golf-ios"]
        ]

        for holeNumber in scores.keys.sorted() {
            if let strokes = scores[holeNumber] {
                tagArrays.append(["score", String(holeNumber), String(strokes)])
            }
        }

        for pubkey in playerPubkeys {
            tagArrays.append(["p", pubkey])
        }

        return tagArrays
    }

    /// Build a kind 30501 Live Scorecard EventBuilder.
    /// Addressable replaceable: relay deduplicates on (kind + pubkey + d tag).
    /// Content is empty — all data lives in tags.
    static func buildLiveScorecardEvent(
        initiationEventId: String,
        scores: [Int: Int],
        status: String,
        playerPubkeys: [String]
    ) throws -> EventBuilder {
        let tagArrays = buildLiveScorecardTagArrays(
            initiationEventId: initiationEventId,
            scores: scores,
            status: status,
            playerPubkeys: playerPubkeys
        )

        let tags = try tagArrays.map { try Tag.parse(data: $0) }

        return EventBuilder(kind: Kind(kind: NIP101gKind.liveScorecard), content: "")
            .tags(tags: tags)
            .allowSelfTagging()
    }

    // MARK: - JSON Helpers

    /// Encode a Codable value to JSON Data with sorted keys for determinism.
    private static func jsonEncode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    /// Encode a Codable value to a JSON string with sorted keys.
    private static func jsonEncodeString<T: Encodable>(_ value: T) throws -> String {
        let data = try jsonEncode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw NIP101gError.utf8EncodingFailed
        }
        return string
    }
}

// MARK: - Errors

enum NIP101gError: LocalizedError {
    case utf8EncodingFailed

    var errorDescription: String? {
        switch self {
        case .utf8EncodingFailed:
            return "Failed to encode NIP-101g event content as UTF-8."
        }
    }
}
