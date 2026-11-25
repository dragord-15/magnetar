// Magnetar Coin — tests for the custom SIGHASH_ALL digest.

use "../lib/sighash.mg";
use "../lib/params.mg";
use "test_common.mg";

fn main() -> int {
    int failures = 0;
    char* prev_txid = alloc<char>(32);
    char* prev_script = alloc<char>(3);
    char* out1 = alloc<char>(3);
    char* out2 = alloc<char>(3);
    char* d1 = alloc<char>(32);
    char* d2 = alloc<char>(32);
    char* d3 = alloc<char>(32);
    char* d4 = alloc<char>(32);
    int* prev_values = alloc<int>(1);
    char** prev_scripts = alloc<char*>(1);
    int* prev_script_lens = alloc<int>(1);
    if (prev_txid == null || prev_script == null || out1 == null || out2 == null ||
        d1 == null || d2 == null || d3 == null || d4 == null ||
        prev_values == null || prev_scripts == null || prev_script_lens == null) {
        print_str("FAIL alloc\n");
        return 1;
    }
    for (int i = 0; i < 32; i = i + 1) { *(prev_txid + i) = cast<char>(i + 1); }
    *(prev_script + 0) = cast<char>(0x76);
    *(prev_script + 1) = cast<char>(0xa9);
    *(prev_script + 2) = cast<char>(0x14);
    *(out1 + 0) = cast<char>(0x51);
    *(out1 + 1) = cast<char>(0x20);
    *(out1 + 2) = cast<char>(0x01);
    *(out2 + 0) = cast<char>(0x51);
    *(out2 + 1) = cast<char>(0x20);
    *(out2 + 2) = cast<char>(0x02);
    prev_values[0] = 5000;
    prev_scripts[0] = prev_script;
    prev_script_lens[0] = 3;

    MgcTx tx;
    mgc_tx_init(&tx);
    check_bool("add input", mgc_tx_add_input(&tx, prev_txid, 7, null, 0, 4294967295), true, &failures);
    check_bool("add output 1", mgc_tx_add_output(&tx, 1000, out1, 3), true, &failures);
    check_bool("add output 2", mgc_tx_add_output(&tx, 2000, out2, 3), true, &failures);

    int chain = mgc_chain_id(MGC_NETWORK_REGTEST);
    int other_chain = mgc_chain_id(MGC_NETWORK_TEST);
    check_bool("sighash ok", mgc_sighash(&tx, 0, prev_values, prev_scripts, prev_script_lens, chain, d1), true, &failures);
    bool nonzero = false;
    for (int i = 0; i < 32; i = i + 1) {
        if ((cast<int>(*(d1 + i)) & 255) != 0) { nonzero = true; }
    }
    check_bool("digest nonzero", nonzero, true, &failures);

    prev_values[0] = 9000;
    check_bool("sighash value ok", mgc_sighash(&tx, 0, prev_values, prev_scripts, prev_script_lens, chain, d2), true, &failures);
    check_bool("value changes digest", mgc_equal(d1, d2, 32), false, &failures);

    prev_values[0] = 5000;
    check_bool("sighash repeat ok", mgc_sighash(&tx, 0, prev_values, prev_scripts, prev_script_lens, chain, d3), true, &failures);
    check_bool("same inputs same digest", mgc_equal(d1, d3, 32), true, &failures);

    check_bool("sighash chain ok", mgc_sighash(&tx, 0, prev_values, prev_scripts, prev_script_lens, other_chain, d4), true, &failures);
    check_bool("chain id changes digest", mgc_equal(d1, d4, 32), false, &failures);

    check_bool("bad input index", mgc_sighash(&tx, 1, prev_values, prev_scripts, prev_script_lens, chain, d2), false, &failures);
    check_bool("negative input index", mgc_sighash(&tx, -1, prev_values, prev_scripts, prev_script_lens, chain, d2), false, &failures);
    check_bool("null values", mgc_sighash(&tx, 0, null, prev_scripts, prev_script_lens, chain, d2), false, &failures);
    check_bool("null out", mgc_sighash(&tx, 0, prev_values, prev_scripts, prev_script_lens, chain, null), false, &failures);

    char* changed_script = tx.output_scripts[1];
    *(changed_script + 2) = cast<char>(0x03);
    check_bool("sighash output ok", mgc_sighash(&tx, 0, prev_values, prev_scripts, prev_script_lens, chain, d2), true, &failures);
    check_bool("output changes digest", mgc_equal(d1, d2, 32), false, &failures);

    mgc_tx_free(&tx);
    free(prev_script_lens);
    free(prev_scripts);
    free(prev_values);
    free(d4);
    free(d3);
    free(d2);
    free(d1);
    free(out2);
    free(out1);
    free(prev_script);
    free(prev_txid);
    return test_report("test_sighash", failures);
}
