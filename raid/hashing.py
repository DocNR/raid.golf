"""
Template hashing for content-addressed KPI templates.

Computes SHA-256 hash of RFC 8785 JCS canonical JSON representation.
Cross-platform deterministic via RFC 8785 JSON Canonicalization Scheme.

Version: 2.0 (Kernel v2.0)
Standard: RFC 8785 (https://www.rfc-editor.org/rfc/rfc8785)
"""
import hashlib
from typing import Any, Dict

from raid.canonical import canonicalize


def compute_template_hash(template_dict: Dict[str, Any]) -> str:
    """
    Compute SHA-256 hash of RFC 8785 JCS canonical template JSON.
    
    Formula: template_hash = SHA-256( UTF-8( JCS( template_json ) ) )
    
    The hash is computed ONCE during template creation and stored.
    Read operations must NOT call this function (RTM-04).
    
    Args:
        template_dict: Template dictionary to hash
    
    Returns:
        64-character lowercase hex SHA-256 hash
    
    Raises:
        ValueError: If template contains NaN, Infinity, or other invalid values
        ImportError: If canonicaljson library is not installed
    """
    canonical_json = canonicalize(template_dict)
    json_bytes = canonical_json.encode('utf-8')
    return hashlib.sha256(json_bytes).hexdigest().lower()
