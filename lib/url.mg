// ============================================================================
// Magnetar Standard Library: URL / URI Toolkit (lib/url.mg)
// RFC 3986 oriented parser, percent codecs, query strings, and URL joining.
//
// Supported URL families:
//   http, https, ws, wss, ftp, ftps, sftp, ssh, scp,
//   smtp, smtps, imap, imaps, pop3, pop3s, dns, ldap, ldaps,
//   mqtt, mqtts, amqp, amqps, redis, rediss, postgres, postgresql,
//   mysql, mongodb, mongodb+srv, telnet, tftp, gopher, file, data,
//   socks4, socks4a, socks5, socks5h, tor
// ============================================================================

use "lib/string.mg";
use "lib/crypto.mg";

struct Url {
    string scheme;    // "http", "https", "ftp", ...
    string userinfo;  // "user:pass" (raw, still percent-encoded)
    string username;
    string password;
    string host;      // "example.com" or IPv6 address without brackets
    int port;         // effective port (explicit or scheme default)
    string path;      // "/api/v1"
    string query;     // "a=1&b=2" (without '?')
    string fragment;  // "section" (without '#')
    bool valid;
    bool has_port;    // an explicit :port was present
    bool is_ipv6;     // host was written as [::1]
    bool secure;      // scheme uses TLS by default
};

struct QueryParams {
    string keys[64];
    string values[64];
    int count;
};

// -------------------------------------------------------------
// Small internal helpers
// -------------------------------------------------------------

fn _url_slice(char* src, int start, int end) -> string {
    int length = end - start;
    if (length <= 0) {
        return "";
    }
    char* buf = alloc<char>(length + 1);
    for (int i = 0; i < length; i = i + 1) {
        *(buf + i) = *(src + start + i);
    }
    *(buf + length) = 0;
    return cast<string>(buf);
}

fn _url_byte(char* p, int index) -> int {
    return cast<int>(*(p + index)) & 255;
}

fn _url_is_alpha(int c) -> bool {
    return (c >= 65 && c <= 90) || (c >= 97 && c <= 122);
}

fn _url_is_digit(int c) -> bool {
    return c >= 48 && c <= 57;
}

fn _url_is_hex(int c) -> bool {
    return _url_is_digit(c) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102);
}

fn _url_hex_value(int c) -> int {
    if (c >= 48 && c <= 57) { return c - 48; }
    if (c >= 65 && c <= 70) { return c - 55; }
    if (c >= 97 && c <= 102) { return c - 87; }
    return -1;
}

fn _url_hex_digit(int value, bool upper) -> char {
    int v = value & 15;
    if (v < 10) {
        return cast<char>(48 + v);
    }
    if (upper) {
        return cast<char>(65 + (v - 10));
    }
    return cast<char>(97 + (v - 10));
}

fn _url_is_unreserved(int c) -> bool {
    if (_url_is_alpha(c) || _url_is_digit(c)) { return true; }
    return c == 45 || c == 46 || c == 95 || c == 126; // - . _ ~
}

// -------------------------------------------------------------
// Schemes and default ports
// -------------------------------------------------------------

fn url_default_port(string scheme) -> int {
    if (scheme == "http" || scheme == "ws") { return 80; }
    if (scheme == "https" || scheme == "wss") { return 443; }
    if (scheme == "ftp") { return 21; }
    if (scheme == "ftps") { return 990; }
    if (scheme == "sftp" || scheme == "ssh" || scheme == "scp") { return 22; }
    if (scheme == "smtp") { return 25; }
    if (scheme == "smtps") { return 465; }
    if (scheme == "imap") { return 143; }
    if (scheme == "imaps") { return 993; }
    if (scheme == "pop3") { return 110; }
    if (scheme == "pop3s") { return 995; }
    if (scheme == "dns") { return 53; }
    if (scheme == "ldap") { return 389; }
    if (scheme == "ldaps") { return 636; }
    if (scheme == "mqtt") { return 1883; }
    if (scheme == "mqtts") { return 8883; }
    if (scheme == "amqp") { return 5672; }
    if (scheme == "amqps") { return 5671; }
    if (scheme == "redis") { return 6379; }
    if (scheme == "rediss") { return 6380; }
    if (scheme == "postgres" || scheme == "postgresql") { return 5432; }
    if (scheme == "mysql") { return 3306; }
    if (scheme == "mongodb") { return 27017; }
    if (scheme == "mongodb+srv") { return 27017; }
    if (scheme == "telnet") { return 23; }
    if (scheme == "tftp") { return 69; }
    if (scheme == "gopher") { return 70; }
    if (scheme == "socks4" || scheme == "socks4a" || scheme == "socks5" || scheme == "socks5h") { return 1080; }
    if (scheme == "tor") { return 9050; }
    return 80;
}

fn url_is_secure_scheme(string scheme) -> bool {
    if (scheme == "https" || scheme == "wss") { return true; }
    if (scheme == "ftps" || scheme == "sftp" || scheme == "ssh" || scheme == "scp") { return true; }
    if (scheme == "smtps" || scheme == "imaps" || scheme == "pop3s") { return true; }
    if (scheme == "ldaps" || scheme == "mqtts" || scheme == "amqps") { return true; }
    if (scheme == "rediss" || scheme == "mongodb+srv" || scheme == "postgresql") { return false; }
    return false;
}

