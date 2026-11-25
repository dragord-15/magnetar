// ============================================================================
// Magnetar Standard Library: Cryptography & Encoding (lib/crypto.mg)
//
// Layers provided:
//   - Encodings: hex, Base64, Base64URL, Base32, URL/percent, ROT13, Caesar
//   - Checksums: CRC32, FNV-1a
//   - Hashes: MD5, SHA-1, SHA-256
//   - MAC/KDF: HMAC-SHA256, PBKDF2-HMAC-SHA256
//   - Ciphers: XOR, RC4, AES-128/192/256 (ECB/CBC/CTR), ChaCha20
//
// All functions are pure Magnetar (no libc/libcrypto dependency).
// ============================================================================

use "lib/string.mg";

extern fn sys_getrandom(char* buf, int buflen, int flags) -> int;

// -------------------------------------------------------------
// Byte helpers
// -------------------------------------------------------------

fn _cr_b(char* p, int i) -> int {
    return cast<int>(*(p + i)) & 255;
}

fn _cr_put(char* p, int i, int v) -> void {
    *(p + i) = cast<char>(v & 255);
}

fn _cr_min(int a, int b) -> int {
    if (a < b) { return a; }
    return b;
}

fn _cr_u32(int x) -> int {
    return x & 4294967295;
}

fn _cr_rotr32(int x, int n) -> int {
    x = x & 4294967295;
    if (n == 0) { return x; }
    return ((x >> n) | (x << (32 - n))) & 4294967295;
}

fn _cr_rotl32(int x, int n) -> int {
    x = x & 4294967295;
    if (n == 0) { return x; }
    return ((x << n) | (x >> (32 - n))) & 4294967295;
}

fn _cr_copy(char* dst, char* src, int count) -> void {
    for (int i = 0; i < count; i = i + 1) {
        *(dst + i) = *(src + i);
    }
}

fn _cr_zero(char* dst, int count) -> void {
    for (int i = 0; i < count; i = i + 1) {
        *(dst + i) = 0;
    }
}

// -------------------------------------------------------------
// Random bytes (Linux getrandom)
// -------------------------------------------------------------

fn crypto_rng_bytes(char* buffer, int count) -> int {
    if (buffer == null || count <= 0) { return 0; }
    int total = 0;
    while (total < count) {
        int n = sys_getrandom(buffer + total, count - total, 0);
        if (n <= 0) { return total; }
        total = total + n;
    }
    return total;
}

fn crypto_rng_hex(int count) -> string {
    if (count <= 0) { return ""; }
    char* buf = alloc<char>(count);
    crypto_rng_bytes(buf, count);
    string out = crypto_hex_encode(buf, count);
    free(buf);
    return out;
}

// -------------------------------------------------------------
// Hex codec
// -------------------------------------------------------------

fn _cr_hex_digit(int v, bool upper) -> char {
    int n = v & 15;
    if (n < 10) { return cast<char>(48 + n); }
    if (upper) { return cast<char>(65 + n - 10); }
    return cast<char>(97 + n - 10);
}

fn crypto_hex_encode(char* data, int length) -> string {
    if (data == null || length <= 0) { return ""; }
    char* out = alloc<char>(length * 2 + 1);
    int pos = 0;
    for (int i = 0; i < length; i = i + 1) {
        int b = _cr_b(data, i);
        *(out + pos) = _cr_hex_digit(b >> 4, false); pos = pos + 1;
        *(out + pos) = _cr_hex_digit(b, false); pos = pos + 1;
    }
    *(out + pos) = 0;
    return cast<string>(out);
}

fn crypto_hex_decode(string text, int* out_len) -> char* {
    if (out_len != null) { *out_len = 0; }
    if (text == null) { return null; }
    int n = len(text);
    if ((n % 2) != 0) { return null; }
    int count = n / 2;
    char* out = alloc<char>(count + 1);
    char* p = cast<char*>(text);
    for (int i = 0; i < count; i = i + 1) {
        int hi = _cr_hex_val(_cr_b(p, i * 2));
        int lo = _cr_hex_val(_cr_b(p, i * 2 + 1));
        if (hi < 0 || lo < 0) {
            free(out);
            return null;
        }
        _cr_put(out, i, (hi << 4) | lo);
    }
    *(out + count) = 0;
    if (out_len != null) { *out_len = count; }
    return out;
}

fn _cr_hex_val(int c) -> int {
    if (c >= 48 && c <= 57) { return c - 48; }
    if (c >= 65 && c <= 70) { return c - 55; }
    if (c >= 97 && c <= 102) { return c - 87; }
    return -1;
}

// -------------------------------------------------------------
// Base64 / Base64URL / Base32
// -------------------------------------------------------------

fn _cr_b64_char(int index, bool url_safe) -> char {
    int i = index & 63;
    if (i < 26) { return cast<char>(65 + i); }
    if (i < 52) { return cast<char>(97 + i - 26); }
    if (i < 62) { return cast<char>(48 + i - 52); }
    if (url_safe) {
        if (i == 62) { return '-'; }
        return '_';
    }
    if (i == 62) { return '+'; }
    return '/';
}

fn _cr_b64_val(int c) -> int {
    if (c >= 65 && c <= 90) { return c - 65; }
    if (c >= 97 && c <= 122) { return c - 97 + 26; }
    if (c >= 48 && c <= 57) { return c - 48 + 52; }
    if (c == 43 || c == 45) { return 62; }
    if (c == 47 || c == 95) { return 63; }
    return -1;
}

fn crypto_base64_encode(char* data, int length) -> string {
    if (data == null || length <= 0) { return ""; }
    int out_len = ((length + 2) / 3) * 4;
    char* out = alloc<char>(out_len + 1);
    int oi = 0;
    int i = 0;
    while (i < length) {
        int b0 = _cr_b(data, i);
        int b1 = 0;
        int b2 = 0;
        if (i + 1 < length) { b1 = _cr_b(data, i + 1); }
        if (i + 2 < length) { b2 = _cr_b(data, i + 2); }
        *(out + oi) = _cr_b64_char(b0 >> 2, false); oi = oi + 1;
        *(out + oi) = _cr_b64_char(((b0 & 3) << 4) | (b1 >> 4), false); oi = oi + 1;
        if (i + 1 < length) {
            *(out + oi) = _cr_b64_char(((b1 & 15) << 2) | (b2 >> 6), false);
        } else {
            *(out + oi) = '=';
        }
        oi = oi + 1;
        if (i + 2 < length) {
            *(out + oi) = _cr_b64_char(b2 & 63, false);
        } else {
            *(out + oi) = '=';
        }
        oi = oi + 1;
        i = i + 3;
    }
    *(out + oi) = 0;
    return cast<string>(out);
}

