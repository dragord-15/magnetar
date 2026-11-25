// Standard System Module for Magnetar OS & Linux
// Pure Magnetar implementation without external C library dependencies
//
// ── Rewrite Notes ──
// 1. open(): flags corrected — "w" → O_WRONLY|O_CREAT|O_TRUNC (577),
//            "a" → O_WRONLY|O_CREAT|O_APPEND (1089), "r+" → O_RDWR (2).
// 2. write(): now takes an explicit len parameter instead of scanning for \0,
//             making it safe for binary data (ELF, images, ...).
// 3. file_copy(): loops with exact byte counts from sys_read → sys_write
//                 so embedded \0 bytes never truncate the copy.
// 4. free / alloc are built-in language keywords (TOK_KW_FREE / TOK_KW_ALLOC),
//    compiled directly to sys_munmap / sys_mmap — no extern declaration needed.
//    Temporary allocs in abspath() are now properly freed after use.
// 5. is_file() / is_dir(): use sys_newstat (syscall 4) to read st_mode
//                          and extract the file-type nibble via /4096
//                          (the parser has no binary bitwise AND operator).
// 6. split(): now extracts BOTH the directory and the filename into globals
//             accessible through dir_name() / base_name().
// 7. listdir(): implemented with sys_getdents64 (syscall 217).
//    wait_proc(): implemented with sys_wait4 (syscall 61).

// -------------------------------------------------------------
// Low-level Native Linux Syscall Bindings
// -------------------------------------------------------------
extern fn sys_open(string path, int flags, int mode) -> int;
extern fn sys_close(int fd) -> int;
extern fn sys_read(int fd, char* buf, int count) -> int;
extern fn sys_write(int fd, char* data, int count) -> int;
extern fn sys_lseek(int fd, int offset, int whence) -> int;
extern fn sys_unlink(string path) -> int;
extern fn sys_rename(string oldpath, string newpath) -> int;
extern fn sys_mkdir(string path, int mode) -> int;
extern fn sys_rmdir(string path) -> int;
extern fn sys_chdir(string path) -> int;
extern fn sys_getcwd(char* buf, int size) -> int;
extern fn sys_fork() -> int;
extern fn sys_getpid() -> int;
extern fn sys_getuid() -> int;
extern fn get_timestamp() -> int;
extern fn process_exec(string cmd) -> int;
extern fn os_get_env(string key) -> string;
extern fn os_get_platform() -> string;
extern fn print_str(string s) -> void;
extern fn print_int(int n) -> void;
// sys_newstat: x86-64 syscall 4 — int stat(const char *path, struct stat *buf).
// The 144-byte stat buffer holds st_mode at offset 24 (little-endian 32-bit).
extern fn sys_newstat(string path, char* buf) -> int;
// sys_getdents64: x86-64 syscall 217 —
//   int getdents64(int fd, struct linux_dirent64 *dirp, unsigned int count).
// Each entry has: d_ino(8), d_off(8), d_reclen(u16), d_type(u8), d_name[].
// The name string starts at offset 19 inside each entry.
extern fn sys_getdents64(int fd, char* dirp, int count) -> int;
// sys_wait4: x86-64 syscall 61 —
//   pid_t wait4(pid_t pid, int *wstatus, int options, struct rusage *rusage).
// Pass NULL (0) for rusage and wstatus pointers when not needed.
extern fn sys_wait4(int pid, int* wstatus, int options, char* rusage) -> int;

// -------------------------------------------------------------
// Linux open() flag constants (x86-64)
// -------------------------------------------------------------
//  O_RDONLY = 0    O_WRONLY = 1    O_RDWR  = 2
//  O_CREAT  = 64   O_TRUNC  = 512  O_APPEND = 1024
// Derived:
//  "w"  = O_WRONLY | O_CREAT | O_TRUNC  = 1 + 64 + 512   = 577
//  "a"  = O_WRONLY | O_CREAT | O_APPEND = 1 + 64 + 1024  = 1089
//  "r+" = O_RDWR                        = 2
//  "r"  = O_RDONLY                       = 0

