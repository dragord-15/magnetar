// Magnetar Coin — 256-bit unsigned big integers.
// Representation: 16 limbs, bs 2^16, little-endian.
// IMPORTANT: pointer arithmetic on `int*` is byte-based in Magnetar v3.5.
// Always index limbs with `a[i]`, never `*(a + i)`.

use "util.mg";

const int MGC_BIG_LIMBS = 16;
const int MGC_BIG_WIDE  = 32;

fn mgc_big_zero(int* a) -> void {
    if (a == null) { return; }
    for (int i = 0; i < 16; i = i + 1) { a[i] = 0; }
}

fn mgc_big_copy(int* dst, int* src) -> void {
    if (dst == null || src == null) { return; }
    for (int i = 0; i < 16; i = i + 1) { dst[i] = src[i] & 65535; }
}

fn mgc_big_is_zero(int* a) -> bool {
    if (a == null) { return true; }
    for (int i = 0; i < 16; i = i + 1) {
        if ((a[i] & 65535) != 0) { return false; }
    }
    return true;
}

fn mgc_big_cmp(int* a, int* b) -> int {
    if (a == null && b == null) { return 0; }
    if (a == null) { return -1; }
    if (b == null) { return 1; }
    for (int i = 15; i >= 0; i = i - 1) {
        int av = a[i] & 65535;
        int bv = b[i] & 65535;
        if (av < bv) { return -1; }
        if (av > bv) { return 1; }
    }
    return 0;
}

fn mgc_big_set_u64(int* a, int v) -> void {
    if (a == null) { return; }
    mgc_big_zero(a);
    int x = v;
    for (int i = 0; i < 4; i = i + 1) {
        a[i] = x & 65535;
        x = x >> 16;
    }
}

fn mgc_big_set_u32(int* a, int v) -> void {
    mgc_big_set_u64(a, v & 4294967295);
}

fn mgc_big_mul_small_add(int* a, int mul, int add) -> void {
    int carry = add;
    for (int i = 0; i < 16; i = i + 1) {
        int t = (a[i] & 65535) * mul + carry;
        a[i] = t & 65535;
        carry = t >> 16;
    }
}

fn mgc_big_from_bytes_be(int* a, char* bytes, int length) -> void {
    if (a == null) { return; }
    mgc_big_zero(a);
    if (bytes == null || length <= 0) { return; }
    if (length > 32) { length = 32; }
    for (int i = 0; i < length; i = i + 1) {
        int v = cast<int>(*(bytes + i)) & 255;
        mgc_big_mul_small_add(a, 256, v);
    }
}

fn mgc_big_to_bytes_be(int* a, char* out32) -> void {
    if (a == null || out32 == null) { return; }
    for (int i = 0; i < 32; i = i + 1) {
        int limb = a[i / 2] & 65535;
        int shift = (i % 2) * 8;
        *(out32 + (31 - i)) = cast<char>((limb >> shift) & 255);
    }
}

fn _bi_hex_val(int c) -> int {
    if (c >= 48 && c <= 57) { return c - 48; }
    if (c >= 65 && c <= 70) { return c - 55; }
    if (c >= 97 && c <= 102) { return c - 87; }
    return -1;
}

fn mgc_big_from_hex(int* a, string hex) -> bool {
    if (a == null || hex == null) { return false; }
    mgc_big_zero(a);
    char* p = cast<char*>(hex);
    int n = len(hex);
    if (n > 64) { return false; }
    for (int i = 0; i < n; i = i + 1) {
        int v = _bi_hex_val(cast<int>(*(p + i)) & 255);
        if (v < 0) { mgc_big_zero(a); return false; }
        mgc_big_mul_small_add(a, 16, v);
    }
    return true;
}

fn mgc_big_add(int* r, int* a, int* b) -> int {
    if (r == null || a == null || b == null) { return 0; }
    int carry = 0;
    for (int i = 0; i < 16; i = i + 1) {
        int s = (a[i] & 65535) + (b[i] & 65535) + carry;
        r[i] = s & 65535;
        carry = s >> 16;
    }
    return carry;
}

