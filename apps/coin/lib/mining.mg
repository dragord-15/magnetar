// Magnetar Coin — block template assembly and nonce search.

use "chain.mg";
use "mempool.mg";
use "consensus.mg";
use "block.mg";
use "tx.mg";
use "script.mg";
use "params.mg";
use "pow.mg";
use "hash.mg";
use "endian.mg";
use "util.mg";

fn mgc_mining_build_block(MgcChain* c, MgcMempool* mp, char* payout_script, int payout_len, MgcBlock* out) -> bool {
    if (c == null || mp == null || out == null || payout_script == null || payout_len <= 0) { return false; }
    mgc_block_init(out);
    out.version = 1;
    out.bits = mgc_chain_expected_bits(c);
    out.timestamp = mgc_chain_next_timestamp(c);
    out.nonce = 0;

    char* tip = alloc<char>(32);
    if (tip == null) { return false; }
    bool ok = mgc_chain_tip_hash(c, tip);
    if (ok) { mgc_copy(out.prev_block, tip, 32); }
    free(tip);
    if (!ok) { return false; }

    int height = mgc_chain_height(c) + 1;
    int mp_count = mgc_mempool_count(mp);
    int limit = mgc_max_money();
    int fees = 0;
    for (int i = 0; i < mp_count && ok; i = i + 1) {
        MgcTx* tx = mgc_mempool_get(mp, i);
        int f = 0;
        if (!mgc_consensus_tx_fee(tx, c.utxo, &f)) { ok = false; break; }
        if (f < 0 || f > limit - fees) { ok = false; break; }
        fees = fees + f;
    }
    if (!ok) { return false; }
    int subsidy = mgc_consensus_subsidy(c.network, height);
    int reward = subsidy + fees;
    if (reward < subsidy || reward < fees || reward > limit) { return false; }

    MgcTx* cb = alloc<MgcTx>(1);
    if (cb == null) { return false; }
    mgc_tx_init(cb);
    char* zero32 = alloc<char>(32);
    char* hbuf = alloc<char>(4);
    char* cb_script = alloc<char>(256);
    if (zero32 == null || hbuf == null || cb_script == null) {
        if (zero32 != null) { free(zero32); }
        if (hbuf != null) { free(hbuf); }
        if (cb_script != null) { free(cb_script); }
        mgc_tx_free(cb);
        free(cb);
        return false;
    }
    mgc_zero(zero32, 32);
    endian_write_u32_le(hbuf, 0, height);
    int cb_len = 0;
    ok = mgc_script_coinbase(hbuf, 4, cb_script, &cb_len);
    if (ok) { ok = mgc_tx_add_input(cb, zero32, 4294967295, cb_script, cb_len, 4294967295); }
    if (ok) { ok = mgc_tx_add_output(cb, reward, payout_script, payout_len); }
    if (ok) { ok = mgc_block_add_tx(out, cb, false); }
    if (!ok) {
        mgc_tx_free(cb);
        free(cb);
        free(cb_script);
        free(hbuf);
        free(zero32);
        mgc_block_free(out);
        return false;
    }

    for (int i = 0; i < mp_count && ok; i = i + 1) {
        MgcTx* tx = mgc_mempool_get(mp, i);
        ok = mgc_block_add_tx(out, tx, true);
    }
    if (ok) {
        char* root = out.merkle_root;
        ok = mgc_block_merkle_root(out, root);
    }
    free(cb_script);
    free(hbuf);
    free(zero32);
    if (!ok) { mgc_block_free(out); return false; }
    return true;
}

fn mgc_mining_mine(MgcBlock* b, int max_attempts, int* attempts) -> bool {
    if (attempts != null) { *attempts = 0; }
    if (b == null || attempts == null || max_attempts <= 0) { return false; }
    char* header = alloc<char>(80);
    char* hash = alloc<char>(32);
    if (header == null || hash == null) {
        if (header != null) { free(header); }
        if (hash != null) { free(hash); }
        return false;
    }
    int tried = 0;
    bool found = false;
    for (int nonce = 0; nonce < max_attempts; nonce = nonce + 1) {
        b.nonce = nonce;
        mgc_block_header(b, header);
        mgc_sha256d_raw(header, 80, hash);
        tried = tried + 1;
        if (mgc_pow_check(hash, b.bits)) { found = true; break; }
    }
    *attempts = tried;
    free(hash);
    free(header);
    return found;
}
