// OutboxRoutingTests.swift
// RAID Golf
//
// Unit tests for NostrService.buildRelayPlan and normalizedRelayURL.
// Pure data-transformation logic — no network calls required.

import XCTest
@testable import RAID

final class OutboxRoutingTests: XCTestCase {

    // Convenience aliases for default publish relays (must match NostrService.defaultPublishRelays)
    private let defaultRelays = NostrService.defaultPublishRelays   // ["wss://relay.damus.io","wss://nos.lol","wss://relay.nostr.band"]

    // MARK: - URL Normalization

    func testNormalization_trailingSlashStripped() {
        XCTAssertEqual(
            NostrService.normalizedRelayURL("wss://relay.damus.io/"),
            "wss://relay.damus.io"
        )
    }

    func testNormalization_noTrailingSlash_unchanged() {
        XCTAssertEqual(
            NostrService.normalizedRelayURL("wss://relay.damus.io"),
            "wss://relay.damus.io"
        )
    }

    func testNormalization_doubleTrailingSlash_onlyOneStripped() {
        // Only the final character is stripped, so double slash becomes single trailing slash
        XCTAssertEqual(
            NostrService.normalizedRelayURL("wss://relay.damus.io//"),
            "wss://relay.damus.io/"
        )
    }

    // MARK: - Empty Input

    func testBuildRelayPlan_emptyInput_returnsEmptyPlan() {
        let (plan, orphanCount) = NostrService.buildRelayPlan(authorRelayMap: [:])
        XCTAssertTrue(plan.isEmpty)
        XCTAssertEqual(orphanCount, 0)
    }

    // MARK: - Metadata Relay Removal

    func testBuildRelayPlan_purplepages_excluded() {
        let author = String(repeating: "a", count: 64)
        let input: [String: [String]] = [
            author: ["wss://purplepag.es", "wss://relay.damus.io"]
        ]

        let (plan, _) = NostrService.buildRelayPlan(authorRelayMap: input)

        XCTAssertNil(plan["wss://purplepag.es"], "purplepag.es must not appear in relay plan")
        XCTAssertNotNil(plan["wss://relay.damus.io"], "content relay must appear in plan")
    }

    func testBuildRelayPlan_userKindpages_excluded() {
        let author = String(repeating: "b", count: 64)
        let input: [String: [String]] = [
            author: ["wss://user.kindpag.es", "wss://nos.lol"]
        ]

        let (plan, _) = NostrService.buildRelayPlan(authorRelayMap: input)

        XCTAssertNil(plan["wss://user.kindpag.es"])
        XCTAssertNotNil(plan["wss://nos.lol"])
    }

    func testBuildRelayPlan_relayNosSocial_excluded() {
        let author = String(repeating: "c", count: 64)
        let input: [String: [String]] = [
            author: ["wss://relay.nos.social", "wss://relay.nostr.band"]
        ]

        let (plan, _) = NostrService.buildRelayPlan(authorRelayMap: input)

        XCTAssertNil(plan["wss://relay.nos.social"])
        XCTAssertNotNil(plan["wss://relay.nostr.band"])
    }

    func testBuildRelayPlan_allMetadataRelays_producesOrphans() {
        // Author only lists metadata relays — all get stripped, author becomes orphan
        let author = String(repeating: "d", count: 64)
        let input: [String: [String]] = [
            author: ["wss://purplepag.es", "wss://user.kindpag.es", "wss://relay.nos.social"]
        ]

        let (plan, orphanCount) = NostrService.buildRelayPlan(authorRelayMap: input)

        XCTAssertEqual(orphanCount, 1, "author with only metadata relays must be orphaned")
        // Orphan is routed to default publish relays
        for defaultRelay in defaultRelays {
            let normalized = NostrService.normalizedRelayURL(defaultRelay)
            if let authors = plan[normalized] {
                XCTAssertTrue(authors.contains(author))
                return
            }
        }
        XCTFail("Orphaned author not found in any default relay entry")
    }

    // MARK: - Coverage Sort

