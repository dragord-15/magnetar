// ============================================================================
// Magnetar Standard Library: String Utilities (lib/string.mg)
// Complete String & Character Manipulation Library for Magnetar
// ============================================================================

extern fn print_str(string s) -> void;

// -------------------------------------------------------------
// 1. Character Inspection & Conversion
// -------------------------------------------------------------

fn is_digit(char c) -> bool {
    return c >= '0' && c <= '9';
}

fn is_alpha(char c) -> bool {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
}

fn is_alphanumeric(char c) -> bool {
    return is_alpha(c) || is_digit(c);
}

fn is_space(char c) -> bool {
    return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' || c == '\f';
}

fn is_upper(char c) -> bool {
    return c >= 'A' && c <= 'Z';
}

fn is_lower(char c) -> bool {
    return c >= 'a' && c <= 'z';
}

fn to_upper(char c) -> char {
    if (c >= 'a' && c <= 'z') {
        return cast<char>(c - 32);
    }
    return c;
}

fn to_lower(char c) -> char {
    if (c >= 'A' && c <= 'Z') {
        return cast<char>(c + 32);
    }
    return c;
}

// -------------------------------------------------------------
// 2. String Properties & Comparisons
// -------------------------------------------------------------

fn str_len(string s) -> int {
    if (cast<char*>(s) == null) {
        return 0;
    }
    return len(s);
}

fn str_is_empty(string s) -> bool {
    if (cast<char*>(s) == null) {
        return true;
    }
    return *cast<char*>(s) == 0;
}

fn str_equals(string a, string b) -> bool {
    char* pa = cast<char*>(a);
    char* pb = cast<char*>(b);
    if (pa == pb) {
        return true;
    }
    if (pa == null || pb == null) {
        return false;
    }
    int i = 0;
    while (*(pa + i) != 0 && *(pb + i) != 0) {
        if (*(pa + i) != *(pb + i)) {
            return false;
        }
        i = i + 1;
    }
    return *(pa + i) == *(pb + i);
}

fn str_equals_ignore_case(string a, string b) -> bool {
    char* pa = cast<char*>(a);
    char* pb = cast<char*>(b);
    if (pa == pb) {
        return true;
    }
    if (pa == null || pb == null) {
        return false;
    }
    int i = 0;
    while (*(pa + i) != 0 && *(pb + i) != 0) {
        char ca = to_lower(*(pa + i));
        char cb = to_lower(*(pb + i));
        if (ca != cb) {
            return false;
        }
        i = i + 1;
    }
    return *(pa + i) == *(pb + i);
}

fn str_compare(string a, string b) -> int {
    char* pa = cast<char*>(a);
    char* pb = cast<char*>(b);
    int i = 0;
    while (*(pa + i) != 0 && *(pb + i) != 0) {
        if (*(pa + i) != *(pb + i)) {
            return cast<int>(*(pa + i)) - cast<int>(*(pb + i));
        }
        i = i + 1;
    }
    return cast<int>(*(pa + i)) - cast<int>(*(pb + i));
}

fn str_starts_with(string s, string prefix) -> bool {
    char* ps = cast<char*>(s);
    char* pp = cast<char*>(prefix);
    int lp = len(prefix);
    if (lp > len(s)) {
        return false;
    }
    for (int i = 0; i < lp; i = i + 1) {
        if (*(ps + i) != *(pp + i)) {
            return false;
        }
    }
    return true;
}

fn str_ends_with(string s, string suffix) -> bool {
    char* ps = cast<char*>(s);
    char* pf = cast<char*>(suffix);
    int ls = len(s);
    int lf = len(suffix);
    if (lf > ls) {
        return false;
    }
    int offset = ls - lf;
    for (int i = 0; i < lf; i = i + 1) {
        int off = offset + i;
        if (*(ps + off) != *(pf + i)) {
            return false;
        }
    }
    return true;
}

fn str_index_of(string s, string sub) -> int {
    char* ps = cast<char*>(s);
    char* pb = cast<char*>(sub);
    int ls = len(s);
    int lb = len(sub);
    if (lb == 0) {
        return 0;
    }
    if (lb > ls) {
        return -1;
    }
    int max_i = ls - lb;
    int i = 0;
    while (i <= max_i) {
        bool is_match = true;
        int j = 0;
        while (j < lb) {
            int off = i + j;
            if (*(ps + off) != *(pb + j)) {
                is_match = false;
                j = lb;
            } else {
                j = j + 1;
            }
        }
        if (is_match) {
            return i;
        }
        i = i + 1;
    }
    return -1;
}

