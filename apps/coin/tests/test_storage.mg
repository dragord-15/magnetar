// Phase 4 storage tests: atomic binary files, UTXO snapshot, block log reload, lock and cookie.

use "../lib/storage.mg";
use "../lib/mining.mg";
use "../lib/mempool.mg";
use "test_common.mg";

fn main() -> int {
    int failures = 0;
    string datadir = "/tmp/mgc_storage_test";

    sys_unlink(mgc_storage_path(datadir, "blob.bin"));
    sys_unlink(mgc_storage_path(datadir, "chainstate/utxo.dat"));
    sys_unlink(mgc_storage_path(datadir, "blocks/blk00000.dat"));
    sys_unlink(mgc_storage_path(datadir, ".cookie"));
    sys_unlink(mgc_storage_path(datadir, ".lock"));

    check_bool("init datadir", mgc_storage_init_datadir(datadir), true, &failures);
    check_bool("init datadir again", mgc_storage_init_datadir(datadir), true, &failures);

    char* blob = alloc<char>(8);
    if (blob == null) { print_str("FAIL alloc\n"); return 1; }
    *(blob + 0) = cast<char>(0x41);
    *(blob + 1) = cast<char>(0x00);
    *(blob + 2) = cast<char>(0x42);
    *(blob + 3) = cast<char>(0x00);
    *(blob + 4) = cast<char>(0xff);
    *(blob + 5) = cast<char>(0x10);
    *(blob + 6) = cast<char>(0x00);
    *(blob + 7) = cast<char>(0x43);
    string blob_path = mgc_storage_path(datadir, "blob.bin");
    check_bool("atomic write", mgc_storage_atomic_write(blob_path, blob, 8), true, &failures);
    char* blob_out = null;
    int blob_len = 0;
    check_bool("read blob", mgc_storage_read(blob_path, &blob_out, &blob_len), true, &failures);
    check_int("blob length", blob_len, 8, &failures);
    if (blob_out != null) {
        check_bool("blob bytes", mgc_equal(blob, blob_out, 8), true, &failures);
        free(blob_out);
    } else {
        check_bool("blob bytes", false, true, &failures);
    }

    MgcUtxoSet set;
    check_bool("utxo init", mgc_utxo_init(&set, 32), true, &failures);
    char* txid = alloc<char>(32);
    char* script = alloc<char>(5);
    if (txid == null || script == null) { print_str("FAIL alloc\n"); return 1; }
    for (int i = 0; i < 32; i = i + 1) { *(txid + i) = cast<char>(i + 1); }
    *(script + 0) = cast<char>(0x51);
    *(script + 1) = cast<char>(0x00);
    *(script + 2) = cast<char>(0x52);
    *(script + 3) = cast<char>(0x00);
    *(script + 4) = cast<char>(0x53);
    check_bool("utxo add one", mgc_utxo_add(&set, txid, 0, 100000, script, 5, 3, true), true, &failures);
    check_bool("utxo add two", mgc_utxo_add(&set, txid, 1, 777, script, 5, 4, false), true, &failures);
    check_bool("save utxo", mgc_storage_save_utxo(datadir, &set), true, &failures);

    MgcUtxoSet restored;
    check_bool("restored init", mgc_utxo_init(&restored, 32), true, &failures);
    check_bool("load utxo", mgc_storage_load_utxo(datadir, &restored), true, &failures);
    check_int("utxo count", mgc_utxo_count(&restored), 2, &failures);
    MgcUtxo u;
    check_bool("get first", mgc_utxo_get(&restored, txid, 0, &u), true, &failures);
    if (u.script != null) {
        check_int("value one", u.value, 100000, &failures);
        check_int("script len one", u.script_len, 5, &failures);
        check_bool("script bytes one", mgc_equal(u.script, script, 5), true, &failures);
        check_int("height one", u.height, 3, &failures);
        check_bool("coinbase one", u.coinbase, true, &failures);
        mgc_utxo_result_free(&u);
    } else {
        check_bool("script bytes one", false, true, &failures);
    }
    check_bool("get second", mgc_utxo_get(&restored, txid, 1, &u), true, &failures);
    if (u.script != null) {
        check_int("value two", u.value, 777, &failures);
        check_int("script len two", u.script_len, 5, &failures);
        check_bool("script bytes two", mgc_equal(u.script, script, 5), true, &failures);
        check_int("height two", u.height, 4, &failures);
        check_bool("coinbase two", u.coinbase, false, &failures);
        mgc_utxo_result_free(&u);
    } else {
        check_bool("script bytes two", false, true, &failures);
    }

    MgcUtxoSet cset;
    MgcChain chain;
    check_bool("chain utxo init", mgc_utxo_init(&cset, 64), true, &failures);
    check_bool("chain init", mgc_chain_init(&chain, MGC_NETWORK_REGTEST, 16, &cset), true, &failures);
    check_bool("genesis", mgc_chain_add_genesis(&chain), true, &failures);

    MgcMempool mp;
    check_bool("mempool init", mgc_mempool_init(&mp, 8), true, &failures);
    char* h160 = alloc<char>(20);
    char* payout = alloc<char>(25);
    if (h160 == null || payout == null) { print_str("FAIL alloc\n"); return 1; }
    mgc_zero(h160, 20);
    *(h160 + 0) = cast<char>(0x42);
    mgc_script_p2pkh(h160, payout);

    MgcBlock* mined = alloc<MgcBlock>(1);
    if (mined == null) { print_str("FAIL alloc\n"); return 1; }
    check_bool("build block", mgc_mining_build_block(&chain, &mp, payout, 25, mined), true, &failures);
    int attempts = 0;
    check_bool("mine block", mgc_mining_mine(mined, 100000, &attempts), true, &failures);

    MgcBlock* genesis = mgc_chain_get(&chain, 0);
    check_bool("append genesis", mgc_storage_append_block(datadir, genesis), true, &failures);
    check_bool("append mined", mgc_storage_append_block(datadir, mined), true, &failures);

    bool reorg = false;
    check_bool("add mined to chain", mgc_chain_add_block(&chain, mined, &reorg), true, &failures);
    check_int("chain one height", mgc_chain_height(&chain), 1, &failures);

    MgcUtxoSet cset2;
    MgcChain chain2;
    check_bool("chain2 utxo init", mgc_utxo_init(&cset2, 64), true, &failures);
    check_bool("chain2 init", mgc_chain_init(&chain2, MGC_NETWORK_REGTEST, 16, &cset2), true, &failures);
    check_bool("chain2 genesis", mgc_chain_add_genesis(&chain2), true, &failures);

    int loaded = mgc_storage_load_blocks(datadir, &chain2);
    check_int("loaded blocks", loaded, 1, &failures);
    check_int("reloaded height", mgc_chain_height(&chain2), 1, &failures);
    char* tip1 = alloc<char>(32);
    char* tip2 = alloc<char>(32);
    if (tip1 == null || tip2 == null) { print_str("FAIL alloc\n"); return 1; }
    check_bool("tip one", mgc_chain_tip_hash(&chain, tip1), true, &failures);
    check_bool("tip two", mgc_chain_tip_hash(&chain2, tip2), true, &failures);
    check_bool("tip matches", mgc_equal(tip1, tip2, 32), true, &failures);

    int fd = mgc_storage_lock(datadir);
    check_bool("lock", fd >= 0, true, &failures);
    if (fd >= 0) { sys_close(fd); }

    string cookie = mgc_storage_write_cookie(datadir);
    check_int("cookie length", len(cookie), 32, &failures);
    bool hex_ok = true;
    char* cp = cast<char*>(cookie);
    for (int i = 0; i < len(cookie); i = i + 1) {
        int c = cast<int>(*(cp + i)) & 255;
        bool is_hex = (c >= 48 && c <= 57) || (c >= 97 && c <= 102);
        if (!is_hex) { hex_ok = false; }
    }
    check_bool("cookie hex", hex_ok, true, &failures);
    char* cookie_out = null;
    int cookie_len = 0;
    if (mgc_storage_read(mgc_storage_path(datadir, ".cookie"), &cookie_out, &cookie_len)) {
        check_int("cookie file length", cookie_len, 32, &failures);
        check_bool("cookie file bytes", mgc_equal(cookie_out, cp, 32), true, &failures);
        free(cookie_out);
    } else {
        check_bool("cookie file read", false, true, &failures);
    }

    mgc_mempool_free(&mp);
    mgc_chain_free(&chain2);
    mgc_chain_free(&chain);
    mgc_utxo_free(&cset2);
    mgc_utxo_free(&cset);
    mgc_utxo_free(&restored);
    mgc_utxo_free(&set);
    free(tip2);
    free(tip1);
    free(payout);
    free(h160);
    free(script);
    free(txid);
    free(blob);
    return test_report("test_storage", failures);
}
