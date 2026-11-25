// ============================================================================
// Magnetar ADB Library (lib/adb.mg)
// Pure Magnetar Android Debug Bridge interface — no libc, no external libs.
//
// Controls Android phones via USB using fork+pipe+execve to call /usr/bin/adb.
// Provides: device discovery, shell commands, input injection, file transfer,
// and screen capture foundations for a phone mirroring application.
//
// Architecture:
//   magnetar process <--pipe--> /usr/bin/adb <--USB--> Android phone
//
// Usage:
//   use "lib/adb.mg";
//   if (adb_available()) {
//       string model = adb_get_prop("ro.product.model");
//       adb_input_tap(540, 960);
//   }
// ============================================================================

// ─── Syscall Externs ────────────────────────────────────────
extern fn sys_open(string path, int flags, int mode) -> int;
extern fn sys_close(int fd) -> int;
extern fn sys_read(int fd, char* buf, int count) -> int;
extern fn sys_write(int fd, char* data, int count) -> int;
extern fn sys_pipe(char* fds) -> int;
extern fn sys_fork() -> int;
extern fn sys_dup2(int oldfd, int newfd) -> int;
extern fn sys_execve(string path, char** argv, char** envp) -> int;
extern fn sys_wait4(int pid, int* wstatus, int options, char* rusage) -> int;
extern fn sys_kill(int pid, int sig) -> int;
extern fn sys_exit(int code) -> void;
extern fn sys_access(string path, int mode) -> int;
extern fn sys_rt_sigaction(int sig, char* act, char* oldact, int sz) -> int;
extern fn sys_poll(char* fds, int nfds, int timeout) -> int;
extern fn print_str(string s) -> void;
extern fn print_int(int n) -> void;
extern fn sleep_ms(int ms) -> void;

// ─── Constants ──────────────────────────────────────────────
const int ADB_PIPE_BUF = 65536;
const int ADB_MAX_OUTPUT = 262144;   // 256 KB max text output
const int ADB_READ_TIMEOUT = 10000;  // 10s timeout
const int ADB_SIGPIPE = 13;
const int ADB_POLLIN = 1;
const int ADB_POLLERR = 8;
const int ADB_POLLHUP = 16;

// ─── ADB Path Discovery ────────────────────────────────────

static string G_ADB_PATH = "";
static int G_ADB_CHECKED = 0;

fn adb_path() -> string {
    if (G_ADB_CHECKED == 1) {
        return G_ADB_PATH;
    }
    G_ADB_CHECKED = 1;
    // Check common ADB locations
    if (sys_access("/usr/bin/adb", 1) == 0) {
        G_ADB_PATH = "/usr/bin/adb";
        return G_ADB_PATH;
    }
    if (sys_access("/usr/local/bin/adb", 1) == 0) {
        G_ADB_PATH = "/usr/local/bin/adb";
        return G_ADB_PATH;
    }
    if (sys_access("/usr/lib/android-sdk/platform-tools/adb", 1) == 0) {
        G_ADB_PATH = "/usr/lib/android-sdk/platform-tools/adb";
        return G_ADB_PATH;
    }
    if (sys_access("/opt/android-sdk/platform-tools/adb", 1) == 0) {
        G_ADB_PATH = "/opt/android-sdk/platform-tools/adb";
        return G_ADB_PATH;
    }
    return "";
}

fn adb_available() -> bool {
    string p = adb_path();
    return _adb_strlen(p) > 0;
}

// ─── Internal Helpers ───────────────────────────────────────

fn _adb_byte(char* p, int i) -> int {
    int v = cast<int>(*(p + i));
    return v & 255;
}

fn _adb_get32(char* p, int off) -> int {
    int v = _adb_byte(p, off);
    v = v + _adb_byte(p, off + 1) * 256;
    v = v + _adb_byte(p, off + 2) * 65536;
    v = v + _adb_byte(p, off + 3) * 16777216;
    return v;
}

fn _adb_put32(char* p, int off, int v) -> void {
    *(p + off) = cast<char>(v & 255);
    *(p + off + 1) = cast<char>((v >> 8) & 255);
    *(p + off + 2) = cast<char>((v >> 16) & 255);
    *(p + off + 3) = cast<char>((v >> 24) & 255);
}

