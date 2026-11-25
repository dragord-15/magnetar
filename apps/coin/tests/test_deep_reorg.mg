// Deep reorg test: a 288-block deep fork must replace the old best chain.

use "../lib/mining.mg";
use "test_common.mg";

fn main() -> int {
    int failures = 0;
    MgcUtxoSet set;
    MgcChain chain;
    MgcMempool mp;
    if (!mgc_utxo_init(&set, 1024)) { print_str("FAIL utxo init\n"); return 1; }
    if (!mgc_chain_init(&chain, MGC_NETWORK_REGTEST, 1024, &set)) { print_str("FAIL chain init\n"); return 1; }
    if (!mgc_mempool_init(&mp, 8)) { print_str("FAIL mempool init\n"); return 1; }
    check_bool("genesis", mgc_chain_add_genesis(&chain), true, &failures);

    char* h160 = alloc<char>(20);
    char* script = alloc<char>(25);
    char* fork_script = alloc<char>(25);
    char* fork_hash = alloc<char>(32);
    if (h160 == null || script == null || fork_script == null || fork_hash == null) { print_str("FAIL alloc\n"); return 1; }
    mgc_zero(h160, 20);
    mgc_script_p2pkh(h160, script);
    *(h160 + 0) = cast<char>(9);
    mgc_script_p2pkh(h160, fork_script);

    int attempts = 0;
    bool reorg = false;
    for (int height = 1; height <= 290; height = height + 1) {
        MgcBlock* b = alloc<MgcBlock>(1);
        if (b == null) { print_str("FAIL alloc\n"); return 1; }
        check_bool("build main", mgc_mining_build_block(&chain, &mp, script, 25, b), true, &failures);
        check_bool("mine main", mgc_mining_mine(b, 1000000, &attempts), true, &failures);
        if (!mgc_chain_add_block(&chain, b, &reorg)) {
            print_str("FAIL add main\n");
            return 1;
        }
    }
    check_int("main height", mgc_chain_height(&chain), 290, &failures);
    check_int("main utxo", mgc_utxo_count(&set), 291, &failures);
    int main_tip = chain.best_tip;
    int fork_parent = mgc_chain_at_height(&chain, 2);
    int old_height_three = mgc_chain_at_height(&chain, 3);
    check_bool("fork parent found", fork_parent >= 0, true, &failures);
    check_bool("height three found", old_height_three >= 0, true, &failures);

    int fork_tip = fork_parent;
    for (int i = 0; i < 289; i = i + 1) {
        chain.best_tip = fork_tip;
        MgcBlock* b = alloc<MgcBlock>(1);
        if (b == null) { print_str("FAIL alloc\n"); return 1; }
        check_bool("build fork", mgc_mining_build_block(&chain, &mp, fork_script, 25, b), true, &failures);
        check_bool("mine fork", mgc_mining_mine(b, 1000000, &attempts), true, &failures);
        if (i == 288) { check_bool("fork tip hash", mgc_block_hash(b, fork_hash), true, &failures); }
        chain.best_tip = main_tip;
        int index = chain.count;
        check_bool("add fork", mgc_chain_add_block(&chain, b, &reorg), true, &failures);
        fork_tip = index;
        if (i < 288) { check_bool("no premature reorg", reorg, false, &failures); }
        else { check_bool("deep reorg triggered", reorg, true, &failures); }
    }

    check_int("fork height", mgc_chain_height(&chain), 291, &failures);
    check_bool("best tip is fork", mgc_chain_tip_hash(&chain, h160), true, &failures);
    check_bool("fork tip matches", mgc_equal(h160, fork_hash, 32), true, &failures);
    check_int("utxo after deep reorg", mgc_utxo_count(&set), 292, &failures);
    check_int("common ancestor kept", mgc_chain_at_height(&chain, 2), fork_parent, &failures);
    check_bool("old height three orphaned", mgc_chain_at_height(&chain, 3) != old_height_three, true, &failures);

    free(fork_hash);
    free(fork_script);
    free(script);
    free(h160);
    mgc_mempool_free(&mp);
    mgc_chain_free(&chain);
    mgc_utxo_free(&set);
    return test_report("test_deep_reorg", failures);
}