fn url_scheme_known(string scheme) -> bool {
    if (scheme == "http" || scheme == "https" || scheme == "ws" || scheme == "wss") { return true; }
    if (scheme == "ftp" || scheme == "ftps" || scheme == "sftp" || scheme == "ssh" || scheme == "scp") { return true; }
    if (scheme == "smtp" || scheme == "smtps" || scheme == "imap" || scheme == "imaps") { return true; }
    if (scheme == "pop3" || scheme == "pop3s" || scheme == "dns" || scheme == "ldap" || scheme == "ldaps") { return true; }
    if (scheme == "mqtt" || scheme == "mqtts" || scheme == "amqp" || scheme == "amqps") { return true; }
    if (scheme == "redis" || scheme == "rediss" || scheme == "postgres" || scheme == "postgresql") { return true; }
    if (scheme == "mysql" || scheme == "mongodb" || scheme == "mongodb+srv") { return true; }
    if (scheme == "telnet" || scheme == "tftp" || scheme == "gopher" || scheme == "file" || scheme == "data") { return true; }
    if (scheme == "socks4" || scheme == "socks4a" || scheme == "socks5" || scheme == "socks5h" || scheme == "tor") { return true; }
    return false;
}

fn url_scheme_from_port(int port) -> string {
    if (port == 80) { return "http"; }
    if (port == 443) { return "https"; }
    if (port == 21) { return "ftp"; }
    if (port == 22) { return "ssh"; }
    if (port == 25) { return "smtp"; }
    if (port == 465) { return "smtps"; }
    if (port == 143) { return "imap"; }
    if (port == 993) { return "imaps"; }
    if (port == 110) { return "pop3"; }
    if (port == 995) { return "pop3s"; }
    if (port == 53) { return "dns"; }
    if (port == 389) { return "ldap"; }
    if (port == 636) { return "ldaps"; }
    if (port == 1883) { return "mqtt"; }
    if (port == 8883) { return "mqtts"; }
    if (port == 5672) { return "amqp"; }
    if (port == 5671) { return "amqps"; }
    if (port == 6379) { return "redis"; }
    if (port == 5432) { return "postgres"; }
    if (port == 3306) { return "mysql"; }
    if (port == 27017) { return "mongodb"; }
    if (port == 1080) { return "socks5"; }
    return "";
}

// -------------------------------------------------------------
// Parser
// -------------------------------------------------------------

fn url_init_defaults() -> Url {
    Url u;
    u.scheme = "http";
    u.userinfo = "";
    u.username = "";
    u.password = "";
    u.host = "";
    u.port = 80;
    u.path = "/";
    u.query = "";
    u.fragment = "";
    u.valid = false;
    u.has_port = false;
    u.is_ipv6 = false;
    u.secure = false;
    return u;
}

fn url_parse(string raw_url) -> Url {
    Url u = url_init_defaults();
    if (raw_url == null) {
        return u;
    }
    int total = len(raw_url);
    if (total == 0) {
        return u;
    }
    char* p = cast<char*>(raw_url);
    int cursor = 0;
    int scheme_end = -1;

    // Scheme: ALPHA *( ALPHA / DIGIT / "+" / "-" / "." ) ":"
    for (int i = 0; i < total; i = i + 1) {
        int c = _url_byte(p, i);
        if (c == 58) { // ':'
            if (i > 0) {
                bool ok = _url_is_alpha(_url_byte(p, 0));
                for (int j = 1; j < i; j = j + 1) {
                    int x = _url_byte(p, j);
                    if (!(_url_is_alpha(x) || _url_is_digit(x) || x == 43 || x == 45 || x == 46)) {
                        ok = false;
                    }
                }
                if (ok) { scheme_end = i; }
            }
            break;
        }
        if (c == 47 || c == 63 || c == 35) { // '/' '?' '#'
            break;
        }
    }

    if (scheme_end > 0) {
        u.scheme = str_to_lower(_url_slice(p, 0, scheme_end));
        cursor = scheme_end + 1;
        if (cursor + 1 < total) {
            if (_url_byte(p, cursor) == 47 && _url_byte(p, cursor + 1) == 47) {
                cursor = cursor + 2;
            }
        }
    }

    u.port = url_default_port(u.scheme);
    u.secure = url_is_secure_scheme(u.scheme);

    // Fragment
    int fragment_start = -1;
    for (int i = cursor; i < total; i = i + 1) {
        if (_url_byte(p, i) == 35) { // '#'
            fragment_start = i;
            break;
        }
    }
    int end_before_fragment = total;
    if (fragment_start >= 0) {
        end_before_fragment = fragment_start;
        u.fragment = _url_slice(p, fragment_start + 1, total);
    }

    // Query
    int query_start = -1;
    for (int i = cursor; i < end_before_fragment; i = i + 1) {
        if (_url_byte(p, i) == 63) { // '?'
            query_start = i;
            break;
        }
    }
    int authority_end = end_before_fragment;
    if (query_start >= 0) {
        authority_end = query_start;
        u.query = _url_slice(p, query_start + 1, end_before_fragment);
    }

    // Authority ends at the first '/' (path separator)
    for (int i = cursor; i < authority_end; i = i + 1) {
        if (_url_byte(p, i) == 47) {
            authority_end = i;
            break;
        }
    }

    // Path (ends where the query starts, if any)
    int path_end = end_before_fragment;
    if (query_start >= 0) { path_end = query_start; }
    if (authority_end < path_end) {
        u.path = _url_slice(p, authority_end, path_end);
    }
    if (len(u.path) == 0) {
        u.path = "/";
    }

    // Userinfo (last '@' in authority)
    int at = -1;
    for (int i = cursor; i < authority_end; i = i + 1) {
        if (_url_byte(p, i) == 64) { at = i; }
    }
    int host_start = cursor;
    if (at >= 0) {
        u.userinfo = _url_slice(p, cursor, at);
        host_start = at + 1;
        int colon = -1;
        char* up = cast<char*>(u.userinfo);
        for (int i = 0; i < len(u.userinfo); i = i + 1) {
            if (_url_byte(up, i) == 58) { colon = i; break; }
        }
        if (colon >= 0) {
            u.username = _url_slice(up, 0, colon);
            u.password = _url_slice(up, colon + 1, len(u.userinfo));
        } else {
            u.username = u.userinfo;
        }
    }

    if (host_start >= authority_end) {
        u.host = "";
    } else if (_url_byte(p, host_start) == 91) { // '['
        int close = -1;
        for (int i = host_start + 1; i < authority_end; i = i + 1) {
            if (_url_byte(p, i) == 93) { close = i; break; }
        }
        if (close < 0) {
            return u;
        }
        u.is_ipv6 = true;
        u.host = _url_slice(p, host_start + 1, close);
        if (close + 1 < authority_end && _url_byte(p, close + 1) == 58) {
            u.has_port = true;
            int parsed = str_to_int(_url_slice(p, close + 2, authority_end));
            if (parsed > 0 && parsed <= 65535) { u.port = parsed; }
        }
    } else {
        int colon = -1;
        for (int i = host_start; i < authority_end; i = i + 1) {
            if (_url_byte(p, i) == 58) { colon = i; break; }
        }
        if (colon >= 0) {
            u.host = _url_slice(p, host_start, colon);
            u.has_port = true;
            int parsed = str_to_int(_url_slice(p, colon + 1, authority_end));
            if (parsed > 0 && parsed <= 65535) { u.port = parsed; }
        } else {
            u.host = _url_slice(p, host_start, authority_end);
        }
    }

    if (len(u.host) == 0 && !(u.scheme == "file" || u.scheme == "data")) {
        return u;
    }
    u.valid = true;
    return u;
}

