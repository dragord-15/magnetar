use "lib/http.mg";
use "lib/file.mg";
use "lib/string.mg";
use "lib/url.mg";

extern fn print_str(string s) -> void;
extern fn sys_open(string path, int flags, int mode) -> int;
extern fn sys_close(int fd) -> int;
extern fn sys_getdents64(int fd, char* dirp, int count) -> int;
extern fn sys_getcwd(char* buf, int size) -> int;
extern fn sys_mkdir(string path, int mode) -> int;
extern fn sys_unlink(string path) -> int;
extern fn sys_rmdir(string path) -> int;
extern fn sys_fork() -> int;
extern fn sys_dup2(int oldfd, int newfd) -> int;
extern fn sys_execve(string path, char** argv, char** envp) -> int;
extern fn sys_wait4(int pid, int* wstatus, int options, char* rusage) -> int;
extern fn sys_exit(int code) -> void;

static char* SRV_PUBLIC;
static char* SRV_ROOT;
static char* SRV_BUF;
static char* SRV_PATH;
static char* SRV_PATH2;
static char* SRV_JSON;
static char* SRV_ENV_BUF;
static char** SRV_ENV_PTRS;
static int SRV_ENV_COUNT;

fn s_byte(char* p, int i) -> int {
    int v = cast<int>(*(p + i));
    if (v < 0) { v = v + 256; }
    return v;
}

fn s_len(char* p) -> int {
    int n = 0;
    while (*(p + n) != 0) { n = n + 1; }
    return n;
}

fn s_copy(char* dst, int cap, string src) -> void {
    if (cap <= 0) { return; }
    char* p = cast<char*>(src);
    int n = s_len(p);
    if (n > cap - 1) { n = cap - 1; }
    int i = 0;
    while (i < n) { *(dst + i) = *(p + i); i = i + 1; }
    *(dst + n) = 0;
}

fn s_append(char* dst, int cap, int at, string src) -> int {
    char* p = cast<char*>(src);
    int i = 0;
    while (*(p + i) != 0 && at < cap - 1) {
        *(dst + at) = *(p + i);
        at = at + 1;
        i = i + 1;
    }
    *(dst + at) = 0;
    return at;
}

fn s_eq(string a, string b) -> bool {
    char* pa = cast<char*>(a);
    char* pb = cast<char*>(b);
    int i = 0;
    while (*(pa + i) != 0 && *(pb + i) != 0) {
        if (*(pa + i) != *(pb + i)) { return false; }
        i = i + 1;
    }
    if (*(pa + i) != *(pb + i)) { return false; }
    return true;
}

fn s_starts(string s, string pre) -> bool {
    char* ps = cast<char*>(s);
    char* pp = cast<char*>(pre);
    int i = 0;
    while (*(pp + i) != 0) {
        if (*(ps + i) != *(pp + i)) { return false; }
        i = i + 1;
    }
    return true;
}

fn s_join(char* out, int cap, string a, string b) -> void {
    int at = 0;
    at = s_append(out, cap, at, a);
    at = s_append(out, cap, at, b);
}

fn s_join3(char* out, int cap, string a, string b, string c) -> void {
    int at = 0;
    at = s_append(out, cap, at, a);
    at = s_append(out, cap, at, b);
    at = s_append(out, cap, at, c);
}

fn is_safe_path(string path) -> bool {
    char* p = cast<char*>(path);
    int i = 0;
    while (*(p + i) != 0) {
        if (*(p + i) == 46 && *(p + i + 1) == 46) { return false; }
        i = i + 1;
    }
    return true;
}

fn resolve_public(string rel, char* out, int cap) -> int {
    s_join3(out, cap, cast<string>(SRV_PUBLIC), "/", rel);
    if (file_is_file(cast<string>(out)) == true) { return 1; }
    s_join3(out, cap, "webedit/public", "/", rel);
    if (file_is_file(cast<string>(out)) == true) { return 1; }
    s_join3(out, cap, "public", "/", rel);
    if (file_is_file(cast<string>(out)) == true) { return 1; }
    return 0;
}

