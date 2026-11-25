// ============================================================================
// Magnetar Standard Library: File Management (lib/file.mg)
// Pure Magnetar implementation without external libc dependencies
// ============================================================================

// -------------------------------------------------------------
// Native Linux x86_64 Syscall Bindings
// -------------------------------------------------------------
extern fn sys_open(string path, int flags, int mode) -> int;
extern fn sys_close(int fd) -> int;
extern fn sys_read(int fd, char* buf, int count) -> int;
extern fn sys_write(int fd, char* data, int count) -> int;
extern fn sys_lseek(int fd, int offset, int whence) -> int;
extern fn sys_unlink(string path) -> int;
extern fn sys_rename(string oldpath, string newpath) -> int;
extern fn sys_stat(string path, char* buf) -> int;
extern fn sys_fstat(int fd, char* buf) -> int;
extern fn sys_fsync(int fd) -> int;
extern fn sys_ftruncate(int fd, int length) -> int;
extern fn sys_truncate(string path, int length) -> int;
extern fn sys_access(string path, int mode) -> int;
extern fn print_str(string s) -> void;

// -------------------------------------------------------------
// Access Modes and Flag Constants
// -------------------------------------------------------------
const int FILE_READ               = 0;    // O_RDONLY
const int FILE_WRITE              = 577;  // O_WRONLY | O_CREAT | O_TRUNC (1 + 64 + 512)
const int FILE_APPEND             = 1089; // O_WRONLY | O_CREAT | O_APPEND (1 + 64 + 1024)
const int FILE_READ_WRITE         = 2;    // O_RDWR
const int FILE_READ_WRITE_CREATE  = 578;  // O_RDWR | O_CREAT | O_TRUNC
const int FILE_READ_WRITE_APPEND  = 1090; // O_RDWR | O_CREAT | O_APPEND

// Seeking constants
const int FILE_SEEK_SET = 0; // Seek from start of file
const int FILE_SEEK_CUR = 1; // Seek from current position
const int FILE_SEEK_END = 2; // Seek from end of file

// Default permissions (0644 octal = 420 decimal)
const int FILE_DEFAULT_PERM = 420;

// stat() st_mode file-type constants (bits 15:12 / 4096)
const int FILE_TYPE_REG = 8; // S_IFREG (0x8000 / 4096 = 8)
const int FILE_TYPE_DIR = 4; // S_IFDIR (0x4000 / 4096 = 4)

// -------------------------------------------------------------
// Internal Helpers
// -------------------------------------------------------------

// Converts string modes ("r", "w", "a", "r+", "w+", "a+", "rb", "wb", etc.) to Linux open flags
fn file_mode_to_flags(string mode) -> int {
    char* p = cast<char*>(mode);
    if (*p == 0) {
        return FILE_READ;
    }
    char m0 = *p;
    char m1 = *(p + 1);
    char m2 = 0;
    if (m1 != 0) {
        m2 = *(p + 2);
    }

    if (m0 == 'r' || m0 == 'R') {
        if (m1 == '+' || m2 == '+') {
            return FILE_READ_WRITE;
        }
        return FILE_READ;
    }
    if (m0 == 'w' || m0 == 'W') {
        if (m1 == '+' || m2 == '+') {
            return FILE_READ_WRITE_CREATE;
        }
        return FILE_WRITE;
    }
    if (m0 == 'a' || m0 == 'A') {
        if (m1 == '+' || m2 == '+') {
            return FILE_READ_WRITE_APPEND;
        }
        return FILE_APPEND;
    }
    return FILE_READ;
}

// -------------------------------------------------------------
// Core Functional API
// -------------------------------------------------------------

// Open a file using mode string ("r", "w", "a", "r+", "w+", "a+")
fn file_open(string path, string mode) -> int {
    int flags = file_mode_to_flags(mode);
    return sys_open(path, flags, FILE_DEFAULT_PERM);
}

// Open a file with custom flags and permissions
fn file_open_flags(string path, int flags, int perm) -> int {
    return sys_open(path, flags, perm);
}