fn url_is_valid(string raw_url) -> bool {
    Url u = url_parse(raw_url);
    return u.valid;
}

fn url_has_scheme(string raw_url) -> bool {
    if (raw_url == null) { return false; }
    int total = len(raw_url);
    char* p = cast<char*>(raw_url);
    for (int i = 0; i < total; i = i + 1) {
        int c = _url_byte(p, i);
        if (c == 58) { return i > 0; }
        if (c == 47 || c == 63 || c == 35) { return false; }
    }
    return false;
}

fn url_is_ipv4_host(string host) -> bool {
    if (host == null || len(host) == 0) { return false; }
    char* p = cast<char*>(host);
    int part = 0;
    int digits = 0;
    int value = 0;
    for (int i = 0; i < len(host); i = i + 1) {
        int c = _url_byte(p, i);
        if (c >= 48 && c <= 57) {
            value = value * 10 + (c - 48);
            digits = digits + 1;
            if (value > 255) { return false; }
        } else if (c == 46) {
            if (digits == 0 || part >= 3) { return false; }
            part = part + 1;
            digits = 0;
            value = 0;
        } else {
            return false;
        }
    }
    return part == 3 && digits > 0;
}

fn url_is_ipv6_host(string host) -> bool {
    if (host == null) { return false; }
    char* p = cast<char*>(host);
    bool has_colon = false;
    for (int i = 0; i < len(host); i = i + 1) {
        int c = _url_byte(p, i);
        if (c == 58) { has_colon = true; }
        else if (!_url_is_hex(c)) { return false; }
    }
    return has_colon;
}

// -------------------------------------------------------------
// Percent encoding / decoding
// -------------------------------------------------------------

fn url_percent_encode(string text, string safe_chars) -> string {
    if (text == null) { return ""; }
    int n = len(text);
    char* p = cast<char*>(text);
    char* safe = cast<char*>(safe_chars);
    int safe_len = len(safe_chars);
    char* out = alloc<char>(n * 3 + 1);
    int pos = 0;
    for (int i = 0; i < n; i = i + 1) {
        int c = _url_byte(p, i);
        bool keep = _url_is_unreserved(c);
        for (int j = 0; j < safe_len; j = j + 1) {
            if (c == _url_byte(safe, j)) { keep = true; }
        }
        if (keep) {
            *(out + pos) = cast<char>(c);
            pos = pos + 1;
        } else {
            *(out + pos) = '%'; pos = pos + 1;
            *(out + pos) = _url_hex_digit(c >> 4, true); pos = pos + 1;
            *(out + pos) = _url_hex_digit(c, true); pos = pos + 1;
        }
    }
    *(out + pos) = 0;
    return cast<string>(out);
}

fn url_encode(string text) -> string {
    return url_percent_encode(text, "");
}

fn url_encode_path(string text) -> string {
    return url_percent_encode(text, "/:@!$&'()*+,;=");
}

fn url_encode_query_component(string text) -> string {
    return url_percent_encode(text, "");
}

