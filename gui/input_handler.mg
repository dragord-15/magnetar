// input_handler.mg -- الوحدة 4: إدخال المستخدم (Input Handling)
// BlackhatOS GUI Core - Keyboard and mouse input via /dev/input/eventN
//
// This module provides:
//   - Opening /dev/input/event0 (keyboard) and /dev/input/event1 (mouse)
//   - Reading Linux input_event structs directly
//   - Mouse position tracking and cursor rendering
//   - Keyboard scancode to ASCII conversion
//   - Non-blocking event polling via O_NONBLOCK
//
// No libc: every syscall is a hand-written trampoline provided by magc.
//
// Linux input_event struct (x86_64):
//   struct input_event {
//       struct timeval time;  // 16 bytes (tv_sec=8, tv_usec=8)
//       __u16 type;           // 2 bytes
//       __u16 code;           // 2 bytes
//       __s32 value;          // 4 bytes
//   };                        // total = 24 bytes

extern fn sys_read(int fd, char* buf, int count) -> int;
extern fn sys_open(char* path, int flags) -> int;
extern fn sys_close(int fd) -> int;
extern fn sys_write(int fd, char* data, int count) -> int;
extern fn sys_mmap(char* addr, int length, int prot, int flags, int fd, int offset) -> int;
extern fn sys_ioctl(int fd, int request, char* arg) -> int;

// External deps
extern fn bval(int v) -> int;
extern fn putb(char* p, int off, int v) -> void;
extern fn getb(char* p, int off) -> int;
extern fn putd(char* p, int off, int v) -> void;
extern fn getd(char* p, int off) -> int;
extern fn getds(char* p, int off) -> int;
extern fn getw(char* p, int off) -> int;
extern fn putq(char* p, int off, int v) -> void;
extern fn getq(char* p, int off) -> int;
extern fn name_len(char* p) -> int;

// from fb_hal.mg
extern fn fb_put_pixel(int x, int y, int color) -> void;
extern fn fb_put_pixel_direct(int x, int y, int color) -> void;
extern fn fb_get_width() -> int;
extern fn fb_get_height() -> int;
extern fn rgb_pack(int r, int g, int b) -> int;

// from gfx_primitives.mg
extern fn draw_line(int x0, int y0, int x1, int y1, int color) -> void;
extern fn draw_filled_rect(int x, int y, int w, int h, int color) -> void;

// ---------------------------------------------------------------------------
// Linux input event types
// ---------------------------------------------------------------------------
// EV_SYN = 0x00  -- Synchronization event
// EV_KEY = 0x01  -- Key/button event
// EV_REL = 0x02  -- Relative movement (mouse)
// EV_ABS = 0x03  -- Absolute movement (touchscreen)
//
// REL_X = 0x00
// REL_Y = 0x01
//
// BTN_LEFT   = 0x110 (272)
// BTN_RIGHT  = 0x111 (273)
// BTN_MIDDLE = 0x112 (274)

// ---------------------------------------------------------------------------
// Globals
// ---------------------------------------------------------------------------
static int g_input_kbd_fd;        // لوحة المفاتيح fd
static int g_input_mouse_fd;      // الماوس fd
static char* g_input_buf;        // مخزن مؤقت لقراءة الأحداث
static char* g_input_probe;      // مخزن مؤقت لاستعلامات ioctl (EVIOCGBIT/EVIOCGABS)
static char* g_input_path;       // مسار مؤقت "/dev/input/eventN"

// Device capability result -- نتيجة فحص قدرات الجهاز
static int g_input_has_kbd;      // 1 = وُجدت لوحة مفاتيح
static int g_input_has_mouse;    // 1 = وُجد ماوس

// Absolute axis range (EVIOCGABS) -- مدى المحاور المطلقة
// VirtualBox reports either 0..(xres-1) or 0..32767 depending on the device,
// so the range is queried instead of hard-coded.
static int g_abs_valid;          // 1 = تم الحصول على المدى من السائق
static int g_abs_x_min;
static int g_abs_x_max;
static int g_abs_y_min;
static int g_abs_y_max;

