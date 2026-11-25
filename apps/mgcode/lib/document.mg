struct Document {
    GapBuffer* buf;
    History* hist;
    int cursor;
    int anchor;
    int dirty;
    int frame;
    int last_edit_frame;
    int* lines;
    int line_count;
    int line_cap;
}

static Document* DOC;
static char* DOC_PATH;
static char* DOC_AUTOSAVE;

fn doc_init() -> void {
    DOC = new Document;
    DOC.buf = new GapBuffer;
    DOC.hist = new History;
    gb_init(DOC.buf, 4096);
    hist_init(DOC.hist, 64);
    DOC.cursor = 0;
    DOC.anchor = 0;
    DOC.dirty = 0;
    DOC.frame = 0;
    DOC.last_edit_frame = 0;
    DOC_PATH = alloc<char>(1024);
    *(DOC_PATH) = 0;
    DOC_AUTOSAVE = alloc<char>(1024);
    char* ap = cast<char*>("/tmp/mgcode_autosave.mg");
    int i = 0;
    while (*(ap + i) != 0) { DOC_AUTOSAVE[i] = *(ap + i); i = i + 1; }
    DOC_AUTOSAVE[i] = 0;
    DOC.line_cap = 65536;
    DOC.lines = alloc<int>(DOC.line_cap);
    DOC.line_count = 1;
    DOC.lines[0] = 0;
}

fn doc_rebuild_lines() -> void {
    DOC.line_count = 1;
    DOC.lines[0] = 0;
    int n = gb_len(DOC.buf);
    int i = 0;
    while (i < n) {
        if (gb_byte(DOC.buf, i) == 10 && DOC.line_count < DOC.line_cap) {
            DOC.lines[DOC.line_count] = i + 1;
            DOC.line_count = DOC.line_count + 1;
        }
        i = i + 1;
    }
}

fn doc_len() -> int {
    return gb_len(DOC.buf);
}

fn doc_char_at(int pos) -> int {
    return gb_byte(DOC.buf, pos);
}

fn doc_line_count() -> int {
    return DOC.line_count;
}

fn doc_line_index(int offset) -> int {
    int n = gb_len(DOC.buf);
    if (offset < 0) { offset = 0; }
    if (offset > n) { offset = n; }
    int lo = 0;
    int hi = DOC.line_count - 1;
    while (lo <= hi) {
        int mid = (lo + hi) / 2;
        if (DOC.lines[mid] <= offset) { lo = mid + 1; }
        else { hi = mid - 1; }
    }
    if (hi < 0) { hi = 0; }
    if (hi >= DOC.line_count) { hi = DOC.line_count - 1; }
    return hi;
}

fn doc_line_start(int li) -> int {
    if (li < 0) { li = 0; }
    if (li >= DOC.line_count) { li = DOC.line_count - 1; }
    return DOC.lines[li];
}

fn doc_line_end(int li) -> int {
    if (li < 0) { li = 0; }
    if (li >= DOC.line_count) { li = DOC.line_count - 1; }
    int st = DOC.lines[li];
    int en = gb_len(DOC.buf);
    if (li + 1 < DOC.line_count) { en = DOC.lines[li + 1] - 1; }
    return en;
}

fn doc_visual_col(int st, int pos) -> int {
    if (pos < st) { pos = st; }
    int n = gb_len(DOC.buf);
    if (pos > n) { pos = n; }
    int vc = 0;
    int i = st;
    while (i < pos) {
        int c = gb_byte(DOC.buf, i);
        if (c == 9) {
            int tab = CFG_TAB_SIZE;
            if (tab < 1) { tab = 4; }
            vc = vc + (tab - (vc - (vc / tab) * tab));
        } else {
            vc = vc + 1;
        }
        i = i + 1;
    }
    return vc;
}

fn doc_offset_from_visual_col(int li, int target) -> int {
    if (target < 0) { target = 0; }
    int st = doc_line_start(li);
    int en = doc_line_end(li);
    int vc = 0;
    int i = st;
    while (i < en) {
        int c = gb_byte(DOC.buf, i);
        int adv = 1;
        if (c == 9) {
            int tab = CFG_TAB_SIZE;
            if (tab < 1) { tab = 4; }
            adv = tab - (vc - (vc / tab) * tab);
        }
        if (vc + adv > target) { return i; }
        vc = vc + adv;
        i = i + 1;
    }
    return en;
}