    func testBuildRelayPlan_coverageSortedMostFirst() {
        let author1 = String(repeating: "1", count: 64)
        let author2 = String(repeating: "2", count: 64)
        let author3 = String(repeating: "3", count: 64)

        // nos.lol covers 3 authors; relay.damus.io covers only 1
        let input: [String: [String]] = [
            author1: ["wss://nos.lol"],
            author2: ["wss://nos.lol"],
            author3: ["wss://nos.lol", "wss://relay.damus.io"],
        ]

        let (plan, _) = NostrService.buildRelayPlan(authorRelayMap: input)

        // nos.lol must be in the plan and cover all 3 authors
        let nosLolAuthors = plan["wss://nos.lol"] ?? []
        XCTAssertEqual(Set(nosLolAuthors).count, 3, "nos.lol must cover all 3 authors")

        // relay.damus.io also in plan (only 1 author, still within cap)
        XCTAssertNotNil(plan["wss://relay.damus.io"])
    }

    // MARK: - 6-Relay Cap

    func testBuildRelayPlan_sixRelayCap() {
        // 8 relays each with 1 author — only top 6 selected
        var input: [String: [String]] = [:]
        let relays = (1...8).map { "wss://relay\($0).example.com" }
        for (i, relay) in relays.enumerated() {
            let author = String(repeating: String(format: "%x", i + 1), count: 64).prefix(64).description
            let author64 = String(author.prefix(64))
            input[author64] = [relay]
        }

        let (plan, _) = NostrService.buildRelayPlan(authorRelayMap: input, maxRelays: 6)

        // Top relays in plan must be at most 6 (before orphan default relays are added)
        // Count plan entries that are NOT default publish relays
        let topRelayEntries = plan.keys.filter { !defaultRelays.map { NostrService.normalizedRelayURL($0) }.contains($0) }
        XCTAssertLessThanOrEqual(topRelayEntries.count, 6, "must not exceed maxRelays cap")
    }

    func testBuildRelayPlan_customMaxRelays_respected() {
        // 5 distinct relays, each with 1 unique author, cap=3 → 2 authors orphaned
        var input: [String: [String]] = [:]
        for i in 1...5 {
            let author = String(repeating: "\(i)", count: 64)
            input[author] = ["wss://relay\(i).example.com"]
        }

        let (_, orphanCount) = NostrService.buildRelayPlan(authorRelayMap: input, maxRelays: 3)

        XCTAssertEqual(orphanCount, 2, "2 authors must be orphaned when cap=3 and 5 distinct relays")
    }

    // MARK: - Orphan Sweep

    func testBuildRelayPlan_orphansRoutedToDefaultRelays() {
        // 7 authors each on a unique relay with 1 author coverage — 1 is orphaned at cap=6
        var input: [String: [String]] = [:]
        for i in 1...7 {
            let author = String(repeating: "\(i)", count: 64)
            input[author] = ["wss://unique-relay-\(i).example.com"]
        }

        let (plan, orphanCount) = NostrService.buildRelayPlan(authorRelayMap: input, maxRelays: 6)

        XCTAssertEqual(orphanCount, 1, "exactly 1 author orphaned when 7 equally-covered relays capped at 6")

        // The orphaned author must appear in at least one default relay
        let orphanFound = defaultRelays.contains { defaultRelay in
            let normalized = NostrService.normalizedRelayURL(defaultRelay)
            return plan[normalized] != nil
        }
        XCTAssertTrue(orphanFound, "orphaned author must be routed to a default relay")
    }

    func testBuildRelayPlan_orphanMerged_whenDefaultRelayAlreadyInTop() {
        // author1 is on relay.damus.io (a default relay) — it will be in top relays
        // author2 has no relay — becomes orphan — must be merged into relay.damus.io entry
        let author1 = String(repeating: "e", count: 64)
        let author2 = String(repeating: "f", count: 64)

        // author2 only lists a metadata relay (gets stripped → orphan)
        let input: [String: [String]] = [
            author1: ["wss://relay.damus.io"],
            author2: ["wss://purplepag.es"],
        ]

        let (plan, orphanCount) = NostrService.buildRelayPlan(authorRelayMap: input)

        XCTAssertEqual(orphanCount, 1)

        // relay.damus.io already in plan from author1 — author2 must be merged in
        let damusAuthors = Set(plan["wss://relay.damus.io"] ?? [])
        XCTAssertTrue(damusAuthors.contains(author1), "author1 must remain in relay.damus.io")
        XCTAssertTrue(damusAuthors.contains(author2), "orphaned author2 must be merged into relay.damus.io")
    }

