"""
Canonical JSON transformation for template content-addressing.

Implements the Phase 0 canonical JSON rules:
- Alphabetically sorted keys at all nesting levels
- Deterministic numeric normalization using Decimal (no binary floats)
- Compact format (no whitespace)
- UTF-8 encoding without BOM
"""
import json
from dataclasses import dataclass
from decimal import Decimal
from typing import Any, Dict, List, Union


@dataclass(frozen=True, slots=True)
class NumericToken:
    """
    Immutable wrapper type for canonical numeric strings.
    
    Ensures numeric values are emitted as unquoted JSON tokens,
    while regular strings are always quoted.
    
    Frozen dataclass ensures no mutation after creation.
    """
    value: str


def _format_decimal(dec: Decimal) -> str:
    """
    Format a Decimal as a canonical numeric string.
    
    Rules:
    - No scientific notation
    - Strip trailing zeros after decimal point
    - Strip decimal point if result is an integer
    - Always include leading zero for |x| < 1
    - Normalize -0 to 0
    
    Returns a string representation suitable for JSON numeric tokens.
    """
    # Normalize -0 to 0
    if dec == Decimal('0'):
        dec = Decimal('0')
    
    # Check if it's an integer
    if dec == dec.to_integral_value():
        return str(int(dec))
    
    # Format as fixed-point (no scientific notation)
    str_val = str(dec)
    
    # Handle scientific notation (convert to fixed-point)
    if 'E' in str_val or 'e' in str_val:
        sign, digits, exponent = dec.as_tuple()
        
        # Build the number as a string
        digit_str = ''.join(str(d) for d in digits)
        
        if exponent >= 0:
            # Positive exponent - add zeros
            result = digit_str + ('0' * exponent)
        else:
            # Negative exponent - add decimal point
            abs_exp = abs(exponent)
            if abs_exp >= len(digit_str):
                # Need leading zeros
                result = '0.' + ('0' * (abs_exp - len(digit_str))) + digit_str
            else:
                # Insert decimal point
                result = digit_str[:-abs_exp] + '.' + digit_str[-abs_exp:]
        
        # Add sign if negative
        if sign:
            result = '-' + result
    else:
        result = str_val
    
    # Strip trailing zeros and trailing decimal point
    if '.' in result:
        result = result.rstrip('0').rstrip('.')
    
    return result


def _normalize_numeric(value: Union[int, float, Decimal]) -> NumericToken:
    """
    Normalize numeric values to canonical token form.
    
    Returns a NumericToken (not a bare string) to distinguish from regular strings.
    """
    # Convert to Decimal for precise manipulation
    if isinstance(value, (int, float)):
        dec = Decimal(str(value))
    else:
        dec = value
    
    return NumericToken(_format_decimal(dec))


def _canonicalize_value(value: Any) -> Any:
    """
    Recursively canonicalize a value.
    
    - Dicts: sort keys and recurse
    - Lists: preserve order and recurse
    - Numbers: normalize to NumericToken
    - Other types: pass through
    """
    if isinstance(value, dict):
        # Sort keys and recursively canonicalize values
        return {k: _canonicalize_value(v) for k, v in sorted(value.items())}
    elif isinstance(value, list):
        # Preserve list order but canonicalize elements
        return [_canonicalize_value(item) for item in value]
    elif isinstance(value, (int, float, Decimal)):
        # Return as NumericToken to mark as unquoted numeric
        return _normalize_numeric(value)
    else:
        # Strings, booleans, None pass through unchanged
        return value


def _build_json(obj: Any) -> str:
    """
    Build JSON string with proper handling of NumericToken.
    
    NumericToken values are emitted unquoted.
    Regular strings are always quoted via json.dumps.
    """
    if obj is None:
        return 'null'
    elif obj is True:
        return 'true'
    elif obj is False:
        return 'false'
    elif isinstance(obj, NumericToken):
        # Emit unquoted numeric token
        return obj.value
    elif isinstance(obj, str):
        # Regular string - always quote
        return json.dumps(obj, ensure_ascii=False)
    elif isinstance(obj, dict):
        if not obj:
            return '{}'
        # Sort keys and build
        items = []
        for key in sorted(obj.keys()):
            key_str = _build_json(key)
            val_str = _build_json(obj[key])
            items.append(f'{key_str}:{val_str}')
        return '{' + ','.join(items) + '}'
    elif isinstance(obj, list):
        if not obj:
            return '[]'
        items = [_build_json(item) for item in obj]
        return '[' + ','.join(items) + ']'
    else:
        # Fallback for unexpected types
        return json.dumps(obj, ensure_ascii=False)


def canonicalize(template_dict: Dict[str, Any]) -> str:
    """
    Convert template dictionary to canonical JSON form.
    
    Returns compact, sorted, normalized JSON string suitable for hashing.
    All numbers are formatted as Decimal strings to ensure cross-platform determinism.
    """
    # Recursively canonicalize the structure (numbers become NumericToken)
    canonical_dict = _canonicalize_value(template_dict)
    
    # Build JSON with NumericToken emitted as unquoted tokens
    canonical_json = _build_json(canonical_dict)
    
    return canonical_json