fn mime_for(string path) -> string {
    if (str_ends_with(path, ".html")) { return "text/html; charset=utf-8"; }
    if (str_ends_with(path, ".htm")) { return "text/html; charset=utf-8"; }
    if (str_ends_with(path, ".css")) { return "text/css; charset=utf-8"; }
    if (str_ends_with(path, ".js")) { return "application/javascript; charset=utf-8"; }
    if (str_ends_with(path, ".json")) { return "application/json; charset=utf-8"; }
    if (str_ends_with(path, ".svg")) { return "image/svg+xml"; }
    if (str_ends_with(path, ".png")) { return "image/png"; }
    if (str_ends_with(path, ".jpg") || str_ends_with(path, ".jpeg")) { return "image/jpeg"; }
    if (str_ends_with(path, ".mg")) { return "text/plain; charset=utf-8"; }
    if (str_ends_with(path, ".md")) { return "text/plain; charset=utf-8"; }
    if (str_ends_with(path, ".txt")) { return "text/plain; charset=utf-8"; }
    return "application/octet-stream";
}

fn json_str(string s) -> string {
    return http_json_escape(s);
}

fn send_json_ok(int fd, string payload) -> void {
    http_send_json_ex(fd, 200, payload, "Access-Control-Allow-Origin: *\r\nCache-Control: no-store\r\n");
}

fn send_json_err(int fd, int code, string msg) -> void {
    int at = 0;
    at = s_append(SRV_JSON, 65536, at, "{\"ok\":false,\"error\":\"");
    at = s_append(SRV_JSON, 65536, at, json_str(msg));
    at = s_append(SRV_JSON, 65536, at, "\"}");
    http_send_json_ex(fd, code, cast<string>(SRV_JSON), "Access-Control-Allow-Origin: *\r\nCache-Control: no-store\r\n");
}

fn api_ping(int fd) -> void {
    send_json_ok(fd, "{\"ok\":true,\"name\":\"Magnetar WebEdit\",\"version\":\"1.0\"}");
}

fn api_cwd(int fd) -> void {
    char* cwd = alloc<char>(1024);
    *(cwd) = 0;
    if (sys_getcwd(cwd, 1023) <= 0) { s_copy(cwd, 1024, "."); }
    int at = 0;
    at = s_append(SRV_JSON, 65536, at, "{\"ok\":true,\"cwd\":\"");
    at = s_append(SRV_JSON, 65536, at, json_str(cast<string>(cwd)));
    at = s_append(SRV_JSON, 65536, at, "\",\"root\":\"");
    at = s_append(SRV_JSON, 65536, at, json_str(cast<string>(SRV_ROOT)));
    at = s_append(SRV_JSON, 65536, at, "\"}");
    send_json_ok(fd, cast<string>(SRV_JSON));
    free(cwd);
}

fn api_list(int fd, string path) -> void {
    if (len(path) == 0) { path = "."; }
    if (is_safe_path(path) == false) { send_json_err(fd, 400, "Invalid path"); return; }
    if (file_is_dir(path) == false) { send_json_err(fd, 404, "Not a directory"); return; }
    int dfd = sys_open(path, 0, 0);
    if (dfd < 0) { send_json_err(fd, 500, "Cannot open directory"); return; }
    char* dbuf = alloc<char>(8192);
    int at = 0;
    at = s_append(SRV_JSON, 65536, at, "{\"ok\":true,\"path\":\"");
    at = s_append(SRV_JSON, 65536, at, json_str(path));
    at = s_append(SRV_JSON, 65536, at, "\",\"entries\":[");
    int first = 1;
    int nread = sys_getdents64(dfd, dbuf, 8192);
    while (nread > 0) {
        int pos = 0;
        while (pos < nread) {
            int lo = s_byte(dbuf, pos + 16);
            int hi = s_byte(dbuf, pos + 17);
            int reclen = lo + hi * 256;
            int dtype = s_byte(dbuf, pos + 18);
            char* name = dbuf + pos + 19;
            int c0 = s_byte(name, 0);
            if (c0 != 46 || (s_byte(name, 1) != 0 && !(s_byte(name, 1) == 46 && s_byte(name, 2) == 0))) {
                if (c0 != 46) {
                    if (first == 0) { at = s_append(SRV_JSON, 65536, at, ","); }
                    first = 0;
                    char* full = alloc<char>(2048);
                    if (s_eq(path, ".")) { s_copy(full, 2048, cast<string>(name)); }
                    else if (s_eq(path, "/")) { s_join(full, 2048, "/", cast<string>(name)); }
                    else { s_join3(full, 2048, path, "/", cast<string>(name)); }
                    string kind = "file";
                    if (dtype == 4) { kind = "dir"; }
                    else if (dtype == 0) {
                        if (file_is_dir(cast<string>(full)) == true) { kind = "dir"; }
                    }
                    at = s_append(SRV_JSON, 65536, at, "{\"name\":\"");
                    at = s_append(SRV_JSON, 65536, at, json_str(cast<string>(name)));
                    at = s_append(SRV_JSON, 65536, at, "\",\"path\":\"");
                    at = s_append(SRV_JSON, 65536, at, json_str(cast<string>(full)));
                    at = s_append(SRV_JSON, 65536, at, "\",\"type\":\"");
                    at = s_append(SRV_JSON, 65536, at, kind);
                    at = s_append(SRV_JSON, 65536, at, "\"}");
                    free(full);
                }
            }
            if (reclen <= 0) { break; }
            pos = pos + reclen;
        }
        nread = sys_getdents64(dfd, dbuf, 8192);
    }
    at = s_append(SRV_JSON, 65536, at, "]}");
    sys_close(dfd);
    free(dbuf);
    send_json_ok(fd, cast<string>(SRV_JSON));
}

