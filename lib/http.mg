// ============================================================================
// Magnetar Standard Library: HTTP/1.1 Client + Server (lib/http.mg)
//
// Features:
//   - http:// over real TCP sockets, https:// through the OpenSSL TLS bridge
//   - GET/POST/PUT/DELETE/HEAD, custom methods and custom headers
//   - Redirects (301/302/303/307/308), chunked transfer decoding
//   - Header lookup, Basic auth from URL userinfo, JSON helpers
//   - Binary-safe bodies (response.body_data + response.body_length)
//   - A small HTTP server: accept, parse requests, send responses
//
// Backwards compatible shortcuts: http_get(), http_post(), .ok, .body.
// ============================================================================

use "lib/net.mg";
use "lib/dns.mg";
use "lib/url.mg";
use "lib/string.mg";
use "lib/buffer.mg";
use "lib/crypto.mg";
use "lib/tls.mg";
use "lib/file.mg";
use "lib/time.mg";

struct HttpResponse {
    int status_code;
    string status_text;
    string http_version;
    string headers;       // header lines only (status line excluded)
    string raw_headers;   // status line + header lines
    string body;          // body as a C string (stops at NUL if binary)
    char* body_data;      // NUL-terminated binary-safe body buffer
    int body_length;      // real body length in bytes
    bool ok;              // 2xx
    bool chunked;
    string content_type;
    string location;
    string final_url;
    int redirects;
    string error;
};

struct HttpRequest {
    string method;
    string target;
    string version;
    string path;
    string query;
    string headers;
    string body;
    char* body_data;
    int body_length;
    int content_length;
    bool valid;
    string error;
};

// Small convenience: create a listening TcpServer for HTTP use.
fn http_listen(int port) -> TcpServer {
    TcpServer server;
    server.start(port, 32);
    return server;
}

// ============================================================================
// Small helpers
// ============================================================================

fn _http_slice(string text, int start, int end) -> string {
    if (text == null) { return ""; }
    if (start < 0) { start = 0; }
    if (end > len(text)) { end = len(text); }
    if (end <= start) { return ""; }
    return str_substr(text, start, end - start);
}

fn _http_init_response() -> HttpResponse {
    HttpResponse r;
    r.status_code = 0;
    r.status_text = "";
    r.http_version = "";
    r.headers = "";
    r.raw_headers = "";
    r.body = "";
    r.body_data = null;
    r.body_length = 0;
    r.ok = false;
    r.chunked = false;
    r.content_type = "";
    r.location = "";
    r.final_url = "";
    r.redirects = 0;
    r.error = "";
    return r;
}

fn _http_error_response(string message) -> HttpResponse {
    HttpResponse r = _http_init_response();
    r.error = message;
    return r;
}

fn _http_init_request() -> HttpRequest {
    HttpRequest r;
    r.method = "";
    r.target = "";
    r.version = "";
    r.path = "";
    r.query = "";
    r.headers = "";
    r.body = "";
    r.body_data = null;
    r.body_length = 0;
    r.content_length = -1;
    r.valid = false;
    r.error = "";
    return r;
}

fn _http_find_header_end(char* data, int length, int* body_start) -> int {
    if (data == null || length <= 0) { return -1; }
    for (int i = 0; i + 3 < length; i = i + 1) {
        char c0 = *(data + i);
        char c1 = *(data + i + 1);
        char c2 = *(data + i + 2);
        char c3 = *(data + i + 3);
        bool crlf2 = (c0 == 13 && c1 == 10 && c2 == 13 && c3 == 10);
        if (crlf2) {
            if (body_start != null) { *body_start = i + 4; }
            return i;
        }
    }
    for (int i = 0; i + 1 < length; i = i + 1) {
        char l0 = *(data + i);
        char l1 = *(data + i + 1);
        bool lf2 = (l0 == 10 && l1 == 10);
        if (lf2) {
            if (body_start != null) { *body_start = i + 2; }
            return i;
        }
    }
    return -1;
}

fn _http_header_value(string headers, string name) -> string {
    if (headers == null || name == null) { return ""; }
    string wanted = str_to_lower(str_trim(name));
    int n = len(headers);
    char* p = cast<char*>(headers);
    int start = 0;
    for (int i = 0; i <= n; i = i + 1) {
        if (i == n || *(p + i) == 10) {
            int end = i;
            if (end > start && *(p + end - 1) == 13) { end = end - 1; }
            int colon = -1;
            for (int j = start; j < end; j = j + 1) {
                if (*(p + j) == 58) { colon = j; break; }
            }
            if (colon >= 0) {
                string line_name = str_to_lower(str_trim(_http_slice(headers, start, colon)));
                if (line_name == wanted) {
                    return str_trim(_http_slice(headers, colon + 1, end));
                }
            }
            start = i + 1;
        }
    }
    return "";
}

fn http_header_value(string headers, string name) -> string {
    return _http_header_value(headers, name);
}

fn _http_contains_ci(string haystack, string needle) -> bool {
    if (haystack == null || needle == null) { return false; }
    return str_index_of(str_to_lower(haystack), str_to_lower(needle)) >= 0;
}

fn _http_is_redirect(int code) -> bool {
    return code == 301 || code == 302 || code == 303 || code == 307 || code == 308;
}

fn http_status_text(int code) -> string {
    if (code == 200) { return "OK"; }
    if (code == 201) { return "Created"; }
    if (code == 202) { return "Accepted"; }
    if (code == 204) { return "No Content"; }
    if (code == 301) { return "Moved Permanently"; }
    if (code == 302) { return "Found"; }
    if (code == 303) { return "See Other"; }
    if (code == 304) { return "Not Modified"; }
    if (code == 307) { return "Temporary Redirect"; }
    if (code == 308) { return "Permanent Redirect"; }
    if (code == 400) { return "Bad Request"; }
    if (code == 401) { return "Unauthorized"; }
    if (code == 403) { return "Forbidden"; }
    if (code == 404) { return "Not Found"; }
    if (code == 405) { return "Method Not Allowed"; }
    if (code == 408) { return "Request Timeout"; }
    if (code == 409) { return "Conflict"; }
    if (code == 413) { return "Payload Too Large"; }
    if (code == 429) { return "Too Many Requests"; }
    if (code == 500) { return "Internal Server Error"; }
    if (code == 501) { return "Not Implemented"; }
    if (code == 502) { return "Bad Gateway"; }
    if (code == 503) { return "Service Unavailable"; }
    if (code == 504) { return "Gateway Timeout"; }
    return "Unknown";
}

fn _http_hex_value(int c) -> int {
    if (c >= 48 && c <= 57) { return c - 48; }
    if (c >= 65 && c <= 70) { return c - 55; }
    if (c >= 97 && c <= 102) { return c - 87; }
    return -1;
}

