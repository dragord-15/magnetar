// ps2.mg — PS/2 keyboard + mouse driver (polling, no IRQ/IDT required)
//
// Talks to the 8042 PS/2 controller on ports 0x60 (data) and 0x64
// (status/command) through the io_ports abstraction. Works on bare metal
// and, for testing, on Linux via /dev/port.
//
// Usage:
//   use "ps2.mg";
//   ...
//   port_use_dev();        // Linux testing  (or port_enable_direct() as root)
//   ps2_init();
//   while (1) {
//       ps2_poll();
//       int ch = ps2_getchar();
//       if (ch != 0) { /* handle key */ }
//       /* ps2_mouse_x(), ps2_mouse_y(), ps2_mouse_clicked() */
//   }
//
// Scancode set 1 (translation enabled by the controller).
// Bitwise operations are emulated with / and % (the language has no & |).

use "io_ports.mg";

// ── Controller ports / commands ──
static const int PS2_DATA    = 0x60;
static const int PS2_STATUS  = 0x64;
static const int PS2_CMD     = 0x64;

static const int PS2_CMD_READ_CFG  = 0x20;
static const int PS2_CMD_WRITE_CFG = 0x60;
static const int PS2_CMD_DISABLE_KBD = 0xAD;
static const int PS2_CMD_ENABLE_KBD  = 0xAE;
static const int PS2_CMD_DISABLE_AUX = 0xA7;
static const int PS2_CMD_ENABLE_AUX  = 0xA8;
static const int PS2_CMD_WRITE_AUX   = 0xD4;

static const int PS2_MOUSE_SET_DEFAULTS    = 0xF6;
static const int PS2_MOUSE_ENABLE_REPORTING = 0xF4;
static const int PS2_MOUSE_SET_SAMPLE      = 0xF3;
static const int PS2_MOUSE_READ_ID         = 0xF2;

static const int KBD_BUF_SIZE = 128;
static const int PS2_TIMEOUT  = 1000000;

// ── Extended-key codes stored in the state table (scancode + 128) ──
static const int KEY_UP    = 128 + 0x48;
static const int KEY_DOWN  = 128 + 0x50;
static const int KEY_LEFT  = 128 + 0x4B;
static const int KEY_RIGHT = 128 + 0x4D;
static const int KEY_HOME  = 128 + 0x47;
static const int KEY_END   = 128 + 0x4F;
static const int KEY_PGUP  = 128 + 0x49;
static const int KEY_PGDN  = 128 + 0x51;
static const int KEY_INS   = 128 + 0x52;
static const int KEY_DEL   = 128 + 0x53;

// ── State ──
static int   G_PS2_READY = 0;
static char* G_PS2_KBD_STATE = 0;   // 256 bytes: 1 = key currently held
static char* G_PS2_KBD_BUF   = 0;   // ASCII ring buffer
static int   G_PS2_KBD_HEAD  = 0;
static int   G_PS2_KBD_TAIL  = 0;

static int G_PS2_KBD_EXT   = 0;     // pending 0xE0 prefix
static int G_PS2_KBD_SHIFT = 0;
static int G_PS2_KBD_CTRL  = 0;
static int G_PS2_KBD_ALT   = 0;
static int G_PS2_KBD_CAPS  = 0;

static int G_PS2_MOUSE_X = 512;
static int G_PS2_MOUSE_Y = 384;
static int G_PS2_MOUSE_MAXX = 1023;
static int G_PS2_MOUSE_MAXY = 767;
static int G_PS2_MOUSE_LEFT = 0;
static int G_PS2_MOUSE_RIGHT = 0;
static int G_PS2_MOUSE_MIDDLE = 0;
static int G_PS2_MOUSE_PREV_LEFT = 0;
static int G_PS2_MOUSE_CLICK = 0;
static int G_PS2_MOUSE_CYCLE = 0;   // 0 = expect flags byte, 1/2 = X/Y, 3 = wheel byte
static int G_PS2_MOUSE_WHEELMODE = 0;  // 0 = 3-byte packets, 1 = 4-byte (IntelliMouse)
static int G_PS2_MOUSE_B0 = 0;
static int G_PS2_MOUSE_B1 = 0;
static int G_PS2_MOUSE_B2 = 0;
static int G_PS2_MOUSE_B3 = 0;        // wheel byte (only in 4-byte mode)
static int G_PS2_MOUSE_WHEEL = 0;     // last packet's wheel delta (sign-extended)

// ── Bit test without bitwise operators ──
fn _ps2_bit(int v, int pos) -> int {
    int x = v;
    int i = 0;
    while (i < pos) { x = x / 2; i = i + 1; }
    return x - (x / 2) * 2;
}

