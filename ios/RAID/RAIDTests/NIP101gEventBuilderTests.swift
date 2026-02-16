// NIP101gEventBuilderTests.swift
// RAID Golf
//
// Tests for NIP-101g event building: data structures, hash parity, tag structure.

import XCTest
@testable import RAID

final class NIP101gEventBuilderTests: XCTestCase {

    // MARK: - Fixtures

    private func makeSnapshot() -> CourseSnapshotRecord {
        CourseSnapshotRecord(
            courseHash: "abc123",
            courseName: "Fowler's Mill Golf Course",
            teeSet: "Silver M",
            holeCount: 9,
            canonicalJSON: "{}",
            createdAt: "2026-01-01T00:00:00Z"
        )
    }

    private func makeHoles(count: Int = 9, startingHole: Int = 1) -> [CourseHoleRecord] {
        (0..<count).map { i in
            CourseHoleRecord(
                courseHash: "abc123",
                holeNumber: startingHole + i,
                par: 4,
                handicapIndex: i + 1
            )
        }
    }

    // MARK: - Content Building

    func testBuildInitiationContent_StructureCorrect() {
        let snapshot = makeSnapshot()
        let holes = makeHoles()

        let content = NIP101gEventBuilder.buildInitiationContent(snapshot: snapshot, holes: holes)

        XCTAssertEqual(content.courseSnapshot.courseName, "Fowler's Mill Golf Course")
        XCTAssertEqual(content.courseSnapshot.teeSet, "Silver M")
        XCTAssertEqual(content.courseSnapshot.holeCount, 9)
        XCTAssertEqual(content.courseSnapshot.holes.count, 9)
        XCTAssertEqual(content.rulesTemplate.format, "stroke_play")
    }

    func testBuildInitiationContent_HolesAreSorted() {
        let snapshot = makeSnapshot()
        // Create holes out of order
        let holes = [
            CourseHoleRecord(courseHash: "abc123", holeNumber: 3, par: 5, handicapIndex: nil),
            CourseHoleRecord(courseHash: "abc123", holeNumber: 1, par: 4, handicapIndex: nil),
            CourseHoleRecord(courseHash: "abc123", holeNumber: 2, par: 3, handicapIndex: nil),
        ]

        let content = NIP101gEventBuilder.buildInitiationContent(snapshot: snapshot, holes: holes)

        XCTAssertEqual(content.courseSnapshot.holes[0].holeNumber, 1)
        XCTAssertEqual(content.courseSnapshot.holes[1].holeNumber, 2)
        XCTAssertEqual(content.courseSnapshot.holes[2].holeNumber, 3)
    }

    func testBuildInitiationContent_HandicapIndexPreserved() {
        let snapshot = makeSnapshot()
        let holes = [
            CourseHoleRecord(courseHash: "abc123", holeNumber: 1, par: 4, handicapIndex: 5),
            CourseHoleRecord(courseHash: "abc123", holeNumber: 2, par: 4, handicapIndex: nil),
        ]

        let content = NIP101gEventBuilder.buildInitiationContent(snapshot: snapshot, holes: holes)

        XCTAssertEqual(content.courseSnapshot.holes[0].handicapIndex, 5)
        XCTAssertNil(content.courseSnapshot.holes[1].handicapIndex)
    }

    // MARK: - JSON Encoding Round-Trip