fn _http_decode_chunked(char* data, int length, int* out_length) -> char* {
    if (out_length != null) { *out_length = 0; }
    if (data == null || length <= 0) { return null; }
    char* out = alloc<char>(length + 1);
    int pos = 0;
    int oi = 0;
    while (pos < length) {
        int line_end = pos;
        while (line_end < length && *(data + line_end) != 10) { line_end = line_end + 1; }
        if (line_end >= length) { break; }
        int size_end = pos;
        if (size_end < line_end && *(data + size_end) == 13) { size_end = size_end + 1; }
        int useful_end = pos;
        while (useful_end < line_end && *(data + useful_end) != 59 && *(data + useful_end) != 13) {
            useful_end = useful_end + 1;
        }
        int chunk_size = 0;
        bool ok_size = false;
        for (int i = pos; i < useful_end; i = i + 1) {
            int h = _http_hex_value(cast<int>(*(data + i)) & 255);
            if (h < 0) { ok_size = false; break; }
            chunk_size = chunk_size * 16 + h;
            ok_size = true;
        }
        if (!ok_size) { break; }
        pos = line_end + 1;
        if (chunk_size == 0) { break; }
        if (pos + chunk_size > length) {
            for (int i = pos; i < length; i = i + 1) {
                *(out + oi) = *(data + i); oi = oi + 1;
            }
            break;
        }
        for (int i = 0; i < chunk_size; i = i + 1) {
            *(out + oi) = *(data + pos + i);
            oi = oi + 1;
        }
        pos = pos + chunk_size;
        while (pos < length && (*(data + pos) == 13 || *(data + pos) == 10)) { pos = pos + 1; }
    }
    *(out + oi) = 0;
    if (out_length != null) { *out_length = oi; }
    return out;
}

// ============================================================================
// Request construction
// ============================================================================

fn _http_host_header(Url u) -> string {
    string host = u.host;
    if (u.is_ipv6) {
        host = str_concat(str_concat("[", host), "]");
    }
    if (u.has_port || u.port != url_default_port(u.scheme)) {
        host = str_concat(str_concat(host, ":"), int_to_str(u.port));
    }
    return host;
}

fn _http_request_target(Url u) -> string {
    string target = u.path;
    if (len(target) == 0) { target = "/"; }
    if (len(u.query) > 0) {
        target = str_concat(str_concat(target, "?"), u.query);
    }
    return target;
}

fn _http_basic_auth_line(Url u) -> string {
    string creds = "";
    if (len(u.userinfo) > 0) {
        creds = u.userinfo;
    } else if (len(u.username) > 0 || len(u.password) > 0) {
        creds = str_concat(u.username, str_concat(":", u.password));
    }
    if (len(creds) == 0) { return ""; }
    string b64 = crypto_base64_encode(cast<char*>(creds), len(creds));
    return str_concat("Authorization: Basic ", str_concat(b64, "\r\n"));
}

fn _http_build_request(string method, Url u, char* body, int body_length, string content_type, string extra_headers) -> ByteBuffer {
    ByteBuffer req;
    req.init(512);
    req.append_str(method);
    req.append_str(" ");
    req.append_str(_http_request_target(u));
    req.append_str(" HTTP/1.1\r\nHost: ");
    req.append_str(_http_host_header(u));
    string user_agent = _http_header_value(extra_headers, "User-Agent");
    if (len(user_agent) == 0) {
        user_agent = "MagnetarHTTP/1.0";
    }
    req.append_str("\r\nUser-Agent: ");
    req.append_str(user_agent);
    req.append_str("\r\nAccept: */*\r\n");
    req.append_str("Accept-Encoding: identity\r\nConnection: close\r\n");

    if (len(extra_headers) > 0) {
        req.append_str(extra_headers);
        int n = len(extra_headers);
        char last = *(cast<char*>(extra_headers) + n - 1);
        if (last != 10) { req.append_str("\r\n"); }
    }

    if (len(u.userinfo) > 0 || len(u.username) > 0) {
        if (!_http_contains_ci(extra_headers, "authorization:")) {
            req.append_str(_http_basic_auth_line(u));
        }
    }

    if (body_length > 0) {
        if (len(content_type) == 0) { content_type = "application/octet-stream"; }
        req.append_str("Content-Type: ");
        req.append_str(content_type);
        req.append_str("\r\nContent-Length: ");
        req.append_str(int_to_str(body_length));
        req.append_str("\r\n");
    }
    req.append_str("\r\n");
    if (body_length > 0 && body != null) { req.append(body, body_length); }
    return req;
}

// ============================================================================
// Response parsing
// ============================================================================

fn _http_parse_response(ByteBuffer wire, string final_url) -> HttpResponse {
    HttpResponse resp = _http_init_response();
    resp.final_url = final_url;
    if (wire.data == null || wire.length <= 0) {
        resp.error = "empty response";
        return resp;
    }

    int body_start = 0;
    int header_end = _http_find_header_end(wire.data, wire.length, &body_start);
    if (header_end < 0) {
        resp.error = "malformed HTTP response (no header terminator)";
        resp.body = wire.slice_string(0, wire.length);
        resp.body_length = wire.length;
        return resp;
    }

    char* p = wire.data;
    int line_end = 0;
    while (line_end < header_end && *(p + line_end) != 10) { line_end = line_end + 1; }
    int line_stop = line_end;
    if (line_stop > 0 && *(p + line_stop - 1) == 13) { line_stop = line_stop - 1; }

    int first_space = -1;
    for (int i = 0; i < line_stop; i = i + 1) {
        if (*(p + i) == 32) { first_space = i; break; }
    }
    if (first_space < 0) {
        resp.error = "malformed status line";
        return resp;
    }

    resp.http_version = _http_slice(cast<string>(wire.data), 0, first_space);
    int code_pos = first_space + 1;
    while (code_pos < line_stop && *(p + code_pos) == 32) { code_pos = code_pos + 1; }
    int code = 0;
    int digits = 0;
    while (code_pos + digits < line_stop && digits < 3) {
        int c = cast<int>(*(p + code_pos + digits)) & 255;
        if (c < 48 || c > 57) { break; }
        code = code * 10 + (c - 48);
        digits = digits + 1;
    }
    resp.status_code = code;
    resp.ok = (code >= 200 && code < 300);
    if (code_pos + digits < line_stop) {
        resp.status_text = str_trim(_http_slice(cast<string>(wire.data), code_pos + digits, line_stop));
    }

    int headers_start = line_end + 1;
    if (headers_start > header_end) { headers_start = header_end; }
    resp.headers = _http_slice(cast<string>(wire.data), headers_start, header_end);
    resp.raw_headers = _http_slice(cast<string>(wire.data), 0, header_end);
    string transfer_encoding = _http_header_value(resp.headers, "Transfer-Encoding");
    resp.chunked = _http_contains_ci(transfer_encoding, "chunked");
    resp.content_type = _http_header_value(resp.headers, "Content-Type");
    resp.location = _http_header_value(resp.headers, "Location");

    int raw_body_len = wire.length - body_start;
    if (raw_body_len < 0) { raw_body_len = 0; }

    char* body_ptr = null;
    int body_len = 0;
    if (resp.chunked) {
        int decoded_len = 0;
        char* rawp2 = wire.data;
        body_ptr = _http_decode_chunked(rawp2 + body_start, raw_body_len, &decoded_len);
        body_len = decoded_len;
    } else {
        string cl = _http_header_value(resp.headers, "Content-Length");
        int content_length = -1;
        if (len(cl) > 0) {
            int parsed = str_to_int(cl);
            if (parsed >= 0) { content_length = parsed; }
        }
        body_len = raw_body_len;
        if (content_length >= 0 && content_length < body_len) {
            body_len = content_length;
        }
        if (body_len > 0) {
            body_ptr = alloc<char>(body_len + 1);
            char* rawp = wire.data;
            for (int i = 0; i < body_len; i = i + 1) {
                *(body_ptr + i) = *(rawp + body_start + i);
            }
            *(body_ptr + body_len) = 0;
        }
    }

    if (body_ptr == null) {
        body_ptr = alloc<char>(1);
        *(body_ptr + 0) = 0;
        body_len = 0;
    }
    resp.body_data = body_ptr;
    resp.body_length = body_len;
    resp.body = cast<string>(body_ptr);
    return resp;
}

