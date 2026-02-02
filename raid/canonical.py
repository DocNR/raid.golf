"""
Canonical JSON transformation for template content-addressing.

Implements RFC 8785 JSON Canonicalization Scheme (JCS) for template identity.

Version: 2.0 (Kernel v2.0)
Standard: RFC 8785 (https://www.rfc-editor.org/rfc/rfc8785)
"""
import json
import math
from typing import Any, Dict

# Use canonicaljson library for RFC 8785 compliance
try:
    import canonicaljson
    _HAS_JCS_LIBRARY = True
except ImportError:
    _HAS_JCS_LIBRARY = False


def _validate_json_value(value: Any, path: str = "root") -> None:
    """
    Validate that a value conforms to I-JSON constraints.
    
    Raises ValueError if the value contains:
    - NaN or Infinity
    - Invalid numeric types
    
    Args:
        value: Value to validate
        path: Current path in object tree (for error messages)
    """
    if isinstance(value, float):
        if math.isnan(value):
            raise ValueError(f"NaN is not allowed in templates (at {path})")
        if math.isinf(value):
            raise ValueError(f"Infinity is not allowed in templates (at {path})")
    elif isinstance(value, dict):
        for key, val in value.items():
            _validate_json_value(val, f"{path}.{key}")
    elif isinstance(value, list):
        for idx, val in enumerate(value):
            _validate_json_value(val, f"{path}[{idx}]")


def canonicalize(template_dict: Dict[str, Any]) -> str:
    """
    Convert template dictionary to RFC 8785 JCS canonical form.
    
    This function produces canonical JSON suitable for cryptographic hashing
    by applying RFC 8785 JSON Canonicalization Scheme (JCS).
    
    Rules (per RFC 8785):
    - Lexicographic key sorting at all nesting levels
    - Compact format (no whitespace)
    - UTF-8 encoding
    - I-JSON constraints (no NaN/Infinity)
    - Deterministic number serialization
    
    Args:
        template_dict: Template dictionary to canonicalize
    
    Returns:
        Canonical JSON string (UTF-8, compact, sorted keys)
    
    Raises:
        ValueError: If template contains NaN, Infinity, or other invalid values
        ImportError: If json_canonicalize library is not installed
    """
    # Validate I-JSON constraints
    _validate_json_value(template_dict)
    
    if not _HAS_JCS_LIBRARY:
        raise ImportError(
            "canonicaljson library is required for RFC 8785 JCS canonicalization. "
            "Install with: pip install canonicaljson"
        )
    
    # Use RFC 8785 library for canonical transformation
    # canonicaljson.encode_canonical_json returns bytes
    canonical_bytes = canonicaljson.encode_canonical_json(template_dict)
    canonical_str = canonical_bytes.decode('utf-8')
    
    return canonical_str