fn crypto_base64url_encode(char* data, int length) -> string {
    if (data == null || length <= 0) { return ""; }
    int out_len = ((length + 2) / 3) * 4;
    char* out = alloc<char>(out_len + 1);
    int oi = 0;
    int i = 0;
    while (i < length) {
        int b0 = _cr_b(data, i);
        int b1 = 0;
        int b2 = 0;
        if (i + 1 < length) { b1 = _cr_b(data, i + 1); }
        if (i + 2 < length) { b2 = _cr_b(data, i + 2); }
        *(out + oi) = _cr_b64_char(b0 >> 2, true); oi = oi + 1;
        *(out + oi) = _cr_b64_char(((b0 & 3) << 4) | (b1 >> 4), true); oi = oi + 1;
        if (i + 1 < length) {
            *(out + oi) = _cr_b64_char(((b1 & 15) << 2) | (b2 >> 6), true);
            oi = oi + 1;
        }
        if (i + 2 < length) {
            *(out + oi) = _cr_b64_char(b2 & 63, true);
            oi = oi + 1;
        }
        i = i + 3;
    }
    *(out + oi) = 0;
    return cast<string>(out);
}

fn _cr_base64_decode_common(string text, bool url_safe, int* out_len) -> char* {
    if (out_len != null) { *out_len = 0; }
    if (text == null) { return null; }
    int n = len(text);
    char* p = cast<char*>(text);
    char* out = alloc<char>((n / 4) * 3 + 4);
    int oi = 0;
    int acc = 0;
    int bits = 0;
    for (int i = 0; i < n; i = i + 1) {
        int c = _cr_b(p, i);
        if (c == 61) { break; } // '='
        if (c == 32 || c == 9 || c == 10 || c == 13) { continue; }
        int v = _cr_b64_val(c);
        if (v < 0) {
            if (url_safe) { continue; }
            free(out);
            return null;
        }
        acc = ((acc << 6) | v) & 16777215;
        bits = bits + 6;
        if (bits >= 8) {
            bits = bits - 8;
            _cr_put(out, oi, (acc >> bits) & 255);
            oi = oi + 1;
        }
    }
    *(out + oi) = 0;
    if (out_len != null) { *out_len = oi; }
    return out;
}

fn crypto_base64_decode(string text, int* out_len) -> char* {
    return _cr_base64_decode_common(text, false, out_len);
}

fn crypto_base64url_decode(string text, int* out_len) -> char* {
    return _cr_base64_decode_common(text, true, out_len);
}

fn _cr_b32_char(int v) -> char {
    return cast<char>(65 + (v & 31));
}

fn crypto_base32_encode(char* data, int length) -> string {
    if (data == null || length <= 0) { return ""; }
    char* out = alloc<char>(((length + 4) / 5) * 8 + 1);
    int oi = 0;
    int i = 0;
    while (i < length) {
        int b0 = _cr_b(data, i);
        int b1 = 0;
        int b2 = 0;
        int b3 = 0;
        int b4 = 0;
        if (i + 1 < length) { b1 = _cr_b(data, i + 1); }
        if (i + 2 < length) { b2 = _cr_b(data, i + 2); }
        if (i + 3 < length) { b3 = _cr_b(data, i + 3); }
        if (i + 4 < length) { b4 = _cr_b(data, i + 4); }
        int chunk = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3;
        *(out + oi) = _cr_b32_char(b0 >> 3); oi = oi + 1;
        *(out + oi) = _cr_b32_char(((b0 & 7) << 2) | (b1 >> 6)); oi = oi + 1;
        *(out + oi) = _cr_b32_char((b1 >> 1) & 31); oi = oi + 1;
        *(out + oi) = _cr_b32_char(((b1 & 1) << 4) | (b2 >> 4)); oi = oi + 1;
        *(out + oi) = _cr_b32_char(((b2 & 15) << 1) | (b3 >> 7)); oi = oi + 1;
        *(out + oi) = _cr_b32_char((b3 >> 2) & 31); oi = oi + 1;
        *(out + oi) = _cr_b32_char(((b3 & 3) << 3) | (b4 >> 5)); oi = oi + 1;
        *(out + oi) = _cr_b32_char(b4 & 31); oi = oi + 1;
        i = i + 5;
    }
    *(out + oi) = 0;
    return cast<string>(out);
}

// -------------------------------------------------------------
// Classic / simple transforms
// -------------------------------------------------------------

fn crypto_rot13(string text) -> string {
    if (text == null) { return ""; }
    int n = len(text);
    char* p = cast<char*>(text);
    char* out = alloc<char>(n + 1);
    for (int i = 0; i < n; i = i + 1) {
        int c = _cr_b(p, i);
        if (c >= 65 && c <= 90) {
            c = 65 + ((c - 65 + 13) % 26);
        } else if (c >= 97 && c <= 122) {
            c = 97 + ((c - 97 + 13) % 26);
        }
        *(out + i) = cast<char>(c);
    }
    *(out + n) = 0;
    return cast<string>(out);
}

fn crypto_caesar(string text, int shift) -> string {
    if (text == null) { return ""; }
    int n = len(text);
    char* p = cast<char*>(text);
    char* out = alloc<char>(n + 1);
    int s = shift % 26;
    if (s < 0) { s = s + 26; }
    for (int i = 0; i < n; i = i + 1) {
        int c = _cr_b(p, i);
        if (c >= 65 && c <= 90) {
            c = 65 + ((c - 65 + s) % 26);
        } else if (c >= 97 && c <= 122) {
            c = 97 + ((c - 97 + s) % 26);
        }
        *(out + i) = cast<char>(c);
    }
    *(out + n) = 0;
    return cast<string>(out);
}

fn crypto_xor_raw(char* data, int length, string key) -> char* {
    if (out_len_null_guard(data, length, key)) { return null; }
    char* out = alloc<char>(length + 1);
    char* kp = cast<char*>(key);
    int klen = len(key);
    for (int i = 0; i < length; i = i + 1) {
        int k = _cr_b(kp, i % klen);
        _cr_put(out, i, _cr_b(data, i) ^ k);
    }
    *(out + length) = 0;
    return out;
}

fn out_len_null_guard(char* data, int length, string key) -> bool {
    return data == null || length <= 0 || key == null || len(key) == 0;
}

fn crypto_xor_hex(string text, string key) -> string {
    if (text == null || key == null || len(key) == 0) { return ""; }
    char* out = crypto_xor_raw(cast<char*>(text), len(text), key);
    string hex = crypto_hex_encode(out, len(text));
    free(out);
    return hex;
}

// -------------------------------------------------------------
// RC4
// -------------------------------------------------------------

fn crypto_rc4_raw(char* data, int length, string key) -> char* {
    if (data == null || length <= 0 || key == null || len(key) == 0) {
        return null;
    }
    int s[256];
    for (int i = 0; i < 256; i = i + 1) { s[i] = i; }
    char* kp = cast<char*>(key);
    int klen = len(key);
    int j = 0;
    for (int i = 0; i < 256; i = i + 1) {
        j = (j + s[i] + _cr_b(kp, i % klen)) & 255;
        int t = s[i]; s[i] = s[j]; s[j] = t;
    }
    char* out = alloc<char>(length + 1);
    int a = 0;
    int b = 0;
    for (int i = 0; i < length; i = i + 1) {
        a = (a + 1) & 255;
        b = (b + s[a]) & 255;
        int t = s[a]; s[a] = s[b]; s[b] = t;
        int k = s[(s[a] + s[b]) & 255];
        _cr_put(out, i, _cr_b(data, i) ^ k);
    }
    *(out + length) = 0;
    return out;
}