// ============================================================================
// One request, no redirects
// ============================================================================

fn _http_perform_once(string method, string raw_url, char* body, int body_length, string content_type, string extra_headers, int timeout_ms, bool verify_tls) -> HttpResponse {
    Url u = url_parse(raw_url);
    if (!u.valid) {
        return _http_error_response("invalid URL");
    }
    bool use_tls = (u.scheme == "https" || u.scheme == "wss");
    if (!use_tls && !(u.scheme == "http" || u.scheme == "ws")) {
        return _http_error_response("unsupported URL scheme (use http:// or https://)");
    }
    if (timeout_ms <= 0) { timeout_ms = 10000; }

    ByteBuffer req = _http_build_request(method, u, body, body_length, content_type, extra_headers);
    ByteBuffer wire;
    wire.init(4096);

    if (use_tls) {
        wire = tls_raw_exchange(u.host, u.port, req.data, req.length, timeout_ms, verify_tls);
        if (wire.length == 0) {
            if (!tls_available()) {
                return _http_error_response("TLS unavailable: openssl binary not found");
            }
            return _http_error_response("TLS handshake/connection failed");
        }
    } else {
        Ipv4Addr ip = dns_resolve(u.host);
        if (!ip.valid) {
            return _http_error_response("DNS resolution failed");
        }
        TcpClient client;
        if (!client.connect_to(ip.ip0, ip.ip1, ip.ip2, ip.ip3, u.port)) {
            return _http_error_response("TCP connection failed");
        }
        net_set_timeout_ms(client.fd, timeout_ms);
        int sent = client.send_bytes(req.data, req.length);
        if (sent <= 0) {
            client.close();
            return _http_error_response("failed to send HTTP request");
        }

        char* rbuf = alloc<char>(8193);
        while (true) {
            int n = client.receive_into(rbuf, 8192);
            if (n <= 0) { break; }
            wire.append(rbuf, n);
            if (wire.length >= 33554432) { break; }
        }
        free(rbuf);
        client.close();
        if (wire.length == 0) {
            return _http_error_response("empty TCP response");
        }
    }

    HttpResponse resp = _http_parse_response(wire, raw_url);
    return resp;
}

// ============================================================================
// Public HTTP client API
// ============================================================================

fn http_request_bytes_ex(string method, string url, char* body, int body_length, string content_type, string extra_headers, bool follow_redirects, int timeout_ms, bool verify_tls) -> HttpResponse {
    string current_url = url;
    string current_method = method;
    char* current_body = body;
    int current_body_length = body_length;
    string current_type = content_type;
    int redirects = 0;
    int max_redirects = 8;

    HttpResponse resp = _http_init_response();
    for (int step = 0; step < max_redirects + 1; step = step + 1) {
        resp = _http_perform_once(current_method, current_url, current_body, current_body_length, current_type, extra_headers, timeout_ms, verify_tls);
        resp.redirects = redirects;
        resp.final_url = current_url;
        if (!follow_redirects) { break; }
        if (resp.error != "") { break; }
        if (!_http_is_redirect(resp.status_code)) { break; }
        if (len(resp.location) == 0) { break; }

        string next_url = url_join(current_url, resp.location);
        if (next_url == current_url) { break; }

        if (resp.status_code == 303 ||
            ((resp.status_code == 301 || resp.status_code == 302) &&
             !(current_method == "GET" || current_method == "HEAD"))) {
            current_method = "GET";
            current_body = null;
            current_body_length = 0;
            current_type = "";
        }
        current_url = next_url;
        redirects = redirects + 1;
    }
    resp.redirects = redirects;
    resp.final_url = current_url;
    return resp;
}

fn http_request_ex(string method, string url, string body, string content_type, string extra_headers, bool follow_redirects, int timeout_ms, bool verify_tls) -> HttpResponse {
    char* data = null;
    int data_len = 0;
    if (body != null) {
        data = cast<char*>(body);
        data_len = len(body);
    }
    return http_request_bytes_ex(method, url, data, data_len, content_type, extra_headers, follow_redirects, timeout_ms, verify_tls);
}

fn http_request(string method, string url, string body, string content_type) -> HttpResponse {
    return http_request_ex(method, url, body, content_type, "", true, 10000, true);
}

fn http_get(string url) -> HttpResponse {
    return http_request_ex("GET", url, "", "", "", true, 10000, true);
}

fn http_get_insecure(string url) -> HttpResponse {
    return http_request_ex("GET", url, "", "", "", true, 10000, false);
}

fn http_get_with_headers(string url, string headers) -> HttpResponse {
    return http_request_ex("GET", url, "", "", headers, true, 10000, true);
}

fn http_get_timeout(string url, int timeout_ms) -> HttpResponse {
    return http_request_ex("GET", url, "", "", "", true, timeout_ms, true);
}

fn http_post(string url, string data, string content_type) -> HttpResponse {
    return http_request_ex("POST", url, data, content_type, "", true, 10000, true);
}

fn http_post_json(string url, string json) -> HttpResponse {
    return http_request_ex("POST", url, json, "application/json", "", true, 10000, true);
}

fn http_post_form(string url, string form_data) -> HttpResponse {
    return http_request_ex("POST", url, form_data, "application/x-www-form-urlencoded", "", true, 10000, true);
}

fn http_put(string url, string data, string content_type) -> HttpResponse {
    return http_request_ex("PUT", url, data, content_type, "", true, 10000, true);
}

fn http_delete(string url) -> HttpResponse {
    return http_request_ex("DELETE", url, "", "", "", true, 10000, true);
}

fn http_head(string url) -> HttpResponse {
    return http_request_ex("HEAD", url, "", "", "", true, 10000, true);
}

fn http_post_with_headers(string url, string data, string content_type, string headers) -> HttpResponse {
    return http_request_ex("POST", url, data, content_type, headers, true, 10000, true);
}

// ============================================================================
// JSON helpers (small, dependency-free)
// ============================================================================

fn http_json_escape(string text) -> string {
    if (text == null) { return ""; }
    int n = len(text);
    char* p = cast<char*>(text);
    char* out = alloc<char>(n * 6 + 1);
    int oi = 0;
    for (int i = 0; i < n; i = i + 1) {
        int c = cast<int>(*(p + i)) & 255;
        if (c == 34) {
            *(out + oi) = 92; oi = oi + 1;
            *(out + oi) = 34; oi = oi + 1;
        } else if (c == 92) {
            *(out + oi) = 92; oi = oi + 1;
            *(out + oi) = 92; oi = oi + 1;
        } else if (c == 10) {
            *(out + oi) = 92; oi = oi + 1;
            *(out + oi) = 110; oi = oi + 1;
        } else if (c == 13) {
            *(out + oi) = 92; oi = oi + 1;
            *(out + oi) = 114; oi = oi + 1;
        } else if (c == 9) {
            *(out + oi) = 92; oi = oi + 1;
            *(out + oi) = 116; oi = oi + 1;
        } else if (c < 32) {
            *(out + oi) = 92; oi = oi + 1;
            *(out + oi) = 117; oi = oi + 1;
            *(out + oi) = 48; oi = oi + 1;
            *(out + oi) = 48; oi = oi + 1;
            int hi = c / 16;
            int lo = c % 16;
            if (hi < 10) { *(out + oi) = cast<char>(48 + hi); } else { *(out + oi) = cast<char>(97 + hi - 10); }
            oi = oi + 1;
            if (lo < 10) { *(out + oi) = cast<char>(48 + lo); } else { *(out + oi) = cast<char>(97 + lo - 10); }
            oi = oi + 1;
        } else {
            *(out + oi) = cast<char>(c);
            oi = oi + 1;
        }
    }
    *(out + oi) = 0;
    return cast<string>(out);
}