// ── Controller primitives ──
fn _ps2_wait_write() -> int {
    int i = 0;
    while (i < PS2_TIMEOUT) {
        int st = port_in8(PS2_STATUS);
        if (_ps2_bit(st, 1) == 0) { return 1; }
        i = i + 1;
    }
    return 0;
}

fn _ps2_wait_read() -> int {
    int i = 0;
    while (i < PS2_TIMEOUT) {
        int st = port_in8(PS2_STATUS);
        if (_ps2_bit(st, 0) == 1) { return 1; }
        i = i + 1;
    }
    return 0;
}

fn _ps2_read() -> int {
    if (_ps2_wait_read() == 0) { return -1; }
    return port_in8(PS2_DATA);
}

fn _ps2_write(int data) -> void {
    _ps2_wait_write();
    port_out8(PS2_DATA, data);
}

fn _ps2_cmd(int cmd) -> void {
    _ps2_wait_write();
    port_out8(PS2_CMD, cmd);
}

fn _ps2_mouse_write(int data) -> void {
    _ps2_cmd(PS2_CMD_WRITE_AUX);
    _ps2_write(data);
}

fn _ps2_flush() -> void {
    int i = 0;
    while (i < 32) {
        int st = port_in8(PS2_STATUS);
        if (_ps2_bit(st, 0) == 0) { return; }
        port_in8(PS2_DATA);
        i = i + 1;
    }
}

// ── Initialisation ──
fn ps2_init() -> int {
    G_PS2_READY = 0;
    if (G_PS2_KBD_STATE == 0) { G_PS2_KBD_STATE = alloc<char>(256); }
    if (G_PS2_KBD_BUF == 0) { G_PS2_KBD_BUF = alloc<char>(KBD_BUF_SIZE); }

    int i = 0;
    while (i < 256) { *(G_PS2_KBD_STATE + i) = 0; i = i + 1; }
    G_PS2_KBD_HEAD = 0; G_PS2_KBD_TAIL = 0;
    G_PS2_KBD_EXT = 0; G_PS2_KBD_SHIFT = 0; G_PS2_KBD_CTRL = 0; G_PS2_KBD_ALT = 0; G_PS2_KBD_CAPS = 0;
    G_PS2_MOUSE_CYCLE = 0; G_PS2_MOUSE_CLICK = 0; G_PS2_MOUSE_PREV_LEFT = 0;
    G_PS2_MOUSE_WHEELMODE = 0; G_PS2_MOUSE_WHEEL = 0; G_PS2_MOUSE_B3 = 0;

    // 1. disable both devices while configuring
    _ps2_cmd(PS2_CMD_DISABLE_KBD);
    _ps2_cmd(PS2_CMD_DISABLE_AUX);
    _ps2_flush();

    // 2. read configuration byte
    _ps2_cmd(PS2_CMD_READ_CFG);
    int cfg = _ps2_read();
    if (cfg < 0) { cfg = 0; }

    // 3. polling mode: clear IRQ1/IRQ12 (bits 0,1); enable clocks (bits 4,5);
    //    enable scancode translation (bit 6) for set 1.
    cfg = cfg - (cfg % 4);
    if (_ps2_bit(cfg, 4) == 1) { cfg = cfg - 16; }
    if (_ps2_bit(cfg, 5) == 1) { cfg = cfg - 32; }
    if (_ps2_bit(cfg, 6) == 0) { cfg = cfg + 64; }

    // 4. write configuration byte back
    _ps2_cmd(PS2_CMD_WRITE_CFG);
    _ps2_write(cfg);

    // 5. re-enable devices
    _ps2_cmd(PS2_CMD_ENABLE_KBD);
    _ps2_cmd(PS2_CMD_ENABLE_AUX);

    // 6. configure the mouse: defaults first (resets the device to 3-byte)
    _ps2_mouse_write(PS2_MOUSE_SET_DEFAULTS);
    _ps2_read();

    // 7. probe for a wheel (IntelliMouse). The sample-rate sequence
    //    200,100,80 is the vendor handshake: a wheel mouse then reports
    //    device ID 3 (IntelliMouse, 4-byte packets) or 4 (Explorer).
    _ps2_mouse_write(PS2_MOUSE_SET_SAMPLE);
    _ps2_read();
    _ps2_mouse_write(200);
    _ps2_read();
    _ps2_mouse_write(PS2_MOUSE_SET_SAMPLE);
    _ps2_read();
    _ps2_mouse_write(100);
    _ps2_read();
    _ps2_mouse_write(PS2_MOUSE_SET_SAMPLE);
    _ps2_read();
    _ps2_mouse_write(80);
    _ps2_read();
    _ps2_mouse_write(PS2_MOUSE_READ_ID);
    _ps2_read();
    int mid = _ps2_read();
    if (mid == 3 || mid == 4) { G_PS2_MOUSE_WHEELMODE = 1; }
    else { G_PS2_MOUSE_WHEELMODE = 0; }

    // 8. enable data reporting, then drop any bytes that queued up so the
    //    first packet we see afterwards starts a clean 3/4-byte frame.
    _ps2_mouse_write(PS2_MOUSE_ENABLE_REPORTING);
    _ps2_read();
    G_PS2_MOUSE_CYCLE = 0;
    _ps2_flush();

    G_PS2_READY = 1;
    return 1;
}

