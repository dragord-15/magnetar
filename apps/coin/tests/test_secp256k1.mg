use "../lib/secp256k1.mg";
use "../lib/bigint.mg";
use "../../lib/crypto.mg";
use "test_common.mg";

fn main() -> int {
    int failures = 0;
    int* d = alloc<int>(16);
    char* pub = alloc<char>(33);
    if (d == null || pub == null) { print_str("FAIL alloc\n"); return 1; }

    mgc_big_set_u32(d, 1);
    check_bool("pubkey 1", secp_pubkey_from_priv(d, pub), true, &failures);
    check_string("pubkey 1 hex", crypto_hex_encode(pub, 33),
                 "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798", &failures);

    mgc_big_set_u32(d, 2);
    check_bool("pubkey 2", secp_pubkey_from_priv(d, pub), true, &failures);
    check_string("pubkey 2 hex", crypto_hex_encode(pub, 33),
                 "02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5", &failures);

    int* gx = alloc<int>(16); int* gy = alloc<int>(16); int* gz = alloc<int>(16);
    int* qx = alloc<int>(16); int* qy = alloc<int>(16); int* qz = alloc<int>(16);
    char* pub1 = crypto_hex_decode("0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798", null);
    check_bool("parse G", secp_pubkey_parse(pub1, 33, qx, qy, qz), true, &failures);
    int* ax = alloc<int>(16); int* ay = alloc<int>(16);
    check_bool("affine G", secp_point_to_affine(ax, ay, qx, qy, qz), true, &failures);
    check_string("Gx", mgc_big_to_hex(ax), "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798", &failures);
    check_string("Gy", mgc_big_to_hex(ay), "483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8", &failures);

    // ECDSA sign/verify, RFC6979 + low-S + DER.
    char* digest = crypto_hex_decode("5df6e0e2761359d30a8275058e299fcc0381534545f55cf43e41983f5d4c9456", null);
    char* priv = crypto_hex_decode("0000000000000000000000000000000000000000000000000000000000000001", null);
    char* der = alloc<char>(80);
    int der_len = 0;
    check_bool("sign", secp_ecdsa_sign(digest, priv, der, &der_len), true, &failures);
    check_bool("der len", der_len >= 8 && der_len <= 72, true, &failures);
    check_bool("verify", secp_ecdsa_verify(digest, pub1, 33, der, der_len), true, &failures);

    char* der2 = alloc<char>(80);
    int der2_len = 0;
    if (der2 == null) { print_str("FAIL alloc\n"); return 1; }
    check_bool("sign again", secp_ecdsa_sign(digest, priv, der2, &der2_len), true, &failures);
    check_int("deterministic length", der2_len, der_len, &failures);
    check_bool("deterministic signature", mgc_equal(der, der2, der_len), true, &failures);
    digest[0] = cast<char>((cast<int>(digest[0]) ^ 1) & 255);
    check_bool("sign changed digest", secp_ecdsa_sign(digest, priv, der2, &der2_len), true, &failures);
    check_bool("changed digest changes signature", mgc_equal(der, der2, der_len), false, &failures);
    digest[0] = cast<char>((cast<int>(digest[0]) ^ 1) & 255);

    // Tampered digest must fail.
    digest[0] = cast<char>((cast<int>(digest[0]) ^ 1) & 255);
    check_bool("reject tampered", secp_ecdsa_verify(digest, pub1, 33, der, der_len), false, &failures);
    digest[0] = cast<char>((cast<int>(digest[0]) ^ 1) & 255);

    // Tampered signature must fail.
    der[der_len - 1] = cast<char>((cast<int>(der[der_len - 1]) ^ 1) & 255);
    check_bool("reject sig", secp_ecdsa_verify(digest, pub1, 33, der, der_len), false, &failures);

    free(der2);
    free(digest); free(priv); free(der); free(pub1);
    free(ax); free(ay); free(qx); free(qy); free(qz); free(gx); free(gy); free(gz);
    free(pub); free(d);
    return test_report("test_secp256k1", failures);
}