fn crypto_rc4_hex(string text, string key) -> string {
    if (text == null || key == null) { return ""; }
    char* out = crypto_rc4_raw(cast<char*>(text), len(text), key);
    if (out == null) { return ""; }
    string hex = crypto_hex_encode(out, len(text));
    free(out);
    return hex;
}

// -------------------------------------------------------------
// Checksums
// -------------------------------------------------------------

fn crypto_fnv1a32(string text) -> int {
    char* p = cast<char*>(text);
    int n = len(text);
    int h = 2166136261;
    for (int i = 0; i < n; i = i + 1) {
        h = h ^ _cr_b(p, i);
        h = _cr_u32(h * 16777619);
    }
    return h;
}

fn crypto_fnv1a_hex(string text) -> string {
    return crypto_hex_encode(cast<char*>(hex32_to_bytes(crypto_fnv1a32(text))), 4);
}

fn hex32_to_bytes(int value) -> char* {
    char* out = alloc<char>(4);
    _cr_put(out, 0, value >> 24);
    _cr_put(out, 1, value >> 16);
    _cr_put(out, 2, value >> 8);
    _cr_put(out, 3, value);
    return out;
}

fn crypto_crc32(string text) -> int {
    if (text == null) { return 0; }
    char* p = cast<char*>(text);
    int n = len(text);
    int crc = 4294967295;
    for (int i = 0; i < n; i = i + 1) {
        crc = crc ^ _cr_b(p, i);
        for (int b = 0; b < 8; b = b + 1) {
            if ((crc & 1) != 0) {
                crc = (crc >> 1) ^ 3988292384;
            } else {
                crc = crc >> 1;
            }
        }
        crc = crc & 4294967295;
    }
    return (crc ^ 4294967295) & 4294967295;
}

fn crypto_crc32_hex(string text) -> string {
    int value = crypto_crc32(text);
    char* b = hex32_to_bytes(value);
    string out = crypto_hex_encode(b, 4);
    free(b);
    return out;
}

// -------------------------------------------------------------
// SHA-256
// -------------------------------------------------------------

fn crypto_sha256_raw(char* data, int length, char* out32) -> void {
    if (out32 == null) { return; }
    if (data == null) { length = 0; }

    int h[8];
    h[0] = 1779033703; h[1] = 3144134277; h[2] = 1013904242; h[3] = 2773480762;
    h[4] = 1359893119; h[5] = 2600822924; h[6] = 528734635;  h[7] = 1541459225;

    int padded_len = ((length + 9 + 63) / 64) * 64;
    char* msg = alloc<char>(padded_len);
    _cr_zero(msg, padded_len);
    _cr_copy(msg, data, length);
    *(msg + length) = cast<char>(128);

    int bit_len = length * 8;
    for (int i = 0; i < 8; i = i + 1) {
        int shift = (7 - i) * 8;
        *(msg + padded_len - 8 + i) = cast<char>((bit_len >> shift) & 255);
    }

    int blocks = padded_len / 64;
    for (int block = 0; block < blocks; block = block + 1) {
        int w[64];
        int bv = block * 64;
        for (int i = 0; i < 16; i = i + 1) {
            int o = bv + i * 4;
            w[i] = (_cr_b(msg, o) << 24) | (_cr_b(msg, o + 1) << 16) |
                   (_cr_b(msg, o + 2) << 8) | _cr_b(msg, o + 3);
        }
        for (int i = 16; i < 64; i = i + 1) {
            int s0 = _cr_rotr32(w[i - 15], 7) ^ _cr_rotr32(w[i - 15], 18) ^ (w[i - 15] >> 3);
            int s1 = _cr_rotr32(w[i - 2], 17) ^ _cr_rotr32(w[i - 2], 19) ^ (w[i - 2] >> 10);
            w[i] = _cr_u32(w[i - 16] + s0 + w[i - 7] + s1);
        }

        int a = h[0];
        int b = h[1];
        int c = h[2];
        int d = h[3];
        int e = h[4];
        int f = h[5];
        int g = h[6];
        int hh = h[7];

        for (int i = 0; i < 64; i = i + 1) {
            int S1 = _cr_rotr32(e, 6) ^ _cr_rotr32(e, 11) ^ _cr_rotr32(e, 25);
            int ch = (e & f) ^ ((~e) & g);
            int temp1 = _cr_u32(hh + S1 + ch + _cr_sha256_k(i) + w[i]);
            int S0 = _cr_rotr32(a, 2) ^ _cr_rotr32(a, 13) ^ _cr_rotr32(a, 22);
            int maj = (a & b) ^ (a & c) ^ (b & c);
            int temp2 = _cr_u32(S0 + maj);
            hh = g; g = f; f = e; e = _cr_u32(d + temp1);
            d = c; c = b; b = a; a = _cr_u32(temp1 + temp2);
        }

        h[0] = _cr_u32(h[0] + a); h[1] = _cr_u32(h[1] + b);
        h[2] = _cr_u32(h[2] + c); h[3] = _cr_u32(h[3] + d);
        h[4] = _cr_u32(h[4] + e); h[5] = _cr_u32(h[5] + f);
        h[6] = _cr_u32(h[6] + g); h[7] = _cr_u32(h[7] + hh);
    }

    for (int i = 0; i < 8; i = i + 1) {
        _cr_put(out32, i * 4, h[i] >> 24);
        _cr_put(out32, i * 4 + 1, h[i] >> 16);
        _cr_put(out32, i * 4 + 2, h[i] >> 8);
        _cr_put(out32, i * 4 + 3, h[i]);
    }
    free(msg);
}

fn _cr_sha256_k(int i) -> int {
    if (i < 16) {
        int t[16] = {1116352408, 1899447441, 3049323471, 3921009573,
                     961987163, 1508970993, 2453635748, 2870763221,
                     3624381080, 310598401, 607225278, 1426881987,
                     1925078388, 2162078206, 2614888103, 3248222580};
        return t[i];
    }
    if (i < 32) {
        int t[16] = {3835390401, 4022224774, 264347078, 604807628,
                     770255983, 1249150122, 1555081692, 1996064986,
                     2554220882, 2821834349, 2952996808, 3210313671,
                     3336571891, 3584528711, 113926993, 338241895};
        return t[i - 16];
    }
    if (i < 48) {
        int t[16] = {666307205, 773529912, 1294757372, 1396182291,
                     1695183700, 1986661051, 2177026350, 2456956037,
                     2730485921, 2820302411, 3259730800, 3345764771,
                     3516065817, 3600352804, 4094571909, 275423344};
        return t[i - 32];
    }
    int t[16] = {430227734, 506948616, 659060556, 883997877,
                 958139571, 1322822218, 1537002063, 1747873779,
                 1955562222, 2024104815, 2227730452, 2361852424,
                 2428436474, 2756734187, 3204031479, 3329325298};
    return t[i - 48];
}