fn _http_json_value_start(string json, string key) -> int {
    string quoted = str_concat(str_concat("\"", key), "\"");
    int k = str_index_of(json, quoted);
    if (k < 0) { return -1; }
    int colon = str_index_of(str_substr(json, k + len(quoted), len(json) - k - len(quoted)), ":");
    if (colon < 0) { return -1; }
    int pos = k + len(quoted) + colon + 1;
    char* p = cast<char*>(json);
    while (pos < len(json) && (*(p + pos) == 32 || *(p + pos) == 9 ||
           *(p + pos) == 10 || *(p + pos) == 13)) {
        pos = pos + 1;
    }
    return pos;
}

fn http_json_get_string(string json, string key) -> string {
    if (json == null || key == null) { return ""; }
    int pos = _http_json_value_start(json, key);
    if (pos < 0 || pos >= len(json)) { return ""; }
    char* p = cast<char*>(json);
    if (*(p + pos) != 34) { return ""; }
    pos = pos + 1;
    char* out = alloc<char>(len(json) - pos + 1);
    int oi = 0;
    while (pos < len(json)) {
        int c = cast<int>(*(p + pos)) & 255;
        if (c == 34) { break; }
        if (c == 92 && pos + 1 < len(json)) {
            pos = pos + 1;
            int e = cast<int>(*(p + pos)) & 255;
            if (e == 110) { c = 10; }
            else if (e == 114) { c = 13; }
            else if (e == 116) { c = 9; }
            else if (e == 34) { c = 34; }
            else if (e == 92) { c = 92; }
            else if (e == 47) { c = 47; }
            else { c = e; }
        }
        *(out + oi) = cast<char>(c);
        oi = oi + 1;
        pos = pos + 1;
    }
    *(out + oi) = 0;
    return cast<string>(out);
}

fn http_json_get_int(string json, string key) -> int {
    if (json == null || key == null) { return 0; }
    int pos = _http_json_value_start(json, key);
    if (pos < 0 || pos >= len(json)) { return 0; }
    char* p = cast<char*>(json);
    int start = pos;
    while (pos < len(json)) {
        int c = cast<int>(*(p + pos)) & 255;
        if ((c >= 48 && c <= 57) || c == 45) {
            pos = pos + 1;
        } else {
            break;
        }
    }
    if (pos == start) { return 0; }
    return str_to_int(_http_slice(json, start, pos));
}

// ============================================================================
// Server helpers
// ============================================================================

fn http_read_request(int client_fd, int timeout_ms) -> HttpRequest {
    HttpRequest req = _http_init_request();
    if (client_fd < 0) {
        req.error = "invalid client fd";
        return req;
    }
    if (timeout_ms <= 0) { timeout_ms = 10000; }
    net_set_timeout_ms(client_fd, timeout_ms);

    ByteBuffer wire;
    wire.init(2048);
    char* rbuf = alloc<char>(8193);
    int header_end = -1;
    int body_start = 0;
    int expected_body = -1;

    while (header_end < 0) {
        int n = net_recv_into(client_fd, rbuf, 8192);
        if (n <= 0) {
            free(rbuf);
            wire.free_buffer();
            req.error = "connection closed before headers";
            return req;
        }
        wire.append(rbuf, n);
        header_end = _http_find_header_end(wire.data, wire.length, &body_start);
        if (wire.length > 1048576 && header_end < 0) {
            free(rbuf);
            wire.free_buffer();
            req.error = "request headers too large";
            return req;
        }
    }

    string header_block = _http_slice(cast<string>(wire.data), 0, header_end);
    string content_length_text = _http_header_value(header_block, "Content-Length");
    if (len(content_length_text) > 0) {
        expected_body = str_to_int(content_length_text);
    }

    if (expected_body > 0) {
        while (wire.length < body_start + expected_body) {
            int n = net_recv_into(client_fd, rbuf, 8192);
            if (n <= 0) { break; }
            wire.append(rbuf, n);
            if (wire.length > 33554432) { break; }
        }
    } else {
        expected_body = wire.length - body_start;
        if (expected_body < 0) { expected_body = 0; }
    }

    int line_end = 0;
    char* rp = wire.data;
    while (line_end < header_end && *(rp + line_end) != 10) { line_end = line_end + 1; }
    int line_stop = line_end;
    if (line_stop > 0 && *(rp + line_stop - 1) == 13) { line_stop = line_stop - 1; }
    string request_line = _http_slice(cast<string>(rp), 0, line_stop);

    int first_space = str_index_of(request_line, " ");
    if (first_space < 0) {
        free(rbuf);
        wire.free_buffer();
        req.error = "malformed request line";
        return req;
    }
    req.method = _http_slice(request_line, 0, first_space);
    int second_space = str_index_of(str_substr(request_line, first_space + 1, len(request_line) - first_space - 1), " ");
    if (second_space < 0) {
        req.target = _http_slice(request_line, first_space + 1, len(request_line));
        req.version = "HTTP/1.1";
    } else {
        second_space = second_space + first_space + 1;
        req.target = _http_slice(request_line, first_space + 1, second_space);
        req.version = _http_slice(request_line, second_space + 1, len(request_line));
    }

    int qmark = str_index_of(req.target, "?");
    if (qmark >= 0) {
        req.path = _http_slice(req.target, 0, qmark);
        req.query = _http_slice(req.target, qmark + 1, len(req.target));
    } else {
        req.path = req.target;
        req.query = "";
    }

    int headers_start = line_end + 1;
    if (headers_start > header_end) { headers_start = header_end; }
    req.headers = _http_slice(cast<string>(rp), headers_start, header_end);

    int avail = wire.length - body_start;
    if (avail < 0) { avail = 0; }
    if (expected_body >= 0 && expected_body < avail) { avail = expected_body; }
    req.body_length = avail;
    req.content_length = expected_body;
    if (avail > 0) {
        char* body_ptr = alloc<char>(avail + 1);
        for (int i = 0; i < avail; i = i + 1) {
            *(body_ptr + i) = *(rp + body_start + i);
        }
        *(body_ptr + avail) = 0;
        req.body_data = body_ptr;
        req.body = cast<string>(body_ptr);
    } else {
        req.body_data = null;
        req.body = "";
    }

    req.valid = true;
    free(rbuf);
    wire.free_buffer();
    return req;
}

fn http_send_response(int client_fd, int status, string content_type, char* body, int body_length) -> int {
    if (client_fd < 0) { return -1; }
    if (content_type == null || len(content_type) == 0) {
        content_type = "text/plain; charset=utf-8";
    }
    if (body_length < 0) { body_length = 0; }

    ByteBuffer out;
    out.init(512);
    out.append_str("HTTP/1.1 ");
    out.append_int(status);
    out.append_str(" ");
    out.append_str(http_status_text(status));
    out.append_str("\r\nServer: MagnetarHTTP/1.0\r\nContent-Type: ");
    out.append_str(content_type);
    out.append_str("\r\nContent-Length: ");
    out.append_int(body_length);
    out.append_str("\r\nConnection: close\r\n\r\n");
    if (body_length > 0 && body != null) { out.append(body, body_length); }

    int sent = net_send_all(client_fd, out.data, out.length);
    out.free_buffer();
    return sent;
}

