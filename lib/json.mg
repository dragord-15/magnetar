// ============================================================================
// Magnetar Standard Library: JSON (lib/json.mg)
// General-purpose JSON builder, parser, validator and helpers.
// Pure Magnetar, no external deps beyond lib/string.mg.
// ============================================================================

use "lib/string.mg";

// -------------------------------------------------------------
// Internal: scanning helpers
// -------------------------------------------------------------

fn _json_is_ws(int c) -> bool {
    return c == 32 || c == 9 || c == 10 || c == 13;
}

fn _json_skip_ws(char* p, int n, int* i) -> void {
    while (*i < n && _json_is_ws(cast<int>(*(p + *i)) & 255)) {
        *i = *i + 1;
    }
}

fn _json_scan_string(char* p, int n, int i, int* end) -> bool {
    if (i < 0 || i >= n || (cast<int>(*(p + i)) & 255) != 34) { return false; }
    int pos = i + 1;
    while (pos < n) {
        int c = cast<int>(*(p + pos)) & 255;
        if (c == 92) {
            pos = pos + 2;
            if (pos > n) { return false; }
        } else if (c == 34) {
            *end = pos + 1;
            return true;
        } else {
            pos = pos + 1;
        }
    }
    return false;
}

fn _json_scan_container(char* p, int n, int* start, int* end) -> bool {
    if (*start < 0 || *start >= n) { return false; }
    int first = cast<int>(*(p + *start)) & 255;
    if (first != 123 && first != 91) { return false; }
    char* stack = alloc<char>(n + 1);
    if (stack == null) { return false; }
    int top = 0;
    int pos = *start;
    bool in_str = false;
    bool ok = false;
    while (pos < n) {
        int c = cast<int>(*(p + pos)) & 255;
        if (in_str) {
            if (c == 92) {
                pos = pos + 2;
                if (pos > n) { break; }
            } else if (c == 34) {
                in_str = false;
                pos = pos + 1;
            } else {
                pos = pos + 1;
            }
        } else if (c == 34) {
            in_str = true;
            pos = pos + 1;
        } else if (c == 123 || c == 91) {
            stack[top] = cast<char>(c);
            top = top + 1;
            pos = pos + 1;
        } else if (c == 125 || c == 93) {
            if (top <= 0) { break; }
            int open = cast<int>(stack[top - 1]) & 255;
            if ((c == 125 && open != 123) || (c == 93 && open != 91)) { break; }
            top = top - 1;
            pos = pos + 1;
            if (top == 0) {
                *end = pos;
                ok = true;
                break;
            }
        } else {
            pos = pos + 1;
        }
    }
    free(stack);
    return ok;
}

fn _json_scan_value(char* p, int n, int* start, int* end) -> bool {
    _json_skip_ws(p, n, start);
    if (*start >= n) { return false; }
    int c = cast<int>(*(p + *start)) & 255;
    if (c == 34) { return _json_scan_string(p, n, *start, end); }
    if (c == 123 || c == 91) { return _json_scan_container(p, n, start, end); }
    int pos = *start;
    while (pos < n) {
        int d = cast<int>(*(p + pos)) & 255;
        if (d == 44 || d == 125 || d == 93 || _json_is_ws(d)) { break; }
        pos = pos + 1;
    }
    if (pos == *start) { return false; }
    *end = pos;
    return true;
}

fn _json_slice(char* p, int start, int end) -> string {
    if (p == null || start < 0 || end < start) { return ""; }
    int count = end - start;
    char* buf = alloc<char>(count + 1);
    if (buf == null) { return ""; }
    for (int i = 0; i < count; i = i + 1) { *(buf + i) = *(p + start + i); }
    *(buf + count) = cast<char>(0);
    return cast<string>(buf);
}

fn _json_hex_val(int c) -> int {
    if (c >= 48 && c <= 57) { return c - 48; }
    if (c >= 65 && c <= 70) { return c - 55; }
    if (c >= 97 && c <= 102) { return c - 87; }
    return -1;
}

