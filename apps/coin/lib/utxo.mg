// Magnetar Coin — in-memory UTXO set with an open-addressing hash table and an undo journal.

use "util.mg";
use "endian.mg";

const int MGC_UTXO_KEY_SIZE = 36;
const int MGC_UTXO_SLOT_EMPTY = 0;
const int MGC_UTXO_SLOT_USED = 1;
const int MGC_UTXO_SLOT_DELETED = 2;
const int MGC_UTXO_OP_ADD = 1;
const int MGC_UTXO_OP_SPEND = 2;
const int MGC_UTXO_RECORD_BASE = 66;
const int MGC_UTXO_JOURNAL_INITIAL = 256;

struct MgcUtxo { int value; char* script; int script_len; int height; bool coinbase; }
struct MgcUtxoSet { int capacity; int count; int* states; char* keys; int* values; char** scripts;
                    int* script_lens; int* heights; bool* coinbase_flags;
                    char* journal; int journal_len; int journal_capacity; }

fn _mgc_utxo_fnv_basis() -> int { return 2166136261; }
fn _mgc_utxo_fnv_prime() -> int { return 16777619; }
fn _mgc_utxo_hash_mask() -> int { return 2147483647; }
fn _mgc_utxo_u32_mask() -> int { return 4294967295; }

fn _mgc_utxo_hash(char* txid32, int index) -> int {
    int h = _mgc_utxo_fnv_basis() & _mgc_utxo_hash_mask();
    int prime = _mgc_utxo_fnv_prime();
    int mask = _mgc_utxo_hash_mask();
    for (int i = 0; i < 32; i = i + 1) {
        h = h ^ (cast<int>(*(txid32 + i)) & 255);
        h = (h * prime) & mask;
    }
    int idx = index & _mgc_utxo_u32_mask();
    for (int i = 0; i < 4; i = i + 1) {
        h = h ^ ((idx >> (i * 8)) & 255);
        h = (h * prime) & mask;
    }
    return h;
}

fn mgc_utxo_init(MgcUtxoSet* set, int capacity) -> bool {
    if (set == null || capacity <= 0) { return false; }
    set.capacity = 0;
    set.count = 0;
    set.states = null;
    set.keys = null;
    set.values = null;
    set.scripts = null;
    set.script_lens = null;
    set.heights = null;
    set.coinbase_flags = null;
    set.journal = null;
    set.journal_len = 0;
    set.journal_capacity = 0;

    set.states = alloc<int>(capacity);
    set.keys = alloc<char>(capacity * MGC_UTXO_KEY_SIZE);
    set.values = alloc<int>(capacity);
    set.scripts = alloc<char*>(capacity);
    set.script_lens = alloc<int>(capacity);
    set.heights = alloc<int>(capacity);
    set.coinbase_flags = alloc<bool>(capacity);
    if (set.states == null || set.keys == null || set.values == null ||
        set.scripts == null || set.script_lens == null || set.heights == null ||
        set.coinbase_flags == null) {
        mgc_utxo_free(set);
        return false;
    }

    set.journal_capacity = MGC_UTXO_JOURNAL_INITIAL;
    set.journal = alloc<char>(set.journal_capacity);
    if (set.journal == null) {
        mgc_utxo_free(set);
        return false;
    }

    int* states = set.states;
    char* keys = set.keys;
    int* values = set.values;
    char** scripts = set.scripts;
    int* script_lens = set.script_lens;
    int* heights = set.heights;
    bool* coinbase_flags = set.coinbase_flags;
    mgc_zero(keys, capacity * MGC_UTXO_KEY_SIZE);
    for (int i = 0; i < capacity; i = i + 1) {
        states[i] = MGC_UTXO_SLOT_EMPTY;
        values[i] = 0;
        scripts[i] = null;
        script_lens[i] = 0;
        heights[i] = 0;
        coinbase_flags[i] = false;
    }
    set.capacity = capacity;
    return true;
}