fn http_send_text(int client_fd, int status, string text) -> int {
    return http_send_response(client_fd, status, "text/plain; charset=utf-8", cast<char*>(text), len(text));
}

fn http_send_html(int client_fd, int status, string html) -> int {
    return http_send_response(client_fd, status, "text/html; charset=utf-8", cast<char*>(html), len(html));
}

fn http_send_json(int client_fd, int status, string json) -> int {
    return http_send_response(client_fd, status, "application/json", cast<char*>(json), len(json));
}

fn http_send_status(int client_fd, int status) -> int {
    return http_send_response(client_fd, status, "text/plain; charset=utf-8", null, 0);
}

// ============================================================================
// Authentication, signing and JSON Web Tokens (HS256)
// ============================================================================

fn http_const_time_equal(char* a, char* b, int length) -> bool {
    if (a == null || b == null || length <= 0) { return false; }
    int diff = 0;
    for (int i = 0; i < length; i = i + 1) {
        diff = diff | ((cast<int>(*(a + i)) & 255) ^ (cast<int>(*(b + i)) & 255));
    }
    return diff == 0;
}

fn http_basic_auth_value(string username, string password) -> string {
    string creds = str_concat(username, str_concat(":", password));
    string b64 = crypto_base64_encode(cast<char*>(creds), len(creds));
    return str_concat("Basic ", b64);
}

fn http_basic_auth_header(string username, string password) -> string {
    return str_concat("Authorization: ", str_concat(http_basic_auth_value(username, password), "\r\n"));
}

fn http_bearer_auth_value(string token) -> string {
    return str_concat("Bearer ", token);
}

fn http_bearer_auth_header(string token) -> string {
    return str_concat("Authorization: ", str_concat(http_bearer_auth_value(token), "\r\n"));
}

fn http_hmac_sha256_hex(string secret, string message) -> string {
    return crypto_hmac_sha256_hex(secret, message);
}

fn http_hmac_signature_header(string secret, string message) -> string {
    string sig = crypto_hmac_sha256_hex(secret, message);
    return str_concat("X-Signature: ", str_concat(sig, "\r\n"));
}

fn http_jwt_encode_hs256(string payload_json, string secret) -> string {
    string header_json = "{\"alg\":\"HS256\",\"typ\":\"JWT\"}";
    string header_b64 = crypto_base64url_encode(cast<char*>(header_json), len(header_json));
    string payload_b64 = crypto_base64url_encode(cast<char*>(payload_json), len(payload_json));
    string signing_input = str_concat(str_concat(header_b64, "."), payload_b64);
    char* signature = alloc<char>(32);
    crypto_hmac_sha256_raw(secret, cast<char*>(signing_input), len(signing_input), signature);
    string signature_b64 = crypto_base64url_encode(signature, 32);
    free(signature);
    return str_concat(str_concat(signing_input, "."), signature_b64);
}

fn http_jwt_payload_hs256(string token) -> string {
    if (token == null) { return ""; }
    int first = str_index_of(token, ".");
    if (first < 0) { return ""; }
    int second = str_index_of(str_substr(token, first + 1, len(token) - first - 1), ".");
    if (second < 0) { return ""; }
    second = second + first + 1;
    string payload_b64 = _http_slice(token, first + 1, second);
    int decoded_len = 0;
    char* decoded = crypto_base64url_decode(payload_b64, &decoded_len);
    if (decoded == null) { return ""; }
    string payload = _http_slice(cast<string>(decoded), 0, decoded_len);
    free(decoded);
    return payload;
}

fn http_jwt_verify_hs256(string token, string secret) -> bool {
    if (token == null) { return false; }
    int last = str_last_index_of(token, ".");
    if (last < 0) { return false; }
    string signing_input = _http_slice(token, 0, last);
    string signature_b64 = _http_slice(token, last + 1, len(token));
    int sig_len = 0;
    char* provided = crypto_base64url_decode(signature_b64, &sig_len);
    if (provided == null || sig_len != 32) {
        if (provided != null) { free(provided); }
        return false;
    }
    char* expected = alloc<char>(32);
    crypto_hmac_sha256_raw(secret, cast<char*>(signing_input), len(signing_input), expected);
    bool ok = http_const_time_equal(provided, expected, 32);
    free(provided);
    free(expected);
    return ok;
}

// ============================================================================
// Cookie helpers (header-string based, domain isolation handled by caller)
// ============================================================================

fn _http_cookie_strip_prefix(string header) -> string {
    if (header == null) { return ""; }
    string trimmed = str_trim(header);
    if (_http_contains_ci(trimmed, "cookie:") && str_index_of(trimmed, ":") == 6) {
        return str_trim(_http_slice(trimmed, 7, len(trimmed)));
    }
    return trimmed;
}

fn http_cookie_header_get(string header, string name) -> string {
    string jar = _http_cookie_strip_prefix(header);
    if (len(jar) == 0 || name == null || len(name) == 0) { return ""; }
    int start = 0;
    int n = len(jar);
    char* p = cast<char*>(jar);
    for (int i = 0; i <= n; i = i + 1) {
        if (i == n || *(p + i) == 59) {
            string pair = str_trim(_http_slice(jar, start, i));
            int eq = str_index_of(pair, "=");
            if (eq >= 0) {
                string key = str_trim(_http_slice(pair, 0, eq));
                if (key == name) {
                    return str_trim(_http_slice(pair, eq + 1, len(pair)));
                }
            }
            start = i + 1;
        }
    }
    return "";
}

fn _http_cookie_contains(string jar, string name) -> bool {
    if (len(jar) == 0) { return false; }
    int n = len(jar);
    char* p = cast<char*>(jar);
    int start = 0;
    for (int i = 0; i <= n; i = i + 1) {
        if (i == n || *(p + i) == 59) {
            string pair = str_trim(_http_slice(jar, start, i));
            int eq = str_index_of(pair, "=");
            if (eq >= 0 && str_trim(_http_slice(pair, 0, eq)) == name) {
                return true;
            }
            start = i + 1;
        }
    }
    return false;
}

fn http_cookie_header_remove(string header, string name) -> string {
    string jar = _http_cookie_strip_prefix(header);
    string out = "";
    int n = len(jar);
    char* p = cast<char*>(jar);
    int start = 0;
    for (int i = 0; i <= n; i = i + 1) {
        if (i == n || *(p + i) == 59) {
            string pair = str_trim(_http_slice(jar, start, i));
            int eq = str_index_of(pair, "=");
            bool keep = true;
            if (eq >= 0 && str_trim(_http_slice(pair, 0, eq)) == name) {
                keep = false;
            }
            if (keep && len(pair) > 0) {
                if (len(out) > 0) { out = str_concat(out, "; "); }
                out = str_concat(out, pair);
            }
            start = i + 1;
        }
    }
    return out;
}

fn http_cookie_header_set(string header, string name, string value) -> string {
    string clean = http_cookie_header_remove(header, name);
    string pair = str_concat(name, str_concat("=", value));
    if (len(clean) == 0) { return pair; }
    return str_concat(str_concat(clean, "; "), pair);
}