fn url_encode_form_component(string text) -> string {
    if (text == null) { return ""; }
    int n = len(text);
    char* p = cast<char*>(text);
    char* out = alloc<char>(n * 3 + 1);
    int pos = 0;
    for (int i = 0; i < n; i = i + 1) {
        int c = _url_byte(p, i);
        if (c == 32) {
            *(out + pos) = '+';
            pos = pos + 1;
        } else if (_url_is_unreserved(c)) {
            *(out + pos) = cast<char>(c);
            pos = pos + 1;
        } else {
            *(out + pos) = '%'; pos = pos + 1;
            *(out + pos) = _url_hex_digit(c >> 4, true); pos = pos + 1;
            *(out + pos) = _url_hex_digit(c, true); pos = pos + 1;
        }
    }
    *(out + pos) = 0;
    return cast<string>(out);
}

fn url_percent_decode(string text, bool plus_as_space) -> string {
    if (text == null) { return ""; }
    int n = len(text);
    char* p = cast<char*>(text);
    char* out = alloc<char>(n + 1);
    int pos = 0;
    for (int i = 0; i < n; i = i + 1) {
        int c = _url_byte(p, i);
        if (c == 37 && i + 2 < n) { // '%'
            int h1 = _url_hex_value(_url_byte(p, i + 1));
            int h2 = _url_hex_value(_url_byte(p, i + 2));
            if (h1 >= 0 && h2 >= 0) {
                *(out + pos) = cast<char>((h1 << 4) | h2);
                pos = pos + 1;
                i = i + 2;
                continue;
            }
        }
        if (c == 43 && plus_as_space) {
            *(out + pos) = ' ';
        } else {
            *(out + pos) = cast<char>(c);
        }
        pos = pos + 1;
    }
    *(out + pos) = 0;
    return cast<string>(out);
}

fn url_decode(string text) -> string {
    return url_percent_decode(text, true);
}

fn url_decode_strict(string text) -> string {
    return url_percent_decode(text, false);
}

// -------------------------------------------------------------
// Query parameters
// -------------------------------------------------------------

fn url_query_params() -> QueryParams {
    QueryParams q;
    q.count = 0;
    for (int i = 0; i < 64; i = i + 1) {
        q.keys[i] = "";
        q.values[i] = "";
    }
    return q;
}

fn query_params_set(QueryParams q, string key, string value) -> void {
    for (int i = 0; i < q.count; i = i + 1) {
        if (q.keys[i] == key) {
            q.values[i] = value;
            return;
        }
    }
    if (q.count >= 64) { return; }
    q.keys[q.count] = key;
    q.values[q.count] = value;
    q.count = q.count + 1;
}

fn query_params_add(QueryParams q, string key, string value) -> void {
    if (q.count >= 64) { return; }
    q.keys[q.count] = key;
    q.values[q.count] = value;
    q.count = q.count + 1;
}

fn query_params_get(QueryParams q, string key) -> string {
    for (int i = 0; i < q.count; i = i + 1) {
        if (q.keys[i] == key) {
            return q.values[i];
        }
    }
    return "";
}

fn query_params_has(QueryParams q, string key) -> bool {
    for (int i = 0; i < q.count; i = i + 1) {
        if (q.keys[i] == key) { return true; }
    }
    return false;
}

// Initializes an existing QueryParams in place. Use this together with
// url_query_parse_into() when you need reliable multi-key parsing.
fn url_query_params_clear(QueryParams q) -> void {
    q.count = 0;
    for (int i = 0; i < 64; i = i + 1) {
        q.keys[i] = "";
        q.values[i] = "";
    }
}

fn url_query_parse_into(string query, QueryParams q) -> void {
    url_query_params_clear(q);
    if (query == null || len(query) == 0) { return; }
    char* p = cast<char*>(query);
    int n = len(query);
    int start = 0;
    for (int i = 0; i <= n; i = i + 1) {
        if (i == n || _url_byte(p, i) == 38) { // '&'
            if (i > start) {
                int eq = -1;
                for (int j = start; j < i; j = j + 1) {
                    if (_url_byte(p, j) == 61) { eq = j; break; }
                }
                string key = "";
                string value = "";
                if (eq >= 0) {
                    key = url_decode_strict(_url_slice(p, start, eq));
                    value = url_decode(_url_slice(p, eq + 1, i));
                } else {
                    key = url_decode_strict(_url_slice(p, start, i));
                }
                query_params_add(q, key, value);
            }
            start = i + 1;
        }
    }
}

// Copies all entries from src to dst (dst is appended to, not cleared).
fn url_query_copy_into(QueryParams dst, QueryParams src) -> void {
    for (int i = 0; i < src.count; i = i + 1) {
        query_params_add(dst, src.keys[i], src.values[i]);
    }
}

fn url_query_parse(string query) -> QueryParams {
    QueryParams q = url_query_params();
    if (query == null || len(query) == 0) { return q; }
    char* p = cast<char*>(query);
    int n = len(query);
    int start = 0;
    for (int i = 0; i <= n; i = i + 1) {
        if (i == n || _url_byte(p, i) == 38) { // '&'
            if (i > start) {
                int eq = -1;
                for (int j = start; j < i; j = j + 1) {
                    if (_url_byte(p, j) == 61) { eq = j; break; }
                }
                string key = "";
                string value = "";
                if (eq >= 0) {
                    key = url_decode_strict(_url_slice(p, start, eq));
                    value = url_decode(_url_slice(p, eq + 1, i));
                } else {
                    key = url_decode_strict(_url_slice(p, start, i));
                }
                query_params_add(q, key, value);
            }
            start = i + 1;
        }
    }
    return q;
}