fn _adb_ignore_sigpipe() -> void {
    char* act = alloc<char>(32);
    for (int i = 0; i < 32; i = i + 1) { *(act + i) = 0; }
    _adb_put32(act, 0, 1); // SIG_IGN
    sys_rt_sigaction(ADB_SIGPIPE, act, null, 8);
    free(act);
}

// Convert integer to decimal string in pre-allocated buffer
// Returns length written
fn _adb_itoa(int val, char* buf) -> int {
    if (val == 0) {
        *buf = '0';
        *(buf + 1) = 0;
        return 1;
    }
    int neg = 0;
    int v = val;
    if (v < 0) {
        neg = 1;
        v = 0 - v;
    }
    // Write digits in reverse
    char* tmp = alloc<char>(24);
    int pos = 0;
    while (v > 0) {
        int digit = v - (v / 10) * 10;
        *(tmp + pos) = cast<char>(48 + digit);
        pos = pos + 1;
        v = v / 10;
    }
    int idx = 0;
    if (neg == 1) {
        *(buf + idx) = '-';
        idx = idx + 1;
    }
    // Reverse copy
    for (int j = pos - 1; j >= 0; j = j - 1) {
        *(buf + idx) = *(tmp + j);
        idx = idx + 1;
    }
    *(buf + idx) = 0;
    free(tmp);
    return idx;
}

// Copy string into buffer, return length
fn _adb_strcpy(char* dst, string src) -> int {
    char* s = cast<char*>(src);
    int i = 0;
    while (*(s + i) != 0) {
        *(dst + i) = *(s + i);
        i = i + 1;
    }
    *(dst + i) = 0;
    return i;
}

// String length
fn _adb_strlen(string s) -> int {
    char* p = cast<char*>(s);
    int n = 0;
    while (*(p + n) != 0) { n = n + 1; }
    return n;
}

// Build an argv array for: adb <args...>
// args is a space-separated argument string
// Returns allocated char** with null terminator
fn _adb_build_argv(string args) -> char** {
    char** argv = alloc<char*>(32);
    int argc = 0;

    // argv[0] = adb path
    argv[argc] = cast<char*>(adb_path());
    argc = argc + 1;

    // Parse space-separated arguments
    char* a = cast<char*>(args);
    int alen = _adb_strlen(args);

    int start = 0;
    int i = 0;
    while (i <= alen) {
        int ch = 0;
        if (i < alen) { ch = cast<int>(*(a + i)); }
        if (ch == 32 || ch == 0) {
            // End of token
            int tlen = i - start;
            if (tlen > 0 && argc < 30) {
                char* token = alloc<char>(tlen + 1);
                for (int k = 0; k < tlen; k = k + 1) {
                    *(token + k) = *(a + start + k);
                }
                *(token + tlen) = 0;
                argv[argc] = token;
                argc = argc + 1;
            }
            start = i + 1;
        }
        i = i + 1;
    }

    argv[argc] = null;
    return argv;
}

// Free the allocated tokens in argv (skip argv[0] = adb_path which is static)
fn _adb_free_argv(char** argv) -> void {
    int i = 1; // Start at 1, argv[0] is static string
    while (argv[i] != null) {
        free(argv[i]);
        i = i + 1;
    }
    free(argv);
}

// ─── Core Execution Engine ──────────────────────────────────