fn http_cookie_header_from_set_cookie(string header, string set_cookie) -> string {
    if (set_cookie == null || len(set_cookie) == 0) { return header; }
    int semi = str_index_of(set_cookie, ";");
    string first = set_cookie;
    if (semi >= 0) { first = _http_slice(set_cookie, 0, semi); }
    first = str_trim(first);
    int eq = str_index_of(first, "=");
    if (eq <= 0) { return header; }
    string name = str_trim(_http_slice(first, 0, eq));
    string value = str_trim(_http_slice(first, eq + 1, len(first)));
    if (len(name) == 0) { return header; }

    string lower = str_to_lower(set_cookie);
    int max_age = str_index_of(lower, "max-age=");
    if (max_age >= 0) {
        string age_text = _http_slice(set_cookie, max_age + 8, len(set_cookie));
        int stop = 0;
        char* ap = cast<char*>(age_text);
        while (stop < len(age_text) && *(ap + stop) != 59 && *(ap + stop) != 32) { stop = stop + 1; }
        int age = str_to_int(_http_slice(age_text, 0, stop));
        if (age <= 0) {
            return http_cookie_header_remove(header, name);
        }
    }
    return http_cookie_header_set(header, name, value);
}

fn http_cookie_header_from_response(string header, HttpResponse resp) -> string {
    string jar = header;
    if (resp.headers == null) { return jar; }
    int n = len(resp.headers);
    char* p = cast<char*>(resp.headers);
    int start = 0;
    for (int i = 0; i <= n; i = i + 1) {
        if (i == n || *(p + i) == 10) {
            int end = i;
            if (end > start && *(p + end - 1) == 13) { end = end - 1; }
            string line = _http_slice(resp.headers, start, end);
            if (str_starts_with(str_to_lower(line), "set-cookie:")) {
                jar = http_cookie_header_from_set_cookie(jar, _http_slice(line, 11, len(line)));
            }
            start = i + 1;
        }
    }
    return jar;
}

// ============================================================================
// requests.Session-like client
// ============================================================================

struct HttpClient {
    string base_url;
    string user_agent;
    int timeout_ms;
    bool verify_tls;
    bool follow_redirects;
    int max_redirects;
    int retries;
    int retry_delay_ms;
    string cookies;
    string header_names[32];
    string header_values[32];
    int header_count;
};

fn http_client_new(string base_url) -> HttpClient {
    HttpClient c;
    c.base_url = base_url;
    c.user_agent = "MagnetarHTTP/1.1";
    c.timeout_ms = 15000;
    c.verify_tls = true;
    c.follow_redirects = true;
    c.max_redirects = 8;
    c.retries = 1;
    c.retry_delay_ms = 400;
    c.cookies = "";
    c.header_count = 0;
    for (int i = 0; i < 32; i = i + 1) {
        c.header_names[i] = "";
        c.header_values[i] = "";
    }
    return c;
}

fn http_client_set_header(HttpClient c, string name, string value) -> void {
    for (int i = 0; i < c.header_count; i = i + 1) {
        if (str_equals_ignore_case(c.header_names[i], name)) {
            c.header_values[i] = value;
            return;
        }
    }
    if (c.header_count >= 32) { return; }
    c.header_names[c.header_count] = name;
    c.header_values[c.header_count] = value;
    c.header_count = c.header_count + 1;
}

fn http_client_remove_header(HttpClient c, string name) -> void {
    int write = 0;
    for (int i = 0; i < c.header_count; i = i + 1) {
        if (!str_equals_ignore_case(c.header_names[i], name)) {
            c.header_names[write] = c.header_names[i];
            c.header_values[write] = c.header_values[i];
            write = write + 1;
        }
    }
    c.header_count = write;
}

fn http_client_set_basic_auth(HttpClient c, string username, string password) -> void {
    http_client_set_header(c, "Authorization", http_basic_auth_value(username, password));
}

fn http_client_set_bearer(HttpClient c, string token) -> void {
    http_client_set_header(c, "Authorization", http_bearer_auth_value(token));
}

fn http_client_clear_cookies(HttpClient c) -> void {
    c.cookies = "";
}

fn http_client_cookie(HttpClient c, string name) -> string {
    return http_cookie_header_get(c.cookies, name);
}

fn _http_client_header_block(HttpClient c, Url u) -> string {
    ByteBuffer block;
    block.init(256);
    bool has_user_agent = false;
    for (int i = 0; i < c.header_count; i = i + 1) {
        if (str_equals_ignore_case(c.header_names[i], "User-Agent")) {
            has_user_agent = true;
        }
        block.append_str(c.header_names[i]);
        block.append_str(": ");
        block.append_str(c.header_values[i]);
        block.append_str("\r\n");
    }
    if (!has_user_agent && len(c.user_agent) > 0) {
        block.append_str("User-Agent: ");
        block.append_str(c.user_agent);
        block.append_str("\r\n");
    }
    if (len(c.cookies) > 0) {
        block.append_str("Cookie: ");
        block.append_str(c.cookies);
        block.append_str("\r\n");
    }
    string out = block.slice_string(0, block.length);
    block.free_buffer();
    return out;
}

fn http_client_request_bytes(HttpClient c, string method, string url, char* body, int body_length, string content_type) -> HttpResponse {
    string start_url = url;
    if (!url_has_scheme(start_url) && len(c.base_url) > 0) {
        start_url = url_join(c.base_url, start_url);
    }
    int max_redirects = c.max_redirects;
    if (max_redirects < 0) { max_redirects = 0; }
    int retries = c.retries;
    if (retries < 0) { retries = 0; }
    int timeout_ms = c.timeout_ms;
    if (timeout_ms <= 0) { timeout_ms = 15000; }

    HttpResponse resp = _http_init_response();
    for (int attempt = 0; attempt <= retries; attempt = attempt + 1) {
        string current_url = start_url;
        string current_method = method;
        char* current_body = body;
        int current_body_length = body_length;
        string current_type = content_type;
        int redirects = 0;
        bool transport_ok = true;

        for (int step = 0; step <= max_redirects; step = step + 1) {
            Url u = url_parse(current_url);
            if (!u.valid) {
                resp = _http_error_response("invalid URL");
                transport_ok = false;
                break;
            }
            string extra = _http_client_header_block(c, u);
            resp = _http_perform_once(current_method, current_url, current_body, current_body_length, current_type, extra, timeout_ms, c.verify_tls);
            c.cookies = http_cookie_header_from_response(c.cookies, resp);
            resp.redirects = redirects;
            resp.final_url = current_url;

            if (resp.error != "") {
                transport_ok = false;
                break;
            }
            if (!c.follow_redirects) { break; }
            if (!_http_is_redirect(resp.status_code)) { break; }
            if (len(resp.location) == 0) { break; }

            string next_url = url_join(current_url, resp.location);
            if (next_url == current_url) { break; }
            if (resp.status_code == 303 ||
                ((resp.status_code == 301 || resp.status_code == 302) &&
                 !(current_method == "GET" || current_method == "HEAD"))) {
                current_method = "GET";
                current_body = null;
                current_body_length = 0;
                current_type = "";
            }
            current_url = next_url;
            redirects = redirects + 1;
        }

        resp.redirects = redirects;
        if (transport_ok) {
            return resp;
        }
        if (attempt < retries && c.retry_delay_ms > 0) {
            time_sleep_ms(c.retry_delay_ms);
        }
    }
    return resp;
}

fn http_client_request(HttpClient c, string method, string url, string body, string content_type) -> HttpResponse {
    char* data = null;
    int data_len = 0;
    if (body != null) {
        data = cast<char*>(body);
        data_len = len(body);
    }
    return http_client_request_bytes(c, method, url, data, data_len, content_type);
}

fn http_client_get(HttpClient c, string url) -> HttpResponse {
    return http_client_request_bytes(c, "GET", url, null, 0, "");
}

fn http_client_head(HttpClient c, string url) -> HttpResponse {
    return http_client_request_bytes(c, "HEAD", url, null, 0, "");
}