    func testInitiationContent_JSONRoundTrip() throws {
        let content = NIP101gEventBuilder.buildInitiationContent(
            snapshot: makeSnapshot(),
            holes: makeHoles()
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(content)

        let decoded = try JSONDecoder().decode(RoundInitiationContent.self, from: data)
        XCTAssertEqual(content, decoded)
    }

    // MARK: - Hash Computation

    func testComputeCourseHash_Deterministic() throws {
        let content = NIP101gEventBuilder.buildInitiationContent(
            snapshot: makeSnapshot(),
            holes: makeHoles()
        )

        let hash1 = try NIP101gEventBuilder.computeCourseHash(content: content)
        let hash2 = try NIP101gEventBuilder.computeCourseHash(content: content)

        XCTAssertEqual(hash1, hash2, "Same content must produce same hash")
        XCTAssertEqual(hash1.count, 64, "SHA-256 hex should be 64 characters")
    }

    func testComputeRulesHash_Deterministic() throws {
        let content = NIP101gEventBuilder.buildInitiationContent(
            snapshot: makeSnapshot(),
            holes: makeHoles()
        )

        let hash1 = try NIP101gEventBuilder.computeRulesHash(content: content)
        let hash2 = try NIP101gEventBuilder.computeRulesHash(content: content)

        XCTAssertEqual(hash1, hash2, "Same rules must produce same hash")
        XCTAssertEqual(hash1.count, 64)
    }

    func testComputeCourseHash_DifferentContentDifferentHash() throws {
        let content1 = NIP101gEventBuilder.buildInitiationContent(
            snapshot: makeSnapshot(),
            holes: makeHoles()
        )

        // Different course
        let differentSnapshot = CourseSnapshotRecord(
            courseHash: "xyz",
            courseName: "Pebble Beach",
            teeSet: "Blue",
            holeCount: 9,
            canonicalJSON: "{}",
            createdAt: "2026-01-01T00:00:00Z"
        )
        let content2 = NIP101gEventBuilder.buildInitiationContent(
            snapshot: differentSnapshot,
            holes: makeHoles()
        )

        let hash1 = try NIP101gEventBuilder.computeCourseHash(content: content1)
        let hash2 = try NIP101gEventBuilder.computeCourseHash(content: content2)

        XCTAssertNotEqual(hash1, hash2, "Different course data must produce different hash")
    }

    func testComputeRulesHash_StrokePlayConsistent() throws {
        // Two independent content builds with same rules → same rules_hash
        let content1 = NIP101gEventBuilder.buildInitiationContent(
            snapshot: makeSnapshot(),
            holes: makeHoles()
        )

        let differentSnapshot = CourseSnapshotRecord(
            courseHash: "xyz",
            courseName: "Different Course",
            teeSet: "Red",
            holeCount: 9,
            canonicalJSON: "{}",
            createdAt: "2026-01-01T00:00:00Z"
        )
        let content2 = NIP101gEventBuilder.buildInitiationContent(
            snapshot: differentSnapshot,
            holes: makeHoles()
        )

        let hash1 = try NIP101gEventBuilder.computeRulesHash(content: content1)
        let hash2 = try NIP101gEventBuilder.computeRulesHash(content: content2)

        XCTAssertEqual(hash1, hash2, "Same rules template must produce same hash regardless of course")
    }

    // MARK: - Hash Parity with CourseSnapshotRepository

    func testCourseHash_ParityWithCourseSnapshotRepository() throws {
        // Build the same course data that CourseSnapshotRepository would canonicalize.
        // CourseSnapshotRepository builds: {"course_name":...,"hole_count":...,"holes":[...],"tee_set":...}
        // NIP101gEventBuilder builds from the same content via CourseSnapshotContent encoding.
        //
        // These use the same RAIDCanonicalizer + RAIDHasher, so canonical JSON → hash must match.

        let canonicalizer = RAIDCanonicalizer()
        let hasher = RAIDHasher()

        // Use a 2-hole snapshot so all values align
        let twoHoleSnapshot = CourseSnapshotRecord(
            courseHash: "test",
            courseName: "Fowler's Mill Golf Course",
            teeSet: "Silver M",
            holeCount: 2,
            canonicalJSON: "{}",
            createdAt: "2026-01-01T00:00:00Z"
        )
        // Use nil handicapIndex to match production: CourseSnapshotRepository
        // always writes NSNull() for handicap_index in canonical JSON.
        let twoHoles = [
            CourseHoleRecord(courseHash: "test", holeNumber: 1, par: 4, handicapIndex: nil),
            CourseHoleRecord(courseHash: "test", holeNumber: 2, par: 4, handicapIndex: nil),
        ]

        // Build the NIP-101g way
        let content = NIP101gEventBuilder.buildInitiationContent(
            snapshot: twoHoleSnapshot,
            holes: twoHoles
        )
        let nip101gHash = try NIP101gEventBuilder.computeCourseHash(
            content: content,
            canonicalizer: canonicalizer,
            hasher: hasher
        )

        // Build the same data the way CourseSnapshotRepository does it (raw dict → serialize → canonicalize → hash)
        // CourseSnapshotRepository always uses NSNull() for handicap_index (line 62 of ScorecardRepository.swift)
        let holesArray: [[String: Any]] = [
            ["handicap_index": NSNull(), "hole_number": 1, "par": 4],
            ["handicap_index": NSNull(), "hole_number": 2, "par": 4],
        ]

        let jsonDict: [String: Any] = [
            "course_name": "Fowler's Mill Golf Course",
            "hole_count": 2,
            "holes": holesArray,
            "tee_set": "Silver M"
        ]

        let rawJSON = try JSONSerialization.data(withJSONObject: jsonDict)
        let canonicalData = try canonicalizer.canonicalize(rawJSON)
        let repoHash = hasher.sha256Hex(canonicalData)

        // The NIP-101g course snapshot JSON has the same keys but different structure
        // (it's Codable-encoded vs dict-based). The canonical form should match IF
        // the JSON keys and values are identical.
        //
        // Note: This test verifies that canonicalization of equivalent JSON produces
        // the same hash. If this fails, it means the Codable encoding produces different
        // JSON structure than the dict-based approach, which needs investigation.

        // Both should be valid 64-char hex hashes
        XCTAssertEqual(nip101gHash.count, 64)
        XCTAssertEqual(repoHash.count, 64)

        // Verify both use same canonicalization pipeline
        // (They may differ if Codable encoding doesn't match dict ordering,
        //  but canonical form normalizes this)
        XCTAssertEqual(nip101gHash, repoHash,
            "NIP-101g course hash must match CourseSnapshotRepository hash for equivalent data")
    }

    // MARK: - Event Kind Verification

    func testBuildInitiationEvent_Kind1501() throws {
        let content = NIP101gEventBuilder.buildInitiationContent(
            snapshot: makeSnapshot(),
            holes: makeHoles()
        )
        let courseHash = try NIP101gEventBuilder.computeCourseHash(content: content)
        let rulesHash = try NIP101gEventBuilder.computeRulesHash(content: content)

        // This just verifies the builder doesn't throw — we can't inspect
        // the EventBuilder internals without signing, but we verify construction succeeds
        let _ = try NIP101gEventBuilder.buildInitiationEvent(
            content: content,
            courseHash: courseHash,
            rulesHash: rulesHash,
            playerPubkeys: ["abc123hex"],
            date: "2026-02-12"
        )
    }

    func testBuildFinalRecordEvent_Kind1502() throws {
        let scores: [(holeNumber: Int, strokes: Int)] = [
            (1, 5), (2, 4), (3, 3), (4, 5), (5, 4),
            (6, 6), (7, 5), (8, 4), (9, 4)
        ]
        let total = scores.reduce(0) { $0 + $1.strokes }

        let _ = try NIP101gEventBuilder.buildFinalRecordEvent(
            initiationEventId: "deadbeef1234",
            scores: scores,
            total: total,
            playerPubkeys: ["abc123hex"],
            notes: nil
        )
    }

    func testBuildFinalRecordEvent_WithNotes() throws {
        let scores: [(holeNumber: Int, strokes: Int)] = [(1, 4), (2, 5)]
        let _ = try NIP101gEventBuilder.buildFinalRecordEvent(
            initiationEventId: "deadbeef",
            scores: scores,
            total: 9,
            playerPubkeys: [],
            notes: "Great round!"
        )
    }
}
