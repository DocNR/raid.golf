// RAID Golf — Course Request Builder
// Pure transformation: build NIP-17 kind 14 rumor for course requests.
// The bot parses the JSON payload; human-readable header is for display in any Nostr client.
// No database queries, no network calls.

import Foundation
import NostrSDK

enum CourseRequestBuilder {

    /// Build a kind 14 rumor (unsigned event) for a course request DM to the RAID bot.
    /// Content includes a human-readable header plus a structured JSON payload.
    static func buildCourseRequestRumor(
        senderPubkey: PublicKey,
        botPubkeyHex: String,
        courseName: String,
        city: String,
        state: String,
        website: String? = nil
    ) throws -> UnsignedEvent {
        let jsonPayload = buildJSON(courseName: courseName, city: city, state: state, website: website)

        let content = """
            Course Request: \(courseName), \(city), \(state)

            Sent from RAID Golf

            \(jsonPayload)
            """.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")

        let pTag = try Tag.parse(data: ["p", botPubkeyHex])

        return EventBuilder(kind: Kind(kind: 14), content: content)
            .tags(tags: [pTag])
            .build(publicKey: senderPubkey)
    }

    /// Build the structured JSON payload for a course request.
    static func buildJSON(courseName: String, city: String, state: String, website: String? = nil) -> String {
        var dict: [String: Any] = [
            "type": "course_request",
            "version": 1,
            "course_name": courseName,
            "city": city,
            "state": state
        ]
        if let website, !website.isEmpty {
            dict["website"] = website
        }
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    /// Extract a course request from DM content by parsing the JSON payload.
    /// Returns nil if the content doesn't contain a valid course_request JSON.
    static func extractCourseRequest(fromContent content: String) -> CourseRequest? {
        // Find JSON object in content (starts with { and ends with })
        guard let jsonStart = content.range(of: "{\""),
              let jsonEnd = content.range(of: "}", options: .backwards, range: jsonStart.lowerBound..<content.endIndex) else {
            return nil
        }

        let jsonString = String(content[jsonStart.lowerBound...jsonEnd.lowerBound])
        guard let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              dict["type"] as? String == "course_request",
              let courseName = dict["course_name"] as? String,
              let city = dict["city"] as? String,
              let state = dict["state"] as? String else {
            return nil
        }

        return CourseRequest(
            courseName: courseName,
            city: city,
            state: state,
            version: dict["version"] as? Int ?? 1,
            website: dict["website"] as? String
        )
    }
}

struct CourseRequest {
    let courseName: String
    let city: String
    let state: String
    let version: Int
    let website: String?
}
