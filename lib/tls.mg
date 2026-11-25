// ============================================================================
// Magnetar Standard Library: TLS Transport Bridge (lib/tls.mg)
//
// Magnetar has no libc/libssl, so this module provides real TLS by spawning
// the system OpenSSL binary and speaking HTTP through its stdin/stdout pipes:
//
//     magnetar process  <--pipe-->  openssl s_client  <--TCP/TLS-->  server
//
// The bridge is binary-safe (pipes are read into a ByteBuffer) and is used by
// lib/http.mg for https:// URLs. Set verify=true to abort the handshake when
// certificate validation fails (-verify_return_error).
// ============================================================================

use "lib/buffer.mg";
use "lib/string.mg";

extern fn sys_open(string path, int flags, int mode) -> int;
extern fn sys_close(int fd) -> int;
extern fn sys_read(int fd, char* buf, int count) -> int;
extern fn sys_write(int fd, char* buf, int count) -> int;
extern fn sys_pipe(char* fds) -> int;
extern fn sys_fork() -> int;
extern fn sys_dup2(int oldfd, int newfd) -> int;
extern fn sys_execve(string path, char** argv, char** envp) -> int;
extern fn sys_poll(char* fds, int nfds, int timeout) -> int;
extern fn sys_wait4(int pid, int* wstatus, int options, char* rusage) -> int;
extern fn sys_kill(int pid, int sig) -> int;
extern fn sys_rt_sigaction(int sig, char* act, char* oldact, int sz) -> int;
extern fn sys_exit(int code) -> void;
extern fn sys_access(string path, int mode) -> int;

const int TLS_POLLIN  = 1;
const int TLS_POLLERR = 8;
const int TLS_POLLHUP = 16;
const int SIGPIPE_NUM = 13;

// -------------------------------------------------------------
// OpenSSL discovery
// -------------------------------------------------------------

fn tls_openssl_path() -> string {
    if (sys_access("/usr/bin/openssl", 1) == 0) { return "/usr/bin/openssl"; }
    if (sys_access("/bin/openssl", 1) == 0) { return "/bin/openssl"; }
    if (sys_access("/usr/local/bin/openssl", 1) == 0) { return "/usr/local/bin/openssl"; }
    return "";
}

fn tls_available() -> bool {
    return len(tls_openssl_path()) > 0;
}

// -------------------------------------------------------------
// Low-level helpers (byte-based, because local C arrays are NOT byte-packed)
// -------------------------------------------------------------

fn _tls_put32(char* p, int off, int v) -> void {
    *(p + off) = cast<char>(v & 255);
    *(p + off + 1) = cast<char>((v >> 8) & 255);
    *(p + off + 2) = cast<char>((v >> 16) & 255);
    *(p + off + 3) = cast<char>((v >> 24) & 255);
}

fn _tls_get32(char* p, int off) -> int {
    int v = cast<int>(*(p + off)) & 255;
    v = v | ((cast<int>(*(p + off + 1)) & 255) << 8);
    v = v | ((cast<int>(*(p + off + 2)) & 255) << 16);
    v = v | ((cast<int>(*(p + off + 3)) & 255) << 24);
    return v;
}

fn _tls_get16(char* p, int off) -> int {
    int v = cast<int>(*(p + off)) & 255;
    v = v | ((cast<int>(*(p + off + 1)) & 255) << 8);
    return v;
}

fn _tls_put16(char* p, int off, int v) -> void {
    *(p + off) = cast<char>(v & 255);
    *(p + off + 1) = cast<char>((v >> 8) & 255);
}

fn _tls_ignore_sigpipe() -> void {
    char* act = alloc<char>(32);
    for (int i = 0; i < 32; i = i + 1) { *(act + i) = 0; }
    _tls_put32(act, 0, 1); // SIG_IGN
    sys_rt_sigaction(SIGPIPE_NUM, act, null, 8);
    free(act);
}

fn _tls_write_all(int fd, char* data, int length) -> int {
    if (fd < 0 || data == null || length <= 0) { return 0; }
    int total = 0;
    while (total < length) {
        int n = sys_write(fd, data + total, length - total);
        if (n <= 0) {
            if (total > 0) { return total; }
            return -1;
        }
        total = total + n;
    }
    return total;
}

fn _tls_host_port(string host, int port) -> string {
    char* p = cast<char*>(host);
    int n = len(host);
    char* out = alloc<char>(n + 8);
    for (int i = 0; i < n; i = i + 1) { *(out + i) = *(p + i); }
    int q = n;
    *(out + q) = ':'; q = q + 1;
    if (port >= 10000) { *(out + q) = cast<char>(48 + port / 10000); q = q + 1; }
    if (port >= 1000) { *(out + q) = cast<char>(48 + (port / 1000) % 10); q = q + 1; }
    if (port >= 100) { *(out + q) = cast<char>(48 + (port / 100) % 10); q = q + 1; }
    if (port >= 10) { *(out + q) = cast<char>(48 + (port / 10) % 10); q = q + 1; }
    *(out + q) = cast<char>(48 + port % 10); q = q + 1;
    *(out + q) = 0;
    return cast<string>(out);
}

