// Magnetar Coin — blocks, 80-byte headers, consensus serialization and Merkle roots.
// Header byte buffers allocated by init are not freed by free: callers may assign their own.

use "tx.mg";
use "hash.mg";
use "serialization.mg";
use "util.mg";
use "params.mg";

const int MGC_BLOCK_MAX_TXS = 100000;

struct MgcBlock {
    int version;
    char* prev_block;
    char* merkle_root;
    int timestamp;
    int bits;
    int nonce;
    int tx_count;
    MgcTx** txs;
}

fn _mgc_block_ensure_hashes(MgcBlock* b) -> bool {
    if (b == null) { return false; }
    if (b.prev_block != null && b.merkle_root != null) { return true; }
    if (b.prev_block == null) {
        b.prev_block = alloc<char>(32);
        if (b.prev_block == null) { return false; }
        mgc_zero(b.prev_block, 32);
    }
    if (b.merkle_root == null) {
        b.merkle_root = alloc<char>(32);
        if (b.merkle_root == null) { return false; }
        mgc_zero(b.merkle_root, 32);
    }
    return true;
}

fn mgc_block_init(MgcBlock* b) -> void {
    if (b == null) { return; }
    b.version = 1;
    b.prev_block = null;
    b.merkle_root = null;
    b.timestamp = 0;
    b.bits = 0;
    b.nonce = 0;
    b.tx_count = 0;
    b.txs = null;
    _mgc_block_ensure_hashes(b);
}

fn mgc_block_free(MgcBlock* b) -> void {
    if (b == null) { return; }
    MgcTx** txs = b.txs;
    int count = b.tx_count;
    if (txs != null) {
        for (int i = 0; i < count; i = i + 1) {
            if (txs[i] != null) {
                mgc_tx_free(txs[i]);
                txs[i] = null;
            }
        }
        free(txs);
    }
    b.tx_count = 0;
    b.txs = null;
}

fn mgc_block_add_tx(MgcBlock* b, MgcTx* tx, bool make_copy) -> bool {
    if (b == null || tx == null || b.tx_count < 0 || b.tx_count >= MGC_BLOCK_MAX_TXS) { return false; }
    if (b.tx_count > 0 && b.txs == null) { return false; }

    MgcTx* stored = tx;
    if (make_copy) {
        int len = 0;
        char* data = mgc_tx_serialize(tx, true, &len);
        if (data == null || len <= 0) {
            if (data != null) { free(data); }
            return false;
        }
        MgcTx* fresh = alloc<MgcTx>(1);
        if (fresh == null) { free(data); return false; }
        bool ok = mgc_tx_deserialize(data, len, fresh);
        free(data);
        if (!ok) { free(fresh); return false; }
        stored = fresh;
    }

    int n = b.tx_count;
    MgcTx** next = alloc<MgcTx*>(n + 1);
    if (next == null) {
        if (make_copy) { mgc_tx_free(stored); free(stored); }
        return false;
    }
    for (int i = 0; i < n; i = i + 1) { next[i] = b.txs[i]; }
    next[n] = stored;
    if (b.txs != null) { free(b.txs); }
    b.txs = next;
    b.tx_count = n + 1;
    return true;
}

fn mgc_block_header(MgcBlock* b, char* out80) -> void {
    if (b == null || out80 == null) { return; }
    char* prev = b.prev_block;
    char* root = b.merkle_root;
    char* zeros = null;
    if (prev == null || root == null) {
        zeros = alloc<char>(64);
        if (zeros == null) { return; }
        mgc_zero(zeros, 64);
        if (prev == null) { prev = zeros; }
        if (root == null) { root = zeros; }
    }
    endian_write_u32_le(out80, 0, b.version);
    mgc_copy(out80 + 4, prev, 32);
    mgc_copy(out80 + 36, root, 32);
    endian_write_u32_le(out80, 68, b.timestamp);
    endian_write_u32_le(out80, 72, b.bits);
    endian_write_u32_le(out80, 76, b.nonce);
    if (zeros != null) { free(zeros); }
}

fn mgc_block_hash(MgcBlock* b, char* out32) -> bool {
    if (b == null || out32 == null) { return false; }
    char* header = alloc<char>(80);
    if (header == null) { return false; }
    mgc_block_header(b, header);
    mgc_sha256d_raw(header, 80, out32);
    free(header);
    return true;
}

fn mgc_block_serialize(MgcBlock* b, int* out_len) -> char* {
    if (out_len != null) { *out_len = 0; }
    if (b == null || b.tx_count < 0 || (b.tx_count > 0 && b.txs == null)) { return null; }

    ByteWriter w;
    bw_init(&w, 256);
    char* header = alloc<char>(80);
    if (!w.ok || header == null) {
        if (header != null) { free(header); }
        bw_free(&w);
        return null;
    }
    mgc_block_header(b, header);
    bool ok = bw_write_bytes(&w, header, 80);
    free(header);
    ok = ok && bw_write_varint(&w, b.tx_count);

    int i = 0;
    while (ok && i < b.tx_count) {
        int tlen = 0;
        char* tdata = mgc_tx_serialize(b.txs[i], true, &tlen);
        if (tdata == null || tlen <= 0) {
            if (tdata != null) { free(tdata); }
            ok = false;
        } else {
            ok = bw_write_varint(&w, tlen);
            if (ok) { ok = bw_write_bytes(&w, tdata, tlen); }
            free(tdata);
        }
        i = i + 1;
    }

    if (!ok || !w.ok) {
        bw_free(&w);
        return null;
    }
    char* data = w.data;
    if (out_len != null) { *out_len = w.length; }
    w.data = null;
    bw_free(&w);
    return data;
}