// Execute adb with the given arguments string (space-separated)
// Returns the stdout output as a string (up to ADB_MAX_OUTPUT bytes)
// On failure returns ""
fn adb_exec(string args) -> string {
    if (!adb_available()) {
        print_str("[ADB] Error: adb not found\n");
        return "";
    }

    _adb_ignore_sigpipe();

    // Create pipe for capturing stdout
    char* pfds = alloc<char>(8);
    for (int i = 0; i < 8; i = i + 1) { *(pfds + i) = 0; }

    if (sys_pipe(pfds) != 0) {
        print_str("[ADB] Error: pipe() failed\n");
        free(pfds);
        return "";
    }

    int rfd = _adb_get32(pfds, 0);
    int wfd = _adb_get32(pfds, 4);
    free(pfds);

    char** argv = _adb_build_argv(args);

    int pid = sys_fork();

    if (pid < 0) {
        print_str("[ADB] Error: fork() failed\n");
        sys_close(rfd);
        sys_close(wfd);
        _adb_free_argv(argv);
        return "";
    }

    if (pid == 0) {
        // ─── Child process ───
        sys_close(rfd);
        sys_dup2(wfd, 1);  // stdout → pipe write end
        // Redirect stderr to /dev/null
        int devnull = sys_open("/dev/null", 1, 0);
        if (devnull >= 0) {
            sys_dup2(devnull, 2);
            if (devnull > 2) { sys_close(devnull); }
        }
        if (wfd > 2) { sys_close(wfd); }

        sys_execve(adb_path(), argv, null);
        // If execve returns, it failed
        sys_exit(127);
    }

    // ─── Parent process ───
    sys_close(wfd);

    // Read all output from child stdout
    char* outbuf = alloc<char>(ADB_MAX_OUTPUT + 1);
    int total = 0;

    while (total < ADB_MAX_OUTPUT) {
        int n = sys_read(rfd, outbuf + total, ADB_MAX_OUTPUT - total);
        if (n <= 0) { break; }
        total = total + n;
    }

    sys_close(rfd);

    // Wait for child to finish
    int wstatus = 0;
    sys_wait4(pid, &wstatus, 0, null);

    _adb_free_argv(argv);

    // Null-terminate and return
    *(outbuf + total) = 0;
    if (total == 0) {
        free(outbuf);
        return "";
    }
    return cast<string>(outbuf);
}

// Execute adb and return raw binary data + length via pointer
// Caller must free the returned buffer
fn adb_exec_raw(string args, int* out_len) -> char* {
    if (!adb_available()) {
        *out_len = 0;
        return null;
    }

    _adb_ignore_sigpipe();

    char* pfds = alloc<char>(8);
    for (int i = 0; i < 8; i = i + 1) { *(pfds + i) = 0; }

    if (sys_pipe(pfds) != 0) {
        free(pfds);
        *out_len = 0;
        return null;
    }

    int rfd = _adb_get32(pfds, 0);
    int wfd = _adb_get32(pfds, 4);
    free(pfds);

    char** argv = _adb_build_argv(args);

    int pid = sys_fork();

    if (pid < 0) {
        sys_close(rfd);
        sys_close(wfd);
        _adb_free_argv(argv);
        *out_len = 0;
        return null;
    }

    if (pid == 0) {
        sys_close(rfd);
        sys_dup2(wfd, 1);
        int devnull = sys_open("/dev/null", 1, 0);
        if (devnull >= 0) {
            sys_dup2(devnull, 2);
            if (devnull > 2) { sys_close(devnull); }
        }
        if (wfd > 2) { sys_close(wfd); }
        sys_execve(adb_path(), argv, null);
        sys_exit(127);
    }

    sys_close(wfd);

    // Read raw binary data — up to 16 MB for screenshots
    int capacity = 16 * 1024 * 1024;
    char* outbuf = alloc<char>(capacity);
    int total = 0;

    while (total < capacity) {
        int n = sys_read(rfd, outbuf + total, ADB_PIPE_BUF);
        if (n <= 0) { break; }
        total = total + n;
    }

    sys_close(rfd);

    int wstatus = 0;
    sys_wait4(pid, &wstatus, 0, null);

    _adb_free_argv(argv);

    *out_len = total;
    if (total == 0) {
        free(outbuf);
        return null;
    }
    return outbuf;
}

// ─── Device Discovery ───────────────────────────────────────

// Returns the output of "adb devices" (list of connected devices)
fn adb_devices() -> string {
    return adb_exec("devices");
}

// Check if any device is connected
fn adb_device_connected() -> bool {
    string devs = adb_exec("devices");
    if (_adb_strlen(devs) == 0) { return false; }
    char* p = cast<char*>(devs);
    int slen = _adb_strlen(devs);
    for (int i = 0; i < slen; i = i + 1) {
        if (_adb_byte(p, i) == 9) { // TAB character
            return true;
        }
    }
    return false;
}

