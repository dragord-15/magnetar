// Magnetar Coin — small memory helpers used by the primitives.
// No libc: every loop is explicit.

fn mgc_zero(char* p, int count) -> void {
    if (p == null || count <= 0) { return; }
    for (int i = 0; i < count; i = i + 1) {
        *(p + i) = cast<char>(0);
    }
}

fn mgc_copy(char* dst, char* src, int count) -> void {
    if (dst == null || src == null || count <= 0) { return; }
    for (int i = 0; i < count; i = i + 1) {
        *(dst + i) = *(src + i);
    }
}

fn mgc_equal(char* a, char* b, int count) -> bool {
    if (a == null || b == null || count < 0) { return false; }
    for (int i = 0; i < count; i = i + 1) {
        if (*(a + i) != *(b + i)) { return false; }
    }
    return true;
}

fn mgc_compare(char* a, char* b, int count) -> int {
    if (a == null && b == null) { return 0; }
    if (a == null) { return -1; }
    if (b == null) { return 1; }
    for (int i = 0; i < count; i = i + 1) {
        int av = cast<int>(*(a + i)) & 255;
        int bv = cast<int>(*(b + i)) & 255;
        if (av < bv) { return -1; }
        if (av > bv) { return 1; }
    }
    return 0;
}

fn mgc_min_int(int a, int b) -> int {
    if (a < b) { return a; }
    return b;
}

fn mgc_max_int(int a, int b) -> int {
    if (a > b) { return a; }
    return b;
}