fn url_query_get(string query, string key) -> string {
    QueryParams q;
    url_query_parse_into(query, q);
    return query_params_get(q, key);
}

fn url_query_has(string query, string key) -> bool {
    QueryParams q;
    url_query_parse_into(query, q);
    return query_params_has(q, key);
}

fn url_query_build(QueryParams q) -> string {
    if (q.count <= 0) { return ""; }
    string out = "";
    for (int i = 0; i < q.count; i = i + 1) {
        if (i > 0) { out = str_concat(out, "&"); }
        out = str_concat(out, url_encode_form_component(q.keys[i]));
        out = str_concat(out, "=");
        out = str_concat(out, url_encode_form_component(q.values[i]));
    }
    return out;
}

fn url_encode_form(string data) -> string {
    if (data == null) { return ""; }
    QueryParams q;
    url_query_parse_into(data, q);
    if (q.count <= 0) { return data; }
    return url_query_build(q);
}

// -------------------------------------------------------------
// Serialization and composition
// -------------------------------------------------------------

fn url_authority(Url u) -> string {
    string out = "";
    if (len(u.userinfo) > 0) {
        out = str_concat(out, u.userinfo);
        out = str_concat(out, "@");
    }
    if (u.is_ipv6) {
        out = str_concat(out, "[");
        out = str_concat(out, u.host);
        out = str_concat(out, "]");
    } else {
        out = str_concat(out, u.host);
    }
    int default_port = url_default_port(u.scheme);
    if (u.has_port || u.port != default_port) {
        out = str_concat(out, ":");
        out = str_concat(out, int_to_str(u.port));
    }
    return out;
}

fn url_request_target(Url u) -> string {
    string out = u.path;
    if (len(out) == 0) { out = "/"; }
    if (len(u.query) > 0) {
        out = str_concat(out, "?");
        out = str_concat(out, u.query);
    }
    return out;
}

fn url_build(Url u) -> string {
    string out = "";
    if (len(u.scheme) > 0) {
        out = str_concat(out, u.scheme);
        out = str_concat(out, "://");
    }
    out = str_concat(out, url_authority(u));
    out = str_concat(out, u.path);
    if (len(u.query) > 0) {
        out = str_concat(out, "?");
        out = str_concat(out, u.query);
    }
    if (len(u.fragment) > 0) {
        out = str_concat(out, "#");
        out = str_concat(out, u.fragment);
    }
    return out;
}

fn url_origin(string raw_url) -> string {
    Url u = url_parse(raw_url);
    if (!u.valid) { return ""; }
    string scheme = str_to_lower(u.scheme);
    string host = u.host;
    if (!u.is_ipv6) { host = str_to_lower(host); }
    string out = str_concat(scheme, "://");
    if (u.is_ipv6) {
        out = str_concat(out, "[");
        out = str_concat(out, host);
        out = str_concat(out, "]");
    } else {
        out = str_concat(out, host);
    }
    int default_port = url_default_port(scheme);
    if (u.has_port && u.port != default_port) {
        out = str_concat(out, ":");
        out = str_concat(out, int_to_str(u.port));
    }
    return out;
}

fn url_strip_fragment(string raw_url) -> string {
    Url u = url_parse(raw_url);
    if (!u.valid) { return raw_url; }
    u.fragment = "";
    return url_build(u);
}

fn url_same_origin(string a, string b) -> bool {
    Url ua = url_parse(a);
    Url ub = url_parse(b);
    if (!ua.valid || !ub.valid) { return false; }
    return ua.scheme == ub.scheme && ua.host == ub.host && ua.port == ub.port;
}

fn _url_remove_dot_segments(string path) -> string {
    if (path == null || len(path) == 0) { return "/"; }
    char* p = cast<char*>(path);
    int n = len(path);
    bool absolute = _url_byte(p, 0) == 47;
    string parts[128];
    int count = 0;
    int start = 0;
    for (int i = 0; i <= n; i = i + 1) {
        if (i == n || _url_byte(p, i) == 47) {
            if (i > start) {
                string seg = _url_slice(p, start, i);
                if (seg == ".") {
                    // skip
                } else if (seg == "..") {
                    if (count > 0) { count = count - 1; }
                } else if (count < 128) {
                    parts[count] = seg;
                    count = count + 1;
                }
            }
            start = i + 1;
        }
    }
    string out = "";
    if (absolute) { out = "/"; }
    for (int i = 0; i < count; i = i + 1) {
        if (i > 0) { out = str_concat(out, "/"); }
        out = str_concat(out, parts[i]);
    }
    if (len(out) == 0) { out = "/"; }
    return out;
}