fn mgc_utxo_free(MgcUtxoSet* set) -> void {
    if (set == null) { return; }
    int cap = set.capacity;
    char** scripts = set.scripts;
    if (scripts != null) {
        for (int i = 0; i < cap; i = i + 1) {
            if (scripts[i] != null) {
                free(scripts[i]);
                scripts[i] = null;
            }
        }
    }
    if (set.states != null) { free(set.states); }
    if (set.keys != null) { free(set.keys); }
    if (set.values != null) { free(set.values); }
    if (scripts != null) { free(scripts); }
    if (set.script_lens != null) { free(set.script_lens); }
    if (set.heights != null) { free(set.heights); }
    if (set.coinbase_flags != null) { free(set.coinbase_flags); }
    if (set.journal != null) { free(set.journal); }
    set.capacity = 0;
    set.count = 0;
    set.states = null;
    set.keys = null;
    set.values = null;
    set.scripts = null;
    set.script_lens = null;
    set.heights = null;
    set.coinbase_flags = null;
    set.journal = null;
    set.journal_len = 0;
    set.journal_capacity = 0;
}

fn mgc_utxo_find(MgcUtxoSet* set, char* txid32, int index) -> int {
    if (set == null || set.capacity <= 0 || set.states == null || set.keys == null ||
        txid32 == null || index < 0) { return -1; }
    int cap = set.capacity;
    int* states = set.states;
    char* keys = set.keys;
    int start = _mgc_utxo_hash(txid32, index) % cap;
    for (int probe = 0; probe < cap; probe = probe + 1) {
        int slot = (start + probe) % cap;
        int st = states[slot];
        if (st == MGC_UTXO_SLOT_EMPTY) { return -1; }
        if (st == MGC_UTXO_SLOT_USED) {
            int kbase = slot * MGC_UTXO_KEY_SIZE;
            if (mgc_equal(keys + kbase, txid32, 32) &&
                endian_read_u32_le(keys, kbase + 32) == index) {
                return slot;
            }
        }
    }
    return -1;
}

fn mgc_utxo_exists(MgcUtxoSet* set, char* txid32, int index) -> bool {
    return mgc_utxo_find(set, txid32, index) >= 0;
}

fn mgc_utxo_count(MgcUtxoSet* set) -> int {
    if (set == null) { return 0; }
    return set.count;
}

fn mgc_utxo_result_free(MgcUtxo* out) -> void {
    if (out == null) { return; }
    if (out.script != null) {
        free(out.script);
        out.script = null;
    }
    out.value = 0;
    out.script_len = 0;
    out.height = 0;
    out.coinbase = false;
}

fn mgc_utxo_get(MgcUtxoSet* set, char* txid32, int index, MgcUtxo* out) -> bool {
    if (out == null) { return false; }
    out.script = null;
    out.value = 0;
    out.script_len = 0;
    out.height = 0;
    out.coinbase = false;
    int slot = mgc_utxo_find(set, txid32, index);
    if (slot < 0) { return false; }
    int* script_lens = set.script_lens;
    char** scripts = set.scripts;
    int slen = script_lens[slot];
    if (slen < 0) { return false; }
    char* sc = null;
    if (slen > 0) {
        if (scripts[slot] == null) { return false; }
        sc = alloc<char>(slen);
        if (sc == null) { return false; }
        mgc_copy(sc, scripts[slot], slen);
    }
    out.script = sc;
    out.value = set.values[slot];
    out.script_len = slen;
    out.height = set.heights[slot];
    out.coinbase = set.coinbase_flags[slot];
    return true;
}

fn _mgc_utxo_journal_ensure(MgcUtxoSet* set, int extra) -> bool {
    if (extra < 0) { return false; }
    int length = set.journal_len;
    int capacity = set.journal_capacity;
    int needed = length + extra;
    if (needed <= capacity) { return true; }
    int new_capacity = capacity;
    if (new_capacity < 16) { new_capacity = 16; }
    while (new_capacity < needed) {
        new_capacity = new_capacity * 2;
    }
    char* fresh = alloc<char>(new_capacity);
    if (fresh == null) { return false; }
    char* old = set.journal;
    mgc_copy(fresh, old, length);
    free(old);
    set.journal = fresh;
    set.journal_capacity = new_capacity;
    return true;
}

