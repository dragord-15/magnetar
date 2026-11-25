// gui.mg — Magnetar GUI Module (Professional Dual-Mode: Direct card0 + X11 Desktop Window)
// Pure syscall GUI with VGA 8x16 font rendering
//
// Dual-Mode Architecture:
//   1. Desktop Window Mode (like Tkinter/GTK/Qt):
//      - Real desktop window via /tmp/.X11-unix/X0 Unix domain socket & X11 wire protocol.
//      - Dynamic resizing and fullscreen support without distortion.
//      - Zero external dependencies: NO libc, NO libX11.
//   2. Direct Card0 Mode (/dev/dri/cardN DRM/KMS):
//      - Draws directly to physical scanout buffer via dumb buffers.
//      - Fallback to /dev/fb0.

// ─── Syscall Externs ────────────────────────────────────
extern fn sys_open(string path, int flags, int mode) -> int;
extern fn sys_close(int fd) -> int;
extern fn sys_read(int fd, char* buf, int count) -> int;
extern fn sys_write(int fd, char* data, int count) -> int;
extern fn sys_mmap(int addr, int len, int prot, int flags, int fd, int off) -> int;
extern fn sys_munmap(int addr, int len) -> int;
extern fn sys_ioctl(int fd, int req, int arg) -> int;

// ─── Socket & System Externs ────────────────────────────
extern fn sys_socket(int domain, int type, int protocol) -> int;
extern fn sys_connect(int fd, char* addr, int addrlen) -> int;
extern fn sys_send(int fd, char* buf, int count, int flags) -> int;
extern fn sys_recv(int fd, char* buf, int count, int flags) -> int;
extern fn sys_poll(char* fds, int nfds, int timeout) -> int;
extern fn sleep_ms(int ms) -> void;
extern fn print_str(string s) -> void;
extern fn print_int(int n) -> void;

// ─── Constants ───────────────────────────────────────────
static const int FBIOGET_VSCREENINFO = 17920;
static const int MAP_SHARED = 1;
static const int MAP_PRIVATE = 2;
static const int MAP_ANONYMOUS = 32;
static const int PROT_RW = 3;
static const int O_RDONLY = 0;
static const int O_RDWR = 2;
static const int O_NONBLOCK = 2048;

// ─── DRM/KMS Constants (Linux /dev/dri/cardN) ────────────
static const int DRM_IOCTL_GETRESOURCES  = 0xC04064A0;
static const int DRM_IOCTL_GETCRTC       = 0xC06864A1;
static const int DRM_IOCTL_SETCRTC       = 0xC06864A2;
static const int DRM_IOCTL_GETENCODER    = 0xC01464A6;
static const int DRM_IOCTL_GETCONNECTOR  = 0xC05064A7;
static const int DRM_IOCTL_ADDFB         = 0xC01C64AE;
static const int DRM_IOCTL_RMFB          = 0xC00464AF;
static const int DRM_IOCTL_CREATE_DUMB   = 0xC02064B2;
static const int DRM_IOCTL_MAP_DUMB      = 0xC01064B3;
static const int DRM_IOCTL_DESTROY_DUMB  = 0xC00464B4;
static const int DRM_FORMAT_XRGB8888     = 0x34325258;
static const int DRM_MODE_CONNECTED      = 1;
static const int DRM_MODE_TYPE_PREFERRED = 8;

// ─── Standard Colors ─────────────────────────────────────
static const int COLOR_BLACK     = 0;
static const int COLOR_WHITE     = 16777215;
static const int COLOR_RED       = 16711680;
static const int COLOR_GREEN     = 65280;
static const int COLOR_BLUE      = 255;
static const int COLOR_GRAY      = 8421504;
static const int COLOR_DARKGRAY  = 4210752;
static const int COLOR_LIGHTGRAY = 12632256;

// ─── Display Buffers & Sizing ────────────────────────────
static int G_FB_FD = 0;
static int G_FB_ADDR = 0;
static int G_BACK = 0;
static int G_DRAW = 0;
static int G_FB_SIZE = 0;
static int G_FB_CAPACITY = 0;
static int G_XRES = 0;
static int G_YRES = 0;
static int G_BPP = 0;
static int G_GUI_SCALE = 1;

static int G_MOUSE_FD = 0 - 1;
static int G_MOUSE_X = 0;
static int G_MOUSE_Y = 0;
static int G_MOUSE_BTN = 0;
static int G_MOUSE_PREV_BTN = 0;
static int G_MOUSE_CLICK = 0;
static int G_MOUSE_RIGHT = 0;
static int G_MOUSE_RIGHT_CLICK = 0;
static int G_MOUSE_WHEEL = 0;
static int G_MBUF = 0;
static int G_MOUSE_PENDING = 0;
static int G_MOUSE_SPEED = 2;
static int G_KB_FD = 0 - 1;
static int G_KB_STATE = 0;
static int G_KB_QUEUE = 0;
static int G_KB_MODQ = 0;
static int G_KB_LAST_MOD = 0;
static int G_KB_HEAD = 0;
static int G_KB_COUNT = 0;
static int G_KB_CAPS = 0;
static int G_KB_DROPPED = 0;
static int G_KB_SHIFT = 0;
static int G_KB_CTRL = 0;

// DRM/KMS state
static int G_DRM_ACTIVE = 0;
static int G_DRM_FB_ID = 0;
static int G_DRM_HANDLE = 0;
static int G_DRM_PITCH = 0;
static int G_DRM_CRTC_ID = 0;
static int G_DRM_CONN_ID = 0;
static int G_DRM_ENC_ID = 0;
static int G_DRM_MODE = 0;

static int G_FB_WIDTH = 0;
static int G_FB_HEIGHT = 0;

// ─── X11 Backend Constants & State ───────────────────────
static const int AF_UNIX = 1;
static const int X11_SOCK_STREAM = 1;

static const int X11_OP_CREATE_WINDOW  = 1;
static const int X11_OP_DESTROY_WINDOW = 4;
static const int X11_OP_MAP_WINDOW     = 8;
static const int X11_OP_INTERN_ATOM    = 16;
static const int X11_OP_CHANGE_PROP    = 18;
static const int X11_OP_CREATE_GC      = 55;
static const int X11_OP_FREE_GC        = 60;
static const int X11_OP_PUT_IMAGE      = 72;

static const int X11_EV_KEY_PRESS      = 2;
static const int X11_EV_KEY_RELEASE    = 3;
static const int X11_EV_BUTTON_PRESS   = 4;
static const int X11_EV_BUTTON_RELEASE = 5;
static const int X11_EV_MOTION_NOTIFY  = 6;
static const int X11_EV_EXPOSE         = 12;
static const int X11_EV_CONFIGURE      = 22;
static const int X11_EV_CLIENT_MESSAGE = 33;

static const int X11_MASK_KEY    = 3;
static const int X11_MASK_BUTTON = 12;
static const int X11_MASK_MOTION = 64;
static const int X11_MASK_EXPOSE = 32768;
static const int X11_MASK_STRUCT = 131072;
static const int X11_IMAGE_Zpixmap = 2;

static int G_X11_ACTIVE = 0;
static int G_X11_FD = 0 - 1;
static int G_X11_ROOT = 0;
static int G_X11_ROOT_DEPTH = 0;
static int G_X11_ROOT_VISUAL = 0;
static int G_X11_WID = 0;
static int G_X11_GC = 0;
static int G_X11_RID_BASE = 0;
static int G_X11_RID_NEXT = 0;
static int G_X11_ATOM_WM_PROTO = 0;
static int G_X11_ATOM_WM_DEL = 0;
static int G_X11_WIN_W = 0;
static int G_X11_WIN_H = 0;
static int G_X11_CLOSE_REQ = 0;
static char* G_X11_EVBUF = 0;
static char* G_X11_REQ_BUF = 0;

static char* G_X11_AUTH_NAME = 0;
static int G_X11_AUTH_NAME_LEN = 0;
static char* G_X11_AUTH_DATA = 0;
static int G_X11_AUTH_DATA_LEN = 0;

// ─── Font Data (VGA 8x16, ASCII 32-126) ─────────────────
static string G_FONT;

// ─── Internal Bit/Math Helpers ───────────────────────────
fn _byte_val(int v) -> int {
    int b = v - (v / 256) * 256;
    if (b < 0) { b = b + 256; }
    return b;
}

fn _hex_val(int ch) -> int {
    if (ch >= 65 && ch <= 70) { return ch - 55; }
    if (ch >= 97 && ch <= 102) { return ch - 87; }
    return ch - 48;
}

fn _bit_at(int bv, int pos) -> int {
    int div = 1;
    if (pos == 1) { div = 2; }
    else if (pos == 2) { div = 4; }
    else if (pos == 3) { div = 8; }
    else if (pos == 4) { div = 16; }
    else if (pos == 5) { div = 32; }
    else if (pos == 6) { div = 64; }
    else if (pos == 7) { div = 128; }
    int v = bv / div;
    return v - (v / 2) * 2;
}

fn _font_byte(int ci, int row) -> int {
    int off = (ci * 16 + row) * 2;
    char* f = cast<char*>(G_FONT);
    int hi = _hex_val(_byte_val(*(f + off)));
    int lo = _hex_val(_byte_val(*(f + off + 1)));
    return hi * 16 + lo;
}

fn _str_len(string s) -> int {
    if (cast<int>(s) <= 0) { return 0; }
    char* p = cast<char*>(s);
    int n = 0;
    while (_byte_val(*(p + n)) != 0) { n = n + 1; }
    return n;
}

fn gui_rgb(int r, int g, int b) -> int {
    if (r < 0) { r = 0; } if (r > 255) { r = 255; }
    if (g < 0) { g = 0; } if (g > 255) { g = 255; }
    if (b < 0) { b = 0; } if (b > 255) { b = 255; }
    return r * 65536 + g * 256 + b;
}

// Mix two colors. t = 0 returns c1, t = 255 returns c2.
fn gui_mix_color(int c1, int c2, int t) -> int {
    if (t <= 0) { return c1; }
    if (t >= 255) { return c2; }
    int r1 = c1 / 65536;
    int g1 = (c1 / 256) - (c1 / 65536) * 256;
    int b1 = c1 - (c1 / 256) * 256;
    int r2 = c2 / 65536;
    int g2 = (c2 / 256) - (c2 / 65536) * 256;
    int b2 = c2 - (c2 / 256) * 256;
    int r = r1 + (r2 - r1) * t / 255;
    int g = g1 + (g2 - g1) * t / 255;
    int b = b1 + (b2 - b1) * t / 255;
    return gui_rgb(r, g, b);
}

fn gui_lighten(int color, int amount) -> int {
    return gui_mix_color(color, gui_rgb(255, 255, 255), amount);
}

fn gui_darken(int color, int amount) -> int {
    return gui_mix_color(color, gui_rgb(0, 0, 0), amount);
}

fn _fb_u32(char* p, int off) -> int {
    int v = 0;
    int i = 3;
    while (i >= 0) {
        int b = _byte_val(*(p + off + i));
        v = v * 256 + b;
        i = i - 1;
    }
    return v;
}

fn _fb_px(int idx, int color) -> void {
    char* fb = cast<char*>(G_DRAW) + idx * 4;
    int b = color - (color / 256) * 256;
    int g = (color / 256) - (color / 65536) * 256;
    int r = color / 65536;
    *(fb + 0) = b;
    *(fb + 1) = g;
    *(fb + 2) = r;
    *(fb + 3) = 0;
}

fn _rd16(char* p, int off) -> int {
    int lo = _byte_val(*(p + off));
    int hi = _byte_val(*(p + off + 1));
    return lo + hi * 256;
}

fn _rd64(char* p, int off) -> int {
    int lo = _fb_u32(p, off);
    int hi = _fb_u32(p, off + 4);
    return hi * 65536 * 65536 + lo;
}

fn _wr8(char* p, int off, int v) -> void {
    *(p + off) = _byte_val(v);
}

fn _wr16(char* p, int off, int v) -> void {
    _wr8(p, off, v);
    _wr8(p, off + 1, v / 256);
}

fn _wr32(char* p, int off, int v) -> void {
    _wr16(p, off, v);
    _wr16(p, off + 2, v / 65536);
}

fn _wr64(char* p, int off, int v) -> void {
    _wr32(p, off, v);
    _wr32(p, off + 4, v / 65536 / 65536);
}

fn _zero(char* p, int n) -> void {
    int i = 0;
    while (i + 8 <= n) {
        *(cast<int*>(p + i)) = 0;
        i = i + 8;
    }
    while (i < n) { *(p + i) = 0; i = i + 1; }
}

fn _memcpy(char* d, char* s, int n) -> void {
    int i = 0;
    while (i + 8 <= n) {
        *(cast<int*>(d + i)) = *(cast<int*>(s + i));
        i = i + 8;
    }
    while (i < n) {
        *(d + i) = *(s + i);
        i = i + 1;
    }
}

fn _pad4(int n) -> int {
    int r = n - (n / 4) * 4;
    if (r == 0) { return n; }
    return n + 4 - r;
}

// ─── Real Linux Environment Reader (/proc/self/environ) ──
fn _real_get_env(string key) -> string {
    int fd = sys_open("/proc/self/environ", 0, 0);
    if (fd < 0) { return ""; }
    char* buf = alloc<char>(16384);
    _zero(buf, 16384);
    int n = sys_read(fd, buf, 16384);
    sys_close(fd);
    if (n <= 0) {
        free(buf);
        return "";
    }

    int klen = _str_len(key);
    char* kp = cast<char*>(key);
    int i = 0;
    while (i < n) {
        int matched = 1;
        int j = 0;
        while (j < klen) {
            if (_byte_val(*(buf + i + j)) != _byte_val(*(kp + j))) {
                matched = 0;
                j = klen;
            } else {
                j = j + 1;
            }
        }
        if (matched == 1 && _byte_val(*(buf + i + klen)) == 61) {
            int vstart = i + klen + 1;
            int vend = vstart;
            while (vend < n && _byte_val(*(buf + vend)) != 0) {
                vend = vend + 1;
            }
            int vlen = vend - vstart;
            char* val = alloc<char>(vlen + 2);
            _zero(val, vlen + 2);
            int k = 0;
            while (k < vlen) {
                *(val + k) = *(buf + vstart + k);
                k = k + 1;
            }
            *(val + k) = 0;
            free(buf);
            return cast<string>(val);
        }
        while (i < n && _byte_val(*(buf + i)) != 0) {
            i = i + 1;
        }
        i = i + 1;
    }
    free(buf);
    return "";
}

// ─── X11 MIT-MAGIC-COOKIE-1 Reader ───────────────────────
fn _x11_read_auth() -> int {
    string path = _real_get_env("XAUTHORITY");
    if (_str_len(path) == 0) {
        string home = _real_get_env("HOME");
        if (_str_len(home) == 0) { return 0; }
        char* buf = alloc<char>(256);
        _zero(buf, 256);
        char* hp = cast<char*>(home);
        int hi = 0;
        while (_byte_val(*(hp + hi)) != 0) {
            *(buf + hi) = *(hp + hi);
            hi = hi + 1;
        }
        char* suf = cast<char*>("/.Xauthority");
        int si = 0;
        while (_byte_val(*(suf + si)) != 0) {
            *(buf + hi + si) = *(suf + si);
            si = si + 1;
        }
        path = cast<string>(buf);
    }

    int fd = sys_open(path, 0, 0);
    if (fd < 0) { return 0; }

    char* abuf = alloc<char>(1024);
    _zero(abuf, 1024);
    int n = sys_read(fd, abuf, 1024);
    sys_close(fd);
    if (n < 16) {
        free(abuf);
        return 0;
    }

    int pos = 0;
    while (pos + 10 < n) {
        pos = pos + 2;
        int alen = _byte_val(*(abuf + pos)) * 256 + _byte_val(*(abuf + pos + 1));
        pos = pos + 2 + alen;
        if (pos + 4 >= n) { break; }
        int nlen = _byte_val(*(abuf + pos)) * 256 + _byte_val(*(abuf + pos + 1));
        pos = pos + 2 + nlen;
        if (pos + 4 >= n) { break; }
        int namelen = _byte_val(*(abuf + pos)) * 256 + _byte_val(*(abuf + pos + 1));
        pos = pos + 2;
        if (pos + namelen + 2 > n) { break; }
        char* nameptr = abuf + pos;
        pos = pos + namelen;
        int datalen = _byte_val(*(abuf + pos)) * 256 + _byte_val(*(abuf + pos + 1));
        pos = pos + 2;
        if (pos + datalen > n) { break; }
        char* dataptr = abuf + pos;

        G_X11_AUTH_NAME_LEN = namelen;
        G_X11_AUTH_DATA_LEN = datalen;
        G_X11_AUTH_NAME = alloc<char>(namelen + 4);
        _zero(G_X11_AUTH_NAME, namelen + 4);
        _memcpy(G_X11_AUTH_NAME, nameptr, namelen);
        G_X11_AUTH_DATA = alloc<char>(datalen + 4);
        _zero(G_X11_AUTH_DATA, datalen + 4);
        _memcpy(G_X11_AUTH_DATA, dataptr, datalen);

        free(abuf);
        return 1;
    }
    free(abuf);
    return 0;
}

fn _x11_send(char* buf, int len) -> int {
    int sent = 0;
    while (sent < len) {
        int n = sys_send(G_X11_FD, buf + sent, len - sent, 0);
        if (n <= 0) { return 0 - 1; }
        sent = sent + n;
    }
    return 0;
}

fn _x11_recv(char* buf, int len) -> int {
    int got = 0;
    while (got < len) {
        int n = sys_recv(G_X11_FD, buf + got, len - got, 0);
        if (n <= 0) { return 0 - 1; }
        got = got + n;
    }
    return got;
}

fn _x11_connect() -> int {
    int fd = sys_socket(AF_UNIX, X11_SOCK_STREAM, 0);
    if (fd < 0) { return 0 - 1; }

    int disp_num = 0;
    string disp = _real_get_env("DISPLAY");
    if (_str_len(disp) > 0) {
        char* dp = cast<char*>(disp);
        int di = 0;
        while (_byte_val(*(dp + di)) != 0) {
            if (*(dp + di) == 58) {
                int digit = _byte_val(*(dp + di + 1)) - 48;
                if (digit >= 0 && digit <= 9) {
                    disp_num = digit;
                }
            }
            di = di + 1;
        }
    }

    char* addr = alloc<char>(110);
    _zero(addr, 110);
    _wr16(addr, 0, AF_UNIX);
    char* basepath = cast<char*>("/tmp/.X11-unix/X");
    int bi = 0;
    while (_byte_val(*(basepath + bi)) != 0) {
        *(addr + 2 + bi) = *(basepath + bi);
        bi = bi + 1;
    }
    *(addr + 2 + bi) = 48 + disp_num;
    *(addr + 2 + bi + 1) = 0;

    int r = sys_connect(fd, addr, 110);
    free(addr);
    if (r < 0) {
        sys_close(fd);
        return 0 - 2;
    }

    G_X11_FD = fd;

    int has_auth = _x11_read_auth();
    int name_pad = _pad4(G_X11_AUTH_NAME_LEN);
    int data_pad = _pad4(G_X11_AUTH_DATA_LEN);
    int setup_len = 12;
    if (has_auth == 1) {
        setup_len = 12 + name_pad + data_pad;
    }

    char* setup = alloc<char>(setup_len);
    _zero(setup, setup_len);
    *(setup + 0) = 108;
    _wr16(setup, 2, 11);
    _wr16(setup, 4, 0);
    if (has_auth == 1) {
        _wr16(setup, 6, G_X11_AUTH_NAME_LEN);
        _wr16(setup, 8, G_X11_AUTH_DATA_LEN);
        _memcpy(setup + 12, G_X11_AUTH_NAME, G_X11_AUTH_NAME_LEN);
        _memcpy(setup + 12 + name_pad, G_X11_AUTH_DATA, G_X11_AUTH_DATA_LEN);
    }

    int sent = sys_send(fd, setup, setup_len, 0);
    free(setup);
    if (sent < setup_len) {
        sys_close(fd);
        return 0 - 3;
    }

    char* hdr = alloc<char>(8);
    _zero(hdr, 8);
    r = _x11_recv(hdr, 8);
    if (r < 8) {
        free(hdr);
        sys_close(fd);
        return 0 - 4;
    }
    int status = _byte_val(*(hdr + 0));
    if (status != 1) {
        free(hdr);
        sys_close(fd);
        return 0 - 5;
    }

    int add_len = _rd16(hdr, 6) * 4;
    free(hdr);

    char* info = alloc<char>(add_len + 16);
    _zero(info, add_len + 16);
    r = _x11_recv(info, add_len);
    if (r < add_len) {
        free(info);
        sys_close(fd);
        return 0 - 6;
    }

    G_X11_RID_BASE = _fb_u32(info, 4);
    int vendor_len = _rd16(info, 16);
    int num_formats = _byte_val(*(info + 21));
    int off = 32 + _pad4(vendor_len) + num_formats * 8;
    G_X11_ROOT = _fb_u32(info, off);
    G_X11_ROOT_VISUAL = _fb_u32(info, off + 32);
    G_X11_ROOT_DEPTH = _byte_val(*(info + off + 38));

    free(info);
    G_X11_RID_NEXT = 1;
    G_X11_CLOSE_REQ = 0;
    return 0;
}