fn mgc_block_deserialize(char* data, int len, MgcBlock* b) -> bool {
    if (data == null || len < 80 || b == null) { return false; }
    ByteReader r;
    br_init(&r, data, len);
    char* prev = alloc<char>(32);
    char* root = alloc<char>(32);
    if (!r.ok || prev == null || root == null) {
        if (prev != null) { free(prev); }
        if (root != null) { free(root); }
        return false;
    }

    int version = br_read_u32(&r);
    br_read_bytes(&r, prev, 32);
    br_read_bytes(&r, root, 32);
    int timestamp = br_read_u32(&r);
    int bits = br_read_u32(&r);
    int nonce = br_read_u32(&r);
    int count = br_read_varint(&r);

    bool ok = r.ok && count >= 0 && count <= MGC_BLOCK_MAX_TXS;
    MgcTx** txs = null;
    if (ok && count > 0) {
        txs = alloc<MgcTx*>(count);
        if (txs == null) {
            ok = false;
        } else {
            for (int i = 0; i < count; i = i + 1) { txs[i] = null; }
        }
    }

    int i = 0;
    while (ok && i < count) {
        int tlen = br_read_varint(&r);
        int offset = r.offset;
        int avail = r.length - offset;
        if (!r.ok || tlen <= 0 || tlen > avail) {
            ok = false;
        } else {
            char* tx_bytes = data + offset;
            MgcTx* tx = alloc<MgcTx>(1);
            if (tx == null) {
                ok = false;
            } else {
                bool tx_ok = mgc_tx_deserialize(tx_bytes, tlen, tx);
                if (!tx_ok) {
                    free(tx);
                    ok = false;
                } else {
                    txs[i] = tx;
                    r.offset = offset + tlen;
                }
            }
        }
        i = i + 1;
    }
    if (!r.ok || r.offset != len) { ok = false; }

    if (ok) {
        ok = _mgc_block_ensure_hashes(b);
    }
    if (ok) {
        mgc_copy(b.prev_block, prev, 32);
        mgc_copy(b.merkle_root, root, 32);
        b.version = version;
        b.timestamp = timestamp;
        b.bits = bits;
        b.nonce = nonce;
        b.tx_count = count;
        b.txs = txs;
    } else {
        if (txs != null) {
            for (int j = 0; j < count; j = j + 1) {
                if (txs[j] != null) {
                    mgc_tx_free(txs[j]);
                    free(txs[j]);
                }
            }
            free(txs);
        }
    }
    free(prev);
    free(root);
    return ok;
}

fn mgc_block_txid(MgcBlock* b, int index, char* out32) -> bool {
    if (b == null || out32 == null || index < 0 || index >= b.tx_count || b.txs == null) { return false; }
    return mgc_tx_txid(b.txs[index], out32);
}

fn mgc_block_merkle_root(MgcBlock* b, char* out32) -> bool {
    if (out32 == null || b == null || b.tx_count <= 0 || b.txs == null) { return false; }
    char* ids = alloc<char>(b.tx_count * 32);
    if (ids == null) { return false; }
    bool ok = true;
    for (int i = 0; i < b.tx_count; i = i + 1) {
        if (!mgc_tx_txid(b.txs[i], ids + i * 32)) { ok = false; break; }
    }
    if (ok) { ok = mgc_merkle_root(ids, b.tx_count, out32); }
    free(ids);
    return ok;
}

fn mgc_block_serialized_size(MgcBlock* b) -> int {
    if (b == null || b.tx_count < 0 || (b.tx_count > 0 && b.txs == null)) { return 0; }
    int size = 80 + varint_size(b.tx_count);
    for (int i = 0; i < b.tx_count; i = i + 1) {
        int tlen = 0;
        char* tdata = mgc_tx_serialize(b.txs[i], true, &tlen);
        if (tdata == null || tlen <= 0) {
            if (tdata != null) { free(tdata); }
            return 0;
        }
        free(tdata);
        size = size + varint_size(tlen) + tlen;
    }
    return size;
}

fn mgc_block_is_coinbase(MgcTx* tx) -> bool {
    if (tx == null || tx.in_count <= 0 || tx.prev_txids == null || tx.prev_indices == null) { return false; }
    if (tx.prev_indices[0] != 4294967295) { return false; }
    for (int i = 0; i < 32; i = i + 1) {
        if ((cast<int>(*(tx.prev_txids + i)) & 255) != 0) { return false; }
    }
    return true;
}
