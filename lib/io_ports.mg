// io_ports.mg — Direct hardware I/O port access for Magnetar / Falcon
//
// Two interchangeable backends:
//
//   PORT_MODE_DIRECT (0) — native x86 IN/OUT instructions.
//       Use on bare metal (Ring 0), or from a privileged Linux user
//       process after port_enable_direct() (which calls iopl(3)).
//
//   PORT_MODE_DEV (1) — Linux /dev/port driver via syscalls.
//       Works from user space (root only) without touching IOPL, and is
//       handy for testing a driver before it runs on real hardware.
//
// The raw externs (inb/outb/inw/outw/inl/outl/iopl) are emitted by the
// Magnetar x86_64 backend as inline IN/OUT / syscall instructions.

// ── Raw port primitives (compiler builtins) ──
extern fn inb(int port) -> int;
extern fn outb(int port, int value) -> void;
extern fn inw(int port) -> int;
extern fn outw(int port, int value) -> void;
extern fn inl(int port) -> int;
extern fn outl(int port, int value) -> void;
extern fn iopl(int level) -> int;

// ── Syscalls used by the /dev/port backend ──
extern fn sys_open(string path, int flags, int mode) -> int;
extern fn sys_close(int fd) -> int;
extern fn sys_lseek(int fd, int offset, int whence) -> int;
extern fn sys_read(int fd, char* buf, int count) -> int;
extern fn sys_write(int fd, char* data, int count) -> int;

// ── Constants ──
static const int PORT_MODE_DIRECT = 0;
static const int PORT_MODE_DEV    = 1;
static const int PORT_SEEK_SET    = 0;
static const int PORT_O_RDWR      = 2;

// ── State ──
static int   G_PORT_MODE = PORT_MODE_DIRECT;
static int   G_PORT_FD   = -1;
static char* G_PORT_BUF  = 0;

// Normalise any int to an unsigned byte (0..255).
fn _port_byte(int v) -> int {
    int b = v - (v / 256) * 256;
    if (b < 0) { b = b + 256; }
    return b;
}

// ── Backend selection ──
fn port_mode() -> int { return G_PORT_MODE; }

fn port_use_direct() -> void { G_PORT_MODE = PORT_MODE_DIRECT; }

// Grant this user-space process access to IN/OUT (Linux syscall iopl).
// Returns 0 on success (root required), non-zero otherwise.
fn port_enable_direct() -> int {
    int r = iopl(3);
    if (r == 0) { G_PORT_MODE = PORT_MODE_DIRECT; }
    return r;
}

// Switch to the /dev/port backend. Returns 1 on success.
fn port_use_dev() -> int {
    G_PORT_FD = sys_open("/dev/port", PORT_O_RDWR, 0);
    if (G_PORT_FD < 0) {
        G_PORT_FD = -1;
        return 0;
    }
    if (G_PORT_BUF == 0) { G_PORT_BUF = alloc<char>(1); }
    G_PORT_MODE = PORT_MODE_DEV;
    return 1;
}

fn port_close() -> void {
    if (G_PORT_FD >= 0) { sys_close(G_PORT_FD); }
    G_PORT_FD = -1;
    G_PORT_MODE = PORT_MODE_DIRECT;
}

// ── /dev/port byte access ──
fn _dev_read(int port) -> int {
    if (G_PORT_FD < 0 || G_PORT_BUF == 0) { return -1; }
    sys_lseek(G_PORT_FD, port, PORT_SEEK_SET);
    int n = sys_read(G_PORT_FD, G_PORT_BUF, 1);
    if (n != 1) { return -1; }
    return _port_byte(*(G_PORT_BUF));
}

fn _dev_write(int port, int value) -> void {
    if (G_PORT_FD < 0 || G_PORT_BUF == 0) { return; }
    *(G_PORT_BUF) = _port_byte(value);
    sys_lseek(G_PORT_FD, port, PORT_SEEK_SET);
    sys_write(G_PORT_FD, G_PORT_BUF, 1);
}

// ── Unified API (8 / 16 / 32-bit) ──
fn port_in8(int port) -> int {
    if (G_PORT_MODE == PORT_MODE_DEV) { return _dev_read(port); }
    return inb(port);
}

fn port_out8(int port, int value) -> void {
    if (G_PORT_MODE == PORT_MODE_DEV) { _dev_write(port, value); return; }
    outb(port, value);
}

fn port_in16(int port) -> int {
    if (G_PORT_MODE == PORT_MODE_DEV) {
        int lo = _dev_read(port);
        int hi = _dev_read(port + 1);
        return lo + hi * 256;
    }
    return inw(port);
}

fn port_out16(int port, int value) -> void {
    if (G_PORT_MODE == PORT_MODE_DEV) {
        _dev_write(port, value);
        _dev_write(port + 1, value / 256);
        return;
    }
    outw(port, value);
}

fn port_in32(int port) -> int {
    if (G_PORT_MODE == PORT_MODE_DEV) {
        int b0 = _dev_read(port);
        int b1 = _dev_read(port + 1);
        int b2 = _dev_read(port + 2);
        int b3 = _dev_read(port + 3);
        return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216;
    }
    return inl(port);
}

fn port_out32(int port, int value) -> void {
    if (G_PORT_MODE == PORT_MODE_DEV) {
        _dev_write(port, value);
        _dev_write(port + 1, value / 256);
        _dev_write(port + 2, value / 65536);
        _dev_write(port + 3, value / 16777216);
        return;
    }
    outl(port, value);
}