fn http_client_delete(HttpClient c, string url) -> HttpResponse {
    return http_client_request_bytes(c, "DELETE", url, null, 0, "");
}

fn http_client_post(HttpClient c, string url, string body, string content_type) -> HttpResponse {
    return http_client_request(c, "POST", url, body, content_type);
}

fn http_client_post_json(HttpClient c, string url, string json) -> HttpResponse {
    return http_client_request(c, "POST", url, json, "application/json");
}

fn http_client_post_form(HttpClient c, string url, string form_data) -> HttpResponse {
    return http_client_request(c, "POST", url, form_data, "application/x-www-form-urlencoded");
}

fn http_client_put(HttpClient c, string url, string body, string content_type) -> HttpResponse {
    return http_client_request(c, "PUT", url, body, content_type);
}

// ============================================================================
// Multipart/form-data builder (binary safe)
// ============================================================================

struct HttpMultipart {
    char* data;
    int length;
    int capacity;
    string boundary;
    bool finished;
};

fn _http_mp_reserve(HttpMultipart m, int extra) -> void {
    int needed = m.length + extra + 1;
    if (needed <= m.capacity) { return; }
    int cap = m.capacity;
    if (cap < 256) { cap = 256; }
    while (cap < needed) { cap = cap * 2; }
    char* next = alloc<char>(cap);
    for (int i = 0; i < m.length; i = i + 1) {
        *(next + i) = *(m.data + i);
    }
    if (m.data != null) { free(m.data); }
    m.data = next;
    m.capacity = cap;
}

fn _http_mp_append(HttpMultipart m, char* src, int count) -> void {
    if (src == null || count <= 0) { return; }
    _http_mp_reserve(m, count);
    for (int i = 0; i < count; i = i + 1) {
        *(m.data + m.length + i) = *(src + i);
    }
    m.length = m.length + count;
    *(m.data + m.length) = 0;
}

fn _http_mp_append_str(HttpMultipart m, string text) -> void {
    _http_mp_append(m, cast<char*>(text), len(text));
}

fn http_multipart_new() -> HttpMultipart {
    HttpMultipart m;
    m.data = null;
    m.length = 0;
    m.capacity = 0;
    m.boundary = str_concat("----MagnetarBoundary", crypto_rng_hex(12));
    m.finished = false;
    _http_mp_reserve(m, 256);
    *(m.data + 0) = 0;
    return m;
}

fn http_multipart_add_field(HttpMultipart m, string name, string value) -> void {
    _http_mp_append_str(m, str_concat("--", str_concat(m.boundary, "\r\n")));
    _http_mp_append_str(m, "Content-Disposition: form-data; name=\"");
    _http_mp_append_str(m, name);
    _http_mp_append_str(m, "\"\r\n\r\n");
    _http_mp_append_str(m, value);
    _http_mp_append_str(m, "\r\n");
}

fn http_multipart_add_file(HttpMultipart m, string name, string filename, string mime_type, char* content, int content_length) -> void {
    if (len(mime_type) == 0) { mime_type = "application/octet-stream"; }
    _http_mp_append_str(m, str_concat("--", str_concat(m.boundary, "\r\n")));
    _http_mp_append_str(m, "Content-Disposition: form-data; name=\"");
    _http_mp_append_str(m, name);
    _http_mp_append_str(m, "\"; filename=\"");
    _http_mp_append_str(m, filename);
    _http_mp_append_str(m, "\"\r\nContent-Type: ");
    _http_mp_append_str(m, mime_type);
    _http_mp_append_str(m, "\r\n\r\n");
    _http_mp_append(m, content, content_length);
    _http_mp_append_str(m, "\r\n");
}

fn http_multipart_finish(HttpMultipart m) -> void {
    if (m.finished) { return; }
    _http_mp_append_str(m, str_concat("--", str_concat(m.boundary, "--\r\n")));
    m.finished = true;
}

fn http_multipart_content_type(HttpMultipart m) -> string {
    return str_concat("multipart/form-data; boundary=", m.boundary);
}

fn http_multipart_body(HttpMultipart m) -> char* {
    return m.data;
}

fn http_multipart_length(HttpMultipart m) -> int {
    return m.length;
}

fn http_multipart_free(HttpMultipart m) -> void {
    if (m.data != null) {
        free(m.data);
        m.data = null;
    }
    m.length = 0;
    m.capacity = 0;
}

fn http_post_multipart(string url, HttpMultipart m, string extra_headers) -> HttpResponse {
    return http_request_bytes_ex("POST", url, m.data, m.length, http_multipart_content_type(m), extra_headers, true, 30000, true);
}

// ============================================================================
// Downloads, uploads and reconnaissance helpers
// ============================================================================

fn _http_mime_type(string path) -> string {
    string ext = str_to_lower(file_extension(path));
    if (ext == "html" || ext == "htm") { return "text/html"; }
    if (ext == "txt") { return "text/plain"; }
    if (ext == "json") { return "application/json"; }
    if (ext == "xml") { return "application/xml"; }
    if (ext == "css") { return "text/css"; }
    if (ext == "js") { return "application/javascript"; }
    if (ext == "csv") { return "text/csv"; }
    if (ext == "png") { return "image/png"; }
    if (ext == "jpg" || ext == "jpeg") { return "image/jpeg"; }
    if (ext == "gif") { return "image/gif"; }
    if (ext == "webp") { return "image/webp"; }
    if (ext == "svg") { return "image/svg+xml"; }
    if (ext == "pdf") { return "application/pdf"; }
    if (ext == "zip") { return "application/zip"; }
    if (ext == "gz") { return "application/gzip"; }
    if (ext == "mp4") { return "video/mp4"; }
    if (ext == "mp3") { return "audio/mpeg"; }
    return "application/octet-stream";
}

fn http_save_response(HttpResponse resp, string path) -> bool {
    if (resp.body_data == null || resp.body_length < 0) { return false; }
    int fd = file_open(path, "w");
    if (fd < 0) { return false; }
    int written = 0;
    while (written < resp.body_length) {
        int n = file_write(fd, cast<string>(resp.body_data + written), resp.body_length - written);
        if (n <= 0) {
            file_close(fd);
            return false;
        }
        written = written + n;
    }
    file_close(fd);
    return true;
}

fn http_download_ex(string url, string path, string headers, int timeout_ms) -> bool {
    HttpResponse resp = http_request_ex("GET", url, "", "", headers, true, timeout_ms, true);
    if (resp.error != "") { return false; }
    if (!resp.ok) { return false; }
    return http_save_response(resp, path);
}

fn http_download(string url, string path) -> bool {
    return http_download_ex(url, path, "", 30000);
}

fn http_upload_file_ex(string url, string field_name, string file_path, string extra_headers) -> HttpResponse {
    if (!file_exists(file_path)) {
        return _http_error_response("file not found");
    }
    int size = file_size(file_path);
    if (size < 0) { return _http_error_response("cannot stat file"); }
    int fd = file_open(file_path, "r");
    if (fd < 0) { return _http_error_response("cannot open file"); }
    char* content = alloc<char>(size + 1);
    int total = 0;
    while (total < size) {
        int n = file_read_bytes(fd, content + total, size - total);
        if (n <= 0) { break; }
        total = total + n;
    }
    file_close(fd);

    HttpMultipart m = http_multipart_new();
    http_multipart_add_file(m, field_name, file_basename(file_path), _http_mime_type(file_path), content, total);
    http_multipart_finish(m);
    HttpResponse resp = http_request_bytes_ex("POST", url, m.data, m.length, http_multipart_content_type(m), extra_headers, true, 60000, true);
    http_multipart_free(m);
    free(content);
    return resp;
}

