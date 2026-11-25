// Tests for the bounded transaction mempool and its deep-copy semantics.

use "../lib/mempool.mg";
use "test_common.mg";

fn _mgc_test_mempool_make_tx(MgcTx* tx, int seed, int version, int locktime, char* prev_out) -> bool {
    mgc_tx_init(tx);
    tx.version = version;
    tx.locktime = locktime;
    char* in_script = alloc<char>(4);
    char* out_script = alloc<char>(3);
    char* out_script2 = alloc<char>(2);
    if (in_script == null || out_script == null || out_script2 == null) {
        if (in_script != null) { free(in_script); }
        if (out_script != null) { free(out_script); }
        if (out_script2 != null) { free(out_script2); }
        return false;
    }
    for (int i = 0; i < 32; i = i + 1) {
        *(prev_out + i) = cast<char>((seed + i * 13) & 255);
    }
    for (int i = 0; i < 4; i = i + 1) {
        *(in_script + i) = cast<char>((seed + 40 + i * 5) & 255);
    }
    for (int i = 0; i < 3; i = i + 1) {
        *(out_script + i) = cast<char>((seed + 60 + i * 7) & 255);
    }
    for (int i = 0; i < 2; i = i + 1) {
        *(out_script2 + i) = cast<char>((seed + 90 + i * 3) & 255);
    }
    bool ok = mgc_tx_add_input(tx, prev_out, seed, in_script, 4, 4294967295);
    ok = ok && mgc_tx_add_output(tx, seed * 1000, out_script, 3);
    ok = ok && mgc_tx_add_output(tx, seed * 500, out_script2, 2);
    free(in_script);
    free(out_script);
    free(out_script2);
    return ok;
}