// Check if connected device is authorized (not in unauthorized or offline state)
fn adb_device_authorized() -> bool {
    string devs = adb_exec("devices");
    int slen = _adb_strlen(devs);
    if (slen == 0) { return false; }
    char* p = cast<char*>(devs);

    // Skip first header line ("List of devices attached")
    int i = 0;
    while (i < slen && _adb_byte(p, i) != 10) {
        i = i + 1;
    }
    if (i >= slen) { return false; }
    i = i + 1;

    // Scan the lines for "device" or "unauthorized"
    int found_unauth = 0;
    int found_device = 0;
    while (i < slen) {
        // "unauthorized"
        if (i <= slen - 12) {
            if (_adb_byte(p, i) == 117 && _adb_byte(p, i+1) == 110 && _adb_byte(p, i+2) == 97 &&
                _adb_byte(p, i+3) == 117 && _adb_byte(p, i+4) == 116 && _adb_byte(p, i+5) == 104) {
                found_unauth = 1;
            }
        }
        // "device"
        if (i <= slen - 6) {
            if (_adb_byte(p, i) == 100 && _adb_byte(p, i+1) == 101 && _adb_byte(p, i+2) == 118 &&
                _adb_byte(p, i+3) == 105 && _adb_byte(p, i+4) == 99 && _adb_byte(p, i+5) == 101) {
                found_device = 1;
            }
        }
        i = i + 1;
    }

    if (found_unauth == 1) {
        return false;
    }
    return found_device == 1;
}

// Get the serial number of the first connected device
fn adb_device_serial() -> string {
    string devs = adb_exec("devices");
    int slen = _adb_strlen(devs);
    if (slen == 0) { return ""; }
    char* p = cast<char*>(devs);

    // Skip first line ("List of devices attached\n")
    int start = 0;
    while (start < slen && _adb_byte(p, start) != 10) {
        start = start + 1;
    }
    if (start < slen && _adb_byte(p, start) == 10) {
        start = start + 1;
    }

    // Now start is at serial start
    int end = start;
    while (end < slen && _adb_byte(p, end) != 9 && _adb_byte(p, end) != 32 && _adb_byte(p, end) != 10) {
        end = end + 1;
    }

    int serial_len = end - start;
    if (serial_len <= 0) { return ""; }

    char* serial_buf = alloc<char>(serial_len + 1);
    for (int k = 0; k < serial_len; k = k + 1) {
        *(serial_buf + k) = cast<char>(_adb_byte(p, start + k));
    }
    *(serial_buf + serial_len) = 0;
    return cast<string>(serial_buf);
}

// ─── Shell Commands ─────────────────────────────────────────

// Execute a command on the connected Android device
fn adb_shell(string cmd) -> string {
    // Build: "shell <cmd>"
    int clen = _adb_strlen(cmd);
    char* full = alloc<char>(clen + 8);
    *(full + 0) = 's'; *(full + 1) = 'h'; *(full + 2) = 'e';
    *(full + 3) = 'l'; *(full + 4) = 'l'; *(full + 5) = ' ';
    for (int i = 0; i < clen; i = i + 1) {
        *(full + 6 + i) = *(cast<char*>(cmd) + i);
    }
    *(full + 6 + clen) = 0;
    string result = adb_exec(cast<string>(full));
    free(full);
    return result;
}

// Get a device property (e.g. "ro.product.model")
fn adb_get_prop(string prop) -> string {
    // Build: "shell getprop <prop>"
    int plen = _adb_strlen(prop);
    char* full = alloc<char>(plen + 20);
    int pos = 0;
    // "shell getprop "
    char* prefix = cast<char*>("shell getprop ");
    while (*(prefix + pos) != 0) {
        *(full + pos) = *(prefix + pos);
        pos = pos + 1;
    }
    for (int i = 0; i < plen; i = i + 1) {
        *(full + pos + i) = *(cast<char*>(prop) + i);
    }
    *(full + pos + plen) = 0;
    string result = adb_exec(cast<string>(full));
    free(full);

    // Trim trailing newline/whitespace
    if (_adb_strlen(result) > 0) {
        char* r = cast<char*>(result);
        int rlen = _adb_strlen(result);
        while (rlen > 0) {
            int ch = cast<int>(*(r + rlen - 1));
            if (ch == 10 || ch == 13 || ch == 32) {
                rlen = rlen - 1;
            } else {
                break;
            }
        }
        *(r + rlen) = 0;
    }
    return result;
}

// ─── Input Control ──────────────────────────────────────────

