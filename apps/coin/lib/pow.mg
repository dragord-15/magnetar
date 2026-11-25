// Magnetar Coin — compact difficulty targets, hash work and retargeting.
// chain work is approximate: 2^256/(target+1) is estimated from the target bit length.

use "bigint.mg";
use "hash.mg";
use "util.mg";
use "params.mg";

fn _mgc_pow_shr1(int* a) -> void {
    if (a == null) { return; }
    int carry = 0;
    for (int i = 15; i >= 0; i = i - 1) {
        int v = a[i] & 65535;
        a[i] = ((v >> 1) | carry) & 65535;
        carry = (v & 1) << 15;
    }
}

fn mgc_pow_target_from_bits(int bits, int* out) -> bool {
    if (out == null) { return false; }
    mgc_big_zero(out);
    int bits32 = bits & 4294967295;
    int exponent = bits32 >> 24;
    int mantissa = bits32 & 8388607;
    if (exponent <= 0 || mantissa == 0) { return false; }
    if ((bits32 & 8388608) != 0) { return false; }

    mgc_big_set_u32(out, mantissa);
    if (exponent > 3) {
        int bytes = exponent - 3;
        if (bytes > 32) { bytes = 32; }
        for (int i = 0; i < bytes; i = i + 1) {
            mgc_big_mul_small_add(out, 256, 0);
        }
    } else if (exponent < 3) {
        int bits_to_shift = (3 - exponent) * 8;
        for (int i = 0; i < bits_to_shift; i = i + 1) {
            _mgc_pow_shr1(out);
        }
    }
    return !mgc_big_is_zero(out);
}

fn mgc_pow_bits_from_target(int* target) -> int {
    if (target == null || mgc_big_is_zero(target)) { return 0; }
    int bit_length = mgc_big_bit_length(target);
    int size = bit_length / 8 + 1;
    if (size < 1) { size = 1; }
    if (size > 255) { size = 255; }

    int* m = alloc<int>(16);
    if (m == null) { return 0; }
    mgc_big_copy(m, target);
    if (size > 3) {
        int shift = (size - 3) * 8;
        if (shift > 255) { shift = 255; }
        for (int i = 0; i < shift; i = i + 1) { _mgc_pow_shr1(m); }
    } else if (size < 3) {
        int shift = (3 - size) * 8;
        for (int i = 0; i < shift; i = i + 1) { mgc_big_shl1(m); }
    }

    int mantissa = (m[0] & 65535) | ((m[1] & 65535) << 16);
    if ((mantissa & 8388608) != 0) {
        mantissa = mantissa >> 8;
        size = size + 1;
    }
    free(m);
    mantissa = mantissa & 8388607;
    return (((size & 255) << 24) | mantissa) & 4294967295;
}

fn mgc_pow_hash_to_big(char* hash32, int* out) -> void {
    if (out == null) { return; }
    mgc_big_zero(out);
    if (hash32 == null) { return; }
    char* be = alloc<char>(32);
    if (be == null) { return; }
    for (int i = 0; i < 32; i = i + 1) {
        *(be + i) = *(hash32 + (31 - i));
    }
    mgc_big_from_bytes_be(out, be, 32);
    free(be);
}

fn mgc_pow_check(char* hash32, int bits) -> bool {
    int* target = alloc<int>(16);
    int* value = alloc<int>(16);
    if (target == null || value == null) {
        if (target != null) { free(target); }
        if (value != null) { free(value); }
        return false;
    }
    bool ok = mgc_pow_target_from_bits(bits, target);
    if (ok) {
        mgc_pow_hash_to_big(hash32, value);
        ok = mgc_big_cmp(value, target) <= 0;
    }
    free(target);
    free(value);
    return ok;
}

fn mgc_pow_work_for_bits(int bits, int* out) -> void {
    if (out == null) { return; }
    mgc_big_zero(out);
    int* target = alloc<int>(16);
    if (target == null) { return; }
    if (!mgc_pow_target_from_bits(bits, target)) { free(target); return; }

    int shift = 256 - mgc_big_bit_length(target);
    if (shift < 0) { shift = 0; }
    if (shift > 255) { shift = 255; }
    mgc_big_set_u64(out, 1);
    for (int i = 0; i < shift; i = i + 1) {
        mgc_big_shl1(out);
    }
    free(target);
}

fn mgc_pow_work_add(int* acc, int* add) -> void {
    if (acc == null || add == null) { return; }
    int* sum = alloc<int>(16);
    if (sum == null) { return; }
    mgc_big_add(sum, acc, add);
    mgc_big_copy(acc, sum);
    free(sum);
}

fn _mgc_pow_div_small(int* out, int* a, int divisor, int* rem) -> void {
    if (out == null || a == null || divisor <= 0) { return; }
    int carry = 0;
    for (int i = 15; i >= 0; i = i - 1) {
        int cur = carry * 65536 + (a[i] & 65535);
        out[i] = cur / divisor;
        carry = cur - out[i] * divisor;
    }
    if (rem != null) { *rem = carry; }
}

fn mgc_pow_max_target(int network, int* out) -> void {
    if (out == null) { return; }
    if (!mgc_pow_target_from_bits(mgc_genesis_bits(network), out)) {
        mgc_big_zero(out);
    }
}

fn mgc_pow_next_bits(int network, int height, int previous_bits, int actual_span) -> int {
    int interval = mgc_retarget_interval(network);
    if (interval <= 0 || height <= 0 || (height % interval) != 0) { return previous_bits; }

    int* old_target = alloc<int>(16);
    int* new_target = alloc<int>(16);
    int* lower = alloc<int>(16);
    int* upper = alloc<int>(16);
    int* maximum = alloc<int>(16);
    if (old_target == null || new_target == null || lower == null || upper == null || maximum == null) {
        if (old_target != null) { free(old_target); }
        if (new_target != null) { free(new_target); }
        if (lower != null) { free(lower); }
        if (upper != null) { free(upper); }
        if (maximum != null) { free(maximum); }
        return previous_bits;
    }
    if (!mgc_pow_target_from_bits(previous_bits, old_target)) {
        free(old_target); free(new_target); free(lower); free(upper); free(maximum);
        return previous_bits;
    }

    int span = actual_span;
    int max_span = interval * 4;
    if (span < 1) { span = 1; }
    if (span > max_span) { span = max_span; }

    mgc_big_copy(new_target, old_target);
    mgc_big_mul_small_add(new_target, span, 0);
    _mgc_pow_div_small(new_target, new_target, interval, null);

    mgc_big_copy(lower, old_target);
    _mgc_pow_div_small(lower, lower, 4, null);
    mgc_big_copy(upper, old_target);
    mgc_big_mul_small_add(upper, 4, 0);

    if (mgc_big_cmp(new_target, lower) < 0) { mgc_big_copy(new_target, lower); }
    if (mgc_big_cmp(new_target, upper) > 0) { mgc_big_copy(new_target, upper); }

    mgc_pow_max_target(network, maximum);
    if (mgc_big_cmp(new_target, maximum) > 0) { mgc_big_copy(new_target, maximum); }

    int bits = mgc_pow_bits_from_target(new_target);
    free(old_target);
    free(new_target);
    free(lower);
    free(upper);
    free(maximum);
    if (bits == 0) { return previous_bits; }
    return bits;
}
