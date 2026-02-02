# 5. Canonical JSON & Hashing Contract

[← Back to Index](00_index.md)

**Version:** 2.0 (Kernel v2.0 - RFC 8785 JCS)  
**Date:** 2026-02-02  
**Standard:** [RFC 8785 JSON Canonicalization Scheme](https://www.rfc-editor.org/rfc/rfc8785)

---

## 5.1 Overview

KPI template identity is defined by the **SHA-256 hash of RFC 8785 JCS canonical JSON**. 

**Normative formula:**

```
template_hash = SHA-256( UTF-8( JCS( template_json ) ) )
```

Where JCS = RFC 8785 JSON Canonicalization Scheme.

This section defines the exact rules for producing canonical JSON from KPI templates per RFC 8785.

---

## 5.2 Canonicalization Requirements (RFC 8785)

As of Kernel v2.0, RAID uses **RFC 8785 JSON Canonicalization Scheme (JCS)** for template canonicalization.

For complete specification, see:
- **Normative spec:** [docs/specs/jcs_hashing.md](../specs/jcs_hashing.md)
- **RFC 8785:** https://www.rfc-editor.org/rfc/rfc8785
- **Kernel Contract v2:** [docs/private/kernel/KERNEL_CONTRACT_v2.md](../private/kernel/KERNEL_CONTRACT_v2.md)

### 5.2.1 Key Ordering

**Rule:** All object keys must be sorted **lexicographically** (Unicode code point order) at **every nesting level**.

```json
// WRONG — keys not sorted
{
  "club": "7i",
  "schema_version": "1.0",
  "metrics": {...}
}

// CORRECT — keys sorted alphabetically
{
  "club": "7i",
  "metrics": {...},
  "schema_version": "1.0"
}
```

**Nested Objects:**

```json
// CORRECT — sorted at all levels
{
  "club": "7i",
  "metrics": {
    "ball_speed": {
      "a_min": 108.92,
      "b_min": 106.60,
      "direction": "higher_is_better"
    },
    "smash_factor": {
      "a_min": 1.32,
      "b_min": 1.29,
      "direction": "higher_is_better"
    }
  },
  "schema_version": "1.0"
}
```

### 5.2.2 Numeric Serialization (RFC 8785)

**Rule:** Numbers are serialized per RFC 8785 §3.2.2.3:

- Integers without decimal point: `5` not `5.0`
- Decimals with minimal precision: `1.5` not `1.50`
- No scientific notation in canonical form
- No leading zeros (except `0.x`)

**I-JSON Constraints (enforced):**
- No NaN or Infinity values
- No non-standard number formats (hex, octal, etc.)

**Implementation:**
- Python: `canonicaljson` library (pinned at v2.0.0)
- Swift/JS: Use RFC 8785-compliant libraries
- Test vectors: `tests/vectors/jcs_vectors.json`
**Cross-Platform Requirement:**

RFC 8785 JCS is **binding for all implementations** — Python, Swift, and JavaScript implementations must produce byte-identical canonical JSON for identical logical inputs.

**Verification:**
- Golden test vectors: `tests/vectors/jcs_vectors.json`
- Template hashes: `tests/vectors/expected/template_hashes.json`

### 5.2.3 Whitespace Elimination

**Rule:** Canonical JSON must be **compact** (no whitespace).

```json
// WRONG — pretty-printed
{
  "club": "7i",
  "schema_version": "1.0"
}

// CORRECT — compact
{"club":"7i","schema_version":"1.0"}
```

**Rationale:** Whitespace variation would cause identical templates to produce different hashes.

### 5.2.4 String Encoding

**Rule:** All strings must be UTF-8 encoded with no BOM (Byte Order Mark).

**Character Escaping:** Use standard JSON escaping:
- Control characters: `\n`, `\t`, `\r`, etc.
- Quotes: `\"`
- Backslash: `\\`
- Unicode: `\uXXXX` (where needed)

**Prohibited:**
- UTF-16 encoding
- UTF-8 with BOM
- Platform-specific encodings (Windows-1252, etc.)

### 5.2.5 Array Ordering

**Rule:** Array elements maintain their **original order** (not sorted).

```json
// If the template defines metrics as an array (not object), preserve order
{
  "metrics": [
    {"name": "ball_speed", "a_min": 108.92},
    {"name": "smash_factor", "a_min": 1.32}
  ]
}
```

**Rationale:** Metric order may have semantic meaning. Unlike object keys, array ordering is preserved in canonical form.

---

## 5.3 Hashing Algorithm

### 5.3.1 Algorithm Specification

**Algorithm:** SHA-256 (Secure Hash Algorithm 256-bit)

**Output Format:** Lowercase hexadecimal string (64 characters)

```
template_hash = sha256(canonical_json_bytes).hexdigest().lower()
```

**Example:**

```
Input:  {"club":"7i","schema_version":"1.0"}
SHA-256: a3f8b5c2e1d4...  (64 hex chars)
```

### 5.3.2 Implementation Requirements

1. **Use standard library implementations:**
   - Python: `hashlib.sha256()`
   - Swift: `CryptoKit.SHA256.hash()`
   - JavaScript: `crypto.subtle.digest('SHA-256', ...)`

2. **Do not implement custom hash functions** — use vetted cryptographic libraries

3. **Output format:**
   - 64 lowercase hexadecimal characters
   - Example: `a3f8b5c2e1d4f6a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e0f1a2b3c4`

### 5.3.3 Cross-Platform Determinism

**Critical Requirement:** Given identical canonical JSON, implementations in Python and Swift **must** produce identical hashes.

**Validation Strategy:**

1. Create reference test cases with known hash values
2. Verify Python implementation produces expected hashes
3. Verify Swift implementation produces identical hashes
4. Include test cases in regression suite

**Reference Test Case (Example):**

```json
Template JSON (after canonicalization):
{"aggregation_method":"worst_metric","club":"7i","created_at":"2026-01-28T05:03:44Z","metrics":{"ball_speed":{"a_min":108.92,"b_min":106.60,"direction":"higher_is_better"},"descent_angle":{"a_min":48.42,"b_min":46.30,"direction":"higher_is_better"},"smash_factor":{"a_min":1.32,"b_min":1.29,"direction":"higher_is_better"},"spin_rate":{"a_min":4854,"b_min":4669,"direction":"higher_is_better"}},"provenance":{"method":"percentile_baseline","n_shots_used":59,"source_session":"fixture_mlm2pro_shotexport_anonymized.csv"},"schema_version":"1.0"}

Expected Hash:
[To be determined during implementation and documented here]
```

---

## 5.4 Canonicalization Process (Step-by-Step)

### Input
Raw JSON (potentially pretty-printed, with arbitrary key ordering)

### Process

1. **Parse JSON** into native data structure (dict/object)
2. **Recursively sort keys** at all nesting levels
3. **Normalize numeric values** according to chosen strategy
4. **Serialize to compact JSON** (no whitespace)
5. **Encode as UTF-8 bytes** (no BOM)
6. **Compute SHA-256 hash**
7. **Format as lowercase hex string**

### Output
- `canonical_json`: Compact, sorted, normalized JSON string
- `template_hash`: 64-character lowercase hex SHA-256 hash

### Pseudocode

```python
def canonicalize_and_hash(template_dict):
    # Step 1: Recursive key sorting and numeric normalization
    canonical_dict = canonicalize_recursive(template_dict)
    
    # Step 2: Serialize to compact JSON
    canonical_json = json.dumps(
        canonical_dict,
        ensure_ascii=False,
        separators=(',', ':'),  # No spaces
        sort_keys=True
    )
    
    # Step 3: Encode to UTF-8
    json_bytes = canonical_json.encode('utf-8')
    
    # Step 4: Hash
    hash_digest = hashlib.sha256(json_bytes).hexdigest().lower()
    
    return canonical_json, hash_digest

def canonicalize_recursive(obj):
    """Recursively canonicalize object (sort keys, normalize numbers)"""
    if isinstance(obj, dict):
        return {k: canonicalize_recursive(v) for k, v in sorted(obj.items())}
    elif isinstance(obj, list):
        return [canonicalize_recursive(item) for item in obj]
    elif isinstance(obj, float):
        return normalize_number(obj)  # Implementation-specific
    else:
        return obj
```

---

## 5.5 Implementation Validation

### 5.5.1 Required Test Cases

Implementations must pass these tests:

1. **Key ordering test:**
   - Input: `{"z": 1, "a": 2}` → Output: `{"a": 2, "z": 1}`

2. **Nested key ordering test:**
   - Input: `{"z": {"y": 1, "x": 2}}` → Output: `{"z": {"x": 2, "y": 1}}`

3. **Numeric normalization test:**
   - Input: `{"val": 1.0}` → Output: consistent across platforms

4. **Whitespace elimination test:**
   - Pretty JSON → Compact JSON

5. **Full template test:**
   - Complete KPI template → Known hash value

### 5.5.2 Cross-Platform Validation

**Requirement:** Python and Swift implementations must produce identical hashes for identical inputs.

**Test procedure:**

1. Define 10+ reference templates
2. Compute hashes in Python implementation
3. Compute hashes in Swift implementation
4. Assert all hashes match exactly
5. Include in CI/CD pipeline

---

## 5.6 Error Handling

### Invalid JSON

If input JSON is malformed:

1. Parse error should be raised immediately
2. Do **not** attempt to "fix" or "guess" structure
3. Provide clear error message indicating parse failure

### Unsupported Data Types

If JSON contains types not in template schema:

1. Reject with validation error
2. Do **not** silently strip unknown fields
3. Template must conform to schema before canonicalization

### Hash Collision (Theoretical)

SHA-256 collisions are computationally infeasible. If a collision is somehow detected:

1. Log the incident (this would be cryptographically significant)
2. Reject the template
3. Do **not** store templates with duplicate hashes

---

## 5.7 Security Considerations

### 5.7.1 Hash Preimage Resistance

SHA-256 provides strong preimage resistance — it is computationally infeasible to:

- Find a template that hashes to a specific value (first preimage)
- Find two templates that hash to the same value (collision)

This guarantees template identity integrity.

### 5.7.2 Canonicalization Bugs

**Risk:** Bugs in canonicalization could allow:
- Same logical template → different hashes
- Different logical templates → same hash (via collision)

**Mitigation:**

1. Use well-tested JSON libraries
2. Include comprehensive test suite
3. Validate against reference implementations
4. Document canonical form with examples

### 5.7.3 Trusted Input

**Assumption:** Template JSON is trusted input (user-generated or imported from known sources).

**No protection against:** Maliciously crafted JSON exploiting parser vulnerabilities.

**Rationale:** Phase 0 is local-only, single-user. Input validation for security is Phase 1+ concern.

---

## 5.8 Future Considerations

### Algorithm Upgrade (Phase 1+)

If SHA-256 needs to be replaced (e.g., quantum-resistant algorithm):

**Strategy:**

1. Add `hash_algorithm` field to template schema
2. Support multiple algorithms in parallel
3. References include algorithm version: `sha256:a3f8b5c2...`
4. Gradually migrate templates to new algorithm

**Constraint:** Cannot break existing `template_hash` references.

---

## 5.9 Summary of Requirements

### MUST Rules

1. Object keys MUST be sorted alphabetically at all nesting levels
2. Numeric values MUST be normalized deterministically
3. JSON MUST be compact (no whitespace)
4. Encoding MUST be UTF-8 without BOM
5. Hash algorithm MUST be SHA-256
6. Hash output MUST be 64-character lowercase hex
7. Python and Swift implementations MUST produce identical hashes

### MUST NOT Rules

1. MUST NOT pretty-print canonical JSON
2. MUST NOT use non-deterministic serialization
3. MUST NOT accept non-UTF-8 encodings
4. MUST NOT use custom hash functions
5. MUST NOT recompute hashes after storage

---

[Next: Session & Sub-Session Invariants →](06_session_invariants.md)