fn crypto_sha256_hex(string text) -> string {
    if (text == null) { text = ""; }
    char* out = alloc<char>(32);
    crypto_sha256_raw(cast<char*>(text), len(text), out);
    string hex = crypto_hex_encode(out, 32);
    free(out);
    return hex;
}

fn crypto_sha256_bytes(char* data, int length) -> string {
    char* out = alloc<char>(32);
    crypto_sha256_raw(data, length, out);
    string hex = crypto_hex_encode(out, 32);
    free(out);
    return hex;
}

// -------------------------------------------------------------
// SHA-1
// -------------------------------------------------------------

fn crypto_sha1_raw(char* data, int length, char* out20) -> void {
    if (out20 == null) { return; }
    if (data == null) { length = 0; }
    int h0 = 1732584193;
    int h1 = 4023233417;
    int h2 = 2562383102;
    int h3 = 271733878;
    int h4 = 3285377520;

    int padded_len = ((length + 9 + 63) / 64) * 64;
    char* msg = alloc<char>(padded_len);
    _cr_zero(msg, padded_len);
    _cr_copy(msg, data, length);
    *(msg + length) = cast<char>(128);
    int bit_len = length * 8;
    for (int i = 0; i < 8; i = i + 1) {
        int shift = (7 - i) * 8;
        *(msg + padded_len - 8 + i) = cast<char>((bit_len >> shift) & 255);
    }

    int blocks = padded_len / 64;
    for (int block = 0; block < blocks; block = block + 1) {
        int w[80];
        int bv = block * 64;
        for (int i = 0; i < 16; i = i + 1) {
            int o = bv + i * 4;
            w[i] = (_cr_b(msg, o) << 24) | (_cr_b(msg, o + 1) << 16) |
                   (_cr_b(msg, o + 2) << 8) | _cr_b(msg, o + 3);
        }
        for (int i = 16; i < 80; i = i + 1) {
            int x = w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16];
            w[i] = _cr_rotl32(x, 1);
        }
        int a = h0;
        int b = h1;
        int c = h2;
        int d = h3;
        int e = h4;
        for (int i = 0; i < 80; i = i + 1) {
            int f = 0;
            int k = 0;
            if (i < 20) {
                f = (b & c) | ((~b) & d);
                k = 1518500249;
            } else if (i < 40) {
                f = b ^ c ^ d;
                k = 1859775393;
            } else if (i < 60) {
                f = (b & c) | (b & d) | (c & d);
                k = 2400959708;
            } else {
                f = b ^ c ^ d;
                k = 3395469782;
            }
            int temp = _cr_u32(_cr_rotl32(a, 5) + f + e + k + w[i]);
            e = d; d = c; c = _cr_rotl32(b, 30); b = a; a = temp;
        }
        h0 = _cr_u32(h0 + a); h1 = _cr_u32(h1 + b); h2 = _cr_u32(h2 + c);
        h3 = _cr_u32(h3 + d); h4 = _cr_u32(h4 + e);
    }

    int hs[5];
    hs[0] = h0; hs[1] = h1; hs[2] = h2; hs[3] = h3; hs[4] = h4;
    for (int i = 0; i < 5; i = i + 1) {
        _cr_put(out20, i * 4, hs[i] >> 24);
        _cr_put(out20, i * 4 + 1, hs[i] >> 16);
        _cr_put(out20, i * 4 + 2, hs[i] >> 8);
        _cr_put(out20, i * 4 + 3, hs[i]);
    }
    free(msg);
}

fn crypto_sha1_hex(string text) -> string {
    if (text == null) { text = ""; }
    char* out = alloc<char>(20);
    crypto_sha1_raw(cast<char*>(text), len(text), out);
    string hex = crypto_hex_encode(out, 20);
    free(out);
    return hex;
}

// -------------------------------------------------------------
// MD5
// -------------------------------------------------------------

fn crypto_md5_raw(char* data, int length, char* out16) -> void {
    if (out16 == null) { return; }
    if (data == null) { length = 0; }
    int a0 = 1732584193;
    int b0 = 4023233417;
    int c0 = 2562383102;
    int d0 = 271733878;

    int padded_len = ((length + 9 + 63) / 64) * 64;
    char* msg = alloc<char>(padded_len);
    _cr_zero(msg, padded_len);
    _cr_copy(msg, data, length);
    *(msg + length) = cast<char>(128);
    int bit_len = length * 8;
    for (int i = 0; i < 8; i = i + 1) {
        int shift = i * 8;
        *(msg + padded_len - 8 + i) = cast<char>((bit_len >> shift) & 255);
    }

    int shifts[64] = {7,12,17,22, 7,12,17,22, 7,12,17,22, 7,12,17,22,
                      5,9,14,20, 5,9,14,20, 5,9,14,20, 5,9,14,20,
                      4,11,16,23, 4,11,16,23, 4,11,16,23, 4,11,16,23,
                      6,10,15,21, 6,10,15,21, 6,10,15,21, 6,10,15,21};

    int blocks = padded_len / 64;
    for (int block = 0; block < blocks; block = block + 1) {
        int m[16];
        int bv = block * 64;
        for (int i = 0; i < 16; i = i + 1) {
            int o = bv + i * 4;
            m[i] = _cr_b(msg, o) | (_cr_b(msg, o + 1) << 8) |
                   (_cr_b(msg, o + 2) << 16) | (_cr_b(msg, o + 3) << 24);
        }
        int A = a0;
        int B = b0;
        int C = c0;
        int D = d0;
        for (int i = 0; i < 64; i = i + 1) {
            int f = 0;
            int g = 0;
            if (i < 16) {
                f = (B & C) | ((~B) & D);
                g = i;
            } else if (i < 32) {
                f = (D & B) | ((~D) & C);
                g = (5 * i + 1) % 16;
            } else if (i < 48) {
                f = B ^ C ^ D;
                g = (3 * i + 5) % 16;
            } else {
                f = C ^ (B | (~D));
                g = (7 * i) % 16;
            }
            int tmp = D;
            D = C;
            C = B;
            int sum = _cr_u32(A + f + _cr_md5_k(i) + m[g]);
            B = _cr_u32(B + _cr_rotl32(sum, shifts[i]));
            A = tmp;
        }
        a0 = _cr_u32(a0 + A); b0 = _cr_u32(b0 + B);
        c0 = _cr_u32(c0 + C); d0 = _cr_u32(d0 + D);
    }

    int hs[4];
    hs[0] = a0; hs[1] = b0; hs[2] = c0; hs[3] = d0;
    for (int i = 0; i < 4; i = i + 1) {
        _cr_put(out16, i * 4, hs[i]);
        _cr_put(out16, i * 4 + 1, hs[i] >> 8);
        _cr_put(out16, i * 4 + 2, hs[i] >> 16);
        _cr_put(out16, i * 4 + 3, hs[i] >> 24);
    }
    free(msg);
}