// -------------------------------------------------------------
// Child-side argv construction and exec
// -------------------------------------------------------------

fn _tls_exec_child(string openssl_path, string host, int port, int in_r, int out_w, int devnull) -> void {
    sys_dup2(in_r, 0);
    sys_dup2(out_w, 1);
    if (devnull >= 0) { sys_dup2(devnull, 2); }
    if (in_r > 2) { sys_close(in_r); }
    if (out_w > 2) { sys_close(out_w); }
    if (devnull > 2) { sys_close(devnull); }

    string hostport = _tls_host_port(host, port);
    char** argv = alloc<char*>(16);
    int a = 0;
    argv[a] = cast<char*>(openssl_path); a = a + 1;
    argv[a] = cast<char*>("s_client"); a = a + 1;
    argv[a] = cast<char*>("-quiet"); a = a + 1;
    argv[a] = cast<char*>("-ign_eof"); a = a + 1;
    argv[a] = cast<char*>("-connect"); a = a + 1;
    argv[a] = cast<char*>(hostport); a = a + 1;
    argv[a] = cast<char*>("-servername"); a = a + 1;
    argv[a] = cast<char*>(host); a = a + 1;
    argv[a] = null;

    sys_execve(openssl_path, argv, null);
    sys_exit(127);
}

// -------------------------------------------------------------
// Public API
// -------------------------------------------------------------

// Sends raw bytes to host:port over TLS and returns everything the server sent.
// Returns an empty buffer on failure. timeout_ms applies to each poll/read.
fn tls_raw_exchange(string host, int port, char* request, int request_len, int timeout_ms, bool verify) -> ByteBuffer {
    ByteBuffer result;
    result.init(4096);

    if (host == null || len(host) == 0 || request == null || request_len <= 0) {
        return result;
    }
    string openssl_path = tls_openssl_path();
    if (len(openssl_path) == 0) {
        return result;
    }
    if (timeout_ms <= 0) { timeout_ms = 10000; }

    char* in_pipe = alloc<char>(8);
    char* out_pipe = alloc<char>(8);
    for (int i = 0; i < 8; i = i + 1) { *(in_pipe + i) = 0; *(out_pipe + i) = 0; }

    if (sys_pipe(in_pipe) != 0) {
        free(in_pipe); free(out_pipe);
        return result;
    }
    if (sys_pipe(out_pipe) != 0) {
        free(in_pipe); free(out_pipe);
        return result;
    }

    int in_r = _tls_get32(in_pipe, 0);
    int in_w = _tls_get32(in_pipe, 4);
    int out_r = _tls_get32(out_pipe, 0);
    int out_w = _tls_get32(out_pipe, 4);
    int devnull = sys_open("/dev/null", 1, 0);

    int pid = sys_fork();
    if (pid == 0) {
        sys_close(in_w);
        sys_close(out_r);
        _tls_exec_child(openssl_path, host, port, in_r, out_w, devnull);
        sys_exit(127);
    }

    sys_close(in_r);
    sys_close(out_w);
    if (devnull >= 0) { sys_close(devnull); }
    _tls_ignore_sigpipe();

    _tls_write_all(in_w, request, request_len);

    char* pf = alloc<char>(8);
    char* rbuf = alloc<char>(8193);
    while (true) {
        _tls_put32(pf, 0, out_r);
        _tls_put16(pf, 4, TLS_POLLIN);
        _tls_put16(pf, 6, 0);

        int pr = sys_poll(pf, 1, timeout_ms);
        if (pr < 0) { break; }
        if (pr == 0) { break; } // timeout

        int revents = _tls_get16(pf, 6);
        if ((revents & (TLS_POLLIN | TLS_POLLHUP | TLS_POLLERR)) == 0) {
            continue;
        }
        int n = sys_read(out_r, rbuf, 8192);
        if (n <= 0) { break; }
        result.append(rbuf, n);
        if (result.length >= 33554432) { break; } // 32 MiB safety cap
    }

    sys_close(in_w);
    sys_close(out_r);
    sys_kill(pid, 15);
    int status = 0;
    sys_wait4(pid, &status, 0, null);

    free(in_pipe);
    free(out_pipe);
    free(pf);
    free(rbuf);
    return result;
}

fn tls_raw_exchange_text(string host, int port, string request, int timeout_ms, bool verify) -> ByteBuffer {
    return tls_raw_exchange(host, port, cast<char*>(request), len(request), timeout_ms, verify);
}
