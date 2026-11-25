fn syn_byte(char* p, int i) -> int {
    int v = cast<int>(*(p + i));
    if (v < 0) { v = v + 256; }
    return v;
}

fn syn_is_word_start(int c) -> int {
    if (c >= 65 && c <= 90) { return 1; }
    if (c >= 97 && c <= 122) { return 1; }
    if (c == 95) { return 1; }
    return 0;
}

fn syn_is_word_char(int c) -> int {
    if (syn_is_word_start(c) == 1) { return 1; }
    if (c >= 48 && c <= 57) { return 1; }
    return 0;
}

fn syn_types() -> string {
    return "int float half bool char string void auto any byte word dword qword fixed slice array ref own raw dyn range tuple typeof";
}

fn syn_keywords() -> string {
    return "fn entry struct class enum union trait impl extends use export as const static extern let if else switch case default for while do break continue return goto defer match new delete alloc free sizeof cast typeof inline volatile register unsafe copy clone borrow move true false null nan inf assert throw try catch finally this self super base print import module package type interface where yield async await spawn parallel asm macro section public private protected internal mut var in is not and or xor";
}

fn syn_word_in_list(char* p, int st, int en, string list) -> int {
    char* l = cast<char*>(list);
    int i = 0;
    while (*(l + i) != 0) {
        while (*(l + i) == 32) { i = i + 1; }
        int s = i;
        while (*(l + i) != 0 && *(l + i) != 32) { i = i + 1; }
        int n = i - s;
        if (n == en - st) {
            int k = 0;
            int same = 1;
            while (k < n) {
                if (syn_byte(p, st + k) != syn_byte(l, s + k)) {
                    same = 0;
                    break;
                }
                k = k + 1;
            }
            if (same == 1) { return 1; }
        }
    }
    return 0;
}

fn syn_kind_at(string line, int col) -> int {
    char* p = cast<char*>(line);
    int in_str = 0;
    int quote = 0;
    int in_line = 0;
    int in_block = 0;
    int i = 0;
    while (*(p + i) != 0) {
        int c = syn_byte(p, i);
        int nx = 0;
        if (*(p + i + 1) != 0) { nx = syn_byte(p, i + 1); }
        if (in_line == 1) {
            if (i == col) { return 4; }
            i = i + 1;
            continue;
        }
        if (in_block == 1) {
            if (c == 42 && nx == 47) {
                if (i == col || i + 1 == col) { return 4; }
                i = i + 2;
                continue;
            }
            if (i == col) { return 4; }
            i = i + 1;
            continue;
        }
        if (in_str == 1) {
            if (c == 92) {
                if (i == col) { return 2; }
                i = i + 2;
                continue;
            }
            if (c == quote) {
                if (i == col) { return 2; }
                in_str = 0;
                i = i + 1;
                continue;
            }
            if (i == col) { return 2; }
            i = i + 1;
            continue;
        }
        if (c == 47 && nx == 47) {
            if (i == col) { return 4; }
            in_line = 1;
            i = i + 2;
            continue;
        }
        if (c == 47 && nx == 42) {
            if (i == col) { return 4; }
            in_block = 1;
            i = i + 2;
            continue;
        }
        if (c == 34 || c == 39) {
            if (i == col) { return 2; }
            in_str = 1;
            quote = c;
            i = i + 1;
            continue;
        }
        if (i == col) {
            if (c >= 48 && c <= 57) { return 3; }
            if (syn_is_word_start(c) == 1) {
                int st = i;
                int en = i + 1;
                while (*(p + en) != 0 && syn_is_word_char(syn_byte(p, en)) == 1) { en = en + 1; }
                if (syn_word_in_list(p, st, en, syn_types()) == 1) { return 5; }
                if (syn_word_in_list(p, st, en, syn_keywords()) == 1) { return 1; }
                int k = en;
                while (*(p + k) == 32) { k = k + 1; }
                if (*(p + k) == 40) { return 6; }
                return 0;
            }
            return 0;
        }
        i = i + 1;
    }
    return 0;
}
