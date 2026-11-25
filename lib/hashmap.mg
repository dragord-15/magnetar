// ============================================================================
// Magnetar Standard Library: Fast Hash Maps (lib/hashmap.mg)
// Open-addressing hash tables with linear probing, tombstones, power-of-two.
// Optimized for speed: integer hash mixing, FNV-1a strings, low overhead.
// ============================================================================

use "lib/string.mg";

// -------------------------------------------------------------
// Hash functions
// -------------------------------------------------------------

// 64-bit integer hash mixer (splitmix64 finalizer style)
fn hash_i64(int x) -> int {
    int h = x;
    h = h ^ (h >> 30);
    h = h * 0xbf58476d1ce4e5b9;
    h = h ^ (h >> 27);
    h = h * 0x94d049bb133111eb;
    h = h ^ (h >> 31);
    if (h < 0) { h = 0 - h; }
    if (h == 0) { h = 1; }
    return h;
}

// FNV-1a 64-bit hash for strings
fn hash_str(string s) -> int {
    char* p = cast<char*>(s);
    int h = 0xcbf29ce484222325;
    int i = 0;
    while (*(p + i) != 0) {
        int c = cast<int>(*(p + i)) & 255;
        h = h ^ c;
        h = h * 0x100000001b3;
        i = i + 1;
    }
    if (h < 0) { h = 0 - h; }
    if (h == 0) { h = 1; }
    return h;
}

fn _hm_next_pow2(int n) -> int {
    int p = 8;
    while (p < n) { p = p * 2; }
    return p;
}

// -------------------------------------------------------------
// IntIntMap: int64 -> int64, open addressing
// state: 0=empty, 1=filled, 2=tombstone
// -------------------------------------------------------------
struct IntIntMap {
    int* keys;
    int* vals;
    int* state;
    int cap;
    int mask;
    int len;
    int tombs;

    fn init(int initial_cap) -> void {
        if (initial_cap < 8) { initial_cap = 8; }
        cap = _hm_next_pow2(initial_cap);
        mask = cap - 1;
        len = 0;
        tombs = 0;
        keys = alloc<int>(cap);
        vals = alloc<int>(cap);
        state = alloc<int>(cap);
        int i = 0;
        while (i < cap) { state[i] = 0; i = i + 1; }
    }

    fn _rehash_put(int key, int val) -> void {
        int h = hash_i64(key);
        int idx = h & mask;
        while (true) {
            int st = state[idx];
            if (st == 0) { keys[idx] = key; vals[idx] = val; state[idx] = 1; len = len + 1; return; }
            idx = (idx + 1) & mask;
        }
    }

    fn _grow() -> void {
        int* ok = keys; int* ov = vals; int* os = state; int ocap = cap;
        cap = ocap * 2; mask = cap - 1; len = 0; tombs = 0;
        keys = alloc<int>(cap); vals = alloc<int>(cap); state = alloc<int>(cap);
        int i = 0; while (i < cap) { state[i] = 0; i = i + 1; }
        i = 0; while (i < ocap) { if (os[i] == 1) { _rehash_put(ok[i], ov[i]); } i = i + 1; }
        free(ok); free(ov); free(os);
    }

    fn _maybe_grow() -> void {
        // load factor 0.70
        if ((len + tombs) * 10 >= cap * 7) { _grow(); }
    }

    fn put(int key, int val) -> void {
        _maybe_grow();
        int h = hash_i64(key);
        int idx = h & mask;
        int first_tomb = 0 - 1;
        while (true) {
            int st = state[idx];
            if (st == 0) {
                int target = idx;
                if (first_tomb >= 0) { target = first_tomb; tombs = tombs - 1; }
                keys[target] = key;
                vals[target] = val;
                state[target] = 1;
                len = len + 1;
                return;
            }
            if (st == 2) {
                if (first_tomb < 0) { first_tomb = idx; }
            } else if (keys[idx] == key) {
                vals[idx] = val;
                return;
            }
            idx = (idx + 1) & mask;
        }
    }

    fn get(int key, int def) -> int {
        int h = hash_i64(key);
        int idx = h & mask;
        while (true) {
            int st = state[idx];
            if (st == 0) { return def; }
            if (st == 1 && keys[idx] == key) { return vals[idx]; }
            idx = (idx + 1) & mask;
        }
        return def;
    }