// Send a tap (touch) at coordinates (x, y) on the phone screen
fn adb_input_tap(int x, int y) -> void {
    // Build: "shell input tap X Y"
    char* cmd = alloc<char>(64);
    int pos = 0;
    char* prefix = cast<char*>("shell input tap ");
    while (*(prefix + pos) != 0) {
        *(cmd + pos) = *(prefix + pos);
        pos = pos + 1;
    }
    char* num = alloc<char>(16);
    int nlen = _adb_itoa(x, num);
    for (int i = 0; i < nlen; i = i + 1) {
        *(cmd + pos) = *(num + i);
        pos = pos + 1;
    }
    *(cmd + pos) = ' ';
    pos = pos + 1;
    nlen = _adb_itoa(y, num);
    for (int i = 0; i < nlen; i = i + 1) {
        *(cmd + pos) = *(num + i);
        pos = pos + 1;
    }
    *(cmd + pos) = 0;
    free(num);

    string result = adb_exec(cast<string>(cmd));
    free(cmd);
}

// Send a swipe gesture from (x1,y1) to (x2,y2) over duration_ms milliseconds
fn adb_input_swipe(int x1, int y1, int x2, int y2, int duration_ms) -> void {
    // Build: "shell input swipe X1 Y1 X2 Y2 DURATION"
    char* cmd = alloc<char>(128);
    int pos = 0;
    char* prefix = cast<char*>("shell input swipe ");
    while (*(prefix + pos) != 0) {
        *(cmd + pos) = *(prefix + pos);
        pos = pos + 1;
    }

    char* num = alloc<char>(16);

    // x1
    int nlen = _adb_itoa(x1, num);
    for (int i = 0; i < nlen; i = i + 1) { *(cmd + pos) = *(num + i); pos = pos + 1; }
    *(cmd + pos) = ' '; pos = pos + 1;

    // y1
    nlen = _adb_itoa(y1, num);
    for (int i = 0; i < nlen; i = i + 1) { *(cmd + pos) = *(num + i); pos = pos + 1; }
    *(cmd + pos) = ' '; pos = pos + 1;

    // x2
    nlen = _adb_itoa(x2, num);
    for (int i = 0; i < nlen; i = i + 1) { *(cmd + pos) = *(num + i); pos = pos + 1; }
    *(cmd + pos) = ' '; pos = pos + 1;

    // y2
    nlen = _adb_itoa(y2, num);
    for (int i = 0; i < nlen; i = i + 1) { *(cmd + pos) = *(num + i); pos = pos + 1; }
    *(cmd + pos) = ' '; pos = pos + 1;

    // duration_ms
    nlen = _adb_itoa(duration_ms, num);
    for (int i = 0; i < nlen; i = i + 1) { *(cmd + pos) = *(num + i); pos = pos + 1; }
    *(cmd + pos) = 0;

    free(num);

    string result = adb_exec(cast<string>(cmd));
    free(cmd);
}

// Send a key event (e.g. 3=HOME, 4=BACK, 24=VOL_UP, 25=VOL_DOWN, 26=POWER)
fn adb_input_keyevent(int keycode) -> void {
    char* cmd = alloc<char>(48);
    int pos = 0;
    char* prefix = cast<char*>("shell input keyevent ");
    while (*(prefix + pos) != 0) {
        *(cmd + pos) = *(prefix + pos);
        pos = pos + 1;
    }
    char* num = alloc<char>(16);
    int nlen = _adb_itoa(keycode, num);
    for (int i = 0; i < nlen; i = i + 1) {
        *(cmd + pos) = *(num + i);
        pos = pos + 1;
    }
    *(cmd + pos) = 0;
    free(num);

    string result = adb_exec(cast<string>(cmd));
    free(cmd);
}

// Send text input to the device (types the text as if from a keyboard)
fn adb_input_text(string text) -> void {
    int tlen = _adb_strlen(text);
    char* cmd = alloc<char>(tlen + 24);
    int pos = 0;
    char* prefix = cast<char*>("shell input text ");
    while (*(prefix + pos) != 0) {
        *(cmd + pos) = *(prefix + pos);
        pos = pos + 1;
    }
    for (int i = 0; i < tlen; i = i + 1) {
        *(cmd + pos + i) = *(cast<char*>(text) + i);
    }
    *(cmd + pos + tlen) = 0;

    string result = adb_exec(cast<string>(cmd));
    free(cmd);
}

