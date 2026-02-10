// KernelTests.swift
// RAID Golf - iOS Port - Kernel Test Harness
//
// Phase 2: Kernel Harness Tests
//
// Purpose:
// - Validate Swift kernel implementation against Python reference
// - All tests must pass before proceeding to Phase 3
//
// Test Vectors:
// - JCS vectors: jcs_vectors.json (12 vectors) - added as test bundle resource
// - Template hashes: template_hashes.json
// - Session CSV: rapsodo_mlm2pro_mixed_club_sample.csv
//
// Exit Criteria:
// - All JCS canonicalization tests pass (byte-for-byte match)
// - All template hash tests match golden values exactly
// - SQLite immutability triggers block UPDATE/DELETE
// - Repository read path never calls canonicalize/hash

import XCTest
import CryptoKit
import GRDB
@testable import RAID

final class KernelTests: XCTestCase {
    
    // MARK: - Test Vector Loading
    
    struct JCSVector: Codable {
        let name: String
        let description: String
        let input: AnyCodable
        let canonical: String
        let sha256: String
    }
    
    struct JCSVectors: Codable {
        let vectors: [JCSVector]
    }
    
    /// Load JCS test vectors from bundle
    func loadJCSVectors() throws -> [JCSVector] {
        guard let url = Bundle(for: type(of: self)).url(forResource: "jcs_vectors", withExtension: "json") else {
            XCTFail("jcs_vectors.json not found in test bundle. Add tests/vectors/jcs_vectors.json as a resource to RAIDTests target.")
            return []
        }
        
        let data = try Data(contentsOf: url)
        let decoded = try JSONDecoder().decode(JCSVectors.self, from: data)
        return decoded.vectors
    }
    
    // MARK: - Phase 2.1: JCS Canonicalization Tests
    
    func testAllJCSVectors() throws {
        let vectors = try loadJCSVectors()
        XCTAssertEqual(vectors.count, 12, "Expected 12 JCS test vectors")
        
        for vector in vectors {
            print("\n=== Testing Vector: \(vector.name) ===")
            print("Description: \(vector.description)")
            
            // Parse input JSON - use JSONSerialization directly to avoid normalization
            let inputObj: Any
            if vector.name == "zero_normalization" {
                // Special case: JSONSerialization normalizes -0.0 to 0.0 during parsing.
                // Manually construct input with true negative zero to test canonicalization behavior.
                let negativeZero = Double(bitPattern: 0x8000_0000_0000_0000)
                inputObj = [
                    "negative_zero": negativeZero,
                    "zero": 0
                ] as [String: Any]
            } else {
                // Normal case: parse vector input JSON string directly
                let inputData = try JSONSerialization.data(withJSONObject: vector.input.value, options: [])
                inputObj = try JSONSerialization.jsonObject(with: inputData, options: [])
            }
            
            // Canonicalize
            let canonical: String
            do {
                canonical = try RAIDCanonical.canonicalize(inputObj)
            } catch {
                XCTFail("[\(vector.name)] Canonicalization failed: \(error)")
                continue
            }
            
            // Compare canonical string byte-for-byte
            if canonical != vector.canonical {
                print("❌ CANONICAL MISMATCH")
                print("Input JSON: \(vector.input.value)")
                print("Expected: \(vector.canonical)")
                print("Actual:   \(canonical)")
                XCTFail("[\(vector.name)] Canonical string mismatch")
                continue
            }
            
            // Compute SHA-256
            let canonicalData = Data(canonical.utf8)
            let digest = SHA256.hash(data: canonicalData)
            let actualHash = digest.map { String(format: "%02x", $0) }.joined()
            
            // Compare hash
            if actualHash != vector.sha256 {
                print("❌ HASH MISMATCH")
                print("Canonical: \(canonical)")
                print("Expected hash: \(vector.sha256)")
                print("Actual hash:   \(actualHash)")
                XCTFail("[\(vector.name)] SHA-256 hash mismatch")
                continue
            }
            
            print("✅ PASS - Canonical: \(canonical)")
            print("✅ PASS - Hash: \(actualHash)")
        }
    }
    
    // Individual vector tests for granular failure reporting
    
    func testJCSVector01_SimpleKeyOrdering() throws {
        let vectors = try loadJCSVectors()
        guard let vector = vectors.first(where: { $0.name == "simple_key_ordering" }) else {
            XCTFail("Vector 'simple_key_ordering' not found")
            return
        }
        
        let inputData = try JSONSerialization.data(withJSONObject: vector.input.value, options: [])
        let inputObj = try JSONSerialization.jsonObject(with: inputData, options: [])
        let canonical = try RAIDCanonical.canonicalize(inputObj)
        
        XCTAssertEqual(canonical, vector.canonical, "Canonical string mismatch for \(vector.name)")
        
        let canonicalData = Data(canonical.utf8)
        let digest = SHA256.hash(data: canonicalData)
        let actualHash = digest.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(actualHash, vector.sha256, "SHA-256 hash mismatch for \(vector.name)")
    }
    
    func testJCSVector02_NestedKeyOrdering() throws {
        let vectors = try loadJCSVectors()
        guard let vector = vectors.first(where: { $0.name == "nested_key_ordering" }) else {
            XCTFail("Vector 'nested_key_ordering' not found")
            return
        }
        
        let inputData = try JSONSerialization.data(withJSONObject: vector.input.value, options: [])
        let inputObj = try JSONSerialization.jsonObject(with: inputData, options: [])
        let canonical = try RAIDCanonical.canonicalize(inputObj)
        
        XCTAssertEqual(canonical, vector.canonical, "Canonical string mismatch for \(vector.name)")
        
        let canonicalData = Data(canonical.utf8)
        let digest = SHA256.hash(data: canonicalData)
        let actualHash = digest.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(actualHash, vector.sha256, "SHA-256 hash mismatch for \(vector.name)")
    }
    
    func testJCSVector03_WhitespaceElimination() throws {
        let vectors = try loadJCSVectors()
        guard let vector = vectors.first(where: { $0.name == "whitespace_elimination" }) else {
            XCTFail("Vector 'whitespace_elimination' not found")
            return
        }
        
        let inputData = try JSONSerialization.data(withJSONObject: vector.input.value, options: [])
        let inputObj = try JSONSerialization.jsonObject(with: inputData, options: [])
        let canonical = try RAIDCanonical.canonicalize(inputObj)
        
        XCTAssertEqual(canonical, vector.canonical, "Canonical string mismatch for \(vector.name)")
        
        let canonicalData = Data(canonical.utf8)
        let digest = SHA256.hash(data: canonicalData)
        let actualHash = digest.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(actualHash, vector.sha256, "SHA-256 hash mismatch for \(vector.name)")
    }
    
    func testJCSVector04_IntegerVsDecimal() throws {
        let vectors = try loadJCSVectors()
        guard let vector = vectors.first(where: { $0.name == "integer_vs_decimal" }) else {
            XCTFail("Vector 'integer_vs_decimal' not found")
            return
        }
        
        let inputData = try JSONSerialization.data(withJSONObject: vector.input.value, options: [])
        let inputObj = try JSONSerialization.jsonObject(with: inputData, options: [])
        let canonical = try RAIDCanonical.canonicalize(inputObj)
        
        XCTAssertEqual(canonical, vector.canonical, "Canonical string mismatch for \(vector.name)")
        
        let canonicalData = Data(canonical.utf8)
        let digest = SHA256.hash(data: canonicalData)
        let actualHash = digest.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(actualHash, vector.sha256, "SHA-256 hash mismatch for \(vector.name)")
    }
    
    func testJCSVector05_ZeroNormalization() throws {
        let vectors = try loadJCSVectors()
        guard let vector = vectors.first(where: { $0.name == "zero_normalization" }) else {
            XCTFail("Vector 'zero_normalization' not found")
            return
        }
        
        // Special case: JSONSerialization normalizes -0.0 to 0.0 during parsing.
        // Manually construct input with true negative zero to test canonicalization behavior.
        let negativeZero = Double(bitPattern: 0x8000_0000_0000_0000)
        let inputObj: [String: Any] = [
            "negative_zero": negativeZero,
            "zero": 0
        ]
        
        let canonical = try RAIDCanonical.canonicalize(inputObj)
        
        XCTAssertEqual(canonical, vector.canonical, "Canonical string mismatch for \(vector.name)")
        
        let canonicalData = Data(canonical.utf8)
        let digest = SHA256.hash(data: canonicalData)
        let actualHash = digest.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(actualHash, vector.sha256, "SHA-256 hash mismatch for \(vector.name)")
    }
    
