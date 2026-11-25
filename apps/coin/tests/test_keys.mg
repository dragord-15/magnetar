use "../lib/keys.mg";
use "../../lib/crypto.mg";
use "test_common.mg";

fn main() -> int {
    int failures = 0;
    char* priv = crypto_hex_decode("0000000000000000000000000000000000000000000000000000000000000001", null);
    char* pub = alloc<char>(33);
    if (priv == null || pub == null) { print_str("FAIL alloc\n"); return 1; }

    check_bool("priv valid", mgc_key_validate(priv), true, &failures);
    check_bool("pub from priv", mgc_privkey_to_pubkey(priv, pub), true, &failures);
    check_string("pub", crypto_hex_encode(pub, 33),
                 "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798", &failures);

    check_string("main address", mgc_address_from_pubkey(pub, 33, MGC_NETWORK_MAIN),
                 "MJaRnao1s62a2zAKSkmG582KbLKianqb7v", &failures);
    check_string("test address", mgc_address_from_pubkey(pub, 33, MGC_NETWORK_TEST),
                 "mrCDrCybB6J1vRfbwM5hemdJz73FwDBC8r", &failures);

    char* h160 = alloc<char>(20);
    check_bool("address decode", mgc_address_decode("MJaRnao1s62a2zAKSkmG582KbLKianqb7v", MGC_NETWORK_MAIN, h160), true, &failures);
    check_string("address h160", crypto_hex_encode(h160, 20),
                 "751e76e8199196d454941c45d1b3a323f1433bd6", &failures);

    check_string("main wif", mgc_wif_encode(priv, MGC_NETWORK_MAIN, true),
                 "KwDiBf89QgGbjEhKnhXJuH7LrciVrZi3qYjgd9M7rFU73sVHnoWn", &failures);
    check_string("test wif", mgc_wif_encode(priv, MGC_NETWORK_TEST, true),
                 "cMahea7zqjxrtgAbB7LSGbcQUr1uX1ojuat9jZodMN87JcbXMTcA", &failures);

    bool compressed = false;
    char* decoded = alloc<char>(32);
    check_bool("wif decode", mgc_wif_decode("KwDiBf89QgGbjEhKnhXJuH7LrciVrZi3qYjgd9M7rFU73sVHnoWn", MGC_NETWORK_MAIN, &compressed, decoded), true, &failures);
    check_bool("wif compressed", compressed, true, &failures);
    check_bool("wif key", mgc_equal(decoded, priv, 32), true, &failures);

    check_bool("reject wrong net wif", mgc_wif_decode("cMahea7zqjxrtgAbB7LSGbcQUr1uX1ojuat9jZodMN87JcbXMTcA", MGC_NETWORK_MAIN, &compressed, decoded), false, &failures);

    char* rnd = alloc<char>(32);
    check_bool("keygen", mgc_key_generate(rnd), true, &failures);
    check_bool("keygen valid", mgc_key_validate(rnd), true, &failures);
    string wif = mgc_wif_encode(rnd, MGC_NETWORK_REGTEST, true);
    check_bool("rnd wif decode", mgc_wif_decode(wif, MGC_NETWORK_REGTEST, &compressed, decoded), true, &failures);
    check_bool("rnd wif key", mgc_equal(decoded, rnd, 32), true, &failures);

    free(rnd); free(decoded); free(h160); free(pub); free(priv);
    return test_report("test_keys", failures);
}
