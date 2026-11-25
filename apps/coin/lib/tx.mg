// Magnetar Coin — v0 transaction model and consensus serialization.
// No SegWit. Amounts are signed 64-bit satoshis (Magnetar `int`).
// Flat arrays are used instead of arrays of structs to avoid compiler limits.

use "hash.mg";
use "serialization.mg";
use "util.mg";

const int MGC_TX_MAX_INPUTS  = 10000;
const int MGC_TX_MAX_OUTPUTS = 10000;
const int MGC_TX_MAX_SCRIPT  = 100000;

struct MgcTx {
    int version;
    int in_count;
    char* prev_txids;          // 32 * in_count
    int* prev_indices;
    char** input_scripts;      // owned byte arrays
    int* input_script_lens;
    int* input_sequences;
    int out_count;
    int* output_values;
    char** output_scripts;     // owned byte arrays
    int* output_script_lens;
    int locktime;
}

fn mgc_tx_init(MgcTx* tx) -> void {
    if (tx == null) { return; }
    tx.version = 1;
    tx.in_count = 0;
    tx.prev_txids = null;
    tx.prev_indices = null;
    tx.input_scripts = null;
    tx.input_script_lens = null;
    tx.input_sequences = null;
    tx.out_count = 0;
    tx.output_values = null;
    tx.output_scripts = null;
    tx.output_script_lens = null;
    tx.locktime = 0;
}

fn mgc_tx_free(MgcTx* tx) -> void {
    if (tx == null) { return; }
    for (int i = 0; i < tx.in_count; i = i + 1) {
        if (tx.input_scripts != null && tx.input_scripts[i] != null) {
            free(tx.input_scripts[i]);
        }
    }
    for (int i = 0; i < tx.out_count; i = i + 1) {
        if (tx.output_scripts != null && tx.output_scripts[i] != null) {
            free(tx.output_scripts[i]);
        }
    }
    if (tx.prev_txids != null) { free(tx.prev_txids); }
    if (tx.prev_indices != null) { free(tx.prev_indices); }
    if (tx.input_scripts != null) { free(tx.input_scripts); }
    if (tx.input_script_lens != null) { free(tx.input_script_lens); }
    if (tx.input_sequences != null) { free(tx.input_sequences); }
    if (tx.output_values != null) { free(tx.output_values); }
    if (tx.output_scripts != null) { free(tx.output_scripts); }
    if (tx.output_script_lens != null) { free(tx.output_script_lens); }
    mgc_tx_init(tx);
}

fn mgc_tx_add_input(MgcTx* tx, char* prev_txid, int prev_index, char* script, int script_len, int sequence) -> bool {
    if (tx == null || prev_txid == null || script_len < 0 || script_len > MGC_TX_MAX_SCRIPT) { return false; }
    if (tx.in_count >= MGC_TX_MAX_INPUTS - 1) { return false; }
    int n = tx.in_count;

    char* ntxids = alloc<char>((n + 1) * 32);
    int* nindices = alloc<int>(n + 1);
    char** nscripts = alloc<char*>(n + 1);
    int* nscript_lens = alloc<int>(n + 1);
    int* nsequences = alloc<int>(n + 1);
    if (ntxids == null || nindices == null || nscripts == null || nscript_lens == null || nsequences == null) {
        if (ntxids != null) { free(ntxids); }
        if (nindices != null) { free(nindices); }
        if (nscripts != null) { free(nscripts); }
        if (nscript_lens != null) { free(nscript_lens); }
        if (nsequences != null) { free(nsequences); }
        return false;
    }

    if (n > 0) {
        mgc_copy(ntxids, tx.prev_txids, n * 32);
        for (int i = 0; i < n; i = i + 1) {
            nindices[i] = tx.prev_indices[i];
            nscripts[i] = tx.input_scripts[i];
            nscript_lens[i] = tx.input_script_lens[i];
            nsequences[i] = tx.input_sequences[i];
        }
    }
    mgc_copy(ntxids + n * 32, prev_txid, 32);
    nindices[n] = prev_index;
    nscripts[n] = null;
    if (script_len > 0) {
        nscripts[n] = alloc<char>(script_len);
        if (nscripts[n] == null) {
            if (n > 0) { /* keep old pointers: do not free nscripts[0..n-1] */ }
            free(ntxids); free(nindices); free(nscripts); free(nscript_lens); free(nsequences);
            return false;
        }
        mgc_copy(nscripts[n], script, script_len);
    }
    nscript_lens[n] = script_len;
    nsequences[n] = sequence;

    if (tx.prev_txids != null) { free(tx.prev_txids); }
    if (tx.prev_indices != null) { free(tx.prev_indices); }
    if (tx.input_scripts != null) { free(tx.input_scripts); }
    if (tx.input_script_lens != null) { free(tx.input_script_lens); }
    if (tx.input_sequences != null) { free(tx.input_sequences); }
    tx.prev_txids = ntxids;
    tx.prev_indices = nindices;
    tx.input_scripts = nscripts;
    tx.input_script_lens = nscript_lens;
    tx.input_sequences = nsequences;
    tx.in_count = n + 1;
    return true;
}