fn api_read(int fd, string path) -> void {
    if (len(path) == 0) { send_json_err(fd, 400, "Missing path"); return; }
    if (is_safe_path(path) == false) { send_json_err(fd, 400, "Invalid path"); return; }
    if (file_is_file(path) == false) { send_json_err(fd, 404, "Not a file"); return; }
    int sz = file_size(path);
    if (sz > 1500000) { send_json_err(fd, 413, "File too large"); return; }
    string data = file_read_all(path);
    int at = 0;
    at = s_append(SRV_JSON, 131072, at, "{\"ok\":true,\"path\":\"");
    at = s_append(SRV_JSON, 131072, at, json_str(path));
    at = s_append(SRV_JSON, 131072, at, "\",\"content\":\"");
    at = s_append(SRV_JSON, 131072, at, json_str(data));
    at = s_append(SRV_JSON, 131072, at, "\"}");
    send_json_ok(fd, cast<string>(SRV_JSON));
    if (len(data) > 0) { free(cast<char*>(data)); }
}

fn api_save(int fd, HttpRequest req, string path) -> void {
    if (len(path) == 0) { send_json_err(fd, 400, "Missing path"); return; }
    if (is_safe_path(path) == false) { send_json_err(fd, 400, "Invalid path"); return; }
    string body = req.body;
    if (req.body_data != null) { body = cast<string>(req.body_data); }
    bool ok = file_write_all(path, body);
    if (ok == false) { send_json_err(fd, 500, "Write failed"); return; }
    int at = 0;
    at = s_append(SRV_JSON, 4096, at, "{\"ok\":true,\"path\":\"");
    at = s_append(SRV_JSON, 4096, at, json_str(path));
    at = s_append(SRV_JSON, 4096, at, "\"}");
    send_json_ok(fd, cast<string>(SRV_JSON));
}

fn api_mkdir(int fd, string path) -> void {
    if (len(path) == 0) { send_json_err(fd, 400, "Missing path"); return; }
    if (is_safe_path(path) == false) { send_json_err(fd, 400, "Invalid path"); return; }
    int r = sys_mkdir(path, 493);
    if (r != 0 && file_is_dir(path) == false) { send_json_err(fd, 500, "mkdir failed"); return; }
    send_json_ok(fd, "{\"ok\":true}");
}

fn api_delete(int fd, string path) -> void {
    if (len(path) == 0) { send_json_err(fd, 400, "Missing path"); return; }
    if (is_safe_path(path) == false) { send_json_err(fd, 400, "Invalid path"); return; }
    if (file_is_dir(path) == true) {
        if (sys_rmdir(path) != 0) { send_json_err(fd, 500, "rmdir failed"); return; }
    } else {
        if (sys_unlink(path) != 0) { send_json_err(fd, 500, "unlink failed"); return; }
    }
    send_json_ok(fd, "{\"ok\":true}");
}

