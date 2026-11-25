// Magnetar Coin — transaction serialization, txid and strict deserialization tests.

use "../lib/tx.mg";
use "../../lib/crypto.mg";
use "test_common.mg";

fn main() -> int {
    int failures = 0;
    char* prev = alloc<char>(32);
    char* script = alloc<char>(3);
    char* out1 = alloc<char>(3);
    char* out2 = alloc<char>(3);
    char* tid = alloc<char>(32);
    char* tid2 = alloc<char>(32);
    char* expected = alloc<char>(32);
    char* full_digest = alloc<char>(32);
    if (prev == null || script == null || out1 == null || out2 == null ||
        tid == null || tid2 == null || expected == null || full_digest == null) {
        print_str("FAIL alloc\n");
        return 1;
    }
    for (int i = 0; i < 32; i = i + 1) { *(prev + i) = cast<char>(i + 1); }
    *(script + 0) = cast<char>(0x51);
    *(script + 1) = cast<char>(0x20);
    *(script + 2) = cast<char>(0x01);
    *(out1 + 0) = cast<char>(0x76);
    *(out1 + 1) = cast<char>(0xa9);
    *(out1 + 2) = cast<char>(0x14);
    *(out2 + 0) = cast<char>(0x51);
    *(out2 + 1) = cast<char>(0x20);
    *(out2 + 2) = cast<char>(0x02);

    MgcTx tx;
    mgc_tx_init(&tx);
    check_bool("add input", mgc_tx_add_input(&tx, prev, 7, null, 0, 4294967295), true, &failures);
    check_int("zero-length input script", tx.input_script_lens[0], 0, &failures);
    check_bool("set input script", mgc_tx_set_input_script(&tx, 0, script, 3), true, &failures);
    check_bool("clear input script", mgc_tx_set_input_script(&tx, 0, null, 0), true, &failures);
    check_int("cleared input script", tx.input_script_lens[0], 0, &failures);
    check_bool("restore input script", mgc_tx_set_input_script(&tx, 0, script, 3), true, &failures);
    check_bool("add output one", mgc_tx_add_output(&tx, 1000, out1, 3), true, &failures);
    check_bool("add output two", mgc_tx_add_output(&tx, 2000, out2, 3), true, &failures);
    check_int("input count", tx.in_count, 1, &failures);
    check_int("output count", tx.out_count, 2, &failures);

    int full_len = 0;
    char* full = mgc_tx_serialize(&tx, true, &full_len);
    check_bool("serialize with scripts", full != null && full_len > 0, true, &failures);
    if (full != null) {
        MgcTx decoded;
        mgc_tx_init(&decoded);
        check_bool("deserialize", mgc_tx_deserialize(full, full_len, &decoded), true, &failures);

        int round_len = 0;
        char* round = mgc_tx_serialize(&decoded, true, &round_len);
        check_int("roundtrip length", round_len, full_len, &failures);
        if (round != null) {
            check_bool("roundtrip bytes", mgc_equal(full, round, full_len), true, &failures);
            free(round);
        } else {
            check_bool("roundtrip bytes", false, true, &failures);
        }
        check_int("decoded inputs", decoded.in_count, 1, &failures);
        check_int("decoded outputs", decoded.out_count, 2, &failures);
        check_int("decoded output value", decoded.output_values[1], 2000, &failures);
        char* decoded_script = mgc_tx_in_script(&decoded, 0);
        check_bool("decoded script", decoded_script != null && mgc_equal(decoded_script, script, 3), true, &failures);

        check_bool("truncated rejected", mgc_tx_deserialize(full, full_len - 1, &decoded), false, &failures);
        char* trailing = alloc<char>(full_len + 1);
        if (trailing != null) {
            mgc_copy(trailing, full, full_len);
            *(trailing + full_len) = cast<char>(0);
            check_bool("trailing rejected", mgc_tx_deserialize(trailing, full_len + 1, &decoded), false, &failures);
            free(trailing);
        } else {
            check_bool("trailing rejected", false, true, &failures);
        }

        mgc_sha256d_raw(full, full_len, expected);
        check_bool("txid", mgc_tx_txid(&tx, tid), true, &failures);
        check_bool("txid is hash of full serialization", mgc_equal(tid, expected, 32), true, &failures);
        mgc_sha256d_raw(full, full_len, full_digest);
        check_bool("txid matches full hash", mgc_equal(tid, full_digest, 32), true, &failures);

        tx.output_values[0] = 1500;
        int changed_len = 0;
        char* changed = mgc_tx_serialize(&tx, true, &changed_len);
        if (changed != null) {
            mgc_sha256d_raw(changed, changed_len, expected);
            check_bool("changed txid", mgc_tx_txid(&tx, tid2), true, &failures);
            check_bool("changed txid matches hash", mgc_equal(tid2, expected, 32), true, &failures);
            check_bool("output value changes txid", mgc_equal(tid, tid2, 32), false, &failures);
            free(changed);
        } else {
            check_bool("serialize after value change", false, true, &failures);
        }

        char* other_script = alloc<char>(3);
        if (other_script != null) {
            mgc_copy(other_script, out2, 3);
            check_bool("replace input script", mgc_tx_set_input_script(&tx, 0, other_script, 3), true, &failures);
            check_bool("scriptSig changes txid", mgc_tx_txid(&tx, tid2), true, &failures);
            check_bool("scriptSig affects txid", mgc_equal(tid, tid2, 32), false, &failures);
            free(other_script);
        } else {
            check_bool("scriptSig affects txid", false, true, &failures);
        }
        mgc_tx_free(&decoded);
        free(full);
    }

    mgc_tx_free(&tx);
    free(full_digest);
    free(expected);
    free(tid2);
    free(tid);
    free(out2);
    free(out1);
    free(script);
    free(prev);
    return test_report("test_tx", failures);
}