fn _cr_md5_k(int i) -> int {
    if (i < 16) {
        int t[16] = {3614090360, 3905402710, 606105819, 3250441966,
                     4118548399, 1200080426, 2821735955, 4249261313,
                     1770035416, 2336552879, 4294925233, 2304563134,
                     1804603682, 4254626195, 2792965006, 1236535329};
        return t[i];
    }
    if (i < 32) {
        int t[16] = {4129170786, 3225465664, 643717713, 3921069994,
                     3593408605, 38016083, 3634488961, 3889429448,
                     568446438, 3275163606, 4107603335, 1163531501,
                     2850285829, 4243563512, 1735328473, 2368359562};
        return t[i - 16];
    }
    if (i < 48) {
        int t[16] = {4294588738, 2272392833, 1839030562, 4259657740,
                     2763975236, 1272893353, 4139469664, 3200236656,
                     681279174, 3936430074, 3572445317, 76029189,
                     3654602809, 3873151461, 530742520, 3299628645};
        return t[i - 32];
    }
    int t[16] = {4096336452, 1126891415, 2878612391, 4237533241,
                 1700485571, 2399980690, 4293915773, 2240044497,
                 1873313359, 4264355552, 2734768916, 1309151649,
                 4149444226, 3174756917, 718787259, 3951481745};
    return t[i - 48];
}

fn crypto_md5_hex(string text) -> string {
    if (text == null) { text = ""; }
    char* out = alloc<char>(16);
    crypto_md5_raw(cast<char*>(text), len(text), out);
    string hex = crypto_hex_encode(out, 16);
    free(out);
    return hex;
}

// -------------------------------------------------------------
// HMAC-SHA256 / PBKDF2
// -------------------------------------------------------------

fn crypto_hmac_sha256_raw(string key, char* message, int message_len, char* out32) -> void {
    if (out32 == null) { return; }
    if (message == null) { message_len = 0; }
    char* kp = cast<char*>(key);
    int klen = len(key);
    char* normalized = alloc<char>(64);
    _cr_zero(normalized, 64);
    if (klen > 64) {
        crypto_sha256_raw(kp, klen, normalized);
    } else {
        _cr_copy(normalized, kp, klen);
    }

    char* inner = alloc<char>(64 + message_len);
    char* outer = alloc<char>(64 + 32);
    for (int i = 0; i < 64; i = i + 1) {
        int k = _cr_b(normalized, i);
        _cr_put(inner, i, k ^ 54);
        _cr_put(outer, i, k ^ 92);
    }
    if (message_len > 0) {
        _cr_copy(inner + 64, message, message_len);
    }
    char* inner_hash = alloc<char>(32);
    crypto_sha256_raw(inner, 64 + message_len, inner_hash);
    _cr_copy(outer + 64, inner_hash, 32);
    crypto_sha256_raw(outer, 96, out32);

    free(normalized);
    free(inner);
    free(outer);
    free(inner_hash);
}

fn crypto_hmac_sha256_hex(string key, string message) -> string {
    char* out = alloc<char>(32);
    crypto_hmac_sha256_raw(key, cast<char*>(message), len(message), out);
    string hex = crypto_hex_encode(out, 32);
    free(out);
    return hex;
}

fn crypto_pbkdf2_sha256_raw(string password, string salt, int iterations, char* out, int out_len) -> int {
    if (out == null || out_len <= 0) { return 0; }
    if (iterations < 1) { iterations = 1; }
    int generated = 0;
    int block_index = 1;
    while (generated < out_len) {
        char* salt_block = alloc<char>(len(salt) + 4);
        _cr_copy(salt_block, cast<char*>(salt), len(salt));
        _cr_put(salt_block, len(salt), block_index >> 24);
        _cr_put(salt_block, len(salt) + 1, block_index >> 16);
        _cr_put(salt_block, len(salt) + 2, block_index >> 8);
        _cr_put(salt_block, len(salt) + 3, block_index);

        char* u = alloc<char>(32);
        char* t = alloc<char>(32);
        crypto_hmac_sha256_raw(password, salt_block, len(salt) + 4, u);
        _cr_copy(t, u, 32);
        for (int j = 1; j < iterations; j = j + 1) {
            crypto_hmac_sha256_raw(password, u, 32, u);
            for (int k = 0; k < 32; k = k + 1) {
                _cr_put(t, k, _cr_b(t, k) ^ _cr_b(u, k));
            }
        }
        int take = _cr_min(32, out_len - generated);
        _cr_copy(out + generated, t, take);
        generated = generated + take;
        block_index = block_index + 1;
        free(salt_block);
        free(u);
        free(t);
    }
    return generated;
}

fn crypto_pbkdf2_sha256_hex(string password, string salt, int iterations, int key_len) -> string {
    if (key_len <= 0) { return ""; }
    char* out = alloc<char>(key_len);
    crypto_pbkdf2_sha256_raw(password, salt, iterations, out, key_len);
    string hex = crypto_hex_encode(out, key_len);
    free(out);
    return hex;
}

// -------------------------------------------------------------
// AES core
// -------------------------------------------------------------

fn _cr_aes_gmul(int a, int b) -> int {
    int p = 0;
    int x = a & 255;
    int y = b & 255;
    for (int i = 0; i < 8; i = i + 1) {
        if ((y & 1) != 0) { p = p ^ x; }
        bool hi = (x & 128) != 0;
        x = (x << 1) & 255;
        if (hi) { x = x ^ 27; }
        y = y >> 1;
    }
    return p & 255;
}

fn _cr_aes_gpow(int a, int power) -> int {
    int result = 1;
    int bv = a & 255;
    int e = power;
    while (e > 0) {
        if ((e & 1) != 0) { result = _cr_aes_gmul(result, bv); }
        bv = _cr_aes_gmul(bv, bv);
        e = e >> 1;
    }
    return result;
}

fn _cr_aes_sbox_byte(int x) -> int {
    int inv = 0;
    if ((x & 255) != 0) { inv = _cr_aes_gpow(x & 255, 254); }
    int r = inv;
    for (int i = 1; i <= 4; i = i + 1) {
        int rot = ((inv << i) | (inv >> (8 - i))) & 255;
        r = r ^ rot;
    }
    return r ^ 99;
}

fn _cr_aes_make_tables(char* sbox, char* inv_sbox) -> void {
    for (int x = 0; x < 256; x = x + 1) {
        int s = _cr_aes_sbox_byte(x);
        _cr_put(sbox, x, s);
        _cr_put(inv_sbox, s, x);
    }
}

