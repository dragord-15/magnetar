// Magnetar Coin — filesystem persistence: atomic files, block log, UTXO snapshot, lock and cookie.

use "block.mg";
use "chain.mg";
use "utxo.mg";
use "hash.mg";
use "endian.mg";
use "../../lib/string.mg";

extern fn sys_open(string path, int flags, int mode) -> int;
extern fn sys_close(int fd) -> int;
extern fn sys_read(int fd, char* buf, int count) -> int;
extern fn sys_write(int fd, char* data, int count) -> int;
extern fn sys_lseek(int fd, int offset, int whence) -> int;
extern fn sys_fsync(int fd) -> int;
extern fn sys_rename(string oldpath, string newpath) -> int;
extern fn sys_unlink(string path) -> int;
extern fn sys_mkdir(string path, int mode) -> int;
extern fn sys_flock(int fd, int op) -> int;
extern fn sys_chmod(string path, int mode) -> int;

fn mgc_storage_path(string datadir, string relative) -> string {
    string prefix = str_concat(datadir, "/");
    return str_concat(prefix, relative);
}

fn _mgc_storage_parent(string path) -> string {
    char* p = cast<char*>(path);
    int n = len(path);
    int slash = -1;
    for (int i = 0; i < n; i = i + 1) {
        if (*(p + i) == 47) { slash = i; }
    }
    if (slash <= 0) { return "."; }
    char* buf = alloc<char>(slash + 1);
    if (buf == null) { return "."; }
    for (int j = 0; j < slash; j = j + 1) { *(buf + j) = *(p + j); }
    *(buf + slash) = 0;
    return cast<string>(buf);
}

fn mgc_storage_init_datadir(string datadir) -> bool {
    string blocks = mgc_storage_path(datadir, "blocks");
    string chainstate = mgc_storage_path(datadir, "chainstate");
    string wallet = mgc_storage_path(datadir, "wallet");
    int r1 = sys_mkdir(datadir, 493);
    if (r1 < 0 && r1 != -17) { return false; }
    int r2 = sys_mkdir(blocks, 493);
    if (r2 < 0 && r2 != -17) { return false; }
    int r3 = sys_mkdir(chainstate, 493);
    if (r3 < 0 && r3 != -17) { return false; }
    int r4 = sys_mkdir(wallet, 493);
    if (r4 < 0 && r4 != -17) { return false; }
    return true;
}

fn mgc_storage_atomic_write(string path, char* data, int len) -> bool {
    if (data == null || len < 0) { return false; }
    string tmp = str_concat(path, ".tmp");
    int fd = sys_open(tmp, 577, 420);
    if (fd < 0) { return false; }
    int written = 0;
    while (written < len) {
        int r = sys_write(fd, data + written, len - written);
        if (r <= 0) { sys_close(fd); sys_unlink(tmp); return false; }
        written = written + r;
    }
    if (sys_fsync(fd) != 0) { sys_close(fd); sys_unlink(tmp); return false; }
    if (sys_close(fd) != 0) { sys_unlink(tmp); return false; }
    if (sys_rename(tmp, path) != 0) { sys_unlink(tmp); return false; }
    string parent = _mgc_storage_parent(path);
    int dfd = sys_open(parent, 0, 0);
    if (dfd >= 0) { sys_fsync(dfd); sys_close(dfd); }
    return true;
}

fn mgc_storage_read(string path, char** out, int* out_len) -> bool {
    if (out == null || out_len == null) { return false; }
    *out = null;
    *out_len = 0;
    int fd = sys_open(path, 0, 0);
    if (fd < 0) { return false; }
    int size = sys_lseek(fd, 0, 2);
    if (size < 0) { sys_close(fd); return false; }
    if (sys_lseek(fd, 0, 0) < 0) { sys_close(fd); return false; }
    char* buf = alloc<char>(size + 1);
    if (buf == null) { sys_close(fd); return false; }
    int total = 0;
    while (total < size) {
        int r = sys_read(fd, buf + total, size - total);
        if (r <= 0) { break; }
        total = total + r;
    }
    *(buf + total) = 0;
    sys_close(fd);
    *out = buf;
    *out_len = total;
    return true;
}