// Mouse state -- حالة الماوس
static int g_mouse_x;            // إحداثي X للمؤشر
static int g_mouse_y;            // إحداثي Y للمؤشر
static int g_mouse_btn_left;     // زر الأيسر (1=مضغوط)
static int g_mouse_btn_right;    // زر الأيمن
static int g_mouse_btn_middle;   // زر الأوسط
static int g_mouse_clicked;      // تم الضغط (حدث جديد)
static int g_mouse_released;     // تم الإفلات

// Keyboard state -- حالة لوحة المفاتيح
static int g_kbd_key;            // آخر مفتاح تم الضغط عليه (scancode)
static int g_kbd_ascii;          // قيمة ASCII للمفتاح
static int g_kbd_pressed;        // تم ضغط مفتاح جديد
static int g_kbd_shift;          // حالة Shift (1=مضغوط)
static int g_kbd_ctrl;           // حالة Ctrl
static int g_kbd_alt;            // حالة Alt

// Cursor appearance saved region -- المنطقة المحفوظة للمؤشر
static char* g_cursor_save;      // بيانات البكسلات المحفوظة تحت المؤشر
static int g_cursor_save_x;
static int g_cursor_save_y;

// ---------------------------------------------------------------------------
// Linux scancode to ASCII mapping table (US keyboard layout)
// ---------------------------------------------------------------------------
static char* g_scancode_map;      // scancode -> ASCII (128 entries, unshifted)
static char* g_scancode_shift;    // scancode -> ASCII (128 entries, shifted)