fn _json_hex_digit(int v) -> char {
    if (v < 10) { return cast<char>(48 + v); }
    return cast<char>(87 + v);
}

fn _json_append_utf8(char* out, int* pos, int cp) -> void {
    if (cp < 128) {
        out[*pos] = cast<char>(cp);
        *pos = *pos + 1;
    } else if (cp < 2048) {
        out[*pos] = cast<char>(192 | (cp >> 6));
        out[*pos + 1] = cast<char>(128 | (cp & 63));
        *pos = *pos + 2;
    } else {
        out[*pos] = cast<char>(224 | (cp >> 12));
        out[*pos + 1] = cast<char>(128 | ((cp >> 6) & 63));
        out[*pos + 2] = cast<char>(128 | (cp & 63));
        *pos = *pos + 3;
    }
}

fn _json_unescape(char* p, int start, int end) -> string {
    if (p == null || start < 0 || end < start) { return ""; }
    char* out = alloc<char>(end - start + 8);
    if (out == null) { return ""; }
    int k = 0;
    int i = start;
    while (i < end) {
        int c = cast<int>(*(p + i)) & 255;
        if (c == 92 && i + 1 < end) {
            int e = cast<int>(*(p + i + 1)) & 255;
            if (e == 34) { out[k] = cast<char>(34); k = k + 1; i = i + 2; }
            else if (e == 92) { out[k] = cast<char>(92); k = k + 1; i = i + 2; }
            else if (e == 47) { out[k] = cast<char>(47); k = k + 1; i = i + 2; }
            else if (e == 98) { out[k] = cast<char>(8); k = k + 1; i = i + 2; }
            else if (e == 102) { out[k] = cast<char>(12); k = k + 1; i = i + 2; }
            else if (e == 110) { out[k] = cast<char>(10); k = k + 1; i = i + 2; }
            else if (e == 114) { out[k] = cast<char>(13); k = k + 1; i = i + 2; }
            else if (e == 116) { out[k] = cast<char>(9); k = k + 1; i = i + 2; }
            else if (e == 117 && i + 5 < end) {
                int h1 = _json_hex_val(cast<int>(*(p + i + 2)) & 255);
                int h2 = _json_hex_val(cast<int>(*(p + i + 3)) & 255);
                int h3 = _json_hex_val(cast<int>(*(p + i + 4)) & 255);
                int h4 = _json_hex_val(cast<int>(*(p + i + 5)) & 255);
                if (h1 >= 0 && h2 >= 0 && h3 >= 0 && h4 >= 0) {
                    int cp = (h1 << 12) | (h2 << 8) | (h3 << 4) | h4;
                    _json_append_utf8(out, &k, cp);
                    i = i + 6;
                } else {
                    out[k] = cast<char>(c);
                    k = k + 1;
                    i = i + 1;
                }
            } else {
                out[k] = cast<char>(e);
                k = k + 1;
                i = i + 2;
            }
        } else {
            out[k] = cast<char>(c);
            k = k + 1;
            i = i + 1;
        }
    }
    out[k] = cast<char>(0);
    return cast<string>(out);
}

fn _json_trim(char* p, int* start, int* end) -> void {
    while (*start < *end && _json_is_ws(cast<int>(*(p + *start)) & 255)) { *start = *start + 1; }
    while (*end > *start && _json_is_ws(cast<int>(*(p + *end - 1)) & 255)) { *end = *end - 1; }
}