    fn has(int key) -> bool {
        int h = hash_i64(key);
        int idx = h & mask;
        while (true) {
            int st = state[idx];
            if (st == 0) { return false; }
            if (st == 1 && keys[idx] == key) { return true; }
            idx = (idx + 1) & mask;
        }
        return false;
    }

    fn remove(int key) -> bool {
        int h = hash_i64(key);
        int idx = h & mask;
        while (true) {
            int st = state[idx];
            if (st == 0) { return false; }
            if (st == 1 && keys[idx] == key) {
                state[idx] = 2;
                len = len - 1;
                tombs = tombs + 1;
                return true;
            }
            idx = (idx + 1) & mask;
        }
        return false;
    }

    fn size() -> int { return len; }

    fn clear() -> void {
        int i = 0;
        while (i < cap) { state[i] = 0; i = i + 1; }
        len = 0; tombs = 0;
    }

    fn free_map() -> void {
        if (keys != null) { free(keys); free(vals); free(state); keys = null; vals = null; state = null; cap = 0; len = 0; tombs = 0; }
    }
};

// -------------------------------------------------------------
// StrIntMap: string -> int64
// -------------------------------------------------------------
struct StrIntMap {
    string* keys;
    int* vals;
    int* hashes;
    int* state;
    int cap;
    int mask;
    int len;
    int tombs;

    fn init(int initial_cap) -> void {
        if (initial_cap < 8) { initial_cap = 8; }
        cap = _hm_next_pow2(initial_cap);
        mask = cap - 1;
        len = 0; tombs = 0;
        keys = alloc<string>(cap);
        vals = alloc<int>(cap);
        hashes = alloc<int>(cap);
        state = alloc<int>(cap);
        int i = 0;
        while (i < cap) { state[i] = 0; keys[i] = ""; i = i + 1; }
    }

    fn _rehash_put(string key, int h, int val) -> void {
        int idx = h & mask;
        while (true) {
            int st = state[idx];
            if (st == 0) { keys[idx] = key; hashes[idx] = h; vals[idx] = val; state[idx] = 1; len = len + 1; return; }
            idx = (idx + 1) & mask;
        }
    }

    fn _grow() -> void {
        string* ok = keys; int* ov = vals; int* oh = hashes; int* os = state; int ocap = cap;
        cap = ocap * 2; mask = cap - 1; len = 0; tombs = 0;
        keys = alloc<string>(cap); vals = alloc<int>(cap); hashes = alloc<int>(cap); state = alloc<int>(cap);
        int i = 0; while (i < cap) { state[i] = 0; keys[i] = ""; i = i + 1; }
        i = 0; while (i < ocap) { if (os[i] == 1) { _rehash_put(ok[i], oh[i], ov[i]); } i = i + 1; }
        free(ok); free(ov); free(oh); free(os);
    }

    fn _maybe_grow() -> void {
        if ((len + tombs) * 10 >= cap * 7) { _grow(); }
    }

    fn _put_hash(string key, int h, int val) -> void {
        _maybe_grow();
        int idx = h & mask;
        int first_tomb = 0 - 1;
        while (true) {
            int st = state[idx];
            if (st == 0) {
                int target = idx;
                if (first_tomb >= 0) { target = first_tomb; tombs = tombs - 1; }
                keys[target] = key; hashes[target] = h; vals[target] = val; state[target] = 1; len = len + 1;
                return;
            }
            if (st == 2) {
                if (first_tomb < 0) { first_tomb = idx; }
            } else if (hashes[idx] == h) {
                if (str_equals(keys[idx], key)) { vals[idx] = val; return; }
            }
            idx = (idx + 1) & mask;
        }
    }

    fn put(string key, int val) -> void {
        _put_hash(key, hash_str(key), val);
    }

    fn get(string key, int def) -> int {
        int h = hash_str(key);
        int idx = h & mask;
        while (true) {
            int st = state[idx];
            if (st == 0) { return def; }
            if (st == 1 && hashes[idx] == h && str_equals(keys[idx], key)) { return vals[idx]; }
            idx = (idx + 1) & mask;
        }
        return def;
    }

    fn has(string key) -> bool {
        int h = hash_str(key);
        int idx = h & mask;
        while (true) {
            int st = state[idx];
            if (st == 0) { return false; }
            if (st == 1 && hashes[idx] == h && str_equals(keys[idx], key)) { return true; }
            idx = (idx + 1) & mask;
        }
        return false;
    }

