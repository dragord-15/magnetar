use "../lib/hash.mg";
use "../../lib/crypto.mg";
use "test_common.mg";

fn main() -> int {
    int failures = 0;

    check_string("sha256 abc",
                 crypto_sha256_hex("abc"),
                 "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                 &failures);

    check_string("sha256d empty",
                 mgc_sha256d_str(""),
                 "5df6e0e2761359d30a8275058e299fcc0381534545f55cf43e41983f5d4c9456",
                 &failures);

    check_string("sha256d abc",
                 mgc_sha256d_str("abc"),
                 "4f8b42c22dd3729b519ba6f68d2da7cc5b2d606d05daed5ad5128cc03e6c6358",
                 &failures);

    check_string("hash160 abc",
                 mgc_hash160_hex(cast<char*>("abc"), 3),
                 "bb1be98c142444d7a56aa3981c3942a978e4dc33",
                 &failures);

    check_string("hash160 empty",
                 mgc_hash160_hex(null, 0),
                 "b472a266d0bd89c13706a4132ccfb16f7c3b9fcb",
                 &failures);

    // Merkle root of three leaves: dsha(dsha(dsha(one)||dsha(two)) ||
    //                                      dsha(dsha(three)||dsha(three)))
    char* leaves = alloc<char>(96);
    if (leaves == null) {
        print_str("FAIL alloc\n");
        return 1;
    }
    mgc_sha256d_raw(cast<char*>("one"), 3, leaves + 0);
    mgc_sha256d_raw(cast<char*>("two"), 3, leaves + 32);
    mgc_sha256d_raw(cast<char*>("three"), 5, leaves + 64);

    check_string("merkle 3",
                 mgc_merkle_root_hex(leaves, 3),
                 "92755eb8133e728471a88a228d47268a2ffa1b0672367cf8a3cc75d4b7c4fa86",
                 &failures);

    check_string("merkle 1",
                 mgc_merkle_root_hex(leaves, 1),
                 "fe8d7a873dc48961a6af334c996b2cb3ce37149d5ce9c9253952a54c6a92c1ad",
                 &failures);

    char* empty_root = alloc<char>(32);
    if (empty_root == null) {
        print_str("FAIL alloc2\n");
        free(leaves);
        return 1;
    }
    check_bool("merkle empty", mgc_merkle_root(null, 0, empty_root), false, &failures);

    free(empty_root);
    free(leaves);
    return test_report("test_hash", failures);
}