fn contains_sub(char* hay, int hlen, char* needle, int nlen) -> int {
    if (nlen == 0) { return 1; }
    if (nlen > hlen) { return 0; }
    int i = 0;
    while (i + nlen <= hlen) {
        int k = 0;
        int ok = 1;
        while (k < nlen) {
            if (*(hay + i + k) != *(needle + k)) { ok = 0; break; }
            k = k + 1;
        }
        if (ok == 1) { return 1; }
        i = i + 1;
    }
    return 0;
}

fn api_search(int fd, string dir, string q) -> void {
    if (len(dir) == 0) { dir = "."; }
    if (len(q) == 0) { send_json_err(fd, 400, "Missing query"); return; }
    if (is_safe_path(dir) == false) { send_json_err(fd, 400, "Invalid path"); return; }
    char* needle = cast<char*>(q);
    int nlen = s_len(needle);
    int dfd = sys_open(dir, 0, 0);
    if (dfd < 0) { send_json_err(fd, 404, "Cannot open directory"); return; }
    char* dbuf = alloc<char>(8192);
    int at = 0;
    at = s_append(SRV_JSON, 65536, at, "{\"ok\":true,\"results\":[");
    int first = 1;
    int count = 0;
    int nread = sys_getdents64(dfd, dbuf, 8192);
    while (nread > 0 && count < 50) {
        int pos = 0;
        while (pos < nread && count < 50) {
            int lo = s_byte(dbuf, pos + 16);
            int hi = s_byte(dbuf, pos + 17);
            int reclen = lo + hi * 256;
            int dtype = s_byte(dbuf, pos + 18);
            char* name = dbuf + pos + 19;
            if (s_byte(name, 0) != 46 && dtype != 4) {
                char* full = alloc<char>(2048);
                if (s_eq(dir, ".")) { s_copy(full, 2048, cast<string>(name)); }
                else { s_join3(full, 2048, dir, "/", cast<string>(name)); }
                if (file_is_file(cast<string>(full)) == true && file_size(cast<string>(full)) < 200000) {
                    string data = file_read_all(cast<string>(full));
                    char* dp = cast<char*>(data);
                    int dlen = s_len(dp);
                    if (contains_sub(dp, dlen, needle, nlen) == 1) {
                        if (first == 0) { at = s_append(SRV_JSON, 65536, at, ","); }
                        first = 0;
                        at = s_append(SRV_JSON, 65536, at, "{\"path\":\"");
                        at = s_append(SRV_JSON, 65536, at, json_str(cast<string>(full)));
                        at = s_append(SRV_JSON, 65536, at, "\",\"name\":\"");
                        at = s_append(SRV_JSON, 65536, at, json_str(cast<string>(name)));
                        at = s_append(SRV_JSON, 65536, at, "\"}");
                        count = count + 1;
                    }
                    if (len(data) > 0) { free(cast<char*>(data)); }
                }
                free(full);
            }
            if (reclen <= 0) { break; }
            pos = pos + reclen;
        }
        nread = sys_getdents64(dfd, dbuf, 8192);
    }
    at = s_append(SRV_JSON, 65536, at, "]}");
    sys_close(dfd);
    free(dbuf);
    send_json_ok(fd, cast<string>(SRV_JSON));
}

fn srv_build_envp(int n) -> void {
    SRV_ENV_COUNT = 0;
    int i = 0;
    while (i < n && SRV_ENV_COUNT < 250) {
        if (s_byte(SRV_ENV_BUF, i) != 0) {
            SRV_ENV_PTRS[SRV_ENV_COUNT] = SRV_ENV_BUF + i;
            SRV_ENV_COUNT = SRV_ENV_COUNT + 1;
        }
        while (i < n && s_byte(SRV_ENV_BUF, i) != 0) { i = i + 1; }
        i = i + 1;
    }
    SRV_ENV_PTRS[SRV_ENV_COUNT] = null;
    if (SRV_ENV_COUNT == 0) {
        SRV_ENV_PTRS[0] = cast<char*>("PATH=/usr/local/bin:/usr/bin:/bin");
        SRV_ENV_PTRS[1] = null;
        SRV_ENV_COUNT = 1;
    }
}

