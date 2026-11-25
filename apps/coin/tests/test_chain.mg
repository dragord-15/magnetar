// Chain tests: deterministic genesis, fast appends and a work-winning fork with reorg.

use "../lib/mining.mg";
use "test_common.mg";

fn main() -> int {
    int failures = 0;
    MgcUtxoSet set;
    MgcUtxoSet other_set;
    MgcChain chain;
    MgcChain other;
    check_bool("utxo init", mgc_utxo_init(&set, 64), true, &failures);
    check_bool("other utxo init", mgc_utxo_init(&other_set, 64), true, &failures);
    check_bool("chain init", mgc_chain_init(&chain, MGC_NETWORK_REGTEST, 16, &set), true, &failures);
    check_bool("other chain init", mgc_chain_init(&other, MGC_NETWORK_REGTEST, 16, &other_set), true, &failures);

    check_int("empty height", mgc_chain_height(&chain), -1, &failures);
    check_bool("empty tip hash", mgc_chain_tip_hash(&chain, null), false, &failures);
    check_bool("add genesis", mgc_chain_add_genesis(&chain), true, &failures);
    check_bool("add other genesis", mgc_chain_add_genesis(&other), true, &failures);
    string genesis_hex = crypto_hex_encode(chain.hashes, 32);
    check_string("genesis hash pinned", genesis_hex, mgc_genesis_hash(MGC_NETWORK_REGTEST), &failures);
    free(cast<char*>(genesis_hex));
    check_int("genesis count", mgc_chain_count(&chain), 1, &failures);
    check_int("genesis height", mgc_chain_height(&chain), 0, &failures);
    check_int("genesis at height", mgc_chain_at_height(&chain, 0), 0, &failures);
    check_bool("genesis block", mgc_chain_best_block(&chain) != null, true, &failures);
    check_int("genesis utxo", mgc_utxo_count(&set), 1, &failures);
    check_int("expected bits", mgc_chain_expected_bits(&chain), mgc_genesis_bits(MGC_NETWORK_REGTEST), &failures);

    char* h1 = alloc<char>(32);
    char* h2 = alloc<char>(32);
    char* h_a2 = alloc<char>(32);
    char* h_b3 = alloc<char>(32);
    char* tip_hash = alloc<char>(32);
    char* a3_txid = alloc<char>(32);
    char* b4_txid = alloc<char>(32);
    char* h160a = alloc<char>(20);
    char* h160b = alloc<char>(20);
    char* script_a = alloc<char>(25);
    char* script_b = alloc<char>(25);
    char* h160x = alloc<char>(20);
    char* script_x = alloc<char>(25);
    if (h1 == null || h2 == null || h_a2 == null || h_b3 == null || tip_hash == null ||
        a3_txid == null || b4_txid == null || h160a == null || h160b == null ||
        script_a == null || script_b == null || h160x == null || script_x == null) {
        print_str("FAIL alloc\n");
        return 1;
    }
    check_bool("tip hash genesis", mgc_chain_tip_hash(&chain, h1), true, &failures);
    check_bool("other tip hash", mgc_chain_tip_hash(&other, h2), true, &failures);
    check_bool("deterministic genesis", mgc_equal(h1, h2, 32), true, &failures);
    check_int("find genesis", mgc_chain_find(&chain, h1), 0, &failures);
    check_bool("find missing", mgc_chain_find(&chain, h160a) < 0, true, &failures);

    mgc_zero(h160a, 20);
    for (int i = 0; i < 20; i = i + 1) { *(h160b + i) = cast<char>(0x11); }
    mgc_script_p2pkh(h160a, script_a);
    mgc_script_p2pkh(h160b, script_b);

    MgcMempool mp;
    check_bool("mempool init", mgc_mempool_init(&mp, 8), true, &failures);

    int attempts = 0;
    bool reorg = true;
    for (int i = 0; i < 3; i = i + 1) {
        MgcBlock* b = alloc<MgcBlock>(1);
        if (b == null) { print_str("FAIL alloc\n"); return 1; }
        mgc_zero(h160x, 20);
        *(h160x + 0) = cast<char>(i + 1);
        mgc_script_p2pkh(h160x, script_x);
        check_bool("build block", mgc_mining_build_block(&chain, &mp, script_x, 25, b), true, &failures);
        check_bool("mine block", mgc_mining_mine(b, 100000, &attempts), true, &failures);
        check_bool("attempts counted", attempts > 0, true, &failures);
        if (i == 1) { check_bool("save a2 hash", mgc_block_hash(b, h_a2), true, &failures); }
        check_bool("add block", mgc_chain_add_block(&chain, b, &reorg), true, &failures);
        check_bool("no reorg append", reorg, false, &failures);
        check_int("height after append", mgc_chain_height(&chain), i + 1, &failures);
        check_int("utxo after append", mgc_utxo_count(&set), i + 2, &failures);
    }
    int a3_index = mgc_chain_at_height(&chain, 3);
    MgcBlock* a3 = mgc_chain_get(&chain, a3_index);
    check_bool("a3 found", a3 != null, true, &failures);
    check_bool("a3 coinbase txid", mgc_block_txid(a3, 0, a3_txid), true, &failures);
    check_bool("a3 still live", mgc_utxo_exists(&set, a3_txid, 0), true, &failures);

    MgcBlock* fb1 = alloc<MgcBlock>(1);
    MgcBlock* fb2 = alloc<MgcBlock>(1);
    if (fb1 == null || fb2 == null) { print_str("FAIL alloc\n"); return 1; }
    mgc_zero(h160x, 20);
    *(h160x + 0) = cast<char>(4);
    mgc_script_p2pkh(h160x, script_x);
    check_bool("build fork1", mgc_mining_build_block(&chain, &mp, script_x, 25, fb1), true, &failures);
    mgc_copy(fb1.prev_block, h_a2, 32);
    check_bool("mine fork1", mgc_mining_mine(fb1, 100000, &attempts), true, &failures);
    check_bool("fork1 hash", mgc_block_hash(fb1, h_b3), true, &failures);
    check_bool("add fork1", mgc_chain_add_block(&chain, fb1, &reorg), true, &failures);
    check_bool("no reorg on tie", reorg, false, &failures);
    check_int("height unchanged on tie", mgc_chain_height(&chain), 3, &failures);
    check_bool("a3 live after tie", mgc_utxo_exists(&set, a3_txid, 0), true, &failures);

    mgc_zero(h160x, 20);
    *(h160x + 0) = cast<char>(5);
    mgc_script_p2pkh(h160x, script_x);
    check_bool("build fork2", mgc_mining_build_block(&chain, &mp, script_x, 25, fb2), true, &failures);
    mgc_copy(fb2.prev_block, h_b3, 32);
    check_bool("mine fork2", mgc_mining_mine(fb2, 100000, &attempts), true, &failures);
    check_bool("fork2 hash", mgc_block_hash(fb2, tip_hash), true, &failures);
    check_bool("add fork2", mgc_chain_add_block(&chain, fb2, &reorg), true, &failures);
    check_bool("reorg triggered", reorg, true, &failures);
    check_int("height after reorg", mgc_chain_height(&chain), 4, &failures);
    check_bool("tip after reorg", mgc_chain_tip_hash(&chain, h1), true, &failures);
    check_bool("tip is fork2", mgc_equal(h1, tip_hash, 32), true, &failures);
    check_int("utxo after reorg", mgc_utxo_count(&set), 5, &failures);
    check_bool("a3 spent by reorg", mgc_utxo_exists(&set, a3_txid, 0), false, &failures);
    check_bool("fork3 at height", mgc_chain_at_height(&chain, 3) >= 0, true, &failures);
    check_int("fork tip height", mgc_chain_at_height(&chain, 4), 5, &failures);
    MgcBlock* f2 = mgc_chain_best_block(&chain);
    check_bool("fork2 coinbase txid", mgc_block_txid(f2, 0, b4_txid), true, &failures);
    check_bool("fork2 output live", mgc_utxo_exists(&set, b4_txid, 0), true, &failures);
    check_int("chain count", mgc_chain_count(&chain), 6, &failures);

    check_int("get genesis", mgc_chain_get(&chain, 0) != null ? 1 : 0, 1, &failures);
    check_bool("get out of range", mgc_chain_get(&chain, 99) == null, true, &failures);
    check_bool("next timestamp sane", mgc_chain_next_timestamp(&chain) > 1760000000, true, &failures);

    mgc_mempool_free(&mp);
    mgc_chain_free(&other);
    mgc_chain_free(&chain);
    mgc_utxo_free(&other_set);
    mgc_utxo_free(&set);
    free(script_x);
    free(h160x);
    free(script_b);
    free(script_a);
    free(h160b);
    free(h160a);
    free(b4_txid);
    free(a3_txid);
    free(tip_hash);
    free(h_b3);
    free(h_a2);
    free(h2);
    free(h1);
    return test_report("test_chain", failures);
}
