static char* SEARCH_QUERY;
static char* SEARCH_REPLACE;
static int SEARCH_LEN;
static int SEARCH_REPLACE_LEN;
static int SEARCH_ACTIVE;
static int SF_TOTAL;
static int SF_START;
static int SF_FOUND;
static int SF_I;
static int SF_A;
static int SF_EN;
static int SF_SEL_A;
static int SF_SEL_EN;
static int SF_COUNT;
static int SM_POS;
static int SM_QN;
static int SM_I;

fn search_init() -> void {
    SEARCH_QUERY = alloc<char>(256);
    SEARCH_REPLACE = alloc<char>(256);
    *(SEARCH_QUERY) = 0;
    *(SEARCH_REPLACE) = 0;
    SEARCH_LEN = 0;
    SEARCH_REPLACE_LEN = 0;
    SEARCH_ACTIVE = 0;
}

fn search_begin() -> void {
    SEARCH_ACTIVE = 1;
    SEARCH_LEN = 0;
    *(SEARCH_QUERY) = 0;
}

fn search_cancel() -> void {
    SEARCH_ACTIVE = 0;
}

fn search_active() -> int {
    return SEARCH_ACTIVE;
}

fn search_input(int c) -> void {
    if (c < 32 || c > 126) { return; }
    if (SEARCH_LEN >= 254) { return; }
    SEARCH_QUERY[SEARCH_LEN] = cast<char>(c);
    SEARCH_LEN = SEARCH_LEN + 1;
    SEARCH_QUERY[SEARCH_LEN] = 0;
}

fn search_backspace() -> void {
    if (SEARCH_LEN <= 0) { return; }
    SEARCH_LEN = SEARCH_LEN - 1;
    SEARCH_QUERY[SEARCH_LEN] = 0;
}

fn search_query_text() -> string {
    return cast<string>(SEARCH_QUERY);
}

fn search_match_at(int pos, int qn) -> int {
    SM_POS = pos;
    SM_QN = qn;
    SM_I = 0;
    while (SM_I < SM_QN) {
        int a = gb_byte(DOC.buf, SM_POS + SM_I);
        if (a < 0) { a = a + 256; }
        if (a >= 65 && a <= 90) { a = a + 32; }
        int b = cast<int>(SEARCH_QUERY[SM_I]);
        if (b < 0) { b = b + 256; }
        if (b >= 65 && b <= 90) { b = b + 32; }
        if (a != b) { return 0; }
        SM_I = SM_I + 1;
    }
    return 1;
}

fn search_select(int pos, int n) -> void {
    SF_SEL_A = pos;
    SF_SEL_EN = pos + n;
    doc_set_cursor(SF_SEL_A, 0);
    doc_set_cursor(SF_SEL_EN, 1);
    view_ensure_cursor_visible();
}

fn search_find(int forward) -> int {
    if (SEARCH_LEN <= 0) { return 0; }
    SF_TOTAL = gb_len(DOC.buf);
    SF_START = doc_cursor();
    if (doc_has_selection() == 1) {
        SF_A = doc_selection_start();
        SF_EN = doc_selection_end();
        if (SF_EN - SF_A == SEARCH_LEN && search_match_at(SF_A, SEARCH_LEN) == 1) {
            if (forward == 1) { SF_START = SF_EN; } else { SF_START = SF_A - 1; }
        }
    }
    SF_FOUND = -1;
    if (forward == 1) {
        SF_I = SF_START;
        if (SF_I < 0) { SF_I = 0; }
        while (SF_I + SEARCH_LEN <= SF_TOTAL) {
            if (search_match_at(SF_I, SEARCH_LEN) == 1) {
                SF_FOUND = SF_I;
                break;
            }
            SF_I = SF_I + 1;
        }
        if (SF_FOUND < 0 && SF_START > 0) {
            SF_I = 0;
            while (SF_I + SEARCH_LEN <= SF_TOTAL && SF_I < SF_START) {
                if (search_match_at(SF_I, SEARCH_LEN) == 1) {
                    SF_FOUND = SF_I;
                    break;
                }
                SF_I = SF_I + 1;
            }
        }
    } else {
        SF_I = SF_START;
        if (SF_I > SF_TOTAL - SEARCH_LEN) { SF_I = SF_TOTAL - SEARCH_LEN; }
        while (SF_I >= 0) {
            if (search_match_at(SF_I, SEARCH_LEN) == 1) {
                SF_FOUND = SF_I;
                break;
            }
            SF_I = SF_I - 1;
        }
        if (SF_FOUND < 0 && SF_START < SF_TOTAL) {
            SF_I = SF_TOTAL - SEARCH_LEN;
            while (SF_I >= 0) {
                if (search_match_at(SF_I, SEARCH_LEN) == 1) {
                    SF_FOUND = SF_I;
                    break;
                }
                SF_I = SF_I - 1;
            }
        }
    }
    if (SF_FOUND < 0) { return 0; }
    search_select(SF_FOUND, SEARCH_LEN);
    return 1;
}

fn search_replace_current() -> int {
    if (SEARCH_LEN <= 0) { return 0; }
    if (doc_has_selection() == 0) { return 0; }
    SF_SEL_A = doc_selection_start();
    SF_SEL_EN = doc_selection_end();
    if (SF_SEL_EN - SF_SEL_A != SEARCH_LEN) { return 0; }
    if (search_match_at(SF_SEL_A, SEARCH_LEN) == 0) { return 0; }
    doc_delete_range(SF_SEL_A, SF_SEL_EN, 1);
    doc_insert_text(cast<string>(SEARCH_REPLACE), 1);
    return 1;
}

fn search_replace_all() -> int {
    if (SEARCH_LEN <= 0) { return 0; }
    SF_COUNT = 0;
    doc_set_cursor(0, 0);
    while (search_find(1) == 1) {
        if (search_replace_current() == 0) { break; }
        SF_COUNT = SF_COUNT + 1;
        if (SF_COUNT > 10000) { break; }
    }
    return SF_COUNT;
}