fn _json_field(string json, string key, int* start, int* end) -> bool {
    if (json == null || key == null || start == null || end == null) { return false; }
    string q1 = str_concat("\"", key);
    string quoted = str_concat(q1, "\"");
    free(cast<char*>(q1));
    int at = str_index_of(json, quoted);
    free(cast<char*>(quoted));
    if (at < 0) { return false; }
    char* p = cast<char*>(json);
    int n = len(json);
    int pos = at + len(key) + 2;
    _json_skip_ws(p, n, &pos);
    if (pos >= n || (cast<int>(*(p + pos)) & 255) != 58) { return false; }
    pos = pos + 1;
    *start = pos;
    return _json_scan_value(p, n, &pos, end);
}

// -------------------------------------------------------------
// Public: escaping & string quoting
// -------------------------------------------------------------

fn json_escape(string s) -> string {
    if (s == null) { return ""; }
    char* p = cast<char*>(s);
    int n = len(s);
    char* out = alloc<char>(n * 6 + 1);
    if (out == null) { return ""; }
    int k = 0;
    for (int i = 0; i < n; i = i + 1) {
        int c = cast<int>(*(p + i)) & 255;
        if (c == 34) {
            out[k] = cast<char>(92); out[k + 1] = cast<char>(34); k = k + 2;
        } else if (c == 92) {
            out[k] = cast<char>(92); out[k + 1] = cast<char>(92); k = k + 2;
        } else if (c == 10) {
            out[k] = cast<char>(92); out[k + 1] = cast<char>(110); k = k + 2;
        } else if (c == 13) {
            out[k] = cast<char>(92); out[k + 1] = cast<char>(114); k = k + 2;
        } else if (c == 9) {
            out[k] = cast<char>(92); out[k + 1] = cast<char>(116); k = k + 2;
        } else if (c == 8) {
            out[k] = cast<char>(92); out[k + 1] = cast<char>(98); k = k + 2;
        } else if (c == 12) {
            out[k] = cast<char>(92); out[k + 1] = cast<char>(102); k = k + 2;
        } else if (c < 32) {
            out[k] = cast<char>(92); out[k + 1] = cast<char>(117);
            out[k + 2] = cast<char>(48); out[k + 3] = cast<char>(48);
            out[k + 4] = _json_hex_digit(c >> 4);
            out[k + 5] = _json_hex_digit(c & 15);
            k = k + 6;
        } else {
            out[k] = cast<char>(c);
            k = k + 1;
        }
    }
    out[k] = cast<char>(0);
    return cast<string>(out);
}

fn json_quote(string s) -> string {
    string esc = json_escape(s);
    string q1 = str_concat("\"", esc);
    string out = str_concat(q1, "\"");
    free(cast<char*>(q1));
    return out;
}

// -------------------------------------------------------------
// Public: getters
// -------------------------------------------------------------

fn json_get_string(string json, string key, string fallback) -> string {
    int st = 0;
    int en = 0;
    if (!_json_field(json, key, &st, &en)) { return fallback; }
    char* p = cast<char*>(json);
    _json_trim(p, &st, &en);
    if (en - st >= 2 && (cast<int>(*(p + st)) & 255) == 34 && (cast<int>(*(p + en - 1)) & 255) == 34) {
        return _json_unescape(p, st + 1, en - 1);
    }
    return _json_slice(p, st, en);
}

fn json_get_int(string json, string key, int fallback) -> int {
    int st = 0;
    int en = 0;
    if (!_json_field(json, key, &st, &en)) { return fallback; }
    char* p = cast<char*>(json);
    _json_trim(p, &st, &en);
    if (en - st >= 2 && (cast<int>(*(p + st)) & 255) == 34 && (cast<int>(*(p + en - 1)) & 255) == 34) {
        st = st + 1;
        en = en - 1;
    }
    string tok = _json_slice(p, st, en);
    int value = str_to_int(tok);
    free(cast<char*>(tok));
    return value;
}