fn mgc_big_sub(int* r, int* a, int* b) -> int {
    if (r == null || a == null || b == null) { return 0; }
    int brw = 0;
    for (int i = 0; i < 16; i = i + 1) {
        int d = (a[i] & 65535) - (b[i] & 65535) - brw;
        if (d < 0) { d = d + 65536; brw = 1; } else { brw = 0; }
        r[i] = d & 65535;
    }
    return brw;
}

fn mgc_big_sub_one(int* r, int* a) -> void {
    if (r == null || a == null) { return; }
    mgc_big_copy(r, a);
    int i = 0;
    while (i < 16) {
        if (r[i] > 0) { r[i] = r[i] - 1; return; }
        r[i] = 65535;
        i = i + 1;
    }
}

fn mgc_big_mul(int* r, int* a, int* b) -> void {
    if (r == null || a == null || b == null) { return; }
    for (int i = 0; i < 32; i = i + 1) { r[i] = 0; }
    for (int i = 0; i < 16; i = i + 1) {
        int ai = a[i] & 65535;
        if (ai != 0) {
        int carry = 0;
        for (int j = 0; j < 16; j = j + 1) {
            int bj = b[j] & 65535;
            int t = r[i + j] + ai * bj + carry;
            r[i + j] = t & 65535;
            carry = t >> 16;
        }
        int k = i + 16;
        while (carry != 0 && k < 32) {
            int t = r[k] + carry;
            r[k] = t & 65535;
            carry = t >> 16;
            k = k + 1;
        }
        }
    }
}

fn mgc_big_shl1(int* a) -> int {
    int carry = 0;
    for (int i = 0; i < 16; i = i + 1) {
        int v = a[i] & 65535;
        a[i] = ((v << 1) | carry) & 65535;
        carry = (v >> 15) & 1;
    }
    return carry;
}

fn mgc_big_bit(int* a, int index) -> int {
    if (a == null || index < 0 || index >= 256) { return 0; }
    return (a[index / 16] >> (index % 16)) & 1;
}

fn mgc_big_bit_length(int* a) -> int {
    if (a == null) { return 0; }
    for (int i = 15; i >= 0; i = i - 1) {
        int v = a[i] & 65535;
        if (v != 0) {
            int bits = 0;
            while (v != 0) { bits = bits + 1; v = v >> 1; }
            return i * 16 + bits;
        }
    }
    return 0;
}

fn mgc_big_add_small(int* a, int v) -> void {
    if (a == null) { return; }
    int carry = v;
    int i = 0;
    while (carry != 0 && i < 16) {
        int t = (a[i] & 65535) + carry;
        a[i] = t & 65535;
        carry = t >> 16;
        i = i + 1;
    }
}

// Generic reduction: out = num (num_limbs bs-2^16 limbs) mod modulus.
// Both out and modulus are 16 limbs. Slow but simple and constant-size.
fn mgc_big_mod(int* out, int* num, int num_limbs, int* modulus) -> void {
    if (out == null || num == null || modulus == null) { return; }
    if (num_limbs < 1) { mgc_big_zero(out); return; }
    if (num_limbs > 32) { num_limbs = 32; }
    int* rem = alloc<int>(16);
    if (rem == null) { mgc_big_zero(out); return; }
    mgc_big_zero(rem);

    int top_bit = num_limbs * 16 - 1;
    for (int bit = top_bit; bit >= 0; bit = bit - 1) {
        int carry = mgc_big_shl1(rem);
        int nb = (num[bit / 16] >> (bit % 16)) & 1;
        if (nb != 0) { rem[0] = rem[0] | 1; }
        if (carry != 0 || mgc_big_cmp(rem, modulus) >= 0) {
            mgc_big_sub(rem, rem, modulus);
        }
    }
    mgc_big_copy(out, rem);
    free(rem);
}

fn mgc_big_mod_add(int* out, int* a, int* b, int* modulus) -> void {
    if (out == null || a == null || b == null || modulus == null) { return; }
    int* tmp = alloc<int>(16);
    if (tmp == null) { return; }
    int carry = mgc_big_add(tmp, a, b);
    if (carry != 0 || mgc_big_cmp(tmp, modulus) >= 0) {
        mgc_big_sub(tmp, tmp, modulus);
    }
    mgc_big_copy(out, tmp);
    free(tmp);
}