fn input_init_scancode_map() -> void {
    g_scancode_map = cast<char*>(sys_mmap(0, 256, 3, 34, -1, 0));
    g_scancode_shift = cast<char*>(sys_mmap(0, 256, 3, 34, -1, 0));

    // Clear all to 0
    int i = 0;
    while (i < 128) {
        putb(g_scancode_map, i, 0);
        putb(g_scancode_shift, i, 0);
        i = i + 1;
    }

    // Number row: scancodes 2-11 -> '1'-'9', '0'
    putb(g_scancode_map, 2, 49);  putb(g_scancode_shift, 2, 33);  // 1 !
    putb(g_scancode_map, 3, 50);  putb(g_scancode_shift, 3, 64);  // 2 @
    putb(g_scancode_map, 4, 51);  putb(g_scancode_shift, 4, 35);  // 3 #
    putb(g_scancode_map, 5, 52);  putb(g_scancode_shift, 5, 36);  // 4 $
    putb(g_scancode_map, 6, 53);  putb(g_scancode_shift, 6, 37);  // 5 %
    putb(g_scancode_map, 7, 54);  putb(g_scancode_shift, 7, 94);  // 6 ^
    putb(g_scancode_map, 8, 55);  putb(g_scancode_shift, 8, 38);  // 7 &
    putb(g_scancode_map, 9, 56);  putb(g_scancode_shift, 9, 42);  // 8 *
    putb(g_scancode_map, 10, 57); putb(g_scancode_shift, 10, 40); // 9 (
    putb(g_scancode_map, 11, 48); putb(g_scancode_shift, 11, 41); // 0 )

    // Punctuation near numbers
    putb(g_scancode_map, 12, 45);  putb(g_scancode_shift, 12, 95);  // - _
    putb(g_scancode_map, 13, 61);  putb(g_scancode_shift, 13, 43);  // = +
    putb(g_scancode_map, 14, 8);   putb(g_scancode_shift, 14, 8);   // Backspace

    // Tab
    putb(g_scancode_map, 15, 9);   putb(g_scancode_shift, 15, 9);   // Tab

    // QWERTY row: scancodes 16-27
    putb(g_scancode_map, 16, 113); putb(g_scancode_shift, 16, 81);  // q Q
    putb(g_scancode_map, 17, 119); putb(g_scancode_shift, 17, 87);  // w W
    putb(g_scancode_map, 18, 101); putb(g_scancode_shift, 18, 69);  // e E
    putb(g_scancode_map, 19, 114); putb(g_scancode_shift, 19, 82);  // r R
    putb(g_scancode_map, 20, 116); putb(g_scancode_shift, 20, 84);  // t T
    putb(g_scancode_map, 21, 121); putb(g_scancode_shift, 21, 89);  // y Y
    putb(g_scancode_map, 22, 117); putb(g_scancode_shift, 22, 85);  // u U
    putb(g_scancode_map, 23, 105); putb(g_scancode_shift, 23, 73);  // i I
    putb(g_scancode_map, 24, 111); putb(g_scancode_shift, 24, 79);  // o O
    putb(g_scancode_map, 25, 112); putb(g_scancode_shift, 25, 80);  // p P
    putb(g_scancode_map, 26, 91);  putb(g_scancode_shift, 26, 123); // [ {
    putb(g_scancode_map, 27, 93);  putb(g_scancode_shift, 27, 125); // ] }

    // Enter
    putb(g_scancode_map, 28, 10);  putb(g_scancode_shift, 28, 10);  // Enter

    // ASDF row: scancodes 30-41
    putb(g_scancode_map, 30, 97);  putb(g_scancode_shift, 30, 65);  // a A
    putb(g_scancode_map, 31, 115); putb(g_scancode_shift, 31, 83);  // s S
    putb(g_scancode_map, 32, 100); putb(g_scancode_shift, 32, 68);  // d D
    putb(g_scancode_map, 33, 102); putb(g_scancode_shift, 33, 70);  // f F
    putb(g_scancode_map, 34, 103); putb(g_scancode_shift, 34, 71);  // g G
    putb(g_scancode_map, 35, 104); putb(g_scancode_shift, 35, 72);  // h H
    putb(g_scancode_map, 36, 106); putb(g_scancode_shift, 36, 74);  // j J
    putb(g_scancode_map, 37, 107); putb(g_scancode_shift, 37, 75);  // k K
    putb(g_scancode_map, 38, 108); putb(g_scancode_shift, 38, 76);  // l L
    putb(g_scancode_map, 39, 59);  putb(g_scancode_shift, 39, 58);  // ; :
    putb(g_scancode_map, 40, 39);  putb(g_scancode_shift, 40, 34);  // ' "
    putb(g_scancode_map, 41, 96);  putb(g_scancode_shift, 41, 126); // ` ~

    // Backslash
    putb(g_scancode_map, 43, 92);  putb(g_scancode_shift, 43, 124); // \ |

    // ZXCV row: scancodes 44-53
    putb(g_scancode_map, 44, 122); putb(g_scancode_shift, 44, 90);  // z Z
    putb(g_scancode_map, 45, 120); putb(g_scancode_shift, 45, 88);  // x X
    putb(g_scancode_map, 46, 99);  putb(g_scancode_shift, 46, 67);  // c C
    putb(g_scancode_map, 47, 118); putb(g_scancode_shift, 47, 86);  // v V
    putb(g_scancode_map, 48, 98);  putb(g_scancode_shift, 48, 66);  // b B
    putb(g_scancode_map, 49, 110); putb(g_scancode_shift, 49, 78);  // n N
    putb(g_scancode_map, 50, 109); putb(g_scancode_shift, 50, 77);  // m M
    putb(g_scancode_map, 51, 44);  putb(g_scancode_shift, 51, 60);  // , <
    putb(g_scancode_map, 52, 46);  putb(g_scancode_shift, 52, 62);  // . >
    putb(g_scancode_map, 53, 47);  putb(g_scancode_shift, 53, 63);  // / ?

    // Space
    putb(g_scancode_map, 57, 32);  putb(g_scancode_shift, 57, 32);  // Space

    // Special keys (mapped to high ASCII for identification)
    // We use values > 127 internally but store as-is
    // Escape = scancode 1
    putb(g_scancode_map, 1, 27);   putb(g_scancode_shift, 1, 27);   // ESC
}

// ---------------------------------------------------------------------------
// Device capability probing -- فحص قدرات أجهزة الإدخال
//
// Opening /dev/input/event0 blindly and treating it as "the keyboard" is
// wrong: on a real machine event0 is often the power button or a lid switch,
// and grabbing it means the kernel stops delivering ACPI power events.  It
// also makes us read BTN_POWER/EV_SW as regular keys.
//
// So every device is asked what it actually emits via EVIOCGBIT, and only
// devices that look like a real keyboard / mouse / tablet are opened.
// ---------------------------------------------------------------------------