fn _x11_intern_atom(string name, int only_if_exists) -> int {
    int name_len = _str_len(name);
    int req_len = 8 + _pad4(name_len);
    char* req = alloc<char>(req_len);
    _zero(req, req_len);
    *(req + 0) = X11_OP_INTERN_ATOM;
    *(req + 1) = only_if_exists;
    _wr16(req, 2, req_len / 4);
    _wr16(req, 4, name_len);
    char* np = cast<char*>(name);
    int i = 0;
    while (i < name_len) {
        *(req + 8 + i) = *(np + i);
        i = i + 1;
    }
    _x11_send(req, req_len);
    free(req);

    char* reply = alloc<char>(32);
    _zero(reply, 32);
    _x11_recv(reply, 32);
    int atom = _fb_u32(reply, 8);
    free(reply);
    return atom;
}

fn _x11_create_window(int x, int y, int w, int h) -> int {
    int wid = G_X11_RID_BASE + G_X11_RID_NEXT;
    G_X11_RID_NEXT = G_X11_RID_NEXT + 1;

    int req_len = 44;
    char* req = alloc<char>(req_len);
    _zero(req, req_len);
    *(req + 0) = X11_OP_CREATE_WINDOW;
    *(req + 1) = G_X11_ROOT_DEPTH;
    _wr16(req, 2, 11);
    _wr32(req, 4, wid);
    _wr32(req, 8, G_X11_ROOT);
    _wr16(req, 12, x);
    _wr16(req, 14, y);
    _wr16(req, 16, w);
    _wr16(req, 18, h);
    _wr16(req, 20, 1);
    _wr16(req, 22, 1);
    _wr32(req, 24, G_X11_ROOT_VISUAL);
    _wr32(req, 28, 2 + 8 + 2048);
    _wr32(req, 32, 0x141824);
    _wr32(req, 36, 0x36425a);
    _wr32(req, 40, X11_MASK_KEY + X11_MASK_BUTTON + X11_MASK_MOTION + X11_MASK_EXPOSE + X11_MASK_STRUCT);

    _x11_send(req, req_len);
    free(req);
    return wid;
}

fn _x11_set_title(int wid, string title) -> void {
    int tlen = _str_len(title);
    int req_len = 24 + _pad4(tlen);
    char* req = alloc<char>(req_len);
    _zero(req, req_len);
    *(req + 0) = X11_OP_CHANGE_PROP;
    *(req + 1) = 0;
    _wr16(req, 2, req_len / 4);
    _wr32(req, 4, wid);
    _wr32(req, 8, 39);
    _wr32(req, 12, 31);
    *(req + 16) = 8;
    _wr32(req, 20, tlen);
    char* tp = cast<char*>(title);
    int i = 0;
    while (i < tlen) {
        *(req + 24 + i) = *(tp + i);
        i = i + 1;
    }
    _x11_send(req, req_len);
    free(req);
}

fn _x11_setup_wm_delete(int wid) -> void {
    G_X11_ATOM_WM_PROTO = _x11_intern_atom("WM_PROTOCOLS", 0);
    G_X11_ATOM_WM_DEL = _x11_intern_atom("WM_DELETE_WINDOW", 0);

    int req_len = 28;
    char* req = alloc<char>(req_len);
    _zero(req, req_len);
    *(req + 0) = X11_OP_CHANGE_PROP;
    *(req + 1) = 0;
    _wr16(req, 2, req_len / 4);
    _wr32(req, 4, wid);
    _wr32(req, 8, G_X11_ATOM_WM_PROTO);
    _wr32(req, 12, 4);
    *(req + 16) = 32;
    _wr32(req, 20, 1);
    _wr32(req, 24, G_X11_ATOM_WM_DEL);
    _x11_send(req, req_len);
    free(req);
}

// Ask the window manager to show or hide the OS title bar / border.
// on = 1 keeps normal OS decorations, on = 0 makes the window borderless.
fn _x11_set_decorations(int wid, int on) -> void {
    int atom = _x11_intern_atom("_MOTIF_WM_HINTS", 0);
    int deco = 1;
    if (on == 0) { deco = 0; }
    int req_len = 44;
    char* req = alloc<char>(req_len);
    _zero(req, req_len);
    *(req + 0) = X11_OP_CHANGE_PROP;
    *(req + 1) = 0;
    _wr16(req, 2, req_len / 4);
    _wr32(req, 4, wid);
    _wr32(req, 8, atom);
    _wr32(req, 12, atom);
    *(req + 16) = 32;
    _wr32(req, 20, 5);
    _wr32(req, 24, 2);       // MWM_HINTS_DECORATIONS
    _wr32(req, 28, 0);       // functions
    _wr32(req, 32, deco);    // decorations
    _wr32(req, 36, 0);       // input mode
    _wr32(req, 40, 0);       // status
    _x11_send(req, req_len);
    free(req);
}

fn _x11_create_gc(int drawable) -> int {
    int gc = G_X11_RID_BASE + G_X11_RID_NEXT;
    G_X11_RID_NEXT = G_X11_RID_NEXT + 1;

    char* req = alloc<char>(16);
    _zero(req, 16);
    *(req + 0) = X11_OP_CREATE_GC;
    _wr16(req, 2, 4);
    _wr32(req, 4, gc);
    _wr32(req, 8, drawable);
    _wr32(req, 12, 0);
    _x11_send(req, 16);
    free(req);
    return gc;
}

fn _x11_map_window(int wid) -> void {
    char* req = alloc<char>(8);
    _zero(req, 8);
    *(req + 0) = X11_OP_MAP_WINDOW;
    _wr16(req, 2, 2);
    _wr32(req, 4, wid);
    _x11_send(req, 8);
    free(req);
}

fn _x11_put_image() -> void {
    if (G_X11_ACTIVE == 0 || G_DRAW <= 0) { return; }
    int w = G_X11_WIN_W;
    int h = G_X11_WIN_H;

    if (G_X11_REQ_BUF == 0) {
        G_X11_REQ_BUF = alloc<char>(262144);
    }

    int max_rows = 60000 / w;
    if (max_rows < 1) { max_rows = 1; }
    if (max_rows > h) { max_rows = h; }

    int row = 0;
    while (row < h) {
        int chunk = max_rows;
        if (row + chunk > h) { chunk = h - row; }
        int dbytes = w * chunk * 4;
        int preq_len = _pad4(24 + dbytes);

        char* req = G_X11_REQ_BUF;
        *(req + 0) = X11_OP_PUT_IMAGE;
        *(req + 1) = X11_IMAGE_Zpixmap;
        _wr16(req, 2, preq_len / 4);
        _wr32(req, 4, G_X11_WID);
        _wr32(req, 8, G_X11_GC);
        _wr16(req, 12, w);
        _wr16(req, 14, chunk);
        _wr16(req, 16, 0);
        _wr16(req, 18, row);
        *(req + 20) = 0;
        *(req + 21) = 24;
        _wr16(req, 22, 0);

        char* src = cast<char*>(G_DRAW) + row * w * 4;
        _memcpy(req + 24, src, dbytes);
        _x11_send(req, preq_len);
        row = row + chunk;
    }
}

// Forward declarations

// ─── Dynamic Fullscreen / Window Resize Handler ─────────
// Resizes backbuffer capacity and updates G_XRES / G_YRES smoothly without distortion.
// Heavy desktop redraw is skipped for non-desktop apps (e.g. vision_color) to avoid flicker/lag.
fn _x11_handle_resize(int new_w, int new_h) -> void {
    if (new_w <= 0 || new_h <= 0) { return; }
    int req_bytes = new_w * new_h * 4;

    // Check if we need to expand backing buffer
    if (req_bytes > G_FB_CAPACITY) {
        if (G_BACK > 0) {
            sys_munmap(G_BACK, G_FB_CAPACITY);
        }
        // Allocate with generous 4MB headroom to avoid constant re-mmap during dragging
        G_FB_CAPACITY = req_bytes + 4194304;
        G_BACK = sys_mmap(0, G_FB_CAPACITY, PROT_RW, MAP_PRIVATE + MAP_ANONYMOUS, 0 - 1, 0);
        G_DRAW = G_BACK;
        G_FB_ADDR = G_BACK;
    }

    G_X11_WIN_W = new_w;
    G_X11_WIN_H = new_h;
    G_XRES = new_w;
    G_YRES = new_h;
    G_FB_WIDTH = new_w;
    G_FB_HEIGHT = new_h;
    G_FB_SIZE = req_bytes;

    // Only desktop/app-mode GUIs should trigger dsk layout redraw during resize.
    if (DSK_READY == 1) {
        dsk_on_resize();
        _x11_put_image();
    }
}

fn _x11_process_events() -> void {
    if (G_X11_ACTIVE == 0) { return; }

    char* pfd = alloc<char>(8);
    _zero(pfd, 8);
    _wr32(pfd, 0, G_X11_FD);
    _wr16(pfd, 4, 1);
    int pr = sys_poll(pfd, 1, 0);
    if (pr <= 0) {
        free(pfd);
        return;
    }
    free(pfd);

    if (G_X11_EVBUF == 0) {
        G_X11_EVBUF = alloc<char>(32);
    }

    int max_ev = 64;
    int ei = 0;
    while (ei < max_ev) {
        char* pfd2 = alloc<char>(8);
        _zero(pfd2, 8);
        _wr32(pfd2, 0, G_X11_FD);
        _wr16(pfd2, 4, 1);
        int pr2 = sys_poll(pfd2, 1, 0);
        free(pfd2);
        if (pr2 <= 0) { return; }

        _zero(G_X11_EVBUF, 32);
        // Use MSG_DONTWAIT (64) to avoid blocking the desktop loop when poll
        // reports stale/readiness or partial event data is unavailable.
        int n = sys_recv(G_X11_FD, G_X11_EVBUF, 32, 64);
        if (n < 32) { return; }

        int code = _byte_val(*(G_X11_EVBUF + 0));
        code = code - (code / 128) * 128;

        if (code == X11_EV_EXPOSE) {
            // Expose w/h are the exposed region, not window size; just repaint.
            _x11_put_image();
        }
        else if (code == X11_EV_CONFIGURE) {
            int new_w = _rd16(G_X11_EVBUF, 20);
            int new_h = _rd16(G_X11_EVBUF, 22);
            if (new_w > 0 && new_h > 0 && (new_w != G_XRES || new_h != G_YRES)) {
                _x11_handle_resize(new_w, new_h);
            }
        }
        else if (code == X11_EV_BUTTON_PRESS) {
            int bx = _rd16(G_X11_EVBUF, 24);
            int by = _rd16(G_X11_EVBUF, 26);
            int btn = _byte_val(*(G_X11_EVBUF + 1));
            G_MOUSE_X = bx;
            G_MOUSE_Y = by;
            if (btn == 1) {
                G_MOUSE_BTN = 1;
                if (G_MOUSE_PREV_BTN == 0) {
                    G_MOUSE_CLICK = 1;
                }
                G_MOUSE_PREV_BTN = 1;
            }
            else if (btn == 3) {
                G_MOUSE_RIGHT = 1;
                G_MOUSE_RIGHT_CLICK = 1;
            }
            else if (btn == 4) { G_MOUSE_WHEEL = G_MOUSE_WHEEL - 1; }
            else if (btn == 5) { G_MOUSE_WHEEL = G_MOUSE_WHEEL + 1; }
        }
        else if (code == X11_EV_BUTTON_RELEASE) {
            int bx = _rd16(G_X11_EVBUF, 24);
            int by = _rd16(G_X11_EVBUF, 26);
            int btn = _byte_val(*(G_X11_EVBUF + 1));
            G_MOUSE_X = bx;
            G_MOUSE_Y = by;
            if (btn == 1) {
                G_MOUSE_BTN = 0;
                G_MOUSE_PREV_BTN = 0;
            }
            else if (btn == 3) { G_MOUSE_RIGHT = 0; }
        }
        else if (code == X11_EV_MOTION_NOTIFY) {
            int mx = _rd16(G_X11_EVBUF, 24);
            int my = _rd16(G_X11_EVBUF, 26);
            G_MOUSE_X = mx;
            G_MOUSE_Y = my;
        }
        else if (code == X11_EV_KEY_PRESS) {
            int keycode = _byte_val(*(G_X11_EVBUF + 1));
            if (keycode == 50 || keycode == 62) { G_KB_SHIFT = 1; }
            else if (keycode == 37 || keycode == 105) { G_KB_CTRL = 1; }
            else if (keycode == 66) { G_KB_CAPS = 1 - G_KB_CAPS; }
            else {
                int k = _x11_key_ascii(keycode);
                if (k >= 0 && G_KB_COUNT < 64 && G_KB_QUEUE > 0) {
                    char* q = cast<char*>(G_KB_QUEUE);
                    *(q + G_KB_HEAD) = k;
                    if (G_KB_MODQ > 0) {
                        char* mq = cast<char*>(G_KB_MODQ);
                        *(mq + G_KB_HEAD) = G_KB_CTRL + G_KB_SHIFT * 2;
                    }
                    G_KB_HEAD = G_KB_HEAD + 1;
                    if (G_KB_HEAD >= 64) { G_KB_HEAD = 0; }
                    G_KB_COUNT = G_KB_COUNT + 1;
                }
            }
        }
        else if (code == X11_EV_KEY_RELEASE) {
            int keycode = _byte_val(*(G_X11_EVBUF + 1));
            if (keycode == 50 || keycode == 62) { G_KB_SHIFT = 0; }
            else if (keycode == 37 || keycode == 105) { G_KB_CTRL = 0; }
        }
        else if (code == X11_EV_CLIENT_MESSAGE) {
            int msg_type = _fb_u32(G_X11_EVBUF, 8);
            int data0 = _fb_u32(G_X11_EVBUF, 12);
            if (msg_type == G_X11_ATOM_WM_PROTO && data0 == G_X11_ATOM_WM_DEL) {
                G_X11_CLOSE_REQ = 1;
            }
        }
        ei = ei + 1;
    }
}

fn _x11_init(int w, int h, string title) -> int {
    int r = _x11_connect();
    if (r < 0) { return r; }

    G_X11_WIN_W = w;
    G_X11_WIN_H = h;
    G_XRES = w;
    G_YRES = h;
    G_BPP = 32;

    G_X11_WID = _x11_create_window(100, 100, w, h);
    _x11_set_title(G_X11_WID, title);
    _x11_setup_wm_delete(G_X11_WID);
    G_X11_GC = _x11_create_gc(G_X11_WID);
    _x11_map_window(G_X11_WID);

    // Initial buffer capacity: 4K (3840x2160x4 = 33MB virtual memory)
    // Anonymous memory only commits physical RAM on demand!
    G_FB_CAPACITY = 3840 * 2160 * 4;
    G_FB_SIZE = w * h * 4;
    G_BACK = sys_mmap(0, G_FB_CAPACITY, PROT_RW, MAP_PRIVATE + MAP_ANONYMOUS, 0 - 1, 0);
    if (G_BACK == 0 - 1 || G_BACK == 0) {
        G_FB_CAPACITY = G_FB_SIZE;
        G_BACK = cast<int>(alloc<char>(G_FB_SIZE));
    }
    G_DRAW = G_BACK;
    G_FB_ADDR = G_BACK;
    G_FB_WIDTH = w;
    G_FB_HEIGHT = h;
    G_X11_ACTIVE = 1;

    G_KB_QUEUE = cast<int>(alloc<char>(64));
    G_KB_MODQ = cast<int>(alloc<char>(64));
    G_KB_HEAD = 0;
    G_KB_COUNT = 0;
    G_X11_EVBUF = alloc<char>(32);
    G_X11_REQ_BUF = alloc<char>(262144);

    G_MOUSE_X = w / 2;
    G_MOUSE_Y = h / 2;
    G_MOUSE_BTN = 0;
    G_MOUSE_PREV_BTN = 0;
    G_MOUSE_CLICK = 0;

    sleep_ms(30);
    _x11_process_events();
    return 0;
}

fn _x11_shutdown() -> void {
    if (G_X11_ACTIVE == 0) { return; }

    if (G_X11_GC > 0) {
        char* req = alloc<char>(8);
        _zero(req, 8);
        *(req + 0) = X11_OP_FREE_GC;
        _wr16(req, 2, 2);
        _wr32(req, 4, G_X11_GC);
        _x11_send(req, 8);
        free(req);
    }
    if (G_X11_WID > 0) {
        char* req = alloc<char>(8);
        _zero(req, 8);
        *(req + 0) = X11_OP_DESTROY_WINDOW;
        _wr16(req, 2, 2);
        _wr32(req, 4, G_X11_WID);
        _x11_send(req, 8);
        free(req);
    }
    if (G_X11_FD > 0) {
        sys_close(G_X11_FD);
    }
    if (G_X11_EVBUF != 0) {
        free(G_X11_EVBUF);
        G_X11_EVBUF = 0;
    }
    if (G_X11_REQ_BUF != 0) {
        free(G_X11_REQ_BUF);
        G_X11_REQ_BUF = 0;
    }
    if (G_BACK > 0) {
        sys_munmap(G_BACK, G_FB_CAPACITY);
        G_BACK = 0;
        G_DRAW = 0;
        G_FB_ADDR = 0;
    }
    G_X11_ACTIVE = 0;
    G_X11_FD = 0 - 1;
    G_X11_WID = 0;
    G_X11_GC = 0;
}

fn gui_close_requested() -> int {
    return G_X11_CLOSE_REQ;
}

fn gui_is_x11() -> int {
    return G_X11_ACTIVE;
}

fn gui_is_framebuffer() -> int {
    if (G_X11_ACTIVE == 1) { return 0; }
    if (G_FB_FD > 0 || G_DRM_ACTIVE == 1) { return 1; }
    return 0;
}

// Enable or disable the OS window decorations (title bar + border).
// Useful to avoid a double title bar when the app draws its own.
fn gui_set_decorated(int on) -> void {
    if (G_X11_ACTIVE == 1 && G_X11_WID > 0) {
        _x11_set_decorations(G_X11_WID, on);
    }
}

// ─── Direct DRM/KMS Hardware (card0) ─────────────────────
fn _drm_open() -> int {
    int fd = sys_open("/dev/dri/card0", O_RDWR, 0);
    if (fd >= 0) { return fd; }
    fd = sys_open("/dev/dri/card1", O_RDWR, 0);
    if (fd >= 0) { return fd; }
    return sys_open("/dev/dri/card2", O_RDWR, 0);
}

fn _drm_pick_connector(int fd, int nconn, char* conn_ids, char* modebuf) -> int {
    int c = 0;
    while (c < nconn) {
        int cid = _fb_u32(conn_ids, c * 4);
        char* cq = alloc<char>(80);
        _zero(cq, 80);
        _wr32(cq, 48, cid);
        sys_ioctl(fd, DRM_IOCTL_GETCONNECTOR, cast<int>(cq));
        int stat = _fb_u32(cq, 60);
        int nmodes = _fb_u32(cq, 32);
        int nencs = _fb_u32(cq, 40);
        if (stat == DRM_MODE_CONNECTED && nmodes > 0) {
            char* modes = alloc<char>(nmodes * 68 + 16);
            char* encs = alloc<char>(nencs * 4 + 16);
            _zero(modes, nmodes * 68 + 16);
            _zero(encs, nencs * 4 + 16);
            _wr64(cq, 8, cast<int>(modes));
            _wr64(cq, 0, cast<int>(encs));
            _wr32(cq, 32, nmodes);
            _wr32(cq, 40, nencs);
            int r = sys_ioctl(fd, DRM_IOCTL_GETCONNECTOR, cast<int>(cq));
            if (r >= 0) {
                int best = 0;
                int mi = 0;
                while (mi < nmodes) {
                    int mt = _fb_u32(modes, mi * 68 + 32);
                    int nonpf = mt / DRM_MODE_TYPE_PREFERRED;
                    if (nonpf - (nonpf / 2) * 2 == 1) {
                        best = mi;
                        mi = nmodes;
                    } else {
                        mi = mi + 1;
                    }
                }
                _memcpy(modebuf, modes + best * 68, 68);
                G_DRM_CONN_ID = cid;
                G_DRM_ENC_ID = _fb_u32(cq, 44);
                free(modes);
                free(encs);
                free(cq);
                return 1;
            }
            free(modes);
            free(encs);
        }
        free(cq);
        c = c + 1;
    }
    return 0;
}