// Supply caller-owned storage instead of allocating. Required on bare
// metal where the allocator (mmap) is unavailable. `state` must be at
// least 256 bytes and `buf` at least KBD_BUF_SIZE bytes.
fn ps2_set_storage(char* state, char* buf) -> void {
    G_PS2_KBD_STATE = state;
    G_PS2_KBD_BUF = buf;
}

fn ps2_ready() -> int { return G_PS2_READY; }

// ── Poll the controller (call this regularly from your main loop) ──
fn ps2_poll() -> void {
    if (G_PS2_READY == 0) { return; }
    int guard = 0;
    while (guard < 64) {
        int st = port_in8(PS2_STATUS);
        if (_ps2_bit(st, 0) == 0) { return; }
        int data = port_in8(PS2_DATA);
        if (_ps2_bit(st, 5) == 1) { _mouse_byte(data); }
        else { _kbd_byte(data); }
        guard = guard + 1;
    }
}

// ── Keyboard ──
fn _kbd_set_state(int key, int val) -> void {
    if (key < 0 || key > 255) { return; }
    *(G_PS2_KBD_STATE + key) = val;
}

fn _kbd_push(int ch) -> void {
    int next = G_PS2_KBD_HEAD + 1;
    if (next >= KBD_BUF_SIZE) { next = 0; }
    if (next == G_PS2_KBD_TAIL) { return; } // buffer full: drop
    *(G_PS2_KBD_BUF + G_PS2_KBD_HEAD) = ch;
    G_PS2_KBD_HEAD = next;
}

fn _kbd_byte(int b) -> void {
    if (b == 0xE0) { G_PS2_KBD_EXT = 1; return; }

    int is_break = _ps2_bit(b, 7);
    int sc = b - (b / 128) * 128; // low 7 bits
    int key = sc;
    if (G_PS2_KBD_EXT == 1) { G_PS2_KBD_EXT = 0; key = 128 + sc; }

    if (is_break == 1) {
        _kbd_set_state(key, 0);
        if (key == 0x2A || key == 0x36) { G_PS2_KBD_SHIFT = 0; }
        if (key == 0x1D || key == 128 + 0x1D) { G_PS2_KBD_CTRL = 0; }
        if (key == 0x38 || key == 128 + 0x38) { G_PS2_KBD_ALT = 0; }
        return;
    }

    _kbd_set_state(key, 1);

    if (key == 0x2A || key == 0x36) { G_PS2_KBD_SHIFT = 1; return; }
    if (key == 0x1D || key == 128 + 0x1D) { G_PS2_KBD_CTRL = 1; return; }
    if (key == 0x38 || key == 128 + 0x38) { G_PS2_KBD_ALT = 1; return; }
    if (key == 0x3A) { G_PS2_KBD_CAPS = 1 - G_PS2_KBD_CAPS; return; }
    if (key >= 128) { return; } // extended navigation keys: state only

    int upper = (G_PS2_KBD_SHIFT + G_PS2_KBD_CAPS) % 2;
    int ch = _kbd_ascii(key, G_PS2_KBD_SHIFT, upper);
    if (ch != 0) { _kbd_push(ch); }
}