fn mgc_storage_append_block(string datadir, MgcBlock* b) -> bool {
    if (b == null) { return false; }
    int blen = 0;
    char* bytes = mgc_block_serialize(b, &blen);
    if (bytes == null || blen <= 0) {
        if (bytes != null) { free(bytes); }
        return false;
    }
    char* hash32 = alloc<char>(32);
    char* record = alloc<char>(4 + blen + 4);
    if (hash32 == null || record == null) {
        if (hash32 != null) { free(hash32); }
        if (record != null) { free(record); }
        free(bytes);
        return false;
    }
    endian_write_u32_le(record, 0, blen);
    mgc_copy(record + 4, bytes, blen);
    mgc_sha256d_raw(bytes, blen, hash32);
    int checksum = endian_read_u32_le(hash32, 0);
    endian_write_u32_le(record, 4 + blen, checksum);
    string path = mgc_storage_path(datadir, "blocks/blk00000.dat");
    int fd = sys_open(path, 1089, 420);
    if (fd < 0) { free(record); free(hash32); free(bytes); return false; }
    int total = 4 + blen + 4;
    int written = 0;
    while (written < total) {
        int r = sys_write(fd, record + written, total - written);
        if (r <= 0) { sys_close(fd); free(record); free(hash32); free(bytes); return false; }
        written = written + r;
    }
    bool ok = sys_fsync(fd) == 0;
    sys_close(fd);
    free(record);
    free(hash32);
    free(bytes);
    return ok;
}

fn mgc_storage_load_blocks(string datadir, MgcChain* chain) -> int {
    if (chain == null) { return 0; }
    string path = mgc_storage_path(datadir, "blocks/blk00000.dat");
    char* data = null;
    int file_len = 0;
    if (!mgc_storage_read(path, &data, &file_len)) { return 0; }
    if (data == null || file_len <= 0) { free(data); return 0; }
    char* hash32 = alloc<char>(32);
    if (hash32 == null) { free(data); return 0; }
    int pos = 0;
    int loaded = 0;
    while (pos + 8 <= file_len) {
        int blen = endian_read_u32_le(data, pos);
        if (blen <= 0) { break; }
        int total = 4 + blen + 4;
        if (pos + total > file_len) { break; }
        char* block_bytes = data + pos + 4;
        int stored = endian_read_u32_le(data, pos + 4 + blen);
        mgc_sha256d_raw(block_bytes, blen, hash32);
        int actual = endian_read_u32_le(hash32, 0);
        if (actual != stored) { break; }
        MgcBlock* b = alloc<MgcBlock>(1);
        if (b == null) { break; }
        mgc_block_init(b);
        if (!mgc_block_deserialize(block_bytes, blen, b)) {
            mgc_block_free(b);
            free(b);
            break;
        }
        bool reorg = false;
        if (mgc_chain_add_block(chain, b, &reorg)) { loaded = loaded + 1; }
        pos = pos + total;
    }
    free(hash32);
    free(data);
    return loaded;
}