fn http_upload_file(string url, string field_name, string file_path) -> HttpResponse {
    return http_upload_file_ex(url, field_name, file_path, "");
}

fn http_probe_ex(string url, string headers, int timeout_ms) -> int {
    HttpResponse resp = http_request_ex("GET", url, "", "", headers, true, timeout_ms, true);
    if (resp.error != "") { return -1; }
    return resp.status_code;
}

fn http_probe(string url) -> int {
    return http_probe_ex(url, "", 8000);
}

fn http_body_contains(string body, string needle) -> bool {
    return _http_contains_ci(body, needle);
}

fn http_html_title(string html) -> string {
    if (html == null) { return ""; }
    string lower = str_to_lower(html);
    int open_tag = str_index_of(lower, "<title");
    if (open_tag < 0) { return ""; }
    int gt = str_index_of(_http_slice(lower, open_tag, len(lower)), ">");
    if (gt < 0) { return ""; }
    int content_start = open_tag + gt + 1;
    int close_tag = str_index_of(_http_slice(lower, content_start, len(lower)), "</title>");
    if (close_tag < 0) { return ""; }
    return str_trim(_http_slice(html, content_start, content_start + close_tag));
}

fn http_status_class(int status) -> int {
    return status / 100;
}

fn http_is_success(int status) -> bool {
    return status >= 200 && status < 300;
}

fn http_is_redirect(int status) -> bool {
    return status >= 300 && status < 400;
}

fn http_is_client_error(int status) -> bool {
    return status >= 400 && status < 500;
}

fn http_is_server_error(int status) -> bool {
    return status >= 500 && status < 600;
}

// ============================================================================
// Server-side helpers (incoming requests + responses)
// ============================================================================

fn http_request_header(HttpRequest req, string name) -> string {
    return _http_header_value(req.headers, name);
}

fn http_request_query(HttpRequest req, string key) -> string {
    return url_query_get(req.query, key);
}

fn http_request_cookie(HttpRequest req, string name) -> string {
    return http_cookie_header_get(_http_header_value(req.headers, "Cookie"), name);
}

fn http_request_json_string(HttpRequest req, string key) -> string {
    return http_json_get_string(req.body, key);
}

fn http_request_json_int(HttpRequest req, string key) -> int {
    return http_json_get_int(req.body, key);
}

fn http_request_form(HttpRequest req, string key) -> string {
    return url_query_get(req.body, key);
}

fn http_send_response_ex(int client_fd, int status, string content_type, char* body, int body_length, string extra_headers) -> int {
    if (client_fd < 0) { return -1; }
    if (content_type == null || len(content_type) == 0) {
        content_type = "text/plain; charset=utf-8";
    }
    if (body_length < 0) { body_length = 0; }

    ByteBuffer out;
    out.init(512);
    out.append_str("HTTP/1.1 ");
    out.append_int(status);
    out.append_str(" ");
    out.append_str(http_status_text(status));
    out.append_str("\r\nServer: MagnetarHTTP/1.1\r\n");
    if (len(extra_headers) > 0) {
        out.append_str(extra_headers);
        int n = len(extra_headers);
        char last = *(cast<char*>(extra_headers) + n - 1);
        if (last != 10) { out.append_str("\r\n"); }
    }
    out.append_str("Content-Type: ");
    out.append_str(content_type);
    out.append_str("\r\nContent-Length: ");
    out.append_int(body_length);
    out.append_str("\r\nConnection: close\r\n\r\n");
    if (body_length > 0 && body != null) { out.append(body, body_length); }

    int sent = net_send_all(client_fd, out.data, out.length);
    out.free_buffer();
    return sent;
}

fn http_send_text_ex(int client_fd, int status, string text, string extra_headers) -> int {
    return http_send_response_ex(client_fd, status, "text/plain; charset=utf-8", cast<char*>(text), len(text), extra_headers);
}

fn http_send_json_ex(int client_fd, int status, string json, string extra_headers) -> int {
    return http_send_response_ex(client_fd, status, "application/json", cast<char*>(json), len(json), extra_headers);
}

fn http_send_redirect(int client_fd, string location, int status) -> int {
    if (status <= 0) { status = 302; }
    string headers = str_concat("Location: ", str_concat(location, "\r\n"));
    return http_send_response_ex(client_fd, status, "text/plain; charset=utf-8", null, 0, headers);
}

fn http_send_file(int client_fd, string path, string content_type) -> int {
    if (!file_exists(path)) {
        return http_send_text(client_fd, 404, "Not Found");
    }
    int size = file_size(path);
    int fd = file_open(path, "r");
    if (fd < 0 || size < 0) {
        if (fd >= 0) { file_close(fd); }
        return http_send_text(client_fd, 500, "Cannot open file");
    }
    char* content = alloc<char>(size + 1);
    int total = 0;
    while (total < size) {
        int n = file_read_bytes(fd, content + total, size - total);
        if (n <= 0) { break; }
        total = total + n;
    }
    file_close(fd);
    if (len(content_type) == 0) { content_type = _http_mime_type(path); }
    int sent = http_send_response_ex(client_fd, 200, content_type, content, total, "");
    free(content);
    return sent;
}

fn http_send_cors_preflight(int client_fd, string allow_origin, string allow_methods, string allow_headers) -> int {
    if (len(allow_origin) == 0) { allow_origin = "*"; }
    if (len(allow_methods) == 0) { allow_methods = "GET, POST, PUT, DELETE, HEAD, OPTIONS"; }
    if (len(allow_headers) == 0) { allow_headers = "Content-Type, Authorization"; }
    string headers = str_concat("Access-Control-Allow-Origin: ", str_concat(allow_origin, "\r\n"));
    headers = str_concat(headers, str_concat("Access-Control-Allow-Methods: ", str_concat(allow_methods, "\r\n")));
    headers = str_concat(headers, str_concat("Access-Control-Allow-Headers: ", str_concat(allow_headers, "\r\n")));
    headers = str_concat(headers, "Access-Control-Max-Age: 86400\r\n");
    return http_send_response_ex(client_fd, 204, "text/plain; charset=utf-8", null, 0, headers);
}

// ============================================================================
// WebSocket handshake helpers (RFC 6455)
// ============================================================================

fn http_websocket_accept(string client_key) -> string {
    string combined = str_concat(client_key, "258EAFA5-E914-47DA-95CA-C5AB0DC85B11");
    char* digest = alloc<char>(20);
    crypto_sha1_raw(cast<char*>(combined), len(combined), digest);
    string encoded = crypto_base64_encode(digest, 20);
    free(digest);
    return encoded;
}

fn http_websocket_is_upgrade(HttpRequest req) -> bool {
    string upgrade = _http_header_value(req.headers, "Upgrade");
    string connection = _http_header_value(req.headers, "Connection");
    return _http_contains_ci(upgrade, "websocket") && _http_contains_ci(connection, "upgrade");
}

fn http_websocket_handshake_response(int client_fd, string client_key) -> int {
    string accept = http_websocket_accept(client_key);
    string response = "HTTP/1.1 101 Switching Protocols\r\n";
    response = str_concat(response, "Upgrade: websocket\r\n");
    response = str_concat(response, "Connection: Upgrade\r\n");
    response = str_concat(response, str_concat("Sec-WebSocket-Accept: ", str_concat(accept, "\r\n\r\n")));
    return net_send_all(client_fd, cast<char*>(response), len(response));
}