fn srv_load_env() -> void {
    SRV_ENV_COUNT = 0;
    int fd = sys_open("/proc/self/environ", 0, 0);
    if (fd < 0) { srv_build_envp(0); return; }
    int n = sys_read(fd, SRV_ENV_BUF, 8191);
    sys_close(fd);
    if (n <= 0) { srv_build_envp(0); return; }
    srv_build_envp(n);
}

fn i2s(int v) -> string {
    char* buf = alloc<char>(32);
    int neg = 0;
    if (v < 0) { neg = 1; v = 0 - v; }
    int i = 0;
    if (v == 0) { *(buf) = 48; i = 1; }
    else {
        char* tmp = alloc<char>(32);
        int t = 0;
        while (v > 0) {
            *(tmp + t) = cast<char>(48 + (v - (v / 10) * 10));
            v = v / 10;
            t = t + 1;
        }
        if (neg == 1) { *(buf + i) = 45; i = i + 1; }
        int k = t - 1;
        while (k >= 0) { *(buf + i) = *(tmp + k); i = i + 1; k = k - 1; }
        free(tmp);
    }
    *(buf + i) = 0;
    return cast<string>(buf);
}

fn api_build(int fd, string path) -> void {
    if (len(path) == 0) { send_json_err(fd, 400, "Missing path"); return; }
    if (is_safe_path(path) == false) { send_json_err(fd, 400, "Invalid path"); return; }
    if (file_is_file(path) == false) { send_json_err(fd, 404, "File not found"); return; }
    if (SRV_ENV_COUNT == 0) { srv_load_env(); }
    string outp = "/tmp/webedit_build";
    string logp = "/tmp/webedit_build.log";
    int lfd = sys_open(logp, 577, 420);
    int pid = sys_fork();
    if (pid == 0) {
        if (lfd >= 0) {
            sys_dup2(lfd, 1);
            sys_dup2(lfd, 2);
            if (lfd > 2) { sys_close(lfd); }
        }
        char** argv = alloc<char*>(12);
        argv[0] = cast<char*>("magc");
        argv[1] = cast<char*>(path);
        argv[2] = cast<char*>("-o");
        argv[3] = cast<char*>(outp);
        argv[4] = null;
        sys_execve("/usr/local/bin/magc", argv, SRV_ENV_PTRS);
        sys_execve("/usr/bin/magc", argv, SRV_ENV_PTRS);
        char** eargv = alloc<char*>(12);
        eargv[0] = cast<char*>("env");
        eargv[1] = cast<char*>("magc");
        eargv[2] = cast<char*>(path);
        eargv[3] = cast<char*>("-o");
        eargv[4] = cast<char*>(outp);
        eargv[5] = null;
        sys_execve("/usr/bin/env", eargv, SRV_ENV_PTRS);
        sys_exit(127);
    }
    if (lfd >= 0) { sys_close(lfd); }
    int status = 0;
    sys_wait4(pid, &status, 0, null);
    int code = status / 256;
    string logtxt = "";
    if (file_is_file(logp) == true) { logtxt = file_read_all(logp); }
    int at = 0;
    at = s_append(SRV_JSON, 131072, at, "{\"ok\":");
    if (code == 0) { at = s_append(SRV_JSON, 131072, at, "true"); }
    else { at = s_append(SRV_JSON, 131072, at, "false"); }
    at = s_append(SRV_JSON, 131072, at, ",\"code\":");
    at = s_append(SRV_JSON, 131072, at, i2s(code));
    at = s_append(SRV_JSON, 131072, at, ",\"output\":\"");
    at = s_append(SRV_JSON, 131072, at, json_str(logtxt));
    at = s_append(SRV_JSON, 131072, at, "\"}");
    send_json_ok(fd, cast<string>(SRV_JSON));
    if (len(logtxt) > 0) { free(cast<char*>(logtxt)); }
}

fn serve_static(int fd, string req_path) -> int {
    string rel = req_path;
    if (s_eq(req_path, "/")) { rel = "index.html"; }
    else {
        // strip leading /
        char* p = cast<char*>(req_path);
        if (*(p) == 47) { rel = cast<string>(p + 1); }
    }
    // block traversal
    char* rp = cast<char*>(rel);
    int i = 0;
    while (*(rp + i) != 0) {
        if (*(rp + i) == 46 && *(rp + i + 1) == 46) { return 0; }
        i = i + 1;
    }
    if (resolve_public(rel, SRV_PATH, 2048) == 0) { return 0; }
    string ctype = mime_for(cast<string>(SRV_PATH));
    http_send_file(fd, cast<string>(SRV_PATH), ctype);
    return 1;
}

