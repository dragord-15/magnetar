// Magnetar Coin — consensus rules: subsidy, fees, verification and application.

use "block.mg";
use "utxo.mg";
use "sighash.mg";
use "script.mg";
use "pow.mg";
use "secp256k1.mg";
use "hash.mg";
use "params.mg";
use "util.mg";
use "endian.mg";
use "bigint.mg";

fn mgc_consensus_subsidy(int network, int height) -> int {
    if (height < 0) { return mgc_initial_subsidy(); }
    int interval = mgc_halving_interval(network);
    if (interval <= 0) { return mgc_initial_subsidy(); }
    int halvings = height / interval;
    int subsidy = mgc_initial_subsidy();
    for (int i = 0; i < halvings; i = i + 1) {
        subsidy = subsidy / 2;
        if (subsidy == 0) { return 0; }
    }
    return subsidy;
}

fn _mgc_consensus_has_duplicate_input(MgcTx* tx) -> bool {
    if (tx == null || tx.in_count <= 1) { return false; }
    if (tx.prev_txids == null || tx.prev_indices == null) { return true; }
    for (int i = 0; i < tx.in_count; i = i + 1) {
        for (int j = 0; j < i; j = j + 1) {
            if (tx.prev_indices[i] == tx.prev_indices[j] &&
                mgc_equal(tx.prev_txids + i * 32, tx.prev_txids + j * 32, 32)) {
                return true;
            }
        }
    }
    return false;
}

fn mgc_consensus_tx_fee(MgcTx* tx, MgcUtxoSet* utxo, int* fee) -> bool {
    if (fee != null) { *fee = 0; }
    if (tx == null || utxo == null || fee == null) { return false; }
    if (mgc_block_is_coinbase(tx)) { return false; }
    if (_mgc_consensus_has_duplicate_input(tx)) { return false; }
    if (tx.in_count <= 0 || tx.prev_txids == null || tx.prev_indices == null) { return false; }
    if (tx.out_count < 0 || (tx.out_count > 0 && tx.output_values == null)) { return false; }
    int limit = mgc_max_money();
    int total_in = 0;
    for (int i = 0; i < tx.in_count; i = i + 1) {
        char* tid = tx.prev_txids + i * 32;
        int idx = tx.prev_indices[i];
        MgcUtxo prev;
        if (!mgc_utxo_get(utxo, tid, idx, &prev)) { return false; }
        int v = prev.value;
        mgc_utxo_result_free(&prev);
        if (v < 0 || v > limit - total_in) { return false; }
        total_in = total_in + v;
    }
    int total_out = 0;
    for (int i = 0; i < tx.out_count; i = i + 1) {
        int v = tx.output_values[i];
        if (v < 0 || v > limit - total_out) { return false; }
        total_out = total_out + v;
    }
    if (total_in < total_out) { return false; }
    *fee = total_in - total_out;
    return true;
}

