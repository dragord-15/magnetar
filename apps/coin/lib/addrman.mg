// Magnetar Coin — bounded peer address book with text persistence.

use "../../lib/string.mg";

extern fn sys_open(string path, int flags, int mode) -> int;
extern fn sys_close(int fd) -> int;
extern fn sys_read(int fd, char* buf, int count) -> int;
extern fn sys_write(int fd, char* data, int count) -> int;

struct MgcAddrEntry { int ip0; int ip1; int ip2; int ip3; int port; int attempts; int last_seen; }

struct MgcAddrMan { int capacity; int count; MgcAddrEntry* entries; }

fn mgc_addrman_init(MgcAddrMan* a, int capacity) -> bool {
    if (a == null || capacity <= 0) { return false; }
    a.capacity = 0;
    a.count = 0;
    a.entries = null;
    a.entries = alloc<MgcAddrEntry>(capacity);
    if (a.entries == null) { return false; }
    a.capacity = capacity;
    int* words = cast<int*>(a.entries);
    for (int i = 0; i < capacity * 7; i = i + 1) {
        words[i] = 0;
    }
    return true;
}

fn mgc_addrman_free(MgcAddrMan* a) -> void {
    if (a == null) { return; }
    if (a.entries != null) {
        free(a.entries);
        a.entries = null;
    }
    a.capacity = 0;
    a.count = 0;
}

fn mgc_addrman_has(MgcAddrMan* a, int ip0, int ip1, int ip2, int ip3, int port) -> bool {
    if (a == null || a.entries == null || a.count <= 0) { return false; }
    int* words = cast<int*>(a.entries);
    for (int i = 0; i < a.count; i = i + 1) {
        int off = i * 7;
        if (words[off] == ip0 && words[off + 1] == ip1 &&
            words[off + 2] == ip2 && words[off + 3] == ip3 &&
            words[off + 4] == port) { return true; }
    }
    return false;
}

fn mgc_addrman_add(MgcAddrMan* a, int ip0, int ip1, int ip2, int ip3, int port) -> bool {
    if (a == null || a.entries == null || a.capacity <= 0 || a.count >= a.capacity) { return false; }
    if (ip0 < 0 || ip0 > 255 || ip1 < 0 || ip1 > 255 ||
        ip2 < 0 || ip2 > 255 || ip3 < 0 || ip3 > 255) { return false; }
    if (port < 0 || port > 65535) { return false; }
    if (mgc_addrman_has(a, ip0, ip1, ip2, ip3, port)) { return false; }

    int* words = cast<int*>(a.entries);
    int n = a.count;
    int off = n * 7;
    words[off] = ip0;
    words[off + 1] = ip1;
    words[off + 2] = ip2;
    words[off + 3] = ip3;
    words[off + 4] = port;
    words[off + 5] = 0;
    words[off + 6] = 0;
    a.count = a.count + 1;
    return true;
}

fn mgc_addrman_get(MgcAddrMan* a, int i) -> MgcAddrEntry* {
    if (a == null || a.entries == null || i < 0 || i >= a.count) { return null; }
    int* words = cast<int*>(a.entries);
    int off = i * 7;
    MgcAddrEntry* e = alloc<MgcAddrEntry>(1);
    if (e == null) { return null; }
    e.ip0 = words[off];
    e.ip1 = words[off + 1];
    e.ip2 = words[off + 2];
    e.ip3 = words[off + 3];
    e.port = words[off + 4];
    e.attempts = words[off + 5];
    e.last_seen = words[off + 6];
    return e;
}

fn mgc_addrman_count(MgcAddrMan* a) -> int {
    if (a == null) { return 0; }
    return a.count;
}

fn _mgc_addrman_emit(int fd, string s) -> bool {
    if (s == null) { return false; }
    int n = len(s);
    if (n <= 0) { return true; }
    int written = sys_write(fd, cast<char*>(s), n);
    return written == n;
}

fn _mgc_addrman_emit_int(int fd, int value) -> bool {
    string s = int_to_str(value);
    bool ok = _mgc_addrman_emit(fd, s);
    free(cast<char*>(s));
    return ok;
}