fn _mgc_utxo_journal_append(MgcUtxoSet* set, int op, int slot, char* txid32, int index,
                            int value, char* script, int script_len, int height, bool coinbase) -> bool {
    if (script_len < 0) { return false; }
    if (script_len > 0 && script == null) { return false; }
    int record_len = MGC_UTXO_RECORD_BASE + script_len;
    if (!_mgc_utxo_journal_ensure(set, record_len)) { return false; }
    int pos = set.journal_len;
    char* j = set.journal;
    endian_write_u8(j, pos, op);
    endian_write_u32_le(j, pos + 1, record_len);
    endian_write_u32_le(j, pos + 5, slot);
    mgc_copy(j + pos + 9, txid32, 32);
    endian_write_u32_le(j, pos + 41, index);
    endian_write_u64_le(j, pos + 45, value);
    endian_write_u32_le(j, pos + 53, script_len);
    if (script_len > 0) {
        mgc_copy(j + pos + 57, script, script_len);
    }
    endian_write_u32_le(j, pos + 57 + script_len, height);
    if (coinbase) {
        endian_write_u8(j, pos + 61 + script_len, 1);
    } else {
        endian_write_u8(j, pos + 61 + script_len, 0);
    }
    endian_write_u32_le(j, pos + 62 + script_len, record_len);
    set.journal_len = pos + record_len;
    return true;
}

fn mgc_utxo_add(MgcUtxoSet* set, char* txid32, int index, int value, char* script, int script_len,
                int height, bool coinbase) -> bool {
    if (set == null || set.capacity <= 0 || txid32 == null || index < 0 || value < 0 ||
        script_len < 0 || set.states == null || set.scripts == null) { return false; }
    if (script_len > 0 && script == null) { return false; }
    int cap = set.capacity;
    int* states = set.states;
    char* keys = set.keys;
    int start = _mgc_utxo_hash(txid32, index) % cap;
    int first_tomb = -1;
    int target = -1;
    for (int probe = 0; probe < cap; probe = probe + 1) {
        int slot = (start + probe) % cap;
        int st = states[slot];
        if (st == MGC_UTXO_SLOT_EMPTY) {
            target = slot;
            break;
        }
        if (st == MGC_UTXO_SLOT_USED) {
            int kbase = slot * MGC_UTXO_KEY_SIZE;
            if (mgc_equal(keys + kbase, txid32, 32) &&
                endian_read_u32_le(keys, kbase + 32) == index) {
                return false;
            }
        } else if (st == MGC_UTXO_SLOT_DELETED) {
            if (first_tomb < 0) { first_tomb = slot; }
        }
    }
    if (target < 0) { target = first_tomb; }
    if (target < 0) { return false; }

    char* sc = null;
    if (script_len > 0) {
        sc = alloc<char>(script_len);
        if (sc == null) { return false; }
        mgc_copy(sc, script, script_len);
    }
    if (!_mgc_utxo_journal_append(set, MGC_UTXO_OP_ADD, target, txid32, index,
                                  value, sc, script_len, height, coinbase)) {
        if (sc != null) { free(sc); }
        return false;
    }

    char** scripts = set.scripts;
    if (scripts[target] != null) {
        free(scripts[target]);
        scripts[target] = null;
    }
    mgc_copy(keys + target * MGC_UTXO_KEY_SIZE, txid32, 32);
    endian_write_u32_le(keys, target * MGC_UTXO_KEY_SIZE + 32, index);
    set.values[target] = value;
    scripts[target] = sc;
    set.script_lens[target] = script_len;
    set.heights[target] = height;
    set.coinbase_flags[target] = coinbase;
    states[target] = MGC_UTXO_SLOT_USED;
    set.count = set.count + 1;
    return true;
}

fn mgc_utxo_spend(MgcUtxoSet* set, char* txid32, int index, MgcUtxo* out) -> bool {
    if (out != null) {
        out.script = null;
        out.value = 0;
        out.script_len = 0;
        out.height = 0;
        out.coinbase = false;
    }
    if (set == null || set.capacity <= 0 || txid32 == null || index < 0 ||
        set.states == null || set.scripts == null) { return false; }
    int slot = mgc_utxo_find(set, txid32, index);
    if (slot < 0) { return false; }
    char** scripts = set.scripts;
    int slen = set.script_lens[slot];
    if (slen < 0) { return false; }
    if (slen > 0 && scripts[slot] == null) { return false; }

    char* sc = null;
    if (slen > 0) {
        sc = alloc<char>(slen);
        if (sc == null) { return false; }
        mgc_copy(sc, scripts[slot], slen);
    }
    int value = set.values[slot];
    int height = set.heights[slot];
    bool coinbase = set.coinbase_flags[slot];
    char* keys = set.keys;
    int kbase = slot * MGC_UTXO_KEY_SIZE;
    char* key_txid = keys + kbase;
    int key_index = endian_read_u32_le(keys, kbase + 32);

    if (!_mgc_utxo_journal_append(set, MGC_UTXO_OP_SPEND, slot, key_txid, key_index,
                                  value, sc, slen, height, coinbase)) {
        if (sc != null) { free(sc); }
        return false;
    }

    if (scripts[slot] != null) {
        free(scripts[slot]);
        scripts[slot] = null;
    }
    set.script_lens[slot] = 0;
    set.states[slot] = MGC_UTXO_SLOT_DELETED;
    set.count = set.count - 1;

    if (out != null) {
        out.script = sc;
        out.value = value;
        out.script_len = slen;
        out.height = height;
        out.coinbase = coinbase;
    } else if (sc != null) {
        free(sc);
    }
    return true;
}

