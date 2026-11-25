// Tests for the in-memory UTXO set and its undo journal.

use "../lib/utxo.mg";
use "test_common.mg";

fn _mgc_test_utxo_txid(char* out, int seed) -> void {
    for (int i = 0; i < 32; i = i + 1) {
        *(out + i) = cast<char>((seed + i * 7) & 255);
    }
}

fn main() -> int {
    int failures = 0;

    MgcUtxoSet set;
    check_bool("init", mgc_utxo_init(&set, 16), true, &failures);
    check_int("count empty", mgc_utxo_count(&set), 0, &failures);
    int mark0 = mgc_utxo_mark(&set);
    check_int("initial mark", mark0, 0, &failures);

    char* txA = alloc<char>(32);
    char* txB = alloc<char>(32);
    char* txC = alloc<char>(32);
    char* script = alloc<char>(4);
    if (txA == null || txB == null || txC == null || script == null) {
        print_str("FAIL alloc test buffers\n");
        return 1;
    }
    _mgc_test_utxo_txid(txA, 1);
    _mgc_test_utxo_txid(txB, 211);
    _mgc_test_utxo_txid(txC, 9021);
    *(script + 0) = cast<char>(0x51);
    *(script + 1) = cast<char>(0x52);
    *(script + 2) = cast<char>(0x53);
    *(script + 3) = cast<char>(0x54);

    check_bool("add A", mgc_utxo_add(&set, txA, 0, 1000, script, 4, 10, false), true, &failures);
    check_int("count after add", mgc_utxo_count(&set), 1, &failures);
    check_bool("exists A", mgc_utxo_exists(&set, txA, 0), true, &failures);

    MgcUtxo out;
    check_bool("get A", mgc_utxo_get(&set, txA, 0, &out), true, &failures);
    check_int("get A value", out.value, 1000, &failures);
    check_int("get A script_len", out.script_len, 4, &failures);
    check_bool("get A script ptr", out.script != null, true, &failures);
    check_int("get A script byte0", endian_read_u8(out.script, 0), 0x51, &failures);
    check_int("get A script byte3", endian_read_u8(out.script, 3), 0x54, &failures);
    check_int("get A height", out.height, 10, &failures);
    check_bool("get A coinbase", out.coinbase, false, &failures);
    int slotA = mgc_utxo_find(&set, txA, 0);
    check_bool("get A copy", out.script != set.scripts[slotA], true, &failures);
    mgc_utxo_result_free(&out);
    check_bool("result free", out.script == null, true, &failures);

    MgcUtxo miss;
    check_bool("get missing", mgc_utxo_get(&set, txB, 77, &miss), false, &failures);
    check_bool("missing script null", miss.script == null, true, &failures);
    check_bool("exists missing", mgc_utxo_exists(&set, txB, 77), false, &failures);
    check_int("find missing", mgc_utxo_find(&set, txB, 77), -1, &failures);
    check_bool("get null out", mgc_utxo_get(&set, txA, 0, null), false, &failures);
    check_bool("spend null out missing", mgc_utxo_spend(&set, txB, 77, null), false, &failures);

    int mark1 = mgc_utxo_mark(&set);
    check_bool("spend A", mgc_utxo_spend(&set, txA, 0, &out), true, &failures);
    check_int("spend A value", out.value, 1000, &failures);
    check_int("spend A script_len", out.script_len, 4, &failures);
    check_int("spend A script byte2", endian_read_u8(out.script, 2), 0x53, &failures);
    check_int("spend A height", out.height, 10, &failures);
    check_bool("spend A coinbase", out.coinbase, false, &failures);
    check_bool("spend A copy", out.script != set.scripts[slotA], true, &failures);
    mgc_utxo_result_free(&out);
    check_int("count after spend", mgc_utxo_count(&set), 0, &failures);
    check_bool("exists after spend", mgc_utxo_exists(&set, txA, 0), false, &failures);
    check_bool("double spend", mgc_utxo_spend(&set, txA, 0, &out), false, &failures);

    check_bool("rollback spend", mgc_utxo_rollback(&set, mark1), true, &failures);
    check_int("journal after spend undo", mgc_utxo_mark(&set), mark1, &failures);
    check_bool("A restored exists", mgc_utxo_exists(&set, txA, 0), true, &failures);
    check_int("count after spend undo", mgc_utxo_count(&set), 1, &failures);
    check_bool("get A restored", mgc_utxo_get(&set, txA, 0, &out), true, &failures);
    check_int("restored value", out.value, 1000, &failures);
    check_int("restored script_len", out.script_len, 4, &failures);
    check_int("restored script byte0", endian_read_u8(out.script, 0), 0x51, &failures);
    check_int("restored script byte3", endian_read_u8(out.script, 3), 0x54, &failures);
    check_int("restored height", out.height, 10, &failures);
    check_bool("restored coinbase", out.coinbase, false, &failures);
    mgc_utxo_result_free(&out);

    check_bool("rollback add", mgc_utxo_rollback(&set, mark0), true, &failures);
    check_int("journal after add undo", mgc_utxo_mark(&set), 0, &failures);
    check_int("count after add undo", mgc_utxo_count(&set), 0, &failures);
    check_bool("A gone after add undo", mgc_utxo_exists(&set, txA, 0), false, &failures);

    check_bool("add B coinbase", mgc_utxo_add(&set, txB, 3, 5000000000, script, 4, 777, true), true, &failures);
    int markB = mgc_utxo_mark(&set);
    check_bool("spend B", mgc_utxo_spend(&set, txB, 3, &out), true, &failures);
    check_int("spend B value", out.value, 5000000000, &failures);
    check_bool("spend B coinbase", out.coinbase, true, &failures);
    mgc_utxo_result_free(&out);
    check_bool("rollback B", mgc_utxo_rollback(&set, markB), true, &failures);
    check_bool("get B restored", mgc_utxo_get(&set, txB, 3, &out), true, &failures);
    check_int("B restored value", out.value, 5000000000, &failures);
    check_int("B restored height", out.height, 777, &failures);
    check_bool("B restored coinbase", out.coinbase, true, &failures);
    check_int("B restored script_len", out.script_len, 4, &failures);
    check_int("B restored script byte1", endian_read_u8(out.script, 1), 0x52, &failures);
    mgc_utxo_result_free(&out);
    check_int("count B", mgc_utxo_count(&set), 1, &failures);

    check_bool("add C", mgc_utxo_add(&set, txC, 9, 42, null, 0, 5, false), true, &failures);
    check_int("count A+B+C", mgc_utxo_count(&set), 2, &failures);
    check_bool("get C", mgc_utxo_get(&set, txC, 9, &out), true, &failures);
    check_bool("C script null", out.script == null, true, &failures);
    check_int("C script_len", out.script_len, 0, &failures);
    check_int("C value", out.value, 42, &failures);
    mgc_utxo_result_free(&out);
    check_bool("spend C no out", mgc_utxo_spend(&set, txC, 9, null), true, &failures);
    check_int("count after spend C", mgc_utxo_count(&set), 1, &failures);

    int markD = mgc_utxo_mark(&set);
    check_bool("readd A tombstone", mgc_utxo_add(&set, txA, 0, 2000, script, 4, 20, true), true, &failures);
    check_int("count after reuse", mgc_utxo_count(&set), 2, &failures);
    check_bool("get reused A", mgc_utxo_get(&set, txA, 0, &out), true, &failures);
    check_int("reused A value", out.value, 2000, &failures);
    check_int("reused A height", out.height, 20, &failures);
    check_bool("reused A coinbase", out.coinbase, true, &failures);
    check_int("reused A script byte0", endian_read_u8(out.script, 0), 0x51, &failures);
    mgc_utxo_result_free(&out);
    check_bool("rollback reuse", mgc_utxo_rollback(&set, markD), true, &failures);
    check_int("count after reuse undo", mgc_utxo_count(&set), 1, &failures);
    check_bool("A gone after reuse undo", mgc_utxo_exists(&set, txA, 0), false, &failures);
    check_bool("B still present", mgc_utxo_exists(&set, txB, 3), true, &failures);

    int markE = mgc_utxo_mark(&set);
    char* big = alloc<char>(40);
    if (big == null) {
        print_str("FAIL alloc big\n");
        mgc_utxo_free(&set);
        free(txA); free(txB); free(txC); free(script);
        return 1;
    }
    for (int i = 0; i < 40; i = i + 1) {
        *(big + i) = cast<char>((i * 3) & 255);
    }
    for (int n = 0; n < 12; n = n + 1) {
        char* tid = alloc<char>(32);
        if (tid == null) { check_bool("alloc tid", false, true, &failures); break; }
        _mgc_test_utxo_txid(tid, 1000 + n * 31);
        check_bool("journal grow add", mgc_utxo_add(&set, tid, n, n + 1, big, 40, n, (n % 2) == 0), true, &failures);
        free(tid);
    }
    check_int("journal grew", mgc_utxo_mark(&set) > markE, true, &failures);
    check_bool("rollback many", mgc_utxo_rollback(&set, markE), true, &failures);
    check_int("count after many undo", mgc_utxo_count(&set), 1, &failures);
    check_bool("bad mark", mgc_utxo_rollback(&set, markE + 999999), false, &failures);

    mgc_utxo_clear(&set);
    check_int("count after clear", mgc_utxo_count(&set), 0, &failures);
    check_int("journal after clear", mgc_utxo_mark(&set), 0, &failures);
    check_bool("missing after clear", mgc_utxo_exists(&set, txB, 3), false, &failures);

    free(big);
    free(txA);
    free(txB);
    free(txC);
    free(script);
    mgc_utxo_free(&set);
    return test_report("test_utxo", failures);
}