// EVIOCGBIT(ev, len) = _IOC(_IOC_READ(2), 'E'(0x45), 0x20 + ev, len)
fn input_evioctl(int ev_type, int nbytes) -> int {
    return 0x80000000 | (nbytes * 65536) | (0x45 * 256) | (0x20 + ev_type);
}

// EVIOCGABS(axis) = _IOC(_IOC_READ, 'E', 0x40 + axis, sizeof(input_absinfo)=24)
fn input_absioctl(int axis) -> int {
    return 0x80000000 | (24 * 65536) | (0x45 * 256) | (0x40 + axis);
}

// bit_test -- هل مضيء bit رقم n في مصفوفة القدرات؟
fn input_bit_test(char* bits, int n) -> int {
    int bv = getb(bits, n / 8);
    int mask = 1;
    int i = n % 8;
    while (i > 0) { mask = mask * 2; i = i - 1; }
    if ((bv / mask) % 2 == 1) { return 1; }
    return 0;
}

// input_has_capability -- هل يعلن الجهاز عن الحدث ev_type؟
fn input_has_capability(int fd, int ev_type) -> int {
    if (sys_ioctl(fd, input_evioctl(0, 16), g_input_probe) < 0) { return 0; }
    return input_bit_test(g_input_probe, ev_type);
}

// input_is_keyboard -- لوحة مفاتيح حقيقية؟ (يملك EV_KEY + KEY_A، وليس فقط أزرار)
fn input_is_keyboard(int fd) -> int {
    if (input_has_capability(fd, 1) == 0) { return 0; } // no EV_KEY
    if (sys_ioctl(fd, input_evioctl(1, 128), g_input_probe) < 0) { return 0; }
    if (input_bit_test(g_input_probe, 30) == 0) { return 0; } // KEY_A absent
    return 1;
}

// input_is_pointer -- ماوس/لقطة/لوحة لمس؟ (EV_REL أو EV_ABS أو BTN_LEFT)
fn input_is_pointer(int fd) -> int {
    if (input_has_capability(fd, 2) == 1) { return 1; } // EV_REL (wheel/rel move)
    if (input_has_capability(fd, 3) == 1) { return 1; } // EV_ABS (tablet/touch)
    if (input_has_capability(fd, 1) == 1) {
        if (sys_ioctl(fd, input_evioctl(1, 128), g_input_probe) >= 0) {
            if (input_bit_test(g_input_probe, 272) == 1) { return 1; } // BTN_LEFT
        }
    }
    return 0;
}

// input_query_abs_range -- اقرأ مدى المحور المطلق (EVIOCGABS)
// Fills g_abs_x_min/max, g_abs_y_min/max; sets g_abs_valid=1 on success.
fn input_query_abs_range(int fd) -> void {
    g_abs_valid = 0;
    if (sys_ioctl(fd, input_absioctl(0), g_input_probe) < 0) { return; } // ABS_X
    int xmin = getds(g_input_probe, 4);
    int xmax = getds(g_input_probe, 8);
    if (sys_ioctl(fd, input_absioctl(1), g_input_probe) < 0) { return; } // ABS_Y
    int ymin = getds(g_input_probe, 4);
    int ymax = getds(g_input_probe, 8);
    if (xmax <= xmin) { return; }
    if (ymax <= ymin) { return; }
    g_abs_x_min = xmin; g_abs_x_max = xmax;
    g_abs_y_min = ymin; g_abs_y_max = ymax;
    g_abs_valid = 1;
}

// input_event_path -- ابنِ "/dev/input/eventN" في g_input_path
fn input_event_path(int n) -> char* {
    char* p = g_input_path;
    putb(p, 0, 47);  putb(p, 1, 100); putb(p, 2, 101); putb(p, 3, 118); // /dev
    putb(p, 4, 47);  putb(p, 5, 105); putb(p, 6, 110); putb(p, 7, 112); // inp
    putb(p, 8, 117); putb(p, 9, 116); putb(p, 10, 47);                  // ut/
    putb(p, 11, 101); putb(p, 12, 118); putb(p, 13, 101); putb(p, 14, 110); // even
    putb(p, 15, 116);                                                  // t
    putb(p, 16, 48 + n);                                               // 0..7
    putb(p, 17, 0);
    return p;
}

