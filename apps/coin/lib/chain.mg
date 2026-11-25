// Magnetar Coin — block index, cumulative work, UTXO snapshots and reorgs.

use "consensus.mg";
use "pow.mg";
use "block.mg";
use "utxo.mg";
use "params.mg";
use "bigint.mg";
use "util.mg";
use "endian.mg";
use "../../lib/crypto.mg";

extern fn get_timestamp() -> int;

struct MgcChain {
    int network;
    int capacity;
    int count;
    MgcBlock** blocks;
    char* hashes;
    int* parents;
    int* heights;
    int* bitses;
    int* work;
    int* in_best;
    int best_tip;
    MgcUtxoSet* utxo;
}

fn _mgc_chain_work_get(MgcChain* c, int index, int* out) -> void {
    if (c == null || out == null || index < 0 || index >= c.capacity) { return; }
    int* src = c.work + index * 128;
    for (int j = 0; j < 16; j = j + 1) {
        out[j] = src[j] & 65535;
    }
}

fn _mgc_chain_work_set(MgcChain* c, int index, int* src) -> void {
    if (c == null || src == null || index < 0 || index >= c.capacity) { return; }
    int* dst = c.work + index * 128;
    for (int j = 0; j < 16; j = j + 1) {
        dst[j] = src[j] & 65535;
    }
}

fn mgc_chain_init(MgcChain* c, int network, int capacity, MgcUtxoSet* utxo) -> bool {
    if (c == null || capacity <= 0 || utxo == null) { return false; }
    c.network = network;
    c.capacity = 0;
    c.count = 0;
    c.blocks = null;
    c.hashes = null;
    c.parents = null;
    c.heights = null;
    c.bitses = null;
    c.work = null;
    c.in_best = null;
    c.best_tip = -1;
    c.utxo = null;

    c.blocks = alloc<MgcBlock*>(capacity);
    c.hashes = alloc<char>(capacity * 32);
    c.parents = alloc<int>(capacity);
    c.heights = alloc<int>(capacity);
    c.bitses = alloc<int>(capacity);
    c.work = alloc<int>(capacity * 16);
    c.in_best = alloc<int>(capacity);
    if (c.blocks == null || c.hashes == null || c.parents == null || c.heights == null ||
        c.bitses == null || c.work == null || c.in_best == null) {
        mgc_chain_free(c);
        return false;
    }
    MgcBlock** blocks = c.blocks;
    char* hashes = c.hashes;
    int* parents = c.parents;
    int* heights = c.heights;
    int* bitses = c.bitses;
    int* in_best = c.in_best;
    mgc_zero(hashes, capacity * 32);
    for (int i = 0; i < capacity; i = i + 1) {
        blocks[i] = null;
        parents[i] = -1;
        heights[i] = 0;
        bitses[i] = 0;
        in_best[i] = 0;
        int* w = c.work + i * 128;
        for (int j = 0; j < 16; j = j + 1) { w[j] = 0; }
    }
    c.capacity = capacity;
    c.utxo = utxo;
    return true;
}

fn mgc_chain_free(MgcChain* c) -> void {
    if (c == null) { return; }
    int n = c.count;
    MgcBlock** blocks = c.blocks;
    if (blocks != null) {
        for (int i = 0; i < n; i = i + 1) {
            MgcBlock* blk = blocks[i];
            if (blk != null) {
                mgc_block_free(blk);
                free(blk);
                blocks[i] = null;
            }
        }
        free(blocks);
    }
    if (c.hashes != null) { free(c.hashes); }
    if (c.parents != null) { free(c.parents); }
    if (c.heights != null) { free(c.heights); }
    if (c.bitses != null) { free(c.bitses); }
    if (c.work != null) { free(c.work); }
    if (c.in_best != null) { free(c.in_best); }
    c.network = 0;
    c.capacity = 0;
    c.count = 0;
    c.blocks = null;
    c.hashes = null;
    c.parents = null;
    c.heights = null;
    c.bitses = null;
    c.work = null;
    c.in_best = null;
    c.best_tip = -1;
    c.utxo = null;
}

