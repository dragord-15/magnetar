extern fn sys_getdents64(int fd, char* dirp, int count) -> int;
extern fn sys_getcwd(char* buf, int size) -> int;

const int FT_ROW_H = 18;
const int FT_TOP_OFFSET = 66;

static char* FT_DIR;
static char* FT_LIST;
static int FT_COUNT;
static int FT_SELECTED;
static char* FT_NAME_BUF;
static char* FT_BUF;
static char* FT_PATH_BUF;
static int FT_FD;
static int FT_NREAD;
static int FT_POS;
static int FT_AT;

fn ft_byte(char* p, int i) -> int {
    int v = cast<int>(*(p + i));
    if (v < 0) { v = v + 256; }
    return v;
}

fn ft_append(char* dst, int cap, int at, char* src) -> int {
    int i = 0;
    while (*(src + i) != 0 && at < cap - 1) {
        *(dst + at) = *(src + i);
        at = at + 1;
        i = i + 1;
    }
    *(dst + at) = 0;
    return at;
}

fn ft_set_dir(string path) -> void {
    char* p = cast<char*>(path);
    int n = 0;
    while (*(p + n) != 0 && n < 1023) {
        FT_DIR[n] = *(p + n);
        n = n + 1;
    }
    FT_DIR[n] = 0;
}

fn ft_scan() -> void {
    *(FT_LIST) = 0;
    FT_COUNT = 0;
    FT_SELECTED = -1;
    char* dp = FT_PATH_BUF;
    int dq = 0;
    while (dq < 1023 && FT_DIR[dq] != 0) {
        dp[dq] = FT_DIR[dq];
        dq = dq + 1;
    }
    dp[dq] = 0;
    FT_FD = sys_open(cast<string>(dp), 0, 0);
    if (FT_FD < 0) { return; }
    FT_AT = 0;
    if (FT_AT < 8190) {
        FT_AT = ft_append(FT_LIST, 8192, FT_AT, cast<char*>(".."));
        FT_COUNT = FT_COUNT + 1;
    }
    FT_NREAD = sys_getdents64(FT_FD, FT_BUF, 8192);
    while (FT_NREAD > 0) {
        FT_POS = 0;
        while (FT_POS < FT_NREAD) {
            int lo = ft_byte(FT_BUF, FT_POS + 16);
            int hi = ft_byte(FT_BUF, FT_POS + 17);
            int reclen = lo + hi * 256;
            int dtype = ft_byte(FT_BUF, FT_POS + 18);
            int c0 = ft_byte(FT_BUF, FT_POS + 19);
            if (c0 != 46 && c0 != 0) {
                if (FT_AT < 8180) {
                    *(FT_LIST + FT_AT) = 44;
                    *(FT_LIST + FT_AT + 1) = 32;
                    FT_AT = FT_AT + 2;
                    FT_AT = ft_append(FT_LIST, 8192, FT_AT, FT_BUF + FT_POS + 19);
                    if (dtype == 4) {
                        FT_AT = ft_append(FT_LIST, 8192, FT_AT, cast<char*>("/"));
                    }
                    FT_COUNT = FT_COUNT + 1;
                }
            }
            if (reclen <= 0) { break; }
            FT_POS = FT_POS + reclen;
        }
        FT_NREAD = sys_getdents64(FT_FD, FT_BUF, 8192);
    }
    sys_close(FT_FD);
}

fn ft_init() -> void {
    FT_DIR = alloc<char>(1024);
    FT_LIST = alloc<char>(8192);
    FT_NAME_BUF = alloc<char>(256);
    FT_BUF = alloc<char>(8192);
    FT_PATH_BUF = alloc<char>(1024);
    *(FT_DIR) = 0;
    *(FT_LIST) = 0;
    FT_COUNT = 0;
    FT_SELECTED = -1;
    if (sys_getcwd(FT_DIR, 1023) <= 0) { ft_set_dir("."); }
    ft_scan();
}

fn ft_count() -> int {
    return FT_COUNT;
}

fn ft_selected() -> int {
    return FT_SELECTED;
}

fn ft_set_selected(int i) -> void {
    FT_SELECTED = i;
}

fn ft_name_at(int idx, char* out, int cap) -> void {
    if (cap <= 0) { return; }
    *(out) = 0;
    if (idx < 0) { return; }
    int i = 0;
    int cur = 0;
    while (*(FT_LIST + i) != 0) {
        int st = i;
        while (*(FT_LIST + i) != 0 && *(FT_LIST + i) != 44) { i = i + 1; }
        int n = i - st;
        if (cur == idx) {
            int k = 0;
            while (k < n && k < cap - 1) {
                *(out + k) = *(FT_LIST + st + k);
                k = k + 1;
            }
            *(out + k) = 0;
            return;
        }
        cur = cur + 1;
        if (*(FT_LIST + i) == 44) { i = i + 2; }
    }
}

