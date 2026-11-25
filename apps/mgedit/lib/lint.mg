static char* LINT_TEXT;
static char* LINT_FIRST;
static int LINT_STATE;
static int LINT_ERRORS;
static int LINT_LINES;

fn lint_init() -> void {
    LINT_TEXT = alloc<char>(8192);
    LINT_FIRST = alloc<char>(512);
    *(LINT_TEXT) = 0;
    *(LINT_FIRST) = 0;
    LINT_STATE = 0;
    LINT_ERRORS = 0;
    LINT_LINES = 0;
}

fn lint_copy(char* dst, int cap, string src) -> void {
    char* p = cast<char*>(src);
    int i = 0;
    while (*(p + i) != 0 && i < cap - 1) {
        *(dst + i) = *(p + i);
        i = i + 1;
    }
    *(dst + i) = 0;
}

fn lint_has(string line, string sub) -> int {
    char* a = cast<char*>(line);
    char* b = cast<char*>(sub);
    int al = 0;
    while (*(a + al) != 0) { al = al + 1; }
    int bl = 0;
    while (*(b + bl) != 0) { bl = bl + 1; }
    if (bl == 0) { return 1; }
    int i = 0;
    while (i + bl <= al) {
        int k = 0;
        int same = 1;
        while (k < bl) {
            if (*(a + i + k) != *(b + k)) { same = 0; break; }
            k = k + 1;
        }
        if (same == 1) { return 1; }
        i = i + 1;
    }
    return 0;
}

fn lint_load() -> int {
    string path = "/tmp/mgedit_build.log";
    *(LINT_TEXT) = 0;
    *(LINT_FIRST) = 0;
    LINT_ERRORS = 0;
    LINT_LINES = 0;
    LINT_STATE = 0;
    if (file_is_file(path) == false) { return 0; }
    string data = file_read_all(path);
    lint_copy(LINT_TEXT, 8192, data);
    if (len(data) > 0) { free(cast<char*>(data)); }
    char* p = LINT_TEXT;
    int i = 0;
    int line_no = 0;
    while (*(p + i) != 0) {
        int st = i;
        while (*(p + i) != 0 && *(p + i) != 10) { i = i + 1; }
        int n = i - st;
        if (n > 0) {
            char* line = alloc<char>(n + 1);
            int k = 0;
            while (k < n) { *(line + k) = *(p + st + k); k = k + 1; }
            *(line + n) = 0;
            if (lint_has(cast<string>(line), "error") == 1 || lint_has(cast<string>(line), "Error") == 1) {
                if (LINT_ERRORS == 0) { lint_copy(LINT_FIRST, 512, cast<string>(line)); }
                LINT_ERRORS = LINT_ERRORS + 1;
            }
            free(line);
            LINT_LINES = LINT_LINES + 1;
        }
        if (*(p + i) == 10) { i = i + 1; }
    }
    if (LINT_ERRORS > 0) { LINT_STATE = 2; }
    else { LINT_STATE = 1; }
    return LINT_STATE;
}

fn lint_show() -> int {
    if (view_tree_on() == 0) { return 0; }
    return 0;
}

fn lint_toggle() -> void {
    view_toggle_lint();
    if (VIEW_LINT_ON == 1) { lint_load(); }
}

fn lint_state() -> int {
    return LINT_STATE;
}

fn lint_errors() -> int {
    return LINT_ERRORS;
}

fn lint_first() -> string {
    return cast<string>(LINT_FIRST);
}

fn lint_text() -> string {
    return cast<string>(LINT_TEXT);
}

fn lint_line_count() -> int {
    return LINT_LINES;
}
