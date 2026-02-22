// CourseEventParser.swift
// RAID Golf
//
// Parses kind 33501 Nostr events into ParsedCourse models.
// Pure transformation — no database or network dependencies.
// See: docs/private/course_data_system.md Section 2.

import Foundation
import NostrSDK

enum CourseEventParser {

    /// Parse a kind 33501 event into a ParsedCourse.
    /// Returns nil if required tags are missing or malformed.
    static func parse(event: Event) -> ParsedCourse? {
        let tags = extractTags(from: event)

        guard let dTag = tags.first(where: { $0[0] == "d" }).flatMap({ $0.count >= 2 ? $0[1] : nil }),
              let title = tags.first(where: { $0[0] == "title" }).flatMap({ $0.count >= 2 ? $0[1] : nil }),
              let location = tags.first(where: { $0[0] == "location" }).flatMap({ $0.count >= 2 ? $0[1] : nil })
        else { return nil }

        let holes = parseHoles(from: tags)
        let tees = parseTees(from: tags)

        // Require at least 9 holes and 1 tee set
        guard holes.count >= 9, !tees.isEmpty else { return nil }

        let yardages = parseYardages(from: tags)
        let country = tags.first(where: { $0[0] == "country" }).flatMap { $0.count >= 2 ? $0[1] : nil }
        let website = tags.first(where: { $0[0] == "website" }).flatMap { $0.count >= 2 ? $0[1] : nil }
        let architect = tags.first(where: { $0[0] == "architect" }).flatMap { $0.count >= 2 ? $0[1] : nil }
        let established = tags.first(where: { $0[0] == "established" }).flatMap { $0.count >= 2 ? $0[1] : nil }
        let imageURL = tags.first(where: { $0[0] == "image" }).flatMap { $0.count >= 2 ? $0[1] : nil }
        let operatorPubkey = parseOperatorPubkey(from: tags)

        let content = event.content()
        let contentStr = content.isEmpty ? nil : content

        return ParsedCourse(
            dTag: dTag,
            authorHex: event.author().toHex(),
            title: title,
            location: location,
            country: country,
            holes: holes.sorted { $0.number < $1.number },
            tees: tees,
            yardages: yardages,
            content: contentStr,
            website: website,
            architect: architect,
            established: established,
            imageURL: imageURL,
            operatorPubkey: operatorPubkey,
            eventId: event.id().toHex(),
            eventCreatedAt: event.createdAt().asSecs()
        )
    }

    // MARK: - Private

    private static func extractTags(from event: Event) -> [[String]] {
        var result: [[String]] = []
        let tagsVec = event.tags().toVec()
        for tag in tagsVec {
            let values = tag.asVec()
            if !values.isEmpty {
                result.append(values)
            }
        }
        return result
    }

    /// Parse `["hole", "<number>", "<par>", "<handicap>"]` tags.
    private static func parseHoles(from tags: [[String]]) -> [ParsedCourse.ParsedHole] {
        tags.compactMap { tag in
            guard tag.count >= 4,
                  tag[0] == "hole",
                  let number = Int(tag[1]),
                  let par = Int(tag[2]),
                  let handicap = Int(tag[3])
            else { return nil }
            return ParsedCourse.ParsedHole(number: number, par: par, handicap: handicap)
        }
    }

    /// Parse `["tee", "<name>", "<rating>", "<slope>"]` tags.
    private static func parseTees(from tags: [[String]]) -> [ParsedCourse.ParsedTee] {
        tags.compactMap { tag in
            guard tag.count >= 4,
                  tag[0] == "tee",
                  let rating = Double(tag[1 + 1]),  // tag[2]
                  let slope = Int(tag[1 + 2])        // tag[3]
            else { return nil }
            return ParsedCourse.ParsedTee(name: tag[1], rating: rating, slope: slope)
        }
    }

    /// Parse `["yardage", "<hole>", "<tee>", "<yards>"]` tags.
    private static func parseYardages(from tags: [[String]]) -> [ParsedCourse.ParsedYardage] {
        tags.compactMap { tag in
            guard tag.count >= 4,
                  tag[0] == "yardage",
                  let hole = Int(tag[1]),
                  let yards = Int(tag[3])
            else { return nil }
            return ParsedCourse.ParsedYardage(hole: hole, tee: tag[2], yards: yards)
        }
    }

    /// Extract operator pubkey from `["p", "<pubkey>", "", "operator"]` tag.
    private static func parseOperatorPubkey(from tags: [[String]]) -> String? {
        for tag in tags {
            guard tag.count >= 4,
                  tag[0] == "p",
                  tag[3] == "operator"
            else { continue }
            return tag[1]
        }
        return nil
    }
}