fn doc_line_copy(int li, char* out, int cap) -> void {
    if (cap <= 0) { return; }
    int st = doc_line_start(li);
    int en = doc_line_end(li);
    int i = st;
    int j = 0;
    while (i < en && j < cap - 1) {
        int c = gb_byte(DOC.buf, i);
        if (c < 32 || c > 126) { c = 32; }
        *(out + j) = cast<char>(c);
        i = i + 1;
        j = j + 1;
    }
    *(out + j) = 0;
}

fn doc_mark_dirty() -> void {
    DOC.dirty = 1;
    DOC.last_edit_frame = DOC.frame;
}

fn doc_is_dirty() -> int {
    return DOC.dirty;
}

fn doc_set_frame(int f) -> void {
    DOC.frame = f;
}

fn doc_set_path(string p) -> void {
    char* s = cast<char*>(p);
    int i = 0;
    while (*(s + i) != 0 && i < 1023) {
        DOC_PATH[i] = *(s + i);
        i = i + 1;
    }
    DOC_PATH[i] = 0;
}

fn doc_path() -> string {
    return cast<string>(DOC_PATH);
}

fn doc_path_len() -> int {
    int i = 0;
    while (DOC_PATH[i] != 0) { i = i + 1; }
    return i;
}

fn doc_clear_text() -> void {
    gb_set(DOC.buf, "");
    DOC.cursor = 0;
    DOC.anchor = 0;
    DOC.dirty = 0;
    doc_rebuild_lines();
}

fn doc_set_text(string s) -> void {
    gb_set(DOC.buf, s);
    DOC.cursor = 0;
    DOC.anchor = 0;
    DOC.dirty = 0;
    doc_rebuild_lines();
}

fn doc_set_cursor(int pos, int extend) -> void {
    int n = gb_len(DOC.buf);
    if (pos < 0) { pos = 0; }
    if (pos > n) { pos = n; }
    if (extend == 0) { DOC.anchor = pos; }
    DOC.cursor = pos;
}

fn doc_cursor() -> int {
    return DOC.cursor;
}

fn doc_anchor() -> int {
    return DOC.anchor;
}

fn doc_selection_start() -> int {
    if (DOC.anchor < DOC.cursor) { return DOC.anchor; }
    return DOC.cursor;
}

fn doc_selection_end() -> int {
    if (DOC.anchor > DOC.cursor) { return DOC.anchor; }
    return DOC.cursor;
}

fn doc_has_selection() -> int {
    if (DOC.anchor != DOC.cursor) { return 1; }
    return 0;
}

fn doc_delete_range_raw(int a, int en) -> void {
    if (a < 0) { a = 0; }
    if (en > gb_len(DOC.buf)) { en = gb_len(DOC.buf); }
    if (a >= en) { return; }
    gb_delete(DOC.buf, a, en);
    DOC.cursor = a;
    DOC.anchor = a;
    doc_rebuild_lines();
    doc_mark_dirty();
}

fn doc_history_push(int force) -> void {
    string s = gb_to_string(DOC.buf);
    hist_push_undo(DOC.hist, s, DOC.cursor, DOC.anchor, DOC.frame, force);
    free(cast<char*>(s));
}

fn doc_delete_range(int a, int en, int force) -> void {
    if (a < 0) { a = 0; }
    if (en > gb_len(DOC.buf)) { en = gb_len(DOC.buf); }
    if (a >= en) { return; }
    doc_history_push(force);
    doc_delete_range_raw(a, en);
}

fn doc_delete_selection(int force) -> int {
    int a = doc_selection_start();
    int en = doc_selection_end();
    if (a == en) { return 0; }
    doc_delete_range(a, en, force);
    return 1;
}

fn doc_insert_text(string s, int force) -> void {
    char* p = cast<char*>(s);
    if (*(p) == 0) { return; }
    doc_history_push(force);
    if (doc_has_selection() == 1) {
        int a = doc_selection_start();
        int en = doc_selection_end();
        gb_delete(DOC.buf, a, en);
        DOC.cursor = a;
        DOC.anchor = a;
    }
    gb_insert_string(DOC.buf, DOC.cursor, s);
    int n = 0;
    while (*(p + n) != 0) {
        if (cast<int>(*(p + n)) != 13) { DOC.cursor = DOC.cursor + 1; }
        n = n + 1;
    }
    DOC.anchor = DOC.cursor;
    doc_rebuild_lines();
    doc_mark_dirty();
}