fn mgc_tx_add_output(MgcTx* tx, int value, char* script, int script_len) -> bool {
    if (tx == null || value < 0 || script_len < 0 || script_len > MGC_TX_MAX_SCRIPT) { return false; }
    if (tx.out_count >= MGC_TX_MAX_OUTPUTS - 1) { return false; }
    int n = tx.out_count;

    int* nvalues = alloc<int>(n + 1);
    char** nscripts = alloc<char*>(n + 1);
    int* nscript_lens = alloc<int>(n + 1);
    if (nvalues == null || nscripts == null || nscript_lens == null) {
        if (nvalues != null) { free(nvalues); }
        if (nscripts != null) { free(nscripts); }
        if (nscript_lens != null) { free(nscript_lens); }
        return false;
    }
    if (n > 0) {
        for (int i = 0; i < n; i = i + 1) {
            nvalues[i] = tx.output_values[i];
            nscripts[i] = tx.output_scripts[i];
            nscript_lens[i] = tx.output_script_lens[i];
        }
    }
    nvalues[n] = value;
    nscripts[n] = null;
    if (script_len > 0) {
        nscripts[n] = alloc<char>(script_len);
        if (nscripts[n] == null) {
            free(nvalues); free(nscripts); free(nscript_lens);
            return false;
        }
        mgc_copy(nscripts[n], script, script_len);
    }
    nscript_lens[n] = script_len;

    if (tx.output_values != null) { free(tx.output_values); }
    if (tx.output_scripts != null) { free(tx.output_scripts); }
    if (tx.output_script_lens != null) { free(tx.output_script_lens); }
    tx.output_values = nvalues;
    tx.output_scripts = nscripts;
    tx.output_script_lens = nscript_lens;
    tx.out_count = n + 1;
    return true;
}

fn mgc_tx_in_script(MgcTx* tx, int index) -> char* {
    if (tx == null || index < 0 || index >= tx.in_count) { return null; }
    return tx.input_scripts[index];
}

fn mgc_tx_set_input_script(MgcTx* tx, int index, char* script, int script_len) -> bool {
    if (tx == null || index < 0 || index >= tx.in_count || script_len < 0 || script_len > MGC_TX_MAX_SCRIPT) { return false; }
    if (script_len == 0) {
        if (tx.input_scripts[index] != null) { free(tx.input_scripts[index]); }
        tx.input_scripts[index] = null;
        tx.input_script_lens[index] = 0;
        return true;
    }
    if (script == null) { return false; }
    char* fresh = alloc<char>(script_len);
    if (fresh == null) { return false; }
    mgc_copy(fresh, script, script_len);
    if (tx.input_scripts[index] != null) { free(tx.input_scripts[index]); }
    tx.input_scripts[index] = fresh;
    tx.input_script_lens[index] = script_len;
    return true;
}

fn mgc_tx_out_script(MgcTx* tx, int index) -> char* {
    if (tx == null || index < 0 || index >= tx.out_count) { return null; }
    return tx.output_scripts[index];
}

fn _mgc_tx_write(MgcTx* tx, bool with_scripts, ByteWriter* w) -> bool {
    if (tx == null || w == null || !w.ok) { return false; }
    if (!bw_write_u32(w, tx.version)) { return false; }
    if (!bw_write_varint(w, tx.in_count)) { return false; }
    for (int i = 0; i < tx.in_count; i = i + 1) {
        if (!bw_write_bytes(w, tx.prev_txids + i * 32, 32)) { return false; }
        if (!bw_write_u32(w, tx.prev_indices[i])) { return false; }
        int slen = 0;
        if (with_scripts) { slen = tx.input_script_lens[i]; }
        if (!bw_write_varint(w, slen)) { return false; }
        if (slen > 0 && !bw_write_bytes(w, tx.input_scripts[i], slen)) { return false; }
        if (!bw_write_u32(w, tx.input_sequences[i])) { return false; }
    }
    if (!bw_write_varint(w, tx.out_count)) { return false; }
    for (int i = 0; i < tx.out_count; i = i + 1) {
        if (!bw_write_u64(w, tx.output_values[i])) { return false; }
        int slen = tx.output_script_lens[i];
        if (!bw_write_varint(w, slen)) { return false; }
        if (slen > 0 && !bw_write_bytes(w, tx.output_scripts[i], slen)) { return false; }
    }
    if (!bw_write_u32(w, tx.locktime)) { return false; }
    return w.ok;
}