fn _drm_init() -> int {
    int fd = _drm_open();
    if (fd < 0) { return 1; }

    char* res = alloc<char>(64);
    _zero(res, 64);
    int r = sys_ioctl(fd, DRM_IOCTL_GETRESOURCES, cast<int>(res));
    int nconn = _fb_u32(res, 40);
    int ncrts = _fb_u32(res, 36);
    if (r < 0 || nconn <= 0) {
        free(res);
        sys_close(fd);
        return 2;
    }
    char* conn_ids = alloc<char>(nconn * 4 + 16);
    char* crtc_ids = alloc<char>(ncrts * 4 + 16);
    _zero(conn_ids, nconn * 4 + 16);
    _zero(crtc_ids, ncrts * 4 + 16);
    _wr64(res, 16, cast<int>(conn_ids));
    if (ncrts > 0) {
        _wr64(res, 8, cast<int>(crtc_ids));
    }
    r = sys_ioctl(fd, DRM_IOCTL_GETRESOURCES, cast<int>(res));
    free(res);
    if (r < 0) {
        free(conn_ids);
        free(crtc_ids);
        sys_close(fd);
        return 3;
    }

    char* modebuf = alloc<char>(68);
    _zero(modebuf, 68);
    int ok = _drm_pick_connector(fd, nconn, conn_ids, modebuf);
    free(conn_ids);
    free(crtc_ids);
    if (ok == 0) {
        free(modebuf);
        sys_close(fd);
        return 4;
    }
    G_XRES = _rd16(modebuf, 4);
    G_YRES = _rd16(modebuf, 14);
    if (G_XRES <= 0 || G_YRES <= 0) {
        free(modebuf);
        sys_close(fd);
        return 5;
    }

    char* enc = alloc<char>(24);
    _zero(enc, 24);
    _wr32(enc, 0, G_DRM_ENC_ID);
    r = sys_ioctl(fd, DRM_IOCTL_GETENCODER, cast<int>(enc));
    int crtc_id = 0;
    if (r >= 0) { crtc_id = _fb_u32(enc, 8); }
    free(enc);
    if (crtc_id <= 0) {
        free(modebuf);
        sys_close(fd);
        return 6;
    }
    G_DRM_CRTC_ID = crtc_id;

    char* dum = alloc<char>(32);
    _zero(dum, 32);
    _wr32(dum, 0, G_YRES);
    _wr32(dum, 4, G_XRES);
    _wr32(dum, 8, 32);
    r = sys_ioctl(fd, DRM_IOCTL_CREATE_DUMB, cast<int>(dum));
    if (r < 0) {
        free(dum);
        free(modebuf);
        sys_close(fd);
        return 7;
    }
    int handle = _fb_u32(dum, 16);
    int pitch = _fb_u32(dum, 20);
    int dsize = _rd64(dum, 24);
    free(dum);
    if (dsize <= 0) {
        free(modebuf);
        sys_close(fd);
        return 8;
    }

    char* mp = alloc<char>(16);
    _zero(mp, 16);
    _wr32(mp, 0, handle);
    r = sys_ioctl(fd, DRM_IOCTL_MAP_DUMB, cast<int>(mp));
    if (r < 0) {
        free(mp);
        free(modebuf);
        sys_close(fd);
        return 9;
    }
    int boff = _rd64(mp, 8);
    free(mp);

    int faddr = sys_mmap(0, dsize, PROT_RW, MAP_SHARED, fd, boff);
    if (faddr == 0 - 1) {
        free(modebuf);
        sys_close(fd);
        return 10;
    }

    char* fbw = alloc<char>(32);
    _zero(fbw, 32);
    _wr32(fbw, 4, G_XRES);
    _wr32(fbw, 8, G_YRES);
    _wr32(fbw, 12, pitch);
    _wr32(fbw, 16, 32);
    _wr32(fbw, 20, 24);
    _wr32(fbw, 24, handle);
    r = sys_ioctl(fd, DRM_IOCTL_ADDFB, cast<int>(fbw));
    if (r < 0) {
        free(fbw);
        free(modebuf);
        sys_munmap(faddr, dsize);
        sys_close(fd);
        return 11;
    }
    int fbid = _fb_u32(fbw, 0);
    free(fbw);

    char* connref = alloc<char>(8);
    _zero(connref, 8);
    _wr32(connref, 0, G_DRM_CONN_ID);
    char* crtc = alloc<char>(104);
    _zero(crtc, 104);
    _wr64(crtc, 0, cast<int>(connref));
    _wr32(crtc, 8, 1);
    _wr32(crtc, 12, crtc_id);
    _wr32(crtc, 16, fbid);
    _wr32(crtc, 20, 0);
    _wr32(crtc, 24, 0);
    _wr32(crtc, 28, 0);
    _wr32(crtc, 32, 1);
    _memcpy(crtc + 36, modebuf, 68);
    r = sys_ioctl(fd, DRM_IOCTL_SETCRTC, cast<int>(crtc));
    free(crtc);
    free(connref);
    if (r < 0) {
        sys_munmap(faddr, dsize);
        sys_close(fd);
        return 12;
    }

    G_FB_FD = fd;
    G_FB_ADDR = faddr;
    G_FB_SIZE = dsize;
    G_BPP = 32;
    G_DRM_ACTIVE = 1;
    G_DRM_FB_ID = fbid;
    G_DRM_HANDLE = handle;
    G_DRM_PITCH = pitch;
    G_DRM_MODE = cast<int>(modebuf);

    G_BACK = sys_mmap(0, G_FB_SIZE, PROT_RW, MAP_PRIVATE + MAP_ANONYMOUS, 0 - 1, 0);
    if (G_BACK == 0 - 1 || G_BACK == 0) {
        G_BACK = 0;
        G_DRAW = G_FB_ADDR;
    } else {
        G_DRAW = G_BACK;
    }

    G_FB_WIDTH = G_XRES;
    G_FB_HEIGHT = G_YRES;
    return 0;
}

fn _fb_init() -> int {
    int drm_err = _drm_init();
    if (drm_err == 0) {
        G_MOUSE_FD = sys_open("/dev/input/mice", O_RDONLY + O_NONBLOCK, 0);
        G_MOUSE_X = G_XRES / 2;
        G_MOUSE_Y = G_YRES / 2;
        G_MBUF = cast<int>(alloc<char>(8));
        return 0;
    }

    G_FB_FD = sys_open("/dev/fb0", O_RDWR, 0);
    if (G_FB_FD < 0) {
        return 1;
    }

    char* info = alloc<char>(200);
    int r = sys_ioctl(G_FB_FD, FBIOGET_VSCREENINFO, cast<int>(info));
    if (r < 0) {
        free(info);
        sys_close(G_FB_FD);
        return 2;
    }

    G_XRES = _fb_u32(info, 0);
    G_YRES = _fb_u32(info, 4);
    G_BPP = _fb_u32(info, 24);
    free(info);

    if (G_BPP != 32) {
        sys_close(G_FB_FD);
        return 3;
    }

    G_FB_SIZE = G_XRES * G_YRES * 4;
    G_FB_ADDR = sys_mmap(0, G_FB_SIZE, PROT_RW, MAP_SHARED, G_FB_FD, 0);
    if (G_FB_ADDR == 0 - 1) {
        sys_close(G_FB_FD);
        return 4;
    }

    G_BACK = sys_mmap(0, G_FB_SIZE, PROT_RW, MAP_PRIVATE + MAP_ANONYMOUS, 0 - 1, 0);
    if (G_BACK == 0 - 1 || G_BACK == 0) {
        G_BACK = 0;
        G_DRAW = G_FB_ADDR;
    } else {
        G_DRAW = G_BACK;
    }

    G_FB_WIDTH = G_XRES;
    G_FB_HEIGHT = G_YRES;
    G_MOUSE_FD = sys_open("/dev/input/mice", O_RDONLY + O_NONBLOCK, 0);
    G_MOUSE_X = G_XRES / 2;
    G_MOUSE_Y = G_YRES / 2;
    G_MBUF = cast<int>(alloc<char>(8));
    return 0;
}

fn _load_font() -> void {
    G_FONT = "000000000000000000000000000000000000183c3c3c18181800181800000000006666662400000000000000000000000000006c6cfe6c6c6cfe6c6c0000000018187cc6c2c07c060686c67c1818000000000000c2c60c183060c686000000000000386c6c3876dccccccc76000000000030303020000000000000000000000000000c18303030303030180c00000000000030180c0c0c0c0c0c1830000000000000000000663cff3c66000000000000000000000018187e18180000000000000000000000000000001818183000000000000000000000fe0000000000000000000000000000000000001818000000000000000002060c183060c080000000000000386cc6c6d6d6c6c66c380000000000001838781818181818187e0000000000007cc6060c183060c0c6fe0000000000007cc606063c060606c67c0000000000000c1c3c6cccfe0c0c0c1e000000000000fec0c0c0fc060606c67c0000000000003860c0c0fcc6c6c6c67c000000000000fec606060c18303030300000000000007cc6c6c67cc6c6c6c67c0000000000007cc6c6c67e0606060c78000000000000000018180000001818000000000000000000181800000018183000000000000000060c18306030180c060000000000000000007e00007e000000000000000000006030180c060c1830600000000000007cc6c60c181818001818000000000000007cc6c6dedededcc07c00000000000010386cc6c6fec6c6c6c6000000000000fc6666667c66666666fc0000000000003c66c2c0c0c0c0c2663c000000000000f86c6666666666666cf8000000000000fe6662687868606266fe000000000000fe6662687868606060f00000000000003c66c2c0c0dec6c6663a000000000000c6c6c6c6fec6c6c6c6c60000000000003c18181818181818183c0000000000001e0c0c0c0c0ccccccc78000000000000e666666c78786c6666e6000000000000f06060606060606266fe000000000000c6eefefed6c6c6c6c6c6000000000000c6e6f6fedecec6c6c6c60000000000007cc6c6c6c6c6c6c6c67c000000000000fc6666667c60606060f00000000000007cc6c6c6c6c6c6d6de7c0c0e00000000fc6666667c6c666666e60000000000007cc6c660380c06c6c67c0000000000007e7e5a1818181818183c000000000000c6c6c6c6c6c6c6c6c67c000000000000c6c6c6c6c6c6c66c3810000000000000c6c6c6c6d6d6d6feee6c000000000000c6c66c7c38387c6cc6c6000000000000666666663c181818183c000000000000fec6860c183060c2c6fe0000000000003c30303030303030303c0000000000000080c0e070381c0e06020000000000003c0c0c0c0c0c0c0c0c3c0000000010386cc600000000000000000000000000000000000000000000000000ff0000303018000000000000000000000000000000000000780c7ccccccc76000000000000e06060786c666666667c0000000000000000007cc6c0c0c0c67c0000000000001c0c0c3c6ccccccccc760000000000000000007cc6fec0c0c67c000000000000386c6460f060606060f000000000000000000076cccccccccc7c0ccc78000000e060606c7666666666e60000000000001818003818181818183c0000000000000606000e06060606060666663c000000e06060666c78786c66e60000000000003818181818181818183c000000000000000000ecfed6d6d6d6c6000000000000000000dc6666666666660000000000000000007cc6c6c6c6c67c000000000000000000dc66666666667c6060f000000000000076cccccccccc7c0c0c1e000000000000dc7666606060f00000000000000000007cc660380cc67c000000000000103030fc30303030361c000000000000000000cccccccccccc7600000000000000000066666666663c18000000000000000000c6c6d6d6d6fe6c000000000000000000c66c3838386cc6000000000000000000c6c6c6c6c6c67e060cf8000000000000fecc183060c6fe0000000000000e18181870181818180e00000000000018181818181818181818000000000000701818180e181818187000000000000076dc000000000000000000000000";
}

// ─── Dual-Mode Public Init Functions ──────────────────────
fn gui_init_window(int width, int height, string title) -> int {
    _load_font();
    int r = _x11_init(width, height, title);
    if (r == 0) { return 0; }
    return _fb_init();
}

fn gui_init_framebuffer() -> int {
    _load_font();
    return _fb_init();
}

fn gui_init_card0() -> int {
    _load_font();
    return _fb_init();
}

fn gui_init() -> int {
    _load_font();
    string disp = _real_get_env("DISPLAY");
    if (_str_len(disp) > 0) {
        int r = _x11_init(800, 560, "Falcon App");
        if (r == 0) { return 0; }
    }
    return _fb_init();
}

fn gui_shutdown() -> void {
    if (G_X11_ACTIVE == 1) {
        _x11_shutdown();
    }
    if (G_BACK > 0 && G_X11_ACTIVE == 0) {
        sys_munmap(G_BACK, G_FB_SIZE);
        G_BACK = 0;
        G_DRAW = 0;
    }
    if (G_FB_ADDR > 0 && G_X11_ACTIVE == 0) {
        sys_munmap(G_FB_ADDR, G_FB_SIZE);
        G_FB_ADDR = 0;
    }
    if (G_DRM_ACTIVE == 1) {
        if (G_DRM_FB_ID > 0 && G_FB_FD > 0) {
            char* rm = alloc<char>(8);
            _zero(rm, 8);
            _wr32(rm, 0, G_DRM_FB_ID);
            sys_ioctl(G_FB_FD, DRM_IOCTL_RMFB, cast<int>(rm));
            free(rm);
            G_DRM_FB_ID = 0;
        }
        if (G_DRM_HANDLE > 0 && G_FB_FD > 0) {
            char* dd = alloc<char>(8);
            _zero(dd, 8);
            _wr32(dd, 0, G_DRM_HANDLE);
            sys_ioctl(G_FB_FD, DRM_IOCTL_DESTROY_DUMB, cast<int>(dd));
            free(dd);
            G_DRM_HANDLE = 0;
        }
        if (G_DRM_MODE > 0) {
            free(cast<char*>(G_DRM_MODE));
            G_DRM_MODE = 0;
        }
        G_DRM_ACTIVE = 0;
    }
    if (G_FB_FD > 0) {
        sys_close(G_FB_FD);
        G_FB_FD = 0;
    }
    if (G_MOUSE_FD >= 0) {
        sys_close(G_MOUSE_FD);
        G_MOUSE_FD = 0 - 1;
    }
    G_MOUSE_PENDING = 0;
    G_MOUSE_BTN = 0;
    G_MOUSE_PREV_BTN = 0;
    G_MOUSE_CLICK = 0;
    if (G_MBUF > 0) {
        free(cast<char*>(G_MBUF));
        G_MBUF = 0;
    }
}

// ─── Drawing Primitives ──────────────────────────────────
fn gui_clear(int color) -> void {
    if (G_DRAW <= 0) { return; }
    int b = color - (color / 256) * 256;
    int total_bytes = G_XRES * G_YRES * 4;
    if (G_BPP == 32) {
        int g = (color / 256) - (color / 65536) * 256;
        int r = color / 65536;
        int pix = (r * 65536) + (g * 256) + b;
        int qw = pix + pix * 4294967296;
        char* fb = cast<char*>(G_DRAW);
        int i = 0;
        while (i + 32 <= total_bytes) {
            *(cast<int*>(fb + i)) = qw;
            *(cast<int*>(fb + i + 8)) = qw;
            *(cast<int*>(fb + i + 16)) = qw;
            *(cast<int*>(fb + i + 24)) = qw;
            i = i + 32;
        }
        while (i + 8 <= total_bytes) {
            *(cast<int*>(fb + i)) = qw;
            i = i + 8;
        }
        while (i < total_bytes) {
            *(fb + i) = 0;
            i = i + 1;
        }
    } else if (G_BPP == 8) {
        char* fb = cast<char*>(G_DRAW);
        int total = G_XRES * G_YRES;
        int i = 0;
        while (i < total) {
            *(fb + i) = b;
            i = i + 1;
        }
    }
}

fn gui_present() -> void {
    if (G_X11_ACTIVE == 1) {
        _x11_put_image();
        return;
    }

    if (G_BACK <= 0 || G_FB_ADDR <= 0) { return; }
    int rowbytes = G_XRES * 4;
    if (G_DRM_ACTIVE == 1 && G_DRM_PITCH != rowbytes) {
        char* src = cast<char*>(G_BACK);
        char* dst = cast<char*>(G_FB_ADDR);
        int y = 0;
        while (y < G_YRES) {
            char* srow = src + y * rowbytes;
            char* drow = dst + y * G_DRM_PITCH;
            int i = 0;
            while (i < rowbytes) {
                *(drow + i) = *(srow + i);
                i = i + 1;
            }
            y = y + 1;
        }
        return;
    }
    char* src = cast<char*>(G_BACK);
    char* dst = cast<char*>(G_FB_ADDR);
    int total = G_XRES * G_YRES * 4;
    int i = 0;
    while (i + 8 <= total) {
        *(cast<int*>(dst + i)) = *(cast<int*>(src + i));
        i = i + 8;
    }
    while (i < total) {
        *(dst + i) = *(src + i);
        i = i + 1;
    }
}

fn gui_put_pixel(int x, int y, int color) -> void {
    if (G_DRAW <= 0) { return; }
    if (x < 0 || y < 0) { return; }
    if (x >= G_XRES || y >= G_YRES) { return; }
    int pixel_idx = y * G_XRES + x;
    if (G_BPP == 32) {
        _fb_px(pixel_idx, color);
    } else if (G_BPP == 8) {
        char* fb = cast<char*>(G_DRAW) + pixel_idx;
        *(fb) = color - (color / 256) * 256;
    }
}

fn gui_fill_rect(int x, int y, int w, int h, int color) -> void {
    if (G_DRAW <= 0) { return; }
    if (x >= G_XRES || y >= G_YRES) { return; }
    if (x + w <= 0 || y + h <= 0) { return; }
    int x0 = x;
    if (x0 < 0) { x0 = 0; }
    int y0 = y;
    if (y0 < 0) { y0 = 0; }
    int x1 = x + w;
    if (x1 > G_XRES) { x1 = G_XRES; }
    int y1 = y + h;
    if (y1 > G_YRES) { y1 = G_YRES; }
    int b = color - (color / 256) * 256;
    int g = (color / 256) - (color / 65536) * 256;
    int r = color / 65536;
    char* fb = cast<char*>(G_DRAW);
    int pix = (r * 65536) + (g * 256) + b;
    int qw = pix + pix * 4294967296;
    int ry = y0;
    while (ry < y1) {
        int rowbase = ry * G_XRES;
        int cx = x0;
        while (cx + 2 <= x1) {
            *(cast<int*>(fb + (rowbase + cx) * 4)) = qw;
            cx = cx + 2;
        }
        if (cx < x1) {
            int o = (rowbase + cx) * 4;
            *(fb + o + 0) = b;
            *(fb + o + 1) = g;
            *(fb + o + 2) = r;
            *(fb + o + 3) = 0;
            cx = cx + 1;
        }
        ry = ry + 1;
    }
}

fn gui_draw_rect(int x, int y, int w, int h, int color) -> void {
    gui_fill_rect(x, y, w, 1, color);
    gui_fill_rect(x, y + h - 1, w, 1, color);
    gui_fill_rect(x, y, 1, h, color);
    gui_fill_rect(x + w - 1, y, 1, h, color);
}

// ─── Professional Decorative Primitives ──────────────────

// Vertical Gradient Fill (Top to Bottom)
fn gui_fill_gradient_v(int x, int y, int w, int h, int col_top, int col_bot) -> void {
    if (G_DRAW <= 0 || h <= 0) { return; }
    int r0 = col_top / 65536;
    int g0 = (col_top / 256) - r0 * 256;
    int b0 = col_top - (col_top / 256) * 256;

    int r1 = col_bot / 65536;
    int g1 = (col_bot / 256) - r1 * 256;
    int b1 = col_bot - (col_bot / 256) * 256;

    int row = 0;
    while (row < h) {
        int r = r0 + (r1 - r0) * row / h;
        int g = g0 + (g1 - g0) * row / h;
        int b = b0 + (b1 - b0) * row / h;
        int col = r * 65536 + g * 256 + b;
        gui_fill_rect(x, y + row, w, 1, col);
        row = row + 1;
    }
}

// Horizontal Gradient Fill (Left to Right)
fn gui_fill_gradient_h(int x, int y, int w, int h, int col_left, int col_right) -> void {
    if (G_DRAW <= 0 || w <= 0) { return; }
    int r0 = col_left / 65536;
    int g0 = (col_left / 256) - r0 * 256;
    int b0 = col_left - (col_left / 256) * 256;

    int r1 = col_right / 65536;
    int g1 = (col_right / 256) - r1 * 256;
    int b1 = col_right - (col_right / 256) * 256;

    int col = 0;
    while (col < w) {
        int r = r0 + (r1 - r0) * col / w;
        int g = g0 + (g1 - g0) * col / w;
        int b = b0 + (b1 - b0) * col / w;
        int c = r * 65536 + g * 256 + b;
        gui_fill_rect(x + col, y, 1, h, c);
        col = col + 1;
    }
}

// Vertical gradient with only the top two corners rounded (title bars).
fn gui_fill_top_rounded_gradient_v(int x, int y, int w, int h, int r, int col_top, int col_bot) -> void {
    if (G_DRAW <= 0 || w <= 0 || h <= 0) { return; }
    if (r < 0) { r = 0; }
    if (r > w / 2) { r = w / 2; }
    if (r > h) { r = h; }
    int r0 = col_top / 65536;
    int g0 = (col_top / 256) - r0 * 256;
    int b0 = col_top - (col_top / 256) * 256;
    int r1 = col_bot / 65536;
    int g1 = (col_bot / 256) - r1 * 256;
    int b1 = col_bot - (col_bot / 256) * 256;
    int row = 0;
    while (row < h) {
        int cr = r0 + (r1 - r0) * row / h;
        int cg = g0 + (g1 - g0) * row / h;
        int cb = b0 + (b1 - b0) * row / h;
        int col = cr * 65536 + cg * 256 + cb;
        int l = x * 256;
        int rr = (x + w) * 256;
        if (row < r) {
            if (_round_span_fp(x, y, w, 2 * r, r, y + row) == 1) {
                l = _SPAN_L;
                rr = _SPAN_R;
            }
        }
        _gui_blend_span_fp(l, rr, y + row, col, 255);
        row = row + 1;
    }
}