fn json_get_bool(string json, string key, bool fallback) -> bool {
    int st = 0;
    int en = 0;
    if (!_json_field(json, key, &st, &en)) { return fallback; }
    char* p = cast<char*>(json);
    _json_trim(p, &st, &en);
    if (en - st >= 2 && (cast<int>(*(p + st)) & 255) == 34 && (cast<int>(*(p + en - 1)) & 255) == 34) {
        st = st + 1;
        en = en - 1;
    }
    string tok = _json_slice(p, st, en);
    bool value = fallback;
    if (tok == "true") { value = true; }
    if (tok == "false") { value = false; }
    free(cast<char*>(tok));
    return value;
}

fn json_get_raw(string json, string key) -> string {
    int st = 0;
    int en = 0;
    if (!_json_field(json, key, &st, &en)) { return ""; }
    char* p = cast<char*>(json);
    _json_trim(p, &st, &en);
    return _json_slice(p, st, en);
}

fn json_has_key(string json, string key) -> bool {
    int st = 0;
    int en = 0;
    return _json_field(json, key, &st, &en);
}

// -------------------------------------------------------------
// Public: array helpers
// -------------------------------------------------------------

fn _json_array_bounds(char* p, int n, int* start, int* end) -> void {
    *start = 0;
    *end = n;
    _json_skip_ws(p, n, start);
    if (*start < n && (cast<int>(*(p + *start)) & 255) == 91) {
        int tmp = *start;
        int stop = n;
        if (_json_scan_container(p, n, &tmp, &stop)) {
            *start = tmp + 1;
            *end = stop - 1;
            return;
        }
    }
    *start = 0;
    *end = n;
    _json_trim(p, start, end);
}

fn json_array_count(string arr_text) -> int {
    if (arr_text == null) { return 0; }
    char* p = cast<char*>(arr_text);
    int n = len(arr_text);
    int st = 0;
    int en = 0;
    _json_array_bounds(p, n, &st, &en);
    char* stack = alloc<char>(en - st + 1);
    if (stack == null) { return 0; }
    int top = 0;
    int i = st;
    int tokens = 1;
    bool seen = false;
    bool in_str = false;
    while (i < en) {
        int c = cast<int>(*(p + i)) & 255;
        if (in_str) {
            if (c == 92) { i = i + 2; }
            else if (c == 34) { in_str = false; i = i + 1; }
            else { i = i + 1; }
        } else if (c == 34) {
            seen = true;
            in_str = true;
            i = i + 1;
        } else if (c == 123 || c == 91) {
            seen = true;
            stack[top] = cast<char>(c);
            top = top + 1;
            i = i + 1;
        } else if (c == 125 || c == 93) {
            if (top > 0) { top = top - 1; }
            i = i + 1;
        } else if (c == 44 && top == 0) {
            tokens = tokens + 1;
            i = i + 1;
        } else {
            if (!_json_is_ws(c)) { seen = true; }
            i = i + 1;
        }
        if (i > en) { i = en; }
    }
    free(stack);
    if (!seen) { return 0; }
    return tokens;
}

fn json_array_get(string arr_text, int index) -> string {
    if (arr_text == null || index < 0) { return ""; }
    char* p = cast<char*>(arr_text);
    int n = len(arr_text);
    int st = 0;
    int en = 0;
    _json_array_bounds(p, n, &st, &en);
    char* stack = alloc<char>(en - st + 1);
    if (stack == null) { return ""; }
    int top = 0;
    int i = st;
    int tok_start = st;
    int found = 0;
    int item_start = 0;
    int item_end = 0;
    bool in_str = false;
    while (i < en) {
        int c = cast<int>(*(p + i)) & 255;
        if (in_str) {
            if (c == 92) { i = i + 2; }
            else if (c == 34) { in_str = false; i = i + 1; }
            else { i = i + 1; }
        } else if (c == 34) {
            in_str = true;
            i = i + 1;
        } else if (c == 123 || c == 91) {
            stack[top] = cast<char>(c);
            top = top + 1;
            i = i + 1;
        } else if (c == 125 || c == 93) {
            if (top > 0) { top = top - 1; }
            i = i + 1;
        } else if (c == 44 && top == 0) {
            if (found == index) { item_start = tok_start; item_end = i; }
            found = found + 1;
            tok_start = i + 1;
            i = i + 1;
        } else {
            i = i + 1;
        }
        if (i > en) { i = en; }
    }
    if (found == index) { item_start = tok_start; item_end = en; }
    free(stack);
    _json_trim(p, &item_start, &item_end);
    if (item_start >= item_end) { return ""; }
    if ((cast<int>(*(p + item_start)) & 255) == 34 && (cast<int>(*(p + item_end - 1)) & 255) == 34) {
        return _json_unescape(p, item_start + 1, item_end - 1);
    }
    return _json_slice(p, item_start, item_end);
}

