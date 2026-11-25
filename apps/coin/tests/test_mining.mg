// Mining tests: block template from a mempool tx, reward and nonce search.

use "../lib/mining.mg";
use "test_common.mg";

fn main() -> int {
    int failures = 0;
    MgcUtxoSet set;
    MgcChain chain;
    MgcMempool mp;
    check_bool("utxo init", mgc_utxo_init(&set, 32), true, &failures);
    check_bool("chain init", mgc_chain_init(&chain, MGC_NETWORK_REGTEST, 8, &set), true, &failures);
    check_bool("mempool init", mgc_mempool_init(&mp, 8), true, &failures);
    check_bool("genesis", mgc_chain_add_genesis(&chain), true, &failures);

    char* prev_tid = alloc<char>(32);
    char* script = alloc<char>(25);
    char* payout = alloc<char>(25);
    char* dummy = alloc<char>(1);
    char* h160 = alloc<char>(20);
    char* tip = alloc<char>(32);
    char* hash = alloc<char>(32);
    if (prev_tid == null || script == null || payout == null || dummy == null ||
        h160 == null || tip == null || hash == null) {
        print_str("FAIL alloc\n");
        return 1;
    }
    for (int i = 0; i < 32; i = i + 1) { *(prev_tid + i) = cast<char>(i + 1); }
    mgc_zero(h160, 20);
    mgc_script_p2pkh(h160, script);
    *(h160 + 0) = cast<char>(1);
    mgc_script_p2pkh(h160, payout);
    *dummy = cast<char>(0);
    check_bool("prev utxo", mgc_utxo_add(&set, prev_tid, 0, 1000, script, 25, 0, false), true, &failures);

    MgcTx spend;
    mgc_tx_init(&spend);
    check_bool("spend input", mgc_tx_add_input(&spend, prev_tid, 0, dummy, 1, 4294967295), true, &failures);
    check_bool("spend output", mgc_tx_add_output(&spend, 700, script, 25), true, &failures);
    check_bool("mempool add", mgc_mempool_add(&mp, &spend), true, &failures);
    int fee = -1;
    check_bool("fee from utxo", mgc_consensus_tx_fee(&spend, &set, &fee), true, &failures);
    check_int("fee value", fee, 300, &failures);
    mgc_tx_free(&spend);

    MgcBlock block;
    check_bool("build block", mgc_mining_build_block(&chain, &mp, payout, 25, &block), true, &failures);
    check_int("tx count", block.tx_count, 2, &failures);
    check_int("coinbase reward", block.txs[0].output_values[0], mgc_consensus_subsidy(MGC_NETWORK_REGTEST, 1) + 300, &failures);
    check_bool("tip hash", mgc_chain_tip_hash(&chain, tip), true, &failures);
    check_bool("prev block", mgc_equal(block.prev_block, tip, 32), true, &failures);
    check_int("bits", block.bits, mgc_chain_expected_bits(&chain), &failures);

    int attempts = 0;
    check_bool("mine", mgc_mining_mine(&block, 100000, &attempts), true, &failures);
    check_bool("attempts", attempts > 0, true, &failures);
    check_bool("hash block", mgc_block_hash(&block, hash), true, &failures);
    check_bool("pow valid", mgc_pow_check(hash, block.bits), true, &failures);

    mgc_block_free(&block);
    mgc_mempool_free(&mp);
    mgc_chain_free(&chain);
    mgc_utxo_free(&set);
    free(hash);
    free(tip);
    free(h160);
    free(dummy);
    free(payout);
    free(script);
    free(prev_tid);
    return test_report("test_mining", failures);
}