fn mgc_addrman_save(MgcAddrMan* a, string path) -> bool {
    if (a == null || a.entries == null || path == null) { return false; }
    int fd = sys_open(path, 577, 420);
    if (fd < 0) { return false; }

    int* words = cast<int*>(a.entries);
    bool ok = true;
    for (int i = 0; i < a.count && ok; i = i + 1) {
        int off = i * 7;
        ok = _mgc_addrman_emit_int(fd, words[off]);
        if (ok) { ok = _mgc_addrman_emit(fd, "."); }
        if (ok) { ok = _mgc_addrman_emit_int(fd, words[off + 1]); }
        if (ok) { ok = _mgc_addrman_emit(fd, "."); }
        if (ok) { ok = _mgc_addrman_emit_int(fd, words[off + 2]); }
        if (ok) { ok = _mgc_addrman_emit(fd, "."); }
        if (ok) { ok = _mgc_addrman_emit_int(fd, words[off + 3]); }
        if (ok) { ok = _mgc_addrman_emit(fd, ":"); }
        if (ok) { ok = _mgc_addrman_emit_int(fd, words[off + 4]); }
        if (ok) { ok = _mgc_addrman_emit(fd, "\n"); }
    }
    sys_close(fd);
    return ok;
}

fn _mgc_addrman_read_line(int fd, char* buf, int cap) -> int {
    int n = 0;
    bool got = false;
    while (n < cap - 1) {
        char ch = 0;
        int r = sys_read(fd, &ch, 1);
        if (r <= 0) { break; }
        got = true;
        if (ch == 10) { break; }
        if (ch == 13) { continue; }
        *(buf + n) = ch;
        n = n + 1;
    }
    *(buf + n) = 0;
    if (!got && n == 0) { return -1; }
    return n;
}

fn _mgc_addrman_parse_part(string s) -> int {
    if (s == null || len(s) <= 0) { return -1; }
    char* p = cast<char*>(s);
    int n = len(s);
    for (int i = 0; i < n; i = i + 1) {
        if (!is_digit(*(p + i))) { return -1; }
    }
    return str_to_int(s);
}

fn _mgc_addrman_parse_line(char* line, int* ip0, int* ip1, int* ip2, int* ip3, int* port) -> bool {
    if (line == null || ip0 == null || ip1 == null || ip2 == null || ip3 == null || port == null) {
        return false;
    }
    string text = cast<string>(line);
    int total = len(text);
    int pos = 0;

    int sep = str_index_of(cast<string>(line + pos), ".");
    if (sep <= 0) { return false; }
    string part = str_substr(text, pos, sep);
    int v0 = _mgc_addrman_parse_part(part);
    free(cast<char*>(part));
    if (v0 < 0 || v0 > 255) { return false; }
    pos = pos + sep + 1;

    sep = str_index_of(cast<string>(line + pos), ".");
    if (sep <= 0) { return false; }
    part = str_substr(text, pos, sep);
    int v1 = _mgc_addrman_parse_part(part);
    free(cast<char*>(part));
    if (v1 < 0 || v1 > 255) { return false; }
    pos = pos + sep + 1;

    sep = str_index_of(cast<string>(line + pos), ".");
    if (sep <= 0) { return false; }
    part = str_substr(text, pos, sep);
    int v2 = _mgc_addrman_parse_part(part);
    free(cast<char*>(part));
    if (v2 < 0 || v2 > 255) { return false; }
    pos = pos + sep + 1;

    sep = str_index_of(cast<string>(line + pos), ":");
    if (sep <= 0) { return false; }
    part = str_substr(text, pos, sep);
    int v3 = _mgc_addrman_parse_part(part);
    free(cast<char*>(part));
    if (v3 < 0 || v3 > 255) { return false; }
    pos = pos + sep + 1;

    if (pos >= total) { return false; }
    part = str_substr(text, pos, total - pos);
    int vp = _mgc_addrman_parse_part(part);
    free(cast<char*>(part));
    if (vp < 0 || vp > 65535) { return false; }

    *ip0 = v0;
    *ip1 = v1;
    *ip2 = v2;
    *ip3 = v3;
    *port = vp;
    return true;
}

fn mgc_addrman_load(MgcAddrMan* a, string path) -> bool {
    if (a == null || a.entries == null || path == null) { return false; }
    int fd = sys_open(path, 0, 0);
    if (fd < 0) { return true; }

    char* line = alloc<char>(256);
    if (line == null) {
        sys_close(fd);
        return false;
    }
    a.count = 0;
    while (true) {
        int n = _mgc_addrman_read_line(fd, line, 256);
        if (n < 0) { break; }
        if (n == 0) { continue; }
        int ip0 = 0;
        int ip1 = 0;
        int ip2 = 0;
        int ip3 = 0;
        int port = 0;
        if (_mgc_addrman_parse_line(line, &ip0, &ip1, &ip2, &ip3, &port)) {
            mgc_addrman_add(a, ip0, ip1, ip2, ip3, port);
        }
    }
    free(line);
    sys_close(fd);
    return true;
}