fn mgc_consensus_verify_tx(MgcTx* tx, MgcUtxoSet* utxo, int height, int network, int chain_id, int* fee) -> bool {
    if (fee != null) { *fee = 0; }
    if (tx == null || utxo == null || fee == null) { return false; }
    if (mgc_block_is_coinbase(tx)) { return false; }
    if (_mgc_consensus_has_duplicate_input(tx)) { return false; }
    if (tx.in_count <= 0 || tx.out_count <= 0) { return false; }
    if (tx.prev_txids == null || tx.prev_indices == null || tx.input_scripts == null ||
        tx.input_script_lens == null || tx.output_values == null || tx.output_scripts == null ||
        tx.output_script_lens == null) { return false; }
    int limit = mgc_max_money();
    int total_out = 0;
    for (int i = 0; i < tx.out_count; i = i + 1) {
        int v = tx.output_values[i];
        int slen = tx.output_script_lens[i];
        char* sc = tx.output_scripts[i];
        if (v < 0 || slen < 0 || (slen > 0 && sc == null)) { return false; }
        if (v > limit - total_out) { return false; }
        total_out = total_out + v;
    }

    int count = tx.in_count;
    int* values = alloc<int>(count);
    char** scripts = alloc<char*>(count);
    int* lens = alloc<int>(count);
    if (values == null || scripts == null || lens == null) {
        if (values != null) { free(values); }
        if (scripts != null) { free(scripts); }
        if (lens != null) { free(lens); }
        return false;
    }
    for (int i = 0; i < count; i = i + 1) {
        values[i] = 0;
        scripts[i] = null;
        lens[i] = 0;
    }

    bool ok = true;
    int total_in = 0;
    int maturity = mgc_coinbase_maturity(network);
    for (int i = 0; i < count && ok; i = i + 1) {
        char* tid = tx.prev_txids + i * 32;
        int idx = tx.prev_indices[i];
        MgcUtxo prev;
        if (!mgc_utxo_get(utxo, tid, idx, &prev)) { ok = false; break; }
        int v = prev.value;
        int slen = prev.script_len;
        bool good = true;
        if (prev.coinbase && prev.height + maturity > height) { good = false; }
        if (v < 0 || slen < 0 || (slen > 0 && prev.script == null)) { good = false; }
        if (good && v > limit - total_in) { good = false; }
        if (!good) {
            mgc_utxo_result_free(&prev);
            ok = false;
            break;
        }
        scripts[i] = prev.script;
        lens[i] = slen;
        values[i] = v;
        prev.script = null;
        total_in = total_in + v;
    }
    if (ok && total_in < total_out) { ok = false; }

    if (ok) {
        for (int i = 0; i < count && ok; i = i + 1) {
            char* digest = alloc<char>(32);
            char* h160 = alloc<char>(20);
            char* expected = alloc<char>(20);
            if (digest == null || h160 == null || expected == null) {
                if (digest != null) { free(digest); }
                if (h160 != null) { free(h160); }
                if (expected != null) { free(expected); }
                ok = false;
                break;
            }
            ok = mgc_sighash(tx, i, values, scripts, lens, chain_id, digest);
            if (ok) {
                char* ins = tx.input_scripts[i];
                int inslen = tx.input_script_lens[i];
                char* sig = null;
                int sig_len = 0;
                char* pub = null;
                int pub_len = 0;
                ok = mgc_script_parse_p2pkh_sig(ins, inslen, &sig, &sig_len, &pub, &pub_len);
                if (ok) { mgc_hash160(pub, pub_len, h160); }
                if (ok) {
                    char* ps = scripts[i];
                    int pl = lens[i];
                    ok = mgc_script_p2pkh_hash160(ps, pl, expected) && mgc_equal(h160, expected, 20);
                }
                if (ok) { ok = secp_ecdsa_verify(digest, pub, pub_len, sig, sig_len); }
            }
            free(expected);
            free(h160);
            free(digest);
        }
    }

    for (int i = 0; i < count; i = i + 1) {
        if (scripts[i] != null) { free(scripts[i]); }
    }
    free(scripts);
    free(values);
    free(lens);
    if (ok) { *fee = total_in - total_out; }
    return ok;
}

fn _mgc_consensus_spend_inputs(MgcTx* tx, MgcUtxoSet* utxo) -> bool {
    if (tx == null || utxo == null || tx.in_count < 0) { return false; }
    if (tx.in_count == 0) { return true; }
    if (tx.prev_txids == null || tx.prev_indices == null) { return false; }
    for (int i = 0; i < tx.in_count; i = i + 1) {
        char* tid = tx.prev_txids + i * 32;
        int idx = tx.prev_indices[i];
        if (!mgc_utxo_spend(utxo, tid, idx, null)) { return false; }
    }
    return true;
}

fn _mgc_consensus_add_outputs(MgcTx* tx, MgcUtxoSet* utxo, int height, bool is_coinbase) -> bool {
    if (tx == null || utxo == null || tx.out_count < 0) { return false; }
    if (tx.out_count == 0) { return true; }
    if (tx.output_values == null || tx.output_scripts == null || tx.output_script_lens == null) { return false; }
    char* tid = alloc<char>(32);
    if (tid == null) { return false; }
    if (!mgc_tx_txid(tx, tid)) { free(tid); return false; }
    bool ok = true;
    int limit = mgc_max_money();
    int sum = 0;
    for (int i = 0; i < tx.out_count && ok; i = i + 1) {
        int v = tx.output_values[i];
        int slen = tx.output_script_lens[i];
        char* sc = tx.output_scripts[i];
        if (v < 0 || slen < 0 || (slen > 0 && sc == null)) { ok = false; break; }
        if (v > limit - sum) { ok = false; break; }
        sum = sum + v;
        ok = mgc_utxo_add(utxo, tid, i, v, sc, slen, height, is_coinbase);
    }
    free(tid);
    return ok;
}