    fn remove(string key) -> bool {
        int h = hash_str(key);
        int idx = h & mask;
        while (true) {
            int st = state[idx];
            if (st == 0) { return false; }
            if (st == 1 && hashes[idx] == h && str_equals(keys[idx], key)) {
                state[idx] = 2; keys[idx] = ""; len = len - 1; tombs = tombs + 1; return true;
            }
            idx = (idx + 1) & mask;
        }
        return false;
    }

    fn size() -> int { return len; }
    fn clear() -> void {
        int i = 0; while (i < cap) { state[i] = 0; keys[i] = ""; i = i + 1; }
        len = 0; tombs = 0;
    }
    fn free_map() -> void {
        if (keys != null) { free(keys); free(vals); free(hashes); free(state); keys = null; vals = null; hashes = null; state = null; cap = 0; len = 0; tombs = 0; }
    }
};

// -------------------------------------------------------------
// StrStrMap: string -> string
// -------------------------------------------------------------
struct StrStrMap {
    string* keys;
    string* vals;
    int* hashes;
    int* state;
    int cap;
    int mask;
    int len;
    int tombs;

    fn init(int initial_cap) -> void {
        if (initial_cap < 8) { initial_cap = 8; }
        cap = _hm_next_pow2(initial_cap);
        mask = cap - 1; len = 0; tombs = 0;
        keys = alloc<string>(cap); vals = alloc<string>(cap); hashes = alloc<int>(cap); state = alloc<int>(cap);
        int i = 0; while (i < cap) { state[i] = 0; keys[i] = ""; vals[i] = ""; i = i + 1; }
    }

    fn _rehash_put(string key, int h, string val) -> void {
        int idx = h & mask;
        while (true) {
            int st = state[idx];
            if (st == 0) { keys[idx] = key; hashes[idx] = h; vals[idx] = val; state[idx] = 1; len = len + 1; return; }
            idx = (idx + 1) & mask;
        }
    }

    fn _grow() -> void {
        string* ok = keys; string* ov = vals; int* oh = hashes; int* os = state; int ocap = cap;
        cap = ocap * 2; mask = cap - 1; len = 0; tombs = 0;
        keys = alloc<string>(cap); vals = alloc<string>(cap); hashes = alloc<int>(cap); state = alloc<int>(cap);
        int i = 0; while (i < cap) { state[i] = 0; keys[i] = ""; vals[i] = ""; i = i + 1; }
        i = 0; while (i < ocap) { if (os[i] == 1) { _rehash_put(ok[i], oh[i], ov[i]); } i = i + 1; }
        free(ok); free(ov); free(oh); free(os);
    }

    fn _maybe_grow() -> void { if ((len + tombs) * 10 >= cap * 7) { _grow(); } }

    fn _put_hash(string key, int h, string val) -> void {
        _maybe_grow();
        int idx = h & mask;
        int first_tomb = 0 - 1;
        while (true) {
            int st = state[idx];
            if (st == 0) {
                int target = idx; if (first_tomb >= 0) { target = first_tomb; tombs = tombs - 1; }
                keys[target] = key; hashes[target] = h; vals[target] = val; state[target] = 1; len = len + 1; return;
            }
            if (st == 2) { if (first_tomb < 0) { first_tomb = idx; } }
            else if (hashes[idx] == h && str_equals(keys[idx], key)) { vals[idx] = val; return; }
            idx = (idx + 1) & mask;
        }
    }

    fn put(string key, string val) -> void { _put_hash(key, hash_str(key), val); }

    fn get(string key, string def) -> string {
        int h = hash_str(key); int idx = h & mask;
        while (true) {
            int st = state[idx];
            if (st == 0) { return def; }
            if (st == 1 && hashes[idx] == h && str_equals(keys[idx], key)) { return vals[idx]; }
            idx = (idx + 1) & mask;
        }
        return def;
    }

    fn has(string key) -> bool {
        int h = hash_str(key); int idx = h & mask;
        while (true) {
            int st = state[idx];
            if (st == 0) { return false; }
            if (st == 1 && hashes[idx] == h && str_equals(keys[idx], key)) { return true; }
            idx = (idx + 1) & mask;
        }
        return false;
    }