// input_open_devices -- افتح أجهزة الإدخال الصحيحة عبر فحص القدرات
// Scans /dev/input/event0..event7, keeps the first keyboard-looking device
// and the first pointer-looking device, closes everything else.
fn input_open_devices() -> void {
    g_input_kbd_fd = -1;
    g_input_mouse_fd = -1;
    g_input_has_kbd = 0;
    g_input_has_mouse = 0;

    int i = 0;
    while (i < 8) {
        int fd = sys_open(input_event_path(i), 0x800); // O_RDONLY|O_NONBLOCK
        if (fd >= 0) {
            if ((g_input_kbd_fd < 0) && (input_is_keyboard(fd) == 1)) {
                g_input_kbd_fd = fd;
                g_input_has_kbd = 1;
                sys_write(2, "input: keyboard on ", 19);
                sys_write(2, input_event_path(i), 18);
                sys_write(2, "\n", 1);
            } else {
                if ((g_input_mouse_fd < 0) && (input_is_pointer(fd) == 1)) {
                    g_input_mouse_fd = fd;
                    g_input_has_mouse = 1;
                    sys_write(2, "input: pointer on ", 18);
                    sys_write(2, input_event_path(i), 18);
                    sys_write(2, "\n", 1);
                    input_query_abs_range(fd); // لوحة مطلقة؟ اقرأ المدى
                } else {
                    sys_close(fd); // جهاز غير مفيد (زر الطاقة، ...)
                }
            }
        }
        i = i + 1;
    }

    if ((g_input_has_kbd == 0) && (g_input_has_mouse == 0)) {
        sys_write(2, "input: no /dev/input/event* devices\n", 36);
    }
}

// ---------------------------------------------------------------------------
// input_init -- تهيئة وحدة الإدخال
// Open keyboard and mouse event devices. Non-blocking.
// Returns 0 on success, -1 on failure.
// ---------------------------------------------------------------------------
fn input_init() -> int {
    g_input_buf = cast<char*>(sys_mmap(0, 4096, 3, 34, -1, 0));
    g_cursor_save = cast<char*>(sys_mmap(0, 4096, 3, 34, -1, 0));
    g_input_probe = cast<char*>(sys_mmap(0, 4096, 3, 34, -1, 0));
    g_input_path = cast<char*>(sys_mmap(0, 4096, 3, 34, -1, 0));

    // Initialize scancode map
    input_init_scancode_map();

    // Initialize mouse state -- تهيئة حالة الماوس
    g_mouse_x = fb_get_width() / 2;
    g_mouse_y = fb_get_height() / 2;
    g_mouse_btn_left = 0;
    g_mouse_btn_right = 0;
    g_mouse_btn_middle = 0;
    g_mouse_clicked = 0;
    g_mouse_released = 0;

    // Initialize keyboard state
    g_kbd_key = 0;
    g_kbd_ascii = 0;
    g_kbd_pressed = 0;
    g_kbd_shift = 0;
    g_kbd_ctrl = 0;
    g_kbd_alt = 0;

    g_cursor_save_x = -1;
    g_cursor_save_y = -1;

    g_abs_valid = 0;

    // Scan /dev/input/event* and keep only real keyboard/pointer devices.
    input_open_devices();

    // At least one should work
    if ((g_input_kbd_fd < 0) && (g_input_mouse_fd < 0)) {
        return -1;
    }

    return 0;
}

// ---------------------------------------------------------------------------
// input_kbd_available / input_mouse_available -- هل يوجد جهاز فعلي؟
// ---------------------------------------------------------------------------
fn input_kbd_available() -> int { return g_input_has_kbd; }
fn input_mouse_available() -> int { return g_input_has_mouse; }
fn input_abs_valid() -> int { return g_abs_valid; }

