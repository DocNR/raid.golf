// IngestIntegrationTests.swift
// RAID Golf - iOS Port - Phase 4A Integration Tests
//
// Phase 4A: Data Confidence Harness
//
// Purpose:
// - Prove end-to-end pipeline correctness
// - Validate deterministic classification and aggregation
// - Enforce kernel invariants
//
// Tests:
// 1. Fixture ingest integration (CSV → persisted shots)
// 2. Classification + aggregation determinism
// 3. Immutability guardrail (consolidated)

import XCTest
import GRDB
@testable import RAID

final class IngestIntegrationTests: XCTestCase {
    
    // MARK: - Test Helpers
    
    /// Result of fixture ingest setup
    struct FixtureIngestResult {
        let dbQueue: DatabaseQueue
        let sessionId: Int64
        let ingestResult: IngestResult
    }
    
    /// Create fresh database and ingest CSV fixture
    /// - Returns: Database, session ID, and ingest result
    /// - Throws: Database or ingest error
    private func makeFreshDBAndIngestFixture() throws -> FixtureIngestResult {
        // Create fresh in-memory database with migrations
        let dbQueue = try DatabaseQueue.createRAIDDatabase(at: ":memory:")
        
        // Load CSV fixture from test bundle
        guard let csvURL = Bundle(for: type(of: self)).url(
            forResource: "rapsodo_mlm2pro_mixed_club_sample",
            withExtension: "csv"
        ) else {
            XCTFail("CSV fixture not found in test bundle. Add tests/vectors/sessions/rapsodo_mlm2pro_mixed_club_sample.csv as a resource to RAIDTests target.")
            throw NSError(domain: "IngestIntegrationTests", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "CSV fixture not found"])
        }
        
        // Create repositories
        let sessionRepo = SessionRepository(dbQueue: dbQueue)
        let shotRepo = ShotRepository(dbQueue: dbQueue)
        
        // Ingest fixture
        let result = try RapsodoIngest.ingest(
            csvURL: csvURL,
            sessionRepository: sessionRepo,
            shotRepository: shotRepo,
            sessionDate: "2026-02-06T12:00:00Z",
            deviceType: "Rapsodo MLM2Pro",
            location: "Test Range"
        )
        