// ─── CSS-like Rounded Rectangles (anti-aliased) ──────────
// Fixed-point 8.8 span scratch (single-threaded renderer).
static int _SPAN_L = 0;
static int _SPAN_R = 0;

fn _isqrt(int n) -> int {
    if (n <= 0) { return 0; }
    if (n < 4) { return 1; }
    int x = n;
    int y = (x + 1) / 2;
    while (y < x) {
        x = y;
        y = (x + n / x) / 2;
    }
    return x;
}

// Compute the horizontal span of a rounded rect at row py (8.8 fixed point).
// Sets _SPAN_L/_SPAN_R and returns 1 when the row has any coverage.
fn _round_span_fp(int x, int y, int w, int h, int r, int py) -> int {
    _SPAN_L = 0;
    _SPAN_R = 0;
    if (w <= 0 || h <= 0 || py < y || py >= y + h) { return 0; }
    if (r <= 0) {
        _SPAN_L = x * 256;
        _SPAN_R = (x + w) * 256;
        return 1;
    }
    if (r > w / 2) { r = w / 2; }
    if (r > h / 2) { r = h / 2; }
    int top = y + r;
    int bot = y + h - r;
    int cy_fp = 0;
    int dy_fp = 0;
    if (py < top) {
        cy_fp = top * 256;
        dy_fp = cy_fp - (py * 256 + 128);
    } else if (py >= bot) {
        cy_fp = bot * 256;
        dy_fp = (py * 256 + 128) - cy_fp;
    } else {
        _SPAN_L = x * 256;
        _SPAN_R = (x + w) * 256;
        return 1;
    }
    int rfp = r * 256;
    if (dy_fp < 0) { dy_fp = 0 - dy_fp; }
    if (dy_fp >= rfp) { return 0; }
    int inside = rfp * rfp - dy_fp * dy_fp;
    if (inside < 0) { inside = 0; }
    int dxfp = _isqrt(inside);
    _SPAN_L = (x + r) * 256 - dxfp;
    _SPAN_R = (x + w - r) * 256 + dxfp;
    if (_SPAN_R <= _SPAN_L) { return 0; }
    return 1;
}

// Alpha-blend a single pixel (0..255). Works on the 32-bit BGR backbuffer.
fn _gui_blend_px(int x, int y, int color, int alpha) -> void {
    if (alpha <= 0) { return; }
    if (alpha >= 255) { gui_put_pixel(x, y, color); return; }
    if (G_DRAW <= 0) { return; }
    if (x < 0 || y < 0 || x >= G_XRES || y >= G_YRES) { return; }
    if (G_BPP != 32) {
        if (alpha >= 128) { gui_put_pixel(x, y, color); }
        return;
    }
    int idx = y * G_XRES + x;
    char* fb = cast<char*>(G_DRAW) + idx * 4;
    int b = _byte_val(*(fb + 0));
    int g = _byte_val(*(fb + 1));
    int r = _byte_val(*(fb + 2));
    int cr = color / 65536;
    int cg = (color / 256) - (color / 65536) * 256;
    int cb = color - (color / 256) * 256;
    int nb = (b * (255 - alpha) + cb * alpha) / 255;
    int ng = (g * (255 - alpha) + cg * alpha) / 255;
    int nr = (r * (255 - alpha) + cr * alpha) / 255;
    *(fb + 0) = _byte_val(nb);
    *(fb + 1) = _byte_val(ng);
    *(fb + 2) = _byte_val(nr);
    *(fb + 3) = 0;
}

// Blend a horizontal run given in 8.8 fixed-point coordinates.
fn _gui_blend_span_fp(int lfp, int rfp, int y, int color, int alpha) -> void {
    if (y < 0 || y >= G_YRES || alpha <= 0) { return; }
    int maxfp = G_XRES * 256;
    if (lfp < 0) { lfp = 0; }
    if (rfp > maxfp) { rfp = maxfp; }
    if (rfp <= lfp) { return; }
    int px = lfp / 256;
    int end = (rfp + 255) / 256;
    while (px < end) {
        int lo = px * 256;
        int hi = lo + 256;
        int a0 = lfp;
        if (a0 < lo) { a0 = lo; }
        int a1 = rfp;
        if (a1 > hi) { a1 = hi; }
        int cov = a1 - a0;
        if (cov > 0) {
            int al = cov * alpha / 256;
            if (al > 255) { al = 255; }
            _gui_blend_px(px, y, color, al);
        }
        px = px + 1;
    }
}

fn gui_fill_rect_alpha(int x, int y, int w, int h, int color, int alpha) -> void {
    if (alpha <= 0 || w <= 0 || h <= 0) { return; }
    if (alpha >= 255) { gui_fill_rect(x, y, w, h, color); return; }
    int py = y;
    while (py < y + h) {
        _gui_blend_span_fp(x * 256, (x + w) * 256, py, color, alpha);
        py = py + 1;
    }
}

// Smooth Rounded Rectangle Fill (CSS border-radius, arbitrary radius).
fn gui_fill_rounded_rect(int x, int y, int w, int h, int r, int color) -> void {
    gui_fill_rounded_rect_alpha(x, y, w, h, r, color, 255);
}

fn gui_fill_rounded_rect_alpha(int x, int y, int w, int h, int r, int color, int alpha) -> void {
    if (G_DRAW <= 0 || w <= 0 || h <= 0 || alpha <= 0) { return; }
    if (r < 0) { r = 0; }
    if (r > w / 2) { r = w / 2; }
    if (r > h / 2) { r = h / 2; }
    if (r == 0) { gui_fill_rect_alpha(x, y, w, h, color, alpha); return; }
    if (h > 2 * r) {
        gui_fill_rect_alpha(x, y + r, w, h - 2 * r, color, alpha);
    }
    int i = 0;
    while (i < r) {
        if (_round_span_fp(x, y, w, h, r, y + i) == 1) {
            int l = _SPAN_L;
            int rr = _SPAN_R;
            _gui_blend_span_fp(l, rr, y + i, color, alpha);
        }
        if (_round_span_fp(x, y, w, h, r, y + h - 1 - i) == 1) {
            int l = _SPAN_L;
            int rr = _SPAN_R;
            _gui_blend_span_fp(l, rr, y + h - 1 - i, color, alpha);
        }
        i = i + 1;
    }
}

// Smooth Rounded Rectangle Border with configurable thickness + alpha.
fn _gui_rrect_border(int x, int y, int w, int h, int r, int t, int color, int alpha) -> void {
    if (G_DRAW <= 0 || w <= 0 || h <= 0 || t <= 0 || alpha <= 0) { return; }
    if (r < 0) { r = 0; }
    if (r > w / 2) { r = w / 2; }
    if (r > h / 2) { r = h / 2; }
    if (t > w / 2) { t = w / 2; }
    if (t > h / 2) { t = h / 2; }
    int ir = r - t;
    if (ir < 0) { ir = 0; }
    int py = y;
    while (py < y + h) {
        if (_round_span_fp(x, y, w, h, r, py) == 1) {
            int ol = _SPAN_L;
            int orr = _SPAN_R;
            int inner_ok = _round_span_fp(x + t, y + t, w - 2 * t, h - 2 * t, ir, py);
            if (inner_ok == 0) {
                _gui_blend_span_fp(ol, orr, py, color, alpha);
            } else {
                int il = _SPAN_L;
                int irr = _SPAN_R;
                if (il > ol) { _gui_blend_span_fp(ol, il, py, color, alpha); }
                if (orr > irr) { _gui_blend_span_fp(irr, orr, py, color, alpha); }
            }
        }
        py = py + 1;
    }
}

fn gui_draw_rounded_rect(int x, int y, int w, int h, int r, int color) -> void {
    _gui_rrect_border(x, y, w, h, r, 1, color, 255);
}

fn gui_draw_rounded_rect_w(int x, int y, int w, int h, int r, int t, int color) -> void {
    _gui_rrect_border(x, y, w, h, r, t, color, 255);
}

fn gui_draw_rounded_rect_ex(int x, int y, int w, int h, int r, int t, int color, int alpha) -> void {
    _gui_rrect_border(x, y, w, h, r, t, color, alpha);
}

// Vertical gradient clipped to a rounded rectangle.
fn gui_fill_rounded_gradient_v(int x, int y, int w, int h, int r, int col_top, int col_bot) -> void {
    if (G_DRAW <= 0 || w <= 0 || h <= 0) { return; }
    if (r < 0) { r = 0; }
    if (r > w / 2) { r = w / 2; }
    if (r > h / 2) { r = h / 2; }
    int r0 = col_top / 65536;
    int g0 = (col_top / 256) - r0 * 256;
    int b0 = col_top - (col_top / 256) * 256;
    int r1 = col_bot / 65536;
    int g1 = (col_bot / 256) - r1 * 256;
    int b1 = col_bot - (col_bot / 256) * 256;
    int row = 0;
    while (row < h) {
        int cr = r0 + (r1 - r0) * row / h;
        int cg = g0 + (g1 - g0) * row / h;
        int cb = b0 + (b1 - b0) * row / h;
        int col = cr * 65536 + cg * 256 + cb;
        if (_round_span_fp(x, y, w, h, r, y + row) == 1) {
            _gui_blend_span_fp(_SPAN_L, _SPAN_R, y + row, col, 255);
        }
        row = row + 1;
    }
}

// Filled Circle / Status Indicator (4x4 supersampled edges).
fn gui_fill_circle(int cx, int cy, int r, int color) -> void {
    if (r <= 0) { return; }
    int x0 = cx - r - 1;
    int y0 = cy - r - 1;
    int x1 = cx + r + 1;
    int y1 = cy + r + 1;
    int rr8 = r * 8;
    int rr2 = rr8 * rr8;
    int py = y0;
    while (py <= y1) {
        int px = x0;
        while (px <= x1) {
            int hits = 0;
            int sy = 0;
            while (sy < 4) {
                int sx = 0;
                int dy8 = py * 8 + sy * 2 + 1 - cy * 8;
                while (sx < 4) {
                    int dx8 = px * 8 + sx * 2 + 1 - cx * 8;
                    if (dx8 * dx8 + dy8 * dy8 <= rr2) { hits = hits + 1; }
                    sx = sx + 1;
                }
                sy = sy + 1;
            }
            if (hits > 0) {
                int al = hits * 255 / 16;
                _gui_blend_px(px, py, color, al);
            }
            px = px + 1;
        }
        py = py + 1;
    }
}

// ─── Font / Text Rendering ───────────────────────────────
fn gui_draw_char(int x, int y, int ch, int fg, int bg, int scale) -> void {
    if (ch < 32 || ch > 126) { return; }
    int ci = ch - 32;
    int ry = 0;
    while (ry < 16) {
        int bv = _font_byte(ci, ry);
        int bx = 0;
        while (bx < 8) {
            int on = _bit_at(bv, 7 - bx);
            int color = bg;
            if (on == 1) { color = fg; }
            if (scale == 1) {
                gui_put_pixel(x + bx, y + ry, color);
            } else {
                int sy = 0;
                while (sy < scale) {
                    int sx = 0;
                    while (sx < scale) {
                        gui_put_pixel(x + bx * scale + sx, y + ry * scale + sy, color);
                        sx = sx + 1;
                    }
                    sy = sy + 1;
                }
            }
            bx = bx + 1;
        }
        ry = ry + 1;
    }
}

// Foreground-only glyph (keeps the existing gradient/background intact).
fn gui_draw_char_fg(int x, int y, int ch, int fg, int alpha) -> void {
    if (ch < 32 || ch > 126) { return; }
    int ci = ch - 32;
    int ry = 0;
    while (ry < 16) {
        int bv = _font_byte(ci, ry);
        int bx = 0;
        while (bx < 8) {
            if (_bit_at(bv, 7 - bx) == 1) {
                int py = 0;
                while (py < G_GUI_SCALE) {
                    int px = 0;
                    while (px < G_GUI_SCALE) {
                        _gui_blend_px(x + bx * G_GUI_SCALE + px, y + ry * G_GUI_SCALE + py, fg, alpha);
                        px = px + 1;
                    }
                    py = py + 1;
                }
            }
            bx = bx + 1;
        }
        ry = ry + 1;
    }
}

fn gui_draw_text_fg(int x, int y, string text, int fg, int alpha) -> void {
    char* t = cast<char*>(text);
    int i = 0;
    int cx = x;
    while (_byte_val(*(t + i)) != 0) {
        int ch = _byte_val(*(t + i));
        if (ch < 32 || ch > 126) { ch = 32; }
        gui_draw_char_fg(cx, y, ch, fg, alpha);
        cx = cx + 8 * G_GUI_SCALE;
        i = i + 1;
    }
}

fn gui_draw_text(int x, int y, string text, int fg, int bg, int scale) -> void {
    char* t = cast<char*>(text);
    int i = 0;
    int cx = x;
    while (_byte_val(*(t + i)) != 0) {
        int ch = _byte_val(*(t + i));
        gui_draw_char(cx, y, ch, fg, bg, scale);
        cx = cx + 8 * scale;
        i = i + 1;
    }
}

fn gui_text_width(string text, int scale) -> int {
    return _str_len(text) * 8 * scale;
}

fn gui_set_scale(int s) -> void {
    if (s >= 1 && s <= 4) { G_GUI_SCALE = s; }
}

fn gui_get_scale() -> int {
    return G_GUI_SCALE;
}

fn _str_at(string s, int i) -> int {
    char* p = cast<char*>(s);
    return _byte_val(*(p + i));
}

// Translate an X11 keycode into ASCII / special key codes.
// Special codes: 8 BackSpace, 9 Tab, 10 Enter, 27 Esc, 127 Delete,
// 128 Up, 129 Down, 130 Left, 131 Right, 132 Home, 133 End,
// 134 PageUp, 135 PageDown, 136 Insert.
fn _x11_key_ascii(int kc) -> int {
    if (kc == 22) { return 8; }
    if (kc == 23) { return 9; }
    if (kc == 36 || kc == 104) { return 10; }
    if (kc == 9) { return 27; }
    if (kc == 65) { return 32; }
    if (kc == 119) { return 127; }
    if (kc == 111) { return 128; }
    if (kc == 116) { return 129; }
    if (kc == 113) { return 130; }
    if (kc == 114) { return 131; }
    if (kc == 110) { return 132; }
    if (kc == 115) { return 133; }
    if (kc == 112) { return 134; }
    if (kc == 117) { return 135; }
    if (kc == 118) { return 136; }
    if (kc >= 10 && kc <= 19) {
        int d = kc - 9;
        if (d == 10) { d = 0; }
        if (G_KB_SHIFT == 0) { return 48 + d; }
        if (d == 1) { return 33; }
        if (d == 2) { return 64; }
        if (d == 3) { return 35; }
        if (d == 4) { return 36; }
        if (d == 5) { return 37; }
        if (d == 6) { return 94; }
        if (d == 7) { return 38; }
        if (d == 8) { return 42; }
        if (d == 9) { return 40; }
        return 41;
    }
    if (kc == 20) { if (G_KB_SHIFT == 1) { return 95; } return 45; }
    if (kc == 21) { if (G_KB_SHIFT == 1) { return 43; } return 61; }
    if (kc == 49) { if (G_KB_SHIFT == 1) { return 126; } return 96; }
    if (kc == 51) { if (G_KB_SHIFT == 1) { return 124; } return 92; }

    int shifted = G_KB_SHIFT;
    if (kc >= 24 && kc <= 35) {
        if (G_KB_CAPS == 1) { shifted = 1 - shifted; }
        if (shifted == 1) {
            int x = _str_at("QWERTYUIOP{}", kc - 24);
            return x;
        }
        return _str_at("qwertyuiop[]", kc - 24);
    }
    if (kc >= 38 && kc <= 48) {
        if (G_KB_CAPS == 1) { shifted = 1 - shifted; }
        if (kc == 47) { if (shifted == 1) { return 58; } return 59; }
        if (kc == 48) { if (shifted == 1) { return 34; } return 39; }
        if (shifted == 1) {
            return _str_at("ASDFGHJKL", kc - 38);
        }
        return _str_at("asdfghjkl", kc - 38);
    }
    if (kc >= 52 && kc <= 61) {
        if (G_KB_CAPS == 1) { shifted = 1 - shifted; }
        if (kc == 59) { if (shifted == 1) { return 60; } return 44; }
        if (kc == 60) { if (shifted == 1) { return 62; } return 46; }
        if (kc == 61) { if (shifted == 1) { return 63; } return 47; }
        if (shifted == 1) {
            return _str_at("ZXCVBNM", kc - 52);
        }
        return _str_at("zxcvbnm", kc - 52);
    }
    return 0 - 1;
}

fn gui_key_available() -> int {
    return G_KB_COUNT;
}

fn gui_shift_down() -> int { return G_KB_SHIFT; }
fn gui_ctrl_down() -> int { return G_KB_CTRL; }
fn gui_key_ctrl() -> int { return G_KB_LAST_MOD - (G_KB_LAST_MOD / 2) * 2; }
fn gui_key_shift() -> int { int v = G_KB_LAST_MOD / 2; return v - (v / 2) * 2; }

// Pop the next keyboard character (ASCII / special code), or -1 if empty.
fn gui_key_poll() -> int {
    if (G_KB_COUNT <= 0 || G_KB_QUEUE <= 0) { return 0 - 1; }
    char* q = cast<char*>(G_KB_QUEUE);
    int r = G_KB_HEAD - G_KB_COUNT;
    if (r < 0) { r = r + 64; }
    int k = _byte_val(*(q + r));
    G_KB_LAST_MOD = 0;
    if (G_KB_MODQ > 0) {
        char* mq = cast<char*>(G_KB_MODQ);
        G_KB_LAST_MOD = _byte_val(*(mq + r));
    }
    G_KB_COUNT = G_KB_COUNT - 1;
    return k;
}

// ─── Mouse Input ─────────────────────────────────────────
fn _mouse_packet(char* mb) -> void {
    int flags = _byte_val(*(mb + 0));
    int dx = _byte_val(*(mb + 1));
    int dy = _byte_val(*(mb + 2));
    if (_bit_at(flags, 4) == 1) { dx = dx - 256; }
    if (_bit_at(flags, 5) == 1) { dy = dy - 256; }
    if (_bit_at(flags, 6) == 0) { G_MOUSE_X = G_MOUSE_X + dx; }
    if (_bit_at(flags, 7) == 0) { G_MOUSE_Y = G_MOUSE_Y - dy; }
    if (G_MOUSE_X < 0) { G_MOUSE_X = 0; }
    if (G_MOUSE_Y < 0) { G_MOUSE_Y = 0; }
    if (G_MOUSE_X >= G_XRES) { G_MOUSE_X = G_XRES - 1; }
    if (G_MOUSE_Y >= G_YRES) { G_MOUSE_Y = G_YRES - 1; }
    G_MOUSE_BTN = _bit_at(flags, 0);
    if (G_MOUSE_BTN == 1 && G_MOUSE_PREV_BTN == 0) {
        G_MOUSE_CLICK = 1;
    }
    G_MOUSE_PREV_BTN = G_MOUSE_BTN;
}

fn gui_read_mouse() -> void {
    G_MOUSE_CLICK = 0;
    G_MOUSE_WHEEL = 0;
    G_MOUSE_RIGHT_CLICK = 0;

    if (G_X11_ACTIVE == 1) {
        _x11_process_events();
        return;
    }

    if (G_MOUSE_FD < 0 || G_MBUF <= 0) { return; }
    char* mb = cast<char*>(G_MBUF);
    int reads = 0;
    while (reads < 256) {
        int wanted = 3 - G_MOUSE_PENDING;
        if (G_MOUSE_PENDING == 0) { wanted = 1; }
        int n = sys_read(G_MOUSE_FD, mb + G_MOUSE_PENDING, wanted);
        if (n <= 0) { return; }
        G_MOUSE_PENDING = G_MOUSE_PENDING + n;
        if (G_MOUSE_PENDING == 1 && _bit_at(_byte_val(*mb), 3) == 0) {
            G_MOUSE_PENDING = 0;
        }
        if (G_MOUSE_PENDING == 3) {
            _mouse_packet(mb);
            G_MOUSE_PENDING = 0;
        }
        reads = reads + 1;
    }
}

fn gui_mouse_x() -> int { return G_MOUSE_X; }
fn gui_mouse_y() -> int { return G_MOUSE_Y; }
fn gui_mouse_left() -> int { return G_MOUSE_BTN - (G_MOUSE_BTN / 2) * 2; }
fn gui_mouse_clicked() -> int { return G_MOUSE_CLICK; }
fn gui_mouse_right() -> int { return G_MOUSE_RIGHT; }
fn gui_mouse_right_clicked() -> int { return G_MOUSE_RIGHT_CLICK; }
fn gui_mouse_wheel() -> int { return G_MOUSE_WHEEL; }

