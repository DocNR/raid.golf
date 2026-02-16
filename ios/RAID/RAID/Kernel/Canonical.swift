// Canonical.swift
// RAID Golf
//
// RAID Canonical JSON v1 (canonicaljson-compatible)
//
// Purpose:
// - Match Python `canonicaljson` library output byte-for-byte
// - NOT strict RFC 8785 JCS (negative zero preserved, not normalized)
// - Lexicographic key ordering by UTF-16 code units
// - Compact JSON (no whitespace), UTF-8 without BOM
// - Reject invalid JSON numbers (NaN, Infinity)
//
// Note: Strict RFC 8785 compliance would be a Kernel v3 migration.
// This implementation preserves frozen vectors and golden hashes.
//
// Test against: tests/vectors/jcs_vectors.json (all 12 vectors must pass)

import Foundation

/// RAID Canonical JSON v1 - canonicaljson-compatible implementation
struct RAIDCanonical {
    
    enum CanonicalError: Error, LocalizedError {
        case invalidJSON(String)
        case nanOrInfinity(String)
        case unsupportedType(String)
        
        var errorDescription: String? {
            switch self {
            case .invalidJSON(let msg): return "Invalid JSON: \(msg)"
            case .nanOrInfinity(let msg): return "NaN or Infinity not allowed: \(msg)"
            case .unsupportedType(let msg): return "Unsupported type: \(msg)"
            }
        }
    }
    
    /// Canonicalize a JSON value to RAID Canonical JSON v1 format
    /// - Parameter value: Any JSON-compatible value (from JSONSerialization)
    /// - Returns: Canonical JSON string (compact, UTF-8, sorted keys)
    /// - Throws: CanonicalError if value contains NaN, Infinity, or invalid types
    static func canonicalize(_ value: Any) throws -> String {
        return try serializeValue(value)
    }
    
    // MARK: - Private Implementation
    
    private static func serializeValue(_ value: Any) throws -> String {
        switch value {
        case let dict as [String: Any]:
            return try serializeObject(dict)
        case let array as [Any]:
            return try serializeArray(array)
        case let string as String:
            return serializeString(string)
        case let number as NSNumber:
            return try serializeNumber(number)
        case is NSNull:
            return "null"
        default:
            throw CanonicalError.unsupportedType("Type \(type(of: value)) is not JSON-serializable")
        }
    }
    
    private static func serializeObject(_ dict: [String: Any]) throws -> String {
        // Sort keys by UTF-16 code units (lexicographic)
        let sortedKeys = dict.keys.sorted { lhs, rhs in
            compareUTF16CodeUnits(lhs, rhs)
        }
        
        var parts: [String] = []
        for key in sortedKeys {
            let keyStr = serializeString(key)
            let valueStr = try serializeValue(dict[key]!)
            parts.append("\(keyStr):\(valueStr)")
        }
        
        return "{" + parts.joined(separator: ",") + "}"
    }
    
    private static func serializeArray(_ array: [Any]) throws -> String {
        let parts = try array.map { try serializeValue($0) }
        return "[" + parts.joined(separator: ",") + "]"
    }
    
    private static func serializeString(_ string: String) -> String {
        // Use Foundation's JSON string escaping
        let data = try! JSONSerialization.data(withJSONObject: [string], options: [])
        let jsonArray = String(data: data, encoding: .utf8)!
        // Extract the string from ["string"] format (including quotes)
        let start = jsonArray.index(jsonArray.startIndex, offsetBy: 1)
        let end = jsonArray.index(jsonArray.endIndex, offsetBy: -1)
        return String(jsonArray[start..<end])
    }
    
    private static func serializeNumber(_ number: NSNumber) throws -> String {
        // Check for actual JSON boolean (not just 0/1)
        // CFBoolean is the true boolean type from JSON parsing
        if CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() {
            return number.boolValue ? "true" : "false"
        }
        
        // Check for NaN and Infinity
        let doubleValue = number.doubleValue
        if doubleValue.isNaN {
            throw CanonicalError.nanOrInfinity("NaN is not allowed in templates")
        }
        if doubleValue.isInfinite {
            throw CanonicalError.nanOrInfinity("Infinity is not allowed in templates")
        }
        
        // Distinguish int vs float using objCType
        let objCType = String(cString: number.objCType)
        
        // Integer types: c, C, s, S, i, I, l, L, q, Q
        let intTypes = ["c", "C", "s", "S", "i", "I", "l", "L", "q", "Q"]
        if intTypes.contains(objCType) {
            // Emit as integer without decimal
            return "\(number.int64Value)"
        }
        
        // Float/Double types: f, d
        // Check for negative zero (special case for canonicaljson compatibility)
        if doubleValue == 0.0 && doubleValue.sign == .minus {
            return "-0.0"
        }
        
        // Emit minimal representation
        // Use String(format:) to avoid scientific notation for common values
        let formatted = String(format: "%g", doubleValue)
        
        // Ensure we have a decimal point for non-integer doubles
        if !formatted.contains(".") && !formatted.contains("e") && !formatted.contains("E") {
            return formatted + ".0"
        }
        
        return formatted
    }
    
    /// Compare two strings by UTF-16 code units (lexicographic)
    /// This matches Python's default string comparison and RFC 8785 requirements
    private static func compareUTF16CodeUnits(_ lhs: String, _ rhs: String) -> Bool {
        let lhsUnits = Array(lhs.utf16)
        let rhsUnits = Array(rhs.utf16)
        
        for (l, r) in zip(lhsUnits, rhsUnits) {
            if l != r {
                return l < r
            }
        }
        
        // If all compared units are equal, shorter string comes first
        return lhsUnits.count < rhsUnits.count
    }
}