const int O_RDONLY = 0;
const int O_WRONLY = 1;
const int O_RDWR   = 2;
const int O_CREAT  = 64;
const int O_APPEND = 1024;
const int O_TRUNC  = 512;

// Permission constants
const int PERM_0644 = 420;
const int PERM_0755 = 493;

// stat() st_mode file-type nibble (bits 15:12)
// st_mode / 4096 extracts the file type:
//   S_IFREG = 0x8000 → 32768 / 4096 = 8
//   S_IFDIR = 0x4000 → 16384 / 4096 = 4
const int TYPE_REG = 8;
const int TYPE_DIR = 4;

// linux_dirent64 field offsets
const int D_TYPE_OFFSET  = 18;
const int D_NAME_OFFSET = 19;
const int D_RECLEN_OFF_LO = 16;
const int D_RECLEN_OFF_HI = 17;

// -------------------------------------------------------------
// Top-Level Functions
// -------------------------------------------------------------

// open() — correct flag dispatch for "r", "w", "a", "r+" modes.
// FIX: The old version only handled read vs write; "a" used O_TRUNC which
// erased file contents on append. "r+" was missing entirely.
fn open(string filepath, string mode) -> int {
    char* p = cast<char*>(mode);
    if (*p == 'r' || *p == 'R') {
        p = p + 1;
        if (*p == '+') {
            // "r+" → read/write, no truncation
            return sys_open(filepath, O_RDWR, 0);
        }
        // "r" → read-only
        return sys_open(filepath, O_RDONLY, 0);
    }
    if (*p == 'a' || *p == 'A') {
        // "a" → append-only, file created if missing, existing data preserved
        return sys_open(filepath, O_WRONLY + O_CREAT + O_APPEND, PERM_0644);
    }
    // "w" → write, truncate to zero, create if missing
    return sys_open(filepath, O_WRONLY + O_CREAT + O_TRUNC, PERM_0644);
}

fn read(int fd, int count) -> string {
    if (fd < 0) {
        return "";
    }
    char* buf = alloc<char>(count + 1);
    int bytes_read = sys_read(fd, buf, count);
    if (bytes_read > 0) {
        *(buf + bytes_read) = 0;
        return cast<string>(buf);
    }
    free(buf);
    return "";
}

// FIX: write() now takes an explicit len parameter. The old version scanned
// for a null terminator (\0), which silently truncated binary data containing
// embedded null bytes (e.g. ELF headers, images).
fn write(int fd, string data, int len) -> int {
    if (fd < 0) {
        return -1;
    }
    if (len <= 0) {
        return 0;
    }
    return sys_write(fd, cast<char*>(data), len);
}

fn seek(int fd, int offset, int whence) -> int {
    if (fd < 0) {
        return -1;
    }
    return sys_lseek(fd, offset, whence);
}

fn close(int fd) -> void {
    if (fd >= 0) {
        sys_close(fd);
    }
}

fn file_delete(string path) -> bool {
    int res = sys_unlink(path);
    return res == 0;
}

// FIX: file_copy() now reads in a loop using raw sys_read/sys_write with
// exact byte counts. The old version called read()+write() where write()
// scanned for \0, corrupting binary files with embedded null bytes.
fn file_copy(string src, string dest) -> bool {
    int fsrc = sys_open(src, O_RDONLY, 0);
    if (fsrc < 0) {
        return false;
    }
    int fdest = sys_open(dest, O_WRONLY + O_CREAT + O_TRUNC, PERM_0644);
    if (fdest < 0) {
        sys_close(fsrc);
        return false;
    }
    bool success = true;
    char* buf = alloc<char>(65536);
    int bytes = sys_read(fsrc, buf, 65536);
    while (bytes > 0) {
        int written = sys_write(fdest, buf, bytes);
        if (written < 0) {
            success = false;
            break;
        }
        bytes = sys_read(fsrc, buf, 65536);
    }
    free(buf);
    sys_close(fsrc);
    sys_close(fdest);
    return success;
}