// ─── UI Classes ──────────────────────────────────────────
class Button {
    int bx; int by; int bw; int bh;
    string label;
    int fg; int bg; int border_color;

    fn init(string l, int px, int py, int pw, int ph, int ifg, int ibg, int ibc) -> void {
        this.label = l; this.bx = px; this.by = py; this.bw = pw; this.bh = ph;
        this.fg = ifg; this.bg = ibg; this.border_color = ibc;
    }

    fn draw() -> void {
        gui_fill_rounded_rect(this.bx, this.by, this.bw, this.bh, 4, this.bg);
        gui_draw_rounded_rect(this.bx, this.by, this.bw, this.bh, 4, this.border_color);
        int tw = gui_text_width(this.label, G_GUI_SCALE);
        int tx = this.bx + (this.bw - tw) / 2;
        int ty = this.by + (this.bh - 16 * G_GUI_SCALE) / 2;
        gui_draw_text(tx, ty, this.label, this.fg, this.bg, G_GUI_SCALE);
    }

    fn is_hovered() -> int {
        if (G_MOUSE_X < this.bx) { return 0; }
        if (G_MOUSE_X >= this.bx + this.bw) { return 0; }
        if (G_MOUSE_Y < this.by) { return 0; }
        if (G_MOUSE_Y >= this.by + this.bh) { return 0; }
        return 1;
    }

    fn clicked() -> int {
        if (this.is_hovered() == 1) {
            if (gui_mouse_clicked() == 1) { return 1; }
        }
        return 0;
    }
};

class Window {
    int wx; int wy; int ww; int wh;
    string title;
    int fg; int bg; int border_color; int title_bg;

    fn init(string t, int px, int py, int pw, int ph, int ifg, int ibg, int ibc, int itbg) -> void {
        this.title = t; this.wx = px; this.wy = py; this.ww = pw; this.wh = ph;
        this.fg = ifg; this.bg = ibg; this.border_color = ibc; this.title_bg = itbg;
    }

    fn draw() -> void {
        gui_fill_rounded_rect(this.wx, this.wy, this.ww, this.wh, 4, this.bg);
        gui_draw_rounded_rect(this.wx, this.wy, this.ww, this.wh, 4, this.border_color);
        gui_fill_gradient_v(this.wx + 1, this.wy + 1, this.ww - 2, 24, this.title_bg, this.title_bg - 0x101010);
        gui_draw_text(this.wx + 8, this.wy + 4, this.title, this.fg, this.title_bg, G_GUI_SCALE);
    }

    fn contains(int px, int py) -> int {
        if (px < this.wx) { return 0; }
        if (px >= this.wx + this.ww) { return 0; }
        if (py < this.wy) { return 0; }
        if (py >= this.wy + this.wh) { return 0; }
        return 1;
    }
};

// ─── High-Level Desktop Application Framework ─────────────
static const int WT_NONE      = 0;
static const int WT_LABEL     = 1;
static const int WT_BUTTON    = 2;
static const int WT_CHECKBOX  = 3;
static const int WT_SLIDER    = 4;
static const int WT_PROGRESS  = 5;
static const int WT_TEXTBOX   = 6;
static const int WT_LISTBOX   = 7;
static const int WT_SWITCH    = 8;  // Modern iOS/Android style toggle switch
static const int WT_BADGE     = 9;  // Status badge/pill ("ACTIVE", "PRO", etc.)
static const int WT_SEPARATOR = 10; // Decorative horizontal divider
static const int WT_TABS      = 11; // Tab navigation bar
static const int WT_INPUT     = 12; // Editable single-line text field (keyboard)
static const int WT_CARD      = 13; // Rounded decorative card / panel
static const int WT_SPINNER   = 14; // Animated activity indicator

static const int WF_ENABLED = 1;
static const int WF_HOVER   = 2;
static const int WF_PRESSED = 4;
static const int WF_CHANGED = 8;
static const int WF_FOCUS   = 16;
static const int WF_HIDDEN  = 32;

static const int WINF_VISIBLE = 1;
static const int WINF_FOCUS   = 2;

static const int DSK_MAX_WIDGETS = 256;
static const int DSK_MAX_WINDOWS = 16;
static const int DSK_MAX_ITEMS   = 128;
static const int DSK_INPUT_CAP   = 128;

// Unified visual metrics (everything uses the same rhythm)
static const int DSK_TITLE_H = 30;
static const int DSK_RADIUS  = 6;
static const int DSK_PAD     = 12;
static const int DSK_TASKBAR_H = 44;

static int* W_TYPE;
static int* W_X;
static int* W_Y;
static int* W_W;
static int* W_H;
static int* W_VAL;
static int* W_MIN;
static int* W_MAX;
static int* W_FLAGS;
static int* W_WIN;
static int* W_TXTP;
static int* W_CARET;
static string* W_LBL;
static int w_count;

static int* WIN_X;
static int* WIN_Y;
static int* WIN_W;
static int* WIN_H;
static int* WIN_FLAGS;
static int* WIN_WSTART;
static int* WIN_WCOUNT;
static string* WIN_TITLE;
static int win_count;

static string* LB_TEXT;
static int* LB_OWNER;
static int lb_count;

static int DSK_READY;
static int DSK_RUNNING;
static int DSK_ACTIVE;
static int DSK_DRAG_WIN;
static int DSK_DRAG_OX;
static int DSK_DRAG_OY;
static int DSK_SLIDER;
static int DSK_HOVER;
static int DSK_CLICKED;
static int DSK_FOCUS_WID;
static int DSK_APP_MODE;
static int DSK_ROOT;
static int DSK_ROOT_CHROME;
static int DSK_TASKBAR_ON;
static int DSK_HOVER_WIN;
static int DSK_FRAME;
static int DSK_WHEEL;
static int DSK_TOAST_TTL;
static int DSK_SHOW_FPS;
static char* DSK_SCRATCH;
static int DSK_SCRATCH_IDX;
static char* DSK_TOAST;

// Themes
static int TH_DESKTOP;
static int TH_PANEL;
static int TH_BORDER;
static int TH_TITLE;
static int TH_TITLE_GRAD;
static int TH_TITLE_FG;
static int TH_TEXT;
static int TH_SUBTEXT;
static int TH_BTN;
static int TH_BTN_HOVER;
static int TH_BTN_FG;
static int TH_ACCENT;
static int TH_ACCENT_FG;
static int TH_TASKBAR;
static int TH_SHADOW;
static int TH_SUCCESS;
static int TH_INPUT_BG;
static int TH_CARD;
static int TH_DIVIDER;
static int TH_WARNING;
static int TH_DANGER;
static int TH_INFO;
static int TH_DISABLED;
static int TH_FOCUS;
static int TH_CARET;

// Theme 0: Modern Deep Blue (Classic Falcon)
fn dsk_theme_default() -> void {
    TH_DESKTOP    = gui_rgb(18, 24, 38);
    TH_PANEL      = gui_rgb(238, 242, 248);
    TH_BORDER     = gui_rgb(60, 78, 115);
    TH_TITLE      = gui_rgb(46, 82, 148);
    TH_TITLE_GRAD = gui_rgb(32, 58, 108);
    TH_TITLE_FG   = gui_rgb(255, 255, 255);
    TH_TEXT       = gui_rgb(24, 30, 44);
    TH_SUBTEXT    = gui_rgb(90, 100, 124);
    TH_BTN        = gui_rgb(202, 214, 234);
    TH_BTN_HOVER  = gui_rgb(226, 236, 250);
    TH_BTN_FG     = gui_rgb(20, 34, 65);
    TH_ACCENT     = gui_rgb(48, 138, 224);
    TH_ACCENT_FG  = gui_rgb(255, 255, 255);
    TH_TASKBAR    = gui_rgb(12, 16, 26);
    TH_SHADOW     = gui_rgb(8, 12, 20);
    TH_SUCCESS    = gui_rgb(39, 174, 96);
    TH_INPUT_BG   = gui_rgb(252, 254, 255);
    TH_CARD       = gui_rgb(248, 250, 254);
    TH_DIVIDER    = gui_rgb(202, 210, 226);
    TH_WARNING    = gui_rgb(242, 201, 76);
    TH_DANGER     = gui_rgb(235, 87, 87);
    TH_INFO       = gui_rgb(48, 138, 224);
    TH_DISABLED   = gui_rgb(168, 176, 192);
    TH_FOCUS      = gui_rgb(48, 138, 224);
    TH_CARET      = gui_rgb(24, 30, 44);
}

// Theme 1: Sleek Dark / Midnight
fn dsk_theme_dark() -> void {
    TH_DESKTOP    = gui_rgb(12, 14, 18);
    TH_PANEL      = gui_rgb(28, 32, 42);
    TH_BORDER     = gui_rgb(52, 62, 82);
    TH_TITLE      = gui_rgb(38, 44, 58);
    TH_TITLE_GRAD = gui_rgb(24, 28, 38);
    TH_TITLE_FG   = gui_rgb(230, 236, 248);
    TH_TEXT       = gui_rgb(220, 226, 240);
    TH_SUBTEXT    = gui_rgb(130, 140, 160);
    TH_BTN        = gui_rgb(44, 50, 66);
    TH_BTN_HOVER  = gui_rgb(62, 70, 92);
    TH_BTN_FG     = gui_rgb(235, 240, 252);
    TH_ACCENT     = gui_rgb(70, 155, 245);
    TH_ACCENT_FG  = gui_rgb(12, 16, 24);
    TH_TASKBAR    = gui_rgb(8, 9, 14);
    TH_SHADOW     = gui_rgb(4, 5, 8);
    TH_SUCCESS    = gui_rgb(46, 204, 113);
    TH_INPUT_BG   = gui_rgb(18, 22, 30);
    TH_CARD       = gui_rgb(34, 39, 50);
    TH_DIVIDER    = gui_rgb(52, 62, 82);
    TH_WARNING    = gui_rgb(245, 196, 78);
    TH_DANGER     = gui_rgb(235, 92, 96);
    TH_INFO       = gui_rgb(70, 155, 245);
    TH_DISABLED   = gui_rgb(92, 100, 116);
    TH_FOCUS      = gui_rgb(70, 155, 245);
    TH_CARET      = gui_rgb(235, 240, 252);
}

// Theme 2: Cyberpunk / Neon Violet
fn dsk_theme_cyberpunk() -> void {
    TH_DESKTOP    = gui_rgb(15, 10, 25);
    TH_PANEL      = gui_rgb(32, 22, 52);
    TH_BORDER     = gui_rgb(140, 40, 190);
    TH_TITLE      = gui_rgb(110, 20, 160);
    TH_TITLE_GRAD = gui_rgb(70, 10, 105);
    TH_TITLE_FG   = gui_rgb(255, 240, 255);
    TH_TEXT       = gui_rgb(240, 230, 255);
    TH_SUBTEXT    = gui_rgb(170, 140, 200);
    TH_BTN        = gui_rgb(58, 35, 90);
    TH_BTN_HOVER  = gui_rgb(85, 52, 130);
    TH_BTN_FG     = gui_rgb(0, 240, 255);
    TH_ACCENT     = gui_rgb(0, 220, 240);
    TH_ACCENT_FG  = gui_rgb(10, 10, 20);
    TH_TASKBAR    = gui_rgb(10, 6, 18);
    TH_SHADOW     = gui_rgb(5, 2, 10);
    TH_SUCCESS    = gui_rgb(0, 255, 180);
    TH_INPUT_BG   = gui_rgb(22, 15, 36);
    TH_CARD       = gui_rgb(40, 28, 64);
    TH_DIVIDER    = gui_rgb(110, 40, 150);
    TH_WARNING    = gui_rgb(255, 210, 74);
    TH_DANGER     = gui_rgb(255, 70, 120);
    TH_INFO       = gui_rgb(0, 220, 240);
    TH_DISABLED   = gui_rgb(110, 90, 140);
    TH_FOCUS      = gui_rgb(0, 220, 240);
    TH_CARET      = gui_rgb(255, 240, 255);
}

// Theme 3: Emerald / Modern Forest
fn dsk_theme_emerald() -> void {
    TH_DESKTOP    = gui_rgb(14, 24, 20);
    TH_PANEL      = gui_rgb(24, 38, 32);
    TH_BORDER     = gui_rgb(42, 85, 65);
    TH_TITLE      = gui_rgb(28, 70, 52);
    TH_TITLE_GRAD = gui_rgb(18, 48, 36);
    TH_TITLE_FG   = gui_rgb(240, 255, 245);
    TH_TEXT       = gui_rgb(230, 245, 235);
    TH_SUBTEXT    = gui_rgb(130, 170, 150);
    TH_BTN        = gui_rgb(36, 58, 48);
    TH_BTN_HOVER  = gui_rgb(50, 82, 68);
    TH_BTN_FG     = gui_rgb(235, 255, 240);
    TH_ACCENT     = gui_rgb(46, 185, 120);
    TH_ACCENT_FG  = gui_rgb(10, 25, 18);
    TH_TASKBAR    = gui_rgb(8, 16, 12);
    TH_SHADOW     = gui_rgb(4, 10, 8);
    TH_SUCCESS    = gui_rgb(46, 204, 113);
    TH_INPUT_BG   = gui_rgb(16, 28, 23);
    TH_CARD       = gui_rgb(32, 50, 42);
    TH_DIVIDER    = gui_rgb(42, 85, 65);
    TH_WARNING    = gui_rgb(240, 200, 80);
    TH_DANGER     = gui_rgb(235, 100, 100);
    TH_INFO       = gui_rgb(46, 185, 120);
    TH_DISABLED   = gui_rgb(96, 130, 112);
    TH_FOCUS      = gui_rgb(46, 185, 120);
    TH_CARET      = gui_rgb(240, 255, 245);
}

// Theme 4: Light / Paper
fn dsk_theme_light() -> void {
    TH_DESKTOP    = gui_rgb(232, 236, 244);
    TH_PANEL      = gui_rgb(255, 255, 255);
    TH_BORDER     = gui_rgb(198, 206, 220);
    TH_TITLE      = gui_rgb(245, 247, 252);
    TH_TITLE_GRAD = gui_rgb(228, 233, 242);
    TH_TITLE_FG   = gui_rgb(30, 38, 54);
    TH_TEXT       = gui_rgb(28, 34, 46);
    TH_SUBTEXT    = gui_rgb(110, 120, 138);
    TH_BTN        = gui_rgb(236, 240, 248);
    TH_BTN_HOVER  = gui_rgb(222, 230, 244);
    TH_BTN_FG     = gui_rgb(30, 40, 60);
    TH_ACCENT     = gui_rgb(52, 120, 220);
    TH_ACCENT_FG  = gui_rgb(255, 255, 255);
    TH_TASKBAR    = gui_rgb(246, 248, 252);
    TH_SHADOW     = gui_rgb(196, 202, 216);
    TH_SUCCESS    = gui_rgb(39, 174, 96);
    TH_INPUT_BG   = gui_rgb(255, 255, 255);
    TH_CARD       = gui_rgb(246, 248, 252);
    TH_DIVIDER    = gui_rgb(214, 220, 232);
    TH_WARNING    = gui_rgb(240, 180, 40);
    TH_DANGER     = gui_rgb(224, 72, 80);
    TH_INFO       = gui_rgb(52, 120, 220);
    TH_DISABLED   = gui_rgb(176, 182, 194);
    TH_FOCUS      = gui_rgb(52, 120, 220);
    TH_CARET      = gui_rgb(28, 34, 46);
}

fn dsk_set_theme(int theme_id) -> void {
    if (theme_id == 1) { dsk_theme_dark(); }
    else if (theme_id == 2) { dsk_theme_cyberpunk(); }
    else if (theme_id == 3) { dsk_theme_emerald(); }
    else if (theme_id == 4) { dsk_theme_light(); }
    else { dsk_theme_default(); }
}

// Override the accent color at runtime (buttons, sliders, focus ring...)
fn dsk_set_accent(int color) -> void {
    TH_ACCENT = color;
    TH_FOCUS = color;
    TH_INFO = color;
}

fn dsk_str_eq(string a, string b) -> int {
    char* pa = cast<char*>(a);
    char* pb = cast<char*>(b);
    int i = 0;
    int done = 0;
    while (done == 0) {
        int ca = _byte_val(*(pa + i));
        int cb = _byte_val(*(pb + i));
        if (ca == 0 && cb == 0) { return 1; }
        if (ca != cb) { return 0; }
        i = i + 1;
    }
    return 1;
}

// Copy a string into a fixed-size buffer (always NUL terminated).
fn _str_copy(char* dst, string src, int cap) -> int {
    if (cap <= 0) { return 0; }
    char* s = cast<char*>(src);
    int i = 0;
    while (i < cap - 1 && _byte_val(*(s + i)) != 0) {
        *(dst + i) = *(s + i);
        i = i + 1;
    }
    *(dst + i) = 0;
    return i;
}

// Append one character to a fixed buffer.
fn _str_push(char* dst, int cap, int ch) -> void {
    int n = 0;
    while (n < cap - 1 && _byte_val(*(dst + n)) != 0) { n = n + 1; }
    if (n >= cap - 1) { return; }
    *(dst + n) = ch;
    *(dst + n + 1) = 0;
}

// Draw text clipped to a maximum pixel width (no overflow).
fn dsk_text_clip(int x, int y, string text, int fg, int bg, int maxw) -> void {
    if (maxw <= 0) { return; }
    char* t = cast<char*>(text);
    int i = 0;
    int cx = x;
    while (_byte_val(*(t + i)) != 0) {
        int ch = _byte_val(*(t + i));
        if (ch < 32 || ch > 126) { ch = 32; }
        if (cx + 8 * G_GUI_SCALE > x + maxw) { return; }
        gui_draw_char(cx, y, ch, fg, bg, G_GUI_SCALE);
        cx = cx + 8 * G_GUI_SCALE;
        i = i + 1;
    }
}

// Right-aligned / centered text helpers.
fn dsk_text_center(int x, int y, int w, string text, int fg, int bg) -> void {
    int tw = gui_text_width(text, G_GUI_SCALE);
    int tx = x + (w - tw) / 2;
    if (tw > w) { tx = x; }
    dsk_text_clip(tx, y, text, fg, bg, w);
}

// Foreground-only variants (text over gradients / rounded backgrounds).
fn dsk_text_clip_fg(int x, int y, string text, int fg, int maxw) -> void {
    if (maxw <= 0) { return; }
    char* t = cast<char*>(text);
    int i = 0;
    int cx = x;
    while (_byte_val(*(t + i)) != 0) {
        int ch = _byte_val(*(t + i));
        if (ch < 32 || ch > 126) { ch = 32; }
        if (cx + 8 * G_GUI_SCALE > x + maxw) { return; }
        gui_draw_char_fg(cx, y, ch, fg, 255);
        cx = cx + 8 * G_GUI_SCALE;
        i = i + 1;
    }
}

fn dsk_text_center_fg(int x, int y, int w, string text, int fg) -> void {
    int tw = gui_text_width(text, G_GUI_SCALE);
    int tx = x + (w - tw) / 2;
    if (tw > w) { tx = x; }
    dsk_text_clip_fg(tx, y, text, fg, w);
}

// Small toast notification (drawn above everything for ~2 seconds).
fn dsk_toast(string text) -> void {
    if (DSK_TOAST == 0) { return; }
    _str_copy(DSK_TOAST, text, 120);
    DSK_TOAST_TTL = 120;
}

fn dsk_toast_active() -> int { return DSK_TOAST_TTL; }

fn dsk_itoa(int v) -> string {
    char* buf = DSK_SCRATCH + DSK_SCRATCH_IDX * 24;
    DSK_SCRATCH_IDX = (DSK_SCRATCH_IDX + 1) - (DSK_SCRATCH_IDX / 32) * 32;
    int i = 0;
    int neg = 0;
    if (v < 0) { neg = 1; v = 0 - v; }
    if (v == 0) {
        *(buf + 0) = 48;
        *(buf + 1) = 0;
        return cast<string>(buf);
    }
    while (v > 0) {
        *(buf + i) = 48 + (v - (v / 10) * 10);
        v = v / 10;
        i = i + 1;
    }
    if (neg == 1) { *(buf + i) = 45; i = i + 1; }
    *(buf + i) = 0;
    int s = 0;
    int e = i - 1;
    while (s < e) {
        int tmp = _byte_val(*(buf + s));
        *(buf + s) = *(buf + e);
        *(buf + e) = tmp;
        s = s + 1;
        e = e - 1;
    }
    return cast<string>(buf);
}