fn main() -> int {
    int failures = 0;

    MgcMempool bad;
    check_bool("init null", mgc_mempool_init(null, 4), false, &failures);
    check_bool("init zero capacity", mgc_mempool_init(&bad, 0), false, &failures);
    check_int("count null mp", mgc_mempool_count(null), 0, &failures);
    check_bool("get null mp", mgc_mempool_get(null, 0) == null, true, &failures);
    mgc_mempool_free(null);
    mgc_mempool_clear(null);

    char* prev = alloc<char>(32);
    char* prev1 = alloc<char>(32);
    char* tid1 = alloc<char>(32);
    char* tid2 = alloc<char>(32);
    char* tid3 = alloc<char>(32);
    char* tid4 = alloc<char>(32);
    char* tid5 = alloc<char>(32);
    char* missing = alloc<char>(32);
    if (prev == null || prev1 == null || tid1 == null || tid2 == null || tid3 == null ||
        tid4 == null || tid5 == null || missing == null) {
        print_str("FAIL alloc test buffers\n");
        return 1;
    }
    for (int i = 0; i < 32; i = i + 1) {
        *(missing + i) = cast<char>((200 + i * 11) & 255);
    }

    MgcTx tx1;
    MgcTx tx2;
    MgcTx tx3;
    MgcTx tx4;
    MgcTx tx5;
    check_bool("build tx1", _mgc_test_mempool_make_tx(&tx1, 11, 2, 123456, prev1), true, &failures);
    check_bool("build tx2", _mgc_test_mempool_make_tx(&tx2, 211, 3, 222222, prev), true, &failures);
    check_bool("build tx3", _mgc_test_mempool_make_tx(&tx3, 307, 4, 333333, prev), true, &failures);
    check_bool("build tx4", _mgc_test_mempool_make_tx(&tx4, 401, 5, 444444, prev), true, &failures);
    check_bool("build tx5", _mgc_test_mempool_make_tx(&tx5, 503, 6, 555555, prev), true, &failures);
    check_bool("txid1", mgc_tx_txid(&tx1, tid1), true, &failures);
    check_bool("txid2", mgc_tx_txid(&tx2, tid2), true, &failures);
    check_bool("txid3", mgc_tx_txid(&tx3, tid3), true, &failures);
    check_bool("txid4", mgc_tx_txid(&tx4, tid4), true, &failures);
    check_bool("txid5", mgc_tx_txid(&tx5, tid5), true, &failures);
    check_bool("distinct txids", mgc_equal(tid1, tid2, 32), false, &failures);

    int len1 = 0;
    int len2 = 0;
    int len3 = 0;
    int len4 = 0;
    char* ser1 = mgc_tx_serialize(&tx1, true, &len1);
    char* ser2 = mgc_tx_serialize(&tx2, true, &len2);
    char* ser3 = mgc_tx_serialize(&tx3, true, &len3);
    char* ser4 = mgc_tx_serialize(&tx4, true, &len4);
    if (ser1 != null) { free(ser1); }
    if (ser2 != null) { free(ser2); }
    if (ser3 != null) { free(ser3); }
    if (ser4 != null) { free(ser4); }

    MgcMempool mp;
    check_bool("init", mgc_mempool_init(&mp, 4), true, &failures);
    check_int("count empty", mgc_mempool_count(&mp), 0, &failures);
    check_bool("get empty", mgc_mempool_get(&mp, 0) == null, true, &failures);
    check_bool("has empty", mgc_mempool_has(&mp, tid1), false, &failures);

    check_bool("add null tx", mgc_mempool_add(&mp, null), false, &failures);
    check_bool("has null txid", mgc_mempool_has(&mp, null), false, &failures);
    check_bool("remove null txid", mgc_mempool_remove(&mp, null), false, &failures);
    check_bool("remove missing empty", mgc_mempool_remove(&mp, missing), false, &failures);
    check_bool("get negative", mgc_mempool_get(&mp, -1) == null, true, &failures);

    check_bool("add tx1", mgc_mempool_add(&mp, &tx1), true, &failures);
    check_int("count after add", mgc_mempool_count(&mp), 1, &failures);
    check_bool("has tx1", mgc_mempool_has(&mp, tid1), true, &failures);
    check_int("size slot 0", mp.sizes[0], len1, &failures);
    check_int("total bytes 1", mp.total_bytes, len1, &failures);
    check_bool("duplicate rejected", mgc_mempool_add(&mp, &tx1), false, &failures);
    check_int("count after duplicate", mgc_mempool_count(&mp), 1, &failures);

    MgcTx* c0 = mgc_mempool_get(&mp, 0);
    check_bool("get slot 0", c0 != null, true, &failures);
    check_bool("deep copy distinct", c0 != &tx1, true, &failures);
    check_int("copy version", c0.version, 2, &failures);
    check_int("copy locktime", c0.locktime, 123456, &failures);
    check_int("copy in count", c0.in_count, 1, &failures);
    check_int("copy out count", c0.out_count, 2, &failures);
    check_int("copy prev index", c0.prev_indices[0], 11, &failures);
    check_bool("copy prev txid", mgc_equal(c0.prev_txids, prev1, 32), true, &failures);
    check_int("copy in script len", c0.input_script_lens[0], 4, &failures);
    check_int("copy in script byte", cast<int>(*(c0.input_scripts[0])) & 255, (11 + 40) & 255, &failures);
    check_int("copy out value 0", c0.output_values[0], 11000, &failures);
    check_int("copy out value 1", c0.output_values[1], 5500, &failures);
    check_int("copy out script len 0", c0.output_script_lens[0], 3, &failures);
    check_int("copy out script byte 0", cast<int>(*(c0.output_scripts[0])) & 255, (11 + 60) & 255, &failures);
    check_int("copy out script byte 1", cast<int>(*(c0.output_scripts[0] + 1)) & 255, (11 + 67) & 255, &failures);

    int original_byte = cast<int>(*(tx1.output_scripts[0])) & 255;
    char* sc0 = tx1.output_scripts[0];
    tx1.version = 99;
    *(sc0 + 0) = cast<char>(0xAA);
    check_int("copy version independent", c0.version, 2, &failures);
    check_int("copy script independent", cast<int>(*(c0.output_scripts[0])) & 255, original_byte, &failures);
    tx1.version = 2;
    *(sc0 + 0) = cast<char>(original_byte);
    check_bool("has tx1 after restore", mgc_mempool_has(&mp, tid1), true, &failures);

    check_bool("add tx2", mgc_mempool_add(&mp, &tx2), true, &failures);
    check_bool("add tx3", mgc_mempool_add(&mp, &tx3), true, &failures);
    check_bool("add tx4", mgc_mempool_add(&mp, &tx4), true, &failures);
    check_int("count full", mgc_mempool_count(&mp), 4, &failures);
    check_bool("has tx2", mgc_mempool_has(&mp, tid2), true, &failures);
    check_bool("has tx3", mgc_mempool_has(&mp, tid3), true, &failures);
    check_bool("has tx4", mgc_mempool_has(&mp, tid4), true, &failures);
    check_int("size slot 1", mp.sizes[1], len2, &failures);
    check_int("size slot 2", mp.sizes[2], len3, &failures);
    check_int("size slot 3", mp.sizes[3], len4, &failures);
    check_int("total bytes 4", mp.total_bytes, len1 + len2 + len3 + len4, &failures);
    check_bool("capacity full rejected", mgc_mempool_add(&mp, &tx5), false, &failures);
    check_int("count after full", mgc_mempool_count(&mp), 4, &failures);
    check_bool("has tx5", mgc_mempool_has(&mp, tid5), false, &failures);
    check_bool("get out of range", mgc_mempool_get(&mp, 4) == null, true, &failures);

    check_bool("remove missing", mgc_mempool_remove(&mp, missing), false, &failures);
    check_bool("remove middle", mgc_mempool_remove(&mp, tid2), true, &failures);
    check_int("count after remove", mgc_mempool_count(&mp), 3, &failures);
    check_bool("has tx2 after remove", mgc_mempool_has(&mp, tid2), false, &failures);
    check_bool("has tx1 after remove", mgc_mempool_has(&mp, tid1), true, &failures);
    check_bool("has tx3 after remove", mgc_mempool_has(&mp, tid3), true, &failures);
    check_bool("has tx4 after remove", mgc_mempool_has(&mp, tid4), true, &failures);
    check_bool("txid slot 1 compacted", mgc_equal(mp.txids + 32, tid3, 32), true, &failures);
    check_int("size slot 1 compacted", mp.sizes[1], len3, &failures);
    MgcTx* c1 = mgc_mempool_get(&mp, 1);
    check_bool("get slot 1", c1 != null, true, &failures);
    check_int("compacted locktime", c1.locktime, 333333, &failures);
    check_int("total after remove", mp.total_bytes, len1 + len3 + len4, &failures);

    check_bool("remove first", mgc_mempool_remove(&mp, tid1), true, &failures);
    check_int("count after first remove", mgc_mempool_count(&mp), 2, &failures);
    check_bool("has tx1 gone", mgc_mempool_has(&mp, tid1), false, &failures);
    MgcTx* c0b = mgc_mempool_get(&mp, 0);
    check_bool("get new slot 0", c0b != null, true, &failures);
    check_int("compacted first locktime", c0b.locktime, 333333, &failures);
    check_bool("txid slot 0 after first", mgc_equal(mp.txids, tid3, 32), true, &failures);

    check_bool("remove last", mgc_mempool_remove(&mp, tid4), true, &failures);
    check_int("count after last remove", mgc_mempool_count(&mp), 1, &failures);
    check_bool("get slot 1 out of range", mgc_mempool_get(&mp, 1) == null, true, &failures);
    check_bool("readd tx2", mgc_mempool_add(&mp, &tx2), true, &failures);
    check_int("count after readd", mgc_mempool_count(&mp), 2, &failures);
    check_bool("has tx2 readded", mgc_mempool_has(&mp, tid2), true, &failures);

    mgc_mempool_clear(&mp);
    check_int("count after clear", mgc_mempool_count(&mp), 0, &failures);
    check_int("total after clear", mp.total_bytes, 0, &failures);
    check_bool("get after clear", mgc_mempool_get(&mp, 0) == null, true, &failures);
    check_bool("has tx2 after clear", mgc_mempool_has(&mp, tid2), false, &failures);
    check_bool("readd after clear", mgc_mempool_add(&mp, &tx1), true, &failures);
    check_int("count readd after clear", mgc_mempool_count(&mp), 1, &failures);

    mgc_mempool_clear(&mp);
    char* big_script = alloc<char>(100000);
    if (big_script == null) {
        check_bool("alloc big script", false, true, &failures);
    } else {
        for (int i = 0; i < 100000; i = i + 1) {
            *(big_script + i) = cast<char>(i & 255);
        }
        MgcTx bigtx;
        mgc_tx_init(&bigtx);
        check_bool("big tx output", mgc_tx_add_output(&bigtx, 7, big_script, 100000), true, &failures);
        check_bool("oversize rejected", mgc_mempool_add(&mp, &bigtx), false, &failures);
        check_int("count oversize", mgc_mempool_count(&mp), 0, &failures);
        mgc_tx_free(&bigtx);
        free(big_script);
    }

    mgc_mempool_free(&mp);
    check_int("freed capacity", mp.capacity, 0, &failures);
    check_int("freed count", mp.count, 0, &failures);
    check_bool("freed txs", mp.txs == null, true, &failures);
    check_bool("freed txids", mp.txids == null, true, &failures);
    check_bool("freed sizes", mp.sizes == null, true, &failures);
    check_int("freed total bytes", mp.total_bytes, 0, &failures);

    mgc_tx_free(&tx5);
    mgc_tx_free(&tx4);
    mgc_tx_free(&tx3);
    mgc_tx_free(&tx2);
    mgc_tx_free(&tx1);
    free(missing);
    free(tid5);
    free(tid4);
    free(tid3);
    free(tid2);
    free(tid1);
    free(prev1);
    free(prev);
    return test_report("test_mempool", failures);
}