fn file_move(string src, string dest) -> bool {
    int res = sys_rename(src, dest);
    if (res == 0) {
        return true;
    }
    if (file_copy(src, dest)) {
        file_delete(src);
        return true;
    }
    return false;
}

fn mkdir(string path) -> bool {
    int res = sys_mkdir(path, PERM_0755);
    return res == 0;
}

fn rmdir(string path) -> bool {
    int res = sys_rmdir(path);
    return res == 0;
}

fn chdir(string path) -> bool {
    int res = sys_chdir(path);
    return res == 0;
}

fn getcwd() -> string {
    char* buf = alloc<char>(1024);
    sys_getcwd(buf, 1024);
    return cast<string>(buf);
}

// FIX: listdir() implemented with sys_getdents64 (syscall 217).
// Reads struct linux_dirent64 entries from the kernel and collects names
// into a comma-separated string. Each entry layout:
//   [0..7]   d_ino     (u64)
//   [8..15]  d_off     (s64)
//   [16..17] d_reclen  (u16, little-endian)
//   [18]     d_type    (u8)
//   [19..]   d_name    (null-terminated char[])
fn listdir(string path) -> string {
    int fd = sys_open(path, O_RDONLY, 0);
    if (fd < 0) {
        return "";
    }
    int bufsize = 8192;
    char* buf = alloc<char>(bufsize);
    // Worst case: each name + ", " fits in 4x the kernel buffer
    char* result = alloc<char>(bufsize * 4 + 1);
    int res_len = 0;
    *(result + 0) = 0;
    bool first = true;

    int nread = sys_getdents64(fd, buf, bufsize);
    while (nread > 0) {
        int pos = 0;
        while (pos < nread) {
            char* entry = buf + pos;
            // d_reclen at offset 16 (little-endian u16)
            int reclen = cast<int>(*(entry + D_RECLEN_OFF_LO)) + cast<int>(*(entry + D_RECLEN_OFF_HI)) * 256;
            // d_name starts at offset 19
            char* name = entry + D_NAME_OFFSET;
            // Skip "." and ".." entries
            if (cast<int>(*name) != 46) {
                // Not a dot entry — append to result
                if (!first) {
                    *(result + res_len) = 44;
                    res_len = res_len + 1;
                    *(result + res_len) = 32;
                    res_len = res_len + 1;
                }
                first = false;
                int k = 0;
                while (cast<int>(*(name + k)) != 0) {
                    *(result + res_len) = *(name + k);
                    res_len = res_len + 1;
                    k = k + 1;
                }
            }
            if (reclen <= 0) {
                break;
            }
            pos = pos + reclen;
        }
        nread = sys_getdents64(fd, buf, bufsize);
    }
    *(result + res_len) = 0;
    sys_close(fd);
    free(buf);
    return cast<string>(result);
}

fn join(string path1, string path2) -> string {
    int len1 = 0;
    char* p1 = cast<char*>(path1);
    while (*p1 != 0) {
        len1 = len1 + 1;
        p1 = p1 + 1;
    }
    int len2 = 0;
    char* p2 = cast<char*>(path2);
    while (*p2 != 0) {
        len2 = len2 + 1;
        p2 = p2 + 1;
    }

    int extra = 0;
    if (len1 > 0) {
        if (cast<int>(*(cast<char*>(path1) + len1 - 1)) != 47) {
            extra = 1;
        }
    }

    int total_len = len1 + len2 + extra;
    char* res = alloc<char>(total_len + 1);
    for (int i = 0; i < len1; i = i + 1) {
        *(res + i) = *(cast<char*>(path1) + i);
    }
    int idx = len1;
    if (extra == 1) {
        *(res + idx) = 47;
        idx = idx + 1;
    }
    for (int j = 0; j < len2; j = j + 1) {
        *(res + idx + j) = *(cast<char*>(path2) + j);
    }
    *(res + total_len) = 0;
    return cast<string>(res);
}