// ─── File Transfer ──────────────────────────────────────────

// Push a file from the local machine to the Android device
fn adb_push(string local_path, string remote_path) -> string {
    int llen = _adb_strlen(local_path);
    int rlen = _adb_strlen(remote_path);
    char* cmd = alloc<char>(llen + rlen + 16);
    int pos = 0;
    char* prefix = cast<char*>("push ");
    while (*(prefix + pos) != 0) {
        *(cmd + pos) = *(prefix + pos);
        pos = pos + 1;
    }
    for (int i = 0; i < llen; i = i + 1) {
        *(cmd + pos + i) = *(cast<char*>(local_path) + i);
    }
    pos = pos + llen;
    *(cmd + pos) = ' ';
    pos = pos + 1;
    for (int i = 0; i < rlen; i = i + 1) {
        *(cmd + pos + i) = *(cast<char*>(remote_path) + i);
    }
    pos = pos + rlen;
    *(cmd + pos) = 0;

    string result = adb_exec(cast<string>(cmd));
    free(cmd);
    return result;
}

// Pull a file from the Android device to the local machine
fn adb_pull(string remote_path, string local_path) -> string {
    int rlen = _adb_strlen(remote_path);
    int llen = _adb_strlen(local_path);
    char* cmd = alloc<char>(rlen + llen + 16);
    int pos = 0;
    char* prefix = cast<char*>("pull ");
    while (*(prefix + pos) != 0) {
        *(cmd + pos) = *(prefix + pos);
        pos = pos + 1;
    }
    for (int i = 0; i < rlen; i = i + 1) {
        *(cmd + pos + i) = *(cast<char*>(remote_path) + i);
    }
    pos = pos + rlen;
    *(cmd + pos) = ' ';
    pos = pos + 1;
    for (int i = 0; i < llen; i = i + 1) {
        *(cmd + pos + i) = *(cast<char*>(local_path) + i);
    }
    pos = pos + llen;
    *(cmd + pos) = 0;

    string result = adb_exec(cast<string>(cmd));
    free(cmd);
    return result;
}

// Install an APK on the connected device
fn adb_install(string apk_path) -> string {
    int plen = _adb_strlen(apk_path);
    char* cmd = alloc<char>(plen + 16);
    int pos = 0;
    char* prefix = cast<char*>("install ");
    while (*(prefix + pos) != 0) {
        *(cmd + pos) = *(prefix + pos);
        pos = pos + 1;
    }
    for (int i = 0; i < plen; i = i + 1) {
        *(cmd + pos + i) = *(cast<char*>(apk_path) + i);
    }
    *(cmd + pos + plen) = 0;

    string result = adb_exec(cast<string>(cmd));
    free(cmd);
    return result;
}

// Uninstall a package from the connected device
fn adb_uninstall(string package_name) -> string {
    int plen = _adb_strlen(package_name);
    char* cmd = alloc<char>(plen + 16);
    int pos = 0;
    char* prefix = cast<char*>("uninstall ");
    while (*(prefix + pos) != 0) {
        *(cmd + pos) = *(prefix + pos);
        pos = pos + 1;
    }
    for (int i = 0; i < plen; i = i + 1) {
        *(cmd + pos + i) = *(cast<char*>(package_name) + i);
    }
    *(cmd + pos + plen) = 0;

    string result = adb_exec(cast<string>(cmd));
    free(cmd);
    return result;
}

// ─── Screen Capture (Foundation) ────────────────────────────

// Get the screen resolution of the connected device
// Returns "WIDTHxHEIGHT" string (e.g. "1080x1920")
fn adb_screen_size() -> string {
    return adb_shell("wm size");
}

// Capture a single screenshot as raw PNG data
// Caller must free the returned buffer; length is written to out_len
fn adb_screencap_png(int* out_len) -> char* {
    return adb_exec_raw("exec-out screencap -p", out_len);
}

// ─── Device Info Helpers ────────────────────────────────────