fn mgc_chain_add_genesis(MgcChain* c) -> bool {
    if (c == null || c.utxo == null || c.count != 0 || c.capacity < 1) { return false; }
    MgcBlock* g = alloc<MgcBlock>(1);
    if (g == null) { return false; }
    mgc_block_init(g);
    g.version = 1;
    mgc_zero(g.prev_block, 32);
    g.timestamp = 1760000000;
    g.bits = mgc_genesis_bits(c.network);
    g.nonce = 0;

    char* zero32 = alloc<char>(32);
    char* h160 = alloc<char>(20);
    char* script = alloc<char>(25);
    char* hbuf = alloc<char>(4);
    char* cb_script = alloc<char>(128);
    char* hash = alloc<char>(32);
    if (zero32 == null || h160 == null || script == null || hbuf == null ||
        cb_script == null || hash == null) {
        if (zero32 != null) { free(zero32); }
        if (h160 != null) { free(h160); }
        if (script != null) { free(script); }
        if (hbuf != null) { free(hbuf); }
        if (cb_script != null) { free(cb_script); }
        if (hash != null) { free(hash); }
        mgc_block_free(g);
        free(g);
        return false;
    }
    mgc_zero(zero32, 32);
    mgc_zero(h160, 20);
    mgc_zero(hbuf, 4);
    int cb_len = 0;
    bool ok = mgc_script_coinbase(hbuf, 4, cb_script, &cb_len);
    MgcTx cb;
    mgc_tx_init(&cb);
    if (ok) { ok = mgc_tx_add_input(&cb, zero32, 4294967295, cb_script, cb_len, 4294967295); }
    if (ok) {
        mgc_script_p2pkh(h160, script);
        ok = mgc_tx_add_output(&cb, mgc_initial_subsidy(), script, 25);
    }
    if (ok) { ok = mgc_block_add_tx(g, &cb, true); }
    mgc_tx_free(&cb);
    if (ok) { ok = mgc_block_merkle_root(g, g.merkle_root); }
    if (ok) { ok = mgc_block_hash(g, hash); }
    if (ok) {
        string got = crypto_hex_encode(hash, 32);
        string want = mgc_genesis_hash(c.network);
        if (got != want) { ok = false; }
        free(cast<char*>(got));
    }
    if (ok) { ok = mgc_consensus_apply_block(g, c.utxo, 0, c.network); }
    if (!ok) {
        mgc_block_free(g);
        free(g);
        free(hash);
        free(cb_script);
        free(hbuf);
        free(script);
        free(h160);
        free(zero32);
        return false;
    }
    int* w = alloc<int>(16);
    if (w == null) {
        mgc_block_free(g);
        free(g);
        free(hash);
        free(cb_script);
        free(hbuf);
        free(script);
        free(h160);
        free(zero32);
        return false;
    }
    mgc_pow_work_for_bits(g.bits, w);
    _mgc_chain_work_set(c, 0, w);
    free(w);
    c.blocks[0] = g;
    mgc_copy(c.hashes, hash, 32);
    c.parents[0] = -1;
    c.heights[0] = 0;
    c.bitses[0] = g.bits;
    c.in_best[0] = 1;
    c.best_tip = 0;
    c.count = 1;

    free(hash);
    free(cb_script);
    free(hbuf);
    free(script);
    free(h160);
    free(zero32);
    return true;
}

fn mgc_chain_count(MgcChain* c) -> int {
    if (c == null) { return 0; }
    return c.count;
}

fn mgc_chain_height(MgcChain* c) -> int {
    if (c == null || c.best_tip < 0 || c.best_tip >= c.count) { return -1; }
    return c.heights[c.best_tip];
}

fn mgc_chain_tip_hash(MgcChain* c, char* out32) -> bool {
    if (c == null || out32 == null || c.best_tip < 0 || c.best_tip >= c.count) { return false; }
    char* h = c.hashes + c.best_tip * 32;
    mgc_copy(out32, h, 32);
    return true;
}

fn mgc_chain_best_block(MgcChain* c) -> MgcBlock* {
    if (c == null || c.best_tip < 0 || c.best_tip >= c.count) { return null; }
    return c.blocks[c.best_tip];
}

fn mgc_chain_find(MgcChain* c, char* hash32) -> int {
    if (c == null || hash32 == null || c.count <= 0) { return -1; }
    for (int i = 0; i < c.count; i = i + 1) {
        char* h = c.hashes + i * 32;
        if (mgc_equal(h, hash32, 32)) { return i; }
    }
    return -1;
}

fn mgc_chain_get(MgcChain* c, int index) -> MgcBlock* {
    if (c == null || index < 0 || index >= c.count) { return null; }
    return c.blocks[index];
}

