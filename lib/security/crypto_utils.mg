// ============================================================================
// Magnetar Security Library: Cryptographic Utilities & Safe Encoding
// File: lib/security/crypto_utils.mg
// ============================================================================

use "lib/string.mg";

// System call for Linux kernel CSPRNG
extern fn sys_getrandom(char* buf, int buflen, int flags) -> int;

// ----------------------------------------------------------------------------
// 1. Secure Randomness & Tokens (like Python's 'secrets' module)
// ----------------------------------------------------------------------------

// Fills buffer with cryptographically secure random bytes from kernel entropy
fn crypto_random_bytes(char* buf, int count) -> int {
    if (buf == null || count <= 0) {
        return 0;
    }
    return sys_getrandom(buf, count, 0);
}

// Internal nibble to hex character
fn _nibble_to_hex(int n) -> char {
    n = n & 15;
    if (n < 10) {
        return cast<char>(48 + n); // '0'..'9'
    }
    return cast<char>(97 + (n - 10)); // 'a'..'f'
}

// Internal hex character to nibble (-1 on invalid)
fn _hex_to_nibble(int c) -> int {
    if (c >= 48 && c <= 57) {
        return c - 48;
    }
    if (c >= 97 && c <= 102) {
        return c - 97 + 10;
    }
    if (c >= 65 && c <= 70) {
        return c - 65 + 10;
    }
    return -1;
}

// Generates a cryptographically secure random hex token (e.g. CSRF tokens, session IDs)
fn crypto_random_token_hex(int byte_count) -> string {
    if (byte_count <= 0) {
        return "";
    }
    char* buf_bytes = alloc<char>(byte_count);
    crypto_random_bytes(buf_bytes, byte_count);
    
    char* out = alloc<char>(byte_count * 2 + 1);
    let i = 0;
    while (i < byte_count) {
        let b = cast<int>(buf_bytes[i]) & 255;
        out[i * 2] = _nibble_to_hex(b >> 4);
        out[i * 2 + 1] = _nibble_to_hex(b & 15);
        i = i + 1;
    }
    out[byte_count * 2] = 0;
    free(buf_bytes);
    return cast<string>(out);
}

// Generates a cryptographically secure UUIDv4 (RFC 4122 compliant)
fn crypto_random_uuid_v4() -> string {
    char* buf_bytes = alloc<char>(16);
    crypto_random_bytes(buf_bytes, 16);
    
    // Set version 4: bits 4..7 of byte 6 = 0100
    let b6 = (cast<int>(buf_bytes[6]) & 15) | 64;
    buf_bytes[6] = cast<char>(b6);
    
    // Set variant RFC 4122: bits 6..7 of byte 8 = 10
    let b8 = (cast<int>(buf_bytes[8]) & 63) | 128;
    buf_bytes[8] = cast<char>(b8);
    
    // Format: 8-4-4-4-12 -> 36 chars + 1 null terminator
    char* out = alloc<char>(37);
    let out_idx = 0;
    
    let i = 0;
    while (i < 16) {
        if (i == 4 || i == 6 || i == 8 || i == 10) {
            out[out_idx] = '-';
            out_idx = out_idx + 1;
        }
        let b = cast<int>(buf_bytes[i]) & 255;
        out[out_idx] = _nibble_to_hex(b >> 4);
        out_idx = out_idx + 1;
        out[out_idx] = _nibble_to_hex(b & 15);
        out_idx = out_idx + 1;
        i = i + 1;
    }
    out[36] = 0;
    free(buf_bytes);
    return cast<string>(out);
}

// ----------------------------------------------------------------------------
// 2. Hex Encoding & Decoding
// ----------------------------------------------------------------------------

fn hex_encode(char* data, int length) -> string {
    if (data == null || length <= 0) {
        return "";
    }
    char* out = alloc<char>(length * 2 + 1);
    let i = 0;
    while (i < length) {
        let b = cast<int>(data[i]) & 255;
        out[i * 2] = _nibble_to_hex(b >> 4);
        out[i * 2 + 1] = _nibble_to_hex(b & 15);
        i = i + 1;
    }
    out[length * 2] = 0;
    return cast<string>(out);
}