fn str_last_index_of(string s, string sub) -> int {
    char* ps = cast<char*>(s);
    char* pb = cast<char*>(sub);
    int ls = len(s);
    int lb = len(sub);
    if (lb == 0) {
        return ls;
    }
    if (lb > ls) {
        return -1;
    }
    int i = ls - lb;
    while (i >= 0) {
        bool is_match = true;
        int j = 0;
        while (j < lb) {
            int off = i + j;
            if (*(ps + off) != *(pb + j)) {
                is_match = false;
                j = lb;
            } else {
                j = j + 1;
            }
        }
        if (is_match) {
            return i;
        }
        i = i - 1;
    }
    return -1;
}

fn str_contains(string s, string sub) -> bool {
    return str_index_of(s, sub) >= 0;
}

fn str_count(string s, string sub) -> int {
    int lb = len(sub);
    if (lb == 0) {
        return 0;
    }
    int count = 0;
    int pos = str_index_of(s, sub);
    char* ps = cast<char*>(s);
    int ls = len(s);
    while (pos >= 0 && pos + lb <= ls) {
        count = count + 1;
        int new_len = ls - (pos + lb);
        if (new_len <= 0) {
            break;
        }
        int rem_off = pos + lb;
        char* rem = ps + rem_off;
        int next_idx = str_index_of(cast<string>(rem), sub);
        if (next_idx < 0) {
            break;
        }
        pos = pos + lb + next_idx;
    }
    return count;
}

// -------------------------------------------------------------
// 3. String Transformations
// -------------------------------------------------------------

fn str_clone(string s) -> string {
    int ls = len(s);
    char* buf = alloc<char>(ls + 1);
    char* ps = cast<char*>(s);
    for (int i = 0; i < ls; i = i + 1) {
        *(buf + i) = *(ps + i);
    }
    *(buf + ls) = 0;
    return cast<string>(buf);
}

fn str_concat(string a, string b) -> string {
    int la = len(a);
    int lb = len(b);
    char* buf = alloc<char>(la + lb + 1);
    char* pa = cast<char*>(a);
    char* pb = cast<char*>(b);
    for (int i = 0; i < la; i = i + 1) {
        *(buf + i) = *(pa + i);
    }
    for (int j = 0; j < lb; j = j + 1) {
        int off = la + j;
        *(buf + off) = *(pb + j);
    }
    *(buf + la + lb) = 0;
    return cast<string>(buf);
}

fn str_substr(string s, int start, int length) -> string {
    int ls = len(s);
    if (start < 0) {
        start = 0;
    }
    if (start >= ls || length <= 0) {
        return "";
    }
    if (start + length > ls) {
        length = ls - start;
    }
    char* buf = alloc<char>(length + 1);
    char* ps = cast<char*>(s);
    for (int i = 0; i < length; i = i + 1) {
        int off = start + i;
        *(buf + i) = *(ps + off);
    }
    *(buf + length) = 0;
    return cast<string>(buf);
}

fn str_to_upper(string s) -> string {
    int ls = len(s);
    char* buf = alloc<char>(ls + 1);
    char* ps = cast<char*>(s);
    for (int i = 0; i < ls; i = i + 1) {
        *(buf + i) = to_upper(*(ps + i));
    }
    *(buf + ls) = 0;
    return cast<string>(buf);
}

fn str_to_lower(string s) -> string {
    int ls = len(s);
    char* buf = alloc<char>(ls + 1);
    char* ps = cast<char*>(s);
    for (int i = 0; i < ls; i = i + 1) {
        *(buf + i) = to_lower(*(ps + i));
    }
    *(buf + ls) = 0;
    return cast<string>(buf);
}

fn str_trim_left(string s) -> string {
    char* ps = cast<char*>(s);
    int ls = len(s);
    int start = 0;
    while (start < ls && is_space(*(ps + start))) {
        start = start + 1;
    }
    return str_substr(s, start, ls - start);
}

fn str_trim_right(string s) -> string {
    char* ps = cast<char*>(s);
    int ls = len(s);
    int end = ls - 1;
    while (end >= 0 && is_space(*(ps + end))) {
        end = end - 1;
    }
    return str_substr(s, 0, end + 1);
}

fn str_trim(string s) -> string {
    return str_trim_right(str_trim_left(s));
}