fn doc_insert_char(int c, int force) -> void {
    if (c == 13) { return; }
    doc_history_push(force);
    if (doc_has_selection() == 1) {
        int a = doc_selection_start();
        int en = doc_selection_end();
        gb_delete(DOC.buf, a, en);
        DOC.cursor = a;
        DOC.anchor = a;
    }
    gb_insert_char(DOC.buf, DOC.cursor, c);
    DOC.cursor = DOC.cursor + 1;
    DOC.anchor = DOC.cursor;
    doc_rebuild_lines();
    doc_mark_dirty();
}

fn doc_backspace() -> void {
    if (doc_has_selection() == 1) {
        doc_delete_selection(0);
        return;
    }
    if (DOC.cursor <= 0) { return; }
    doc_delete_range(DOC.cursor - 1, DOC.cursor, 0);
}

fn doc_delete_forward() -> void {
    if (doc_has_selection() == 1) {
        doc_delete_selection(0);
        return;
    }
    if (DOC.cursor >= gb_len(DOC.buf)) { return; }
    doc_delete_range(DOC.cursor, DOC.cursor + 1, 0);
}

fn doc_undo() -> int {
    string cur = gb_to_string(DOC.buf);
    char* txt = null;
    int c = 0;
    int a = 0;
    int ok = hist_undo(DOC.hist, cur, DOC.cursor, DOC.anchor, DOC.frame, &txt, &c, &a);
    free(cast<char*>(cur));
    if (ok == 0) { return 0; }
    gb_set(DOC.buf, cast<string>(txt));
    free(txt);
    DOC.cursor = c;
    DOC.anchor = a;
    doc_rebuild_lines();
    doc_mark_dirty();
    return 1;
}

fn doc_redo() -> int {
    string cur = gb_to_string(DOC.buf);
    char* txt = null;
    int c = 0;
    int a = 0;
    int ok = hist_redo(DOC.hist, cur, DOC.cursor, DOC.anchor, DOC.frame, &txt, &c, &a);
    free(cast<char*>(cur));
    if (ok == 0) { return 0; }
    gb_set(DOC.buf, cast<string>(txt));
    free(txt);
    DOC.cursor = c;
    DOC.anchor = a;
    doc_rebuild_lines();
    doc_mark_dirty();
    return 1;
}

fn doc_select_all() -> void {
    DOC.anchor = 0;
    DOC.cursor = gb_len(DOC.buf);
}

fn doc_copy_selection() -> string {
    int a = doc_selection_start();
    int en = doc_selection_end();
    return gb_range_to_string(DOC.buf, a, en);
}

fn doc_new() -> void {
    doc_clear_text();
    *(DOC_PATH) = 0;
    hist_clear(DOC.hist);
}

fn doc_load_file(string path) -> int {
    if (file_is_file(path) == false) { return 0; }
    if (file_size(path) > 131072) { return -1; }
    string data = file_read_all(path);
    doc_set_text(data);
    if (len(data) > 0) { free(cast<char*>(data)); }
    doc_set_path(path);
    hist_clear(DOC.hist);
    DOC.cursor = 0;
    DOC.anchor = 0;
    DOC.dirty = 0;
    doc_rebuild_lines();
    return 1;
}

fn doc_save_file(string path, int overwrite_path) -> int {
    string data = gb_to_string(DOC.buf);
    bool ok = file_write_all(path, data);
    free(cast<char*>(data));
    if (ok == false) { return 0; }
    if (overwrite_path == 1) { doc_set_path(path); }
    DOC.dirty = 0;
    return 1;
}

fn doc_flush() -> int {
    if (DOC.dirty == 0) { return 1; }
    if (doc_path_len() > 0) { return doc_save_file(doc_path(), 0); }
    return doc_save_file(cast<string>(DOC_AUTOSAVE), 0);
}

fn doc_autosave(int frame) -> int {
    if (CFG_AUTOSAVE == 0) { return 0; }
    if (DOC.dirty == 0) { return 0; }
    int delta = frame - DOC.last_edit_frame;
    if (delta < CFG_AUTOSAVE_FRAMES && frame > 0) { return 0; }
    if (doc_path_len() > 0) { return doc_save_file(doc_path(), 0); }
    return doc_save_file(cast<string>(DOC_AUTOSAVE), 0);
}
