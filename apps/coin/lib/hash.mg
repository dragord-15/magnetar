// Magnetar Coin — hashing primitives.
// SHA-256 comes from the root library; SHA-256d and Merkle are MGC-specific.

use "../../lib/crypto.mg";
use "util.mg";
use "ripemd160.mg";

fn mgc_sha256d_raw(char* data, int length, char* out32) -> void {
    if (out32 == null) { return; }
    if (data == null) { length = 0; }

    char* first = alloc<char>(32);
    if (first == null) {
        mgc_zero(out32, 32);
        return;
    }
    crypto_sha256_raw(data, length, first);
    crypto_sha256_raw(first, 32, out32);
    free(first);
}

fn mgc_sha256d_hex(char* data, int length) -> string {
    char* out = alloc<char>(32);
    if (out == null) { return ""; }
    mgc_sha256d_raw(data, length, out);
    string hex = crypto_hex_encode(out, 32);
    free(out);
    return hex;
}

fn mgc_sha256d_str(string text) -> string {
    if (text == null) { return mgc_sha256d_hex(null, 0); }
    return mgc_sha256d_hex(cast<char*>(text), len(text));
}

// `hashes` is a contiguous array of `count` 32-byte hashes.
// Odd nodes are duplicated at each level, as in Bitcoin.
fn mgc_merkle_root(char* hashes, int count, char* out32) -> bool {
    if (out32 == null) { return false; }
    mgc_zero(out32, 32);
    if (hashes == null || count <= 0) { return false; }

    int capacity = count * 32;
    char* current = alloc<char>(capacity);
    char* next = alloc<char>(capacity);
    if (current == null || next == null) {
        if (current != null) { free(current); }
        if (next != null) { free(next); }
        return false;
    }

    mgc_copy(current, hashes, capacity);
    int level_count = count;

    while (level_count > 1) {
        int next_count = (level_count + 1) / 2;
        char* pair = alloc<char>(64);
        if (pair == null) {
            free(current);
            free(next);
            mgc_zero(out32, 32);
            return false;
        }
        for (int i = 0; i < next_count; i = i + 1) {
            int left_index = i * 2;
            int right_index = i * 2 + 1;
            if (right_index >= level_count) {
                right_index = left_index;
            }

            mgc_copy(pair, current + left_index * 32, 32);
            mgc_copy(pair + 32, current + right_index * 32, 32);
            mgc_sha256d_raw(pair, 64, next + i * 32);
        }
        free(pair);

        char* swap = current;
        current = next;
        next = swap;
        level_count = next_count;
    }

    mgc_copy(out32, current, 32);
    free(current);
    free(next);
    return true;
}

fn mgc_merkle_root_hex(char* hashes, int count) -> string {
    char* out = alloc<char>(32);
    if (out == null) { return ""; }
    if (!mgc_merkle_root(hashes, count, out)) {
        free(out);
        return "";
    }
    string hex = crypto_hex_encode(out, 32);
    free(out);
    return hex;
}

// HASH160 = RIPEMD160(SHA256(data))
fn mgc_hash160(char* data, int length, char* out20) -> void {
    if (out20 == null) { return; }
    mgc_zero(out20, 20);
    char* sha = alloc<char>(32);
    if (sha == null) { return; }
    crypto_sha256_raw(data, length, sha);
    ripemd160_raw(sha, 32, out20);
    free(sha);
}

fn mgc_hash160_hex(char* data, int length) -> string {
    char* out = alloc<char>(20);
    if (out == null) { return ""; }
    mgc_hash160(data, length, out);
    string hex = crypto_hex_encode(out, 20);
    free(out);
    return hex;
}
