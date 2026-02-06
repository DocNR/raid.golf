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
    
    // MARK: - Phase 2.2: SHA-256 Hashing Tests (TODO after Phase 2.1 passes)
    
    func testTemplateHashFixtureA() throws {
        // TODO: Load tests/vectors/templates/fixture_a.json
        // Compare hash against tests/vectors/expected/template_hashes.json
        XCTFail("Not implemented - Phase 2.2")
    }
    
    func testTemplateHashFixtureB() throws {
        // TODO: Test fixture_b.json hash
        XCTFail("Not implemented - Phase 2.2")
    }
    
    func testTemplateHashFixtureC() throws {
        // TODO: Test fixture_c.json hash
        XCTFail("Not implemented - Phase 2.2")
    }
    
    // MARK: - Phase 2.3: Schema Immutability Tests (TODO)
    
    func testSessionsTableImmutable() throws {
        // TODO: Create in-memory database
        // Insert a session
        // Attempt UPDATE → must fail with trigger error
        // Attempt DELETE → must fail with trigger error
        XCTFail("Not implemented - Phase 2.3")
    }
    
    func testKPITemplatesTableImmutable() throws {
        // TODO: Test kpi_templates immutability
        XCTFail("Not implemented - Phase 2.3")
    }
    
    func testClubSubsessionsTableImmutable() throws {
        // TODO: Test club_subsessions immutability
        XCTFail("Not implemented - Phase 2.3")
    }
    
    // MARK: - Phase 2.4: Repository Tests (TODO)
    
    func testInsertTemplateComputesHashOnce() throws {
        // TODO: Insert template, verify hash is computed
        // Re-fetch template, verify hash is returned from storage
        XCTFail("Not implemented - Phase 2.4")
    }
    
    func testFetchTemplateNeverRecomputesHash() throws {
        // TODO: Use spy/mock to prove fetchTemplate never calls canonicalize/hash
        XCTFail("Not implemented - Phase 2.4")
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