// Module-level state for split() / dir_name() / base_name().
// split() populates both; dir_name() and base_name() read them.
string _split_dir = "";
string _split_name = "";

// FIX: split() now extracts BOTH the directory prefix and the filename,
// storing them in _split_dir / _split_name. The old version only returned
// the directory path (acting like dirname). The filename is accessible
// through base_name().
fn split(string filepath) -> string {
    int len = 0;
    char* p = cast<char*>(filepath);
    while (*p != 0) {
        len = len + 1;
        p = p + 1;
    }
    int last_slash = 0 - 1;
    for (int i = 0; i < len; i = i + 1) {
        if (cast<int>(*(cast<char*>(filepath) + i)) == 47) {
            last_slash = i;
        }
    }

    if (last_slash >= 0) {
        // Directory: everything before the last slash
        char* dir_buf = alloc<char>(last_slash + 1);
        for (int k = 0; k < last_slash; k = k + 1) {
            *(dir_buf + k) = *(cast<char*>(filepath) + k);
        }
        *(dir_buf + last_slash) = 0;
        _split_dir = cast<string>(dir_buf);

        // Filename: everything after the last slash
        int name_len = len - last_slash - 1;
        char* name_buf = alloc<char>(name_len + 1);
        for (int j = 0; j < name_len; j = j + 1) {
            *(name_buf + j) = *(cast<char*>(filepath) + last_slash + 1 + j);
        }
        *(name_buf + name_len) = 0;
        _split_name = cast<string>(name_buf);
    } else {
        // No slash found — directory is ".", filename is the whole path
        _split_dir = ".";
        _split_name = filepath;
    }

    return _split_dir;
}

// Returns the directory portion from the last split() call.
fn dir_name(string filepath) -> string {
    split(filepath);
    return _split_dir;
}

// Returns the filename portion from the last split() call.
fn base_name(string filepath) -> string {
    split(filepath);
    return _split_name;
}

fn exists(string path) -> bool {
    int fd = sys_open(path, O_RDONLY, 0);
    if (fd >= 0) {
        sys_close(fd);
        return true;
    }
    return false;
}

// FIX: is_file() / is_dir() now use sys_newstat (syscall 4) to read the
// actual st_mode field from the kernel's stat buffer. The old versions
// just called exists(), which could not distinguish files from directories.
// Since the parser has no binary bitwise AND operator (& is address-of only),
// we extract the file-type nibble with integer division: st_mode / 4096
// maps S_IFREG (0x8000) → 8 and S_IFDIR (0x4000) → 4.
fn is_file(string path) -> bool {
    // struct stat is 144 bytes on x86-64; st_mode at offset 24
    char* st = alloc<char>(144);
    int res = sys_newstat(path, st);
    if (res < 0) {
        free(st);
        return false;
    }
    // Read st_mode as a 32-bit little-endian integer from offset 24
    int mode = cast<int>(*(st + 24))
             + cast<int>(*(st + 25)) * 256
             + cast<int>(*(st + 26)) * 65536
             + cast<int>(*(st + 27)) * 16777216;
    free(st);
    // Extract file type nibble (bits 15:12) via integer division by 4096
    return (mode / 4096) == TYPE_REG;
}

fn is_dir(string path) -> bool {
    char* st = alloc<char>(144);
    int res = sys_newstat(path, st);
    if (res < 0) {
        free(st);
        return false;
    }
    int mode = cast<int>(*(st + 24))
             + cast<int>(*(st + 25)) * 256
             + cast<int>(*(st + 26)) * 65536
             + cast<int>(*(st + 27)) * 16777216;
    free(st);
    return (mode / 4096) == TYPE_DIR;
}

// FIX: free the intermediate getcwd() buffer after join() copies it.
// The old version leaked the cwd allocation on every call.
fn abspath(string path) -> string {
    string cwd = getcwd();
    string result = join(cwd, path);
    free(cast<char*>(cwd));
    return result;
}

fn fork() -> int {
    return sys_fork();
}

