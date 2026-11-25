use "../lib/bigint.mg";
use "test_common.mg";

fn main() -> int {
    int failures = 0;
    int* a = alloc<int>(16);
    int* b = alloc<int>(16);
    int* r = alloc<int>(16);
    int* m = alloc<int>(16);
    int* wide = alloc<int>(32);
    int* inv = alloc<int>(16);
    int* chk = alloc<int>(16);
    if (a == null || b == null || r == null || m == null || wide == null || inv == null || chk == null) {
        print_str("FAIL alloc\n");
        return 1;
    }

    mgc_big_from_hex(a, "0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF");
    check_string("bigint a hex", mgc_big_to_hex(a),
                 "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef", &failures);

    mgc_big_from_hex(b, "FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210");
    check_string("bigint b hex", mgc_big_to_hex(b),
                 "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210", &failures);

    mgc_big_add(r, a, b);
    check_string("bigint add", mgc_big_to_hex(r),
                 "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff", &failures);

    mgc_big_sub(r, b, a);
    check_string("bigint sub", mgc_big_to_hex(r),
                 "fdb97530eca86421fdb97530eca86421fdb97530eca86421fdb97530eca86421", &failures);

    mgc_big_set_u32(a, 123456789);
    mgc_big_set_u32(b, 987654321);
    mgc_big_mul(wide, a, b);
    check_string("bigint mul", mgc_big_to_hex(wide),
                 "00000000000000000000000000000000000000000000000001b13114fbff5385", &failures);

    // p = 2^256 - 2^32 - 977
    mgc_big_from_hex(m, "FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F");
    // a^(p-2) * a == 1 mod p
    int* aa = alloc<int>(16);
    mgc_big_from_hex(aa, "79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798");
    check_bool("bigint inv", mgc_big_mod_inv(inv, aa, m), true, &failures);
    mgc_big_mod_mul(chk, inv, aa, m);
    mgc_big_set_u32(r, 1);
    check_int("bigint inv check", mgc_big_cmp(chk, r), 0, &failures);

    // (p-1)^2 mod p == 1
    mgc_big_sub_one(a, m);
    mgc_big_mod_mul(r, a, a, m);
    mgc_big_set_u32(b, 1);
    check_int("bigint mod square", mgc_big_cmp(r, b), 0, &failures);

    free(aa);
    free(chk); free(inv); free(wide); free(m); free(r); free(b); free(a);
    return test_report("test_bigint", failures);
}
