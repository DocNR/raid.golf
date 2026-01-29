"""
Template hashing for content-addressed KPI templates.

Computes SHA-256 hash of canonical JSON representation.
Cross-platform deterministic via Decimal-based canonicalization.
"""
import hashlib
from typing import Any, Dict

from raid.canonical import canonicalize


def compute_template_hash(template_dict: Dict[str, Any]) -> str:
    """
    Compute SHA-256 hash of canonical template JSON.
    
    The hash is computed ONCE during template creation and stored.
    Read operations must NOT call this function (RTM-04).
    
    Args:
        template_dict: Template dictionary to hash
    
    Returns:
        64-character lowercase hex SHA-256 hash
    """
    canonical_json = canonicalize(template_dict)
    json_bytes = canonical_json.encode('utf-8')
    return hashlib.sha256(json_bytes).hexdigest().lower()