fn mgc_chain_at_height(MgcChain* c, int height) -> int {
    if (c == null || height < 0) { return -1; }
    for (int i = 0; i < c.count; i = i + 1) {
        if (c.in_best[i] == 1 && c.heights[i] == height) { return i; }
    }
    return -1;
}

fn _mgc_chain_ancestor_at_height(MgcChain* c, int index, int target) -> int {
    if (c == null || index < 0 || index >= c.count || target < 0) { return -1; }
    int cur = index;
    int guard = 0;
    while (cur >= 0 && cur < c.count && guard <= c.count) {
        int h = c.heights[cur];
        if (h == target) { return cur; }
        if (h < target) { return -1; }
        cur = c.parents[cur];
        guard = guard + 1;
    }
    return -1;
}

fn _mgc_chain_expected_bits_for(MgcChain* c, int parent_index) -> int {
    if (c == null) { return mgc_genesis_bits(MGC_NETWORK_REGTEST); }
    if (parent_index < 0 || parent_index >= c.count) { return mgc_genesis_bits(c.network); }
    int child_height = c.heights[parent_index] + 1;
    int interval = mgc_retarget_interval(c.network);
    int ref_height = c.heights[parent_index] - interval + 1;
    if (ref_height < 0) { ref_height = 0; }
    int span = 1;
    int ref_idx = _mgc_chain_ancestor_at_height(c, parent_index, ref_height);
    if (ref_idx >= 0) {
        MgcBlock* pb = c.blocks[parent_index];
        MgcBlock* rb = c.blocks[ref_idx];
        if (pb != null && rb != null) {
            span = pb.timestamp - rb.timestamp;
            if (span < 1) { span = 1; }
        }
    }
    return mgc_pow_next_bits(c.network, child_height, c.bitses[parent_index], span);
}

fn mgc_chain_expected_bits(MgcChain* c) -> int {
    if (c == null) { return mgc_genesis_bits(MGC_NETWORK_REGTEST); }
    int n = c.count;
    int tip = c.best_tip;
    if (n <= 0 || tip < 0) { return mgc_genesis_bits(MGC_NETWORK_REGTEST); }
    return _mgc_chain_expected_bits_for(c, tip);
}

fn mgc_chain_next_timestamp(MgcChain* c) -> int {
    int now = get_timestamp();
    if (c == null || c.best_tip < 0 || c.best_tip >= c.count) { return now; }
    MgcBlock* tip = c.blocks[c.best_tip];
    int floor_ts = 1;
    if (tip != null) { floor_ts = tip.timestamp + 1; }
    if (now < floor_ts) { return floor_ts; }
    return now;
}

fn _mgc_chain_mark_best(MgcChain* c, int tip_index) -> void {
    if (c == null) { return; }
    for (int i = 0; i < c.capacity; i = i + 1) { c.in_best[i] = 0; }
    int cur = tip_index;
    int guard = 0;
    while (cur >= 0 && cur < c.count && guard <= c.count) {
        c.in_best[cur] = 1;
        cur = c.parents[cur];
        guard = guard + 1;
    }
}

fn mgc_chain_rebuild_utxo(MgcChain* c, int tip_index) -> bool {
    if (c == null || c.utxo == null || tip_index < 0 || tip_index >= c.count) { return false; }
    int* chain = alloc<int>(c.count);
    if (chain == null) { return false; }
    int n = 0;
    int cur = tip_index;
    int guard = 0;
    while (cur >= 0 && cur < c.count && guard <= c.capacity) {
        chain[n] = cur;
        n = n + 1;
        cur = c.parents[cur];
        guard = guard + 1;
    }
    bool ok = (cur == -1 && n > 0 && chain[n - 1] == 0);
    if (ok) {
        mgc_utxo_clear(c.utxo);
        for (int i = n - 1; i >= 0 && ok; i = i - 1) {
            int idx = chain[i];
            MgcBlock* blk = c.blocks[idx];
            if (blk == null) { ok = false; break; }
            ok = mgc_consensus_apply_block(blk, c.utxo, c.heights[idx], c.network);
        }
    }
    free(chain);
    return ok;
}

