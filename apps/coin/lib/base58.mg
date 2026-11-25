use "hash.mg";
use "util.mg";

// Base58 encoding/decoding and Base58Check (Bitcoin-style).
// Uses big-integer arithmetic in base 256 via byte arrays.

fn _b58_index(int c) -> int {
    if (c >= 49 && c <= 57) { return c - 49; }           // 1-9
    if (c >= 65 && c <= 72) { return c - 65 + 9; }       // A-H
    if (c >= 74 && c <= 78) { return c - 74 + 17; }      // J-N
    if (c >= 80 && c <= 90) { return c - 80 + 22; }      // P-Z
    if (c >= 97 && c <= 107) { return c - 97 + 33; }     // a-k
    if (c >= 109 && c <= 122) { return c - 109 + 44; }   // m-z
    return -1;
}

fn _b58_char(int v) -> char {
    string alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
    if (v < 0 || v > 57) { return cast<char>(49); }
    return *(cast<char*>(alphabet) + v);
}

fn base58_encode(char* data, int length) -> string {
    if (data == null || length <= 0) { return ""; }

    int zeros = 0;
    while (zeros < length && cast<int>(*(data + zeros)) == 0) {
        zeros = zeros + 1;
    }

    int size = length * 138 / 100 + 1;
    char* b58 = alloc<char>(size);
    if (b58 == null) { return ""; }
    mgc_zero(b58, size);

    int b58_len = 0;
    for (int i = zeros; i < length; i = i + 1) {
        int carry = cast<int>(*(data + i)) & 255;
        int j = 0;
        while (j < b58_len || carry != 0) {
            int idx = size - 1 - j;
            carry = carry + 256 * (cast<int>(*(b58 + idx)) & 255);
            *(b58 + idx) = cast<char>(carry % 58);
            carry = carry / 58;
            j = j + 1;
        }
        b58_len = j;
    }

    int start = size - b58_len;
    int total = zeros + b58_len;
    char* out = alloc<char>(total + 1);
    if (out == null) { free(b58); return ""; }

    for (int i = 0; i < zeros; i = i + 1) {
        *(out + i) = cast<char>(49); // '1'
    }
    for (int i = 0; i < b58_len; i = i + 1) {
        *(out + zeros + i) = _b58_char(cast<int>(*(b58 + start + i)) & 255);
    }
    *(out + total) = cast<char>(0);

    free(b58);
    return cast<string>(out);
}

fn base58_decode(string text, int* out_len) -> char* {
    if (out_len != null) { *out_len = 0; }
    if (text == null) { return null; }
    int n = len(text);
    if (n <= 0) { return null; }

    int zeros = 0;
    char* p = cast<char*>(text);
    while (zeros < n && *(p + zeros) == cast<char>(49)) {
        zeros = zeros + 1;
    }

    int size = n * 733 / 1000 + 1;
    char* b256 = alloc<char>(size);
    if (b256 == null) { return null; }
    mgc_zero(b256, size);

    int b256_len = 0;
    for (int i = zeros; i < n; i = i + 1) {
        int val = _b58_index(cast<int>(*(p + i)) & 255);
        if (val < 0) { free(b256); return null; }
        int carry = val;
        int j = 0;
        while (j < b256_len || carry != 0) {
            int idx = size - 1 - j;
            carry = carry + 58 * (cast<int>(*(b256 + idx)) & 255);
            *(b256 + idx) = cast<char>(carry % 256);
            carry = carry / 256;
            j = j + 1;
        }
        b256_len = j;
    }

    int start = size - b256_len;
    int total = zeros + b256_len;
    char* out = alloc<char>(total);
    if (out == null) { free(b256); return null; }
    mgc_zero(out, zeros);
    mgc_copy(out + zeros, b256 + start, b256_len);

    if (out_len != null) { *out_len = total; }
    free(b256);
    return out;
}

fn base58check_encode(char* data, int length) -> string {
    if (data == null || length <= 0) { return ""; }
    char* hash = alloc<char>(32);
    char* payload = alloc<char>(length + 4);
    if (hash == null || payload == null) {
        if (hash != null) { free(hash); }
        if (payload != null) { free(payload); }
        return "";
    }
    mgc_copy(payload, data, length);
    mgc_sha256d_raw(data, length, hash);
    mgc_copy(payload + length, hash, 4);
    string out = base58_encode(payload, length + 4);
    free(hash);
    free(payload);
    return out;
}

fn base58check_decode(string text, int* out_len) -> char* {
    if (out_len != null) { *out_len = 0; }
    int full_len = 0;
    char* full = base58_decode(text, &full_len);
    if (full == null || full_len < 5) {
        if (full != null) { free(full); }
        return null;
    }

    int data_len = full_len - 4;
    char* hash = alloc<char>(32);
    if (hash == null) { free(full); return null; }
    mgc_sha256d_raw(full, data_len, hash);

    bool ok = mgc_equal(hash, full + data_len, 4);
    free(hash);
    if (!ok) {
        free(full);
        return null;
    }

    char* out = alloc<char>(data_len);
    if (out == null) { free(full); return null; }
    mgc_copy(out, full, data_len);
    if (out_len != null) { *out_len = data_len; }
    free(full);
    return out;
}