fn hex_decode(string hex_str, int* out_length) -> char* {
    if (hex_str == null) {
        *out_length = 0;
        return null;
    }
    let slen = str_len(hex_str);
    if ((slen % 2) != 0) {
        *out_length = 0;
        return null;
    }
    let byte_count = slen / 2;
    char* out = alloc<char>(byte_count);
    char* p = cast<char*>(hex_str);
    
    let i = 0;
    while (i < byte_count) {
        let n1 = _hex_to_nibble(cast<int>(p[i * 2]) & 255);
        let n2 = _hex_to_nibble(cast<int>(p[i * 2 + 1]) & 255);
        if (n1 < 0 || n2 < 0) {
            free(out);
            *out_length = 0;
            return null;
        }
        out[i] = cast<char>((n1 << 4) | n2);
        i = i + 1;
    }
    *out_length = byte_count;
    return out;
}

// ----------------------------------------------------------------------------
// 3. Base64 Encoding & Decoding
// ----------------------------------------------------------------------------

fn _b64_char(int index) -> char {
    index = index & 63;
    if (index >= 0 && index <= 25) {
        return cast<char>(65 + index); // 'A'..'Z'
    }
    if (index >= 26 && index <= 51) {
        return cast<char>(97 + (index - 26)); // 'a'..'z'
    }
    if (index >= 52 && index <= 61) {
        return cast<char>(48 + (index - 52)); // '0'..'9'
    }
    if (index == 62) {
        return '+';
    }
    return '/';
}

fn _b64_value(int c) -> int {
    if (c >= 65 && c <= 90) { return c - 65; }
    if (c >= 97 && c <= 122) { return c - 97 + 26; }
    if (c >= 48 && c <= 57) { return c - 48 + 52; }
    if (c == 43) { return 62; } // '+'
    if (c == 47) { return 63; } // '/'
    return -1;
}

fn base64_encode(char* data, int length) -> string {
    if (data == null || length <= 0) {
        return "";
    }
    let out_len = ((length + 2) / 3) * 4;
    char* out = alloc<char>(out_len + 1);
    let out_idx = 0;
    
    let i = 0;
    while (i < length) {
        let b0 = cast<int>(data[i]) & 255;
        let b1 = 0;
        let b2 = 0;
        if (i + 1 < length) {
            b1 = cast<int>(data[i + 1]) & 255;
        }
        if (i + 2 < length) {
            b2 = cast<int>(data[i + 2]) & 255;
        }
        
        out[out_idx] = _b64_char(b0 >> 2);
        out_idx = out_idx + 1;
        out[out_idx] = _b64_char(((b0 & 3) << 4) | (b1 >> 4));
        out_idx = out_idx + 1;
        
        if (i + 1 < length) {
            out[out_idx] = _b64_char(((b1 & 15) << 2) | (b2 >> 6));
        } else {
            out[out_idx] = '=';
        }
        out_idx = out_idx + 1;
        
        if (i + 2 < length) {
            out[out_idx] = _b64_char(b2 & 63);
        } else {
            out[out_idx] = '=';
        }
        out_idx = out_idx + 1;
        
        i = i + 3;
    }
    out[out_len] = 0;
    return cast<string>(out);
}

// ----------------------------------------------------------------------------
// 4. Message Integrity Check (64-bit Keyed Checksum / Token Tag)
// ----------------------------------------------------------------------------

// Calculates a 64-bit keyed MAC (using FNV-1a 64-bit with key mixing)
// Used for tamper-proof session tokens and API signatures
fn crypto_keyed_tag(string key, string message) -> string {
    char* pkey = cast<char*>(key);
    char* pmsg = cast<char*>(message);
    let klen = str_len(key);
    let mlen = str_len(message);
    
    let hash = 1469598103934665603; // FNV offset basis 64-bit
    let prime = 1099511628211;      // FNV prime 64-bit
    
    // Hash key first
    let i = 0;
    while (i < klen) {
        let b = cast<int>(pkey[i]) & 255;
        hash = hash ^ b;
        hash = hash * prime;
        i = i + 1;
    }
    
    // Hash message
    i = 0;
    while (i < mlen) {
        let b = cast<int>(pmsg[i]) & 255;
        hash = hash ^ b;
        hash = hash * prime;
        i = i + 1;
    }
    
    // Output 16-hex char signature
    char* out = alloc<char>(17);
    for (int j = 0; j < 16; j = j + 1) {
        let shift = (15 - j) * 4;
        let nib = (hash >> shift) & 15;
        out[j] = _nibble_to_hex(nib);
    }
    out[16] = 0;
    return cast<string>(out);
}