fn _kbd_ascii(int sc, int shift, int upper) -> int {
    if (sc == 0x01) { return 27; }
    if (sc == 0x02) { if (shift == 1) { return 33; } return 49; }
    if (sc == 0x03) { if (shift == 1) { return 64; } return 50; }
    if (sc == 0x04) { if (shift == 1) { return 35; } return 51; }
    if (sc == 0x05) { if (shift == 1) { return 36; } return 52; }
    if (sc == 0x06) { if (shift == 1) { return 37; } return 53; }
    if (sc == 0x07) { if (shift == 1) { return 94; } return 54; }
    if (sc == 0x08) { if (shift == 1) { return 38; } return 55; }
    if (sc == 0x09) { if (shift == 1) { return 42; } return 56; }
    if (sc == 0x0A) { if (shift == 1) { return 40; } return 57; }
    if (sc == 0x0B) { if (shift == 1) { return 41; } return 48; }
    if (sc == 0x0C) { if (shift == 1) { return 95; } return 45; }
    if (sc == 0x0D) { if (shift == 1) { return 43; } return 61; }
    if (sc == 0x0E) { return 8; }
    if (sc == 0x0F) { return 9; }
    if (sc == 0x10) { if (upper == 1) { return 81; } return 113; }
    if (sc == 0x11) { if (upper == 1) { return 87; } return 119; }
    if (sc == 0x12) { if (upper == 1) { return 69; } return 101; }
    if (sc == 0x13) { if (upper == 1) { return 82; } return 114; }
    if (sc == 0x14) { if (upper == 1) { return 84; } return 116; }
    if (sc == 0x15) { if (upper == 1) { return 89; } return 121; }
    if (sc == 0x16) { if (upper == 1) { return 85; } return 117; }
    if (sc == 0x17) { if (upper == 1) { return 73; } return 105; }
    if (sc == 0x18) { if (upper == 1) { return 79; } return 111; }
    if (sc == 0x19) { if (upper == 1) { return 80; } return 112; }
    if (sc == 0x1A) { if (shift == 1) { return 123; } return 91; }
    if (sc == 0x1B) { if (shift == 1) { return 125; } return 93; }
    if (sc == 0x1C) { return 10; }
    if (sc == 0x1E) { if (upper == 1) { return 65; } return 97; }
    if (sc == 0x1F) { if (upper == 1) { return 83; } return 115; }
    if (sc == 0x20) { if (upper == 1) { return 68; } return 100; }
    if (sc == 0x21) { if (upper == 1) { return 70; } return 102; }
    if (sc == 0x22) { if (upper == 1) { return 71; } return 103; }
    if (sc == 0x23) { if (upper == 1) { return 72; } return 104; }
    if (sc == 0x24) { if (upper == 1) { return 74; } return 106; }
    if (sc == 0x25) { if (upper == 1) { return 75; } return 107; }
    if (sc == 0x26) { if (upper == 1) { return 76; } return 108; }
    if (sc == 0x27) { if (shift == 1) { return 58; } return 59; }
    if (sc == 0x28) { if (shift == 1) { return 34; } return 39; }
    if (sc == 0x29) { if (shift == 1) { return 126; } return 96; }
    if (sc == 0x2B) { if (shift == 1) { return 124; } return 92; }
    if (sc == 0x2C) { if (upper == 1) { return 90; } return 122; }
    if (sc == 0x2D) { if (upper == 1) { return 88; } return 120; }
    if (sc == 0x2E) { if (upper == 1) { return 67; } return 99; }
    if (sc == 0x2F) { if (upper == 1) { return 86; } return 118; }
    if (sc == 0x30) { if (upper == 1) { return 66; } return 98; }
    if (sc == 0x31) { if (upper == 1) { return 78; } return 110; }
    if (sc == 0x32) { if (upper == 1) { return 77; } return 109; }
    if (sc == 0x33) { if (shift == 1) { return 60; } return 44; }
    if (sc == 0x34) { if (shift == 1) { return 62; } return 46; }
    if (sc == 0x35) { if (shift == 1) { return 63; } return 47; }
    if (sc == 0x39) { return 32; }
    return 0;
}

fn ps2_key_down(int key) -> int {
    if (G_PS2_KBD_STATE == 0 || key < 0 || key > 255) { return 0; }
    return _ps2_bit(*(G_PS2_KBD_STATE + key), 0);
}

fn ps2_shift() -> int { return G_PS2_KBD_SHIFT; }
fn ps2_ctrl()  -> int { return G_PS2_KBD_CTRL; }
fn ps2_alt()   -> int { return G_PS2_KBD_ALT; }
fn ps2_caps()  -> int { return G_PS2_KBD_CAPS; }

fn ps2_kbd_avail() -> int {
    int n = G_PS2_KBD_HEAD - G_PS2_KBD_TAIL;
    if (n < 0) { n = n + KBD_BUF_SIZE; }
    return n;
}

// Returns next ASCII character (0 if none). Handles \n, \t, \b.
fn ps2_getchar() -> int {
    if (G_PS2_KBD_HEAD == G_PS2_KBD_TAIL) { return 0; }
    int ch = *(G_PS2_KBD_BUF + G_PS2_KBD_TAIL);
    int next = G_PS2_KBD_TAIL + 1;
    if (next >= KBD_BUF_SIZE) { next = 0; }
    G_PS2_KBD_TAIL = next;
    return ch;
}