fn mgc_consensus_apply_tx(MgcTx* tx, MgcUtxoSet* utxo, int height, bool is_coinbase) -> bool {
    if (tx == null || utxo == null) { return false; }
    if (!_mgc_consensus_spend_inputs(tx, utxo)) { return false; }
    return _mgc_consensus_add_outputs(tx, utxo, height, is_coinbase);
}

fn mgc_consensus_verify_block(MgcBlock* b, MgcUtxoSet* utxo, int height, int network, int expected_bits,
                              char* prev_hash32, int* total_fees) -> bool {
    if (total_fees != null) { *total_fees = 0; }
    if (b == null || utxo == null || total_fees == null || prev_hash32 == null) { return false; }
    int size = mgc_block_serialized_size(b);
    if (size <= 0 || size > MGC_MAX_BLOCK_BYTES) { return false; }
    if (b.tx_count < 1 || b.txs == null || b.timestamp <= 0) { return false; }
    if (!mgc_block_is_coinbase(b.txs[0])) { return false; }
    for (int i = 1; i < b.tx_count; i = i + 1) {
        if (b.txs[i] == null || mgc_block_is_coinbase(b.txs[i])) { return false; }
    }
    if (!mgc_equal(b.prev_block, prev_hash32, 32)) { return false; }
    if (b.bits != expected_bits) { return false; }

    char* hash = alloc<char>(32);
    if (hash == null) { return false; }
    bool ok = mgc_block_hash(b, hash);
    if (ok) { ok = mgc_pow_check(hash, b.bits); }
    free(hash);
    if (!ok) { return false; }

    char* root = alloc<char>(32);
    if (root == null) { return false; }
    ok = mgc_block_merkle_root(b, root);
    if (ok) { ok = mgc_equal(root, b.merkle_root, 32); }
    free(root);
    if (!ok) { return false; }

    int fees = 0;
    int limit = mgc_max_money();
    for (int i = 1; i < b.tx_count && ok; i = i + 1) {
        MgcTx* tx = b.txs[i];
        int f = 0;
        if (!mgc_consensus_tx_fee(tx, utxo, &f)) { ok = false; break; }
        if (f < 0 || f > limit - fees) { ok = false; break; }
        fees = fees + f;
    }
    if (!ok) { return false; }

    MgcTx* cb = b.txs[0];
    if (cb.out_count < 1 || cb.output_values == null) { return false; }
    int cb_sum = 0;
    for (int i = 0; i < cb.out_count; i = i + 1) {
        int v = cb.output_values[i];
        if (v < 0 || v > limit - cb_sum) { return false; }
        cb_sum = cb_sum + v;
    }
    int subsidy = mgc_consensus_subsidy(network, height);
    int allowed = subsidy + fees;
    if (allowed < subsidy || allowed < fees) { return false; }
    if (cb_sum > allowed) { return false; }

    int mark = mgc_utxo_mark(utxo);
    if (mark < 0) { return false; }
    int chain = mgc_chain_id(network);
    for (int i = 1; i < b.tx_count && ok; i = i + 1) {
        MgcTx* tx = b.txs[i];
        int f = 0;
        if (!mgc_consensus_verify_tx(tx, utxo, height, network, chain, &f)) { ok = false; break; }
        if (!mgc_consensus_apply_tx(tx, utxo, height, false)) { ok = false; break; }
    }
    mgc_utxo_rollback(utxo, mark);
    if (!ok) { return false; }
    *total_fees = fees;
    return true;
}

fn mgc_consensus_apply_block(MgcBlock* b, MgcUtxoSet* utxo, int height, int network) -> bool {
    if (b == null || utxo == null || b.tx_count < 1 || b.txs == null) { return false; }
    for (int i = 1; i < b.tx_count; i = i + 1) {
        MgcTx* tx = b.txs[i];
        if (tx == null || mgc_block_is_coinbase(tx)) { return false; }
        if (!_mgc_consensus_spend_inputs(tx, utxo)) { return false; }
    }
    for (int i = 0; i < b.tx_count; i = i + 1) {
        MgcTx* tx = b.txs[i];
        if (tx == null) { return false; }
        bool iscb = mgc_block_is_coinbase(tx);
        if (!_mgc_consensus_add_outputs(tx, utxo, height, iscb)) { return false; }
    }
    return true;
}