fn _cr_aes_expand_key(char* key, int key_len, char* round_keys) -> int {
    int nk = key_len / 4;
    int nr = nk + 6;
    int total_words = 4 * (nr + 1);
    for (int i = 0; i < key_len; i = i + 1) {
        _cr_put(round_keys, i, _cr_b(key, i));
    }
    int rcon = 1;
    for (int i = nk; i < total_words; i = i + 1) {
        int t0 = _cr_b(round_keys, (i - 1) * 4);
        int t1 = _cr_b(round_keys, (i - 1) * 4 + 1);
        int t2 = _cr_b(round_keys, (i - 1) * 4 + 2);
        int t3 = _cr_b(round_keys, (i - 1) * 4 + 3);
        if ((i % nk) == 0) {
            int tmp = t0;
            t0 = _cr_aes_sbox_byte(t1) ^ rcon;
            t1 = _cr_aes_sbox_byte(t2);
            t2 = _cr_aes_sbox_byte(t3);
            t3 = _cr_aes_sbox_byte(tmp);
            rcon = _cr_aes_gmul(rcon, 2);
        } else if (nk > 6 && (i % nk) == 4) {
            t0 = _cr_aes_sbox_byte(t0);
            t1 = _cr_aes_sbox_byte(t1);
            t2 = _cr_aes_sbox_byte(t2);
            t3 = _cr_aes_sbox_byte(t3);
        }
        int bv = (i - nk) * 4;
        _cr_put(round_keys, i * 4, _cr_b(round_keys, bv) ^ t0);
        _cr_put(round_keys, i * 4 + 1, _cr_b(round_keys, bv + 1) ^ t1);
        _cr_put(round_keys, i * 4 + 2, _cr_b(round_keys, bv + 2) ^ t2);
        _cr_put(round_keys, i * 4 + 3, _cr_b(round_keys, bv + 3) ^ t3);
    }
    return nr;
}

fn _cr_aes_add_round_key(char* state, char* round_keys, int round) -> void {
    int off = round * 16;
    for (int i = 0; i < 16; i = i + 1) {
        _cr_put(state, i, _cr_b(state, i) ^ _cr_b(round_keys, off + i));
    }
}

fn _cr_aes_sub_bytes(char* state, char* sbox) -> void {
    for (int i = 0; i < 16; i = i + 1) {
        _cr_put(state, i, _cr_b(sbox, _cr_b(state, i)));
    }
}

fn _cr_aes_inv_sub_bytes(char* state, char* inv_sbox) -> void {
    for (int i = 0; i < 16; i = i + 1) {
        _cr_put(state, i, _cr_b(inv_sbox, _cr_b(state, i)));
    }
}

fn _cr_aes_shift_rows(char* state) -> void {
    char* tmp = alloc<char>(16);
    for (int i = 0; i < 16; i = i + 1) { tmp[i] = *(state + i); }
    for (int row = 0; row < 4; row = row + 1) {
        for (int col = 0; col < 4; col = col + 1) {
            int src = row + 4 * ((col + row) % 4);
            _cr_put(state, row + 4 * col, cast<int>(tmp[src]) & 255);
        }
    }
    free(tmp);
}

fn _cr_aes_inv_shift_rows(char* state) -> void {
    char* tmp = alloc<char>(16);
    for (int i = 0; i < 16; i = i + 1) { tmp[i] = *(state + i); }
    for (int row = 0; row < 4; row = row + 1) {
        for (int col = 0; col < 4; col = col + 1) {
            int src = row + 4 * ((col - row + 4) % 4);
            _cr_put(state, row + 4 * col, cast<int>(tmp[src]) & 255);
        }
    }
    free(tmp);
}

fn _cr_aes_mix_columns(char* state) -> void {
    for (int c = 0; c < 4; c = c + 1) {
        int a0 = _cr_b(state, c * 4);
        int a1 = _cr_b(state, c * 4 + 1);
        int a2 = _cr_b(state, c * 4 + 2);
        int a3 = _cr_b(state, c * 4 + 3);
        int b0 = _cr_aes_gmul(a0, 2) ^ _cr_aes_gmul(a1, 3) ^ a2 ^ a3;
        int b1 = a0 ^ _cr_aes_gmul(a1, 2) ^ _cr_aes_gmul(a2, 3) ^ a3;
        int b2 = a0 ^ a1 ^ _cr_aes_gmul(a2, 2) ^ _cr_aes_gmul(a3, 3);
        int b3 = _cr_aes_gmul(a0, 3) ^ a1 ^ a2 ^ _cr_aes_gmul(a3, 2);
        _cr_put(state, c * 4, b0);
        _cr_put(state, c * 4 + 1, b1);
        _cr_put(state, c * 4 + 2, b2);
        _cr_put(state, c * 4 + 3, b3);
    }
}

fn _cr_aes_inv_mix_columns(char* state) -> void {
    for (int c = 0; c < 4; c = c + 1) {
        int a0 = _cr_b(state, c * 4);
        int a1 = _cr_b(state, c * 4 + 1);
        int a2 = _cr_b(state, c * 4 + 2);
        int a3 = _cr_b(state, c * 4 + 3);
        int b0 = _cr_aes_gmul(a0, 14) ^ _cr_aes_gmul(a1, 11) ^ _cr_aes_gmul(a2, 13) ^ _cr_aes_gmul(a3, 9);
        int b1 = _cr_aes_gmul(a0, 9) ^ _cr_aes_gmul(a1, 14) ^ _cr_aes_gmul(a2, 11) ^ _cr_aes_gmul(a3, 13);
        int b2 = _cr_aes_gmul(a0, 13) ^ _cr_aes_gmul(a1, 9) ^ _cr_aes_gmul(a2, 14) ^ _cr_aes_gmul(a3, 11);
        int b3 = _cr_aes_gmul(a0, 11) ^ _cr_aes_gmul(a1, 13) ^ _cr_aes_gmul(a2, 9) ^ _cr_aes_gmul(a3, 14);
        _cr_put(state, c * 4, b0);
        _cr_put(state, c * 4 + 1, b1);
        _cr_put(state, c * 4 + 2, b2);
        _cr_put(state, c * 4 + 3, b3);
    }
}

fn crypto_aes_block_encrypt(char* block_in, char* block_out, char* key, int key_len) -> void {
    int nr = key_len / 4 + 6;
    char* rk = alloc<char>(16 * (nr + 1));
    char* sbox = alloc<char>(256);
    char* inv_sbox = alloc<char>(256);
    _cr_aes_make_tables(sbox, inv_sbox);
    _cr_aes_expand_key(key, key_len, rk);

    char* state = alloc<char>(16);
    for (int i = 0; i < 16; i = i + 1) { state[i] = *(block_in + i); }
    _cr_aes_add_round_key(state, rk, 0);
    for (int round = 1; round < nr; round = round + 1) {
        _cr_aes_sub_bytes(state, sbox);
        _cr_aes_shift_rows(state);
        _cr_aes_mix_columns(state);
        _cr_aes_add_round_key(state, rk, round);
    }
    _cr_aes_sub_bytes(state, sbox);
    _cr_aes_shift_rows(state);
    _cr_aes_add_round_key(state, rk, nr);
    for (int i = 0; i < 16; i = i + 1) { *(block_out + i) = state[i]; }

    free(state);
    free(rk);
    free(sbox);
    free(inv_sbox);
}