// ---------------------------------------------------------------------------
// input_process_event -- معالجة حدث واحد
// Process a single input_event from a buffer.
// ---------------------------------------------------------------------------
fn input_process_event(char* ev) -> void {
    // input_event layout on x86_64:
    //   0-15: struct timeval (16 bytes)
    //   16-17: __u16 type
    //   18-19: __u16 code
    //   20-23: __s32 value
    int type = getw(ev, 16);
    int code = getw(ev, 18);
    int value = getds(ev, 20);

    // EV_KEY = 1 -- أحداث المفاتيح والأزرار
    if (type == 1) {
        // Mouse buttons
        if (code == 272) { // BTN_LEFT
            if (value == 1) {
                g_mouse_btn_left = 1;
                g_mouse_clicked = 1;
            }
            if (value == 0) {
                g_mouse_btn_left = 0;
                g_mouse_released = 1;
            }
            return;
        }
        if (code == 273) { // BTN_RIGHT
            if (value == 1) { g_mouse_btn_right = 1; }
            if (value == 0) { g_mouse_btn_right = 0; }
            return;
        }
        if (code == 274) { // BTN_MIDDLE
            if (value == 1) { g_mouse_btn_middle = 1; }
            if (value == 0) { g_mouse_btn_middle = 0; }
            return;
        }

        // Modifier keys -- مفاتيح التعديل
        // value 0=release, 1=press, 2=autorepeat.  Normalize to 1/0 so a
        // stuck-shift state can never leak in from a repeat event.
        if ((code == 42) || (code == 54)) { // Left/Right Shift
            if (value == 0) { g_kbd_shift = 0; } else { g_kbd_shift = 1; }
            return;
        }
        if ((code == 29) || (code == 97)) { // Left/Right Ctrl
            if (value == 0) { g_kbd_ctrl = 0; } else { g_kbd_ctrl = 1; }
            return;
        }
        if ((code == 56) || (code == 100)) { // Left/Right Alt
            if (value == 0) { g_kbd_alt = 0; } else { g_kbd_alt = 1; }
            return;
        }

        // Regular key press -- ضغط مفتاح عادي
        // value 1 = press, value 2 = autorepeat (treat as another press so
        // holding a key in a text field keeps typing).
        if ((value == 1) || (value == 2)) {
            g_kbd_key = code;
            g_kbd_pressed = 1;
            // Convert scancode to ASCII
            if (code < 128) {
                if (g_kbd_shift == 1) {
                    g_kbd_ascii = getb(g_scancode_shift, code);
                } else {
                    g_kbd_ascii = getb(g_scancode_map, code);
                }
            } else {
                g_kbd_ascii = 0;
            }
        }
    }

    // EV_REL = 2 -- حركة الماوس النسبية
    if (type == 2) {
        if (code == 0) { // REL_X
            g_mouse_x = g_mouse_x + value;
            // Clamp -- تقييد
            if (g_mouse_x < 0) { g_mouse_x = 0; }
            if (g_mouse_x >= fb_get_width()) { g_mouse_x = fb_get_width() - 1; }
        }
        if (code == 1) { // REL_Y
            g_mouse_y = g_mouse_y + value;
            if (g_mouse_y < 0) { g_mouse_y = 0; }
            if (g_mouse_y >= fb_get_height()) { g_mouse_y = fb_get_height() - 1; }
        }
    }

    // EV_ABS = 3 -- حركة الماوس المطلقة (VirtualBox tablet mode)
    // Scale using the range reported by EVIOCGABS when we got one; the
    // VirtualBox tablet is NOT always 0..32767 (guest-resolution is common).
    if (type == 3) {
        if (code == 0) { // ABS_X
            if (g_abs_valid == 1) {
                g_mouse_x = (value - g_abs_x_min) * fb_get_width()
                          / (g_abs_x_max - g_abs_x_min + 1);
            } else {
                g_mouse_x = value * fb_get_width() / 32768;
            }
            if (g_mouse_x < 0) { g_mouse_x = 0; }
            if (g_mouse_x >= fb_get_width()) { g_mouse_x = fb_get_width() - 1; }
        }
        if (code == 1) { // ABS_Y
            if (g_abs_valid == 1) {
                g_mouse_y = (value - g_abs_y_min) * fb_get_height()
                          / (g_abs_y_max - g_abs_y_min + 1);
            } else {
                g_mouse_y = value * fb_get_height() / 32768;
            }
            if (g_mouse_y < 0) { g_mouse_y = 0; }
            if (g_mouse_y >= fb_get_height()) { g_mouse_y = fb_get_height() - 1; }
        }
    }
}