fn dsk_itoa_pad(int v, int pad) -> string {
    char* buf = DSK_SCRATCH + DSK_SCRATCH_IDX * 24;
    DSK_SCRATCH_IDX = (DSK_SCRATCH_IDX + 1) - (DSK_SCRATCH_IDX / 32) * 32;
    int i = 0;
    int val = v;
    if (val < 0) { val = 0 - val; }
    if (val == 0) {
        *(buf + 0) = 48;
        i = 1;
    } else {
        while (val > 0) {
            *(buf + i) = 48 + (val - (val / 10) * 10);
            val = val / 10;
            i = i + 1;
        }
    }
    while (i < pad) {
        *(buf + i) = 48;
        i = i + 1;
    }
    *(buf + i) = 0;
    int s = 0;
    int e = i - 1;
    while (s < e) {
        int tmp = _byte_val(*(buf + s));
        *(buf + s) = *(buf + e);
        *(buf + e) = tmp;
        s = s + 1;
        e = e - 1;
    }
    return cast<string>(buf);
}

fn dsk_shadow(int x, int y, int w, int h) -> void {
    // Layered soft shadow (CSS-like box-shadow).
    gui_fill_rounded_rect_alpha(x + 2, y + 4, w, h, DSK_RADIUS + 3, TH_SHADOW, 55);
    gui_fill_rounded_rect_alpha(x + 5, y + 8, w, h, DSK_RADIUS + 6, TH_SHADOW, 35);
    gui_fill_rounded_rect_alpha(x + 9, y + 13, w, h, DSK_RADIUS + 9, TH_SHADOW, 20);
}

fn dsk_hline(int x, int y, int w, int color) -> void {
    gui_fill_rect(x, y, w, 1, color);
}

fn dsk_vline(int x, int y, int h, int color) -> void {
    gui_fill_rect(x, y, 1, h, color);
}

fn dsk_line(int x0, int y0, int x1, int y1, int color) -> void {
    int dx = x1 - x0;
    if (dx < 0) { dx = 0 - dx; }
    int dy = y1 - y0;
    if (dy < 0) { dy = 0 - dy; }
    int sx = 1;
    if (x0 > x1) { sx = 0 - 1; }
    int sy = 1;
    if (y0 > y1) { sy = 0 - 1; }
    int err = dx - dy;
    int cx = x0;
    int cy = y0;
    int guard = 0;
    while (guard < 4096) {
        gui_put_pixel(cx, cy, color);
        if (cx == x1 && cy == y1) { return; }
        int e2 = err * 2;
        if (e2 > (0 - dy)) { err = err - dy; cx = cx + sx; }
        if (e2 < dx) { err = err + dx; cy = cy + sy; }
        guard = guard + 1;
    }
}

fn dsk_text_in(int x, int y, int w, int h, string s, int fg, int bg) -> void {
    int tw = gui_text_width(s, G_GUI_SCALE);
    int tx = x + (w - tw) / 2;
    int ty = y + (h - 16 * G_GUI_SCALE) / 2;
    gui_draw_text(tx, ty, s, fg, bg, G_GUI_SCALE);
}

fn dsk_alloc_pool() -> int {
    W_TYPE = alloc<int>(DSK_MAX_WIDGETS);
    W_X = alloc<int>(DSK_MAX_WIDGETS);
    W_Y = alloc<int>(DSK_MAX_WIDGETS);
    W_W = alloc<int>(DSK_MAX_WIDGETS);
    W_H = alloc<int>(DSK_MAX_WIDGETS);
    W_VAL = alloc<int>(DSK_MAX_WIDGETS);
    W_MIN = alloc<int>(DSK_MAX_WIDGETS);
    W_MAX = alloc<int>(DSK_MAX_WIDGETS);
    W_FLAGS = alloc<int>(DSK_MAX_WIDGETS);
    W_WIN = alloc<int>(DSK_MAX_WIDGETS);
    W_TXTP = alloc<int>(DSK_MAX_WIDGETS);
    W_CARET = alloc<int>(DSK_MAX_WIDGETS);
    W_LBL = alloc<string>(DSK_MAX_WIDGETS);

    WIN_X = alloc<int>(DSK_MAX_WINDOWS);
    WIN_Y = alloc<int>(DSK_MAX_WINDOWS);
    WIN_W = alloc<int>(DSK_MAX_WINDOWS);
    WIN_H = alloc<int>(DSK_MAX_WINDOWS);
    WIN_FLAGS = alloc<int>(DSK_MAX_WINDOWS);
    WIN_WSTART = alloc<int>(DSK_MAX_WINDOWS);
    WIN_WCOUNT = alloc<int>(DSK_MAX_WINDOWS);
    WIN_TITLE = alloc<string>(DSK_MAX_WINDOWS);

    LB_TEXT = alloc<string>(DSK_MAX_ITEMS);
    LB_OWNER = alloc<int>(DSK_MAX_ITEMS);
    DSK_SCRATCH = alloc<char>(768);
    DSK_SCRATCH_IDX = 0;
    DSK_TOAST = alloc<char>(128);
    _zero(DSK_TOAST, 128);
    return 0;
}

fn _dsk_reset(int app_mode) -> void {
    dsk_alloc_pool();
    dsk_theme_default();
    w_count = 0;
    win_count = 0;
    lb_count = 0;
    DSK_READY = 1;
    DSK_RUNNING = 1;
    DSK_ACTIVE = 0 - 1;
    DSK_DRAG_WIN = 0 - 1;
    DSK_SLIDER = 0 - 1;
    DSK_HOVER = 0 - 1;
    DSK_CLICKED = 0 - 1;
    DSK_FOCUS_WID = 0 - 1;
    DSK_APP_MODE = app_mode;
    DSK_ROOT = 0 - 1;
    DSK_ROOT_CHROME = 0;
    DSK_TASKBAR_ON = 1;
    DSK_HOVER_WIN = 0 - 1;
    DSK_FRAME = 0;
    DSK_WHEEL = 0;
    DSK_TOAST_TTL = 0;
    DSK_SHOW_FPS = 0;
}

fn dsk_init() -> int {
    int err = gui_init();
    if (err != 0) { return err; }
    _dsk_reset(0);
    return 0;
}

fn dsk_init_window(int w, int h, string title) -> int {
    int err = gui_init_window(w, h, title);
    if (err != 0) { return err; }
    _dsk_reset(1);
    // One OS window, one application root window that fills the client area.
    DSK_ROOT = dsk_add_window(title, 0, 0, G_XRES, G_YRES);
    DSK_TASKBAR_ON = 0;
    // On X11 the OS already draws a title bar, so the root content must not
    // draw a second one. On framebuffer we draw our own title bar.
    if (gui_is_x11() == 1) { DSK_ROOT_CHROME = 0; gui_set_decorated(1); }
    else { DSK_ROOT_CHROME = 1; }
    return 0;
}

// Single-call application entry: returns the root window handle (or -1).
// Use this instead of calling dsk_init_window() + dsk_add_window().
fn dsk_open(int w, int h, string title) -> int {
    int err = dsk_init_window(w, h, title);
    if (err != 0) { return 0 - 1; }
    return dsk_root();
}

// Explicit, readable alias for single-window applications.
fn dsk_init_app(int w, int h, string title) -> int {
    return dsk_init_window(w, h, title);
}

fn dsk_root_chrome() -> int { return DSK_ROOT_CHROME; }

// on=0: rely on the OS title bar (no internal bar). on=1: hide OS decorations
// and draw the professional internal title bar instead.
fn dsk_set_root_chrome(int on) -> void {
    if (DSK_APP_MODE != 1) { return; }
    DSK_ROOT_CHROME = on;
    if (gui_is_x11() == 1) {
        if (on == 1) { gui_set_decorated(0); }
        else { gui_set_decorated(1); }
    }
    dsk_on_resize();
}

// Y coordinate where root content begins (0 without internal chrome).
fn dsk_content_top() -> int {
    if (DSK_APP_MODE == 1 && DSK_ROOT >= 0 && DSK_ROOT < win_count && DSK_ROOT_CHROME == 0) { return 0; }
    return DSK_TITLE_H;
}

fn dsk_init_framebuffer() -> int {
    int err = gui_init_framebuffer();
    if (err != 0) { return err; }
    _dsk_reset(0);
    return 0;
}

fn dsk_shutdown() -> void {
    gui_shutdown();
    DSK_READY = 0;
    DSK_RUNNING = 0;
}

fn dsk_stop() -> void { DSK_RUNNING = 0; }
fn dsk_running() -> int { return DSK_RUNNING; }
fn dsk_screen_w() -> int { return G_XRES; }
fn dsk_screen_h() -> int { return G_YRES; }
fn dsk_root() -> int { return DSK_ROOT; }
fn dsk_app_mode() -> int { return DSK_APP_MODE; }

fn dsk_set_app_mode(int on) -> void {
    if (on == 1) { DSK_APP_MODE = 1; DSK_TASKBAR_ON = 0; }
    else { DSK_APP_MODE = 0; }
    dsk_on_resize();
}

fn dsk_set_taskbar(int on) -> void { DSK_TASKBAR_ON = on; }
fn dsk_taskbar_visible() -> int { return DSK_TASKBAR_ON; }

// Reflow windows after the OS window is resized.
fn dsk_on_resize() -> void {
    if (DSK_APP_MODE == 1 && DSK_ROOT >= 0 && DSK_ROOT < win_count) {
        WIN_X[DSK_ROOT] = 0;
        WIN_Y[DSK_ROOT] = 0;
        WIN_W[DSK_ROOT] = G_XRES;
        WIN_H[DSK_ROOT] = G_YRES;
    } else {
        int i = 0;
        while (i < win_count) {
            if (WIN_X[i] + WIN_W[i] > G_XRES) { WIN_X[i] = G_XRES - WIN_W[i]; }
            if (WIN_Y[i] + WIN_H[i] > G_YRES) { WIN_Y[i] = G_YRES - WIN_H[i]; }
            if (WIN_X[i] < 0) { WIN_X[i] = 0; }
            if (WIN_Y[i] < 0) { WIN_Y[i] = 0; }
            i = i + 1;
        }
    }
    dsk_draw_all();
}

fn dsk_add_window(string title, int x, int y, int w, int h) -> int {
    if (win_count >= DSK_MAX_WINDOWS) { return 0 - 1; }
    // In app mode the first added window reuses the full-screen root window.
    if (DSK_APP_MODE == 1 && DSK_ROOT >= 0 && win_count == 1 && WIN_WCOUNT[DSK_ROOT] == 0) {
        WIN_TITLE[DSK_ROOT] = title;
        WIN_X[DSK_ROOT] = 0;
        WIN_Y[DSK_ROOT] = 0;
        WIN_W[DSK_ROOT] = G_XRES;
        WIN_H[DSK_ROOT] = G_YRES;
        dsk_focus_window(DSK_ROOT);
        return DSK_ROOT;
    }
    int id = win_count;
    WIN_X[id] = x;
    WIN_Y[id] = y;
    WIN_W[id] = w;
    WIN_H[id] = h;
    WIN_FLAGS[id] = WINF_VISIBLE;
    WIN_WSTART[id] = w_count;
    WIN_WCOUNT[id] = 0;
    WIN_TITLE[id] = title;
    win_count = win_count + 1;
    DSK_ACTIVE = id;
    if (DSK_APP_MODE == 1 && DSK_ROOT < 0) {
        DSK_ROOT = id;
        WIN_X[id] = 0;
        WIN_Y[id] = 0;
        WIN_W[id] = G_XRES;
        WIN_H[id] = G_YRES;
    }
    return id;
}

fn dsk_focus_window(int id) -> void {
    if (id < 0 || id >= win_count) { return; }
    int i = 0;
    while (i < win_count) {
        WIN_FLAGS[i] = WIN_FLAGS[i] - (WIN_FLAGS[i] / 2) * 2 + (WIN_FLAGS[i] / 4) * 4;
        i = i + 1;
    }
    WIN_FLAGS[id] = WIN_FLAGS[id] + WINF_FOCUS;
    DSK_ACTIVE = id;
}

fn dsk_window_visible(int id) -> int {
    return WIN_FLAGS[id] - (WIN_FLAGS[id] / 2) * 2;
}

fn dsk_toggle_window(int id) -> void {
    if (dsk_window_visible(id) == 1) {
        WIN_FLAGS[id] = WIN_FLAGS[id] - 1;
    } else {
        WIN_FLAGS[id] = WIN_FLAGS[id] + 1;
        dsk_focus_window(id);
    }
}

fn dsk_maximize_window(int id) -> void {
    if (id < 0 || id >= win_count) { return; }
    if (DSK_APP_MODE == 1 && id == DSK_ROOT) { return; }
    int tbh = 0;
    if (DSK_TASKBAR_ON == 1 && G_YRES >= 360) { tbh = dsk_taskbar_h(); }
    if (WIN_X[id] == 8 && WIN_Y[id] == 8 && WIN_W[id] == G_XRES - 16) {
        WIN_X[id] = 30;
        WIN_Y[id] = 20;
        WIN_W[id] = 740;
        if (WIN_W[id] > G_XRES - 40) { WIN_W[id] = G_XRES - 40; }
        WIN_H[id] = 480;
        if (WIN_H[id] > G_YRES - tbh - 30) { WIN_H[id] = G_YRES - tbh - 30; }
    } else {
        WIN_X[id] = 8;
        WIN_Y[id] = 8;
        WIN_W[id] = G_XRES - 16;
        WIN_H[id] = G_YRES - tbh - 16;
    }
    dsk_draw_all();
}

fn dsk_add_widget(int win, int type, int x, int y, int w, int h, string label, int val, int vmin, int vmax) -> int {
    if (win < 0 || win >= win_count) { return 0 - 1; }
    if (w_count >= DSK_MAX_WIDGETS) { return 0 - 1; }
    int id = w_count;
    W_TYPE[id] = type;
    W_X[id] = x;
    W_Y[id] = y;
    W_W[id] = w;
    W_H[id] = h;
    W_VAL[id] = val;
    W_MIN[id] = vmin;
    W_MAX[id] = vmax;
    W_FLAGS[id] = WF_ENABLED;
    W_WIN[id] = win;
    W_LBL[id] = label;
    W_TXTP[id] = 0;
    W_CARET[id] = 0;
    if (type == WT_INPUT) {
        char* tb = alloc<char>(DSK_INPUT_CAP);
        _zero(tb, DSK_INPUT_CAP);
        _str_copy(tb, label, DSK_INPUT_CAP);
        W_TXTP[id] = cast<int>(tb);
        W_CARET[id] = _str_len(label);
    }
    w_count = w_count + 1;
    WIN_WCOUNT[win] = WIN_WCOUNT[win] + 1;
    return id;
}

fn dsk_widget_val(int id) -> int { if (id < 0) { return 0; } return W_VAL[id]; }
fn dsk_widget_set(int id, int val) -> void {
    if (id < 0) { return; }
    if (val < W_MIN[id] && W_MAX[id] > W_MIN[id]) { val = W_MIN[id]; }
    if (val > W_MAX[id] && W_MAX[id] > W_MIN[id]) { val = W_MAX[id]; }
    W_VAL[id] = val;
}
fn dsk_widget_on(int id) -> int { if (id < 0) { return 0; } return W_VAL[id]; }
fn dsk_widget_toggle(int id) -> void { if (id >= 0) { W_VAL[id] = 1 - W_VAL[id]; } }
fn dsk_widget_label(int id) -> string { if (id < 0) { return ""; } return W_LBL[id]; }
fn dsk_widget_set_label(int id, string s) -> void {
    if (id < 0) { return; }
    W_LBL[id] = s;
    if (W_TYPE[id] == WT_INPUT && W_TXTP[id] != 0) {
        char* tb = cast<char*>(W_TXTP[id]);
        _str_copy(tb, s, DSK_INPUT_CAP);
        W_CARET[id] = _str_len(s);
    }
}
fn dsk_widget_type(int id) -> int { if (id < 0) { return WT_NONE; } return W_TYPE[id]; }

// ─── Editable text helpers ───────────────────────────────
fn dsk_widget_text(int id) -> string {
    if (id < 0) { return ""; }
    if (W_TYPE[id] == WT_INPUT && W_TXTP[id] != 0) { return cast<string>(cast<char*>(W_TXTP[id])); }
    return W_LBL[id];
}
fn dsk_widget_set_text(int id, string s) -> void {
    if (id < 0) { return; }
    if (W_TYPE[id] == WT_INPUT && W_TXTP[id] != 0) {
        char* tb = cast<char*>(W_TXTP[id]);
        _str_copy(tb, s, DSK_INPUT_CAP);
        W_CARET[id] = _str_len(s);
    } else {
        W_LBL[id] = s;
    }
}
fn dsk_widget_clear_text(int id) -> void { dsk_widget_set_text(id, ""); }
fn dsk_widget_caret(int id) -> int { if (id < 0) { return 0; } return W_CARET[id]; }

fn dsk_widget_visible(int id) -> int {
    if (id < 0) { return 0; }
    return 1 - dsk_widget_has_flag(id, WF_HIDDEN);
}
fn dsk_widget_enabled(int id) -> int {
    if (id < 0) { return 0; }
    return dsk_widget_has_flag(id, WF_ENABLED);
}
fn dsk_widget_show(int id) -> void { if (id >= 0) { dsk_set_flag(id, WF_HIDDEN, 0); } }
fn dsk_widget_hide(int id) -> void { if (id >= 0) { dsk_set_flag(id, WF_HIDDEN, 1); } }
fn dsk_widget_set_enabled(int id, int on) -> void { if (id >= 0) { dsk_set_flag(id, WF_ENABLED, on); } }

fn dsk_widget_move(int id, int x, int y) -> void {
    if (id < 0) { return; }
    W_X[id] = x; W_Y[id] = y;
}
fn dsk_widget_resize(int id, int w, int h) -> void {
    if (id < 0) { return; }
    W_W[id] = w; W_H[id] = h;
}
fn dsk_widget_set_range(int id, int vmin, int vmax) -> void {
    if (id < 0) { return; }
    W_MIN[id] = vmin;
    W_MAX[id] = vmax;
}
fn dsk_widget_changed(int id) -> int {
    if (id < 0) { return 0; }
    return dsk_widget_has_flag(id, WF_CHANGED);
}
fn dsk_widget_clear_changed(int id) -> void { if (id >= 0) { dsk_set_flag(id, WF_CHANGED, 0); } }

fn dsk_focus_widget(int id) -> void {
    if (id < 0 || id >= w_count) { return; }
    if (W_TYPE[id] != WT_INPUT) { return; }
    if (DSK_FOCUS_WID >= 0 && DSK_FOCUS_WID != id) { dsk_set_flag(DSK_FOCUS_WID, WF_FOCUS, 0); }
    DSK_FOCUS_WID = id;
    dsk_set_flag(id, WF_FOCUS, 1);
}
fn dsk_focused_widget() -> int { return DSK_FOCUS_WID; }
fn dsk_clear_focus() -> void {
    if (DSK_FOCUS_WID >= 0) { dsk_set_flag(DSK_FOCUS_WID, WF_FOCUS, 0); }
    DSK_FOCUS_WID = 0 - 1;
}

fn dsk_window_x(int id) -> int { return WIN_X[id]; }
fn dsk_window_y(int id) -> int { return WIN_Y[id]; }
fn dsk_window_w(int id) -> int { return WIN_W[id]; }
fn dsk_window_h(int id) -> int { return WIN_H[id]; }
fn dsk_window_widget(int id) -> int { return WIN_WSTART[id]; }
fn dsk_window_widget_count(int id) -> int { return WIN_WCOUNT[id]; }
fn dsk_window_title(int id) -> string { return WIN_TITLE[id]; }
fn dsk_window_focused(int id) -> int {
    if (id < 0) { return 0; }
    return (WIN_FLAGS[id] / 2) - (WIN_FLAGS[id] / 4) * 2;
}
fn dsk_active() -> int { return DSK_ACTIVE; }

fn dsk_window_set_title(int id, string title) -> void {
    if (id < 0 || id >= win_count) { return; }
    WIN_TITLE[id] = title;
}
fn dsk_window_move(int id, int x, int y) -> void {
    if (id < 0 || id >= win_count) { return; }
    WIN_X[id] = x; WIN_Y[id] = y;
}
fn dsk_window_resize(int id, int w, int h) -> void {
    if (id < 0 || id >= win_count) { return; }
    WIN_W[id] = w; WIN_H[id] = h;
}
fn dsk_window_center(int id) -> void {
    if (id < 0 || id >= win_count) { return; }
    WIN_X[id] = (G_XRES - WIN_W[id]) / 2;
    WIN_Y[id] = (G_YRES - WIN_H[id]) / 2;
    if (WIN_Y[id] < 0) { WIN_Y[id] = 0; }
}
fn dsk_window_show(int id) -> void {
    if (id < 0 || id >= win_count) { return; }
    WIN_FLAGS[id] = WIN_FLAGS[id] - (WIN_FLAGS[id] / 2) * 2 + 1;
    dsk_focus_window(id);
}
fn dsk_window_hide(int id) -> void {
    if (id < 0 || id >= win_count) { return; }
    WIN_FLAGS[id] = WIN_FLAGS[id] - (WIN_FLAGS[id] / 2) * 2;
}

