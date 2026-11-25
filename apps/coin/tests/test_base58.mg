use "../lib/base58.mg";
use "../lib/hash.mg";
use "../../lib/crypto.mg";
use "test_common.mg";

extern fn print_str(string s) -> void;

fn main() -> int {
    int failures = 0;

    // Basic Base58 encode
    char* one = alloc<char>(1);
    *(one + 0) = cast<char>(0);
    check_string("b58 zero", base58_encode(one, 1), "1", &failures);

    char* lead = alloc<char>(6);
    *(lead + 0) = cast<char>(0);
    *(lead + 1) = cast<char>(0);
    *(lead + 2) = cast<char>(0x00);
    *(lead + 3) = cast<char>(0x28);
    *(lead + 4) = cast<char>(0x7f);
    *(lead + 5) = cast<char>(0xb4);
    // bytes 00 00 00 28 7f b4 cd? wait vector is 0000287fb4cd (6 bytes)
    char* lead2 = alloc<char>(6);
    *(lead2 + 0) = cast<char>(0); *(lead2 + 1) = cast<char>(0);
    *(lead2 + 2) = cast<char>(0x28); *(lead2 + 3) = cast<char>(0x7f);
    *(lead2 + 4) = cast<char>(0xb4); *(lead2 + 5) = cast<char>(0xcd);
    check_string("b58 leading zeros", base58_encode(lead2, 6), "11233QC4", &failures);

    string hello = "Hello World";
    check_string("b58 hello", base58_encode(cast<char*>(hello), 11), "JxF12TrwUP45BMd", &failures);

    // Decode roundtrip
    int out_len = 0;
    char* dec = base58_decode("JxF12TrwUP45BMd", &out_len);
    check_int("b58 dec len", out_len, 11, &failures);
    if (dec != null) {
        check_bool("b58 dec ok", mgc_equal(dec, cast<char*>(hello), 11), true, &failures);
        free(dec);
    } else {
        print_str("FAIL b58 dec null\n");
        failures = failures + 1;
    }

    // Invalid char
    char* bad = base58_decode("0OIl", &out_len);
    check_bool("b58 invalid", bad == null, true, &failures);

    // HASH160 + Base58Check for compressed pubkey of privkey 1
    int pk_len = 0;
    char* pub = crypto_hex_decode("0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798", &pk_len);
    if (pub == null || pk_len != 33) {
        print_str("FAIL pubkey decode\n");
        return 1;
    }
    char* h160 = alloc<char>(20);
    mgc_hash160(pub, 33, h160);
    check_string("hash160 pub1", crypto_hex_encode(h160, 20),
                 "751e76e8199196d454941c45d1b3a323f1433bd6", &failures);

    char* payload = alloc<char>(21);
    *(payload + 0) = cast<char>(0x00);
    mgc_copy(payload + 1, h160, 20);
    string addr = base58check_encode(payload, 21);
    check_string("address privkey1", addr, "1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH", &failures);

    // Base58Check decode and checksum
    int chk_len = 0;
    char* chk = base58check_decode(addr, &chk_len);
    check_int("chk len", chk_len, 21, &failures);
    if (chk != null) {
        check_bool("chk payload", mgc_equal(chk, payload, 21), true, &failures);
        free(chk);
    } else {
        failures = failures + 1;
    }

    // Tampered checksum must fail
    char* tampered = base58check_decode("1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMI", &chk_len);
    check_bool("tampered null", tampered == null, true, &failures);

    free(payload);
    free(h160);
    free(pub);
    free(lead2);
    free(lead);
    free(one);
    return test_report("test_base58", failures);
}
