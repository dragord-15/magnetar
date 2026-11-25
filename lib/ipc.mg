// lib/ipc.mg - Unix domain socket IPC helpers for MDE
// Simple line-delimited JSON transport.

extern fn sys_socket(int domain, int type, int protocol) -> int;
extern fn sys_bind(int fd, char* addr, int addrlen) -> int;
extern fn sys_listen(int fd, int backlog) -> int;
extern fn sys_accept(int fd, char* addr, int* addrlen) -> int;
extern fn sys_connect(int fd, char* addr, int addrlen) -> int;
extern fn sys_send(int fd, char* buf, int count, int flags) -> int;
extern fn sys_recv(int fd, char* buf, int count, int flags) -> int;
extern fn sys_close(int fd) -> int;
extern fn sys_unlink(string path) -> int;
extern fn sys_mkdir(string path, int mode) -> int;
extern fn sys_chmod(string path, int mode) -> int;
extern fn sys_fcntl(int fd, int cmd, int arg) -> int;
extern fn print_str(string s) -> void;

const int AF_UNIX = 1;
const int SOCK_STREAM = 1;
const int F_GETFL = 3;
const int F_SETFL = 4;
const int O_NONBLOCK = 2048;

fn ipc_sockaddr_un(string path) -> char* {
    char* addr = alloc<char>(110);
    int i = 0;
    while (i < 110) { *(addr + i) = 0; i = i + 1; }
    // sun_family = AF_UNIX (little-endian short)
    *(addr + 0) = 1;
    *(addr + 1) = 0;
    char* p = cast<char*>(path);
    int j = 0;
    while (*(p + j) != 0 && j < 107) {
        *(addr + 2 + j) = *(p + j);
        j = j + 1;
    }
    *(addr + 2 + j) = 0;
    return addr;
}

fn ipc_server_create(string path) -> int {
    sys_unlink(path);
    int fd = sys_socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) { return -1; }
    char* addr = ipc_sockaddr_un(path);
    int br = sys_bind(fd, addr, 110);
    free(addr);
    if (br < 0) { sys_close(fd); return -2; }
    sys_chmod(path, 511); // 0777 for dev; tighten in production
    if (sys_listen(fd, 16) < 0) { sys_close(fd); return -3; }
    return fd;
}

fn ipc_server_accept(int server_fd) -> int {
    char* addr = alloc<char>(110);
    int* alen = alloc<int>(1);
    *alen = 110;
    int cfd = sys_accept(server_fd, addr, alen);
    free(addr);
    free(alen);
    return cfd;
}

fn ipc_client_connect(string path) -> int {
    int fd = sys_socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) { return -1; }
    char* addr = ipc_sockaddr_un(path);
    int r = sys_connect(fd, addr, 110);
    free(addr);
    if (r < 0) { sys_close(fd); return -2; }
    return fd;
}

fn ipc_set_nonblock(int fd) -> int {
    int flags = sys_fcntl(fd, F_GETFL, 0);
    if (flags < 0) { return -1; }
    return sys_fcntl(fd, F_SETFL, flags + O_NONBLOCK);
}

fn ipc_send_line(int fd, string line) -> int {
    char* p = cast<char*>(line);
    int n = 0;
    while (*(p + n) != 0) { n = n + 1; }
    int sent = 0;
    while (sent < n) {
        int w = sys_send(fd, p + sent, n - sent, 0);
        if (w <= 0) { return -1; }
        sent = sent + w;
    }
    // newline
    char* nl = alloc<char>(2);
    *(nl + 0) = 10;
    int w2 = sys_send(fd, nl, 1, 0);
    free(nl);
    if (w2 <= 0) { return -1; }
    return sent + 1;
}

// Receives into buf until newline or max-1. Returns bytes read, 0 closed, -1 error/no-data.
fn ipc_recv_line(int fd, char* buf, int max) -> int {
    int i = 0;
    while (i < max - 1) {
        int r = sys_recv(fd, buf + i, 1, 0);
        if (r <= 0) {
            if (i > 0) { *(buf + i) = 0; return i; }
            return r;
        }
        int c = cast<int>(*(buf + i)) & 255;
        if (c == 10) { *(buf + i) = 0; return i; }
        if (c != 13) { i = i + 1; }
    }
    *(buf + i) = 0;
    return i;
}

fn ipc_close(int fd) -> void {
    if (fd >= 0) { sys_close(fd); }
}