fn handle_request(int fd, HttpRequest req) -> void {
    string path = req.path;
    string method = req.method;
    print_str(method);
    print_str(" ");
    print_str(path);
    print_str("\n");

    if (s_eq(method, "OPTIONS")) {
        http_send_response_ex(fd, 204, "text/plain", null, 0, "Access-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET,POST,OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type,X-Path\r\nAccess-Control-Max-Age: 86400\r\n");
        return;
    }

    if (s_starts(path, "/api/")) {
        string qpath = url_decode(url_query_get(req.query, "path"));
        if (s_eq(path, "/api/ping")) { api_ping(fd); return; }
        if (s_eq(path, "/api/cwd")) { api_cwd(fd); return; }
        if (s_eq(path, "/api/list")) { api_list(fd, qpath); return; }
        if (s_eq(path, "/api/read")) { api_read(fd, qpath); return; }
        if (s_eq(path, "/api/save") && s_eq(method, "POST")) { api_save(fd, req, qpath); return; }
        if (s_eq(path, "/api/mkdir") && s_eq(method, "POST")) { api_mkdir(fd, qpath); return; }
        if (s_eq(path, "/api/delete") && s_eq(method, "POST")) { api_delete(fd, qpath); return; }
        if (s_eq(path, "/api/search")) {
            string q = url_decode(url_query_get(req.query, "q"));
            api_search(fd, qpath, q);
            return;
        }
        if (s_eq(path, "/api/build") && s_eq(method, "POST")) { api_build(fd, qpath); return; }
        send_json_err(fd, 404, "Unknown API endpoint");
        return;
    }

    if (serve_static(fd, path) == 1) { return; }
    // SPA fallback
    if (resolve_public("index.html", SRV_PATH, 2048) == 1) {
        http_send_file(fd, cast<string>(SRV_PATH), "text/html; charset=utf-8");
        return;
    }
    http_send_text_ex(fd, 404, "Not Found", "Access-Control-Allow-Origin: *\r\n");
}

fn main() -> int {
    SRV_PUBLIC = alloc<char>(1024);
    SRV_ROOT = alloc<char>(1024);
    SRV_BUF = alloc<char>(8192);
    SRV_PATH = alloc<char>(2048);
    SRV_PATH2 = alloc<char>(2048);
    SRV_JSON = alloc<char>(131072);
    SRV_ENV_BUF = alloc<char>(8192);
    SRV_ENV_PTRS = alloc<char*>(256);
    *(SRV_ENV_BUF) = 0;
    SRV_ENV_COUNT = 0;

    *(SRV_ROOT) = 0;
    if (sys_getcwd(SRV_ROOT, 1023) <= 0) { s_copy(SRV_ROOT, 1024, "."); }

    // detect public dir
    s_copy(SRV_PUBLIC, 1024, "public");
    if (file_is_dir("public") == false) {
        if (file_is_dir("webedit/public") == true) { s_copy(SRV_PUBLIC, 1024, "webedit/public"); }
    }

    srv_load_env();

    int port = 8765;
    TcpServer server;
    if (!server.start(port, 32)) {
        print_str("Cannot bind 0.0.0.0:8765\n");
        return 1;
    }
    print_str("Magnetar WebEdit server running at http://127.0.0.1:8765\n");
    print_str("Public dir: ");
    print_str(cast<string>(SRV_PUBLIC));
    print_str("\nRoot: ");
    print_str(cast<string>(SRV_ROOT));
    print_str("\n");

    while (true) {
        int cfd = server.accept_connection();
        if (cfd < 0) { continue; }
        HttpRequest req = http_read_request(cfd, 10000);
        if (!req.valid) {
            http_send_text_ex(cfd, 400, "Bad Request", "Access-Control-Allow-Origin: *\r\n");
            net_close(cfd);
            continue;
        }
        handle_request(cfd, req);
        net_close(cfd);
    }
    return 0;
}
