// Magnetar Coin — bounded in-memory transaction mempool with deep-copied entries.

use "tx.mg";
use "params.mg";

struct MgcMempool { int capacity; int count; MgcTx** txs; char* txids; int* sizes; int total_bytes; }

fn mgc_mempool_init(MgcMempool* mp, int capacity) -> bool {
    if (mp == null || capacity <= 0) { return false; }
    mp.capacity = 0;
    mp.count = 0;
    mp.txs = null;
    mp.txids = null;
    mp.sizes = null;
    mp.total_bytes = 0;

    mp.txs = alloc<MgcTx*>(capacity);
    mp.txids = alloc<char>(capacity * 32);
    mp.sizes = alloc<int>(capacity);
    if (mp.txs == null || mp.txids == null || mp.sizes == null) {
        mgc_mempool_free(mp);
        return false;
    }

    MgcTx** txs = mp.txs;
    int* sizes = mp.sizes;
    char* txids = mp.txids;
    mgc_zero(txids, capacity * 32);
    for (int i = 0; i < capacity; i = i + 1) {
        txs[i] = null;
        sizes[i] = 0;
    }
    mp.capacity = capacity;
    return true;
}

fn mgc_mempool_free(MgcMempool* mp) -> void {
    if (mp == null) { return; }
    int cap = mp.capacity;
    MgcTx** txs = mp.txs;
    if (txs != null) {
        for (int i = 0; i < cap; i = i + 1) {
            if (txs[i] != null) {
                mgc_tx_free(txs[i]);
                txs[i] = null;
            }
        }
        free(txs);
    }
    if (mp.txids != null) { free(mp.txids); }
    if (mp.sizes != null) { free(mp.sizes); }
    mp.capacity = 0;
    mp.count = 0;
    mp.txs = null;
    mp.txids = null;
    mp.sizes = null;
    mp.total_bytes = 0;
}

fn mgc_mempool_has(MgcMempool* mp, char* txid32) -> bool {
    if (mp == null || txid32 == null || mp.txids == null || mp.count <= 0) { return false; }
    char* txids = mp.txids;
    for (int i = 0; i < mp.count; i = i + 1) {
        if (mgc_equal(txids + i * 32, txid32, 32)) { return true; }
    }
    return false;
}

fn mgc_mempool_add(MgcMempool* mp, MgcTx* tx) -> bool {
    if (mp == null || tx == null || mp.capacity <= 0 || mp.txs == null ||
        mp.txids == null || mp.sizes == null) { return false; }
    if (mp.count >= mp.capacity) { return false; }

    char* tid = alloc<char>(32);
    if (tid == null) { return false; }
    if (!mgc_tx_txid(tx, tid)) { free(tid); return false; }
    if (mgc_mempool_has(mp, tid)) { free(tid); return false; }

    int len = 0;
    char* data = mgc_tx_serialize(tx, true, &len);
    if (data == null || len <= 0 || len > MGC_MAX_TX_BYTES) {
        if (data != null) { free(data); }
        free(tid);
        return false;
    }

    MgcTx* stored = alloc<MgcTx>(1);
    if (stored == null) { free(data); free(tid); return false; }
    if (!mgc_tx_deserialize(data, len, stored)) {
        free(stored);
        free(data);
        free(tid);
        return false;
    }
    free(data);

    int n = mp.count;
    MgcTx** txs = mp.txs;
    int* sizes = mp.sizes;
    char* txids = mp.txids;
    txs[n] = stored;
    mgc_copy(txids + n * 32, tid, 32);
    sizes[n] = len;
    mp.count = n + 1;
    mp.total_bytes = mp.total_bytes + len;
    free(tid);
    return true;
}

fn mgc_mempool_remove(MgcMempool* mp, char* txid32) -> bool {
    if (mp == null || txid32 == null || mp.count <= 0 || mp.txs == null ||
        mp.txids == null || mp.sizes == null) { return false; }
    char* txids = mp.txids;
    int found = -1;
    for (int i = 0; i < mp.count; i = i + 1) {
        if (mgc_equal(txids + i * 32, txid32, 32)) { found = i; break; }
    }
    if (found < 0) { return false; }

    MgcTx** txs = mp.txs;
    int* sizes = mp.sizes;
    mgc_tx_free(txs[found]);
    txs[found] = null;
    mp.total_bytes = mp.total_bytes - sizes[found];

    int n = mp.count;
    for (int i = found + 1; i < n; i = i + 1) {
        txs[i - 1] = txs[i];
        sizes[i - 1] = sizes[i];
        mgc_copy(txids + (i - 1) * 32, txids + i * 32, 32);
    }
    txs[n - 1] = null;
    sizes[n - 1] = 0;
    mgc_zero(txids + (n - 1) * 32, 32);
    mp.count = n - 1;
    return true;
}

fn mgc_mempool_get(MgcMempool* mp, int i) -> MgcTx* {
    if (mp == null || i < 0 || i >= mp.count || mp.txs == null) { return null; }
    return mp.txs[i];
}

fn mgc_mempool_count(MgcMempool* mp) -> int {
    if (mp == null) { return 0; }
    return mp.count;
}

fn mgc_mempool_clear(MgcMempool* mp) -> void {
    if (mp == null || mp.txs == null || mp.txids == null || mp.sizes == null) { return; }
    int n = mp.count;
    MgcTx** txs = mp.txs;
    int* sizes = mp.sizes;
    char* txids = mp.txids;
    for (int i = 0; i < n; i = i + 1) {
        if (txs[i] != null) { mgc_tx_free(txs[i]); txs[i] = null; }
        sizes[i] = 0;
        mgc_zero(txids + i * 32, 32);
    }
    mp.count = 0;
    mp.total_bytes = 0;
}
