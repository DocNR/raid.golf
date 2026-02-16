// RAID Golf — NIP-101g Event Parser
// Pure transformation: Nostr event content/tags → local data models.
// Inverse of NIP101gEventBuilder. No database queries, no network calls.
// See: docs/nips/nip101g_round_wip.md

import Foundation

// MARK: - Parser

enum NIP101gEventParser {

    /// Parse a kind 1501 initiation event's JSON content into RoundInitiationContent.
    static func parseInitiationContent(json: String) throws -> RoundInitiationContent {
        guard let data = json.data(using: .utf8) else {
            throw NIP101gParseError.invalidJSON
        }
        return try JSONDecoder().decode(RoundInitiationContent.self, from: data)
    }

    /// Extract structured tag data from a kind 1501 initiation event's tag arrays.
    /// Each tag is [String] where index 0 is the tag name and index 1+ are values.
    static func parseInitiationTags(tagArrays: [[String]]) -> InitiationTagData {
        var courseHash: String?
        var rulesHash: String?
        var date: String?
        var playerPubkeys: [String] = []

        for tag in tagArrays {
            guard tag.count >= 2 else { continue }
            switch tag[0] {
            case "course_hash":
                courseHash = tag[1]
            case "rules_hash":
                rulesHash = tag[1]
            case "date":
                date = tag[1]
            case "p":
                playerPubkeys.append(tag[1])
            default:
                break
            }
        }

        return InitiationTagData(
            courseHash: courseHash,
            rulesHash: rulesHash,
            date: date,
            playerPubkeys: playerPubkeys
        )
    }

    /// Verify that computed hashes match the tagged hashes from a kind 1501 event.
    /// Uses the same canonicalization + hashing pipeline as NIP101gEventBuilder.
    static func verifyHashes(
        content: RoundInitiationContent,
        courseHash: String,
        rulesHash: String,
        canonicalizer: Canonicalizing = RAIDCanonicalizer(),
        hasher: Hashing = RAIDHasher()
    ) throws -> Bool {
        let computedCourseHash = try NIP101gEventBuilder.computeCourseHash(
            content: content, canonicalizer: canonicalizer, hasher: hasher)
        let computedRulesHash = try NIP101gEventBuilder.computeRulesHash(
            content: content, canonicalizer: canonicalizer, hasher: hasher)

        return computedCourseHash == courseHash && computedRulesHash == rulesHash
    }
    // MARK: - Live Scorecard Parsing (kind 30501)

    /// Parse a kind 30501 live scorecard event's tags into structured data.
    /// Works with raw tag arrays (for unit testing) — caller extracts tags from Event.
    static func parseLiveScorecard(
        tagArrays: [[String]],
        authorPubkeyHex: String
    ) -> LiveScorecardData? {
        var initiationEventId: String?
        var status: String?
        var scores: [Int: Int] = [:]

        for tag in tagArrays {
            guard tag.count >= 2 else { continue }
            switch tag[0] {
            case "d":
                initiationEventId = tag[1]
            case "status":
                status = tag[1]
            case "score":
                guard tag.count >= 3,
                      let hole = Int(tag[1]),
                      let strokes = Int(tag[2]) else { continue }
                scores[hole] = strokes
            default:
                break
            }
        }

        return LiveScorecardData(
            initiationEventId: initiationEventId,
            authorPubkeyHex: authorPubkeyHex,
            scores: scores,
            status: status ?? "unknown"
        )
    }
    // MARK: - Final Record Parsing (kind 1502)

    /// Parse a kind 1502 final round record event's tags and content.
    static func parseFinalRecord(
        tagArrays: [[String]],
        authorPubkeyHex: String,
        content: String
    ) -> FinalRecordData? {
        var initiationEventId: String?
        var total: Int?
        var scoredByPubkey: String?
        var scores: [(holeNumber: Int, strokes: Int)] = []

        for tag in tagArrays {
            guard tag.count >= 2 else { continue }
            switch tag[0] {
            case "e":
                initiationEventId = tag[1]
            case "total":
                total = Int(tag[1])
            case "scored_by":
                scoredByPubkey = tag[1]
            case "score":
                guard tag.count >= 3,
                      let hole = Int(tag[1]),
                      let strokes = Int(tag[2]) else { continue }
                scores.append((holeNumber: hole, strokes: strokes))
            default:
                break
            }
        }

        return FinalRecordData(
            authorPubkeyHex: authorPubkeyHex,
            scoredByPubkey: scoredByPubkey,
            initiationEventId: initiationEventId,
            scores: scores.sorted { $0.holeNumber < $1.holeNumber },
            total: total ?? scores.reduce(0) { $0 + $1.strokes },
            notes: content.isEmpty ? nil : content
        )
    }
}

// MARK: - Data Types

/// Structured tag data extracted from a kind 1501 initiation event.
struct InitiationTagData {
    let courseHash: String?
    let rulesHash: String?
    let date: String?
    let playerPubkeys: [String]
}

/// Structured data from a kind 30501 live scorecard event.
struct LiveScorecardData {
    let initiationEventId: String?
    let authorPubkeyHex: String
    let scores: [Int: Int]   // holeNumber → strokes
    let status: String       // "in_progress" or "completed"
}

/// Parsed data from a kind 1502 final round record event.
struct FinalRecordData {
    let authorPubkeyHex: String
    let scoredByPubkey: String?
    let initiationEventId: String?
    let scores: [(holeNumber: Int, strokes: Int)]
    let total: Int
    let notes: String?
}

/// Combined scorecard from multiple players' final records.
/// Deduplicates by author (keeps last in array, simulating newest).
struct CombinedScorecard {
    struct PlayerResult {
        let pubkeyHex: String
        let scores: [Int: Int]  // holeNumber → strokes
        let total: Int
    }

    let players: [PlayerResult]

    init(records: [FinalRecordData]) {
        // Deduplicate: keep last per author (simulates newest by created_at)
        var latestByAuthor: [String: FinalRecordData] = [:]
        for record in records {
            latestByAuthor[record.authorPubkeyHex] = record
        }

        players = latestByAuthor.values
            .sorted { $0.total < $1.total }  // Sort by total ascending (lowest first)
            .map { record in
                var scoreDict: [Int: Int] = [:]
                for s in record.scores {
                    scoreDict[s.holeNumber] = s.strokes
                }
                return PlayerResult(
                    pubkeyHex: record.authorPubkeyHex,
                    scores: scoreDict,
                    total: record.total
                )
            }
    }

    /// Get a specific player's score for a hole, or nil if not found.
    func scoreForPlayer(_ pubkeyHex: String, hole: Int) -> Int? {
        players.first(where: { $0.pubkeyHex == pubkeyHex })?.scores[hole]
    }
}

// MARK: - Errors

enum NIP101gParseError: LocalizedError {
    case invalidJSON
    case missingRequiredTag(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "Failed to parse NIP-101g event content."
        case .missingRequiredTag(let tag):
            return "Missing required tag: \(tag)"
        }
    }
}