    func testJCSVector06_NegativeNumbers() throws {
        let vectors = try loadJCSVectors()
        guard let vector = vectors.first(where: { $0.name == "negative_numbers" }) else {
            XCTFail("Vector 'negative_numbers' not found")
            return
        }
        
        let inputData = try JSONSerialization.data(withJSONObject: vector.input.value, options: [])
        let inputObj = try JSONSerialization.jsonObject(with: inputData, options: [])
        let canonical = try RAIDCanonical.canonicalize(inputObj)
        
        XCTAssertEqual(canonical, vector.canonical, "Canonical string mismatch for \(vector.name)")
        
        let canonicalData = Data(canonical.utf8)
        let digest = SHA256.hash(data: canonicalData)
        let actualHash = digest.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(actualHash, vector.sha256, "SHA-256 hash mismatch for \(vector.name)")
    }
    
    func testJCSVector07_UnicodeStrings() throws {
        let vectors = try loadJCSVectors()
        guard let vector = vectors.first(where: { $0.name == "unicode_strings" }) else {
            XCTFail("Vector 'unicode_strings' not found")
            return
        }
        
        let inputData = try JSONSerialization.data(withJSONObject: vector.input.value, options: [])
        let inputObj = try JSONSerialization.jsonObject(with: inputData, options: [])
        let canonical = try RAIDCanonical.canonicalize(inputObj)
        
        XCTAssertEqual(canonical, vector.canonical, "Canonical string mismatch for \(vector.name)")
        
        let canonicalData = Data(canonical.utf8)
        let digest = SHA256.hash(data: canonicalData)
        let actualHash = digest.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(actualHash, vector.sha256, "SHA-256 hash mismatch for \(vector.name)")
    }
    
    func testJCSVector08_ArrayOrderPreserved() throws {
        let vectors = try loadJCSVectors()
        guard let vector = vectors.first(where: { $0.name == "array_order_preserved" }) else {
            XCTFail("Vector 'array_order_preserved' not found")
            return
        }
        
        let inputData = try JSONSerialization.data(withJSONObject: vector.input.value, options: [])
        let inputObj = try JSONSerialization.jsonObject(with: inputData, options: [])
        let canonical = try RAIDCanonical.canonicalize(inputObj)
        
        XCTAssertEqual(canonical, vector.canonical, "Canonical string mismatch for \(vector.name)")
        
        let canonicalData = Data(canonical.utf8)
        let digest = SHA256.hash(data: canonicalData)
        let actualHash = digest.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(actualHash, vector.sha256, "SHA-256 hash mismatch for \(vector.name)")
    }
    
    func testJCSVector09_NestedArraysAndObjects() throws {
        let vectors = try loadJCSVectors()
        guard let vector = vectors.first(where: { $0.name == "nested_arrays_and_objects" }) else {
            XCTFail("Vector 'nested_arrays_and_objects' not found")
            return
        }
        
        let inputData = try JSONSerialization.data(withJSONObject: vector.input.value, options: [])
        let inputObj = try JSONSerialization.jsonObject(with: inputData, options: [])
        let canonical = try RAIDCanonical.canonicalize(inputObj)
        
        XCTAssertEqual(canonical, vector.canonical, "Canonical string mismatch for \(vector.name)")
        
        let canonicalData = Data(canonical.utf8)
        let digest = SHA256.hash(data: canonicalData)
        let actualHash = digest.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(actualHash, vector.sha256, "SHA-256 hash mismatch for \(vector.name)")
    }
    
    func testJCSVector10_EmptyStructures() throws {
        let vectors = try loadJCSVectors()
        guard let vector = vectors.first(where: { $0.name == "empty_structures" }) else {
            XCTFail("Vector 'empty_structures' not found")
            return
        }
        
        let inputData = try JSONSerialization.data(withJSONObject: vector.input.value, options: [])
        let inputObj = try JSONSerialization.jsonObject(with: inputData, options: [])
        let canonical = try RAIDCanonical.canonicalize(inputObj)
        
        XCTAssertEqual(canonical, vector.canonical, "Canonical string mismatch for \(vector.name)")
        
        let canonicalData = Data(canonical.utf8)
        let digest = SHA256.hash(data: canonicalData)
        let actualHash = digest.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(actualHash, vector.sha256, "SHA-256 hash mismatch for \(vector.name)")
    }
    
    func testJCSVector11_BooleanAndNull() throws {
        let vectors = try loadJCSVectors()
        guard let vector = vectors.first(where: { $0.name == "boolean_and_null" }) else {
            XCTFail("Vector 'boolean_and_null' not found")
            return
        }
        
        let inputData = try JSONSerialization.data(withJSONObject: vector.input.value, options: [])
        let inputObj = try JSONSerialization.jsonObject(with: inputData, options: [])
        let canonical = try RAIDCanonical.canonicalize(inputObj)
        
        XCTAssertEqual(canonical, vector.canonical, "Canonical string mismatch for \(vector.name)")
        
        let canonicalData = Data(canonical.utf8)
        let digest = SHA256.hash(data: canonicalData)
        let actualHash = digest.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(actualHash, vector.sha256, "SHA-256 hash mismatch for \(vector.name)")
    }
    
    func testJCSVector12_DecimalPrecision() throws {
        let vectors = try loadJCSVectors()
        guard let vector = vectors.first(where: { $0.name == "decimal_precision" }) else {
            XCTFail("Vector 'decimal_precision' not found")
            return
        }
        
        let inputData = try JSONSerialization.data(withJSONObject: vector.input.value, options: [])
        let inputObj = try JSONSerialization.jsonObject(with: inputData, options: [])
        let canonical = try RAIDCanonical.canonicalize(inputObj)
        
        XCTAssertEqual(canonical, vector.canonical, "Canonical string mismatch for \(vector.name)")
        
        let canonicalData = Data(canonical.utf8)
        let digest = SHA256.hash(data: canonicalData)
        let actualHash = digest.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(actualHash, vector.sha256, "SHA-256 hash mismatch for \(vector.name)")
    }
    
    // MARK: - Phase 2.2: Template Hash Fixtures
    
    func testTemplateHashFixtureA() throws {
        try verifyTemplateHashFixture("fixture_a")
    }
    
    func testTemplateHashFixtureB() throws {
        try verifyTemplateHashFixture("fixture_b")
    }
    
    func testTemplateHashFixtureC() throws {
        try verifyTemplateHashFixture("fixture_c")
    }
    
    /// Verify template hash matches golden value
    private func verifyTemplateHashFixture(_ fixtureName: String) throws {
        print("\n=== Testing Template Hash: \(fixtureName) ===")
        
        // Load template JSON
        let template = try loadTemplateFixture(fixtureName)
        
        // Compute hash
        let actualHash = try RAIDHashing.computeTemplateHash(template)
        
        // Load expected hash
        let expectedHash = try loadExpectedHash(fixtureName)
        
        // Get canonical JSON for diagnostics
        let canonical = try RAIDCanonical.canonicalize(template)
        
        // Compare
        if actualHash != expectedHash {
            print("❌ HASH MISMATCH")
            print("Fixture: \(fixtureName)")
            print("Expected: \(expectedHash)")
            print("Actual:   \(actualHash)")
            print("Canonical JSON: \(canonical)")
            XCTFail("[\(fixtureName)] Template hash mismatch. Expected: \(expectedHash), Actual: \(actualHash)")
        } else {
            print("✅ PASS - Hash: \(actualHash)")
            print("Canonical: \(canonical)")
        }
    }
    