    // MARK: - Dedup / Same Author Multiple Relays

    func testBuildRelayPlan_sameAuthorMultipleRelays_noDuplication() {
        let author = String(repeating: "a", count: 64)
        let input: [String: [String]] = [
            author: ["wss://relay.damus.io", "wss://nos.lol", "wss://relay.nostr.band"]
        ]

        let (plan, orphanCount) = NostrService.buildRelayPlan(authorRelayMap: input)

        XCTAssertEqual(orphanCount, 0, "no orphans when author is on multiple relays")
        // Author must appear in at least one relay; must not be duplicated within a single relay's list
        for (_, authors) in plan {
            let authorSet = Set(authors)
            XCTAssertEqual(authors.count, authorSet.count, "authors list must not contain duplicates")
        }
    }

    // MARK: - All Authors on One Relay

    func testBuildRelayPlan_allAuthorsOnOneRelay_noOrphans() {
        let authors = (1...5).map { String(repeating: "\($0)", count: 64) }
        var input: [String: [String]] = [:]
        for author in authors {
            input[author] = ["wss://nos.lol"]
        }

        let (plan, orphanCount) = NostrService.buildRelayPlan(authorRelayMap: input)

        XCTAssertEqual(orphanCount, 0, "no orphans when all authors share one relay")
        let nosLolAuthors = plan["wss://nos.lol"] ?? []
        XCTAssertEqual(Set(nosLolAuthors).count, 5, "all 5 authors must be under nos.lol")
    }

    // MARK: - All Authors Orphaned (no relays at all)

    func testBuildRelayPlan_allAuthorsOrphaned_allGoToDefaults() {
        // Authors have empty relay lists — all become orphans
        let author1 = String(repeating: "a", count: 64)
        let author2 = String(repeating: "b", count: 64)
        let input: [String: [String]] = [
            author1: [],
            author2: [],
        ]

        let (plan, orphanCount) = NostrService.buildRelayPlan(authorRelayMap: input)

        XCTAssertEqual(orphanCount, 2, "both authors orphaned with empty relay lists")
        // Both must be routed to at least one default relay
        let coveredByDefaults = defaultRelays.contains { defaultRelay in
            let normalized = NostrService.normalizedRelayURL(defaultRelay)
            guard let authors = plan[normalized] else { return false }
            return Set(authors).contains(author1) && Set(authors).contains(author2)
        }
        XCTAssertTrue(coveredByDefaults, "all orphans must appear in at least one default relay")
    }

    // MARK: - Normalized URL Dedup

    func testBuildRelayPlan_normalizedURLDedup_trailingSlashTreatedAsSameRelay() {
        let author = String(repeating: "a", count: 64)
        // Both URLs differ only by trailing slash — must be grouped as one relay
        let input: [String: [String]] = [
            author: ["wss://relay.damus.io/", "wss://relay.damus.io"]
        ]

        let (plan, orphanCount) = NostrService.buildRelayPlan(authorRelayMap: input)

        XCTAssertEqual(orphanCount, 0)
        // Only one key for relay.damus.io (normalized form)
        XCTAssertNotNil(plan["wss://relay.damus.io"])
        XCTAssertNil(plan["wss://relay.damus.io/"], "trailing-slash variant must not appear as separate key")
    }

    func testBuildRelayPlan_twoAuthorsOnSameRelayDifferentSlash_countedOnce() {
        // Two authors: one lists with slash, one without — must be one relay entry covering both
        let author1 = String(repeating: "1", count: 64)
        let author2 = String(repeating: "2", count: 64)
        let input: [String: [String]] = [
            author1: ["wss://nos.lol/"],
            author2: ["wss://nos.lol"],
        ]

        let (plan, orphanCount) = NostrService.buildRelayPlan(authorRelayMap: input)

        XCTAssertEqual(orphanCount, 0)
        let nosAuthors = plan["wss://nos.lol"] ?? []
        XCTAssertEqual(Set(nosAuthors).count, 2, "both authors must appear under the single normalized nos.lol key")
        XCTAssertNil(plan["wss://nos.lol/"], "trailing-slash variant must not be a separate plan entry")
    }
}