fn json_array_get_raw(string arr_text, int index) -> string {
    if (arr_text == null || index < 0) { return ""; }
    char* p = cast<char*>(arr_text);
    int n = len(arr_text);
    int st = 0;
    int en = 0;
    _json_array_bounds(p, n, &st, &en);
    char* stack = alloc<char>(en - st + 1);
    if (stack == null) { return ""; }
    int top = 0;
    int i = st;
    int tok_start = st;
    int found = 0;
    int item_start = 0;
    int item_end = 0;
    bool in_str = false;
    while (i < en) {
        int c = cast<int>(*(p + i)) & 255;
        if (in_str) {
            if (c == 92) { i = i + 2; }
            else if (c == 34) { in_str = false; i = i + 1; }
            else { i = i + 1; }
        } else if (c == 34) {
            in_str = true;
            i = i + 1;
        } else if (c == 123 || c == 91) {
            stack[top] = cast<char>(c);
            top = top + 1;
            i = i + 1;
        } else if (c == 125 || c == 93) {
            if (top > 0) { top = top - 1; }
            i = i + 1;
        } else if (c == 44 && top == 0) {
            if (found == index) { item_start = tok_start; item_end = i; }
            found = found + 1;
            tok_start = i + 1;
            i = i + 1;
        } else {
            i = i + 1;
        }
        if (i > en) { i = en; }
    }
    if (found == index) { item_start = tok_start; item_end = en; }
    free(stack);
    _json_trim(p, &item_start, &item_end);
    if (item_start >= item_end) { return ""; }
    return _json_slice(p, item_start, item_end);
}

// -------------------------------------------------------------
// Public: validation
// -------------------------------------------------------------

fn json_is_valid(string json) -> bool {
    if (json == null) { return false; }
    char* p = cast<char*>(json);
    int n = len(json);
    if (n <= 0) { return false; }
    char* stack = alloc<char>(n + 1);
    if (stack == null) { return false; }
    int top = 0;
    int i = 0;
    bool in_str = false;
    bool ok = true;
    while (i < n) {
        int c = cast<int>(*(p + i)) & 255;
        if (in_str) {
            if (c == 92) {
                if (i + 1 >= n) { ok = false; break; }
                i = i + 2;
            } else if (c == 34) {
                in_str = false;
                i = i + 1;
            } else {
                i = i + 1;
            }
        } else if (c == 34) {
            in_str = true;
            i = i + 1;
        } else if (c == 123 || c == 91) {
            stack[top] = cast<char>(c);
            top = top + 1;
            i = i + 1;
        } else if (c == 125 || c == 93) {
            if (top <= 0) { ok = false; break; }
            int open = cast<int>(stack[top - 1]) & 255;
            if ((c == 125 && open != 123) || (c == 93 && open != 91)) { ok = false; break; }
            top = top - 1;
            i = i + 1;
        } else {
            i = i + 1;
        }
    }
    free(stack);
    return ok && !in_str && top == 0;
}

// -------------------------------------------------------------
// Public: simple builders
// -------------------------------------------------------------

fn json_object_begin() -> string { return "{"; }