fn ft_name(int idx) -> string {
    ft_name_at(idx, FT_NAME_BUF, 256);
    return cast<string>(FT_NAME_BUF);
}

fn ft_path(int idx) -> string {
    ft_name_at(idx, FT_NAME_BUF, 256);
    int dl = 0;
    while (*(FT_DIR + dl) != 0) { dl = dl + 1; }
    int nl = 0;
    while (*(FT_NAME_BUF + nl) != 0) { nl = nl + 1; }
    int is_parent = 0;
    if (nl == 2 && *(FT_NAME_BUF) == 46 && *(FT_NAME_BUF + 1) == 46) { is_parent = 1; }
    int use_len = nl;
    if (nl > 0 && *(FT_NAME_BUF + nl - 1) == 47) { use_len = nl - 1; }
    if (is_parent == 1) {
        if (dl <= 1) {
            char* root = alloc<char>(2);
            *(root) = 47;
            *(root + 1) = 0;
            return cast<string>(root);
        }
        int end = dl;
        if (end > 1 && *(FT_DIR + end - 1) == 47) { end = end - 1; }
        int last = -1;
        int i = 0;
        while (i < end) {
            if (*(FT_DIR + i) == 47) { last = i; }
            i = i + 1;
        }
        if (last <= 0) {
            char* root = alloc<char>(2);
            *(root) = 47;
            *(root + 1) = 0;
            return cast<string>(root);
        }
        char* out = alloc<char>(last + 1);
        i = 0;
        while (i < last) {
            *(out + i) = *(FT_DIR + i);
            i = i + 1;
        }
        *(out + last) = 0;
        return cast<string>(out);
    }
    int sep = 0;
    if (dl > 0 && *(FT_DIR + dl - 1) != 47) { sep = 1; }
    char* out = alloc<char>(dl + use_len + sep + 1);
    int i = 0;
    while (i < dl) { *(out + i) = *(FT_DIR + i); i = i + 1; }
    if (sep == 1) { *(out + i) = 47; i = i + 1; }
    int k = 0;
    while (k < use_len) { *(out + i + k) = *(FT_NAME_BUF + k); k = k + 1; }
    *(out + i + use_len) = 0;
    return cast<string>(out);
}

fn ft_open_index(int idx) -> int {
    string path = ft_path(idx);
    ft_name_at(idx, FT_NAME_BUF, 256);
    int nl = 0;
    while (*(FT_NAME_BUF + nl) != 0) { nl = nl + 1; }
    int is_dir_entry = 0;
    if (nl > 0 && *(FT_NAME_BUF + nl - 1) == 47) { is_dir_entry = 1; }
    if (nl == 2 && *(FT_NAME_BUF) == 46 && *(FT_NAME_BUF + 1) == 46) { is_dir_entry = 1; }
    if (is_dir_entry == 1 || file_is_dir(path) == true) {
        ft_set_dir(path);
        ft_scan();
        free(cast<char*>(path));
        view_ensure_cursor_visible();
        return 1;
    }
    int ok = editor_open_path(path);
    free(cast<char*>(path));
    return ok;
}

fn ft_reload_for_path(string path) -> void {
    char* p = cast<char*>(path);
    int n = 0;
    while (*(p + n) != 0) { n = n + 1; }
    int last = -1;
    int i = 0;
    while (i < n) {
        if (*(p + i) == 47) { last = i; }
        i = i + 1;
    }
    if (last > 0) {
        char* dir = alloc<char>(last + 1);
        i = 0;
        while (i < last) { *(dir + i) = *(p + i); i = i + 1; }
        *(dir + last) = 0;
        ft_set_dir(cast<string>(dir));
        free(dir);
    }
    ft_scan();
}

fn ft_reload() -> void {
    ft_scan();
}

fn ft_toggle() -> void {
    view_toggle_tree();
    if (view_tree_on() == 1) { ft_scan(); }
}

fn ft_index_at_y(int my) -> int {
    if (view_tree_on() == 0) { return -1; }
    int top = VIEW_HEADER_H + FT_TOP_OFFSET;
    if (my < top) { return -1; }
    int idx = (my - top) / FT_ROW_H;
    if (idx < 0 || idx >= FT_COUNT) { return -1; }
    return idx;
}