fn str_repeat(string s, int count) -> string {
    if (count <= 0) {
        return "";
    }
    int ls = len(s);
    char* buf = alloc<char>(ls * count + 1);
    char* ps = cast<char*>(s);
    int pos = 0;
    for (int c = 0; c < count; c = c + 1) {
        for (int i = 0; i < ls; i = i + 1) {
            *(buf + pos) = *(ps + i);
            pos = pos + 1;
        }
    }
    *(buf + pos) = 0;
    return cast<string>(buf);
}

fn str_replace(string s, string old_sub, string new_sub) -> string {
    int l_old = len(old_sub);
    if (l_old == 0) {
        return str_clone(s);
    }
    int first_idx = str_index_of(s, old_sub);
    if (first_idx < 0) {
        return str_clone(s);
    }

    int ls = len(s);
    int l_new = len(new_sub);
    int count = str_count(s, old_sub);
    int new_total_len = ls + (l_new - l_old) * count;

    char* buf = alloc<char>(new_total_len + 1);
    char* ps = cast<char*>(s);
    char* pnew = cast<char*>(new_sub);

    int r_pos = 0;
    int i = 0;
    while (i < ls) {
        if (i <= ls - l_old) {
            bool sub_match = true;
            char* pold = cast<char*>(old_sub);
            int k = 0;
            while (k < l_old) {
                int off = i + k;
                if (*(ps + off) != *(pold + k)) {
                    sub_match = false;
                    k = l_old;
                } else {
                    k = k + 1;
                }
            }
            if (sub_match) {
                for (int m = 0; m < l_new; m = m + 1) {
                    *(buf + r_pos) = *(pnew + m);
                    r_pos = r_pos + 1;
                }
                i = i + l_old;
                continue;
            }
        }
        *(buf + r_pos) = *(ps + i);
        r_pos = r_pos + 1;
        i = i + 1;
    }
    *(buf + r_pos) = 0;
    return cast<string>(buf);
}

fn str_pad_left(string s, int target_len, char pad_char) -> string {
    int ls = len(s);
    if (ls >= target_len) {
        return str_clone(s);
    }
    int diff = target_len - ls;
    char* buf = alloc<char>(target_len + 1);
    for (int i = 0; i < diff; i = i + 1) {
        *(buf + i) = pad_char;
    }
    char* ps = cast<char*>(s);
    for (int j = 0; j < ls; j = j + 1) {
        int off = diff + j;
        *(buf + off) = *(ps + j);
    }
    *(buf + target_len) = 0;
    return cast<string>(buf);
}

fn str_pad_right(string s, int target_len, char pad_char) -> string {
    int ls = len(s);
    if (ls >= target_len) {
        return str_clone(s);
    }
    char* buf = alloc<char>(target_len + 1);
    char* ps = cast<char*>(s);
    for (int i = 0; i < ls; i = i + 1) {
        *(buf + i) = *(ps + i);
    }
    for (int j = ls; j < target_len; j = j + 1) {
        *(buf + j) = pad_char;
    }
    *(buf + target_len) = 0;
    return cast<string>(buf);
}

// -------------------------------------------------------------
// 4. Conversions (Numbers <-> Strings)
// -------------------------------------------------------------

fn int_to_str(int n) -> string {
    if (n == 0) {
        return "0";
    }
    bool is_neg = false;
    int temp = n;
    if (temp < 0) {
        is_neg = true;
        temp = 0 - temp;
    }
    char* buf = alloc<char>(32);
    int pos = 0;
    while (temp > 0) {
        int rem = temp % 10;
        *(buf + pos) = cast<char>(48 + rem);
        pos = pos + 1;
        temp = temp / 10;
    }
    char* res = alloc<char>(pos + 2);
    int idx = 0;
    if (is_neg) {
        *(res + idx) = '-';
        idx = idx + 1;
    }
    for (int i = 0; i < pos; i = i + 1) {
        int off = pos - 1 - i;
        int target = idx + i;
        *(res + target) = *(buf + off);
    }
    int total_len = idx + pos;
    *(res + total_len) = 0;
    free(buf);
    return cast<string>(res);
}

fn str_to_int(string s) -> int {
    char* p = cast<char*>(s);
    if (*p == 0) {
        return 0;
    }
    int sign = 1;
    int idx = 0;
    if (*p == '-') {
        sign = -1;
        idx = 1;
    } else if (*p == '+') {
        idx = 1;
    }
    int result = 0;
    while (*(p + idx) != 0) {
        char c = *(p + idx);
        if (c >= '0' && c <= '9') {
            result = result * 10 + cast<int>(c - '0');
        } else {
            break;
        }
        idx = idx + 1;
    }
    return result * sign;
}