fn crypto_aes_block_decrypt(char* block_in, char* block_out, char* key, int key_len) -> void {
    int nr = key_len / 4 + 6;
    char* rk = alloc<char>(16 * (nr + 1));
    char* sbox = alloc<char>(256);
    char* inv_sbox = alloc<char>(256);
    _cr_aes_make_tables(sbox, inv_sbox);
    _cr_aes_expand_key(key, key_len, rk);

    char* state = alloc<char>(16);
    for (int i = 0; i < 16; i = i + 1) { state[i] = *(block_in + i); }
    _cr_aes_add_round_key(state, rk, nr);
    for (int round = nr - 1; round >= 1; round = round - 1) {
        _cr_aes_inv_shift_rows(state);
        _cr_aes_inv_sub_bytes(state, inv_sbox);
        _cr_aes_add_round_key(state, rk, round);
        _cr_aes_inv_mix_columns(state);
    }
    _cr_aes_inv_shift_rows(state);
    _cr_aes_inv_sub_bytes(state, inv_sbox);
    _cr_aes_add_round_key(state, rk, 0);
    for (int i = 0; i < 16; i = i + 1) { *(block_out + i) = state[i]; }

    free(state);
    free(rk);
    free(sbox);
    free(inv_sbox);
}

fn crypto_aes_ecb_encrypt_raw(char* input, int length, char* key, int key_len, char* out) -> int {
    if (input == null || out == null || key == null) { return 0; }
    if (key_len != 16 && key_len != 24 && key_len != 32) { return 0; }
    int blocks = length / 16;
    for (int b = 0; b < blocks; b = b + 1) {
        crypto_aes_block_encrypt(input + b * 16, out + b * 16, key, key_len);
    }
    return blocks * 16;
}

fn crypto_aes_ecb_decrypt_raw(char* input, int length, char* key, int key_len, char* out) -> int {
    if (input == null || out == null || key == null) { return 0; }
    if (key_len != 16 && key_len != 24 && key_len != 32) { return 0; }
    int blocks = length / 16;
    for (int b = 0; b < blocks; b = b + 1) {
        crypto_aes_block_decrypt(input + b * 16, out + b * 16, key, key_len);
    }
    return blocks * 16;
}

fn crypto_aes_cbc_encrypt_raw(char* input, int length, char* key, int key_len, char* iv, char* out) -> int {
    if (input == null || out == null || key == null || iv == null) { return 0; }
    if (key_len != 16 && key_len != 24 && key_len != 32) { return 0; }
    int padded = ((length / 16) + 1) * 16;
    int pad = padded - length;
    char* buf = alloc<char>(padded);
    _cr_copy(buf, input, length);
    for (int i = 0; i < pad; i = i + 1) { _cr_put(buf, length + i, pad); }

    char* prev = alloc<char>(16);
    for (int i = 0; i < 16; i = i + 1) { prev[i] = *(iv + i); }
    char* xored = alloc<char>(16);
    int blocks = padded / 16;
    for (int b = 0; b < blocks; b = b + 1) {
        for (int i = 0; i < 16; i = i + 1) {
            xored[i] = cast<char>(_cr_b(buf, b * 16 + i) ^ (cast<int>(prev[i]) & 255));
        }
        crypto_aes_block_encrypt(xored, out + b * 16, key, key_len);
        for (int i = 0; i < 16; i = i + 1) { prev[i] = *(out + b * 16 + i); }
    }
    free(buf);
    free(prev);
    free(xored);
    return padded;
}

fn crypto_aes_cbc_decrypt_raw(char* input, int length, char* key, int key_len, char* iv, char* out) -> int {
    if (input == null || out == null || key == null || iv == null) { return 0; }
    if (key_len != 16 && key_len != 24 && key_len != 32) { return 0; }
    if ((length % 16) != 0 || length <= 0) { return 0; }
    char* prev = alloc<char>(16);
    for (int i = 0; i < 16; i = i + 1) { prev[i] = *(iv + i); }
    char* decrypted = alloc<char>(16);
    int blocks = length / 16;
    for (int b = 0; b < blocks; b = b + 1) {
        crypto_aes_block_decrypt(input + b * 16, decrypted, key, key_len);
        for (int i = 0; i < 16; i = i + 1) {
            _cr_put(out, b * 16 + i, (cast<int>(decrypted[i]) & 255) ^ (cast<int>(prev[i]) & 255));
        }
        for (int i = 0; i < 16; i = i + 1) { prev[i] = *(input + b * 16 + i); }
    }
    int pad = _cr_b(out, length - 1);
    if (pad < 1 || pad > 16) { free(prev); free(decrypted); return length; }
    for (int i = 0; i < pad; i = i + 1) {
        if (_cr_b(out, length - 1 - i) != pad) { free(prev); free(decrypted); return length; }
    }
    free(prev);
    free(decrypted);
    return length - pad;
}

fn crypto_aes_ctr_xor_raw(char* input, int length, char* key, int key_len, char* iv, int counter, char* out) -> int {
    if (input == null || out == null || key == null || iv == null) { return 0; }
    if (key_len != 16 && key_len != 24 && key_len != 32) { return 0; }
    char* counter_block = alloc<char>(16);
    for (int i = 0; i < 16; i = i + 1) { counter_block[i] = *(iv + i); }
    // The last 4 bytes hold the block counter (big-endian).
    _cr_put(counter_block, 12, counter >> 24);
    _cr_put(counter_block, 13, counter >> 16);
    _cr_put(counter_block, 14, counter >> 8);
    _cr_put(counter_block, 15, counter);
    char* stream = alloc<char>(16);
    int done = 0;
    while (done < length) {
        crypto_aes_block_encrypt(counter_block, stream, key, key_len);
        int chunk = _cr_min(16, length - done);
        for (int i = 0; i < chunk; i = i + 1) {
            _cr_put(out, done + i, _cr_b(input, done + i) ^ (cast<int>(stream[i]) & 255));
        }
        done = done + chunk;
        // Increment 32-bit counter.
        int cn = ((_cr_b(counter_block, 12) << 24) | (_cr_b(counter_block, 13) << 16) |
                  (_cr_b(counter_block, 14) << 8) | _cr_b(counter_block, 15)) + 1;
        _cr_put(counter_block, 12, cn >> 24);
        _cr_put(counter_block, 13, cn >> 16);
        _cr_put(counter_block, 14, cn >> 8);
        _cr_put(counter_block, 15, cn);
    }
    free(counter_block);
    free(stream);
    return done;
}

