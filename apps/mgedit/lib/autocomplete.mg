static char* AC_BUF;
static char* AC_PREFIX;

fn ac_init() -> void {
    AC_BUF = alloc<char>(128);
    AC_PREFIX = alloc<char>(128);
    *(AC_BUF) = 0;
    *(AC_PREFIX) = 0;
}

fn ac_scan_list(string list, int plen) -> int {
    char* l = cast<char*>(list);
    int i = 0;
    while (*(l + i) != 0) {
        while (*(l + i) == 32) { i = i + 1; }
        int st = i;
        while (*(l + i) != 0 && *(l + i) != 32) { i = i + 1; }
        int n = i - st;
        if (n > plen) {
            int k = 0;
            int same = 1;
            while (k < plen) {
                if (*(l + st + k) != AC_PREFIX[k]) {
                    same = 0;
                    break;
                }
                k = k + 1;
            }
            if (same == 1) {
                k = 0;
                while (k < n && k < 120) {
                    AC_BUF[k] = *(l + st + k);
                    k = k + 1;
                }
                AC_BUF[k] = 0;
                return 1;
            }
        }
    }
    return 0;
}

fn ac_complete() -> int {
    int pos = doc_cursor();
    int st = pos;
    while (st > 0 && cur_is_word_char(doc_char_at(st - 1)) == 1) { st = st - 1; }
    int n = pos - st;
    if (n <= 0) { return 0; }
    if (n > 120) { return 0; }
    int i = 0;
    while (i < n) {
        AC_PREFIX[i] = cast<char>(doc_char_at(st + i));
        i = i + 1;
    }
    AC_PREFIX[n] = 0;
    if (ac_scan_list(syn_types(), n) == 0) {
        if (ac_scan_list(syn_keywords(), n) == 0) { return 0; }
    }
    int match_len = 0;
    while (*(AC_BUF + match_len) != 0) { match_len = match_len + 1; }
    doc_delete_range(st, pos, 1);
    doc_insert_text(cast<string>(AC_BUF), 1);
    return match_len;
}

fn ac_last() -> string {
    return cast<string>(AC_BUF);
}
