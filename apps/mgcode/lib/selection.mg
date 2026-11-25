static char* SEL_CLIP;
static int SEL_CLIP_LEN;

fn sel_init() -> void {
    SEL_CLIP = alloc<char>(131072);
    *(SEL_CLIP) = 0;
    SEL_CLIP_LEN = 0;
}

fn sel_copy() -> int {
    string s = doc_copy_selection();
    char* p = cast<char*>(s);
    int n = 0;
    while (*(p + n) != 0 && n < 131071) { n = n + 1; }
    int i = 0;
    while (i < n) {
        SEL_CLIP[i] = *(p + i);
        i = i + 1;
    }
    SEL_CLIP[n] = 0;
    SEL_CLIP_LEN = n;
    free(p);
    return n;
}

fn sel_cut() -> int {
    if (sel_copy() == 0) { return 0; }
    doc_delete_selection(1);
    return 1;
}

fn sel_paste() -> int {
    if (SEL_CLIP_LEN <= 0) { return 0; }
    doc_insert_text(cast<string>(SEL_CLIP), 1);
    return 1;
}

fn sel_select_all() -> void {
    doc_select_all();
    view_ensure_cursor_visible();
}

fn sel_clear() -> void {
    doc_set_cursor(doc_cursor(), 0);
}