    fn remove(string key) -> bool {
        int h = hash_str(key); int idx = h & mask;
        while (true) {
            int st = state[idx];
            if (st == 0) { return false; }
            if (st == 1 && hashes[idx] == h && str_equals(keys[idx], key)) {
                state[idx] = 2; keys[idx] = ""; vals[idx] = ""; len = len - 1; tombs = tombs + 1; return true;
            }
            idx = (idx + 1) & mask;
        }
        return false;
    }

    fn size() -> int { return len; }
    fn clear() -> void { int i = 0; while (i < cap) { state[i] = 0; keys[i] = ""; vals[i] = ""; i = i + 1; } len = 0; tombs = 0; }
    fn free_map() -> void {
        if (keys != null) { free(keys); free(vals); free(hashes); free(state); keys = null; vals = null; hashes = null; state = null; cap = 0; len = 0; tombs = 0; }
    }
};

// -------------------------------------------------------------
// IntSet: hash set of int64
// -------------------------------------------------------------
struct IntSet {
    int* keys;
    int* state; // 0 empty, 1 filled, 2 tombstone
    int cap;
    int mask;
    int len;
    int tombs;

    fn init(int initial_cap) -> void {
        if (initial_cap < 8) { initial_cap = 8; }
        cap = _hm_next_pow2(initial_cap); mask = cap - 1; len = 0; tombs = 0;
        keys = alloc<int>(cap); state = alloc<int>(cap);
        int i = 0; while (i < cap) { state[i] = 0; i = i + 1; }
    }

    fn _rehash_put(int key) -> void {
        int idx = hash_i64(key) & mask;
        while (true) {
            if (state[idx] == 0) { keys[idx] = key; state[idx] = 1; len = len + 1; return; }
            idx = (idx + 1) & mask;
        }
    }

    fn _grow() -> void {
        int* ok = keys; int* os = state; int ocap = cap;
        cap = ocap * 2; mask = cap - 1; len = 0; tombs = 0;
        keys = alloc<int>(cap); state = alloc<int>(cap);
        int i = 0; while (i < cap) { state[i] = 0; i = i + 1; }
        i = 0; while (i < ocap) { if (os[i] == 1) { _rehash_put(ok[i]); } i = i + 1; }
        free(ok); free(os);
    }

    fn _maybe_grow() -> void { if ((len + tombs) * 10 >= cap * 7) { _grow(); } }

    fn add(int key) -> bool {
        _maybe_grow();
        int idx = hash_i64(key) & mask;
        int first_tomb = 0 - 1;
        while (true) {
            int st = state[idx];
            if (st == 0) {
                int target = idx; if (first_tomb >= 0) { target = first_tomb; tombs = tombs - 1; }
                keys[target] = key; state[target] = 1; len = len + 1; return true;
            }
            if (st == 2) { if (first_tomb < 0) { first_tomb = idx; } }
            else if (keys[idx] == key) { return false; }
            idx = (idx + 1) & mask;
        }
        return false;
    }

    fn has(int key) -> bool {
        int idx = hash_i64(key) & mask;
        while (true) {
            int st = state[idx];
            if (st == 0) { return false; }
            if (st == 1 && keys[idx] == key) { return true; }
            idx = (idx + 1) & mask;
        }
        return false;
    }

    fn remove(int key) -> bool {
        int idx = hash_i64(key) & mask;
        while (true) {
            int st = state[idx];
            if (st == 0) { return false; }
            if (st == 1 && keys[idx] == key) { state[idx] = 2; len = len - 1; tombs = tombs + 1; return true; }
            idx = (idx + 1) & mask;
        }
        return false;
    }

    fn size() -> int { return len; }
    fn clear() -> void { int i = 0; while (i < cap) { state[i] = 0; i = i + 1; } len = 0; tombs = 0; }
    fn free_set() -> void { if (keys != null) { free(keys); free(state); keys = null; state = null; cap = 0; len = 0; tombs = 0; } }
};

// -------------------------------------------------------------
// StrSet: hash set of strings
// -------------------------------------------------------------
struct StrSet {
    string* keys;
    int* hashes;
    int* state;
    int cap;
    int mask;
    int len;
    int tombs;

    fn init(int initial_cap) -> void {
        if (initial_cap < 8) { initial_cap = 8; }
        cap = _hm_next_pow2(initial_cap); mask = cap - 1; len = 0; tombs = 0;
        keys = alloc<string>(cap); hashes = alloc<int>(cap); state = alloc<int>(cap);
        int i = 0; while (i < cap) { state[i] = 0; keys[i] = ""; i = i + 1; }
    }

