// Consensus unit tests: subsidy halving, fee accounting and coinbase maturity.

use "../lib/consensus.mg";
use "test_common.mg";

fn main() -> int {
    int failures = 0;
    int interval = mgc_halving_interval(MGC_NETWORK_REGTEST);
    check_int("halving interval", interval, 150, &failures);
    check_int("subsidy genesis", mgc_consensus_subsidy(MGC_NETWORK_REGTEST, 0), 5000000000, &failures);
    check_int("subsidy pre halving", mgc_consensus_subsidy(MGC_NETWORK_REGTEST, interval - 1), 5000000000, &failures);
    check_int("subsidy first halving", mgc_consensus_subsidy(MGC_NETWORK_REGTEST, interval), 2500000000, &failures);
    check_int("subsidy after first", mgc_consensus_subsidy(MGC_NETWORK_REGTEST, interval + 1), 2500000000, &failures);
    check_int("subsidy second halving", mgc_consensus_subsidy(MGC_NETWORK_REGTEST, 2 * interval), 1250000000, &failures);
    check_int("subsidy exhausted", mgc_consensus_subsidy(MGC_NETWORK_REGTEST, 40 * interval), 0, &failures);
    check_int("subsidy main first", mgc_consensus_subsidy(MGC_NETWORK_MAIN, mgc_halving_interval(MGC_NETWORK_MAIN)), 2500000000, &failures);

    MgcUtxoSet set;
    check_bool("utxo init", mgc_utxo_init(&set, 32), true, &failures);
    char* zero32 = alloc<char>(32);
    char* tid_a = alloc<char>(32);
    char* tid_b = alloc<char>(32);
    char* script = alloc<char>(25);
    char* dummy = alloc<char>(1);
    if (zero32 == null || tid_a == null || tid_b == null || script == null || dummy == null) {
        print_str("FAIL alloc\n");
        return 1;
    }
    mgc_zero(zero32, 32);
    for (int i = 0; i < 32; i = i + 1) {
        *(tid_a + i) = cast<char>(i + 1);
        *(tid_b + i) = cast<char>(200 - i);
    }
    mgc_script_p2pkh(zero32, script);
    *dummy = cast<char>(0);

    check_bool("add prev a0", mgc_utxo_add(&set, tid_a, 0, 1000, script, 25, 0, true), true, &failures);
    check_bool("add prev a1", mgc_utxo_add(&set, tid_a, 1, 500, script, 25, 5, false), true, &failures);
    check_bool("add prev b0", mgc_utxo_add(&set, tid_b, 0, 2000, script, 25, 0, true), true, &failures);

    MgcTx tx;
    mgc_tx_init(&tx);
    check_bool("tx input a0", mgc_tx_add_input(&tx, tid_a, 0, dummy, 1, 4294967295), true, &failures);
    check_bool("tx input a1", mgc_tx_add_input(&tx, tid_a, 1, dummy, 1, 4294967295), true, &failures);
    check_bool("tx output 1200", mgc_tx_add_output(&tx, 1200, script, 25), true, &failures);
    int fee = -1;
    check_bool("fee ok", mgc_consensus_tx_fee(&tx, &set, &fee), true, &failures);
    check_int("fee value", fee, 300, &failures);
    mgc_tx_free(&tx);

    MgcTx duplicate;
    mgc_tx_init(&duplicate);
    mgc_tx_add_input(&duplicate, tid_a, 0, dummy, 1, 4294967295);
    mgc_tx_add_input(&duplicate, tid_a, 0, dummy, 1, 4294967295);
    mgc_tx_add_output(&duplicate, 1000, script, 25);
    int dup_fee = -1;
    check_bool("duplicate input fee rejected", mgc_consensus_tx_fee(&duplicate, &set, &dup_fee), false, &failures);
    check_bool("duplicate input verify rejected", mgc_consensus_verify_tx(&duplicate, &set, 20, MGC_NETWORK_REGTEST, mgc_chain_id(MGC_NETWORK_REGTEST), &dup_fee), false, &failures);
    mgc_tx_free(&duplicate);

    MgcTx too_big;
    mgc_tx_init(&too_big);
    mgc_tx_add_input(&too_big, tid_a, 0, dummy, 1, 4294967295);
    mgc_tx_add_output(&too_big, 2000, script, 25);
    int fee2 = -1;
    check_bool("fee underflow rejected", mgc_consensus_tx_fee(&too_big, &set, &fee2), false, &failures);
    mgc_tx_free(&too_big);

    MgcTx immature;
    mgc_tx_init(&immature);
    char* pub = alloc<char>(33);
    char* sig = alloc<char>(8);
    if (pub == null || sig == null) { print_str("FAIL alloc\n"); return 1; }
    *pub = cast<char>(2);
    for (int i = 1; i < 33; i = i + 1) { *(pub + i) = cast<char>(i); }
    for (int i = 0; i < 8; i = i + 1) { *(sig + i) = cast<char>(i + 1); }
    int slen = 0;
    char* script_sig = alloc<char>(128);
    if (script_sig == null) { print_str("FAIL alloc\n"); return 1; }
    check_bool("sig script build", mgc_script_sig(sig, 8, pub, 33, script_sig, &slen), true, &failures);
    check_bool("immature input", mgc_tx_add_input(&immature, tid_b, 0, script_sig, slen, 4294967295), true, &failures);
    check_bool("immature output", mgc_tx_add_output(&immature, 1000, script, 25), true, &failures);
    int fee3 = -1;
    check_bool("immature verify rejected", mgc_consensus_verify_tx(&immature, &set, 9, MGC_NETWORK_REGTEST, mgc_chain_id(MGC_NETWORK_REGTEST), &fee3), false, &failures);

    MgcUtxo prev;
    check_bool("get coinbase prev", mgc_utxo_get(&set, tid_b, 0, &prev), true, &failures);
    check_int("prev height", prev.height, 0, &failures);
    check_bool("prev coinbase", prev.coinbase, true, &failures);
    int mat = mgc_coinbase_maturity(MGC_NETWORK_REGTEST);
    check_int("maturity constant", mat, 10, &failures);
    check_bool("immature at 9", prev.height + mat > 9, true, &failures);
    check_bool("mature at 10", prev.height + mat > 10, false, &failures);
    mgc_utxo_result_free(&prev);

    MgcTx cb;
    mgc_tx_init(&cb);
    mgc_tx_add_input(&cb, zero32, 4294967295, dummy, 1, 4294967295);
    mgc_tx_add_output(&cb, 100, script, 25);
    int fee4 = -1;
    check_bool("coinbase fee rejected", mgc_consensus_tx_fee(&cb, &set, &fee4), false, &failures);
    check_bool("coinbase verify rejected", mgc_consensus_verify_tx(&cb, &set, 20, MGC_NETWORK_REGTEST, mgc_chain_id(MGC_NETWORK_REGTEST), &fee4), false, &failures);
    mgc_tx_free(&cb);

    mgc_tx_free(&immature);
    mgc_utxo_free(&set);
    free(script_sig);
    free(pub);
    free(sig);
    free(dummy);
    free(script);
    free(tid_b);
    free(tid_a);
    free(zero32);
    return test_report("test_consensus", failures);
}