// Get battery level as a string (e.g. "99")
fn adb_battery_level() -> string {
    string bat_out = adb_shell("dumpsys battery");
    int slen = _adb_strlen(bat_out);
    if (slen == 0) { return "?"; }
    char* p = cast<char*>(bat_out);

    // Find "level: " in output
    for (int i = 0; i < slen - 7; i = i + 1) {
        if (_adb_byte(p, i) == 108 && _adb_byte(p, i+1) == 101 && _adb_byte(p, i+2) == 118 &&
            _adb_byte(p, i+3) == 101 && _adb_byte(p, i+4) == 108 && _adb_byte(p, i+5) == 58) {
            // Found "level:"
            int j = i + 6;
            while (j < slen && _adb_byte(p, j) == 32) { j = j + 1; }
            char* num = alloc<char>(8);
            int npos = 0;
            while (j < slen && _adb_byte(p, j) >= 48 && _adb_byte(p, j) <= 57) {
                *(num + npos) = cast<char>(_adb_byte(p, j));
                npos = npos + 1;
                j = j + 1;
            }
            *(num + npos) = 0;
            if (npos > 0) {
                return cast<string>(num);
            }
            free(num);
        }
    }
    return "?";
}

// Get device model name
fn adb_device_model() -> string {
    return adb_get_prop("ro.product.model");
}

// Get Android version
fn adb_android_version() -> string {
    return adb_get_prop("ro.build.version.release");
}

// Get device manufacturer
fn adb_manufacturer() -> string {
    return adb_get_prop("ro.product.manufacturer");
}

// ─── Streaming Foundation ───────────────────────────────────

struct AdbStream {
    int pid;        // PID of the adb process
    int fd;         // read end of the pipe
    int active;     // 1 if streaming
    char* framebuf; // buffer for one frame
    int frame_size; // expected bytes per frame (w * h * 4)
};

fn adb_stream_init(AdbStream* s) -> void {
    s.pid = -1;
    s.fd = -1;
    s.active = 0;
    s.framebuf = null;
    s.frame_size = 0;
}

fn adb_stream_close(AdbStream* s) -> void {
    if (s == null) { return; }
    if (s.fd >= 0) {
        sys_close(s.fd);
        s.fd = -1;
    }
    if (s.pid > 0) {
        sys_kill(s.pid, 15); // SIGTERM
        int wstatus = 0;
        sys_wait4(s.pid, &wstatus, 0, null);
        s.pid = -1;
    }
    if (s.framebuf != null) {
        free(s.framebuf);
        s.framebuf = null;
    }
    s.active = 0;
    s.frame_size = 0;
}

// Start raw video stream from the phone via screenrecord
// width/height: desired capture resolution
// Returns true if the stream was started successfully
fn adb_stream_start(AdbStream* s, int width, int height) -> bool {
    if (s == null || !adb_available()) { return false; }
    adb_stream_init(s);

    // Build size string "WIDTHxHEIGHT"
    char* sizebuf = alloc<char>(32);
    int pos = _adb_itoa(width, sizebuf);
    *(sizebuf + pos) = 'x';
    pos = pos + 1;
    pos = pos + _adb_itoa(height, sizebuf + pos);

    // Create pipe
    char* pfds = alloc<char>(8);
    for (int i = 0; i < 8; i = i + 1) { *(pfds + i) = 0; }

    if (sys_pipe(pfds) != 0) {
        free(pfds);
        free(sizebuf);
        return false;
    }

    int rfd = _adb_get32(pfds, 0);
    int wfd = _adb_get32(pfds, 4);
    free(pfds);

    _adb_ignore_sigpipe();

    int pid = sys_fork();
    if (pid < 0) {
        sys_close(rfd);
        sys_close(wfd);
        free(sizebuf);
        return false;
    }

    if (pid == 0) {
        // Child: exec adb exec-out screenrecord --output-format=raw-frames --size=WxH -
        sys_close(rfd);
        sys_dup2(wfd, 1);
        int devnull = sys_open("/dev/null", 1, 0);
        if (devnull >= 0) {
            sys_dup2(devnull, 2);
            if (devnull > 2) { sys_close(devnull); }
        }
        if (wfd > 2) { sys_close(wfd); }

        char** argv = alloc<char*>(16);
        argv[0] = cast<char*>(adb_path());
        argv[1] = cast<char*>("exec-out");
        argv[2] = cast<char*>("screenrecord");
        argv[3] = cast<char*>("--output-format=raw-frames");

        // Build --size=WxH
        char* sizearg = alloc<char>(40);
        char* sp = cast<char*>("--size=");
        int si = 0;
        while (*(sp + si) != 0) {
            *(sizearg + si) = *(sp + si);
            si = si + 1;
        }
        int sj = 0;
        while (*(sizebuf + sj) != 0) {
            *(sizearg + si + sj) = *(sizebuf + sj);
            sj = sj + 1;
        }
        *(sizearg + si + sj) = 0;

        argv[4] = sizearg;
        argv[5] = cast<char*>("-");
        argv[6] = null;

        sys_execve(adb_path(), argv, null);
        sys_exit(127);
    }

    // Parent
    sys_close(wfd);
    free(sizebuf);

    s.pid = pid;
    s.fd = rfd;
    s.active = 1;
    s.frame_size = width * height * 4; // RGBA
    s.framebuf = alloc<char>(s.frame_size);

    return true;
}