        return FixtureIngestResult(
            dbQueue: dbQueue,
            sessionId: result.sessionId,
            ingestResult: result
        )
    }
    
    // MARK: - Test 1: Fixture Ingest Integration
    
    func testFixtureIngestEndToEnd() throws {
        print("\n=== Phase 4A.1 Test 1: Fixture Ingest Integration ===")
        
        // Setup: Fresh DB + ingest fixture
        let fixture = try makeFreshDBAndIngestFixture()
        let result = fixture.ingestResult
        
        // Fixture properties (documented in Data_Confidence_Report.md)
        let expectedShotCount = 15  // 6 × 7i + 9 × 5i
        let expectedSkippedCount = 0  // Clean fixture (no malformed rows)
        
        // Assert: Import counts
        XCTAssertEqual(result.importedCount, expectedShotCount,
                      "Imported count should match expected shot rows")
        XCTAssertEqual(result.skippedCount, expectedSkippedCount,
                      "Skipped count should be 0 for clean fixture")
        XCTAssertEqual(result.importedCount + result.skippedCount, expectedShotCount,
                      "Imported + skipped should equal expected rows")
        
        print("✅ Import counts: imported=\(result.importedCount), skipped=\(result.skippedCount)")
        
        // Assert: Shots are fetchable by session_id
        let shotRepo = ShotRepository(dbQueue: fixture.dbQueue)
        let shots = try shotRepo.fetchShots(forSession: fixture.sessionId)
        
        XCTAssertEqual(shots.count, expectedShotCount,
                      "Fetched shot count should match imported count")
        
        print("✅ Fetched \(shots.count) shots by session_id")
        
        // Assert: source_row_index is unique and sequential (0..14)
        let rowIndices = shots.map { $0.sourceRowIndex }
        let uniqueIndices = Set(rowIndices)
        
        XCTAssertEqual(uniqueIndices.count, expectedShotCount,
                      "source_row_index values should be unique")
        XCTAssertEqual(rowIndices.sorted(), Array(0..<expectedShotCount),
                      "source_row_index should be exactly 0..14")
        
        print("✅ source_row_index is unique and sequential: \(rowIndices.sorted())")
        
        // Assert: FK integrity (all shots reference the created session_id)
        let sessionIds = Set(shots.map { $0.sessionId })
        XCTAssertEqual(sessionIds.count, 1,
                      "All shots should reference the same session")
        XCTAssertEqual(sessionIds.first, fixture.sessionId,
                      "All shots should reference the created session_id")
        
        print("✅ FK integrity: all shots reference session_id=\(fixture.sessionId)")
        
        print("✅ PASS: Fixture ingest integration test")
    }
    
    // MARK: - Test 2: Classification + Aggregation Determinism
    
    func testClassificationAggregationDeterminism() throws {
        print("\n=== Phase 4A.1 Test 2: Classification + Aggregation Determinism ===")
        
        // Setup: Fresh DB + ingest fixture
        let fixture = try makeFreshDBAndIngestFixture()
        
        // Load template fixture via repository path (exercises canonicalization + hashing)
        guard let templateURL = Bundle(for: type(of: self)).url(
            forResource: "fixture_a",
            withExtension: "json"
        ) else {
            XCTFail("Template fixture not found in test bundle. Add tests/vectors/templates/fixture_a.json as a resource to RAIDTests target.")
            return
        }
        
        let templateData = try Data(contentsOf: templateURL)
        
        // Insert template via repository (computes hash)
        let templateRepo = TemplateRepository(dbQueue: fixture.dbQueue)
        let templateRecord = try templateRepo.insertTemplate(rawJSON: templateData)
        
        print("✅ Template inserted via repository: hash=\(templateRecord.hash)")
        
        // Fetch template deterministically (by hash)
        guard let fetchedTemplate = try templateRepo.fetchTemplate(byHash: templateRecord.hash) else {
            XCTFail("Template should be fetchable by hash")
            return
        }
        
        // Decode to KPITemplate
        let canonicalData = Data(fetchedTemplate.canonicalJSON.utf8)
        let kpiTemplate = try JSONDecoder().decode(KPITemplate.self, from: canonicalData)
        
        XCTAssertEqual(kpiTemplate.club, "7i", "Template should be for 7i")
        
        print("✅ Template decoded: club=\(kpiTemplate.club), aggregation=\(kpiTemplate.aggregationMethod)")
        
        // Fetch shots for session
        let shotRepo = ShotRepository(dbQueue: fixture.dbQueue)
        let allShots = try shotRepo.fetchShots(forSession: fixture.sessionId)
        
        // Filter to 7i only
        let shots7i = allShots.filter { $0.club == "7i" }
        
        XCTAssertGreaterThan(shots7i.count, 0, "Should have at least one 7i shot")
        
        print("✅ Filtered to \(shots7i.count) × 7i shots")
        
        // Run classification + aggregation (first time)
        let classifications1 = try ShotClassifier.classify(shots7i, using: kpiTemplate)
        let summary1 = ShotClassifier.aggregate(classifications1, shots: shots7i)
        
        // Assert: A + B + C == totalShots
        XCTAssertEqual(summary1.aCount + summary1.bCount + summary1.cCount, summary1.totalShots,
                      "A + B + C should equal total shots")
        
        print("✅ First run: A=\(summary1.aCount), B=\(summary1.bCount), C=\(summary1.cCount), total=\(summary1.totalShots)")
        
        // Run classification + aggregation (second time)
        let classifications2 = try ShotClassifier.classify(shots7i, using: kpiTemplate)
        let summary2 = ShotClassifier.aggregate(classifications2, shots: shots7i)
        
        // Assert: Repeated runs produce identical results
        XCTAssertEqual(summary2.aCount, summary1.aCount, "A count should be deterministic")
        XCTAssertEqual(summary2.bCount, summary1.bCount, "B count should be deterministic")
        XCTAssertEqual(summary2.cCount, summary1.cCount, "C count should be deterministic")
        XCTAssertEqual(summary2.aPercentage, summary1.aPercentage, "A% should be deterministic")
        
        print("✅ Second run: identical results (A%=\(summary2.aPercentage?.description ?? "nil"))")
        
        // Re-ingest into fresh DB
        let fixture2 = try makeFreshDBAndIngestFixture()
        
        // Insert same template into fresh DB
        let templateRepo2 = TemplateRepository(dbQueue: fixture2.dbQueue)
        let templateRecord2 = try templateRepo2.insertTemplate(rawJSON: templateData)
        
        // Fetch and decode template
        guard let fetchedTemplate2 = try templateRepo2.fetchTemplate(byHash: templateRecord2.hash) else {
            XCTFail("Template should be fetchable in fresh DB")
            return
        }
        
        let canonicalData2 = Data(fetchedTemplate2.canonicalJSON.utf8)
        let kpiTemplate2 = try JSONDecoder().decode(KPITemplate.self, from: canonicalData2)
        
        // Fetch and filter shots
        let shotRepo2 = ShotRepository(dbQueue: fixture2.dbQueue)
        let allShots2 = try shotRepo2.fetchShots(forSession: fixture2.sessionId)
        let shots7i2 = allShots2.filter { $0.club == "7i" }
        
        // Run classification + aggregation (fresh DB)
        let classifications3 = try ShotClassifier.classify(shots7i2, using: kpiTemplate2)
        let summary3 = ShotClassifier.aggregate(classifications3, shots: shots7i2)
        
        // Assert: Fresh DB produces same A%
        XCTAssertEqual(summary3.aPercentage, summary1.aPercentage,
                      "Fresh DB ingest should produce identical A%")
        
        print("✅ Fresh DB run: identical A% (A%=\(summary3.aPercentage?.description ?? "nil"))")
        
        // Optional sanity checks
        XCTAssertGreaterThanOrEqual(summary1.aCount, 0, "A count should be non-negative")
        XCTAssertGreaterThanOrEqual(summary1.bCount, 0, "B count should be non-negative")
        XCTAssertGreaterThanOrEqual(summary1.cCount, 0, "C count should be non-negative")
        
        print("✅ PASS: Classification + aggregation determinism test")
    }
    
    // MARK: - Test 3: Immutability Guardrail (Consolidated)
    
    func testAuthoritativeShotMutationBlocked() throws {
        print("\n=== Phase 4A.1 Test 3: Immutability Guardrail ===")
        
        // Setup: Fresh DB + ingest fixture
        let fixture = try makeFreshDBAndIngestFixture()
        
        // Fetch a shot to attempt mutation
        let shotRepo = ShotRepository(dbQueue: fixture.dbQueue)
        let shots = try shotRepo.fetchShots(forSession: fixture.sessionId)
        
        guard let firstShot = shots.first else {
            XCTFail("Should have at least one shot")
            return
        }
        
        print("Testing mutation attempts on shot_id=\(firstShot.shotId)")
        
        // Attempt UPDATE - should hard-fail
        do {
            try fixture.dbQueue.write { db in
                try db.execute(
                    sql: "UPDATE shots SET carry = ? WHERE shot_id = ?",
                    arguments: [999.9, firstShot.shotId]
                )
            }
            XCTFail("UPDATE on authoritative shot should have been rejected by trigger")
        } catch let error as DatabaseError {
            let message = error.message ?? ""
            print("✅ UPDATE rejected: \(message)")
            XCTAssertTrue(message.lowercased().contains("immutable"),
                         "Error message should contain 'immutable': \(message)")
        }
        
        // Verify original value unchanged
        let shotsAfterUpdate = try shotRepo.fetchShots(forSession: fixture.sessionId)
        let shotAfterUpdate = shotsAfterUpdate.first { $0.shotId == firstShot.shotId }
        XCTAssertEqual(shotAfterUpdate?.carry, firstShot.carry,
                      "Original carry value should be unchanged after failed UPDATE")
        
        // Attempt DELETE - should hard-fail
        do {
            try fixture.dbQueue.write { db in
                try db.execute(
                    sql: "DELETE FROM shots WHERE shot_id = ?",
                    arguments: [firstShot.shotId]
                )
            }
            XCTFail("DELETE on authoritative shot should have been rejected by trigger")
        } catch let error as DatabaseError {
            let message = error.message ?? ""
            print("✅ DELETE rejected: \(message)")
            XCTAssertTrue(message.lowercased().contains("immutable"),
                         "Error message should contain 'immutable': \(message)")
        }
        
        // Verify row still exists
        let shotsAfterDelete = try shotRepo.fetchShots(forSession: fixture.sessionId)
        XCTAssertEqual(shotsAfterDelete.count, shots.count,
                      "Shot count should be unchanged after failed DELETE")
        XCTAssertNotNil(shotsAfterDelete.first { $0.shotId == firstShot.shotId },
                       "Shot should still exist after failed DELETE")
        
        print("✅ PASS: Authoritative shot mutation blocked (no silent mutation)")
    }

    // MARK: - Phase 4B: Trends v1

    func testTrendsV1_AllShotsAndAOnly_DeterministicAndStable() throws {
        print("\n=== Phase 4B Test: Trends v1 (allShots + aOnly) ===")

        // Fresh DB with deterministic setup
        let dbQueue = try DatabaseQueue.createRAIDDatabase(at: ":memory:")
        let sessionRepo = SessionRepository(dbQueue: dbQueue)
        let shotRepo = ShotRepository(dbQueue: dbQueue)
        let templateRepo = TemplateRepository(dbQueue: dbQueue)
        let trendsRepo = TrendsRepository(dbQueue: dbQueue, templateRepository: templateRepo)

        // Fixtures from test bundle
        guard let csvURL = Bundle(for: type(of: self)).url(
            forResource: "rapsodo_mlm2pro_mixed_club_sample",
            withExtension: "csv"
        ) else {
            XCTFail("CSV fixture not found in test bundle")
            return
        }

        guard let templateURL = Bundle(for: type(of: self)).url(
            forResource: "fixture_a",
            withExtension: "json"
        ) else {
            XCTFail("Template fixture not found in test bundle")
            return
        }

        let templateData = try Data(contentsOf: templateURL)
        let templateRecord = try templateRepo.insertTemplate(rawJSON: templateData)

        guard let fetchedTemplate = try templateRepo.fetchTemplate(byHash: templateRecord.hash) else {
            XCTFail("Template should be fetchable by hash")
            return
        }
        let canonicalData = Data(fetchedTemplate.canonicalJSON.utf8)
        let kpiTemplate = try JSONDecoder().decode(KPITemplate.self, from: canonicalData)

        // Deterministic distinct session_date values (no wall-clock dependency)
        let sessionDate1 = "2026-02-06T12:00:00Z"
        let sessionDate2 = "2026-02-07T12:00:00Z"

        _ = try RapsodoIngest.ingest(
            csvURL: csvURL,
            sessionRepository: sessionRepo,
            shotRepository: shotRepo,
            sessionDate: sessionDate1,
            deviceType: "Rapsodo MLM2Pro",
            location: "Test Range A"
        )

        _ = try RapsodoIngest.ingest(
            csvURL: csvURL,
            sessionRepository: sessionRepo,
            shotRepository: shotRepo,
            sessionDate: sessionDate2,
            deviceType: "Rapsodo MLM2Pro",
            location: "Test Range B"
        )

        // allShots (SQL-only AVG/COUNT(metric))
        let allShotsRun1 = try trendsRepo.fetchTrendPoints(
            club: "7i",
            metric: .carry,
            seriesType: .allShots
        )
        let allShotsRun2 = try trendsRepo.fetchTrendPoints(
            club: "7i",
            metric: .carry,
            seriesType: .allShots
        )

        XCTAssertEqual(allShotsRun1.count, 2, "allShots should return one point per session")
        XCTAssertEqual(allShotsRun1, allShotsRun2, "allShots should be deterministic across repeated runs")

        XCTAssertLessThanOrEqual(allShotsRun1[0].sessionDate, allShotsRun1[1].sessionDate,
                                 "allShots must be ordered by session_date ASC")
        if allShotsRun1[0].sessionDate == allShotsRun1[1].sessionDate {
            XCTAssertLessThan(allShotsRun1[0].sessionId, allShotsRun1[1].sessionId,
                              "Tie-break must be session_id ASC")
        }

        // aOnly (Swift-computed with latest template at query time)
        let aOnlyRun1 = try trendsRepo.fetchTrendPoints(
            club: "7i",
            metric: .carry,
            seriesType: .aOnly
        )
        let aOnlyRun2 = try trendsRepo.fetchTrendPoints(
            club: "7i",
            metric: .carry,
            seriesType: .aOnly
        )

        XCTAssertEqual(aOnlyRun1.count, 2, "aOnly should return one point per session")
        XCTAssertEqual(aOnlyRun1, aOnlyRun2, "aOnly should be deterministic across repeated runs")

        XCTAssertLessThanOrEqual(aOnlyRun1[0].sessionDate, aOnlyRun1[1].sessionDate,
                                 "aOnly must be ordered by session_date ASC")
        if aOnlyRun1[0].sessionDate == aOnlyRun1[1].sessionDate {
            XCTAssertLessThan(aOnlyRun1[0].sessionId, aOnlyRun1[1].sessionId,
                              "Tie-break must be session_id ASC")
        }

        // Required: every A-only point has non-null + stable templateHash
        XCTAssertTrue(aOnlyRun1.allSatisfy { $0.templateHash != nil },
                      "Every A-only trend point must include non-null templateHash")
        XCTAssertTrue(aOnlyRun1.allSatisfy { $0.templateHash == templateRecord.hash },
                      "A-only templateHash should be stable and match latest template")

        // Required: A-only nShots equals A-with-metric count per session
        for point in aOnlyRun1 {
            let sessionShots = try shotRepo.fetchShots(forSession: point.sessionId)
                .filter { $0.club == "7i" }
                .sorted { $0.sourceRowIndex < $1.sourceRowIndex }

            let classifications = try ShotClassifier.classify(sessionShots, using: kpiTemplate)
            let aShotIds = Set(classifications.filter { $0.grade == .a }.map { $0.shotId })
            let expectedAWithCarryCount = sessionShots
                .filter { aShotIds.contains($0.shotId) }
                .compactMap { $0.carry }
                .count

            XCTAssertEqual(point.nShots, expectedAWithCarryCount,
                           "A-only nShots must equal A-with-metric count for session \(point.sessionId)")
        }

        print("✅ PASS: Trends v1 allShots + aOnly deterministic semantics verified")
    }

    // MARK: - Phase 4C: Template Bootstrap

    func testTemplateBootstrapIsIdempotent() throws {
        print("\n=== Phase 4C Test: Template Bootstrap Idempotency ===")

        let dbQueue = try DatabaseQueue.createRAIDDatabase(at: ":memory:")

        // Simulate bootstrap with seed JSON (same format as template_seeds.json)
        let seedJSON: [[String: Any]] = [
            [
                "schema_version": "1.0",
                "club": "7i",
                "aggregation_method": "worst_metric",
                "metrics": [
                    "ball_speed": ["direction": "higher_is_better", "a_min": 104.0],
                    "smash_factor": ["direction": "higher_is_better", "a_min": 1.25, "b_min": 1.22],
                    "spin_rate": ["direction": "higher_is_better", "a_min": 4300.0, "b_min": 4200.0],
                    "descent_angle": ["direction": "higher_is_better", "a_min": 45.0, "b_min": 44.0]
                ]
            ]
        ]

        let repo = TemplateRepository(dbQueue: dbQueue)

        // First insert
        let seedData = try JSONSerialization.data(withJSONObject: seedJSON[0])
        let record = try repo.insertTemplate(rawJSON: seedData)
        print("✅ First insert: hash=\(record.hash.prefix(12))…")

        // Count templates after first insert
        let count1 = try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM kpi_templates") ?? 0
        }
        XCTAssertEqual(count1, 1, "Should have exactly 1 template after first insert")

        // Second insert (idempotent — should fail silently on PK constraint)
        do {
            _ = try repo.insertTemplate(rawJSON: seedData)
            XCTFail("Second insert should throw (PK constraint)")
        } catch {
            // Expected: PK violation
            print("✅ Second insert correctly rejected (PK constraint)")
        }

        // Count templates after second insert attempt
        let count2 = try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM kpi_templates") ?? 0
        }
        XCTAssertEqual(count2, 1, "Template count should be unchanged after duplicate insert")

        print("✅ PASS: Template bootstrap is idempotent")
    }

    func testSeedTemplateDecodesAsKPITemplate() throws {
        print("\n=== Phase 4C Test: Seed Template Decode ===")

        let dbQueue = try DatabaseQueue.createRAIDDatabase(at: ":memory:")

        // Same seed as template_seeds.json
        let seed: [String: Any] = [
            "schema_version": "1.0",
            "club": "7i",
            "aggregation_method": "worst_metric",
            "metrics": [
                "ball_speed": ["direction": "higher_is_better", "a_min": 104.0],
                "smash_factor": ["direction": "higher_is_better", "a_min": 1.25, "b_min": 1.22],
                "spin_rate": ["direction": "higher_is_better", "a_min": 4300.0, "b_min": 4200.0],
                "descent_angle": ["direction": "higher_is_better", "a_min": 45.0, "b_min": 44.0]
            ]
        ]

        let repo = TemplateRepository(dbQueue: dbQueue)
        let seedData = try JSONSerialization.data(withJSONObject: seed)
        _ = try repo.insertTemplate(rawJSON: seedData)

        // Fetch latest template for 7i
        guard let fetched = try repo.fetchLatestTemplate(forClub: "7i") else {
            XCTFail("Should fetch latest 7i template after bootstrap")
            return
        }

        // Decode canonical JSON to KPITemplate
        let canonicalData = Data(fetched.canonicalJSON.utf8)
        let template = try JSONDecoder().decode(KPITemplate.self, from: canonicalData)

        XCTAssertEqual(template.club, "7i")
        XCTAssertEqual(template.schemaVersion, "1.0")
        XCTAssertEqual(template.aggregationMethod, "worst_metric")
        XCTAssertEqual(template.metrics.count, 4, "Should have 4 metrics")
        XCTAssertNotNil(template.metrics["ball_speed"])
        XCTAssertNotNil(template.metrics["smash_factor"])
        XCTAssertNotNil(template.metrics["spin_rate"])
        XCTAssertNotNil(template.metrics["descent_angle"])

        // Verify thresholds
        XCTAssertEqual(template.metrics["ball_speed"]?.aMin, 104.0)
        XCTAssertEqual(template.metrics["smash_factor"]?.aMin, 1.25)
        XCTAssertEqual(template.metrics["smash_factor"]?.bMin, 1.22)

        print("✅ Seed template: club=\(template.club), metrics=\(template.metrics.keys.sorted())")
        print("✅ PASS: Seed template decodes successfully as KPITemplate")
    }
}