fn json_object_end(string obj) -> string {
    if (obj == null) { return "{}"; }
    int n = len(obj);
    if (n <= 0) { return "{}"; }
    char* p = cast<char*>(obj);
    int last = cast<int>(*(p + n - 1)) & 255;
    if (last == 44) {
        char* out = alloc<char>(n + 1);
        if (out == null) { return str_concat(obj, "}"); }
        for (int i = 0; i < n - 1; i = i + 1) { *(out + i) = *(p + i); }
        *(out + n - 1) = 125;
        *(out + n) = cast<char>(0);
        return cast<string>(out);
    }
    return str_concat(obj, "}");
}

fn json_array_begin() -> string { return "["; }

fn json_array_end(string arr) -> string {
    if (arr == null) { return "[]"; }
    int n = len(arr);
    if (n <= 0) { return "[]"; }
    char* p = cast<char*>(arr);
    int last = cast<int>(*(p + n - 1)) & 255;
    if (last == 44) {
        char* out = alloc<char>(n + 1);
        if (out == null) { return str_concat(arr, "]"); }
        for (int i = 0; i < n - 1; i = i + 1) { *(out + i) = *(p + i); }
        *(out + n - 1) = 93;
        *(out + n) = cast<char>(0);
        return cast<string>(out);
    }
    return str_concat(arr, "]");
}

fn json__obj_prefix(string obj) -> string {
    if (obj == null || len(obj) == 0) { return "{"; }
    char* p = cast<char*>(obj);
    int n = len(obj);
    int last = cast<int>(*(p + n - 1)) & 255;
    if (last == 123) { return obj; }
    return str_concat(obj, ",");
}

fn json__arr_prefix(string arr) -> string {
    if (arr == null || len(arr) == 0) { return "["; }
    char* p = cast<char*>(arr);
    int n = len(arr);
    int last = cast<int>(*(p + n - 1)) & 255;
    if (last == 91) { return arr; }
    return str_concat(arr, ",");
}

fn json_object_set_str(string obj, string key, string value) -> string {
    string base = json__obj_prefix(obj);
    string k = json_quote(key);
    string v = json_quote(value);
    string a = str_concat(base, k);
    string b = str_concat(a, ":");
    string c = str_concat(b, v);
    string out = str_concat(c, ",");
    if (base != obj) { free(cast<char*>(base)); }
    free(cast<char*>(k));
    free(cast<char*>(v));
    free(cast<char*>(a));
    free(cast<char*>(b));
    free(cast<char*>(c));
    return out;
}

fn json_object_set_int(string obj, string key, int value) -> string {
    string base = json__obj_prefix(obj);
    string k = json_quote(key);
    string vs = int_to_str(value);
    string a = str_concat(base, k);
    string b = str_concat(a, ":");
    string c = str_concat(b, vs);
    string out = str_concat(c, ",");
    if (base != obj) { free(cast<char*>(base)); }
    free(cast<char*>(k));
    free(cast<char*>(vs));
    free(cast<char*>(a));
    free(cast<char*>(b));
    free(cast<char*>(c));
    return out;
}

fn json_object_set_bool(string obj, string key, bool value) -> string {
    string base = json__obj_prefix(obj);
    string k = json_quote(key);
    string a = str_concat(base, k);
    string b = str_concat(a, ":");
    string c;
    if (value) { c = str_concat(b, "true"); }
    else { c = str_concat(b, "false"); }
    string out = str_concat(c, ",");
    if (base != obj) { free(cast<char*>(base)); }
    free(cast<char*>(k));
    free(cast<char*>(a));
    free(cast<char*>(b));
    free(cast<char*>(c));
    return out;
}

fn json_object_set_raw(string obj, string key, string raw_json) -> string {
    string base = json__obj_prefix(obj);
    string k = json_quote(key);
    string a = str_concat(base, k);
    string b = str_concat(a, ":");
    string c = str_concat(b, raw_json);
    string out = str_concat(c, ",");
    if (base != obj) { free(cast<char*>(base)); }
    free(cast<char*>(k));
    free(cast<char*>(a));
    free(cast<char*>(b));
    free(cast<char*>(c));
    return out;
}