// ─── Convenience widget builders ─────────────────────────
fn dsk_label(int win, int x, int y, int w, int h, string text) -> int {
    return dsk_add_widget(win, WT_LABEL, x, y, w, h, text, 0, 0, 0);
}
fn dsk_button(int win, int x, int y, int w, int h, string text) -> int {
    return dsk_add_widget(win, WT_BUTTON, x, y, w, h, text, 0, 0, 0);
}
fn dsk_checkbox(int win, int x, int y, int w, int h, string text, int on) -> int {
    return dsk_add_widget(win, WT_CHECKBOX, x, y, w, h, text, on, 0, 1);
}
fn dsk_switch(int win, int x, int y, string text, int on) -> int {
    return dsk_add_widget(win, WT_SWITCH, x, y, 44, 22, text, on, 0, 1);
}
fn dsk_slider(int win, int x, int y, int w, int h, int val, int vmin, int vmax) -> int {
    return dsk_add_widget(win, WT_SLIDER, x, y, w, h, "", val, vmin, vmax);
}
fn dsk_progress(int win, int x, int y, int w, int h, int val, int vmax) -> int {
    return dsk_add_widget(win, WT_PROGRESS, x, y, w, h, "", val, 0, vmax);
}
fn dsk_textbox(int win, int x, int y, int w, int h, string text) -> int {
    return dsk_add_widget(win, WT_TEXTBOX, x, y, w, h, text, 0, 0, 0);
}
fn dsk_input(int win, int x, int y, int w, int h, string text) -> int {
    return dsk_add_widget(win, WT_INPUT, x, y, w, h, text, 0, 0, 0);
}
fn dsk_listbox(int win, int x, int y, int w, int h) -> int {
    return dsk_add_widget(win, WT_LISTBOX, x, y, w, h, "", 0, 0, 0);
}
fn dsk_badge(int win, int x, int y, int w, int h, string text, int kind) -> int {
    return dsk_add_widget(win, WT_BADGE, x, y, w, h, text, kind, 0, 3);
}
fn dsk_separator(int win, int x, int y, int w) -> int {
    return dsk_add_widget(win, WT_SEPARATOR, x, y, w, 1, "", 0, 0, 0);
}
fn dsk_card(int win, int x, int y, int w, int h) -> int {
    return dsk_add_widget(win, WT_CARD, x, y, w, h, "", 0, 0, 0);
}
fn dsk_spinner(int win, int x, int y, int size) -> int {
    return dsk_add_widget(win, WT_SPINNER, x, y, size, size, "", 0, 0, 0);
}
fn dsk_tabs(int win, int x, int y, int w, int h, string labels, int active) -> int {
    return dsk_add_widget(win, WT_TABS, x, y, w, h, labels, active, 0, 0);
}

fn dsk_add_list_item(int box, string text) -> int {
    if (box < 0 || box >= w_count || W_TYPE[box] != WT_LISTBOX) { return 0 - 1; }
    if (lb_count >= DSK_MAX_ITEMS) { return 0 - 1; }
    int id = lb_count;
    LB_TEXT[id] = text;
    LB_OWNER[id] = box;
    lb_count = lb_count + 1;
    return id;
}

fn dsk_list_count(int box) -> int {
    int i = 0;
    int n = 0;
    while (i < lb_count) {
        if (LB_OWNER[i] == box) { n = n + 1; }
        i = i + 1;
    }
    return n;
}

fn dsk_list_item(int box, int index) -> string {
    int i = 0;
    int n = 0;
    while (i < lb_count) {
        if (LB_OWNER[i] == box) {
            if (n == index) { return LB_TEXT[i]; }
            n = n + 1;
        }
        i = i + 1;
    }
    return "";
}

fn dsk_list_clear(int box) -> void {
    int i = 0;
    while (i < lb_count) {
        if (LB_OWNER[i] == box) { LB_OWNER[i] = 0 - 1; }
        i = i + 1;
    }
    W_VAL[box] = 0;
    W_CARET[box] = 0;
}

fn dsk_list_selected(int box) -> int { return W_VAL[box]; }
fn dsk_list_select(int box, int index) -> void {
    if (index >= 0 && index < dsk_list_count(box)) { W_VAL[box] = index; }
}

fn dsk_screen_x(int wid) -> int { return WIN_X[W_WIN[wid]] + W_X[wid]; }
fn dsk_screen_y(int wid) -> int { return WIN_Y[W_WIN[wid]] + W_Y[wid]; }

fn dsk_widget_hit(int wid, int mx, int my) -> int {
    int sx = dsk_screen_x(wid);
    int sy = dsk_screen_y(wid);
    if (mx < sx) { return 0; }
    if (mx >= sx + W_W[wid]) { return 0; }
    if (my < sy) { return 0; }
    if (my >= sy + W_H[wid]) { return 0; }
    return 1;
}

// ─── Modern Widget Renderers ─────────────────────────────
fn _tab_count(string s) -> int {
    char* p = cast<char*>(s);
    int i = 0;
    int n = 1;
    while (_byte_val(*(p + i)) != 0) {
        if (_byte_val(*(p + i)) == 124) { n = n + 1; }
        i = i + 1;
    }
    return n;
}

fn _tab_start(string s, int idx) -> int {
    char* p = cast<char*>(s);
    int i = 0;
    int n = 0;
    while (_byte_val(*(p + i)) != 0) {
        if (n == idx) { return i; }
        if (_byte_val(*(p + i)) == 124) { n = n + 1; }
        i = i + 1;
    }
    return i;
}

fn _tab_len(string s, int idx) -> int {
    char* p = cast<char*>(s);
    int start = _tab_start(s, idx);
    int i = start;
    while (_byte_val(*(p + i)) != 0 && _byte_val(*(p + i)) != 124) { i = i + 1; }
    return i - start;
}

fn _draw_slice(int x, int y, string s, int start, int len, int fg, int bg, int maxw) -> void {
    char* p = cast<char*>(s);
    int i = 0;
    int cx = x;
    while (i < len) {
        int ch = _byte_val(*(p + start + i));
        if (ch < 32 || ch > 126) { ch = 32; }
        if (cx + 8 * G_GUI_SCALE > x + maxw) { return; }
        gui_draw_char(cx, y, ch, fg, bg, G_GUI_SCALE);
        cx = cx + 8 * G_GUI_SCALE;
        i = i + 1;
    }
}

fn dsk_draw_label(int id) -> void {
    int fg = TH_TEXT;
    if (dsk_widget_has_flag(id, WF_ENABLED) == 0) { fg = TH_DISABLED; }
    dsk_text_clip(dsk_screen_x(id), dsk_screen_y(id), W_LBL[id], fg, TH_PANEL, W_W[id]);
}

fn dsk_draw_button(int id) -> void {
    int sx = dsk_screen_x(id);
    int sy = dsk_screen_y(id);
    int enabled = dsk_widget_has_flag(id, WF_ENABLED);
    int bg = TH_BTN;
    int fg = TH_BTN_FG;
    int border = TH_BORDER;
    if (enabled == 0) {
        fg = TH_DISABLED;
    } else if (dsk_widget_has_flag(id, WF_PRESSED) == 1) {
        bg = TH_ACCENT;
        fg = TH_ACCENT_FG;
        border = TH_ACCENT;
    } else if (dsk_widget_has_flag(id, WF_HOVER) == 1) {
        bg = TH_BTN_HOVER;
        border = TH_ACCENT;
    }
    int shadow_off = 2;
    if (dsk_widget_has_flag(id, WF_PRESSED) == 1) { shadow_off = 0; }
    gui_fill_rounded_rect_alpha(sx, sy + shadow_off, W_W[id], W_H[id], DSK_RADIUS, TH_SHADOW, 45);
    int top = bg;
    if (enabled == 1 && dsk_widget_has_flag(id, WF_PRESSED) == 0) { top = gui_lighten(bg, 16); }
    gui_fill_rounded_gradient_v(sx, sy, W_W[id], W_H[id], DSK_RADIUS, top, bg);
    gui_draw_rounded_rect(sx, sy, W_W[id], W_H[id], DSK_RADIUS, border);
    dsk_text_center_fg(sx, sy + (W_H[id] - 16 * G_GUI_SCALE) / 2, W_W[id], W_LBL[id], fg);
}

fn dsk_draw_checkbox(int id) -> void {
    int sx = dsk_screen_x(id);
    int sy = dsk_screen_y(id);
    int fg = TH_TEXT;
    if (dsk_widget_has_flag(id, WF_ENABLED) == 0) { fg = TH_DISABLED; }
    gui_fill_rounded_rect(sx, sy + 2, 18, 18, 4, TH_INPUT_BG);
    gui_draw_rounded_rect(sx, sy + 2, 18, 18, 4, TH_BORDER);
    if (W_VAL[id] == 1) {
        gui_fill_rounded_rect(sx + 3, sy + 5, 12, 12, 3, TH_ACCENT);
    }
    dsk_text_clip(sx + 26, sy + 3, W_LBL[id], fg, TH_PANEL, W_W[id] - 26);
}

// Modern iOS/Android style toggle switch
fn dsk_draw_switch(int id) -> void {
    int sx = dsk_screen_x(id);
    int sy = dsk_screen_y(id);
    int sw = 44;
    int sh = 22;
    int bg = TH_BORDER;
    int fg = TH_TEXT;
    if (dsk_widget_has_flag(id, WF_ENABLED) == 0) { fg = TH_DISABLED; }
    if (W_VAL[id] == 1) { bg = TH_SUCCESS; }
    gui_fill_rounded_rect(sx, sy, sw, sh, sh / 2, bg);
    gui_draw_rounded_rect(sx, sy, sw, sh, sh / 2, TH_BORDER);
    int kx = sx + 2;
    if (W_VAL[id] == 1) { kx = sx + sw - 20; }
    gui_fill_circle(kx + 9, sy + 11, 7, gui_rgb(255, 255, 255));
    if (_str_len(W_LBL[id]) > 0) {
        dsk_text_clip(sx + sw + 10, sy + 3, W_LBL[id], fg, TH_PANEL, W_W[id] - sw - 10);
    }
}

// Status Badge / Tag (0 info, 1 success, 2 danger, 3 warning)
fn dsk_draw_badge(int id) -> void {
    int sx = dsk_screen_x(id);
    int sy = dsk_screen_y(id);
    int bg = TH_INFO;
    int fg = TH_ACCENT_FG;
    if (W_VAL[id] == 1) { bg = TH_SUCCESS; }
    else if (W_VAL[id] == 2) { bg = TH_DANGER; }
    else if (W_VAL[id] == 3) { bg = TH_WARNING; fg = TH_TEXT; }
    gui_fill_rounded_rect(sx, sy, W_W[id], W_H[id], W_H[id] / 2, bg);
    dsk_text_center(sx, sy + (W_H[id] - 16 * G_GUI_SCALE) / 2, W_W[id], W_LBL[id], fg, bg);
}

// Decorative Horizontal Separator
fn dsk_draw_separator(int id) -> void {
    int sx = dsk_screen_x(id);
    int sy = dsk_screen_y(id);
    dsk_hline(sx, sy, W_W[id], TH_DIVIDER);
}

fn dsk_draw_slider(int id) -> void {
    int sx = dsk_screen_x(id);
    int sy = dsk_screen_y(id);
    int track_y = sy + W_H[id] / 2;
    int accent = TH_ACCENT;
    if (dsk_widget_has_flag(id, WF_ENABLED) == 0) { accent = TH_DISABLED; }
    gui_fill_rounded_rect(sx, track_y - 3, W_W[id], 6, 3, TH_BTN);
    int span = W_W[id] - 16;
    int rng = W_MAX[id] - W_MIN[id];
    int knob = 0;
    if (rng > 0) {
        knob = (W_VAL[id] - W_MIN[id]) * span / rng;
        if (knob < 0) { knob = 0; }
        if (knob > span) { knob = span; }
    }
    gui_fill_rounded_rect(sx, track_y - 3, knob + 8, 6, 3, accent);
    gui_fill_circle(sx + 8 + knob, track_y, 8, TH_TITLE);
    gui_fill_circle(sx + 8 + knob, track_y, 4, gui_rgb(255, 255, 255));
}

fn dsk_draw_progress(int id) -> void {
    int sx = dsk_screen_x(id);
    int sy = dsk_screen_y(id);
    int accent = TH_ACCENT;
    if (dsk_widget_has_flag(id, WF_ENABLED) == 0) { accent = TH_DISABLED; }
    gui_fill_rounded_rect(sx, sy, W_W[id], W_H[id], 4, TH_BTN);
    int vmax = W_MAX[id];
    if (vmax <= 0) { vmax = 100; }
    int fill_w = W_W[id] * W_VAL[id] / vmax;
    if (fill_w < 0) { fill_w = 0; }
    if (fill_w > W_W[id]) { fill_w = W_W[id]; }
    if (fill_w > 0) {
        gui_fill_gradient_h(sx, sy, fill_w, W_H[id], accent, accent + 0x152020);
    }
    gui_draw_rounded_rect(sx, sy, W_W[id], W_H[id], 4, TH_BORDER);
}

fn dsk_draw_textbox(int id) -> void {
    int sx = dsk_screen_x(id);
    int sy = dsk_screen_y(id);
    gui_fill_rounded_rect(sx, sy, W_W[id], W_H[id], DSK_RADIUS, TH_INPUT_BG);
    gui_draw_rounded_rect(sx, sy, W_W[id], W_H[id], DSK_RADIUS, TH_BORDER);
    dsk_text_clip(sx + 8, sy + (W_H[id] - 16 * G_GUI_SCALE) / 2, W_LBL[id], TH_TEXT, TH_INPUT_BG, W_W[id] - 16);
}

// Editable text field with caret, focus ring and horizontal clipping.
fn dsk_draw_input(int id) -> void {
    int sx = dsk_screen_x(id);
    int sy = dsk_screen_y(id);
    int focused = dsk_widget_has_flag(id, WF_FOCUS);
    int border = TH_BORDER;
    if (focused == 1) { border = TH_FOCUS; }
    gui_fill_rounded_rect(sx, sy, W_W[id], W_H[id], DSK_RADIUS, TH_INPUT_BG);
    gui_draw_rounded_rect(sx, sy, W_W[id], W_H[id], DSK_RADIUS, border);
    if (focused == 1) {
        gui_draw_rounded_rect_ex(sx - 2, sy - 2, W_W[id] + 4, W_H[id] + 4, DSK_RADIUS + 2, 2, TH_FOCUS, 120);
    }
    int ty = sy + (W_H[id] - 16 * G_GUI_SCALE) / 2;
    int cap = W_W[id] - 16;
    if (W_TXTP[id] != 0) {
        string txt = cast<string>(cast<char*>(W_TXTP[id]));
        dsk_text_clip(sx + 8, ty, txt, TH_TEXT, TH_INPUT_BG, cap);
        if (focused == 1 && (DSK_FRAME / 24) - ((DSK_FRAME / 24) / 2) * 2 == 0) {
            int cx = sx + 8 + W_CARET[id] * 8 * G_GUI_SCALE;
            if (cx >= sx + 8 && cx < sx + 8 + cap) {
                gui_fill_rect(cx, ty, 1, 16 * G_GUI_SCALE, TH_CARET);
            }
        }
    }
}

fn dsk_draw_listbox(int id) -> void {
    int sx = dsk_screen_x(id);
    int sy = dsk_screen_y(id);
    gui_fill_rounded_rect(sx, sy, W_W[id], W_H[id], DSK_RADIUS, TH_INPUT_BG);
    gui_draw_rounded_rect(sx, sy, W_W[id], W_H[id], DSK_RADIUS, TH_BORDER);
    int n = dsk_list_count(id);
    int offset = W_CARET[id];
    int maxrows = (W_H[id] - 8) / 20;
    if (offset > n - maxrows) { offset = n - maxrows; }
    if (offset < 0) { offset = 0; }
    int i = 0;
    while (i < maxrows) {
        int row = offset + i;
        if (row >= n) { return; }
        int ry = sy + 4 + i * 20;
        int rbg = TH_INPUT_BG;
        if (row - (row / 2) * 2 == 1) {
            rbg = TH_CARD;
            gui_fill_rect(sx + 2, ry - 1, W_W[id] - 4, 18, rbg);
        }
        if (W_VAL[id] == row) {
            gui_fill_rounded_rect(sx + 2, ry - 1, W_W[id] - 4, 18, 3, TH_ACCENT);
            dsk_text_clip(sx + 8, ry, dsk_list_item(id, row), TH_ACCENT_FG, TH_ACCENT, W_W[id] - 16);
        } else {
            dsk_text_clip(sx + 8, ry, dsk_list_item(id, row), TH_TEXT, rbg, W_W[id] - 16);
        }
        i = i + 1;
    }
}

// Tab navigation bar. Labels are separated with '|', W_VAL = active tab.
fn dsk_draw_tabs(int id) -> void {
    int sx = dsk_screen_x(id);
    int sy = dsk_screen_y(id);
    int n = _tab_count(W_LBL[id]);
    if (n <= 0) { return; }
    gui_fill_rounded_rect(sx, sy, W_W[id], W_H[id], DSK_RADIUS, TH_BTN);
    int tw = W_W[id] / n;
    int i = 0;
    while (i < n) {
        int tx = sx + i * tw;
        if (W_VAL[id] == i) {
            gui_fill_rounded_rect(tx + 2, sy + 3, tw - 4, W_H[id] - 6, DSK_RADIUS - 2, TH_ACCENT);
        }
        int slen = _tab_len(W_LBL[id], i);
        int textw = slen * 8 * G_GUI_SCALE;
        int off = (tw - textw) / 2;
        if (off < 4) { off = 4; }
        int fg = TH_BTN_FG;
        int tbg = TH_BTN;
        if (W_VAL[id] == i) { fg = TH_ACCENT_FG; tbg = TH_ACCENT; }
        _draw_slice(tx + off, sy + (W_H[id] - 16 * G_GUI_SCALE) / 2, W_LBL[id], _tab_start(W_LBL[id], i), slen, fg, tbg, tw - off - 2);
        i = i + 1;
    }
}

fn dsk_draw_card(int id) -> void {
    int sx = dsk_screen_x(id);
    int sy = dsk_screen_y(id);
    gui_fill_rounded_rect_alpha(sx + 1, sy + 2, W_W[id], W_H[id], DSK_RADIUS + 2, TH_SHADOW, 35);
    gui_fill_rounded_rect(sx, sy, W_W[id], W_H[id], DSK_RADIUS, TH_CARD);
    gui_draw_rounded_rect(sx, sy, W_W[id], W_H[id], DSK_RADIUS, TH_DIVIDER);
    if (_str_len(W_LBL[id]) > 0) {
        dsk_text_clip(sx + 12, sy + 10, W_LBL[id], TH_SUBTEXT, TH_CARD, W_W[id] - 24);
    }
}

// Animated spinner (8 dots rotating with the frame counter).
fn dsk_draw_spinner(int id) -> void {
    int sx = dsk_screen_x(id);
    int sy = dsk_screen_y(id);
    int cx = sx + W_W[id] / 2;
    int cy = sy + W_H[id] / 2;
    int r = W_W[id] / 2 - 3;
    if (r < 4) { r = 4; }
    array<int, 8> dx;
    array<int, 8> dy;
    dx[0] = 0;    dy[0] = 0 - r;
    dx[1] = r * 7 / 10;  dy[1] = 0 - r * 7 / 10;
    dx[2] = r;    dy[2] = 0;
    dx[3] = r * 7 / 10;  dy[3] = r * 7 / 10;
    dx[4] = 0;    dy[4] = r;
    dx[5] = 0 - r * 7 / 10; dy[5] = r * 7 / 10;
    dx[6] = 0 - r; dy[6] = 0;
    dx[7] = 0 - r * 7 / 10; dy[7] = 0 - r * 7 / 10;
    int active = (DSK_FRAME / 6) - ((DSK_FRAME / 6) / 8) * 8;
    int i = 0;
    while (i < 8) {
        int col = TH_BTN;
        int rad = 2;
        if (i == active) { col = TH_ACCENT; rad = 3; }
        gui_fill_circle(cx + dx[i], cy + dy[i], rad, col);
        i = i + 1;
    }
}

fn dsk_draw_widget(int id) -> void {
    if (dsk_widget_has_flag(id, WF_HIDDEN) == 1) { return; }
    int t = W_TYPE[id];
    if (t == WT_LABEL) { dsk_draw_label(id); }
    else if (t == WT_BUTTON) { dsk_draw_button(id); }
    else if (t == WT_CHECKBOX) { dsk_draw_checkbox(id); }
    else if (t == WT_SWITCH) { dsk_draw_switch(id); }
    else if (t == WT_BADGE) { dsk_draw_badge(id); }
    else if (t == WT_SEPARATOR) { dsk_draw_separator(id); }
    else if (t == WT_SLIDER) { dsk_draw_slider(id); }
    else if (t == WT_PROGRESS) { dsk_draw_progress(id); }
    else if (t == WT_TEXTBOX) { dsk_draw_textbox(id); }
    else if (t == WT_INPUT) { dsk_draw_input(id); }
    else if (t == WT_LISTBOX) { dsk_draw_listbox(id); }
    else if (t == WT_TABS) { dsk_draw_tabs(id); }
    else if (t == WT_CARD) { dsk_draw_card(id); }
    else if (t == WT_SPINNER) { dsk_draw_spinner(id); }
}

