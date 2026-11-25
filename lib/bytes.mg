// ============================================================================
// Magnetar Standard Library: Bytes / Data Size (lib/bytes.mg)
// Convert a byte count into a human-readable size: B, KB, MB, GB, TB, PB, ...
//
// Two conventions are supported:
//   - Binary (default): 1 KB = 1024 B  -> bytes_to_string()
//   - SI decimal:       1 KB = 1000 B  -> bytes_to_string_si()
//
// Example:
//   print_str(bytes_to_string(1536));       // 1.50 KB
//   print_str(bytes_to_string_si(1500));    // 1.50 KB
// ============================================================================

use "string.mg";

// Number of supported units (B .. YB).
fn bytes_unit_count() -> int {
    return 9;
}

// Human-readable name for a unit index (0 = B, 1 = KB, ...).
fn bytes_unit_name(int unit) -> string {
    if (unit <= 0) { return "B"; }
    if (unit == 1) { return "KB"; }
    if (unit == 2) { return "MB"; }
    if (unit == 3) { return "GB"; }
    if (unit == 4) { return "TB"; }
    if (unit == 5) { return "PB"; }
    if (unit == 6) { return "EB"; }
    if (unit == 7) { return "ZB"; }
    return "YB";
}

// radix^exponent, used to build the divisor for a unit.
fn _bytes_factor(int radix, int unit) -> int {
    if (unit < 0) { unit = 0; }
    if (unit > 8) { unit = 8; }
    int result = 1;
    for (int i = 0; i < unit; i++) {
        result = result * radix;
    }
    return result;
}

// Absolute value, avoiding the known negative-float issues.
fn _bytes_abs(int value) -> int {
    if (value < 0) {
        return 0 - value;
    }
    return value;
}

// Pick the largest unit that keeps the magnitude >= 1.
fn _bytes_unit_index_abs(int magnitude, int radix) -> int {
    int unit = 0;
    while (magnitude >= radix && unit < 8) {
        magnitude = magnitude / radix;
        unit = unit + 1;
    }
    return unit;
}

// Unit index using binary units (1024).
fn bytes_unit_index(int bytes) -> int {
    return _bytes_unit_index_abs(_bytes_abs(bytes), 1024);
}

// Unit index using SI decimal units (1000).
fn bytes_unit_index_si(int bytes) -> int {
    return _bytes_unit_index_abs(_bytes_abs(bytes), 1000);
}

// Scaled value in the given binary unit (unit 0 = bytes, 1 = KB, ...).
fn bytes_value(int bytes, int unit) -> float {
    int factor = _bytes_factor(1024, unit);
    float value = cast<float>(bytes);
    float divisor = cast<float>(factor);
    return value / divisor;
}

// Scaled value in the given SI decimal unit.
fn bytes_value_si(int bytes, int unit) -> float {
    int factor = _bytes_factor(1000, unit);
    float value = cast<float>(bytes);
    float divisor = cast<float>(factor);
    return value / divisor;
}

// Convert a value expressed in `unit` back to bytes (binary units).
fn unit_to_bytes(float value, int unit) -> int {
    int factor = _bytes_factor(1024, unit);
    return cast<int>(value * cast<float>(factor));
}

// Convert a value expressed in `unit` back to bytes (SI decimal units).
fn unit_to_bytes_si(float value, int unit) -> int {
    int factor = _bytes_factor(1000, unit);
    return cast<int>(value * cast<float>(factor));
}

// Core formatter. `decimals` is clamped to 0..6, and byte-only output (B)
// never shows a fractional part.
fn _bytes_format(int bytes, int decimals, int radix) -> string {
    int magnitude = _bytes_abs(bytes);
    if (decimals < 0) { decimals = 0; }
    if (decimals > 6) { decimals = 6; }

    int unit = _bytes_unit_index_abs(magnitude, radix);
    if (unit == 0) { decimals = 0; }

    int factor = _bytes_factor(radix, unit);
    float magnitude_f = cast<float>(magnitude);
    float factor_f = cast<float>(factor);
    float scaled = magnitude_f / factor_f;

    // Round the scaled value ourselves. float_to_str() does not carry a
    // fraction that rounds up to 10^decimals (it would print 0.100 instead of
    // 1.00), so we also use the rounded value to detect unit promotion: e.g.
    // 1023.999 KB must become 1.00 MB instead of "1024.00 KB".
    int scale = 1;
    for (int i = 0; i < decimals; i++) {
        scale = scale * 10;
    }
    float scale_f = cast<float>(scale);
    int scaled_int = cast<int>(scaled * scale_f + 0.5);
    if (scaled_int >= radix * scale && unit < 8) {
        unit = unit + 1;
        scaled_int = scaled_int / radix;
    }
    scaled = cast<float>(scaled_int) / scale_f;

    string number = float_to_str(scaled, decimals);
    string result = str_concat(number, " ");
    result = str_concat(result, bytes_unit_name(unit));
    if (bytes < 0) {
        result = str_concat("-", result);
    }
    return result;
}

// Auto-scale with binary units and 2 decimals (0 decimals for plain bytes).
fn bytes_to_string(int bytes) -> string {
    return _bytes_format(bytes, 2, 1024);
}

// Auto-scale with binary units and an explicit number of decimals.
fn bytes_to_string_prec(int bytes, int decimals) -> string {
    return _bytes_format(bytes, decimals, 1024);
}

// Auto-scale with SI decimal units and 2 decimals (0 decimals for plain bytes).
fn bytes_to_string_si(int bytes) -> string {
    return _bytes_format(bytes, 2, 1000);
}

// Auto-scale with SI decimal units and an explicit number of decimals.
fn bytes_to_string_si_prec(int bytes, int decimals) -> string {
    return _bytes_format(bytes, decimals, 1000);
}

// Short aliases.
fn bytes_format(int bytes) -> string {
    return bytes_to_string(bytes);
}

fn bytes_format_si(int bytes) -> string {
    return bytes_to_string_si(bytes);
}

// Bit conversions (1 byte = 8 bits).
fn bytes_to_bits(int bytes) -> int {
    return bytes * 8;
}

fn bits_to_bytes(int bits) -> int {
    return bits / 8;
}