// Resolves a (possibly relative) reference against an absolute absu URL.
fn url_join(string base_url, string reference) -> string {
    Url absu = url_parse(base_url);
    if (!absu.valid) { return reference; }
    if (reference == null || len(reference) == 0) { return base_url; }

    Url rel = url_parse(reference);
    // Absolute URL with a scheme.
    if (url_has_scheme(reference)) {
        return url_build(rel);
    }

    char* rp = cast<char*>(reference);
    int rn = len(reference);
    if (rn >= 2 && _url_byte(rp, 0) == 47 && _url_byte(rp, 1) == 47) {
        // Network-path reference: //host/path
        Url net = absu;
        Url parsed = url_parse(str_concat(str_concat(absu.scheme, ":"), reference));
        if (parsed.valid) { return url_build(parsed); }
        return reference;
    }

    Url out = absu;
    out.fragment = rel.fragment;
    out.query = rel.query;

    if (rn > 0 && _url_byte(rp, 0) == 47) {
        out.path = _url_remove_dot_segments(reference);
        if (len(rel.query) == 0 && str_index_of(reference, "?") < 0) {
            out.query = "";
        }
        return url_build(out);
    }

    if (rn > 0 && _url_byte(rp, 0) == 63) { // "?query"
        out.query = _url_slice(rp, 1, rn);
        return url_build(out);
    }
    if (rn > 0 && _url_byte(rp, 0) == 35) { // "#fragment"
        out.fragment = _url_slice(rp, 1, rn);
        return url_build(out);
    }

    // Relative path: replace last segment of absu.path
    int slash = str_last_index_of(absu.path, "/");
    string dir = "/";
    if (slash >= 0) {
        dir = _url_slice(cast<char*>(absu.path), 0, slash + 1);
    }
    if (str_index_of(reference, "?") >= 0) {
        int q = str_index_of(reference, "?");
        out.path = _url_remove_dot_segments(str_concat(dir, _url_slice(rp, 0, q)));
        out.query = _url_slice(rp, q + 1, rn);
    } else {
        out.path = _url_remove_dot_segments(str_concat(dir, reference));
        out.query = "";
    }
    return url_build(out);
}

fn url_from_parts(string scheme, string host, int port, string path, string query) -> string {
    Url u = url_init_defaults();
    u.scheme = scheme;
    u.host = host;
    u.port = port;
    u.path = path;
    u.query = query;
    u.has_port = (port != url_default_port(scheme));
    u.secure = url_is_secure_scheme(scheme);
    u.valid = len(host) > 0;
    return url_build(u);
}

fn url_host_only(string raw_url) -> string {
    Url u = url_parse(raw_url);
    return u.host;
}

fn url_base_domain(string host) -> string {
    if (host == null || len(host) == 0) { return ""; }
    if (url_is_ipv4_host(host) || url_is_ipv6_host(host)) { return host; }
    char* p = cast<char*>(host);
    int last = -1;
    for (int i = 0; i < len(host); i = i + 1) {
        if (_url_byte(p, i) == 46) { last = i; }
    }
    if (last < 0) { return host; }
    int prev = -1;
    for (int i = 0; i < last; i = i + 1) {
        if (_url_byte(p, i) == 46) { prev = i; }
    }
    if (prev < 0) { return host; }
    // Handle common second-level public suffixes co.uk, com.br, ...
    string tld = _url_slice(p, last + 1, len(host));
    string sld = _url_slice(p, prev + 1, last);
    if (len(tld) == 2) {
        if (sld == "co" || sld == "com" || sld == "org" || sld == "net" || sld == "gov" || sld == "edu" || sld == "ac") {
            if (prev > 0) {
                int before = -1;
                for (int i = 0; i < prev; i = i + 1) {
                    if (_url_byte(p, i) == 46) { before = i; }
                }
                if (before >= 0) { return _url_slice(p, before + 1, len(host)); }
            }
        }
    }
    return _url_slice(p, prev + 1, len(host));
}

// ============================================================================
// Extended URL utilities
// ============================================================================

struct DataUrl {
    string media_type;
    string charset;
    bool base64;
    string data;
    bool valid;
};

fn url_init_data() -> DataUrl {
    DataUrl d;
    d.media_type = "";
    d.charset = "";
    d.base64 = false;
    d.data = "";
    d.valid = false;
    return d;
}

fn url_is_absolute(string raw_url) -> bool {
    return url_has_scheme(raw_url);
}

fn url_is_relative(string raw_url) -> bool {
    return !url_has_scheme(raw_url);
}

fn url_is_http(string raw_url) -> bool {
    Url u = url_parse(raw_url);
    return u.valid && (u.scheme == "http" || u.scheme == "https");
}

fn url_is_https(string raw_url) -> bool {
    Url u = url_parse(raw_url);
    return u.valid && u.scheme == "https";
}

fn url_scheme_of(string raw_url) -> string {
    Url u = url_parse(raw_url);
    return u.scheme;
}

fn url_host_of(string raw_url) -> string {
    Url u = url_parse(raw_url);
    return u.host;
}

fn url_path_of(string raw_url) -> string {
    Url u = url_parse(raw_url);
    if (!u.valid) { return ""; }
    return u.path;
}

fn url_query_of(string raw_url) -> string {
    Url u = url_parse(raw_url);
    return u.query;
}

fn url_fragment_of(string raw_url) -> string {
    Url u = url_parse(raw_url);
    return u.fragment;
}

fn url_port_of(string raw_url) -> int {
    Url u = url_parse(raw_url);
    return u.port;
}

fn url_userinfo_of(string raw_url) -> string {
    Url u = url_parse(raw_url);
    return u.userinfo;
}

// Lowercases scheme/host, removes default ports and dot segments.
fn url_normalize(string raw_url) -> string {
    Url u = url_parse(raw_url);
    if (!u.valid) { return raw_url; }
    u.scheme = str_to_lower(u.scheme);
    if (!u.is_ipv6) {
        u.host = str_to_lower(u.host);
    }
    if (u.has_port && u.port == url_default_port(u.scheme)) {
        u.has_port = false;
        u.port = url_default_port(u.scheme);
    }
    if (len(u.path) == 0) {
        u.path = "/";
    }
    u.path = _url_remove_dot_segments(u.path);
    return url_build(u);
}

