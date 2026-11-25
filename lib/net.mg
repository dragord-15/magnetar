// ============================================================================
// Magnetar Standard Library: Networking (lib/net.mg)
// Real Linux IPv4 TCP/UDP Sockets, TCP Server & Client Implementations
// ============================================================================

use "lib/string.mg";

// -------------------------------------------------------------
// Native Linux Syscalls for Networking
// -------------------------------------------------------------
extern fn sys_socket(int domain, int type, int protocol) -> int;
extern fn sys_bind(int fd, char* addr, int addrlen) -> int;
extern fn sys_listen(int fd, int backlog) -> int;
extern fn sys_accept(int fd, char* addr, int* addrlen) -> int;
extern fn sys_connect(int fd, char* addr, int addrlen) -> int;
extern fn sys_send(int fd, char* buf, int count, int flags) -> int;
extern fn sys_recv(int fd, char* buf, int count, int flags) -> int;
extern fn sys_shutdown(int fd, int how) -> int;
extern fn sys_close(int fd) -> int;
extern fn sys_setsockopt(int fd, int level, int optname, char* optval, int optlen) -> int;
extern fn print_str(string s) -> void;
extern fn sys_sendto(int fd, char* buf, int len, int flags, char* dest_addr, int addrlen) -> int;
extern fn sys_recvfrom(int fd, char* buf, int len, int flags, char* src_addr, int* addrlen) -> int;

// -------------------------------------------------------------
// Socket Constants
// -------------------------------------------------------------
const int AF_INET         = 2;
const int SOCK_STREAM     = 1; // TCP
const int SOCK_DGRAM      = 2; // UDP
const int SOL_SOCKET      = 1;
const int SO_REUSEADDR    = 2;
const int SO_RCVTIMEO     = 20;
const int SO_SNDTIMEO     = 21;
const int SHUT_RD         = 0;
const int SHUT_WR         = 1;
const int SHUT_RDWR       = 2;

// -------------------------------------------------------------
// Address Helpers (struct sockaddr_in - 16 bytes)
// -------------------------------------------------------------

fn net_create_ipv4_addr(int ip0, int ip1, int ip2, int ip3, int port) -> char* {
    char* addr = alloc<char>(16);
    // sin_family = AF_INET (2)
    *(addr + 0) = 2;
    *(addr + 1) = 0;
    // sin_port (network byte order / big-endian)
    *(addr + 2) = cast<char>(port / 256);
    *(addr + 3) = cast<char>(port % 256);
    // sin_addr (4 bytes IPv4)
    *(addr + 4) = cast<char>(ip0);
    *(addr + 5) = cast<char>(ip1);
    *(addr + 6) = cast<char>(ip2);
    *(addr + 7) = cast<char>(ip3);
    // sin_zero (8 bytes zero padding)
    for (int i = 8; i < 16; i = i + 1) {
        *(addr + i) = 0;
    }
    return addr;
}

fn net_create_any_addr(int port) -> char* {
    return net_create_ipv4_addr(0, 0, 0, 0, port);
}

fn net_create_loopback_addr(int port) -> char* {
    return net_create_ipv4_addr(127, 0, 0, 1, port);
}

// -------------------------------------------------------------
// Core Functional Networking API
// -------------------------------------------------------------

fn net_socket_tcp() -> int {
    int fd = sys_socket(AF_INET, SOCK_STREAM, 0);
    if (fd >= 0) {
        // Enable SO_REUSEADDR so port can be immediately rebound
        char* opt = alloc<char>(4);
        *(opt + 0) = 1;
        *(opt + 1) = 0;
        *(opt + 2) = 0;
        *(opt + 3) = 0;
        sys_setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, opt, 4);
        free(opt);
    }
    return fd;
}

fn net_socket_udp() -> int {
    return sys_socket(AF_INET, SOCK_DGRAM, 0);
}

fn net_bind(int fd, int port) -> bool {
    char* addr = net_create_any_addr(port);
    int res = sys_bind(fd, addr, 16);
    free(addr);
    return res == 0;
}

fn net_listen(int fd, int backlog) -> bool {
    if (backlog <= 0) {
        backlog = 10;
    }
    return sys_listen(fd, backlog) == 0;
}

fn net_accept(int server_fd) -> int {
    char* client_addr = alloc<char>(16);
    int* addr_len = alloc<int>(1);
    *addr_len = 16;
    int client_fd = sys_accept(server_fd, client_addr, addr_len);
    free(client_addr);
    free(addr_len);
    return client_fd;
}

fn net_connect(int fd, int ip0, int ip1, int ip2, int ip3, int port) -> bool {
    char* addr = net_create_ipv4_addr(ip0, ip1, ip2, ip3, port);
    int res = sys_connect(fd, addr, 16);
    free(addr);
    return res == 0;
}

fn net_connect_localhost(int fd, int port) -> bool {
    return net_connect(fd, 127, 0, 0, 1, port);
}

fn net_send(int fd, string data, int len) -> int {
    if (fd < 0 || len <= 0) {
        return 0;
    }
    return sys_send(fd, cast<char*>(data), len, 0);
}

fn net_send_str(int fd, string s) -> int {
    return net_send(fd, s, len(s));
}

// Sends every byte, retrying on partial writes (Linux may return short writes).
fn net_send_all(int fd, char* data, int length) -> int {
    if (fd < 0 || data == null || length <= 0) {
        return 0;
    }
    int total = 0;
    while (total < length) {
        int written = sys_send(fd, data + total, length - total, 0);
        if (written <= 0) {
            if (total > 0) {
                return total;
            }
            return -1;
        }
        total = total + written;
    }
    return total;
}