fn mgc_storage_save_utxo(string datadir, MgcUtxoSet* set) -> bool {
    if (set == null || set.states == null || set.capacity <= 0) { return false; }
    int cap = set.capacity;
    int used = 0;
    int payload_len = 12;
    for (int i = 0; i < cap; i = i + 1) {
        if (set.states[i] == 1) {
            int slen = set.script_lens[i];
            if (slen < 0) { return false; }
            used = used + 1;
            payload_len = payload_len + 53 + slen;
        }
    }
    int total = payload_len + 4;
    char* payload = alloc<char>(total);
    char* hash32 = alloc<char>(32);
    if (payload == null || hash32 == null) {
        if (payload != null) { free(payload); }
        if (hash32 != null) { free(hash32); }
        return false;
    }
    mgc_copy(payload, cast<char*>("MGCU"), 4);
    endian_write_u32_le(payload, 4, 1);
    endian_write_u32_le(payload, 8, used);
    int pos = 12;
    for (int i = 0; i < cap; i = i + 1) {
        if (set.states[i] == 1) {
            int slen = set.script_lens[i];
            mgc_copy(payload + pos, set.keys + i * 36, 36);
            endian_write_u64_le(payload, pos + 36, set.values[i]);
            endian_write_u32_le(payload, pos + 44, slen);
            if (slen > 0) {
                if (set.scripts[i] == null) { free(payload); free(hash32); return false; }
                mgc_copy(payload + pos + 48, set.scripts[i], slen);
            }
            endian_write_u32_le(payload, pos + 48 + slen, set.heights[i]);
            int cb = 0;
            if (set.coinbase_flags[i]) { cb = 1; }
            endian_write_u8(payload, pos + 52 + slen, cb);
            pos = pos + 53 + slen;
        }
    }
    mgc_sha256d_raw(payload, pos, hash32);
    mgc_copy(payload + pos, hash32, 4);
    string path = mgc_storage_path(datadir, "chainstate/utxo.dat");
    bool ok = mgc_storage_atomic_write(path, payload, total);
    free(payload);
    free(hash32);
    return ok;
}

fn mgc_storage_load_utxo(string datadir, MgcUtxoSet* set) -> bool {
    if (set == null || set.states == null || set.capacity <= 0) { return false; }
    string path = mgc_storage_path(datadir, "chainstate/utxo.dat");
    char* data = null;
    int file_len = 0;
    if (!mgc_storage_read(path, &data, &file_len)) { return false; }
    if (data == null || file_len < 16) { free(data); return false; }
    char* hash32 = alloc<char>(32);
    if (hash32 == null) { free(data); return false; }
    bool valid = mgc_equal(data, cast<char*>("MGCU"), 4);
    if (valid) { valid = endian_read_u32_le(data, 4) == 1; }
    int payload_len = file_len - 4;
    if (valid) {
        mgc_sha256d_raw(data, payload_len, hash32);
        valid = mgc_equal(hash32, data + payload_len, 4);
    }
    if (!valid) { free(hash32); free(data); return false; }
    int count = endian_read_u32_le(data, 8);
    mgc_utxo_clear(set);
    int pos = 12;
    int added = 0;
    bool entries_ok = count >= 0;
    while (added < count && entries_ok) {
        if (pos + 53 > payload_len) { entries_ok = false; break; }
        int slen = endian_read_u32_le(data, pos + 44);
        if (slen < 0 || pos + 53 + slen > payload_len) { entries_ok = false; break; }
        char* key = data + pos;
        int value = endian_read_u64_le(data, pos + 36);
        int index = endian_read_u32_le(key, 32);
        char* script = null;
        if (slen > 0) { script = data + pos + 48; }
        int height = endian_read_u32_le(data, pos + 48 + slen);
        int cb = endian_read_u8(data, pos + 52 + slen);
        bool coinbase = cb != 0;
        if (!mgc_utxo_add(set, key, index, value, script, slen, height, coinbase)) {
            entries_ok = false;
            break;
        }
        pos = pos + 53 + slen;
        added = added + 1;
    }
    free(hash32);
    free(data);
    if (!entries_ok) { return false; }
    set.journal_len = 0;
    return true;
}

fn mgc_storage_lock(string datadir) -> int {
    string path = mgc_storage_path(datadir, ".lock");
    int fd = sys_open(path, 65, 420);
    if (fd < 0) { return -1; }
    int r = sys_flock(fd, 6);
    if (r != 0) { sys_close(fd); return -1; }
    return fd;
}

fn mgc_storage_write_cookie(string datadir) -> string {
    string hex = crypto_rng_hex(16);
    string path = mgc_storage_path(datadir, ".cookie");
    char* bytes = cast<char*>(hex);
    int n = len(hex);
    if (n <= 0) { return hex; }
    if (mgc_storage_atomic_write(path, bytes, n)) { sys_chmod(path, 384); }
    return hex;
}