fn url_without_query(string raw_url) -> string {
    Url u = url_parse(raw_url);
    if (!u.valid) { return raw_url; }
    u.query = "";
    return url_build(u);
}

fn url_without_fragment(string raw_url) -> string {
    Url u = url_parse(raw_url);
    if (!u.valid) { return raw_url; }
    u.fragment = "";
    return url_build(u);
}

fn url_without_userinfo(string raw_url) -> string {
    Url u = url_parse(raw_url);
    if (!u.valid) { return raw_url; }
    u.userinfo = "";
    u.username = "";
    u.password = "";
    return url_build(u);
}

fn url_with_scheme(string raw_url, string scheme) -> string {
    Url u = url_parse(raw_url);
    if (!u.valid) { return raw_url; }
    int old_default = url_default_port(u.scheme);
    if (!u.has_port || u.port == old_default) {
        u.port = url_default_port(scheme);
        u.has_port = false;
    }
    u.scheme = scheme;
    u.secure = url_is_secure_scheme(scheme);
    return url_build(u);
}

fn url_to_https(string raw_url) -> string {
    return url_with_scheme(raw_url, "https");
}

fn url_to_http(string raw_url) -> string {
    return url_with_scheme(raw_url, "http");
}

fn url_with_query(string raw_url, string query) -> string {
    Url u = url_parse(raw_url);
    if (!u.valid) { return raw_url; }
    u.query = query;
    return url_build(u);
}

fn url_with_path(string raw_url, string path) -> string {
    Url u = url_parse(raw_url);
    if (!u.valid) { return raw_url; }
    if (len(path) == 0) {
        u.path = "/";
    } else {
        u.path = path;
    }
    return url_build(u);
}

fn url_add_query(string raw_url, string key, string value) -> string {
    Url u = url_parse(raw_url);
    if (!u.valid) { return raw_url; }
    QueryParams q;
    url_query_parse_into(u.query, q);
    query_params_set(q, key, value);
    u.query = url_query_build(q);
    return url_build(u);
}

fn url_append_query(string raw_url, string key, string value) -> string {
    Url u = url_parse(raw_url);
    if (!u.valid) { return raw_url; }
    QueryParams q;
    url_query_parse_into(u.query, q);
    query_params_add(q, key, value);
    u.query = url_query_build(q);
    return url_build(u);
}

fn url_remove_query(string raw_url, string key) -> string {
    Url u = url_parse(raw_url);
    if (!u.valid) { return raw_url; }
    QueryParams parsed;
    url_query_parse_into(u.query, parsed);
    string out = "";
    for (int i = 0; i < parsed.count; i = i + 1) {
        if (parsed.keys[i] != key) {
            if (len(out) > 0) { out = str_concat(out, "&"); }
            out = str_concat(out, url_encode_form_component(parsed.keys[i]));
            out = str_concat(out, "=");
            out = str_concat(out, url_encode_form_component(parsed.values[i]));
        }
    }
    u.query = out;
    return url_build(u);
}

fn url_merge_query(string raw_url, string extra_query) -> string {
    Url u = url_parse(raw_url);
    if (!u.valid) { return raw_url; }
    string merged_base = url_encode_form(u.query);
    string merged_extra = url_encode_form(extra_query);
    if (len(merged_base) == 0) {
        u.query = merged_extra;
    } else if (len(merged_extra) == 0) {
        u.query = merged_base;
    } else {
        u.query = str_concat(str_concat(merged_base, "&"), merged_extra);
    }
    return url_build(u);
}

fn url_set_fragment(string raw_url, string fragment) -> string {
    Url u = url_parse(raw_url);
    if (!u.valid) { return raw_url; }
    u.fragment = fragment;
    return url_build(u);
}

fn url_join_path(string base_url, string relative_path) -> string {
    return url_join(base_url, relative_path);
}

fn url_path_segment_count(string raw_url) -> int {
    string path = url_path_of(raw_url);
    if (len(path) == 0) { return 0; }
    char* p = cast<char*>(path);
    int count = 0;
    for (int i = 0; i < len(path); i = i + 1) {
        if (_url_byte(p, i) == 47 && i + 1 < len(path)) {
            count = count + 1;
        }
    }
    if (len(path) > 0 && _url_byte(p, 0) != 47) {
        count = count + 1;
    }
    return count;
}

fn url_path_segment(string raw_url, int index) -> string {
    string path = url_path_of(raw_url);
    if (len(path) == 0 || index < 0) { return ""; }
    char* p = cast<char*>(path);
    int current = 0;
    int start = 0;
    if (_url_byte(p, 0) == 47) { start = 1; }
    for (int i = start; i <= len(path); i = i + 1) {
        if (i == len(path) || _url_byte(p, i) == 47) {
            if (i > start) {
                if (current == index) {
                    return _url_slice(p, start, i);
                }
                current = current + 1;
            }
            start = i + 1;
        }
    }
    return "";
}

fn url_last_path_segment(string raw_url) -> string {
    string path = url_path_of(raw_url);
    if (len(path) == 0) { return ""; }
    int slash = str_last_index_of(path, "/");
    if (slash < 0) { return path; }
    return _url_slice(cast<char*>(path), slash + 1, len(path));
}