// Read one complete frame from the stream
// Returns true if a full frame was read, false on error/end
fn adb_stream_read_frame(AdbStream* s) -> bool {
    if (s == null || s.active == 0 || s.fd < 0) { return false; }

    int need = s.frame_size;
    int got = 0;

    while (got < need) {
        int n = sys_read(s.fd, s.framebuf + got, need - got);
        if (n <= 0) {
            s.active = 0;
            return false;
        }
        got = got + n;
    }
    return true;
}

// ─── Utility ────────────────────────────────────────────────

// Reboot the device (normal, recovery, or bootloader)
fn adb_reboot(string target) -> string {
    int tlen = _adb_strlen(target);
    if (tlen == 0) {
        return adb_exec("reboot");
    }
    char* cmd = alloc<char>(tlen + 16);
    int pos = 0;
    char* prefix = cast<char*>("reboot ");
    while (*(prefix + pos) != 0) {
        *(cmd + pos) = *(prefix + pos);
        pos = pos + 1;
    }
    for (int i = 0; i < tlen; i = i + 1) {
        *(cmd + pos + i) = *(cast<char*>(target) + i);
    }
    *(cmd + pos + tlen) = 0;
    string result = adb_exec(cast<string>(cmd));
    free(cmd);
    return result;
}

// Get ADB server version
fn adb_version() -> string {
    return adb_exec("version");
}

// Forward a TCP port: local_port <-> remote_port
fn adb_forward(int local_port, int remote_port) -> string {
    char* cmd = alloc<char>(64);
    int pos = 0;
    char* prefix = cast<char*>("forward tcp:");
    while (*(prefix + pos) != 0) {
        *(cmd + pos) = *(prefix + pos);
        pos = pos + 1;
    }
    char* num = alloc<char>(16);
    int nlen = _adb_itoa(local_port, num);
    for (int i = 0; i < nlen; i = i + 1) {
        *(cmd + pos) = *(num + i);
        pos = pos + 1;
    }
    // " tcp:"
    *(cmd + pos) = ' '; pos = pos + 1;
    *(cmd + pos) = 't'; pos = pos + 1;
    *(cmd + pos) = 'c'; pos = pos + 1;
    *(cmd + pos) = 'p'; pos = pos + 1;
    *(cmd + pos) = ':'; pos = pos + 1;

    nlen = _adb_itoa(remote_port, num);
    for (int i = 0; i < nlen; i = i + 1) {
        *(cmd + pos) = *(num + i);
        pos = pos + 1;
    }
    *(cmd + pos) = 0;
    free(num);

    string result = adb_exec(cast<string>(cmd));
    free(cmd);
    return result;
}

// List installed packages
fn adb_list_packages() -> string {
    return adb_shell("pm list packages");
}

// Take a screenshot and save it to local_path as PNG
fn adb_screenshot(string local_path) -> bool {
    int slen = 0;
    char* data = adb_screencap_png(&slen);
    if (data == null || slen <= 0) {
        return false;
    }
    int fd = sys_open(local_path, 577, 420); // O_WRONLY|O_CREAT|O_TRUNC, 0644
    if (fd < 0) {
        free(data);
        return false;
    }
    int total = 0;
    while (total < slen) {
        int n = sys_write(fd, data + total, slen - total);
        if (n <= 0) { break; }
        total = total + n;
    }
    sys_close(fd);
    free(data);
    return total == slen;
}
