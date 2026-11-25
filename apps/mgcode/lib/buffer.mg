struct GapBuffer {
    char* data;
    int cap;
    int gap_start;
    int gap_end;
    int len;
}

fn gb_byte(GapBuffer* b, int pos) -> int {
    if (pos < 0 || pos >= b.len) { return 0; }
    char* d = b.data;
    int idx = pos;
    if (pos >= b.gap_start) { idx = b.gap_end + (pos - b.gap_start); }
    int v = cast<int>(*(d + idx));
    if (v < 0) { v = v + 256; }
    return v;
}

fn gb_init(GapBuffer* b, int cap) -> void {
    if (cap < 64) { cap = 64; }
    b.data = alloc<char>(cap);
    b.cap = cap;
    b.gap_start = 0;
    b.gap_end = cap;
    b.len = 0;
    *(b.data) = 0;
}

fn gb_destroy(GapBuffer* b) -> void {
    if (b.data != null) { free(b.data); }
    b.data = null;
    b.cap = 0;
    b.gap_start = 0;
    b.gap_end = 0;
    b.len = 0;
}

fn gb_len(GapBuffer* b) -> int {
    return b.len;
}

fn gb_move_gap(GapBuffer* b, int pos) -> void {
    if (pos < 0) { pos = 0; }
    if (pos > b.len) { pos = b.len; }
    char* d = b.data;
    while (b.gap_start > pos) {
        b.gap_start = b.gap_start - 1;
        b.gap_end = b.gap_end - 1;
        *(d + b.gap_end) = *(d + b.gap_start);
    }
    while (b.gap_start < pos) {
        *(d + b.gap_start) = *(d + b.gap_end);
        b.gap_start = b.gap_start + 1;
        b.gap_end = b.gap_end + 1;
    }
}

fn gb_grow(GapBuffer* b) -> void {
    gb_move_gap(b, b.len);
    int oldcap = b.cap;
    int newcap = oldcap * 2;
    if (newcap < 128) { newcap = 128; }
    char* nd = alloc<char>(newcap);
    char* d = b.data;
    int i = 0;
    while (i < b.len) {
        *(nd + i) = *(d + i);
        i = i + 1;
    }
    free(d);
    b.data = nd;
    b.cap = newcap;
    b.gap_start = b.len;
    b.gap_end = newcap;
}

fn gb_insert_char(GapBuffer* b, int pos, int c) -> void {
    gb_move_gap(b, pos);
    if (b.gap_start == b.gap_end) { gb_grow(b); }
    char* d = b.data;
    *(d + b.gap_start) = cast<char>(c);
    b.gap_start = b.gap_start + 1;
    b.len = b.len + 1;
}

fn gb_insert_string(GapBuffer* b, int pos, string s) -> void {
    char* p = cast<char*>(s);
    int i = 0;
    int at = pos;
    while (*(p + i) != 0) {
        int v = cast<int>(*(p + i));
        if (v < 0) { v = v + 256; }
        if (v != 13) {
            gb_insert_char(b, at, v);
            at = at + 1;
        }
        i = i + 1;
    }
}

fn gb_delete(GapBuffer* b, int a, int en) -> void {
    if (a < 0) { a = 0; }
    if (en > b.len) { en = b.len; }
    if (a >= en) { return; }
    gb_move_gap(b, a);
    b.gap_end = b.gap_end + (en - a);
    b.len = b.len - (en - a);
}

fn gb_set(GapBuffer* b, string s) -> void {
    b.gap_start = 0;
    b.gap_end = b.cap;
    b.len = 0;
    *(b.data) = 0;
    gb_insert_string(b, 0, s);
}

fn gb_to_string(GapBuffer* b) -> string {
    char* out = alloc<char>(b.len + 1);
    char* d = b.data;
    int i = 0;
    while (i < b.gap_start) {
        *(out + i) = *(d + i);
        i = i + 1;
    }
    char* right = d + b.gap_end;
    int r = 0;
    while (i < b.len) {
        *(out + i) = *(right + r);
        i = i + 1;
        r = r + 1;
    }
    *(out + b.len) = 0;
    return cast<string>(out);
}

fn gb_range_to_string(GapBuffer* b, int a, int en) -> string {
    if (a < 0) { a = 0; }
    if (en > b.len) { en = b.len; }
    if (a >= en) {
        char* empty = alloc<char>(1);
        *(empty) = 0;
        return cast<string>(empty);
    }
    char* out = alloc<char>(en - a + 1);
    int i = a;
    int j = 0;
    while (i < en) {
        *(out + j) = cast<char>(gb_byte(b, i));
        i = i + 1;
        j = j + 1;
    }
    *(out + j) = 0;
    return cast<string>(out);
}