    /// Load template fixture from test bundle
    private func loadTemplateFixture(_ name: String) throws -> [String: Any] {
        guard let url = Bundle(for: type(of: self)).url(forResource: name, withExtension: "json") else {
            throw NSError(domain: "KernelTests", code: 1, 
                         userInfo: [NSLocalizedDescriptionKey: "\(name).json not found in test bundle. Ensure tests/vectors/templates/\(name).json is added as a resource to RAIDTests target."])
        }
        let data = try Data(contentsOf: url)
        guard let template = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "KernelTests", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "\(name).json is not a valid JSON object"])
        }
        return template
    }
    
    /// Load expected hash from golden values file
    private func loadExpectedHash(_ fixtureName: String) throws -> String {
        guard let url = Bundle(for: type(of: self)).url(forResource: "template_hashes", withExtension: "json") else {
            throw NSError(domain: "KernelTests", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "template_hashes.json not found in test bundle. Ensure tests/vectors/expected/template_hashes.json is added as a resource to RAIDTests target."])
        }
        let data = try Data(contentsOf: url)
        
        // Parse as dictionary (skip metadata fields starting with _)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "KernelTests", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "template_hashes.json is not a valid JSON object"])
        }
        
        guard let hash = json[fixtureName] as? String else {
            throw NSError(domain: "KernelTests", code: 3,
                         userInfo: [NSLocalizedDescriptionKey: "No hash found for '\(fixtureName)' in template_hashes.json"])
        }
        
        return hash
    }
    
    // MARK: - Phase 2.3: Schema Immutability Tests
    
    /// Create in-memory database with schema installed
    private func createTestDatabase() throws -> DatabaseQueue {
        let dbQueue = try DatabaseQueue()
        try Schema.install(in: dbQueue)
        return dbQueue
    }
    
    // MARK: Sessions Immutability (RTM-01)
    
    func testSessionUpdateRejected() throws {
        print("\n=== Testing Session UPDATE Rejection ===")
        let dbQueue = try createTestDatabase()
        
        // Insert a session
        var sessionId: Int64 = 0
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO sessions (session_date, source_file, device_type, location, ingested_at)
                VALUES (?, ?, ?, ?, ?)
                """, arguments: ["2026-02-06T12:00:00Z", "test.csv", "Rapsodo", "Range A", "2026-02-06T12:00:00Z"])
            sessionId = db.lastInsertedRowID
        }
        
        // Attempt to update source_file - should fail
        do {
            try dbQueue.write { db in
                try db.execute(sql: "UPDATE sessions SET source_file = ? WHERE session_id = ?",
                              arguments: ["modified.csv", sessionId])
            }
            XCTFail("UPDATE should have been rejected by trigger")
        } catch let error as DatabaseError {
            let message = error.message ?? ""
            print("✅ UPDATE rejected: \(message)")
            XCTAssertTrue(message.lowercased().contains("immutable"), 
                         "Error message should contain 'immutable': \(message)")
        }
        
        // Verify original value unchanged
        let sourceFile = try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT source_file FROM sessions WHERE session_id = ?", arguments: [sessionId])
        }
        XCTAssertEqual(sourceFile, "test.csv", "Original value should be unchanged")
    }
    
    func testSessionDeleteRejected() throws {
        print("\n=== Testing Session DELETE Rejection ===")
        let dbQueue = try createTestDatabase()
        
        // Insert a session
        var sessionId: Int64 = 0
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO sessions (session_date, source_file, device_type, location, ingested_at)
                VALUES (?, ?, ?, ?, ?)
                """, arguments: ["2026-02-06T12:00:00Z", "test.csv", "Rapsodo", "Range A", "2026-02-06T12:00:00Z"])
            sessionId = db.lastInsertedRowID
        }
        
        // Attempt to delete - should fail
        do {
            try dbQueue.write { db in
                try db.execute(sql: "DELETE FROM sessions WHERE session_id = ?", arguments: [sessionId])
            }
            XCTFail("DELETE should have been rejected by trigger")
        } catch let error as DatabaseError {
            let message = error.message ?? ""
            print("✅ DELETE rejected: \(message)")
            XCTAssertTrue(message.lowercased().contains("immutable"),
                         "Error message should contain 'immutable': \(message)")
        }
        
        // Verify row still exists
        let count = try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sessions WHERE session_id = ?", arguments: [sessionId])
        }
        XCTAssertEqual(count, 1, "Row should still exist")
    }
    
    func testSessionAllFieldsProtected() throws {
        print("\n=== Testing All Session Fields Protected ===")
        let dbQueue = try createTestDatabase()
        
        // Insert a session
        var sessionId: Int64 = 0
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO sessions (session_date, source_file, device_type, location, ingested_at)
                VALUES (?, ?, ?, ?, ?)
                """, arguments: ["2026-02-06T12:00:00Z", "test.csv", "Rapsodo", "Range A", "2026-02-06T12:00:00Z"])
            sessionId = db.lastInsertedRowID
        }
        
        // Test each field
        let fieldsToTest: [(String, String)] = [
            ("session_date", "2026-02-07T12:00:00Z"),
            ("device_type", "TrackMan"),
            ("location", "Indoor")
        ]
        
        for (field, newValue) in fieldsToTest {
            do {
                try dbQueue.write { db in
                    try db.execute(sql: "UPDATE sessions SET \(field) = ? WHERE session_id = ?",
                                  arguments: [newValue, sessionId])
                }
                XCTFail("UPDATE of \(field) should have been rejected")
            } catch let error as DatabaseError {
                print("✅ Field '\(field)' protected: \(error.message ?? "")")
            }
        }
    }
    
    // MARK: Templates Immutability (RTM-03)
    
    func testTemplateUpdateRejected() throws {
        print("\n=== Testing Template UPDATE Rejection ===")
        let dbQueue = try createTestDatabase()
        
        // Insert a template
        let templateHash = "a" + String(repeating: "0", count: 63) // Valid 64-char hex
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO kpi_templates (template_hash, schema_version, club, canonical_json, created_at)
                VALUES (?, ?, ?, ?, ?)
                """, arguments: [templateHash, "1.0", "7i", "{\"club\":\"7i\"}", "2026-02-06T12:00:00Z"])
        }
        
        // Attempt to update canonical_json - should fail
        do {
            try dbQueue.write { db in
                try db.execute(sql: "UPDATE kpi_templates SET canonical_json = ? WHERE template_hash = ?",
                              arguments: ["{\"modified\":true}", templateHash])
            }
            XCTFail("UPDATE should have been rejected by trigger")
        } catch let error as DatabaseError {
            let message = error.message ?? ""
            print("✅ UPDATE rejected: \(message)")
            XCTAssertTrue(message.lowercased().contains("immutable"),
                         "Error message should contain 'immutable': \(message)")
        }
        
        // Verify original value unchanged
        let canonicalJson = try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT canonical_json FROM kpi_templates WHERE template_hash = ?", 
                               arguments: [templateHash])
        }
        XCTAssertEqual(canonicalJson, "{\"club\":\"7i\"}", "Original value should be unchanged")
    }
    
    func testTemplateDeleteRejected() throws {
        print("\n=== Testing Template DELETE Rejection ===")
        let dbQueue = try createTestDatabase()
        
        // Insert a template
        let templateHash = "b" + String(repeating: "0", count: 63)
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO kpi_templates (template_hash, schema_version, club, canonical_json, created_at)
                VALUES (?, ?, ?, ?, ?)
                """, arguments: [templateHash, "1.0", "7i", "{\"club\":\"7i\"}", "2026-02-06T12:00:00Z"])
        }
        
        // Attempt to delete - should fail
        do {
            try dbQueue.write { db in
                try db.execute(sql: "DELETE FROM kpi_templates WHERE template_hash = ?", arguments: [templateHash])
            }
            XCTFail("DELETE should have been rejected by trigger")
        } catch let error as DatabaseError {
            let message = error.message ?? ""
            print("✅ DELETE rejected: \(message)")
            XCTAssertTrue(message.lowercased().contains("immutable"),
                         "Error message should contain 'immutable': \(message)")
        }
        
        // Verify row still exists
        let count = try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM kpi_templates WHERE template_hash = ?", 
                            arguments: [templateHash])
        }
        XCTAssertEqual(count, 1, "Row should still exist")
    }
    
    // MARK: Subsessions Immutability (RTM-02)
    
    func testSubsessionUpdateRejected() throws {
        print("\n=== Testing Subsession UPDATE Rejection ===")
        let dbQueue = try createTestDatabase()
        
        // Insert session and template
        var sessionId: Int64 = 0
        let templateHash = "c" + String(repeating: "0", count: 63)
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO sessions (session_date, source_file, ingested_at)
                VALUES (?, ?, ?)
                """, arguments: ["2026-02-06T12:00:00Z", "test.csv", "2026-02-06T12:00:00Z"])
            sessionId = db.lastInsertedRowID
            
            try db.execute(sql: """
                INSERT INTO kpi_templates (template_hash, schema_version, club, canonical_json, created_at)
                VALUES (?, ?, ?, ?, ?)
                """, arguments: [templateHash, "1.0", "7i", "{\"club\":\"7i\"}", "2026-02-06T12:00:00Z"])
        }
        
        // Insert subsession
        var subsessionId: Int64 = 0
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO club_subsessions (session_id, club, kpi_template_hash, shot_count, 
                                             validity_status, a_count, b_count, c_count, 
                                             a_percentage, analyzed_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [sessionId, "7i", templateHash, 20, "valid", 10, 8, 2, 50.0, "2026-02-06T12:00:00Z"])
            subsessionId = db.lastInsertedRowID
        }
        
        // Attempt to update a_count - should fail
        do {
            try dbQueue.write { db in
                try db.execute(sql: "UPDATE club_subsessions SET a_count = ? WHERE subsession_id = ?",
                              arguments: [15, subsessionId])
            }
            XCTFail("UPDATE should have been rejected by trigger")
        } catch let error as DatabaseError {
            let message = error.message ?? ""
            print("✅ UPDATE rejected: \(message)")
            XCTAssertTrue(message.lowercased().contains("immutable"),
                         "Error message should contain 'immutable': \(message)")
        }
        
        // Verify original value unchanged
        let aCount = try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT a_count FROM club_subsessions WHERE subsession_id = ?", 
                            arguments: [subsessionId])
        }
        XCTAssertEqual(aCount, 10, "Original value should be unchanged")
    }
    
    func testSubsessionDeleteRejected() throws {
        print("\n=== Testing Subsession DELETE Rejection ===")
        let dbQueue = try createTestDatabase()
        
        // Insert session and template
        var sessionId: Int64 = 0
        let templateHash = "d" + String(repeating: "0", count: 63)
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO sessions (session_date, source_file, ingested_at)
                VALUES (?, ?, ?)
                """, arguments: ["2026-02-06T12:00:00Z", "test.csv", "2026-02-06T12:00:00Z"])
            sessionId = db.lastInsertedRowID
            
            try db.execute(sql: """
                INSERT INTO kpi_templates (template_hash, schema_version, club, canonical_json, created_at)
                VALUES (?, ?, ?, ?, ?)
                """, arguments: [templateHash, "1.0", "7i", "{\"club\":\"7i\"}", "2026-02-06T12:00:00Z"])
        }
        
        // Insert subsession
        var subsessionId: Int64 = 0
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO club_subsessions (session_id, club, kpi_template_hash, shot_count,
                                             validity_status, a_count, b_count, c_count,
                                             a_percentage, analyzed_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [sessionId, "7i", templateHash, 20, "valid", 10, 8, 2, 50.0, "2026-02-06T12:00:00Z"])
            subsessionId = db.lastInsertedRowID
        }
        
        // Attempt to delete - should fail
        do {
            try dbQueue.write { db in
                try db.execute(sql: "DELETE FROM club_subsessions WHERE subsession_id = ?", 
                              arguments: [subsessionId])
            }
            XCTFail("DELETE should have been rejected by trigger")
        } catch let error as DatabaseError {
            let message = error.message ?? ""
            print("✅ DELETE rejected: \(message)")
            XCTAssertTrue(message.lowercased().contains("immutable"),
                         "Error message should contain 'immutable': \(message)")
        }
        
        // Verify row still exists
        let count = try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM club_subsessions WHERE subsession_id = ?",
                            arguments: [subsessionId])
        }
        XCTAssertEqual(count, 1, "Row should still exist")
    }
    
    func testSubsessionTemplateSwapRejected() throws {
        print("\n=== Testing Subsession Template Swap Rejection ===")
        let dbQueue = try createTestDatabase()
        
        // Insert session and two templates
        var sessionId: Int64 = 0
        let templateHash1 = "e" + String(repeating: "0", count: 63)
        let templateHash2 = "f" + String(repeating: "0", count: 63)
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO sessions (session_date, source_file, ingested_at)
                VALUES (?, ?, ?)
                """, arguments: ["2026-02-06T12:00:00Z", "test.csv", "2026-02-06T12:00:00Z"])
            sessionId = db.lastInsertedRowID
            
            try db.execute(sql: """
                INSERT INTO kpi_templates (template_hash, schema_version, club, canonical_json, created_at)
                VALUES (?, ?, ?, ?, ?)
                """, arguments: [templateHash1, "1.0", "7i", "{\"version\":\"1\"}", "2026-02-06T12:00:00Z"])
            
            try db.execute(sql: """
                INSERT INTO kpi_templates (template_hash, schema_version, club, canonical_json, created_at)
                VALUES (?, ?, ?, ?, ?)
                """, arguments: [templateHash2, "2.0", "7i", "{\"version\":\"2\"}", "2026-02-06T12:00:00Z"])
        }
        
        // Insert subsession with template1
        var subsessionId: Int64 = 0
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO club_subsessions (session_id, club, kpi_template_hash, shot_count,
                                             validity_status, a_count, b_count, c_count,
                                             a_percentage, analyzed_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [sessionId, "7i", templateHash1, 20, "valid", 10, 8, 2, 50.0, "2026-02-06T12:00:00Z"])
            subsessionId = db.lastInsertedRowID
        }
        
        // Attempt to swap to template2 - should fail
        do {
            try dbQueue.write { db in
                try db.execute(sql: "UPDATE club_subsessions SET kpi_template_hash = ? WHERE subsession_id = ?",
                              arguments: [templateHash2, subsessionId])
            }
            XCTFail("Template swap should have been rejected by trigger")
        } catch let error as DatabaseError {
            print("✅ Template swap rejected: \(error.message ?? "")")
        }
        
        // Verify original template reference unchanged
        let storedHash = try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT kpi_template_hash FROM club_subsessions WHERE subsession_id = ?",
                               arguments: [subsessionId])
        }
        XCTAssertEqual(storedHash, templateHash1, "Original template hash should be unchanged")
    }
    
    // MARK: - Phase 2.3b: Shots Table Immutability + FK Tests
    
    func testShotInsertSucceeds() throws {
        print("\n=== Testing Shot Insert with FK ===")
        let dbQueue = try createTestDatabase()
        
        // Insert a session first
        var sessionId: Int64 = 0
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO sessions (session_date, source_file, ingested_at)
                VALUES (?, ?, ?)
                """, arguments: ["2026-02-06T12:00:00Z", "test.csv", "2026-02-06T12:00:00Z"])
            sessionId = db.lastInsertedRowID
        }
        
        // Insert a shot
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO shots (session_id, source_row_index, source_format, imported_at, raw_json, club, carry, ball_speed)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [sessionId, 0, "rapsodo_mlm2pro_shotexport_v1", "2026-02-06T12:00:00Z", "{\"club\":\"7i\"}", "7i", 142.2, 99.3])
        }
        
        // Verify shot exists
        let count = try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM shots WHERE session_id = ?", arguments: [sessionId])
        }
        XCTAssertEqual(count, 1, "Shot should be inserted")
        print("✅ Shot inserted successfully with FK to session")
    }
    
    func testShotUpdateRejected() throws {
        print("\n=== Testing Shot UPDATE Rejection ===")
        let dbQueue = try createTestDatabase()
        
        // Insert session and shot
        var sessionId: Int64 = 0
        var shotId: Int64 = 0
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO sessions (session_date, source_file, ingested_at)
                VALUES (?, ?, ?)
                """, arguments: ["2026-02-06T12:00:00Z", "test.csv", "2026-02-06T12:00:00Z"])
            sessionId = db.lastInsertedRowID
            
            try db.execute(sql: """
                INSERT INTO shots (session_id, source_row_index, source_format, imported_at, raw_json, club, carry)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """, arguments: [sessionId, 0, "rapsodo_mlm2pro_shotexport_v1", "2026-02-06T12:00:00Z", "{\"club\":\"7i\"}", "7i", 142.2])
            shotId = db.lastInsertedRowID
        }
        
        // Attempt to update carry - should fail
        do {
            try dbQueue.write { db in
                try db.execute(sql: "UPDATE shots SET carry = ? WHERE shot_id = ?", arguments: [150.0, shotId])
            }
            XCTFail("UPDATE should have been rejected by trigger")
        } catch let error as DatabaseError {
            let message = error.message ?? ""
            print("✅ UPDATE rejected: \(message)")
            XCTAssertTrue(message.lowercased().contains("immutable"), "Error message should contain 'immutable': \(message)")
        }
        
        // Verify original value unchanged
        let carry = try dbQueue.read { db in
            try Double.fetchOne(db, sql: "SELECT carry FROM shots WHERE shot_id = ?", arguments: [shotId])
        }
        let unwrappedCarry = try XCTUnwrap(carry, "Carry should exist")
        XCTAssertEqual(unwrappedCarry, 142.2, accuracy: 0.01, "Original value should be unchanged")
    }
    
    func testShotDeleteRejected() throws {
        print("\n=== Testing Shot DELETE Rejection ===")
        let dbQueue = try createTestDatabase()
        
        // Insert session and shot
        var sessionId: Int64 = 0
        var shotId: Int64 = 0
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO sessions (session_date, source_file, ingested_at)
                VALUES (?, ?, ?)
                """, arguments: ["2026-02-06T12:00:00Z", "test.csv", "2026-02-06T12:00:00Z"])
            sessionId = db.lastInsertedRowID
            
            try db.execute(sql: """
                INSERT INTO shots (session_id, source_row_index, source_format, imported_at, raw_json, club)
                VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [sessionId, 0, "rapsodo_mlm2pro_shotexport_v1", "2026-02-06T12:00:00Z", "{\"club\":\"7i\"}", "7i"])
            shotId = db.lastInsertedRowID
        }
        
        // Attempt to delete - should fail
        do {
            try dbQueue.write { db in
                try db.execute(sql: "DELETE FROM shots WHERE shot_id = ?", arguments: [shotId])
            }
            XCTFail("DELETE should have been rejected by trigger")
        } catch let error as DatabaseError {
            let message = error.message ?? ""
            print("✅ DELETE rejected: \(message)")
            XCTAssertTrue(message.lowercased().contains("immutable"), "Error message should contain 'immutable': \(message)")
        }
        
        // Verify row still exists
        let count = try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM shots WHERE shot_id = ?", arguments: [shotId])
        }
        XCTAssertEqual(count, 1, "Row should still exist")
    }
    
    func testShotFKEnforced() throws {
        print("\n=== Testing Shot FK Enforcement ===")
        let dbQueue = try createTestDatabase()
        
        // Attempt to insert shot with nonexistent session_id - should fail
        do {
            try dbQueue.write { db in
                try db.execute(sql: """
                    INSERT INTO shots (session_id, source_row_index, source_format, imported_at, raw_json, club)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """, arguments: [99999, 0, "rapsodo_mlm2pro_shotexport_v1", "2026-02-06T12:00:00Z", "{\"club\":\"7i\"}", "7i"])
            }
            XCTFail("INSERT with invalid FK should have been rejected")
        } catch let error as DatabaseError {
            print("✅ FK violation rejected: \(error.message ?? "")")
            // GRDB reports FK violations as SQLITE_CONSTRAINT
            XCTAssertEqual(error.resultCode, .SQLITE_CONSTRAINT, "Should be FK constraint violation")
        }
    }
    
    func testShotDuplicateRowIndexRejected() throws {
        print("\n=== Testing Shot Duplicate Row Index Rejection ===")
        let dbQueue = try createTestDatabase()
        
        // Insert session and shot
        var sessionId: Int64 = 0
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO sessions (session_date, source_file, ingested_at)
                VALUES (?, ?, ?)
                """, arguments: ["2026-02-06T12:00:00Z", "test.csv", "2026-02-06T12:00:00Z"])
            sessionId = db.lastInsertedRowID
            
            try db.execute(sql: """
                INSERT INTO shots (session_id, source_row_index, source_format, imported_at, raw_json, club)
                VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [sessionId, 0, "rapsodo_mlm2pro_shotexport_v1", "2026-02-06T12:00:00Z", "{\"club\":\"7i\"}", "7i"])
        }
        
        // Attempt to insert duplicate (same session_id + source_row_index) - should fail
        do {
            try dbQueue.write { db in
                try db.execute(sql: """
                    INSERT INTO shots (session_id, source_row_index, source_format, imported_at, raw_json, club)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """, arguments: [sessionId, 0, "rapsodo_mlm2pro_shotexport_v1", "2026-02-06T12:00:00Z", "{\"club\":\"7i\"}", "7i"])
            }
            XCTFail("Duplicate shot should have been rejected by UNIQUE constraint")
        } catch let error as DatabaseError {
            print("✅ Duplicate rejected: \(error.message ?? "")")
            XCTAssertEqual(error.resultCode, .SQLITE_CONSTRAINT, "Should be UNIQUE constraint violation")
        }
    }
    
    // MARK: - Phase 2.4: Repository Tests
    
    func testInsertTemplateComputesHashOnce() throws {
        print("\n=== Testing Insert Template Computes Hash Once ===")
        
        // Create test database
        let dbQueue = try DatabaseQueue.createRAIDDatabase(at: ":memory:")
        
        // Create spy implementations
        let spyCanon = SpyCanonicalizer()
        let spyHash = SpyHasher()
        
        // Create repository with spies
        let repo = TemplateRepository(dbQueue: dbQueue, canonicalizer: spyCanon, hasher: spyHash)
        
        // Template JSON
        let templateDict: [String: Any] = [
            "club": "7i",
            "schema_version": "1.0",
            "aggregation_method": "worst_metric",
            "metrics": [
                "ball_speed": [
                    "a_min": 100,
                    "b_min": 90,
                    "direction": "higher_is_better"
                ]
            ]
        ]
        let rawJSON = try JSONSerialization.data(withJSONObject: templateDict, options: [])
        
        // Insert template
        let record = try repo.insertTemplate(rawJSON: rawJSON)
        
        // Verify hash was computed exactly once
        XCTAssertEqual(spyCanon.callCount, 1, "Canonicalize should be called exactly once during insert")
        XCTAssertEqual(spyHash.callCount, 1, "Hash should be called exactly once during insert")
        
        print("✅ Insert called canonicalize: \(spyCanon.callCount) time(s)")
        print("✅ Insert called hash: \(spyHash.callCount) time(s)")
        print("✅ Computed hash: \(record.hash)")
        
        // Fetch template (should NOT call canonicalize or hash)
        let fetched = try repo.fetchTemplate(byHash: record.hash)
        
        // Verify no additional calls during fetch
        XCTAssertEqual(spyCanon.callCount, 1, "Fetch should NOT call canonicalize")
        XCTAssertEqual(spyHash.callCount, 1, "Fetch should NOT call hash")
        
        // Verify fetched hash matches inserted hash
        XCTAssertNotNil(fetched, "Template should be fetchable")
        XCTAssertEqual(fetched?.hash, record.hash, "Fetched hash must match inserted hash")
        
        print("✅ Fetch did NOT call canonicalize or hash (counters unchanged)")
        print("✅ Fetched hash matches inserted hash: \(record.hash)")
    }
    
    func testFetchTemplateNeverRecomputesHash() throws {
        print("\n=== Testing Fetch Template Never Recomputes Hash ===")

        // Create test database
        let dbQueue = try DatabaseQueue.createRAIDDatabase(at: ":memory:")

        // Create spy implementations
        let spyCanon = SpyCanonicalizer()
        let spyHash = SpyHasher()

        // Create repository with spies
        let repo = TemplateRepository(dbQueue: dbQueue, canonicalizer: spyCanon, hasher: spyHash)

        // Template JSON
        let templateDict: [String: Any] = [
            "club": "7i",
            "schema_version": "1.0",
            "aggregation_method": "worst_metric",
            "metrics": [
                "ball_speed": [
                    "a_min": 100,
                    "b_min": 90,
                    "direction": "higher_is_better"
                ]
            ]
        ]
        let rawJSON = try JSONSerialization.data(withJSONObject: templateDict, options: [])

        // Insert template
        let record = try repo.insertTemplate(rawJSON: rawJSON)
        XCTAssertEqual(spyCanon.callCount, 1, "Insert should call canonicalize once")
        XCTAssertEqual(spyHash.callCount, 1, "Insert should call hash once")

        print("✅ After insert: canonicalize=\(spyCanon.callCount), hash=\(spyHash.callCount)")

        // Fetch multiple times
        for i in 1...3 {
            let fetched = try repo.fetchTemplate(byHash: record.hash)
            XCTAssertNotNil(fetched, "Template should be fetchable (attempt \(i))")
            XCTAssertEqual(fetched?.hash, record.hash, "Hash should match (attempt \(i))")

            // Verify counters unchanged
            XCTAssertEqual(spyCanon.callCount, 1, "Fetch \(i) should NOT call canonicalize")
            XCTAssertEqual(spyHash.callCount, 1, "Fetch \(i) should NOT call hash")
        }

        print("✅ After 3 fetches: canonicalize=\(spyCanon.callCount), hash=\(spyHash.callCount)")
        print("✅ Fetch path never calls canonicalize or hash (RTM-04 verified)")
    }

    // MARK: - v4 Migration: Template Preferences Tests

    func testV4MigrationAppliesOnFreshDB() throws {
        print("\n=== Testing v4 Migration Applies on Fresh DB ===")
        let dbQueue = try createTestDatabase()

        // Verify template_preferences table exists
        let tableExists = try dbQueue.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM sqlite_master
                WHERE type='table' AND name='template_preferences'
                """)
        }
        XCTAssertEqual(tableExists, 1, "template_preferences table should exist")

        // Verify partial unique index exists
        let indexExists = try dbQueue.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM sqlite_master
                WHERE type='index' AND name='idx_one_active_per_club'
                """)
        }
        XCTAssertEqual(indexExists, 1, "idx_one_active_per_club index should exist")

        print("✅ v4 migration applied successfully")
        print("✅ template_preferences table created")
        print("✅ idx_one_active_per_club index created")
    }

    func testTemplatePreferenceFKEnforcement() throws {
        print("\n=== Testing Template Preference FK Enforcement ===")
        let dbQueue = try createTestDatabase()

        let nonexistentHash = "a" + String(repeating: "0", count: 63)

        // Attempt to insert preference with nonexistent template_hash - should fail
        do {
            try dbQueue.write { db in
                try db.execute(sql: """
                    INSERT INTO template_preferences (template_hash, club, updated_at)
                    VALUES (?, ?, ?)
                    """, arguments: [nonexistentHash, "7i", "2026-02-10T12:00:00Z"])
            }
            XCTFail("INSERT with invalid FK should have been rejected")
        } catch let error as DatabaseError {
            print("✅ FK violation rejected: \(error.message ?? "")")
            XCTAssertEqual(error.resultCode, .SQLITE_CONSTRAINT, "Should be FK constraint violation")
        }
    }

    func testTemplatePreferenceActiveUniquenessPerClub() throws {
        print("\n=== Testing Template Preference Active Uniqueness Per Club ===")
        let dbQueue = try createTestDatabase()

        // Insert two templates for same club
        let templateHash1 = "b" + String(repeating: "0", count: 63)
        let templateHash2 = "c" + String(repeating: "0", count: 63)
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO kpi_templates (template_hash, schema_version, club, canonical_json, created_at)
                VALUES (?, ?, ?, ?, ?)
                """, arguments: [templateHash1, "1.0", "7i", "{\"version\":\"1\"}", "2026-02-10T12:00:00Z"])

            try db.execute(sql: """
                INSERT INTO kpi_templates (template_hash, schema_version, club, canonical_json, created_at)
                VALUES (?, ?, ?, ?, ?)
                """, arguments: [templateHash2, "1.0", "7i", "{\"version\":\"2\"}", "2026-02-10T12:00:00Z"])
        }

        // Insert first preference as active
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO template_preferences (template_hash, club, is_active, updated_at)
                VALUES (?, ?, ?, ?)
                """, arguments: [templateHash1, "7i", 1, "2026-02-10T12:00:00Z"])
        }

        // Attempt to insert second preference as active for same club - should fail
        do {
            try dbQueue.write { db in
                try db.execute(sql: """
                    INSERT INTO template_preferences (template_hash, club, is_active, updated_at)
                    VALUES (?, ?, ?, ?)
                    """, arguments: [templateHash2, "7i", 1, "2026-02-10T12:00:00Z"])
            }
            XCTFail("INSERT of second active template for same club should have been rejected")
        } catch let error as DatabaseError {
            print("✅ Active uniqueness violation rejected: \(error.message ?? "")")
            XCTAssertEqual(error.resultCode, .SQLITE_CONSTRAINT, "Should be UNIQUE constraint violation")
        }

        // Verify first preference still active
        let activeHash = try dbQueue.read { db in
            try String.fetchOne(db, sql: """
                SELECT template_hash FROM template_preferences
                WHERE club = ? AND is_active = 1
                """, arguments: ["7i"])
        }
        XCTAssertEqual(activeHash, templateHash1, "First template should remain active")

        print("✅ Partial unique index prevents multiple active templates per club")
    }

    func testTemplatePreferenceAllowsMultipleInactivePerClub() throws {
        print("\n=== Testing Template Preference Allows Multiple Inactive Per Club ===")
        let dbQueue = try createTestDatabase()

        // Insert two templates for same club
        let templateHash1 = "d" + String(repeating: "0", count: 63)
        let templateHash2 = "e" + String(repeating: "0", count: 63)
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO kpi_templates (template_hash, schema_version, club, canonical_json, created_at)
                VALUES (?, ?, ?, ?, ?)
                """, arguments: [templateHash1, "1.0", "7i", "{\"version\":\"1\"}", "2026-02-10T12:00:00Z"])

            try db.execute(sql: """
                INSERT INTO kpi_templates (template_hash, schema_version, club, canonical_json, created_at)
                VALUES (?, ?, ?, ?, ?)
                """, arguments: [templateHash2, "1.0", "7i", "{\"version\":\"2\"}", "2026-02-10T12:00:00Z"])
        }

        // Insert both preferences as inactive - should succeed
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO template_preferences (template_hash, club, is_active, updated_at)
                VALUES (?, ?, ?, ?)
                """, arguments: [templateHash1, "7i", 0, "2026-02-10T12:00:00Z"])

            try db.execute(sql: """
                INSERT INTO template_preferences (template_hash, club, is_active, updated_at)
                VALUES (?, ?, ?, ?)
                """, arguments: [templateHash2, "7i", 0, "2026-02-10T12:00:00Z"])
        }

        // Verify both exist
        let count = try dbQueue.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM template_preferences
                WHERE club = ? AND is_active = 0
                """, arguments: ["7i"])
        }
        XCTAssertEqual(count, 2, "Both inactive preferences should exist")

        print("✅ Multiple inactive templates per club allowed")
    }

    func testTemplatePreferenceUpdateAllowed() throws {
        print("\n=== Testing Template Preference UPDATE Allowed ===")
        let dbQueue = try createTestDatabase()

        // Insert template and preference
        let templateHash = "f" + String(repeating: "0", count: 63)
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO kpi_templates (template_hash, schema_version, club, canonical_json, created_at)
                VALUES (?, ?, ?, ?, ?)
                """, arguments: [templateHash, "1.0", "7i", "{\"club\":\"7i\"}", "2026-02-10T12:00:00Z"])

            try db.execute(sql: """
                INSERT INTO template_preferences (template_hash, club, display_name, is_active, updated_at)
                VALUES (?, ?, ?, ?, ?)
                """, arguments: [templateHash, "7i", "Original Name", 0, "2026-02-10T12:00:00Z"])
        }

        // Update display_name - should succeed (no immutability triggers)
        try dbQueue.write { db in
            try db.execute(sql: """
                UPDATE template_preferences
                SET display_name = ?, updated_at = ?
                WHERE template_hash = ?
                """, arguments: ["Updated Name", "2026-02-10T13:00:00Z", templateHash])
        }

        // Verify update succeeded
        let displayName = try dbQueue.read { db in
            try String.fetchOne(db, sql: """
                SELECT display_name FROM template_preferences
                WHERE template_hash = ?
                """, arguments: [templateHash])
        }
        XCTAssertEqual(displayName, "Updated Name", "Display name should be updated")

        print("✅ UPDATE allowed on template_preferences (no immutability triggers)")
    }

    func testTemplatePreferenceDeleteAllowed() throws {
        print("\n=== Testing Template Preference DELETE Allowed ===")
        let dbQueue = try createTestDatabase()

        // Insert template and preference
        let templateHash = "1" + String(repeating: "0", count: 63)
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO kpi_templates (template_hash, schema_version, club, canonical_json, created_at)
                VALUES (?, ?, ?, ?, ?)
                """, arguments: [templateHash, "1.0", "7i", "{\"club\":\"7i\"}", "2026-02-10T12:00:00Z"])

            try db.execute(sql: """
                INSERT INTO template_preferences (template_hash, club, is_active, updated_at)
                VALUES (?, ?, ?, ?)
                """, arguments: [templateHash, "7i", 0, "2026-02-10T12:00:00Z"])
        }

        // Verify preference exists
        let countBefore = try dbQueue.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM template_preferences
                WHERE template_hash = ?
                """, arguments: [templateHash])
        }
        XCTAssertEqual(countBefore, 1, "Preference should exist before delete")

        // Delete preference - should succeed (no immutability triggers)
        try dbQueue.write { db in
            try db.execute(sql: """
                DELETE FROM template_preferences
                WHERE template_hash = ?
                """, arguments: [templateHash])
        }

        // Verify deletion succeeded
        let countAfter = try dbQueue.read { db in
            try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM template_preferences
                WHERE template_hash = ?
                """, arguments: [templateHash])
        }
        XCTAssertEqual(countAfter, 0, "Preference should be deleted")

        print("✅ DELETE allowed on template_preferences (no immutability triggers)")
    }

    func testTemplatePreferenceDefaultValues() throws {
        print("\n=== Testing Template Preference Default Values ===")
        let dbQueue = try createTestDatabase()

        // Insert template
        let templateHash = "2" + String(repeating: "0", count: 63)
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO kpi_templates (template_hash, schema_version, club, canonical_json, created_at)
                VALUES (?, ?, ?, ?, ?)
                """, arguments: [templateHash, "1.0", "7i", "{\"club\":\"7i\"}", "2026-02-10T12:00:00Z"])

            // Insert preference without specifying is_active or is_hidden (should default to 0)
            try db.execute(sql: """
                INSERT INTO template_preferences (template_hash, club, updated_at)
                VALUES (?, ?, ?)
                """, arguments: [templateHash, "7i", "2026-02-10T12:00:00Z"])
        }

        // Verify default values
        let row = try dbQueue.read { db in
            try Row.fetchOne(db, sql: """
                SELECT is_active, is_hidden FROM template_preferences
                WHERE template_hash = ?
                """, arguments: [templateHash])
        }

        let isActive = try XCTUnwrap(row?["is_active"] as Int?, "is_active should exist")
        let isHidden = try XCTUnwrap(row?["is_hidden"] as Int?, "is_hidden should exist")

        XCTAssertEqual(isActive, 0, "is_active should default to 0")
        XCTAssertEqual(isHidden, 0, "is_hidden should default to 0")

        print("✅ Default values: is_active=0, is_hidden=0")
    }

    // MARK: - Task 2: Repository Read Extensions Tests

    func testListTemplatesForClubOrdersByRecency() throws {
        print("\n=== Testing listTemplates(forClub:) Orders By Recency ===")
        let dbQueue = try createTestDatabase()
        let repo = TemplateRepository(dbQueue: dbQueue)

        // Insert three templates for same club at different times
        let hash1 = "3" + String(repeating: "0", count: 63)
        let hash2 = "4" + String(repeating: "0", count: 63)
        let hash3 = "5" + String(repeating: "0", count: 63)

        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO kpi_templates (template_hash, schema_version, club, canonical_json, created_at, imported_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [hash1, "1.0", "7i", "{\"v\":\"1\"}", "2026-02-08T12:00:00Z", "2026-02-08T12:00:00Z"])

            try db.execute(sql: """
                INSERT INTO kpi_templates (template_hash, schema_version, club, canonical_json, created_at, imported_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [hash2, "1.0", "7i", "{\"v\":\"2\"}", "2026-02-09T12:00:00Z", "2026-02-09T12:00:00Z"])

            try db.execute(sql: """
                INSERT INTO kpi_templates (template_hash, schema_version, club, canonical_json, created_at, imported_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [hash3, "1.0", "7i", "{\"v\":\"3\"}", "2026-02-10T12:00:00Z", "2026-02-10T12:00:00Z"])
        }

        let templates = try repo.listTemplates(forClub: "7i")

        XCTAssertEqual(templates.count, 3, "Should return 3 templates")
        XCTAssertEqual(templates[0].hash, hash3, "Most recent template should be first")
        XCTAssertEqual(templates[1].hash, hash2, "Second most recent template should be second")
        XCTAssertEqual(templates[2].hash, hash1, "Oldest template should be last")

        print("✅ listTemplates orders by recency: \(templates.map { $0.hash })")
    }

    func testListTemplatesExcludesHidden() throws {
        print("\n=== Testing listTemplates Excludes Hidden Templates ===")
        let dbQueue = try createTestDatabase()
        let repo = TemplateRepository(dbQueue: dbQueue)

        // Insert two templates for same club
        let hash1 = "6" + String(repeating: "0", count: 63)
        let hash2 = "7" + String(repeating: "0", count: 63)

        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO kpi_templates (template_hash, schema_version, club, canonical_json, created_at, imported_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [hash1, "1.0", "7i", "{\"v\":\"1\"}", "2026-02-10T12:00:00Z", "2026-02-10T12:00:00Z"])

            try db.execute(sql: """
                INSERT INTO kpi_templates (template_hash, schema_version, club, canonical_json, created_at, imported_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [hash2, "1.0", "7i", "{\"v\":\"2\"}", "2026-02-10T13:00:00Z", "2026-02-10T13:00:00Z"])

            // Hide hash1
            try db.execute(sql: """
                INSERT INTO template_preferences (template_hash, club, is_hidden, updated_at)
                VALUES (?, ?, ?, ?)
                """, arguments: [hash1, "7i", 1, "2026-02-10T14:00:00Z"])
        }

        let templates = try repo.listTemplates(forClub: "7i")

        XCTAssertEqual(templates.count, 1, "Should return only non-hidden template")
        XCTAssertEqual(templates[0].hash, hash2, "Should return only non-hidden template")

        print("✅ listTemplates excludes hidden templates")
    }

    func testListAllTemplatesGroupsByClub() throws {
        print("\n=== Testing listAllTemplates Groups By Club ===")
        let dbQueue = try createTestDatabase()
        let repo = TemplateRepository(dbQueue: dbQueue)

        // Insert templates for multiple clubs
        let hash7i1 = "8" + String(repeating: "0", count: 63)
        let hash7i2 = "9" + String(repeating: "0", count: 63)
        let hashPW = "a" + String(repeating: "0", count: 63)

        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO kpi_templates (template_hash, schema_version, club, canonical_json, created_at, imported_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [hash7i1, "1.0", "7i", "{\"v\":\"1\"}", "2026-02-09T12:00:00Z", "2026-02-09T12:00:00Z"])

            try db.execute(sql: """
                INSERT INTO kpi_templates (template_hash, schema_version, club, canonical_json, created_at, imported_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [hash7i2, "1.0", "7i", "{\"v\":\"2\"}", "2026-02-10T12:00:00Z", "2026-02-10T12:00:00Z"])

            try db.execute(sql: """
                INSERT INTO kpi_templates (template_hash, schema_version, club, canonical_json, created_at, imported_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [hashPW, "1.0", "PW", "{\"v\":\"1\"}", "2026-02-10T12:00:00Z", "2026-02-10T12:00:00Z"])
        }

        let templates = try repo.listAllTemplates()

        XCTAssertEqual(templates.count, 3, "Should return all 3 templates")
        // Should be ordered: 7i (most recent first), then PW
        XCTAssertEqual(templates[0].club, "7i")
        XCTAssertEqual(templates[0].hash, hash7i2, "Most recent 7i template first")
        XCTAssertEqual(templates[1].club, "7i")
        XCTAssertEqual(templates[1].hash, hash7i1, "Older 7i template second")
        XCTAssertEqual(templates[2].club, "PW")
        XCTAssertEqual(templates[2].hash, hashPW, "PW template last (club ASC)")

        print("✅ listAllTemplates groups by club (ASC), orders by recency (DESC)")
    }

    func testFetchSubsessionsReturnsCorrectRecords() throws {
        print("\n=== Testing fetchSubsessions Returns Correct Records ===")
        let dbQueue = try createTestDatabase()
        let sessionRepo = SessionRepository(dbQueue: dbQueue)
        let subsessionRepo = SubsessionRepository(dbQueue: dbQueue)

        // Insert session and template
        let session = try sessionRepo.insertSession(
            sessionDate: "2026-02-10T12:00:00Z",
            sourceFile: "test.csv"
        )

        let templateHash = "b" + String(repeating: "0", count: 63)
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO kpi_templates (template_hash, schema_version, club, canonical_json, created_at)
                VALUES (?, ?, ?, ?, ?)
                """, arguments: [templateHash, "1.0", "7i", "{\"club\":\"7i\"}", "2026-02-10T12:00:00Z"])
        }

        // Insert two subsessions for different clubs
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO club_subsessions
                    (session_id, club, kpi_template_hash, shot_count, validity_status,
                     a_count, b_count, c_count, a_percentage, avg_carry, avg_ball_speed,
                     avg_spin, avg_descent, analyzed_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    session.sessionId, "7i", templateHash, 20, "valid",
                    10, 8, 2, 50.0, 142.5, 99.2, 7200.0, 48.5,
                    "2026-02-10T13:00:00Z"
                ])

            try db.execute(sql: """
                INSERT INTO club_subsessions
                    (session_id, club, kpi_template_hash, shot_count, validity_status,
                     a_count, b_count, c_count, a_percentage, analyzed_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    session.sessionId, "PW", templateHash, 15, "valid_low_sample_warning",
                    8, 5, 2, 53.3,
                    "2026-02-10T13:30:00Z"
                ])
        }

        let subsessions = try subsessionRepo.fetchSubsessions(forSession: session.sessionId)

        XCTAssertEqual(subsessions.count, 2, "Should return 2 subsessions")
        XCTAssertEqual(subsessions[0].club, "7i", "First subsession should be 7i (club ASC)")
        XCTAssertEqual(subsessions[1].club, "PW", "Second subsession should be PW")

        // Verify 7i subsession data
        XCTAssertEqual(subsessions[0].shotCount, 20)
        XCTAssertEqual(subsessions[0].aCount, 10)
        let aPercentage = try XCTUnwrap(subsessions[0].aPercentage)
        XCTAssertEqual(aPercentage, 50.0, accuracy: 0.01)
        let avgCarry = try XCTUnwrap(subsessions[0].avgCarry)
        XCTAssertEqual(avgCarry, 142.5, accuracy: 0.01)

        print("✅ fetchSubsessions returns correct records ordered by club ASC")
    }

    // MARK: - Task 2: TemplatePreferencesRepository Tests

    func testSetActiveTransactionally() throws {
        print("\n=== Testing setActive Transactionally Switches Active Template ===")
        let dbQueue = try createTestDatabase()
        let prefsRepo = TemplatePreferencesRepository(dbQueue: dbQueue)

        // Insert two templates for same club
        let hash1 = "c" + String(repeating: "0", count: 63)
        let hash2 = "d" + String(repeating: "0", count: 63)

        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO kpi_templates (template_hash, schema_version, club, canonical_json, created_at)
                VALUES (?, ?, ?, ?, ?)
                """, arguments: [hash1, "1.0", "7i", "{\"v\":\"1\"}", "2026-02-10T12:00:00Z"])

            try db.execute(sql: """
                INSERT INTO kpi_templates (template_hash, schema_version, club, canonical_json, created_at)
                VALUES (?, ?, ?, ?, ?)
                """, arguments: [hash2, "1.0", "7i", "{\"v\":\"2\"}", "2026-02-10T12:00:00Z"])
        }

        // Activate first template
        try prefsRepo.setActive(templateHash: hash1, club: "7i")

        // Verify first template is active
        let pref1 = try prefsRepo.fetchPreference(forHash: hash1)
        XCTAssertNotNil(pref1)
        XCTAssertTrue(pref1?.isActive ?? false, "First template should be active")

        // Activate second template (should deactivate first)
        try prefsRepo.setActive(templateHash: hash2, club: "7i")

        // Verify first template is now inactive
        let pref1After = try prefsRepo.fetchPreference(forHash: hash1)
        XCTAssertNotNil(pref1After)
        XCTAssertFalse(pref1After?.isActive ?? true, "First template should be inactive")

        // Verify second template is active
        let pref2 = try prefsRepo.fetchPreference(forHash: hash2)
        XCTAssertNotNil(pref2)
        XCTAssertTrue(pref2?.isActive ?? false, "Second template should be active")

        print("✅ setActive transactionally switches active template")
    }

    func testFetchActiveTemplateReturnsCorrectTemplate() throws {
        print("\n=== Testing fetchActiveTemplate Returns Correct Template ===")
        let dbQueue = try createTestDatabase()
        let prefsRepo = TemplatePreferencesRepository(dbQueue: dbQueue)

        // Insert two templates for same club
        let hash1 = "e" + String(repeating: "0", count: 63)
        let hash2 = "f" + String(repeating: "0", count: 63)

        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO kpi_templates (template_hash, schema_version, club, canonical_json, created_at, imported_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [hash1, "1.0", "7i", "{\"v\":\"1\"}", "2026-02-10T12:00:00Z", "2026-02-10T12:00:00Z"])

            try db.execute(sql: """
                INSERT INTO kpi_templates (template_hash, schema_version, club, canonical_json, created_at, imported_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """, arguments: [hash2, "1.0", "7i", "{\"v\":\"2\"}", "2026-02-10T13:00:00Z", "2026-02-10T13:00:00Z"])
        }

        // No active template initially
        let noActive = try prefsRepo.fetchActiveTemplate(forClub: "7i")
        XCTAssertNil(noActive, "Should have no active template initially")

        // Activate second template
        try prefsRepo.setActive(templateHash: hash2, club: "7i")

        // Fetch active template
        let activeTemplate = try prefsRepo.fetchActiveTemplate(forClub: "7i")
        XCTAssertNotNil(activeTemplate)
        XCTAssertEqual(activeTemplate?.hash, hash2, "Active template should be hash2")
        XCTAssertEqual(activeTemplate?.club, "7i")
        XCTAssertEqual(activeTemplate?.importedAt, "2026-02-10T13:00:00Z")

        print("✅ fetchActiveTemplate returns correct template after activation")
    }

    func testEnsurePreferenceExistsIsIdempotent() throws {
        print("\n=== Testing ensurePreferenceExists Is Idempotent ===")
        let dbQueue = try createTestDatabase()
        let prefsRepo = TemplatePreferencesRepository(dbQueue: dbQueue)

        // Insert template
        let hash = "1" + String(repeating: "2", count: 63)
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO kpi_templates (template_hash, schema_version, club, canonical_json, created_at)
                VALUES (?, ?, ?, ?, ?)
                """, arguments: [hash, "1.0", "7i", "{\"club\":\"7i\"}", "2026-02-10T12:00:00Z"])
        }

        // Ensure preference exists (first call)
        try prefsRepo.ensurePreferenceExists(forHash: hash, club: "7i")

        // Fetch preference
        let pref1 = try prefsRepo.fetchPreference(forHash: hash)
        XCTAssertNotNil(pref1)
        XCTAssertFalse(pref1?.isActive ?? true, "Should be inactive by default")
        XCTAssertFalse(pref1?.isHidden ?? true, "Should be not hidden by default")

        // Ensure preference exists again (idempotent)
        try prefsRepo.ensurePreferenceExists(forHash: hash, club: "7i")

        // Verify preference still exists and unchanged
        let pref2 = try prefsRepo.fetchPreference(forHash: hash)
        XCTAssertNotNil(pref2)
        XCTAssertEqual(pref1?.updatedAt, pref2?.updatedAt, "Should not update existing preference")

        // Verify only one preference row exists
        let count = try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM template_preferences WHERE template_hash = ?",
                            arguments: [hash])
        }
        XCTAssertEqual(count, 1, "Should have exactly one preference row")

        print("✅ ensurePreferenceExists is idempotent")
    }

    func testSetDisplayNameUpdatesPreference() throws {
        print("\n=== Testing setDisplayName Updates Preference ===")
        let dbQueue = try createTestDatabase()
        let prefsRepo = TemplatePreferencesRepository(dbQueue: dbQueue)

        // Insert template and preference
        let hash = "1" + String(repeating: "3", count: 63)
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO kpi_templates (template_hash, schema_version, club, canonical_json, created_at)
                VALUES (?, ?, ?, ?, ?)
                """, arguments: [hash, "1.0", "7i", "{\"club\":\"7i\"}", "2026-02-10T12:00:00Z"])
        }

        try prefsRepo.ensurePreferenceExists(forHash: hash, club: "7i")

        // Set display name
        try prefsRepo.setDisplayName(templateHash: hash, name: "My 7i Template")

        // Verify display name was set
        let pref = try prefsRepo.fetchPreference(forHash: hash)
        XCTAssertNotNil(pref)
        XCTAssertEqual(pref?.displayName, "My 7i Template")

        print("✅ setDisplayName updates preference")
    }

    func testSetHiddenUpdatesPreference() throws {
        print("\n=== Testing setHidden Updates Preference ===")
        let dbQueue = try createTestDatabase()
        let prefsRepo = TemplatePreferencesRepository(dbQueue: dbQueue)

        // Insert template and preference
        let hash = "1" + String(repeating: "4", count: 63)
        try dbQueue.write { db in
            try db.execute(sql: """
                INSERT INTO kpi_templates (template_hash, schema_version, club, canonical_json, created_at)
                VALUES (?, ?, ?, ?, ?)
                """, arguments: [hash, "1.0", "7i", "{\"club\":\"7i\"}", "2026-02-10T12:00:00Z"])
        }

        try prefsRepo.ensurePreferenceExists(forHash: hash, club: "7i")

        // Set hidden
        try prefsRepo.setHidden(templateHash: hash, hidden: true)

        // Verify hidden status was set
        let pref = try prefsRepo.fetchPreference(forHash: hash)
        XCTAssertNotNil(pref)
        XCTAssertTrue(pref?.isHidden ?? false)

        // Set not hidden
        try prefsRepo.setHidden(templateHash: hash, hidden: false)

        // Verify hidden status was unset
        let pref2 = try prefsRepo.fetchPreference(forHash: hash)
        XCTAssertNotNil(pref2)
        XCTAssertFalse(pref2?.isHidden ?? true)

        print("✅ setHidden updates preference")
    }
}

// MARK: - Test Spies

/// Spy canonicalizer that counts calls
class SpyCanonicalizer: Canonicalizing {
    var callCount = 0
    
    func canonicalize(_ raw: Data) throws -> Data {
        callCount += 1
        // Delegate to real implementation
        return try RAIDCanonicalizer().canonicalize(raw)
    }
}

/// Spy hasher that counts calls
class SpyHasher: Hashing {
    var callCount = 0
    
    func sha256Hex(_ canonical: Data) -> String {
        callCount += 1
        // Delegate to real implementation
        return RAIDHasher().sha256Hex(canonical)
    }
}

// MARK: - Helper: AnyCodable for dynamic JSON

struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if container.decodeNil() {
            value = NSNull()
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON type")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let string as String:
            try container.encode(string)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let bool as Bool:
            try container.encode(bool)
        case is NSNull:
            try container.encodeNil()
        default:
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: [], debugDescription: "Unsupported type"))
        }
    }
}
