static int CUR_WANT_COL;

fn cur_init() -> void {
    CUR_WANT_COL = -1;
}

fn cur_reset_want() -> void {
    CUR_WANT_COL = -1;
}

fn cur_is_word_start(int c) -> int {
    if (c >= 65 && c <= 90) { return 1; }
    if (c >= 97 && c <= 122) { return 1; }
    if (c == 95) { return 1; }
    return 0;
}

fn cur_is_word_char(int c) -> int {
    if (cur_is_word_start(c) == 1) { return 1; }
    if (c >= 48 && c <= 57) { return 1; }
    return 0;
}

fn cur_set(int pos, int extend) -> void {
    doc_set_cursor(pos, extend);
    view_ensure_cursor_visible();
}

fn cur_left(int shift) -> void {
    cur_reset_want();
    if (shift == 0 && doc_has_selection() == 1) {
        cur_set(doc_selection_start(), 0);
        return;
    }
    cur_set(doc_cursor() - 1, shift);
}

fn cur_right(int shift) -> void {
    cur_reset_want();
    if (shift == 0 && doc_has_selection() == 1) {
        cur_set(doc_selection_end(), 0);
        return;
    }
    cur_set(doc_cursor() + 1, shift);
}

fn cur_vertical(int delta, int shift) -> void {
    int li = doc_line_index(doc_cursor());
    int want = CUR_WANT_COL;
    if (want < 0) { want = doc_visual_col(doc_line_start(li), doc_cursor()); }
    int target = li + delta;
    if (target < 0) { target = 0; }
    if (target >= doc_line_count()) { target = doc_line_count() - 1; }
    int pos = doc_offset_from_visual_col(target, want);
    doc_set_cursor(pos, shift);
    CUR_WANT_COL = want;
    view_ensure_cursor_visible();
}

fn cur_home(int shift) -> void {
    cur_reset_want();
    int li = doc_line_index(doc_cursor());
    cur_set(doc_line_start(li), shift);
}

fn cur_end(int shift) -> void {
    cur_reset_want();
    int li = doc_line_index(doc_cursor());
    cur_set(doc_line_end(li), shift);
}

fn cur_doc_start(int shift) -> void {
    cur_reset_want();
    cur_set(0, shift);
}

fn cur_doc_end(int shift) -> void {
    cur_reset_want();
    cur_set(doc_len(), shift);
}

fn cur_page(int delta, int shift) -> void {
    int rows = view_rows();
    cur_vertical(delta * (rows - 1), shift);
}

fn cur_word_left(int shift) -> void {
    cur_reset_want();
    int pos = doc_cursor();
    while (pos > 0) {
        int c = doc_char_at(pos - 1);
        if (cur_is_word_char(c) == 1) { break; }
        pos = pos - 1;
    }
    while (pos > 0) {
        int c = doc_char_at(pos - 1);
        if (cur_is_word_char(c) == 0) { break; }
        pos = pos - 1;
    }
    cur_set(pos, shift);
}

fn cur_word_right(int shift) -> void {
    cur_reset_want();
    int pos = doc_cursor();
    int n = doc_len();
    while (pos < n) {
        int c = doc_char_at(pos);
        if (cur_is_word_char(c) == 1) { break; }
        pos = pos + 1;
    }
    while (pos < n) {
        int c = doc_char_at(pos);
        if (cur_is_word_char(c) == 0) { break; }
        pos = pos + 1;
    }
    cur_set(pos, shift);
}