// Close an open file descriptor
fn file_close(int fd) -> bool {
    if (fd < 0) {
        return false;
    }
    return sys_close(fd) == 0;
}

// Read raw bytes into a pre-allocated buffer
fn file_read_bytes(int fd, char* buf, int count) -> int {
    if (fd < 0 || count <= 0) {
        return 0;
    }
    return sys_read(fd, buf, count);
}

// Read up to 'count' bytes from file into a newly allocated string
fn file_read(int fd, int count) -> string {
    if (fd < 0 || count <= 0) {
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

// Read a single line until newline (\n) or EOF
fn file_read_line(int fd) -> string {
    if (fd < 0) {
        return "";
    }
    int max_len = 2048;
    char* buf = alloc<char>(max_len + 1);
    int len = 0;
    char* ch = alloc<char>(2);

    while (len < max_len) {
        int r = sys_read(fd, ch, 1);
        if (r <= 0) {
            break;
        }
        if (*ch == 10) { // '\n'
            break;
        }
        if (*ch != 13) { // ignore '\r'
            *(buf + len) = *ch;
            len = len + 1;
        }
    }
    free(ch);

    if (len == 0 && r <= 0) {
        free(buf);
        return "";
    }
    *(buf + len) = 0;
    return cast<string>(buf);
}

// Read an entire file into memory as a string
fn file_read_all(string path) -> string {
    int fd = file_open(path, "r");
    if (fd < 0) {
        return "";
    }
    int size = sys_lseek(fd, 0, FILE_SEEK_END);
    sys_lseek(fd, 0, FILE_SEEK_SET);
    if (size <= 0) {
        sys_close(fd);
        return "";
    }
    char* buf = alloc<char>(size + 1);
    int total = 0;
    while (total < size) {
        int r = sys_read(fd, buf + total, size - total);
        if (r <= 0) {
            break;
        }
        total = total + r;
    }
    *(buf + total) = 0;
    sys_close(fd);
    return cast<string>(buf);
}

// Write 'len' bytes to an open file
fn file_write(int fd, string data, int len) -> int {
    if (fd < 0 || len <= 0) {
        return 0;
    }
    return sys_write(fd, cast<char*>(data), len);
}

// Write a null-terminated string to an open file
fn file_write_str(int fd, string text) -> int {
    if (fd < 0) {
        return 0;
    }
    return sys_write(fd, cast<char*>(text), len(text));
}

// Write a string followed by a newline (\n)
fn file_write_line(int fd, string text) -> int {
    if (fd < 0) {
        return 0;
    }
    int w1 = sys_write(fd, cast<char*>(text), len(text));
    int w2 = sys_write(fd, "\n", 1);
    return w1 + w2;
}

// Write the entire content to a file (creates or truncates)
fn file_write_all(string path, string content) -> bool {
    int fd = file_open(path, "w");
    if (fd < 0) {
        return false;
    }
    int total = len(content);
    int written = 0;
    char* p = cast<char*>(content);
    while (written < total) {
        int r = sys_write(fd, p + written, total - written);
        if (r < 0) {
            sys_close(fd);
            return false;
        }
        written = written + r;
    }
    sys_close(fd);
    return true;
}

// Append content to the end of a file (creates if not existing)
fn file_append_all(string path, string content) -> bool {
    int fd = file_open(path, "a");
    if (fd < 0) {
        return false;
    }
    int total = len(content);
    int written = 0;
    char* p = cast<char*>(content);
    while (written < total) {
        int r = sys_write(fd, p + written, total - written);
        if (r < 0) {
            sys_close(fd);
            return false;
        }
        written = written + r;
    }
    sys_close(fd);
    return true;
}

// Reposition read/write file offset
fn file_seek(int fd, int offset, int whence) -> int {
    if (fd < 0) {
        return -1;
    }
    return sys_lseek(fd, offset, whence);
}

// Get the current file position
fn file_tell(int fd) -> int {
    if (fd < 0) {
        return -1;
    }
    return sys_lseek(fd, 0, FILE_SEEK_CUR);
}

// Rewind file position to the beginning
fn file_rewind(int fd) -> void {
    if (fd >= 0) {
        sys_lseek(fd, 0, FILE_SEEK_SET);
    }
}

// Get file size in bytes by path
fn file_size(string path) -> int {
    int fd = sys_open(path, 0, 0);
    if (fd < 0) {
        return -1;
    }
    int size = sys_lseek(fd, 0, FILE_SEEK_END);
    sys_close(fd);
    return size;
}

// Get size of an open file descriptor without changing position
fn file_fd_size(int fd) -> int {
    if (fd < 0) {
        return -1;
    }
    int cur = sys_lseek(fd, 0, FILE_SEEK_CUR);
    int end = sys_lseek(fd, 0, FILE_SEEK_END);
    sys_lseek(fd, cur, FILE_SEEK_SET);
    return end;
}

// Check if a file exists
fn file_exists(string path) -> bool {
    int res = sys_access(path, 0);
    if (res == 0) {
        return true;
    }
    int fd = sys_open(path, 0, 0);
    if (fd >= 0) {
        sys_close(fd);
        return true;
    }
    return false;
}

// Delete / remove a file
fn file_delete(string path) -> bool {
    return sys_unlink(path) == 0;
}

// Alias for file_delete
fn file_remove(string path) -> bool {
    return sys_unlink(path) == 0;
}

// Rename or move a file
fn file_rename(string oldpath, string newpath) -> bool {
    return sys_rename(oldpath, newpath) == 0;
}

// Copy a file from src to dest
fn file_copy(string src, string dest) -> bool {
    int fsrc = file_open(src, "r");
    if (fsrc < 0) {
        return false;
    }
    int fdest = file_open(dest, "w");
    if (fdest < 0) {
        file_close(fsrc);
        return false;
    }
    int buf_size = 65536;
    char* buf = alloc<char>(buf_size);
    bool success = true;
    int bytes = sys_read(fsrc, buf, buf_size);
    while (bytes > 0) {
        int written = sys_write(fdest, buf, bytes);
        if (written < 0) {
            success = false;
            break;
        }
        bytes = sys_read(fsrc, buf, buf_size);
    }
    free(buf);
    file_close(fsrc);
    file_close(fdest);
    return success;
}

// Move a file from src to dest (uses rename, or copy+delete fallback)
fn file_move(string src, string dest) -> bool {
    if (file_rename(src, dest)) {
        return true;
    }
    if (file_copy(src, dest)) {
        file_delete(src);
        return true;
    }
    return false;
}

// Flush kernel buffers for an open file to disk
fn file_sync(int fd) -> bool {
    if (fd < 0) {
        return false;
    }
    return sys_fsync(fd) == 0;
}

// Alias for file_sync
fn file_flush(int fd) -> bool {
    return file_sync(fd);
}

// Truncate open file to specified length
fn file_truncate(int fd, int length) -> bool {
    if (fd < 0) {
        return false;
    }
    return sys_ftruncate(fd, length) == 0;
}

// Check if path is a regular file
fn file_is_file(string path) -> bool {
    char* st = alloc<char>(144);
    int res = sys_stat(path, st);
    if (res < 0) {
        free(st);
        return false;
    }
    int mode = cast<int>(*(st + 24))
             + cast<int>(*(st + 25)) * 256
             + cast<int>(*(st + 26)) * 65536
             + cast<int>(*(st + 27)) * 16777216;
    free(st);
    return (mode / 4096) == FILE_TYPE_REG;
}

// Check if path is a directory
fn file_is_dir(string path) -> bool {
    char* st = alloc<char>(144);
    int res = sys_stat(path, st);
    if (res < 0) {
        free(st);
        return false;
    }
    int mode = cast<int>(*(st + 24))
             + cast<int>(*(st + 25)) * 256
             + cast<int>(*(st + 26)) * 65536
             + cast<int>(*(st + 27)) * 16777216;
    free(st);
    return (mode / 4096) == FILE_TYPE_DIR;
}

// Extract filename component from path
fn file_basename(string path) -> string {
    char* p = cast<char*>(path);
    int total_len = len(path);
    int last_slash = -1;
    for (int i = 0; i < total_len; i = i + 1) {
        if (*(p + i) == 47) { // '/'
            last_slash = i;
        }
    }
    if (last_slash < 0) {
        return path;
    }
    int name_len = total_len - last_slash - 1;
    char* res = alloc<char>(name_len + 1);
    for (int j = 0; j < name_len; j = j + 1) {
        *(res + j) = *(p + last_slash + 1 + j);
    }
    *(res + name_len) = 0;
    return cast<string>(res);
}

// Extract directory component from path
fn file_dirname(string path) -> string {
    char* p = cast<char*>(path);
    int total_len = len(path);
    int last_slash = -1;
    for (int i = 0; i < total_len; i = i + 1) {
        if (*(p + i) == 47) {
            last_slash = i;
        }
    }
    if (last_slash < 0) {
        return ".";
    }
    if (last_slash == 0) {
        return "/";
    }
    char* res = alloc<char>(last_slash + 1);
    for (int k = 0; k < last_slash; k = k + 1) {
        *(res + k) = *(p + k);
    }
    *(res + last_slash) = 0;
    return cast<string>(res);
}

// Extract file extension without the dot (e.g. "txt", "mg")
fn file_extension(string path) -> string {
    char* p = cast<char*>(path);
    int total_len = len(path);
    int last_dot = -1;
    int last_slash = -1;
    for (int i = 0; i < total_len; i = i + 1) {
        if (*(p + i) == 47) {
            last_slash = i;
        }
        if (*(p + i) == 46) { // '.'
            last_dot = i;
        }
    }
    if (last_dot < 0 || last_dot < last_slash) {
        return "";
    }
    int ext_len = total_len - last_dot - 1;
    char* res = alloc<char>(ext_len + 1);
    for (int j = 0; j < ext_len; j = j + 1) {
        *(res + j) = *(p + last_dot + 1 + j);
    }
    *(res + ext_len) = 0;
    return cast<string>(res);
}

// -------------------------------------------------------------
// Object-Oriented File Wrapper
// -------------------------------------------------------------

struct File {
    int fd;
    string path;
    string mode;
    bool is_open;

    fn open(string filepath, string filemode) -> bool {
        path = filepath;
        mode = filemode;
        fd = file_open(filepath, filemode);
        is_open = (fd >= 0);
        return is_open;
    }

    fn read(int count) -> string {
        if (!is_open) {
            return "";
        }
        return file_read(fd, count);
    }

    fn read_line() -> string {
        if (!is_open) {
            return "";
        }
        return file_read_line(fd);
    }

    fn read_all() -> string {
        if (!is_open) {
            return "";
        }
        int cur = sys_lseek(fd, 0, FILE_SEEK_CUR);
        int size = sys_lseek(fd, 0, FILE_SEEK_END);
        sys_lseek(fd, cur, FILE_SEEK_SET);
        int remaining = size - cur;
        if (remaining <= 0) {
            return "";
        }
        return file_read(fd, remaining);
    }

    fn write(string data, int len) -> int {
        if (!is_open) {
            return -1;
        }
        return file_write(fd, data, len);
    }

    fn write_str(string text) -> int {
        if (!is_open) {
            return -1;
        }
        return file_write_str(fd, text);
    }

    fn write_line(string text) -> int {
        if (!is_open) {
            return -1;
        }
        return file_write_line(fd, text);
    }

    fn seek(int offset, int whence) -> int {
        if (!is_open) {
            return -1;
        }
        return file_seek(fd, offset, whence);
    }

    fn tell() -> int {
        if (!is_open) {
            return -1;
        }
        return file_tell(fd);
    }

    fn rewind() -> void {
        if (is_open) {
            file_rewind(fd);
        }
    }

    fn size() -> int {
        if (!is_open) {
            return -1;
        }
        return file_fd_size(fd);
    }

    fn flush() -> bool {
        if (!is_open) {
            return false;
        }
        return file_sync(fd);
    }

    fn close() -> void {
        if (is_open) {
            file_close(fd);
            is_open = false;
            fd = -1;
        }
    }
};
