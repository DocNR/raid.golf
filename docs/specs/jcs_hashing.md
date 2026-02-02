# Template Hashing Specification — RFC 8785 JCS

**Version:** 2.0  
**Date:** 2026-02-02  
**Audience:** Cross-platform implementers (Swift, JavaScript, Rust, etc.)  
**Status:** Normative

---

## Template Identity Formula

```
template_hash = SHA-256( UTF-8( JCS( template_json ) ) )
```

Where:
- **JCS** = RFC 8785 JSON Canonicalization Scheme
- **UTF-8** = UTF-8 encoding without BOM
- **SHA-256** = Secure Hash Algorithm 256-bit
- **Output** = 64-character lowercase hexadecimal string

---

## Canonicalization Rules (RFC 8785 JCS)

### 1. Key Ordering
- Object keys MUST be sorted **lexicographically** (Unicode code point order)
- Sorting applies **recursively** at all nesting levels

### 2. Whitespace
- Canonical JSON MUST be **compact** (no insignificant whitespace)
- No spaces, newlines, or tabs outside string values

### 3. String Encoding
- Strings MUST be UTF-8 encoded
- Standard JSON escaping applies: `\"`, `\\`, `\n`, `\t`, `\uXXXX`
- No UTF-8 BOM

### 4. Number Serialization
- Numbers MUST conform to RFC 8785 §3.2.2.3
- Integers serialized without decimal point: `5` not `5.0`
- Decimals use minimal precision: `1.5` not `1.50`
- Scientific notation (E notation) MAY be used per RFC 8785 for numbers outside the interoperable range
- No leading zeros (except `0.x`)

### 5. Arrays
- Array element order is **preserved** (not sorted)

### 6. I-JSON Constraints (Enforced)
- **No NaN or Infinity** — producers MUST reject
- **No duplicate keys** — producers MUST NOT emit
- **Valid JSON numbers only** — no hex, octal, or other non-standard formats
- **Valid UTF-8 strings** — no invalid byte sequences

---

## Hash Computation

1. **Canonicalize** the template JSON using RFC 8785 JCS
2. **Encode** the canonical string as UTF-8 bytes (no BOM)
3. **Hash** the bytes using SHA-256
4. **Format** the hash as lowercase hexadecimal (64 characters)

---

## Reference Implementation (Python)

```python
import hashlib
import canonicaljson  # RFC 8785 library

def compute_template_hash(template_dict):
    """Compute RFC 8785 JCS + SHA-256 hash of template."""
    # Canonicalize per RFC 8785
    canonical_bytes = canonicaljson.encode_canonical_json(template_dict)
    
    # Hash
    hash_digest = hashlib.sha256(canonical_bytes).hexdigest()
    
    return hash_digest.lower()
```

---

## Test Vectors

See `tests/vectors/jcs_vectors.json` for canonical test cases.

Each vector includes:
- **input**: Template JSON (object form)
- **canonical**: Expected JCS canonical string
- **sha256**: Expected hash (lowercase hex)

Implementations MUST produce identical output for all test vectors.

---

## Validation Requirements

### Producers (Template Creation)
- MUST reject NaN, Infinity, or invalid JSON numbers
- MUST NOT emit duplicate keys
- MUST compute hash exactly once at creation
- MUST store hash alongside template

### Consumers (Template Verification)
- MUST verify hash matches JCS canonicalization
- MUST NOT recompute hash on read (use stored hash)
- MAY reject templates with duplicate keys (optional)

---

## Cross-Platform Determinism

**Critical requirement:** Given identical template JSON, implementations in **all languages** MUST produce **identical hashes**.

Validation strategy:
1. Use test vectors from `tests/vectors/jcs_vectors.json`
2. Verify your implementation produces exact matches
3. Include test vectors in your unit test suite

---

## Security Considerations

- **SHA-256 preimage resistance**: Computationally infeasible to find a template that hashes to a specific value
- **Collision resistance**: Computationally infeasible to find two templates with the same hash
- **Canonicalization bugs**: Use vetted RFC 8785 libraries; do not implement JCS from scratch unless necessary

---

## References

- **RFC 8785**: JSON Canonicalization Scheme (JCS)  
  https://www.rfc-editor.org/rfc/rfc8785
- **I-JSON**: RFC 7493 (Internet JSON)  
  https://www.rfc-editor.org/rfc/rfc7493
- **SHA-256**: FIPS 180-4  
  https://csrc.nist.gov/publications/detail/fips/180/4/final

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-02-01 | Custom Decimal-based canonicalization (deprecated) |
| 2.0 | 2026-02-02 | RFC 8785 JCS canonicalization (current) |