// ─── Professional Window Renderer ────────────────────────
fn dsk_draw_window(int id) -> void {
    if (dsk_window_visible(id) == 0) { return; }
    int x = WIN_X[id];
    int y = WIN_Y[id];
    int w = WIN_W[id];
    int h = WIN_H[id];
    int is_root = 0;
    if (DSK_APP_MODE == 1 && id == DSK_ROOT) { is_root = 1; }
    int show_chrome = 1;
    if (is_root == 1 && DSK_ROOT_CHROME == 0) { show_chrome = 0; }

    if (is_root == 0) { dsk_shadow(x, y, w, h); }

    if (show_chrome == 0) {
        gui_fill_rect(x, y, w, h, TH_PANEL);
    } else {
        gui_fill_rounded_rect(x, y, w, h, DSK_RADIUS, TH_PANEL);

        // Unified gradient title bar, clipped to the rounded top corners.
        int focused = dsk_window_focused(id);
        int tcol = TH_TITLE;
        int tcol2 = TH_TITLE_GRAD;
        if (focused == 0) { tcol2 = tcol; }
        int tr = DSK_RADIUS - 1;
        if (tr < 0) { tr = 0; }
        gui_fill_top_rounded_gradient_v(x + 1, y + 1, w - 2, DSK_TITLE_H - 1, tr, tcol, tcol2);
        dsk_text_clip_fg(x + DSK_PAD, y + (DSK_TITLE_H - 16 * G_GUI_SCALE) / 2, WIN_TITLE[id], TH_TITLE_FG, w - 70);

        // Window controls: close (red), minimize (yellow), maximize (green)
        int btn_y = y + DSK_TITLE_H / 2;
        gui_fill_circle(x + w - 18, btn_y, 5, TH_DANGER);
        gui_fill_circle(x + w - 34, btn_y, 5, TH_WARNING);
        gui_fill_circle(x + w - 50, btn_y, 5, TH_SUCCESS);

        int border = TH_BORDER;
        if (focused == 1) { border = TH_TITLE; }
        gui_draw_rounded_rect(x, y, w, h, DSK_RADIUS, border);
    }

    int i = 0;
    int idx = WIN_WSTART[id];
    while (i < WIN_WCOUNT[id]) {
        dsk_draw_widget(idx + i);
        i = i + 1;
    }
}

fn dsk_draw_desktop() -> void {
    gui_clear(TH_DESKTOP);
    gui_fill_gradient_v(0, 0, G_XRES, G_YRES, TH_DESKTOP, TH_DESKTOP + 0x060810);
    int gx = 0;
    int gy = 0;
    while (gy < G_YRES) {
        gx = 0;
        while (gx < G_XRES) {
            gui_put_pixel(gx, gy, TH_DESKTOP + 0x060810);
            gx = gx + 48;
        }
        gy = gy + 48;
    }
}

fn dsk_taskbar_h() -> int { return DSK_TASKBAR_H; }

fn dsk_draw_taskbar() -> void {
    if (DSK_TASKBAR_ON == 0) { return; }
    if (G_YRES < 240) { return; }
    int th = dsk_taskbar_h();
    int bar_y = G_YRES - th;
    gui_fill_gradient_v(0, bar_y, G_XRES, th, TH_TASKBAR + 0x080808, TH_TASKBAR);
    dsk_hline(0, bar_y, G_XRES, TH_BORDER);

    gui_fill_rounded_rect(DSK_PAD, bar_y + 7, 96, th - 14, 5, TH_ACCENT);
    dsk_text_center(DSK_PAD, bar_y + (th - 16 * G_GUI_SCALE) / 2, 96, "FALCON", TH_ACCENT_FG, TH_ACCENT);

    int i = 0;
    int bx = DSK_PAD + 108;
    while (i < win_count) {
        if (DSK_APP_MODE == 1 && i == DSK_ROOT) { i = i + 1; }
        else {
            int label_w = gui_text_width(WIN_TITLE[i], G_GUI_SCALE) + 28;
            int bg = TH_BTN;
            if (DSK_ACTIVE == i) { bg = TH_ACCENT; }
            gui_fill_rounded_rect(bx, bar_y + 7, label_w, th - 14, 5, bg);
            gui_draw_rounded_rect(bx, bar_y + 7, label_w, th - 14, 5, TH_BORDER);
            dsk_text_center(bx, bar_y + (th - 16 * G_GUI_SCALE) / 2, label_w, WIN_TITLE[i], TH_BTN_FG, bg);
            bx = bx + label_w + 8;
            i = i + 1;
        }
    }
}

fn dsk_draw_toast() -> void {
    if (DSK_TOAST_TTL <= 0 || DSK_TOAST == 0) { return; }
    string text = cast<string>(DSK_TOAST);
    int tw = gui_text_width(text, G_GUI_SCALE);
    if (tw > G_XRES - 80) { tw = G_XRES - 80; }
    int bw = tw + 32;
    int bx = (G_XRES - bw) / 2;
    int by = G_YRES - 76;
    if (DSK_TASKBAR_ON == 1 && G_YRES >= 240) { by = G_YRES - dsk_taskbar_h() - 52; }
    gui_fill_rounded_rect(bx, by, bw, 34, 6, TH_TASKBAR);
    gui_draw_rounded_rect(bx, by, bw, 34, 6, TH_ACCENT);
    dsk_text_clip(bx + 16, by + 9, text, TH_TITLE_FG, TH_TASKBAR, bw - 32);
}

fn dsk_draw_all() -> void {
    dsk_draw_desktop();
    int active = DSK_ACTIVE;
    int top = active;
    int is_root_active = 0;
    if (DSK_APP_MODE == 1 && DSK_ROOT >= 0 && DSK_ROOT < win_count) {
        dsk_draw_window(DSK_ROOT);
        if (active == DSK_ROOT) { is_root_active = 1; top = 0 - 1; }
    }
    int i = 0;
    while (i < win_count) {
        if (i != top && !(DSK_APP_MODE == 1 && i == DSK_ROOT)) { dsk_draw_window(i); }
        i = i + 1;
    }
    if (top >= 0 && top < win_count && is_root_active == 0) { dsk_draw_window(top); }
    dsk_draw_taskbar();
    dsk_draw_toast();
}

fn dsk_draw_cursor(int mx, int my) -> void {
    if (G_X11_ACTIVE == 1) { return; }
    dsk_line(mx, my, mx, my + 12, gui_rgb(255, 255, 255));
    dsk_line(mx, my, mx + 8, my + 8, gui_rgb(255, 255, 255));
    dsk_line(mx + 1, my + 1, mx + 1, my + 11, gui_rgb(20, 20, 20));
    dsk_line(mx + 1, my + 1, mx + 7, my + 7, gui_rgb(20, 20, 20));
}

fn dsk_widget_has_flag(int id, int bit) -> int {
    int v = W_FLAGS[id] / bit;
    return v - (v / 2) * 2;
}

fn dsk_set_flag(int id, int bit, int on) -> void {
    int cur = dsk_widget_has_flag(id, bit);
    if (on == 1 && cur == 0) { W_FLAGS[id] = W_FLAGS[id] + bit; }
    if (on == 0 && cur == 1) { W_FLAGS[id] = W_FLAGS[id] - bit; }
}

fn dsk_clear_transient() -> void {
    int i = 0;
    while (i < w_count) {
        dsk_set_flag(i, WF_HOVER, 0);
        dsk_set_flag(i, WF_PRESSED, 0);
        i = i + 1;
    }
}

fn dsk_find_widget_at(int mx, int my, int win) -> int {
    int i = WIN_WCOUNT[win] - 1;
    int idx = WIN_WSTART[win];
    while (i >= 0) {
        if (dsk_widget_hit(idx + i, mx, my) == 1) { return idx + i; }
        i = i - 1;
    }
    return 0 - 1;
}

fn dsk_hit_window(int mx, int my) -> int {
    int i = win_count - 1;
    while (i >= 0) {
        if (dsk_window_visible(i) == 1) {
            if (mx >= WIN_X[i] && mx < WIN_X[i] + WIN_W[i] &&
                my >= WIN_Y[i] && my < WIN_Y[i] + WIN_H[i]) {
                return i;
            }
        }
        i = i - 1;
    }
    return 0 - 1;
}

fn dsk_taskbar_hit(int mx, int my) -> int {
    if (DSK_TASKBAR_ON == 0 || G_YRES < 240) { return 0 - 1; }
    int bar_y = G_YRES - dsk_taskbar_h();
    if (my < bar_y) { return 0 - 1; }
    int i = 0;
    int bx = DSK_PAD + 108;
    while (i < win_count) {
        if (DSK_APP_MODE == 1 && i == DSK_ROOT) { i = i + 1; }
        else {
            int label_w = gui_text_width(WIN_TITLE[i], G_GUI_SCALE) + 28;
            if (mx >= bx && mx < bx + label_w) { return i; }
            bx = bx + label_w + 8;
            i = i + 1;
        }
    }
    return 0 - 1;
}

// ─── Editable input internals ────────────────────────────
fn _dsk_input_insert(int id, int ch) -> void {
    if (W_TXTP[id] == 0) { return; }
    char* tb = cast<char*>(W_TXTP[id]);
    int n = _str_len(cast<string>(tb));
    if (n >= DSK_INPUT_CAP - 1) { return; }
    int c = W_CARET[id];
    if (c < 0) { c = 0; }
    if (c > n) { c = n; }
    int i = n;
    while (i >= c) {
        *(tb + i + 1) = *(tb + i);
        i = i - 1;
    }
    *(tb + c) = ch;
    W_CARET[id] = c + 1;
    dsk_set_flag(id, WF_CHANGED, 1);
}

fn _dsk_input_backspace(int id) -> void {
    if (W_TXTP[id] == 0) { return; }
    char* tb = cast<char*>(W_TXTP[id]);
    int n = _str_len(cast<string>(tb));
    int c = W_CARET[id];
    if (c <= 0) { return; }
    if (c > n) { c = n; }
    int i = c - 1;
    while (i < n) {
        *(tb + i) = *(tb + i + 1);
        i = i + 1;
    }
    W_CARET[id] = c - 1;
    dsk_set_flag(id, WF_CHANGED, 1);
}

fn _dsk_input_delete(int id) -> void {
    if (W_TXTP[id] == 0) { return; }
    char* tb = cast<char*>(W_TXTP[id]);
    int n = _str_len(cast<string>(tb));
    int c = W_CARET[id];
    if (c < 0 || c >= n) { return; }
    int i = c;
    while (i < n) {
        *(tb + i) = *(tb + i + 1);
        i = i + 1;
    }
    dsk_set_flag(id, WF_CHANGED, 1);
}

fn _dsk_cycle_input(int dir) -> void {
    if (w_count <= 0) { return; }
    int start = DSK_FOCUS_WID;
    if (start < 0) { start = 0; }
    else { start = start + dir; }
    int i = 0;
    while (i < w_count) {
        int k = start + dir * i;
        while (k < 0) { k = k + w_count; }
        while (k >= w_count) { k = k - w_count; }
        if (W_TYPE[k] == WT_INPUT && dsk_widget_has_flag(k, WF_ENABLED) == 1 && dsk_widget_has_flag(k, WF_HIDDEN) == 0) {
            dsk_focus_widget(k);
            return;
        }
        i = i + 1;
    }
}

fn _dsk_process_keys() -> int {
    int result = 0 - 1;
    int k = gui_key_poll();
    while (k >= 0) {
        if (k == 9) {
            if (gui_shift_down() == 1) { _dsk_cycle_input(0 - 1); }
            else { _dsk_cycle_input(1); }
        } else if (k == 27) {
            dsk_clear_focus();
        } else if (DSK_FOCUS_WID >= 0) {
            int id = DSK_FOCUS_WID;
            if (k == 10) {
                result = id;
            } else if (k == 8) {
                _dsk_input_backspace(id);
            } else if (k == 127) {
                _dsk_input_delete(id);
            } else if (k == 130) {
                if (W_CARET[id] > 0) { W_CARET[id] = W_CARET[id] - 1; }
            } else if (k == 131) {
                int n = _str_len(dsk_widget_text(id));
                if (W_CARET[id] < n) { W_CARET[id] = W_CARET[id] + 1; }
            } else if (k == 132) {
                W_CARET[id] = 0;
            } else if (k == 133) {
                W_CARET[id] = _str_len(dsk_widget_text(id));
            } else if (k >= 32 && k <= 126) {
                _dsk_input_insert(id, k);
            }
        }
        k = gui_key_poll();
    }
    return result;
}

fn dsk_update() -> int {
    if (DSK_READY == 0) { return 0 - 1; }

    if (G_X11_ACTIVE == 1 && G_X11_CLOSE_REQ == 1) {
        DSK_RUNNING = 0;
        return 0 - 2;
    }

    DSK_FRAME = DSK_FRAME + 1;
    if (DSK_TOAST_TTL > 0) { DSK_TOAST_TTL = DSK_TOAST_TTL - 1; }

    gui_read_mouse();
    int mx = gui_mouse_x();
    int my = gui_mouse_y();
    int btn = gui_mouse_left();
    int click = gui_mouse_clicked();
    DSK_WHEEL = gui_mouse_wheel();

    DSK_CLICKED = 0 - 1;
    if (btn == 0) {
        int i = 0;
        while (i < w_count) {
            dsk_set_flag(i, WF_PRESSED, 0);
            i = i + 1;
        }
    }
    int key_click = _dsk_process_keys();
    if (key_click >= 0) { DSK_CLICKED = key_click; }

    int tb = 0 - 1;
    if (click == 1) { tb = dsk_taskbar_hit(mx, my); }
    if (tb >= 0) {
        dsk_focus_window(tb);
        dsk_draw_all();
        dsk_draw_cursor(mx, my);
        return 0 - 1;
    }

    int hit = dsk_hit_window(mx, my);
    DSK_HOVER_WIN = hit;
    int wid = 0 - 1;
    if (hit >= 0) {
        wid = dsk_find_widget_at(mx, my, hit);
        if (wid >= 0) {
            if (dsk_widget_has_flag(wid, WF_ENABLED) == 0 || dsk_widget_has_flag(wid, WF_HIDDEN) == 1) { wid = 0 - 1; }
        }
    }
    DSK_HOVER = wid;

    if (DSK_WHEEL != 0 && wid >= 0 && W_TYPE[wid] == WT_LISTBOX) {
        int n = dsk_list_count(wid);
        int maxrows = (W_H[wid] - 8) / 20;
        int off = W_CARET[wid] + DSK_WHEEL;
        if (off > n - maxrows) { off = n - maxrows; }
        if (off < 0) { off = 0; }
        W_CARET[wid] = off;
    }

    // Hover state (disabled / hidden widgets never light up)
    int i = 0;
    while (i < w_count) {
        if (i == wid) { dsk_set_flag(i, WF_HOVER, 1); }
        else { dsk_set_flag(i, WF_HOVER, 0); }
        i = i + 1;
    }

    if (hit >= 0) {
        int wx = WIN_X[hit];
        int wy = WIN_Y[hit];
        int ww = WIN_W[hit];
        int cy = wy + DSK_TITLE_H / 2;
        if (click == 1) {
            dsk_focus_window(hit);
            int title_area = 0;
            if (my >= wy && my < wy + DSK_TITLE_H) {
                title_area = 1;
                if (DSK_APP_MODE == 1 && hit == DSK_ROOT && DSK_ROOT_CHROME == 0) { title_area = 0; }
            }
            if (title_area == 1) {
                // Close
                if (mx >= wx + ww - 26 && mx <= wx + ww - 10 && my >= cy - 8 && my <= cy + 8) {
                    if (DSK_APP_MODE == 1 && hit == DSK_ROOT) { dsk_stop(); }
                    else { dsk_toggle_window(hit); }
                    dsk_draw_all();
                    return 0 - 1;
                }
                // Minimize
                if (mx >= wx + ww - 42 && mx <= wx + ww - 26 && my >= cy - 8 && my <= cy + 8) {
                    if (!(DSK_APP_MODE == 1 && hit == DSK_ROOT)) { dsk_toggle_window(hit); }
                    dsk_draw_all();
                    return 0 - 1;
                }
                // Maximize
                if (mx >= wx + ww - 58 && mx <= wx + ww - 42 && my >= cy - 8 && my <= cy + 8) {
                    dsk_maximize_window(hit);
                    dsk_draw_all();
                    return 0 - 1;
                }
            }
        }

        if (wid >= 0) {
            int t = W_TYPE[wid];
            if (click == 1) {
                if (t == WT_BUTTON) {
                    dsk_set_flag(wid, WF_PRESSED, 1);
                    DSK_CLICKED = wid;
                }
                else if (t == WT_CHECKBOX || t == WT_SWITCH) {
                    dsk_widget_toggle(wid);
                    dsk_set_flag(wid, WF_CHANGED, 1);
                    DSK_CLICKED = wid;
                }
                else if (t == WT_SLIDER) {
                    DSK_SLIDER = wid;
                }
                else if (t == WT_INPUT) {
                    dsk_focus_widget(wid);
                    int rel = mx - (dsk_screen_x(wid) + 8);
                    int c = rel / (8 * G_GUI_SCALE);
                    if (c < 0) { c = 0; }
                    int n = _str_len(dsk_widget_text(wid));
                    if (c > n) { c = n; }
                    W_CARET[wid] = c;
                }
                else if (t == WT_LISTBOX) {
                    int offset = W_CARET[wid];
                    int rel = my - (dsk_screen_y(wid)) - 4;
                    int row = offset + rel / 20;
                    if (row >= 0 && row < dsk_list_count(wid)) {
                        W_VAL[wid] = row;
                        dsk_set_flag(wid, WF_CHANGED, 1);
                        DSK_CLICKED = wid;
                    }
                }
                else if (t == WT_TABS) {
                    int n = _tab_count(W_LBL[wid]);
                    int rel = mx - dsk_screen_x(wid);
                    int tw = W_W[wid] / n;
                    if (n > 0 && tw > 0) {
                        int idx = rel / tw;
                        if (idx >= 0 && idx < n) {
                            W_VAL[wid] = idx;
                            dsk_set_flag(wid, WF_CHANGED, 1);
                            DSK_CLICKED = wid;
                        }
                    }
                }
                if (t == WT_INPUT || t == WT_SLIDER || t == WT_LISTBOX || t == WT_TABS || t == WT_BUTTON) {
                    dsk_clear_focus();
                    if (t == WT_INPUT) { dsk_focus_widget(wid); }
                }
                // Drag floating windows by their title bar only
                if (my < wy + DSK_TITLE_H && !(DSK_APP_MODE == 1 && hit == DSK_ROOT) && my >= wy) {
                    DSK_DRAG_WIN = hit;
                    DSK_DRAG_OX = mx - wx;
                    DSK_DRAG_OY = my - wy;
                }
            }
        } else {
            if (click == 1 && my < wy + DSK_TITLE_H && my >= wy && !(DSK_APP_MODE == 1 && hit == DSK_ROOT)) {
                DSK_DRAG_WIN = hit;
                DSK_DRAG_OX = mx - WIN_X[hit];
                DSK_DRAG_OY = my - WIN_Y[hit];
            }
        }
    }

    if (DSK_DRAG_WIN >= 0) {
        if (btn == 1) {
            WIN_X[DSK_DRAG_WIN] = mx - DSK_DRAG_OX;
            WIN_Y[DSK_DRAG_WIN] = my - DSK_DRAG_OY;
            if (WIN_Y[DSK_DRAG_WIN] < 0) { WIN_Y[DSK_DRAG_WIN] = 0; }
        } else {
            DSK_DRAG_WIN = 0 - 1;
        }
    }

    if (DSK_SLIDER >= 0) {
        if (btn == 1) {
            int wid2 = DSK_SLIDER;
            int sx = dsk_screen_x(wid2);
            int rel = mx - sx;
            int span = W_W[wid2] - 16;
            int rng = W_MAX[wid2] - W_MIN[wid2];
            int val = W_MIN[wid2];
            if (span > 0) { val = W_MIN[wid2] + rel * rng / span; }
            if (val < W_MIN[wid2]) { val = W_MIN[wid2]; }
            if (val > W_MAX[wid2]) { val = W_MAX[wid2]; }
            if (val != W_VAL[wid2]) { dsk_set_flag(wid2, WF_CHANGED, 1); }
            W_VAL[wid2] = val;
        } else {
            DSK_SLIDER = 0 - 1;
        }
    }

    dsk_draw_all();
    dsk_draw_cursor(mx, my);
    return DSK_CLICKED;
}

// Convenience frame: update + present + ~60 FPS pacing.
fn dsk_frame() -> int {
    int clicked = dsk_update();
    gui_present();
    sleep_ms(16);
    return clicked;
}

fn dsk_clicked_widget() -> int { return DSK_CLICKED; }
fn dsk_hovered_widget() -> int { return DSK_HOVER; }
fn dsk_hovered_window() -> int { return DSK_HOVER_WIN; }
fn dsk_mouse_wheel() -> int { return DSK_WHEEL; }
fn dsk_frame_count() -> int { return DSK_FRAME; }


fn dsk_msg(string s, int x, int y) -> void {
    gui_draw_text(x, y, s, TH_TEXT, TH_PANEL, G_GUI_SCALE);
}