fn mgc_chain_add_block(MgcChain* c, MgcBlock* b, bool* reorg) -> bool {
    if (reorg != null) { *reorg = false; }
    if (c == null || b == null || c.utxo == null || c.count <= 0 ||
        c.best_tip < 0 || c.count >= c.capacity) {
        if (b != null) { mgc_block_free(b); free(b); }
        return false;
    }

    char* hash = alloc<char>(32);
    if (hash == null) { mgc_block_free(b); free(b); return false; }
    bool ok = mgc_block_hash(b, hash);
    if (ok) { ok = mgc_chain_find(c, hash) < 0; }
    if (!ok) {
        free(hash);
        mgc_block_free(b);
        free(b);
        return false;
    }
    int parent = mgc_chain_find(c, b.prev_block);
    if (parent < 0) {
        free(hash);
        mgc_block_free(b);
        free(b);
        return false;
    }
    int height = c.heights[parent] + 1;
    int expected_bits = _mgc_chain_expected_bits_for(c, parent);
    int old_tip = c.best_tip;
    bool need_restore = false;
    bool verify_ok = false;
    if (parent != old_tip) {
        need_restore = true;
        if (mgc_chain_rebuild_utxo(c, parent)) {
            char* ph = alloc<char>(32);
            if (ph != null) {
                char* src = c.hashes + parent * 32;
                mgc_copy(ph, src, 32);
                int fees = 0;
                verify_ok = mgc_consensus_verify_block(b, c.utxo, height, c.network, expected_bits, ph, &fees);
                free(ph);
            }
        }
    } else {
        char* ph = alloc<char>(32);
        if (ph != null) {
            char* src = c.hashes + parent * 32;
            mgc_copy(ph, src, 32);
            int fees = 0;
            verify_ok = mgc_consensus_verify_block(b, c.utxo, height, c.network, expected_bits, ph, &fees);
            free(ph);
        }
    }
    if (!verify_ok) {
        if (need_restore) { mgc_chain_rebuild_utxo(c, old_tip); }
        free(hash);
        mgc_block_free(b);
        free(b);
        return false;
    }

    int index = c.count;
    int* work_add = alloc<int>(16);
    int* parent_work = alloc<int>(16);
    if (work_add == null || parent_work == null) {
        if (work_add != null) { free(work_add); }
        if (parent_work != null) { free(parent_work); }
        if (need_restore) { mgc_chain_rebuild_utxo(c, old_tip); }
        free(hash);
        mgc_block_free(b);
        free(b);
        return false;
    }
    _mgc_chain_work_get(c, parent, parent_work);
    mgc_pow_work_for_bits(b.bits, work_add);
    mgc_pow_work_add(parent_work, work_add);
    _mgc_chain_work_set(c, index, parent_work);
    free(work_add);
    free(parent_work);

    c.blocks[index] = b;
    mgc_copy(c.hashes + index * 32, hash, 32);
    c.parents[index] = parent;
    c.heights[index] = height;
    c.bitses[index] = b.bits;
    c.in_best[index] = 0;
    c.count = index + 1;

    int* cw = alloc<int>(16);
    int* nw = alloc<int>(16);
    if (cw == null || nw == null) {
        if (cw != null) { free(cw); }
        if (nw != null) { free(nw); }
        if (need_restore) { mgc_chain_rebuild_utxo(c, old_tip); }
        c.blocks[index] = null;
        c.count = index;
        free(hash);
        mgc_block_free(b);
        free(b);
        return false;
    }
    _mgc_chain_work_get(c, old_tip, cw);
    _mgc_chain_work_get(c, index, nw);
    int chosen = old_tip;
    if (mgc_big_cmp(nw, cw) > 0) { chosen = index; }
    free(cw);
    free(nw);

    if (chosen == index) {
        bool apply_ok = false;
        if (parent == old_tip) {
            apply_ok = mgc_consensus_apply_block(b, c.utxo, height, c.network);
        } else {
            apply_ok = mgc_chain_rebuild_utxo(c, index);
        }
        if (!apply_ok) {
            if (need_restore) { mgc_chain_rebuild_utxo(c, old_tip); }
            c.blocks[index] = null;
            c.count = index;
            free(hash);
            mgc_block_free(b);
            free(b);
            return false;
        }
        _mgc_chain_mark_best(c, index);
        c.best_tip = index;
        if (parent != old_tip && reorg != null) { *reorg = true; }
    } else {
        if (need_restore) { mgc_chain_rebuild_utxo(c, old_tip); }
    }
    free(hash);
    return true;
}
