// Magnetar Coin — custom SIGHASH_ALL digest covering all inputs and outputs.

use "tx.mg";

const int MGC_SIGHASH_ALL = 1;

fn mgc_sighash(MgcTx* tx, int input_index, int* prev_values, char** prev_scripts,
               int* prev_script_lens, int chain_id, char* out32) -> bool {
    if (tx == null || out32 == null || prev_values == null || prev_scripts == null ||
        prev_script_lens == null) { return false; }
    if (tx.in_count <= 0 || input_index < 0 || input_index >= tx.in_count) { return false; }

    for (int i = 0; i < tx.in_count; i = i + 1) {
        int slen = prev_script_lens[i];
        if (slen < 0 || slen > MGC_TX_MAX_SCRIPT) { return false; }
        if (slen > 0 && prev_scripts[i] == null) { return false; }
    }
    for (int i = 0; i < tx.out_count; i = i + 1) {
        int slen = tx.output_script_lens[i];
        if (slen < 0 || slen > MGC_TX_MAX_SCRIPT) { return false; }
        if (slen > 0 && tx.output_scripts[i] == null) { return false; }
    }

    ByteWriter w;
    bw_init(&w, 512);
    if (!w.ok) { return false; }

    bool ok = true;
    ok = ok && bw_write_bytes(&w, cast<char*>("MGC-SIGHASH-v1"), 14);
    ok = ok && bw_write_u32(&w, chain_id);
    ok = ok && bw_write_u32(&w, tx.version);
    ok = ok && bw_write_u32(&w, tx.locktime);
    ok = ok && bw_write_varint(&w, tx.in_count);

    for (int i = 0; ok && i < tx.in_count; i = i + 1) {
        char* txid = tx.prev_txids + i * 32;
        int prev_index = tx.prev_indices[i];
        int value = prev_values[i];
        int slen = prev_script_lens[i];
        ok = ok && bw_write_bytes(&w, txid, 32);
        ok = ok && bw_write_u32(&w, prev_index);
        ok = ok && bw_write_u64(&w, value);
        ok = ok && bw_write_varint(&w, slen);
        if (slen > 0) { ok = ok && bw_write_bytes(&w, prev_scripts[i], slen); }
    }

    ok = ok && bw_write_varint(&w, tx.out_count);
    for (int i = 0; ok && i < tx.out_count; i = i + 1) {
        int value = tx.output_values[i];
        int slen = tx.output_script_lens[i];
        ok = ok && bw_write_u64(&w, value);
        ok = ok && bw_write_varint(&w, slen);
        if (slen > 0) { ok = ok && bw_write_bytes(&w, tx.output_scripts[i], slen); }
    }

    ok = ok && bw_write_u32(&w, input_index);
    ok = ok && bw_write_u32(&w, MGC_SIGHASH_ALL);

    if (ok) { mgc_sha256d_raw(w.data, w.length, out32); }
    bw_free(&w);
    return ok;
}