// ---------------------------------------------------------------------------
// input_poll -- استطلاع الأحداث (non-blocking)
// Poll for input events from both keyboard and mouse.
// Call this once per frame in the event loop.
// ---------------------------------------------------------------------------
fn input_poll() -> void {
    // Reset per-frame state
    g_mouse_clicked = 0;
    g_mouse_released = 0;
    g_kbd_pressed = 0;
    g_kbd_key = 0;
    g_kbd_ascii = 0;

    // Read keyboard events -- قراءة أحداث لوحة المفاتيح
    if (g_input_kbd_fd >= 0) {
        int n = sys_read(g_input_kbd_fd, g_input_buf, 4096);
        if (n > 0) {
            int off = 0;
            while (off + 24 <= n) {
                input_process_event(g_input_buf + off);
                off = off + 24;
            }
        }
    }

    // Read mouse events -- قراءة أحداث الماوس
    if (g_input_mouse_fd >= 0) {
        int n = sys_read(g_input_mouse_fd, g_input_buf, 4096);
        if (n > 0) {
            int off = 0;
            while (off + 24 <= n) {
                input_process_event(g_input_buf + off);
                off = off + 24;
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Mouse state getters -- دوال الحصول على حالة الماوس
// ---------------------------------------------------------------------------
fn input_mouse_x() -> int { return g_mouse_x; }
fn input_mouse_y() -> int { return g_mouse_y; }
fn input_mouse_left() -> int { return g_mouse_btn_left; }
fn input_mouse_right() -> int { return g_mouse_btn_right; }
fn input_mouse_clicked() -> int { return g_mouse_clicked; }
fn input_mouse_released() -> int { return g_mouse_released; }

// ---------------------------------------------------------------------------
// Keyboard state getters -- دوال الحصول على حالة لوحة المفاتيح
// ---------------------------------------------------------------------------
fn input_kbd_key() -> int { return g_kbd_key; }
fn input_kbd_ascii() -> int { return g_kbd_ascii; }
fn input_kbd_pressed() -> int { return g_kbd_pressed; }
fn input_kbd_shift() -> int { return g_kbd_shift; }
fn input_kbd_ctrl() -> int { return g_kbd_ctrl; }
fn input_kbd_alt() -> int { return g_kbd_alt; }

// ---------------------------------------------------------------------------
// Scancode constants for special keys
// ---------------------------------------------------------------------------
// KEY_ESC = 1
// KEY_BACKSPACE = 14
// KEY_TAB = 15
// KEY_ENTER = 28
// KEY_UP = 103
// KEY_DOWN = 108
// KEY_LEFT = 105
// KEY_RIGHT = 106
// KEY_DELETE = 111
// KEY_HOME = 102
// KEY_END = 107

// ---------------------------------------------------------------------------
// input_draw_cursor -- رسم مؤشر الماوس
// Draw a simple arrow cursor at the current mouse position.
// This draws directly to the framebuffer (not the backbuffer)
// to avoid flicker.
// ---------------------------------------------------------------------------
fn input_draw_cursor() -> void {
    int mx = g_mouse_x;
    int my = g_mouse_y;

    // Arrow cursor pattern (12x16 pixels) -- شكل سهم المؤشر
    int white = rgb_pack(255, 255, 255);
    int black = rgb_pack(0, 0, 0);

    // Outline (black border) -- الحدود السوداء
    // Row 0
    fb_put_pixel(mx, my, black);
    // Row 1
    fb_put_pixel(mx, my + 1, black);
    fb_put_pixel(mx + 1, my + 1, black);
    // Row 2
    fb_put_pixel(mx, my + 2, black);
    fb_put_pixel(mx + 1, my + 2, white);
    fb_put_pixel(mx + 2, my + 2, black);
    // Row 3
    fb_put_pixel(mx, my + 3, black);
    fb_put_pixel(mx + 1, my + 3, white);
    fb_put_pixel(mx + 2, my + 3, white);
    fb_put_pixel(mx + 3, my + 3, black);
    // Row 4
    fb_put_pixel(mx, my + 4, black);
    fb_put_pixel(mx + 1, my + 4, white);
    fb_put_pixel(mx + 2, my + 4, white);
    fb_put_pixel(mx + 3, my + 4, white);
    fb_put_pixel(mx + 4, my + 4, black);
    // Row 5
    fb_put_pixel(mx, my + 5, black);
    fb_put_pixel(mx + 1, my + 5, white);
    fb_put_pixel(mx + 2, my + 5, white);
    fb_put_pixel(mx + 3, my + 5, white);
    fb_put_pixel(mx + 4, my + 5, white);
    fb_put_pixel(mx + 5, my + 5, black);
    // Row 6
    fb_put_pixel(mx, my + 6, black);
    fb_put_pixel(mx + 1, my + 6, white);
    fb_put_pixel(mx + 2, my + 6, white);
    fb_put_pixel(mx + 3, my + 6, white);
    fb_put_pixel(mx + 4, my + 6, white);
    fb_put_pixel(mx + 5, my + 6, white);
    fb_put_pixel(mx + 6, my + 6, black);
    // Row 7
    fb_put_pixel(mx, my + 7, black);
    fb_put_pixel(mx + 1, my + 7, white);
    fb_put_pixel(mx + 2, my + 7, white);
    fb_put_pixel(mx + 3, my + 7, white);
    fb_put_pixel(mx + 4, my + 7, white);
    fb_put_pixel(mx + 5, my + 7, white);
    fb_put_pixel(mx + 6, my + 7, white);
    fb_put_pixel(mx + 7, my + 7, black);
    // Row 8
    fb_put_pixel(mx, my + 8, black);
    fb_put_pixel(mx + 1, my + 8, white);
    fb_put_pixel(mx + 2, my + 8, white);
    fb_put_pixel(mx + 3, my + 8, white);
    fb_put_pixel(mx + 4, my + 8, white);
    fb_put_pixel(mx + 5, my + 8, white);
    fb_put_pixel(mx + 6, my + 8, white);
    fb_put_pixel(mx + 7, my + 8, white);
    fb_put_pixel(mx + 8, my + 8, black);
    // Row 9
    fb_put_pixel(mx, my + 9, black);
    fb_put_pixel(mx + 1, my + 9, white);
    fb_put_pixel(mx + 2, my + 9, white);
    fb_put_pixel(mx + 3, my + 9, white);
    fb_put_pixel(mx + 4, my + 9, white);
    fb_put_pixel(mx + 5, my + 9, white);
    fb_put_pixel(mx + 6, my + 9, black);
    fb_put_pixel(mx + 7, my + 9, black);
    fb_put_pixel(mx + 8, my + 9, black);
    // Row 10
    fb_put_pixel(mx, my + 10, black);
    fb_put_pixel(mx + 1, my + 10, white);
    fb_put_pixel(mx + 2, my + 10, white);
    fb_put_pixel(mx + 3, my + 10, black);
    fb_put_pixel(mx + 4, my + 10, white);
    fb_put_pixel(mx + 5, my + 10, white);
    fb_put_pixel(mx + 6, my + 10, black);
    // Row 11
    fb_put_pixel(mx, my + 11, black);
    fb_put_pixel(mx + 1, my + 11, white);
    fb_put_pixel(mx + 2, my + 11, black);
    fb_put_pixel(mx + 3, my + 11, black);
    fb_put_pixel(mx + 4, my + 11, black);
    fb_put_pixel(mx + 5, my + 11, white);
    fb_put_pixel(mx + 6, my + 11, white);
    fb_put_pixel(mx + 7, my + 11, black);
    // Row 12
    fb_put_pixel(mx, my + 12, black);
    fb_put_pixel(mx + 1, my + 12, black);
    fb_put_pixel(mx + 4, my + 12, black);
    fb_put_pixel(mx + 5, my + 12, white);
    fb_put_pixel(mx + 6, my + 12, white);
    fb_put_pixel(mx + 7, my + 12, black);
    // Row 13
    fb_put_pixel(mx + 5, my + 13, black);
    fb_put_pixel(mx + 6, my + 13, black);
    fb_put_pixel(mx + 7, my + 13, black);
}

// ---------------------------------------------------------------------------
// input_close -- إغلاق أجهزة الإدخال
// ---------------------------------------------------------------------------
fn input_close() -> void {
    if (g_input_kbd_fd >= 0) { sys_close(g_input_kbd_fd); }
    if (g_input_mouse_fd >= 0) { sys_close(g_input_mouse_fd); }
}