fn exec(string command) -> int {
    return process_exec(command);
}

// FIX: wait_proc() now uses the real sys_wait4 syscall (number 61 on x86-64)
// instead of returning a hardcoded 0, which left zombie processes behind.
// Passing NULL (0) for the rusage pointer since it is not needed.
fn wait_proc(int pid) -> int {
    int status = 0;
    int res = sys_wait4(pid, &status, 0, 0);
    return res;
}

fn getpid() -> int {
    return sys_getpid();
}

fn getenv(string key) -> string {
    return os_get_env(key);
}

fn setenv(string key, string value) -> bool {
    return true;
}

fn environ() -> string {
    return "USER=hamza HOME=/home/hamza PATH=/usr/local/bin:/usr/bin";
}

fn uname() -> string {
    return "Linux Magnetar 6.x x86_64";
}

fn hostname() -> string {
    return "magnetar-linux";
}

fn time() -> int {
    return get_timestamp();
}

fn getuid() -> int {
    return sys_getuid();
}

// -------------------------------------------------------------
// 1. Files Class Wrapper
// -------------------------------------------------------------
class File {
    int handle;
    string path;

    fn open(string filepath, string mode) -> bool {
        this.path = filepath;
        this.handle = open(filepath, mode);
        if (this.handle < 0) {
            return false;
        }
        return true;
    }

    fn read(int count) -> string {
        return read(this.handle, count);
    }

    // FIX: write() now takes an explicit len for binary-safe writes.
    fn write(string data, int len) -> int {
        return write(this.handle, data, len);
    }

    fn seek(int offset, int whence) -> int {
        return seek(this.handle, offset, whence);
    }

    fn close() -> void {
        close(this.handle);
        this.handle = -1;
    }
};

class Directory {
    fn mkdir(string path) -> bool { return mkdir(path); }
    fn rmdir(string path) -> bool { return rmdir(path); }
    fn chdir(string path) -> bool { return chdir(path); }
    fn getcwd() -> string { return getcwd(); }
    fn listdir(string path) -> string { return listdir(path); }
};

class Path {
    fn join(string p1, string p2) -> string { return join(p1, p2); }
    fn split(string p) -> string { return split(p); }
    fn dir_name(string p) -> string { return dir_name(p); }
    fn base_name(string p) -> string { return base_name(p); }
    fn exists(string p) -> bool { return exists(p); }
    fn is_file(string p) -> bool { return is_file(p); }
    fn is_dir(string p) -> bool { return is_dir(p); }
    fn abspath(string p) -> string { return abspath(p); }
};

class Process {
    fn fork() -> int { return sys_fork(); }
    fn exec(string cmd) -> int { return process_exec(cmd); }
    fn run(string command) -> int { return process_exec(command); }
    fn wait_proc(int pid) -> int { return wait_proc(pid); }
    fn exit_proc(int code) -> void {}
    fn getpid() -> int { return sys_getpid(); }
};

class Environment {
    fn getenv(string k) -> string { return getenv(k); }
    fn setenv(string k, string v) -> bool { return setenv(k, v); }
    fn environ() -> string { return environ(); }
};

class SystemInfo {
    fn uname() -> string { return uname(); }
    fn hostname() -> string { return hostname(); }
    fn time() -> int { return time(); }
    fn getuid() -> int { return getuid(); }
};// Time module
extern fn get_timestamp() -> int;
extern fn sleep_ms(int ms) -> void;

class Time {
    fn now() -> int {
        return get_timestamp();
    }
    fn sleep(int milliseconds) -> void {
        sleep_ms(milliseconds);
    }
};
// File System module
extern fn fs_exists(string path) -> bool;
extern fn fs_mkdir(string path) -> bool;
extern fn fs_rm(string path) -> bool;

class FileSystem {
    fn exists(string path) -> bool { return fs_exists(path); }
    fn createDirectory(string path) -> bool { return fs_mkdir(path); }
    fn remove(string path) -> bool { return fs_rm(path); }
};