// Hex-friendly AES wrappers
fn crypto_aes_ecb_encrypt_hex(string plaintext, string key_hex) -> string {
    int key_len = 0;
    char* key = crypto_hex_decode(key_hex, &key_len);
    if (key == null) { return ""; }
    int len = len(plaintext);
    int padded = ((len / 16) + 1) * 16;
    char* padded_buf = alloc<char>(padded);
    _cr_copy(padded_buf, cast<char*>(plaintext), len);
    int pad = padded - len;
    for (int i = 0; i < pad; i = i + 1) { _cr_put(padded_buf, len + i, pad); }
    char* out = alloc<char>(padded);
    int out_len = crypto_aes_ecb_encrypt_raw(padded_buf, padded, key, key_len, out);
    string hex = crypto_hex_encode(out, out_len);
    free(key); free(padded_buf); free(out);
    return hex;
}

fn crypto_aes_cbc_encrypt_hex(string plaintext, string key_hex, string iv_hex) -> string {
    int key_len = 0;
    int iv_len = 0;
    char* key = crypto_hex_decode(key_hex, &key_len);
    char* iv = crypto_hex_decode(iv_hex, &iv_len);
    if (key == null || iv == null || iv_len != 16) { return ""; }
    int len = len(plaintext);
    int padded = ((len / 16) + 1) * 16;
    char* out = alloc<char>(padded);
    int out_len = crypto_aes_cbc_encrypt_raw(cast<char*>(plaintext), len, key, key_len, iv, out);
    string hex = crypto_hex_encode(out, out_len);
    free(key); free(iv); free(out);
    return hex;
}

fn crypto_aes_cbc_decrypt_hex(string cipher_hex, string key_hex, string iv_hex) -> string {
    int key_len = 0;
    int iv_len = 0;
    int data_len = 0;
    char* key = crypto_hex_decode(key_hex, &key_len);
    char* iv = crypto_hex_decode(iv_hex, &iv_len);
    char* data = crypto_hex_decode(cipher_hex, &data_len);
    if (key == null || iv == null || data == null || iv_len != 16) { return ""; }
    char* out = alloc<char>(data_len + 1);
    int out_len = crypto_aes_cbc_decrypt_raw(data, data_len, key, key_len, iv, out);
    *(out + out_len) = 0;
    string text = cast<string>(out);
    free(key); free(iv); free(data); free(out);
    return text;
}

fn crypto_aes_ctr_xor_hex(string data_hex, string key_hex, string iv_hex, int counter) -> string {
    int key_len = 0;
    int iv_len = 0;
    int data_len = 0;
    char* key = crypto_hex_decode(key_hex, &key_len);
    char* iv = crypto_hex_decode(iv_hex, &iv_len);
    char* data = crypto_hex_decode(data_hex, &data_len);
    if (key == null || iv == null || data == null || iv_len != 16) { return ""; }
    char* out = alloc<char>(data_len + 1);
    int out_len = crypto_aes_ctr_xor_raw(data, data_len, key, key_len, iv, counter, out);
    string hex = crypto_hex_encode(out, out_len);
    free(key); free(iv); free(data); free(out);
    return hex;
}

// -------------------------------------------------------------
// ChaCha20
// -------------------------------------------------------------

fn _cr_add32(int a, int b) -> int {
    return _cr_u32(a + b);
}

fn _cr_chacha_qr(int* x, int a, int b, int c, int d) -> void {
    x[a] = _cr_add32(x[a], x[b]); x[d] = _cr_rotl32(x[d] ^ x[a], 16);
    x[c] = _cr_add32(x[c], x[d]); x[b] = _cr_rotl32(x[b] ^ x[c], 12);
    x[a] = _cr_add32(x[a], x[b]); x[d] = _cr_rotl32(x[d] ^ x[a], 8);
    x[c] = _cr_add32(x[c], x[d]); x[b] = _cr_rotl32(x[b] ^ x[c], 7);
}

fn _cr_le32(char* p, int off) -> int {
    return _cr_b(p, off) | (_cr_b(p, off + 1) << 8) |
           (_cr_b(p, off + 2) << 16) | (_cr_b(p, off + 3) << 24);
}

fn _cr_put_le32(char* p, int off, int value) -> void {
    _cr_put(p, off, value);
    _cr_put(p, off + 1, value >> 8);
    _cr_put(p, off + 2, value >> 16);
    _cr_put(p, off + 3, value >> 24);
}

fn _cr_chacha_block(char* key32, char* nonce12, int counter, char* out64) -> void {
    int initial[16];
    initial[0] = 1634760805; initial[1] = 857760878;
    initial[2] = 2036477234; initial[3] = 1797285236;
    for (int i = 0; i < 8; i = i + 1) {
        initial[4 + i] = _cr_le32(key32, i * 4);
    }
    initial[12] = counter;
    initial[13] = _cr_le32(nonce12, 0);
    initial[14] = _cr_le32(nonce12, 4);
    initial[15] = _cr_le32(nonce12, 8);

    int x[16];
    for (int i = 0; i < 16; i = i + 1) { x[i] = initial[i]; }
    for (int round = 0; round < 10; round = round + 1) {
        _cr_chacha_qr(x, 0, 4, 8, 12);
        _cr_chacha_qr(x, 1, 5, 9, 13);
        _cr_chacha_qr(x, 2, 6, 10, 14);
        _cr_chacha_qr(x, 3, 7, 11, 15);
        _cr_chacha_qr(x, 0, 5, 10, 15);
        _cr_chacha_qr(x, 1, 6, 11, 12);
        _cr_chacha_qr(x, 2, 7, 8, 13);
        _cr_chacha_qr(x, 3, 4, 9, 14);
    }
    for (int i = 0; i < 16; i = i + 1) {
        _cr_put_le32(out64, i * 4, _cr_add32(x[i], initial[i]));
    }
}

fn crypto_chacha20_xor_raw(char* input, int length, char* key32, char* nonce12, int counter, char* out) -> int {
    if (input == null || out == null || key32 == null || nonce12 == null) { return 0; }
    char* block = alloc<char>(64);
    int done = 0;
    int ctr = counter;
    while (done < length) {
        _cr_chacha_block(key32, nonce12, ctr, block);
        int chunk = _cr_min(64, length - done);
        for (int i = 0; i < chunk; i = i + 1) {
            _cr_put(out, done + i, _cr_b(input, done + i) ^ (cast<int>(block[i]) & 255));
        }
        done = done + chunk;
        ctr = ctr + 1;
    }
    free(block);
    return done;
}

fn crypto_chacha20_xor_hex(string data_hex, string key_hex, string nonce_hex, int counter) -> string {
    int key_len = 0;
    int nonce_len = 0;
    int data_len = 0;
    char* key = crypto_hex_decode(key_hex, &key_len);
    char* nonce = crypto_hex_decode(nonce_hex, &nonce_len);
    char* data = crypto_hex_decode(data_hex, &data_len);
    if (key == null || nonce == null || data == null || key_len != 32 || nonce_len != 12) {
        return "";
    }
    char* out = alloc<char>(data_len + 1);
    int out_len = crypto_chacha20_xor_raw(data, data_len, key, nonce, counter, out);
    string hex = crypto_hex_encode(out, out_len);
    free(key); free(nonce); free(data); free(out);
    return hex;
}