fn float_to_str(float val, int decimals) -> string {
    if (decimals < 0) {
        decimals = 0;
    }
    if (decimals > 9) {
        decimals = 9;
    }
    bool is_neg = false;
    float temp = val;
    if (temp < 0.0) {
        is_neg = true;
        temp = 0.0 - temp;
    }
    int int_part = cast<int>(temp);
    float frac_part = temp - cast<float>(int_part);

    string s_int = int_to_str(int_part);
    if (decimals == 0) {
        if (is_neg) {
            return str_concat("-", s_int);
        }
        return s_int;
    }

    float mult = 1.0;
    for (int i = 0; i < decimals; i = i + 1) {
        mult = mult * 10.0;
    }
    int frac_int = cast<int>(frac_part * mult + 0.5);
    string s_frac = int_to_str(frac_int);
    int frac_len = len(s_frac);
    if (frac_len < decimals) {
        int diff = decimals - frac_len;
        char* zeros = alloc<char>(diff + 1);
        for (int k = 0; k < diff; k = k + 1) {
            *(zeros + k) = '0';
        }
        *(zeros + diff) = 0;
        s_frac = str_concat(cast<string>(zeros), s_frac);
        free(zeros);
    }

    string res = str_concat(s_int, ".");
    res = str_concat(res, s_frac);
    if (is_neg) {
        res = str_concat("-", res);
    }
    return res;
}

fn hex_to_str(int n) -> string {
    if (n == 0) {
        return "0x0";
    }
    char* hex_digits = "0123456789abcdef";
    char* buf = alloc<char>(32);
    int temp = n;
    int pos = 0;
    while (temp > 0) {
        int rem = temp % 16;
        *(buf + pos) = *(hex_digits + rem);
        pos = pos + 1;
        temp = temp / 16;
    }
    char* res = alloc<char>(pos + 3);
    *(res + 0) = '0';
    *(res + 1) = 'x';
    for (int i = 0; i < pos; i = i + 1) {
        int off = pos - 1 - i;
        int target = 2 + i;
        *(res + target) = *(buf + off);
    }
    int total_len = 2 + pos;
    *(res + total_len) = 0;
    free(buf);
    return cast<string>(res);
}

// -------------------------------------------------------------
// 5. StringBuilder Object
// -------------------------------------------------------------

struct StringBuilder {
    char* buffer;
    int length;
    int capacity;

    fn init(int initial_cap) -> void {
        if (initial_cap < 16) {
            initial_cap = 64;
        }
        capacity = initial_cap;
        buffer = alloc<char>(capacity);
        length = 0;
        *buffer = 0;
    }

    fn ensure_capacity(int needed) -> void {
        if (length + needed + 1 > capacity) {
            int new_cap = capacity * 2;
            if (new_cap < length + needed + 64) {
                new_cap = length + needed + 64;
            }
            char* new_buf = alloc<char>(new_cap);
            for (int i = 0; i < length; i = i + 1) {
                *(new_buf + i) = *(buffer + i);
            }
            *(new_buf + length) = 0;
            free(buffer);
            buffer = new_buf;
            capacity = new_cap;
        }
    }

    fn append(string text) -> void {
        int lt = len(text);
        if (lt == 0) {
            return;
        }
        ensure_capacity(lt);
        char* pt = cast<char*>(text);
        for (int i = 0; i < lt; i = i + 1) {
            int off = length + i;
            *(buffer + off) = *(pt + i);
        }
        length = length + lt;
        *(buffer + length) = 0;
    }

    fn append_char(char c) -> void {
        ensure_capacity(1);
        *(buffer + length) = c;
        length = length + 1;
        *(buffer + length) = 0;
    }

    fn append_int(int n) -> void {
        string s = int_to_str(n);
        append(s);
        free(cast<char*>(s));
    }

    fn append_line(string text) -> void {
        append(text);
        append_char('\n');
    }

    fn to_string() -> string {
        return str_clone(cast<string>(buffer));
    }

    fn clear() -> void {
        length = 0;
        if (buffer != null) {
            *buffer = 0;
        }
    }

    fn free_builder() -> void {
        if (buffer != null) {
            free(buffer);
            buffer = null;
            length = 0;
            capacity = 0;
        }
    }
};