fn mgc_utxo_mark(MgcUtxoSet* set) -> int {
    if (set == null) { return -1; }
    return set.journal_len;
}

fn mgc_utxo_rollback(MgcUtxoSet* set, int mark) -> bool {
    if (set == null || mark < 0 || set.journal == null || set.states == null) { return false; }
    if (mark > set.journal_len) { return false; }
    char* j = set.journal;
    int cap = set.capacity;
    int* states = set.states;
    char* keys = set.keys;
    char** scripts = set.scripts;
    while (set.journal_len > mark) {
        int end = set.journal_len;
        if (end < MGC_UTXO_RECORD_BASE) { return false; }
        int record_len = endian_read_u32_le(j, end - 4);
        if (record_len < MGC_UTXO_RECORD_BASE || record_len > end) { return false; }
        int start = end - record_len;
        if (start < mark) { return false; }
        int check_len = endian_read_u32_le(j, start + 1);
        if (check_len != record_len) { return false; }
        int op = endian_read_u8(j, start);
        int slot = endian_read_u32_le(j, start + 5);
        int slen = endian_read_u32_le(j, start + 53);
        if (slen != record_len - MGC_UTXO_RECORD_BASE) { return false; }
        if (slot < 0 || slot >= cap) { return false; }
        int value = endian_read_u64_le(j, start + 45);
        int height = endian_read_u32_le(j, start + 57 + slen);
        int cb = endian_read_u8(j, start + 61 + slen);
        int index = endian_read_u32_le(j, start + 41);

        if (op == MGC_UTXO_OP_ADD) {
            if (scripts[slot] != null) {
                free(scripts[slot]);
                scripts[slot] = null;
            }
            set.script_lens[slot] = 0;
            states[slot] = MGC_UTXO_SLOT_DELETED;
            set.count = set.count - 1;
        } else if (op == MGC_UTXO_OP_SPEND) {
            char* sc = null;
            if (slen > 0) {
                sc = alloc<char>(slen);
                if (sc == null) { return false; }
                mgc_copy(sc, j + start + 57, slen);
            }
            if (scripts[slot] != null) {
                free(scripts[slot]);
                scripts[slot] = null;
            }
            int kbase = slot * MGC_UTXO_KEY_SIZE;
            mgc_copy(keys + kbase, j + start + 9, 32);
            endian_write_u32_le(keys, kbase + 32, index);
            scripts[slot] = sc;
            set.script_lens[slot] = slen;
            set.values[slot] = value;
            set.heights[slot] = height;
            if (cb != 0) {
                set.coinbase_flags[slot] = true;
            } else {
                set.coinbase_flags[slot] = false;
            }
            states[slot] = MGC_UTXO_SLOT_USED;
            set.count = set.count + 1;
        } else {
            return false;
        }
        set.journal_len = start;
    }
    return true;
}

fn mgc_utxo_clear(MgcUtxoSet* set) -> void {
    if (set == null || set.states == null) { return; }
    int cap = set.capacity;
    int* states = set.states;
    char* keys = set.keys;
    char** scripts = set.scripts;
    for (int i = 0; i < cap; i = i + 1) {
        if (scripts != null && scripts[i] != null) {
            free(scripts[i]);
            scripts[i] = null;
        }
        states[i] = MGC_UTXO_SLOT_EMPTY;
        set.values[i] = 0;
        set.script_lens[i] = 0;
        set.heights[i] = 0;
        set.coinbase_flags[i] = false;
    }
    mgc_zero(keys, cap * MGC_UTXO_KEY_SIZE);
    set.count = 0;
    set.journal_len = 0;
}
