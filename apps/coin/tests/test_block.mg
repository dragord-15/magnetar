// Tests for block headers, consensus serialization, deep-copy ownership and Merkle roots.

use "../lib/block.mg";
use "test_common.mg";

fn _mgc_test_block_tx(MgcTx* tx, int seed, bool coinbase, char* prev_out, char* in_script, char* out_script) -> bool {
    mgc_tx_init(tx);
    tx.version = 2;
    tx.locktime = seed;
    int prev_index = 3;
    if (coinbase) { prev_index = 4294967295; }
    bool ok = mgc_tx_add_input(tx, prev_out, prev_index, in_script, 4, 4294967295);
    ok = ok && mgc_tx_add_output(tx, 1000000 + seed, out_script, 3);
    return ok;
}

fn main() -> int {
    int failures = 0;
    char* zero32 = alloc<char>(32);
    char* prev32 = alloc<char>(32);
    char* in_script = alloc<char>(4);
    char* in_script2 = alloc<char>(4);
    char* out_script = alloc<char>(3);
    char* header = alloc<char>(80);
    char* hash1 = alloc<char>(32);
    char* hash2 = alloc<char>(32);
    char* ids = alloc<char>(96);
    char* merkle = alloc<char>(32);
    char* tid = alloc<char>(32);
    if (zero32 == null || prev32 == null || in_script == null || in_script2 == null ||
        out_script == null || header == null || hash1 == null || hash2 == null ||
        ids == null || merkle == null || tid == null) {
        print_str("FAIL alloc\n");
        return 1;
    }
    mgc_zero(zero32, 32);
    mgc_zero(prev32, 32);
    for (int i = 0; i < 32; i = i + 1) {
        *(prev32 + i) = cast<char>((i * 7 + 1) & 255);
    }
    for (int i = 0; i < 4; i = i + 1) {
        *(in_script + i) = cast<char>(10 + i);
        *(in_script2 + i) = cast<char>(20 + i);
    }
    for (int i = 0; i < 3; i = i + 1) { *(out_script + i) = cast<char>(51 + i); }

    MgcTx cb;
    MgcTx tx2;
    MgcTx tx3;
    check_bool("make coinbase", _mgc_test_block_tx(&cb, 1, true, zero32, in_script, out_script), true, &failures);
    check_bool("make tx2", _mgc_test_block_tx(&tx2, 2, false, prev32, in_script, out_script), true, &failures);
    check_bool("make tx3", _mgc_test_block_tx(&tx3, 3, false, prev32, in_script2, out_script), true, &failures);
    check_bool("coinbase detect", mgc_block_is_coinbase(&cb), true, &failures);
    check_bool("coinbase detect negative", mgc_block_is_coinbase(&tx2), false, &failures);
    check_bool("coinbase null", mgc_block_is_coinbase(null), false, &failures);

    check_bool("cb txid", mgc_tx_txid(&cb, ids), true, &failures);
    check_bool("tx2 txid", mgc_tx_txid(&tx2, ids + 32), true, &failures);
    check_bool("tx3 txid", mgc_tx_txid(&tx3, ids + 64), true, &failures);
    check_bool("merkle source", mgc_merkle_root(ids, 3, merkle), true, &failures);

    MgcBlock b;
    mgc_block_init(&b);
    b.version = 2;
    mgc_copy(b.prev_block, prev32, 32);
    mgc_copy(b.merkle_root, merkle, 32);
    b.timestamp = 1700000000;
    b.bits = mgc_genesis_bits(MGC_NETWORK_REGTEST);
    b.nonce = 12345;
    check_bool("add cb", mgc_block_add_tx(&b, &cb, true), true, &failures);
    check_bool("add tx2", mgc_block_add_tx(&b, &tx2, true), true, &failures);
    check_bool("add tx3", mgc_block_add_tx(&b, &tx3, true), true, &failures);
    check_int("tx count", b.tx_count, 3, &failures);
    check_bool("null add", mgc_block_add_tx(&b, null, true), false, &failures);

    mgc_block_header(&b, header);
    check_int("header version", endian_read_u32_le(header, 0), 2, &failures);
    check_bool("header prev", mgc_equal(header + 4, prev32, 32), true, &failures);
    check_bool("header merkle", mgc_equal(header + 36, merkle, 32), true, &failures);
    check_int("header timestamp", endian_read_u32_le(header, 68), 1700000000, &failures);
    check_int("header bits", endian_read_u32_le(header, 72), b.bits, &failures);
    check_int("header nonce", endian_read_u32_le(header, 76), 12345, &failures);

    check_bool("block hash", mgc_block_hash(&b, hash1), true, &failures);
    check_bool("block hash repeat", mgc_block_hash(&b, hash2), true, &failures);
    check_bool("block hash stable", mgc_equal(hash1, hash2, 32), true, &failures);
    b.nonce = 12346;
    check_bool("block hash changed", mgc_block_hash(&b, hash2), true, &failures);
    check_bool("nonce changes hash", mgc_equal(hash1, hash2, 32), false, &failures);
    b.nonce = 12345;

    int ser_len = 0;
    char* ser = mgc_block_serialize(&b, &ser_len);
    check_bool("serialize ok", ser != null, true, &failures);
    if (ser != null) {
        check_int("serialized size", ser_len, mgc_block_serialized_size(&b), &failures);
        check_int("header prefix len", mgc_equal(ser, header, 80) ? 1 : 0, 1, &failures);
        check_int("tx count varint", endian_read_u8(ser, 80), 3, &failures);
    }

    MgcBlock b2;
    mgc_block_init(&b2);
    if (ser != null) {
        check_bool("deserialize ok", mgc_block_deserialize(ser, ser_len, &b2), true, &failures);
        check_bool("deserialize strict", mgc_block_deserialize(ser, ser_len - 1, &b2), false, &failures);
        check_bool("deserialize null", mgc_block_deserialize(null, ser_len, &b2), false, &failures);
        check_int("b2 version", b2.version, 2, &failures);
        check_int("b2 timestamp", b2.timestamp, 1700000000, &failures);
        check_int("b2 bits", b2.bits, b.bits, &failures);
        check_int("b2 nonce", b2.nonce, 12345, &failures);
        check_int("b2 tx count", b2.tx_count, 3, &failures);
        check_bool("b2 prev", mgc_equal(b2.prev_block, prev32, 32), true, &failures);
        check_bool("b2 merkle", mgc_equal(b2.merkle_root, merkle, 32), true, &failures);
        check_bool("deep copy array", b2.txs != b.txs, true, &failures);
        check_bool("b2 hash", mgc_block_hash(&b2, hash2), true, &failures);
        check_bool("roundtrip hash", mgc_equal(hash1, hash2, 32), true, &failures);
        check_bool("b2 merkle recompute", mgc_block_merkle_root(&b2, hash2), true, &failures);
        check_bool("merkle matches", mgc_equal(hash2, merkle, 32), true, &failures);
        check_bool("b2 txid", mgc_block_txid(&b2, 1, tid), true, &failures);
        check_bool("txid roundtrip", mgc_equal(tid, ids + 32, 32), true, &failures);
        check_bool("bad txid index", mgc_block_txid(&b2, 3, tid), false, &failures);
    }

    char* sig = mgc_tx_in_script(&cb, 0);
    if (sig != null) { *(sig + 1) = cast<char>(99); }
    check_bool("txid after sig change", mgc_block_txid(&b, 0, tid), true, &failures);
    check_bool("txid excludes scripts", mgc_equal(tid, ids, 32), true, &failures);
    char* b2sig = mgc_tx_in_script(b2.txs[0], 0);
    check_bool("copied script independent", b2sig != null && *(b2sig + 1) == in_script[1], true, &failures);

    MgcBlock moved;
    mgc_block_init(&moved);
    check_bool("add transferred", mgc_block_add_tx(&moved, &tx3, false), true, &failures);
    check_int("transferred count", moved.tx_count, 1, &failures);
    check_bool("transferred pointer", moved.txs[0] == &tx3, true, &failures);

    mgc_block_free(&b);
    mgc_block_free(&b2);
    mgc_block_free(&moved);
    mgc_tx_free(&cb);
    mgc_tx_free(&tx2);
    if (ser != null) { free(ser); }
    if (b.prev_block != null) { free(b.prev_block); }
    if (b.merkle_root != null) { free(b.merkle_root); }
    if (b2.prev_block != null) { free(b2.prev_block); }
    if (b2.merkle_root != null) { free(b2.merkle_root); }
    if (moved.prev_block != null) { free(moved.prev_block); }
    if (moved.merkle_root != null) { free(moved.merkle_root); }
    free(tid); free(merkle); free(ids); free(hash2); free(hash1); free(header);
    free(out_script); free(in_script2); free(in_script); free(prev32); free(zero32);
    return test_report("test_block", failures);
}
