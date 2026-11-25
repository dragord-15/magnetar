// Tests for compact targets, little-endian hash conversion, work and retargeting.

use "../lib/pow.mg";
use "../lib/endian.mg";
use "test_common.mg";

fn main() -> int {
    int failures = 0;
    int* target = alloc<int>(16);
    int* value = alloc<int>(16);
    int* one = alloc<int>(16);
    int* work = alloc<int>(16);
    int* work2 = alloc<int>(16);
    int* expected = alloc<int>(16);
    int* bits_list = alloc<int>(7);
    char* hash = alloc<char>(32);
    char* header = alloc<char>(80);
    if (target == null || value == null || one == null || work == null || work2 == null ||
        expected == null || bits_list == null || hash == null || header == null) {
        print_str("FAIL alloc\n");
        return 1;
    }

    bits_list[0] = 486604799;
    bits_list[1] = 520159231;
    bits_list[2] = 545259519;
    bits_list[3] = 50397183;
    bits_list[4] = 16842752;
    bits_list[5] = 33619712;
    bits_list[6] = 503382015;
    for (int i = 0; i < 7; i = i + 1) {
        bool ok = mgc_pow_target_from_bits(bits_list[i], target);
        check_bool("target from bits", ok, true, &failures);
        check_int("bits roundtrip", mgc_pow_bits_from_target(target), bits_list[i], &failures);
    }

    check_bool("zero mantissa", mgc_pow_target_from_bits(486539264, target), false, &failures);
    check_bool("sign bit", mgc_pow_target_from_bits(494993407, target), false, &failures);
    check_bool("zero exponent", mgc_pow_target_from_bits(65535, target), false, &failures);
    check_bool("null target out", mgc_pow_target_from_bits(486604799, null), false, &failures);
    check_int("bits from zero", mgc_pow_bits_from_target(target), 0, &failures);

    mgc_zero(hash, 32);
    *(hash + 0) = cast<char>(1);
    mgc_pow_hash_to_big(hash, value);
    mgc_big_set_u64(one, 1);
    check_int("hash little endian one", mgc_big_cmp(value, one), 0, &failures);
    mgc_zero(hash, 32);
    *(hash + 31) = cast<char>(1);
    mgc_pow_hash_to_big(hash, value);
    check_int("hash little endian high", mgc_big_bit_length(value), 249, &failures);

    int reg_bits = mgc_genesis_bits(MGC_NETWORK_REGTEST);
    mgc_zero(header, 80);
    endian_write_u32_le(header, 0, 1);
    endian_write_u32_le(header, 72, reg_bits);
    bool mined = false;
    int nonce = 0;
    while (!mined && nonce < 10000) {
        endian_write_u32_le(header, 76, nonce);
        mgc_sha256d_raw(header, 80, hash);
        mined = mgc_pow_check(hash, reg_bits);
        nonce = nonce + 1;
    }
    check_bool("regtest nonce found", mined, true, &failures);
    for (int i = 0; i < 32; i = i + 1) { *(hash + i) = cast<char>(255); }
    check_bool("high hash rejected", mgc_pow_check(hash, reg_bits), false, &failures);
    check_bool("bad bits rejected", mgc_pow_check(hash, 0), false, &failures);

    mgc_pow_max_target(MGC_NETWORK_MAIN, expected);
    check_bool("max from genesis", mgc_pow_target_from_bits(mgc_genesis_bits(MGC_NETWORK_MAIN), value), true, &failures);
    check_int("max target matches genesis", mgc_big_cmp(expected, value), 0, &failures);

    mgc_pow_work_for_bits(reg_bits, work);
    check_int("regtest work bits", mgc_big_bit_length(work), 2, &failures);
    mgc_pow_work_add(work, work);
    check_int("work add bits", mgc_big_bit_length(work), 3, &failures);
    mgc_big_set_u64(work2, 1);
    mgc_pow_work_add(work, work2);
    check_int("work add one", mgc_big_bit_length(work), 3, &failures);
    mgc_pow_work_for_bits(mgc_genesis_bits(MGC_NETWORK_MAIN), work);
    check_int("main work bits", mgc_big_bit_length(work), 33, &failures);
    check_int("main work top bit", mgc_big_bit(work, 32), 1, &failures);

    int main_bits = mgc_genesis_bits(MGC_NETWORK_MAIN);
    int interval = mgc_retarget_interval(MGC_NETWORK_MAIN);
    check_int("no retarget", mgc_pow_next_bits(MGC_NETWORK_MAIN, interval - 1, main_bits, interval * 4), main_bits, &failures);
    check_int("zero height", mgc_pow_next_bits(MGC_NETWORK_MAIN, 0, main_bits, interval), main_bits, &failures);
    check_int("same span", mgc_pow_next_bits(MGC_NETWORK_MAIN, interval, main_bits, interval), main_bits, &failures);
    check_int("double span", mgc_pow_next_bits(MGC_NETWORK_MAIN, interval, 469827583, interval * 2), 469893118, &failures);
    check_int("fast clamp", mgc_pow_next_bits(MGC_NETWORK_MAIN, interval, main_bits, 1), 473956288, &failures);
    check_int("max clamp", mgc_pow_next_bits(MGC_NETWORK_MAIN, interval, 520159231, interval), main_bits, &failures);
    check_int("regtest boundary", mgc_pow_next_bits(MGC_NETWORK_REGTEST, mgc_retarget_interval(MGC_NETWORK_REGTEST), reg_bits, 1), 538968063, &failures);

    mgc_pow_target_from_bits(469827583, value);
    mgc_big_copy(expected, value);
    mgc_big_mul_small_add(expected, 4, 0);
    int slow_bits = mgc_pow_next_bits(MGC_NETWORK_MAIN, interval, 469827583, interval * 8);
    mgc_pow_target_from_bits(slow_bits, value);
    check_int("slow clamp target", mgc_big_cmp(value, expected), 0, &failures);

    free(hash); free(header); free(bits_list); free(expected); free(work2);
    free(work); free(one); free(value); free(target);
    return test_report("test_pow", failures);
}