fn mgc_tx_serialize(MgcTx* tx, bool with_scripts, int* out_len) -> char* {
    if (out_len != null) { *out_len = 0; }
    if (tx == null) { return null; }
    ByteWriter w;
    bw_init(&w, 128);
    if (!w.ok) { return null; }
    if (!_mgc_tx_write(tx, with_scripts, &w)) {
        bw_free(&w);
        return null;
    }
    char* data = w.data;
    if (out_len != null) { *out_len = w.length; }
    w.data = null;
    bw_free(&w);
    return data;
}

fn _mgc_tx_read_bytes_into(ByteReader* r, char** out, int* out_len, int count) -> bool {
    if (out == null || out_len == null || count < 0) { return false; }
    *out = null;
    *out_len = count;
    if (count == 0) { return true; }
    char* buf = alloc<char>(count);
    if (buf == null) { return false; }
    if (!br_read_bytes(r, buf, count)) { free(buf); return false; }
    *out = buf;
    return true;
}

fn mgc_tx_deserialize(char* data, int length, MgcTx* tx) -> bool {
    if (data == null || length <= 0 || tx == null) { return false; }
    mgc_tx_init(tx);
    ByteReader r;
    br_init(&r, data, length);
    if (!r.ok) { return false; }

    tx.version = br_read_u32(&r);
    int n = br_read_varint(&r);
    if (!r.ok || n < 0 || n > MGC_TX_MAX_INPUTS) { mgc_tx_free(tx); return false; }

    if (n > 0) {
        tx.prev_txids = alloc<char>(n * 32);
        tx.prev_indices = alloc<int>(n);
        tx.input_scripts = alloc<char*>(n);
        tx.input_script_lens = alloc<int>(n);
        tx.input_sequences = alloc<int>(n);
        if (tx.prev_txids == null || tx.prev_indices == null || tx.input_scripts == null || tx.input_script_lens == null || tx.input_sequences == null) {
            mgc_tx_free(tx); return false;
        }
        for (int i = 0; i < n; i = i + 1) {
            tx.input_scripts[i] = null;
            tx.input_script_lens[i] = 0;
        }
    }
    tx.in_count = n;

    for (int i = 0; i < n; i = i + 1) {
        if (!br_read_bytes(&r, tx.prev_txids + i * 32, 32)) { mgc_tx_free(tx); return false; }
        tx.prev_indices[i] = br_read_u32(&r);
        int slen = br_read_varint(&r);
        if (!r.ok || slen < 0 || slen > MGC_TX_MAX_SCRIPT) { mgc_tx_free(tx); return false; }
        char* script = null;
        int script_len = 0;
        if (!_mgc_tx_read_bytes_into(&r, &script, &script_len, slen)) { mgc_tx_free(tx); return false; }
        tx.input_scripts[i] = script;
        tx.input_script_lens[i] = script_len;
        tx.input_sequences[i] = br_read_u32(&r);
        if (!r.ok) { mgc_tx_free(tx); return false; }
    }

    int m = br_read_varint(&r);
    if (!r.ok || m < 0 || m > MGC_TX_MAX_OUTPUTS) { mgc_tx_free(tx); return false; }
    if (m > 0) {
        tx.output_values = alloc<int>(m);
        tx.output_scripts = alloc<char*>(m);
        tx.output_script_lens = alloc<int>(m);
        if (tx.output_values == null || tx.output_scripts == null || tx.output_script_lens == null) {
            mgc_tx_free(tx); return false;
        }
        for (int i = 0; i < m; i = i + 1) {
            tx.output_scripts[i] = null;
            tx.output_script_lens[i] = 0;
        }
    }
    tx.out_count = m;

    for (int i = 0; i < m; i = i + 1) {
        int value = br_read_u64(&r);
        if (!r.ok || value < 0) { mgc_tx_free(tx); return false; }
        tx.output_values[i] = value;
        int slen = br_read_varint(&r);
        if (!r.ok || slen < 0 || slen > MGC_TX_MAX_SCRIPT) { mgc_tx_free(tx); return false; }
        char* script = null;
        int script_len = 0;
        if (!_mgc_tx_read_bytes_into(&r, &script, &script_len, slen)) { mgc_tx_free(tx); return false; }
        tx.output_scripts[i] = script;
        tx.output_script_lens[i] = script_len;
    }

    tx.locktime = br_read_u32(&r);
    if (!r.ok || r.offset != length) { mgc_tx_free(tx); return false; }
    return true;
}

fn mgc_tx_txid(MgcTx* tx, char* out32) -> bool {
    if (tx == null || out32 == null) { return false; }
    int len = 0;
    char* data = mgc_tx_serialize(tx, true, &len);
    if (data == null) { return false; }
    mgc_sha256d_raw(data, len, out32);
    free(data);
    return true;
}

fn mgc_tx_txid_hex(MgcTx* tx) -> string {
    char* h = alloc<char>(32);
    if (h == null) { return ""; }
    if (!mgc_tx_txid(tx, h)) { free(h); return ""; }
    string hex = crypto_hex_encode(h, 32);
    free(h);
    return hex;
}
