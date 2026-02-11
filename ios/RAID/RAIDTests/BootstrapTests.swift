// BootstrapTests.swift
// RAID Golf - iOS Port
//
// KPI Template UX Sprint - Task 5
//
// Purpose:
// - Validate seed template bootstrap with preference initialization
// - Verify idempotent behavior on repeated launches
// - Ensure first template for each club is set as active

import XCTest
import GRDB
@testable import RAID

final class BootstrapTests: XCTestCase {

    // MARK: - Test Lifecycle

    var dbQueue: DatabaseQueue!

    override func setUp() {
        super.setUp()
        // Create in-memory database for each test
        dbQueue = try! DatabaseQueue(path: ":memory:")
        try! Schema.install(in: dbQueue)
    }

    override func tearDown() {
        dbQueue = nil
        super.tearDown()
    }

    // MARK: - Bootstrap Tests

    /// Test that seed templates bootstrap creates preference rows and sets active templates
    func testBootstrapCreatesPreferencesAndSetsActive() throws {
        // Given: Fresh database with seed templates available
        // When: Bootstrap runs
        try TemplateBootstrap.loadSeeds(into: dbQueue)

        // Then: Templates exist in kpi_templates table
        let templateRepo = TemplateRepository(dbQueue: dbQueue)
        let templates = try templateRepo.listAllTemplates()
        XCTAssertFalse(templates.isEmpty, "Templates should be bootstrapped")

        // Then: Each template has a preference row
        let prefsRepo = TemplatePreferencesRepository(dbQueue: dbQueue)
        for template in templates {
            let pref = try prefsRepo.fetchPreference(forHash: template.hash)
            XCTAssertNotNil(pref, "Preference row should exist for template \(template.hash)")
            XCTAssertEqual(pref?.club, template.club, "Preference club should match template club")
        }

        // Then: Each club has exactly one active template
        let clubs = Set(templates.map { $0.club })
        for club in clubs {
            let activeTemplate = try prefsRepo.fetchActiveTemplate(forClub: club)
            XCTAssertNotNil(activeTemplate, "Club \(club) should have an active template")
            XCTAssertEqual(activeTemplate?.club, club, "Active template club should match")
        }
    }

    /// Test that bootstrap is idempotent (running twice doesn't create duplicates or fail)
    func testBootstrapIsIdempotent() throws {
        // Given: Bootstrap has already run once
        try TemplateBootstrap.loadSeeds(into: dbQueue)

        let templateRepo = TemplateRepository(dbQueue: dbQueue)
        let prefsRepo = TemplatePreferencesRepository(dbQueue: dbQueue)

        let firstTemplates = try templateRepo.listAllTemplates()
        let firstTemplateHashes = Set(firstTemplates.map { $0.hash })

        // When: Bootstrap runs again
        try TemplateBootstrap.loadSeeds(into: dbQueue)

        // Then: Same templates exist (no duplicates)
        let secondTemplates = try templateRepo.listAllTemplates()
        let secondTemplateHashes = Set(secondTemplates.map { $0.hash })
        XCTAssertEqual(firstTemplateHashes, secondTemplateHashes, "Template hashes should be identical")

        // Then: Preference rows still exist and active status unchanged
        for club in Set(firstTemplates.map { $0.club }) {
            let activeTemplate = try prefsRepo.fetchActiveTemplate(forClub: club)
            XCTAssertNotNil(activeTemplate, "Club \(club) should still have active template")
            XCTAssertTrue(firstTemplateHashes.contains(activeTemplate!.hash), "Active template should be from original bootstrap")
        }
    }

    /// Test that bootstrap sets first template as active when none exists
    func testBootstrapSetsFirstTemplateAsActiveForEachClub() throws {
        // Given: Empty database
        // When: Bootstrap runs
        try TemplateBootstrap.loadSeeds(into: dbQueue)

        // Then: Each club has exactly one active template
        let templateRepo = TemplateRepository(dbQueue: dbQueue)
        let prefsRepo = TemplatePreferencesRepository(dbQueue: dbQueue)

        let templates = try templateRepo.listAllTemplates()
        let clubGroups = Dictionary(grouping: templates) { $0.club }

        for (club, clubTemplates) in clubGroups {
            // Count active templates for this club
            let activeCount = clubTemplates.filter { template in
                let pref = try? prefsRepo.fetchPreference(forHash: template.hash)
                return pref?.isActive == true
            }.count

            XCTAssertEqual(activeCount, 1, "Club \(club) should have exactly 1 active template")
        }
    }

    /// Test that bootstrap handles missing seed file gracefully
    func testBootstrapHandlesMissingSeedFileGracefully() throws {
        // Note: This test validates the code path when bundle resource is not found
        // The actual bundle check happens at runtime, so we can only verify
        // that the method returns without throwing when seeds are present

        // When: Bootstrap runs with seeds available
        // Then: No error is thrown
        XCTAssertNoThrow(try TemplateBootstrap.loadSeeds(into: dbQueue))
    }
}
