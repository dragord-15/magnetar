struct History {
    char** undo_text;
    int* undo_cursor;
    int* undo_anchor;
    int undo_count;
    char** redo_text;
    int* redo_cursor;
    int* redo_anchor;
    int redo_count;
    int cap;
    int last_frame;
}

fn hist_dup(string s) -> char* {
    char* p = cast<char*>(s);
    int n = 0;
    while (*(p + n) != 0) { n = n + 1; }
    char* out = alloc<char>(n + 1);
    int i = 0;
    while (i < n) {
        *(out + i) = *(p + i);
        i = i + 1;
    }
    *(out + n) = 0;
    return out;
}

fn hist_init(History* h, int cap) -> void {
    if (cap < 8) { cap = 8; }
    h.cap = cap;
    h.undo_text = alloc<char*>(cap);
    h.undo_cursor = alloc<int>(cap);
    h.undo_anchor = alloc<int>(cap);
    h.undo_count = 0;
    h.redo_text = alloc<char*>(cap);
    h.redo_cursor = alloc<int>(cap);
    h.redo_anchor = alloc<int>(cap);
    h.redo_count = 0;
    h.last_frame = -1000000;
}

fn hist_clear(History* h) -> void {
    int i = 0;
    while (i < h.undo_count) {
        if (h.undo_text[i] != null) { free(h.undo_text[i]); }
        i = i + 1;
    }
    i = 0;
    while (i < h.redo_count) {
        if (h.redo_text[i] != null) { free(h.redo_text[i]); }
        i = i + 1;
    }
    h.undo_count = 0;
    h.redo_count = 0;
    h.last_frame = -1000000;
}

fn hist_destroy(History* h) -> void {
    hist_clear(h);
    free(h.undo_text);
    free(h.undo_cursor);
    free(h.undo_anchor);
    free(h.redo_text);
    free(h.redo_cursor);
    free(h.redo_anchor);
    h.undo_text = null;
    h.redo_text = null;
}

fn hist_clear_redo(History* h) -> void {
    int i = 0;
    while (i < h.redo_count) {
        if (h.redo_text[i] != null) { free(h.redo_text[i]); }
        i = i + 1;
    }
    h.redo_count = 0;
}

fn hist_push_undo(History* h, string text, int cursor, int anchor, int frame, int force) -> void {
    if (force == 0 && frame - h.last_frame < 18) {
        h.last_frame = frame;
        return;
    }
    hist_clear_redo(h);
    if (h.undo_count >= h.cap) {
        if (h.undo_text[0] != null) { free(h.undo_text[0]); }
        int i = 0;
        while (i < h.cap - 1) {
            h.undo_text[i] = h.undo_text[i + 1];
            h.undo_cursor[i] = h.undo_cursor[i + 1];
            h.undo_anchor[i] = h.undo_anchor[i + 1];
            i = i + 1;
        }
        h.undo_count = h.cap - 1;
    }
    int at = h.undo_count;
    h.undo_text[at] = hist_dup(text);
    h.undo_cursor[at] = cursor;
    h.undo_anchor[at] = anchor;
    h.undo_count = h.undo_count + 1;
    h.last_frame = frame;
}

fn hist_push_redo(History* h, string text, int cursor, int anchor) -> void {
    if (h.redo_count >= h.cap) {
        if (h.redo_text[0] != null) { free(h.redo_text[0]); }
        int i = 0;
        while (i < h.cap - 1) {
            h.redo_text[i] = h.redo_text[i + 1];
            h.redo_cursor[i] = h.redo_cursor[i + 1];
            h.redo_anchor[i] = h.redo_anchor[i + 1];
            i = i + 1;
        }
        h.redo_count = h.cap - 1;
    }
    int at = h.redo_count;
    h.redo_text[at] = hist_dup(text);
    h.redo_cursor[at] = cursor;
    h.redo_anchor[at] = anchor;
    h.redo_count = h.redo_count + 1;
}

fn hist_undo(History* h, string current, int cursor, int anchor, int frame, char** out_text, int* out_cursor, int* out_anchor) -> int {
    if (h.undo_count <= 0) { return 0; }
    hist_push_redo(h, current, cursor, anchor);
    h.undo_count = h.undo_count - 1;
    *out_text = h.undo_text[h.undo_count];
    *out_cursor = h.undo_cursor[h.undo_count];
    *out_anchor = h.undo_anchor[h.undo_count];
    h.undo_text[h.undo_count] = null;
    h.last_frame = -1000000;
    return 1;
}

fn hist_redo(History* h, string current, int cursor, int anchor, int frame, char** out_text, int* out_cursor, int* out_anchor) -> int {
    if (h.redo_count <= 0) { return 0; }
    if (h.undo_count >= h.cap) {
        if (h.undo_text[0] != null) { free(h.undo_text[0]); }
        int i = 0;
        while (i < h.cap - 1) {
            h.undo_text[i] = h.undo_text[i + 1];
            h.undo_cursor[i] = h.undo_cursor[i + 1];
            h.undo_anchor[i] = h.undo_anchor[i + 1];
            i = i + 1;
        }
        h.undo_count = h.cap - 1;
    }
    int at = h.undo_count;
    h.undo_text[at] = hist_dup(current);
    h.undo_cursor[at] = cursor;
    h.undo_anchor[at] = anchor;
    h.undo_count = h.undo_count + 1;
    h.redo_count = h.redo_count - 1;
    *out_text = h.redo_text[h.redo_count];
    *out_cursor = h.redo_cursor[h.redo_count];
    *out_anchor = h.redo_anchor[h.redo_count];
    h.redo_text[h.redo_count] = null;
    h.last_frame = -1000000;
    return 1;
}