    fn _rehash_put(string key, int h) -> void {
        int idx = h & mask;
        while (true) {
            if (state[idx] == 0) { keys[idx] = key; hashes[idx] = h; state[idx] = 1; len = len + 1; return; }
            idx = (idx + 1) & mask;
        }
    }

    fn _grow() -> void {
        string* ok = keys; int* oh = hashes; int* os = state; int ocap = cap;
        cap = ocap * 2; mask = cap - 1; len = 0; tombs = 0;
        keys = alloc<string>(cap); hashes = alloc<int>(cap); state = alloc<int>(cap);
        int i = 0; while (i < cap) { state[i] = 0; keys[i] = ""; i = i + 1; }
        i = 0; while (i < ocap) { if (os[i] == 1) { _rehash_put(ok[i], oh[i]); } i = i + 1; }
        free(ok); free(oh); free(os);
    }

    fn _maybe_grow() -> void { if ((len + tombs) * 10 >= cap * 7) { _grow(); } }

    fn add(string key) -> bool {
        int h = hash_str(key);
        _maybe_grow();
        int idx = h & mask;
        int first_tomb = 0 - 1;
        while (true) {
            int st = state[idx];
            if (st == 0) {
                int target = idx; if (first_tomb >= 0) { target = first_tomb; tombs = tombs - 1; }
                keys[target] = key; hashes[target] = h; state[target] = 1; len = len + 1; return true;
            }
            if (st == 2) { if (first_tomb < 0) { first_tomb = idx; } }
            else if (hashes[idx] == h && str_equals(keys[idx], key)) { return false; }
            idx = (idx + 1) & mask;
        }
        return false;
    }

    fn has(string key) -> bool {
        int h = hash_str(key); int idx = h & mask;
        while (true) {
            int st = state[idx];
            if (st == 0) { return false; }
            if (st == 1 && hashes[idx] == h && str_equals(keys[idx], key)) { return true; }
            idx = (idx + 1) & mask;
        }
        return false;
    }

    fn remove(string key) -> bool {
        int h = hash_str(key); int idx = h & mask;
        while (true) {
            int st = state[idx];
            if (st == 0) { return false; }
            if (st == 1 && hashes[idx] == h && str_equals(keys[idx], key)) {
                state[idx] = 2; keys[idx] = ""; len = len - 1; tombs = tombs + 1; return true;
            }
            idx = (idx + 1) & mask;
        }
        return false;
    }

    fn size() -> int { return len; }
    fn clear() -> void { int i = 0; while (i < cap) { state[i] = 0; keys[i] = ""; i = i + 1; } len = 0; tombs = 0; }
    fn free_set() -> void { if (keys != null) { free(keys); free(hashes); free(state); keys = null; hashes = null; state = null; cap = 0; len = 0; tombs = 0; } }
};

// -------------------------------------------------------------
// Key iteration helpers (caller provides pre-allocated arrays)
// -------------------------------------------------------------
fn intintmap_keys(IntIntMap* m, int* out_keys) -> int {
    int n = 0; int i = 0;
    while (i < m.cap) {
        if (m.state[i] == 1) { out_keys[n] = m.keys[i]; n = n + 1; }
        i = i + 1;
    }
    return n;
}

fn strintmap_keys(StrIntMap* m, string* out_keys) -> int {
    int n = 0; int i = 0;
    while (i < m.cap) {
        if (m.state[i] == 1) { out_keys[n] = m.keys[i]; n = n + 1; }
        i = i + 1;
    }
    return n;
}

fn strstrmap_keys(StrStrMap* m, string* out_keys) -> int {
    int n = 0; int i = 0;
    while (i < m.cap) {
        if (m.state[i] == 1) { out_keys[n] = m.keys[i]; n = n + 1; }
        i = i + 1;
    }
    return n;
}

fn intset_values(IntSet* s, int* out_vals) -> int {
    int n = 0; int i = 0;
    while (i < s.cap) {
        if (s.state[i] == 1) { out_vals[n] = s.keys[i]; n = n + 1; }
        i = i + 1;
    }
    return n;
}

fn strset_values(StrSet* s, string* out_vals) -> int {
    int n = 0; int i = 0;
    while (i < s.cap) {
        if (s.state[i] == 1) { out_vals[n] = s.keys[i]; n = n + 1; }
        i = i + 1;
    }
    return n;
}