fn mgc_big_mod_sub(int* out, int* a, int* b, int* modulus) -> void {
    if (out == null || a == null || b == null || modulus == null) { return; }
    int* tmp = alloc<int>(16);
    if (tmp == null) { return; }
    if (mgc_big_cmp(a, b) >= 0) {
        mgc_big_sub(tmp, a, b);
    } else {
        int* diff = alloc<int>(16);
        if (diff == null) { free(tmp); return; }
        mgc_big_sub(diff, b, a);
        mgc_big_sub(tmp, modulus, diff);
        free(diff);
    }
    mgc_big_copy(out, tmp);
    free(tmp);
}

fn mgc_big_mod_mul(int* out, int* a, int* b, int* modulus) -> void {
    if (out == null || a == null || b == null || modulus == null) { return; }
    int* prod = alloc<int>(32);
    if (prod == null) { return; }
    mgc_big_mul(prod, a, b);
    mgc_big_mod(out, prod, 32, modulus);
    free(prod);
}

fn mgc_big_mod_pow(int* out, int* bs, int* exponent, int* modulus) -> void {
    if (out == null || bs == null || exponent == null || modulus == null) { return; }
    int* result = alloc<int>(16);
    int* b = alloc<int>(16);
    if (result == null || b == null) {
        if (result != null) { free(result); }
        if (b != null) { free(b); }
        return;
    }
    mgc_big_set_u32(result, 1);
    mgc_big_mod(b, bs, 16, modulus);

    int bits = mgc_big_bit_length(exponent);
    for (int i = bits - 1; i >= 0; i = i - 1) {
        mgc_big_mod_mul(result, result, result, modulus);
        if (mgc_big_bit(exponent, i) != 0) {
            mgc_big_mod_mul(result, result, b, modulus);
        }
    }
    mgc_big_copy(out, result);
    free(result);
    free(b);
}

// Fermat inverse: out = a^(modulus-2) mod modulus (modulus must be prime).
fn mgc_big_mod_inv(int* out, int* a, int* modulus) -> bool {
    if (out == null || a == null || modulus == null) { return false; }
    int* exp = alloc<int>(16);
    int* bs = alloc<int>(16);
    if (exp == null || bs == null) {
        if (exp != null) { free(exp); }
        if (bs != null) { free(bs); }
        return false;
    }
    mgc_big_sub_one(exp, modulus);
    mgc_big_sub_one(exp, exp);
    mgc_big_mod(bs, a, 16, modulus);
    if (mgc_big_is_zero(bs)) { free(exp); free(bs); return false; }
    mgc_big_mod_pow(out, bs, exp, modulus);
    bool ok = !mgc_big_is_zero(out);
    free(exp);
    free(bs);
    return ok;
}

// Byte helpers for 256-bit values.
fn mgc_big_from_hex32(int* a, string hex) -> bool {
    if (hex == null || len(hex) != 64) { return false; }
    return mgc_big_from_hex(a, hex);
}

fn mgc_big_to_hex(int* a) -> string {
    if (a == null) { return ""; }
    char* out = alloc<char>(32);
    if (out == null) { return ""; }
    mgc_big_to_bytes_be(a, out);
    // local tiny hex encoder to keep bigint independent of crypto.mg
    char* hex = alloc<char>(65);
    if (hex == null) { free(out); return ""; }
    for (int i = 0; i < 32; i = i + 1) {
        int b = cast<int>(*(out + i)) & 255;
        int hi = b >> 4;
        int lo = b & 15;
        if (hi < 10) { hex[i * 2] = cast<char>(48 + hi); } else { hex[i * 2] = cast<char>(87 + hi); }
        if (lo < 10) { hex[i * 2 + 1] = cast<char>(48 + lo); } else { hex[i * 2 + 1] = cast<char>(87 + lo); }
    }
    hex[64] = cast<char>(0);
    free(out);
    return cast<string>(hex);
}