fn json_array_push_str(string arr, string value) -> string {
    string base = json__arr_prefix(arr);
    string v = json_quote(value);
    string a = str_concat(base, v);
    string out = str_concat(a, ",");
    if (base != arr) { free(cast<char*>(base)); }
    free(cast<char*>(v));
    free(cast<char*>(a));
    return out;
}

fn json_array_push_int(string arr, int value) -> string {
    string base = json__arr_prefix(arr);
    string vs = int_to_str(value);
    string a = str_concat(base, vs);
    string out = str_concat(a, ",");
    if (base != arr) { free(cast<char*>(base)); }
    free(cast<char*>(vs));
    free(cast<char*>(a));
    return out;
}

fn json_array_push_bool(string arr, bool value) -> string {
    string base = json__arr_prefix(arr);
    string a;
    if (value) { a = str_concat(base, "true"); }
    else { a = str_concat(base, "false"); }
    string out = str_concat(a, ",");
    if (base != arr) { free(cast<char*>(base)); }
    free(cast<char*>(a));
    return out;
}

fn json_array_push_raw(string arr, string raw_json) -> string {
    string base = json__arr_prefix(arr);
    string a = str_concat(base, raw_json);
    string out = str_concat(a, ",");
    if (base != arr) { free(cast<char*>(base)); }
    free(cast<char*>(a));
    return out;
}

// -------------------------------------------------------------
// Public: JSON-RPC / convenience
// -------------------------------------------------------------

fn json_rpc_result(int id, string result_json) -> string {
    string head = "{\"jsonrpc\":\"2.0\",\"result\":";
    string tail1 = str_concat(",\"id\":", int_to_str(id));
    string mid = str_concat(head, result_json);
    string tail = str_concat(tail1, "}");
    string out = str_concat(mid, tail);
    free(cast<char*>(mid));
    free(cast<char*>(tail1));
    free(cast<char*>(tail));
    return out;
}

fn json_rpc_error(int id, int code, string message) -> string {
    string head = "{\"jsonrpc\":\"2.0\",\"error\":{\"code\":";
    string cpart = str_concat(head, int_to_str(code));
    string mpart = str_concat(",\"message\":", json_quote(message));
    string body = str_concat(cpart, mpart);
    string tail = str_concat("},\"id\":", int_to_str(id));
    string mid = str_concat(body, tail);
    string out = str_concat(mid, "}");
    free(cast<char*>(cpart));
    free(cast<char*>(mpart));
    free(cast<char*>(body));
    free(cast<char*>(tail));
    free(cast<char*>(mid));
    return out;
}

// Backward-compatible aliases for coin/lib/json.mg users
fn mgc_json_escape(string s) -> string { return json_escape(s); }
fn mgc_json_string(string s) -> string { return json_quote(s); }
fn mgc_json_get_string(string json, string key, string fallback) -> string { return json_get_string(json, key, fallback); }
fn mgc_json_get_int(string json, string key, int fallback) -> int { return json_get_int(json, key, fallback); }
fn mgc_json_get_bool(string json, string key, bool fallback) -> bool { return json_get_bool(json, key, fallback); }
fn mgc_json_get_params(string json) -> string { return json_get_raw(json, "params"); }
fn mgc_json_array_count(string arr_text) -> int { return json_array_count(arr_text); }
fn mgc_json_array_item(string arr_text, int index) -> string { return json_array_get(arr_text, index); }
fn mgc_json_result(int id, string result_json) -> string { return json_rpc_result(id, result_json); }
fn mgc_json_error(int id, int code, string message) -> string { return json_rpc_error(id, code, message); }
fn mgc_json_valid(string json) -> bool { return json_is_valid(json); }