fn url_host_tld(string host) -> string {
    if (host == null || len(host) == 0) { return ""; }
    if (url_is_ipv4_host(host) || url_is_ipv6_host(host)) { return ""; }
    char* p = cast<char*>(host);
    int last = -1;
    for (int i = 0; i < len(host); i = i + 1) {
        if (_url_byte(p, i) == 46) { last = i; }
    }
    if (last < 0 || last + 1 >= len(host)) { return ""; }
    return _url_slice(p, last + 1, len(host));
}

fn url_host_subdomain(string host) -> string {
    if (host == null || len(host) == 0) { return ""; }
    if (url_is_ipv4_host(host) || url_is_ipv6_host(host)) { return ""; }
    string base_domain = url_base_domain(host);
    if (len(base_domain) == 0 || len(host) <= len(base_domain)) { return ""; }
    int diff = len(host) - len(base_domain) - 1;
    if (diff <= 0) { return ""; }
    return _url_slice(cast<char*>(host), 0, diff);
}

fn url_is_localhost(string host) -> bool {
    if (host == null) { return false; }
    string h = str_to_lower(host);
    if (h == "localhost" || h == "localhost.localdomain") { return true; }
    if (h == "::1" || h == "0:0:0:0:0:0:0:1") { return true; }
    if (str_starts_with(h, "127.")) { return true; }
    return false;
}

fn _url_parse_ipv4_octets(string host, int* o0, int* o1, int* o2, int* o3) -> bool {
    if (!url_is_ipv4_host(host)) { return false; }
    char* p = cast<char*>(host);
    int values[4] = {0, 0, 0, 0};
    int part = 0;
    for (int i = 0; i < len(host); i = i + 1) {
        int c = _url_byte(p, i);
        if (c == 46) {
            part = part + 1;
        } else if (part < 4) {
            values[part] = values[part] * 10 + (c - 48);
        }
    }
    *o0 = values[0];
    *o1 = values[1];
    *o2 = values[2];
    *o3 = values[3];
    return part == 3;
}

fn url_is_private_host(string host) -> bool {
    if (host == null) { return false; }
    if (url_is_localhost(host)) { return true; }
    int a = 0;
    int b = 0;
    int c = 0;
    int d = 0;
    if (!_url_parse_ipv4_octets(host, &a, &b, &c, &d)) { return false; }
    if (a == 10) { return true; }
    if (a == 127) { return true; }
    if (a == 169 && b == 254) { return true; }
    if (a == 172 && b >= 16 && b <= 31) { return true; }
    if (a == 192 && b == 168) { return true; }
    if (a == 100 && b >= 64 && b <= 127) { return true; }
    if (a == 0) { return true; }
    return false;
}

fn url_is_safe_public_url(string raw_url) -> bool {
    Url u = url_parse(raw_url);
    if (!u.valid) { return false; }
    if (!(u.scheme == "http" || u.scheme == "https")) { return false; }
    if (url_is_private_host(u.host)) { return false; }
    return true;
}

// -------------------------------------------------------------
// data: URLs (RFC 2397)
// -------------------------------------------------------------

fn url_data_parse(string raw_url) -> DataUrl {
    DataUrl d = url_init_data();
    if (raw_url == null || len(raw_url) < 6) { return d; }
    if (!str_starts_with(str_to_lower(raw_url), "data:")) { return d; }
    int comma = str_index_of(raw_url, ",");
    if (comma < 0) { return d; }
    string meta = _url_slice(cast<char*>(raw_url), 5, comma);
    d.data = _url_slice(cast<char*>(raw_url), comma + 1, len(raw_url));
    d.media_type = "text/plain";
    d.charset = "";

    char* mp = cast<char*>(meta);
    int start = 0;
    for (int i = 0; i <= len(meta); i = i + 1) {
        if (i == len(meta) || _url_byte(mp, i) == 59) {
            string part = _url_slice(mp, start, i);
            string lower = str_to_lower(str_trim(part));
            if (i == 0 || start == 0) {
                if (len(lower) > 0) { d.media_type = lower; }
            } else if (lower == "base64") {
                d.base64 = true;
            } else if (str_starts_with(lower, "charset=")) {
                d.charset = _url_slice(cast<char*>(lower), 8, len(lower));
            }
            start = i + 1;
        }
    }
    d.valid = true;
    return d;
}

fn url_data_decode_raw(string raw_url, int* out_len) -> char* {
    if (out_len != null) { *out_len = 0; }
    DataUrl d = url_data_parse(raw_url);
    if (!d.valid) { return null; }
    if (d.base64) {
        int decoded_len = 0;
        char* out = crypto_base64_decode(d.data, &decoded_len);
        if (out_len != null) { *out_len = decoded_len; }
        return out;
    }
    string decoded = url_percent_decode(d.data, false);
    char* out = alloc<char>(len(decoded) + 1);
    for (int i = 0; i < len(decoded); i = i + 1) {
        *(out + i) = *(cast<char*>(decoded) + i);
    }
    *(out + len(decoded)) = 0;
    if (out_len != null) { *out_len = len(decoded); }
    return out;
}

fn url_data_decode(string raw_url) -> string {
    int n = 0;
    char* decoded = url_data_decode_raw(raw_url, &n);
    if (decoded == null) { return ""; }
    string out = _url_slice(decoded, 0, n);
    free(decoded);
    return out;
}