fn net_send_all_str(int fd, string s) -> int {
    return net_send_all(fd, cast<char*>(s), len(s));
}

// Reads up to max_len bytes into an existing buffer. Returns the byte count,
// 0 on orderly shutdown, and -1 on error/timeout.
fn net_recv_into(int fd, char* buffer, int max_len) -> int {
    if (fd < 0 || buffer == null || max_len <= 0) {
        return -1;
    }
    return sys_recv(fd, buffer, max_len, 0);
}

// Sets receive/send timeouts using struct timeval { long tv_sec; long tv_usec; }
fn net_set_socket_timeouts(int fd, int seconds, int microseconds) -> bool {
    if (fd < 0) {
        return false;
    }
    char* tv = alloc<char>(16);
    for (int i = 0; i < 16; i = i + 1) {
        *(tv + i) = 0;
    }
    int sec = seconds;
    if (sec < 0) { sec = 0; }
    *(tv + 0) = cast<char>(sec & 255);
    *(tv + 1) = cast<char>((sec >> 8) & 255);
    *(tv + 2) = cast<char>((sec >> 16) & 255);
    *(tv + 3) = cast<char>((sec >> 24) & 255);
    *(tv + 4) = cast<char>((sec >> 32) & 255);
    *(tv + 5) = cast<char>((sec >> 40) & 255);
    *(tv + 6) = cast<char>((sec >> 48) & 255);
    *(tv + 7) = cast<char>((sec >> 56) & 255);

    int usec = microseconds;
    if (usec < 0) { usec = 0; }
    if (usec > 999999) { usec = 999999; }
    *(tv + 8) = cast<char>(usec & 255);
    *(tv + 9) = cast<char>((usec >> 8) & 255);
    *(tv + 10) = cast<char>((usec >> 16) & 255);
    *(tv + 11) = cast<char>((usec >> 24) & 255);

    bool ok_rx = sys_setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, tv, 16) == 0;
    bool ok_tx = sys_setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, tv, 16) == 0;
    free(tv);
    return ok_rx && ok_tx;
}

fn net_set_recv_timeout(int fd, int seconds) -> bool {
    return net_set_socket_timeouts(fd, seconds, 0);
}

fn net_set_timeout_ms(int fd, int milliseconds) -> bool {
    if (milliseconds <= 0) { milliseconds = 1000; }
    int sec = milliseconds / 1000;
    int usec = (milliseconds % 1000) * 1000;
    return net_set_socket_timeouts(fd, sec, usec);
}

fn net_recv(int fd, int max_len) -> string {
    if (fd < 0 || max_len <= 0) {
        return "";
    }
    char* buf = alloc<char>(max_len + 1);
    int bytes = sys_recv(fd, buf, max_len, 0);
    if (bytes > 0) {
        *(buf + bytes) = 0;
        return cast<string>(buf);
    }
    free(buf);
    return "";
}

fn net_close(int fd) -> void {
    if (fd >= 0) {
        sys_shutdown(fd, SHUT_RDWR);
        sys_close(fd);
    }
}

// -------------------------------------------------------------
// TCP Client & Server Struct Wrappers
// -------------------------------------------------------------

struct TcpClient {
    int fd;
    bool is_connected;

    fn connect_to(int ip0, int ip1, int ip2, int ip3, int port) -> bool {
        fd = net_socket_tcp();
        if (fd < 0) {
            is_connected = false;
            return false;
        }
        is_connected = net_connect(fd, ip0, ip1, ip2, ip3, port);
        if (!is_connected) {
            sys_close(fd);
            fd = -1;
        }
        return is_connected;
    }

    fn connect_localhost(int port) -> bool {
        return connect_to(127, 0, 0, 1, port);
    }

    fn set_timeout(int seconds) -> bool {
        if (!is_connected) {
            return false;
        }
        return net_set_recv_timeout(fd, seconds);
    }

    fn send_data(string data) -> int {
        if (!is_connected) {
            return -1;
        }
        return net_send_all_str(fd, data);
    }

    fn send_bytes(char* data, int count) -> int {
        if (!is_connected) {
            return -1;
        }
        return net_send_all(fd, data, count);
    }

    fn receive(int max_bytes) -> string {
        if (!is_connected) {
            return "";
        }
        return net_recv(fd, max_bytes);
    }

    fn receive_into(char* buffer, int max_bytes) -> int {
        if (!is_connected) {
            return -1;
        }
        return net_recv_into(fd, buffer, max_bytes);
    }

    fn close() -> void {
        if (is_connected) {
            net_close(fd);
            is_connected = false;
            fd = -1;
        }
    }
};

struct TcpServer {
    int fd;
    int port;
    bool is_running;

    fn start(int p, int backlog) -> bool {
        port = p;
        fd = net_socket_tcp();
        if (fd < 0) {
            is_running = false;
            return false;
        }
        if (!net_bind(fd, port)) {
            sys_close(fd);
            is_running = false;
            return false;
        }
        if (!net_listen(fd, backlog)) {
            sys_close(fd);
            is_running = false;
            return false;
        }
        is_running = true;
        return true;
    }

    fn accept_connection() -> int {
        if (!is_running) {
            return -1;
        }
        return net_accept(fd);
    }

    fn stop() -> void {
        if (is_running) {
            net_close(fd);
            is_running = false;
            fd = -1;
        }
    }
};