// ── Mouse ──
fn _mouse_byte(int b) -> void {
    if (G_PS2_MOUSE_CYCLE == 0) {
        // Byte 0 of a packet must have the always-1 bit (bit 3) set.
        // If we saw a spurious byte, ignore it and keep waiting for the
        // real flags byte (this is what keeps the stream aligned).
        if (_ps2_bit(b, 3) == 0) { return; }
        G_PS2_MOUSE_B0 = b;
        G_PS2_MOUSE_CYCLE = 1;
        return;
    }
    if (G_PS2_MOUSE_CYCLE == 1) {
        G_PS2_MOUSE_B1 = b;
        G_PS2_MOUSE_CYCLE = 2;
        return;
    }
    if (G_PS2_MOUSE_CYCLE == 2) {
        G_PS2_MOUSE_B2 = b;
        if (G_PS2_MOUSE_WHEELMODE == 1) { G_PS2_MOUSE_CYCLE = 3; return; }
        G_PS2_MOUSE_CYCLE = 0;
        _mouse_process();
        return;
    }
    G_PS2_MOUSE_B3 = b;
    G_PS2_MOUSE_CYCLE = 0;
    _mouse_process();
}

fn _mouse_process() -> void {
    int flags = G_PS2_MOUSE_B0;
    int dx = G_PS2_MOUSE_B1;
    int dy = G_PS2_MOUSE_B2;

    if (_ps2_bit(flags, 4) == 1) { dx = dx - 256; }
    if (_ps2_bit(flags, 5) == 1) { dy = dy - 256; }

    if (_ps2_bit(flags, 6) == 0) { G_PS2_MOUSE_X = G_PS2_MOUSE_X + dx; }
    if (_ps2_bit(flags, 7) == 0) { G_PS2_MOUSE_Y = G_PS2_MOUSE_Y - dy; }

    if (G_PS2_MOUSE_X < 0) { G_PS2_MOUSE_X = 0; }
    if (G_PS2_MOUSE_Y < 0) { G_PS2_MOUSE_Y = 0; }
    if (G_PS2_MOUSE_X > G_PS2_MOUSE_MAXX) { G_PS2_MOUSE_X = G_PS2_MOUSE_MAXX; }
    if (G_PS2_MOUSE_Y > G_PS2_MOUSE_MAXY) { G_PS2_MOUSE_Y = G_PS2_MOUSE_MAXY; }

    // Wheel delta (4-byte mode): byte 4 as a signed 8-bit value.
    int z = G_PS2_MOUSE_B3;
    if (z > 127) { z = z - 256; }
    G_PS2_MOUSE_WHEEL = z;
    if (G_PS2_MOUSE_WHEELMODE == 0) { G_PS2_MOUSE_WHEEL = 0; }

    int left = _ps2_bit(flags, 0);
    if (left == 1 && G_PS2_MOUSE_PREV_LEFT == 0) { G_PS2_MOUSE_CLICK = 1; }
    G_PS2_MOUSE_LEFT = left;
    G_PS2_MOUSE_RIGHT = _ps2_bit(flags, 1);
    G_PS2_MOUSE_MIDDLE = _ps2_bit(flags, 2);
    G_PS2_MOUSE_PREV_LEFT = left;
}

fn ps2_mouse_set_bounds(int w, int h) -> void {
    G_PS2_MOUSE_MAXX = w - 1;
    G_PS2_MOUSE_MAXY = h - 1;
}

fn ps2_mouse_x() -> int { return G_PS2_MOUSE_X; }
fn ps2_mouse_y() -> int { return G_PS2_MOUSE_Y; }
fn ps2_mouse_left() -> int { return G_PS2_MOUSE_LEFT; }
fn ps2_mouse_right() -> int { return G_PS2_MOUSE_RIGHT; }
fn ps2_mouse_middle() -> int { return G_PS2_MOUSE_MIDDLE; }

// Wheel delta from the last packet (+ scroll up, - scroll down). Only
// non-zero when the connected mouse answered the IntelliMouse probe.
fn ps2_mouse_wheel() -> int { return G_PS2_MOUSE_WHEEL; }

fn ps2_mouse_wheel_mode() -> int { return G_PS2_MOUSE_WHEELMODE; }

// Returns 1 once per press edge, then clears.
fn ps2_mouse_clicked() -> int {
    int c = G_PS2_MOUSE_CLICK;
    G_PS2_MOUSE_CLICK = 0;
    return c;
}
