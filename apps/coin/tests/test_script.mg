// Magnetar Coin — tests for script templates, pushes, and P2PKH scriptSig parsing.

use "../lib/script.mg";
use "../../lib/crypto.mg";
use "test_common.mg";

fn main() -> int {
    int failures = 0;
    int hlen = 0;
    int plen = 0;
    char* h160 = crypto_hex_decode("751e76e8199196d454941c45d1b3a323f1433bd6", &hlen);
    char* pub = crypto_hex_decode("0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798", &plen);
    if (h160 == null || hlen != 20 || pub == null || plen != 33) {
        print_str("FAIL decode\n");
        return 1;
    }

    char* p25 = alloc<char>(25);
    char* h160_out = alloc<char>(20);
    char* payload = alloc<char>(256);
    char* out = alloc<char>(300);
    char* sig = alloc<char>(80);
    char* scriptbuf = alloc<char>(300);
    if (p25 == null || h160_out == null || payload == null || out == null || sig == null || scriptbuf == null) {
        print_str("FAIL alloc\n");
        return 1;
    }
    for (int i = 0; i < 256; i = i + 1) { *(payload + i) = cast<char>(i + 1); }
    for (int i = 0; i < 80; i = i + 1) { *(sig + i) = cast<char>(0x30 + i); }

    mgc_script_p2pkh(h160, p25);
    check_string("p2pkh template", crypto_hex_encode(p25, 25),
                 "76a914751e76e8199196d454941c45d1b3a323f1433bd688ac", &failures);
    check_bool("p2pkh valid", mgc_script_is_p2pkh(p25, 25), true, &failures);
    check_bool("p2pkh short", mgc_script_is_p2pkh(p25, 24), false, &failures);
    check_bool("p2pkh long", mgc_script_is_p2pkh(p25, 26), false, &failures);
    check_bool("hash160 ok", mgc_script_p2pkh_hash160(p25, 25, h160_out), true, &failures);
    check_string("hash160 out", crypto_hex_encode(h160_out, 20),
                 "751e76e8199196d454941c45d1b3a323f1433bd6", &failures);

    *(p25 + 0) = cast<char>(0x51);
    check_bool("tamper opcode", mgc_script_is_p2pkh(p25, 25), false, &failures);
    check_bool("tamper hash160", mgc_script_p2pkh_hash160(p25, 25, h160_out), false, &failures);
    *(p25 + 0) = cast<char>(0x76);
    *(p25 + 2) = cast<char>(0x15);
    check_bool("tamper push len", mgc_script_is_p2pkh(p25, 25), false, &failures);
    *(p25 + 2) = cast<char>(0x14);
    *(p25 + 24) = cast<char>(0xab);
    check_bool("tamper checksig", mgc_script_is_p2pkh(p25, 25), false, &failures);
    *(p25 + 24) = cast<char>(0xac);

    int n = -1;
    check_bool("push empty", mgc_script_push(payload, 0, out, &n), true, &failures);
    check_int("push empty len", n, 0, &failures);
    check_bool("push 20", mgc_script_push(payload, 20, out, &n), true, &failures);
    check_int("push 20 len", n, 21, &failures);
    check_bool("push 20 opcode", (cast<int>(*(out + 0)) & 255) == 20, true, &failures);
    check_bool("push 20 bytes", mgc_equal(out + 1, payload, 20), true, &failures);
    check_bool("push 75", mgc_script_push(payload, 75, out, &n), true, &failures);
    check_int("push 75 len", n, 76, &failures);
    check_bool("push 75 opcode", (cast<int>(*(out + 0)) & 255) == 75, true, &failures);
    check_bool("push 75 bytes", mgc_equal(out + 1, payload, 75), true, &failures);
    check_bool("push 76", mgc_script_push(payload, 76, out, &n), true, &failures);
    check_int("push 76 len", n, 78, &failures);
    check_bool("push 76 opcode", (cast<int>(*(out + 0)) & 255) == 0x4c, true, &failures);
    check_bool("push 76 count", (cast<int>(*(out + 1)) & 255) == 76, true, &failures);
    check_bool("push 76 bytes", mgc_equal(out + 2, payload, 76), true, &failures);
    check_bool("push 255", mgc_script_push(payload, 255, out, &n), true, &failures);
    check_int("push 255 len", n, 257, &failures);
    check_bool("push 255 bytes", mgc_equal(out + 2, payload, 255), true, &failures);
    check_bool("push 256 rejected", mgc_script_push(payload, 256, out, &n), false, &failures);

    char* coinbase_data = payload;
    check_bool("coinbase push", mgc_script_coinbase(coinbase_data, 4, out, &n), true, &failures);
    check_int("coinbase len", n, 5, &failures);
    check_bool("coinbase opcode", (cast<int>(*(out + 0)) & 255) == 4, true, &failures);
    check_bool("coinbase bytes", mgc_equal(out + 1, coinbase_data, 4), true, &failures);

    check_bool("sig build", mgc_script_sig(sig, 71, pub, 33, scriptbuf, &n), true, &failures);
    check_int("sig len", n, 106, &failures);
    check_bool("sig opcode", (cast<int>(*(scriptbuf + 0)) & 255) == 71, true, &failures);
    check_bool("pub opcode", (cast<int>(*(scriptbuf + 72)) & 255) == 33, true, &failures);
    check_bool("sig bytes", mgc_equal(scriptbuf + 1, sig, 71), true, &failures);
    check_bool("pub bytes", mgc_equal(scriptbuf + 73, pub, 33), true, &failures);

    char* psig = null;
    int psig_len = 0;
    char* ppub = null;
    int ppub_len = 0;
    check_bool("sig parse", mgc_script_parse_p2pkh_sig(scriptbuf, n, &psig, &psig_len, &ppub, &ppub_len), true, &failures);
    check_int("parsed sig len", psig_len, 71, &failures);
    check_int("parsed pub len", ppub_len, 33, &failures);
    check_bool("sig is view", psig == scriptbuf + 1, true, &failures);
    check_bool("pub is view", ppub == scriptbuf + 73, true, &failures);
    check_bool("parsed sig bytes", mgc_equal(psig, sig, 71), true, &failures);
    check_bool("parsed pub bytes", mgc_equal(ppub, pub, 33), true, &failures);

    *(scriptbuf + 0) = cast<char>(0x4c);
    check_bool("non-minimal sig push", mgc_script_parse_p2pkh_sig(scriptbuf, n, &psig, &psig_len, &ppub, &ppub_len), false, &failures);
    *(scriptbuf + 0) = cast<char>(71);
    *(scriptbuf + 72) = cast<char>(0x4c);
    check_bool("non-minimal pub push", mgc_script_parse_p2pkh_sig(scriptbuf, n, &psig, &psig_len, &ppub, &ppub_len), false, &failures);
    *(scriptbuf + 72) = cast<char>(33);
    *(scriptbuf + 72) = cast<char>(32);
    check_bool("wrong pub size", mgc_script_parse_p2pkh_sig(scriptbuf, n - 1, &psig, &psig_len, &ppub, &ppub_len), false, &failures);
    *(scriptbuf + 72) = cast<char>(33);
    check_bool("trailing byte", mgc_script_parse_p2pkh_sig(scriptbuf, n + 1, &psig, &psig_len, &ppub, &ppub_len), false, &failures);
    check_bool("truncated", mgc_script_parse_p2pkh_sig(scriptbuf, n - 1, &psig, &psig_len, &ppub, &ppub_len), false, &failures);

    check_bool("sig build long", mgc_script_sig(sig, 80, pub, 33, scriptbuf, &n), true, &failures);
    check_int("sig long len", n, 116, &failures);
    check_bool("sig long parse", mgc_script_parse_p2pkh_sig(scriptbuf, n, &psig, &psig_len, &ppub, &ppub_len), true, &failures);
    check_int("sig long parsed len", psig_len, 80, &failures);
    check_bool("sig long view", psig == scriptbuf + 2, true, &failures);
    check_bool("sig long pub view", ppub == scriptbuf + 83, true, &failures);
    check_bool("sig too long", mgc_script_sig(sig, 256, pub, 33, scriptbuf, &n), false, &failures);

    free(scriptbuf);
    free(sig);
    free(out);
    free(payload);
    free(h160_out);
    free(p25);
    free(pub);
    free(h160);
    return test_report("test_script", failures);
}
