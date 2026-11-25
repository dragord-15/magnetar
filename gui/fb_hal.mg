// fb_hal.mg -- الوحدة 1: طبقة العتاد (Hardware Abstraction Layer)
// BlackhatOS GUI Core - Framebuffer direct access layer
//
// This module provides the lowest-level interface to /dev/fb0:
//   - open the framebuffer and query screen geometry via ioctl
//   - mmap the framebuffer memory for direct pixel writes
//   - draw individual pixels with RGB color support (16/24/32 bpp)
//   - clear the entire screen
//   - double-buffering support via a shadow backbuffer
//
// No libc: every syscall is a hand-written trampoline provided by magc.

extern fn sys_write(int fd, char* data, int count) -> int;
extern fn sys_read(int fd, char* buf, int count) -> int;
extern fn sys_open(char* path, int flags) -> int;
extern fn sys_close(int fd) -> int;
extern fn sys_mmap(char* addr, int length, int prot, int flags, int fd, int offset) -> int;
extern fn sys_ioctl(int fd, int request, char* arg) -> int;
extern fn sys_exit_group(int code) -> int;

// ---------------------------------------------------------------------------
// byte helpers (same as blackhat-init.mg for consistency)
// ---------------------------------------------------------------------------
fn bval(int v) -> int {
    int b = v - (v / 256) * 256;
    if (b < 0) { b = b + 256; }
    return b;
}

fn putb(char* p, int off, int v) -> void {
    *(p + off) = bval(v);
}

fn getb(char* p, int off) -> int {
    return bval(*(p + off));
}

fn putw(char* p, int off, int v) -> void {
    putb(p, off, bval(v));
    putb(p, off + 1, bval(v / 256));
}

fn getw(char* p, int off) -> int {
    return getb(p, off) + getb(p, off + 1) * 256;
}

fn putd(char* p, int off, int v) -> void {
    putb(p, off, bval(v));
    putb(p, off + 1, bval(v / 256));
    putb(p, off + 2, bval(v / 65536));
    putb(p, off + 3, bval(v / 16777216));
}

fn getd(char* p, int off) -> int {
    return getb(p, off) + getb(p, off + 1) * 256 + getb(p, off + 2) * 65536 + getb(p, off + 3) * 16777216;
}

// getds -- same as getd but sign-extends a 32-bit two's-complement value.
// Needed for anything that stores __s32 (input_event.value, absinfo min/max).
fn getds(char* p, int off) -> int {
    int v = getd(p, off);
    if (v >= 2147483648) { v = v - 4294967296; }
    return v;
}

fn putq(char* p, int off, int v) -> void {
    int q = v;
    int i = 0;
    while (i < 8) {
        putb(p, off + i, bval(q));
        q = q / 256;
        i = i + 1;
    }
}

fn getq(char* p, int off) -> int {
    int v = 0;
    int mul = 1;
    int i = 0;
    while (i < 8) {
        v = v + bval(*(p + off + i)) * mul;
        mul = mul * 256;
        i = i + 1;
    }
    return v;
}

fn name_len(char* p) -> int {
    int n = 0;
    while (bval(*(p + n)) != 0) { n = n + 1; }
    return n;
}

// ---------------------------------------------------------------------------
// Framebuffer state globals
// ---------------------------------------------------------------------------
// Screen geometry
static int g_fb_fd;          // file descriptor for /dev/fb0
static int g_fb_width;       // screen width in pixels
static int g_fb_height;      // screen height in pixels
static int g_fb_bpp;         // bits per pixel (16, 24, or 32)
static int g_fb_stride;      // bytes per scanline (line_length)
static int g_fb_size;        // total framebuffer size in bytes
static char* g_fb_mem;       // mmap'd framebuffer memory
static char* g_fb_back;      // backbuffer for double-buffering (مخزن مؤقت لتجنب الوميض)

// Color channel offsets + lengths from fb_var_screeninfo
// (offset 32/44/56 hold .offset, offset 36/48/60 hold .length)
static int g_fb_red_off;     // red channel bit offset
static int g_fb_green_off;   // green channel bit offset
static int g_fb_blue_off;    // blue channel bit offset
static int g_fb_red_len;     // red channel bit length (5 for RGB565, 8 otherwise)
static int g_fb_green_len;   // green channel bit length
static int g_fb_blue_len;    // blue channel bit length

// IOCTL constants for Linux framebuffer
// FBIOGET_VSCREENINFO = 0x4600
// FBIOGET_FSCREENINFO = 0x4602

// ---------------------------------------------------------------------------
// fb_init -- فتح الفريم بفر وقراءة معلومات الشاشة
// Open /dev/fb0, query screen info via ioctl, mmap the memory.
// Returns 0 on success, -1 on failure.
// ---------------------------------------------------------------------------
fn fb_init() -> int {
    // Open framebuffer device
    g_fb_fd = sys_open("/dev/fb0", 2); // O_RDWR = 2
    if (g_fb_fd < 0) {
        sys_write(2, "fb_hal: cannot open /dev/fb0\n", 29);
        return -1;
    }

    // Allocate buffers for ioctl structs
    // fb_var_screeninfo is 160 bytes, fb_fix_screeninfo is 68 bytes
    char* vinfo = cast<char*>(sys_mmap(0, 4096, 3, 34, -1, 0));
    char* finfo = cast<char*>(sys_mmap(0, 4096, 3, 34, -1, 0));

    // FBIOGET_VSCREENINFO = 0x4600
    if (sys_ioctl(g_fb_fd, 0x4600, vinfo) < 0) {
        sys_write(2, "fb_hal: FBIOGET_VSCREENINFO failed\n", 35);
        sys_close(g_fb_fd);
        return -1;
    }

    // FBIOGET_FSCREENINFO = 0x4602
    if (sys_ioctl(g_fb_fd, 0x4602, finfo) < 0) {
        sys_write(2, "fb_hal: FBIOGET_FSCREENINFO failed\n", 35);
        sys_close(g_fb_fd);
        return -1;
    }

    // Parse fb_var_screeninfo (struct layout for x86_64):
    //   offset  0: __u32 xres
    //   offset  4: __u32 yres
    //   offset  8: __u32 xres_virtual
    //   offset 12: __u32 yres_virtual
    //   offset 16: __u32 xoffset
    //   offset 20: __u32 yoffset
    //   offset 24: __u32 bits_per_pixel
    //   ...
    //   offset 32: struct fb_bitfield red   { offset(32), length(36), msb_right(40) }
    //   offset 44: struct fb_bitfield green { offset(44), length(48), msb_right(52) }
    //   offset 56: struct fb_bitfield blue  { offset(56), length(60), msb_right(64) }
    g_fb_width = getd(vinfo, 0);
    g_fb_height = getd(vinfo, 4);
    g_fb_bpp = getd(vinfo, 24);

    // Color channel offsets + lengths
    g_fb_red_off = getd(vinfo, 32);
    g_fb_green_off = getd(vinfo, 44);
    g_fb_blue_off = getd(vinfo, 56);
    g_fb_red_len = getd(vinfo, 36);
    g_fb_green_len = getd(vinfo, 48);
    g_fb_blue_len = getd(vinfo, 60);

    // Some drivers leave the bitfield lengths zeroed; fall back to the layout
    // that the bpp implies so rgb_pack still produces usable colors.
    if ((g_fb_red_len == 0) && (g_fb_green_len == 0) && (g_fb_blue_len == 0)) {
        if (g_fb_bpp == 16) {
            g_fb_red_len = 5;
            g_fb_green_len = 6;
            g_fb_blue_len = 5;
        } else {
            g_fb_red_len = 8;
            g_fb_green_len = 8;
            g_fb_blue_len = 8;
        }
    }

    // Parse fb_fix_screeninfo:
    //   offset  0: char id[16]
    //   offset 16: unsigned long smem_start (8 bytes on x86_64)
    //   offset 24: __u32 smem_len
    //   offset 28: __u32 type
    //   offset 32: __u32 type_aux
    //   offset 36: __u32 visual
    //   offset 40: __u16 xpanstep
    //   offset 42: __u16 ypanstep
    //   offset 44: __u16 ywrapstep
    //   offset 46: (2 bytes compiler padding - the struct is 4-aligned)
    //   offset 48: __u32 line_length   <-- هذا هو stride
    //   offset 52: (4 bytes padding - mmio_start is 8-aligned at 56)
    //
    // NOTE: an earlier revision read offset 52, which is padding and always
    // reads as 0 -> stride 0 -> mmap(0) fails.  Verified against the kernel
    // ABI with ctypes on this host (line_length @48).
    g_fb_stride = getd(finfo, 48);
    if (g_fb_stride == 0) {
        // Defensive fallback: stride = width * bpp/8 when the driver lied.
        g_fb_stride = (g_fb_width * g_fb_bpp) / 8;
    }
    g_fb_size = g_fb_stride * g_fb_height;

    // mmap the framebuffer -- الربط المباشر للذاكرة
    // PROT_READ|PROT_WRITE = 3, MAP_SHARED = 1
    //
    // NOTE: do NOT test the result with `cast<int>(ptr) < 0`.  mmap returns a
    // 64-bit address in the 0x7f.. range; truncating it to 32 bits makes it
    // look negative, which used to silently disable the backbuffer and make
    // every "backbuffer" draw land on the real screen.  mmap signals failure
    // with -1; compare the raw value instead (see fb_mmap_failed below).
    g_fb_mem = cast<char*>(sys_mmap(0, g_fb_size, 3, 1, g_fb_fd, 0));
    if (fb_mmap_failed(g_fb_mem) == 1) {
        sys_write(2, "fb_hal: mmap framebuffer failed\n", 31);
        sys_close(g_fb_fd);
        return -1;
    }

    // Allocate backbuffer for double-buffering -- تخصيص المخزن المؤقت
    // MAP_PRIVATE|MAP_ANONYMOUS = 34
    g_fb_back = cast<char*>(sys_mmap(0, g_fb_size, 3, 34, -1, 0));
    if (fb_mmap_failed(g_fb_back) == 1) {
        sys_write(2, "fb_hal: mmap backbuffer failed\n", 30);
        // Continue without backbuffer, use direct rendering
        g_fb_back = g_fb_mem;
    }

    return 0;
}

// ---------------------------------------------------------------------------
// fb_mmap_failed -- هل فشل mmap؟ (النتيجة -1 في آخر 64 بت)
// mmap returns -1 (all bits set) on failure; a valid mapping is a canonical
// user address.  We detect failure by checking that the pointer is either 0
// or has only its low bit set in every byte after truncation to 64 bits.
// Since our trampoline returns int (already 64-bit), -1 is the only negative
// value mmap can return.
// ---------------------------------------------------------------------------
fn fb_mmap_failed(char* p) -> int {
    // The trampoline puts the raw syscall result in a 64-bit value.  A failed
    // mmap is exactly (unsigned)-1.  Any successful mapping on x86_64 Linux
    // is in [0x0000000000400000, 0x00007fffffffffff], never negative when
    // interpreted as a signed 64-bit int.
    int v = cast<int>(p);
    if (v == -1) { return 1; }
    return 0;
}

// ---------------------------------------------------------------------------
// gui_grab_display / gui_release_display -- الاستيلاء على الشاشة بالكامل
//
// Problem: writing to /dev/fb0 lets us paint pixels, but the kernel's virtual
// terminal (fbcon) still OWNS the screen.  It keeps its own text cursor, and
// on any console activity (kernel messages, another process writing to the
// tty, a VT switch) it repaints over our graphics -- exactly the "GUI draws
// inside the tty instead of taking over the screen" symptom.
//
// Fix (the same thing X/Wayland/GNOME do): put the active VT into KD_GRAPHICS
// mode.  In that mode fbcon stops drawing the text console entirely and the
// framebuffer belongs to us.  We also hide the hardware text cursor and detach
// the VT keyboard so stray keystrokes do not print to the console.
//
// VT ioctls (linux/kd.h):
//   KDSETMODE = 0x4B3A   KD_TEXT=0x00, KD_GRAPHICS=0x01
//   KDSKBMODE = 0x4B45   K_XLATE=0x01, K_OFF=0x04
// ---------------------------------------------------------------------------
static int g_display_fd;        // /dev/tty0 file descriptor (-1 when not grabbed)
static int g_display_grabbed;   // 1 when we own the VT in graphics mode

fn gui_grab_display() -> int {
    // /dev/tty0 is the currently active virtual terminal; we must own it to
    // switch it to graphics mode.  O_RDWR = 2.
    g_display_fd = sys_open("/dev/tty0", 2);
    if (g_display_fd < 0) {
        // Not fatal: we can still draw to /dev/fb0 (e.g. inside a container).
        sys_write(2, "fb_hal: no /dev/tty0, drawing without VT takeover\n", 50);
        g_display_grabbed = 0;
        return -1;
    }

    // Enter graphics mode: fbcon releases the framebuffer and stops drawing
    // the text console over us.  KDSETMODE = 0x4B3A, KD_GRAPHICS = 1.
    if (sys_ioctl(g_display_fd, 0x4B3A, cast<char*>(1)) < 0) {
        sys_write(2, "fb_hal: KDSETMODE KD_GRAPHICS failed\n", 37);
    }

    // Hide the hardware cursor (DEC private mode ?25l).  In graphics mode the
    // cursor is normally already invisible, but this covers the transition.
    sys_write(g_display_fd, "\033[?25l", 6);
    // Move the cursor home and clear so no stale text remains under the GUI.
    sys_write(g_display_fd, "\033[2J\033[H", 7);

    // Detach the keyboard from the VT so nothing we do prints to the console.
    // KDSKBMODE = 0x4B45, K_OFF = 4.  (Input still arrives via evdev.)
    sys_ioctl(g_display_fd, 0x4B45, cast<char*>(4));

    g_display_grabbed = 1;
    return 0;
}

fn gui_release_display() -> void {
    if (g_display_grabbed != 1) { return; }
    // Restore the keyboard and return the VT to normal text mode.
    sys_ioctl(g_display_fd, 0x4B45, cast<char*>(1)); // K_XLATE = 1
    sys_write(g_display_fd, "\033[?25h", 6);          // show cursor again
    sys_ioctl(g_display_fd, 0x4B3A, cast<char*>(0)); // KD_TEXT = 0
    if (g_display_fd >= 0) { sys_close(g_display_fd); }
    g_display_fd = -1;
    g_display_grabbed = 0;
}

fn fb_display_grabbed() -> int { return g_display_grabbed; }


// ---------------------------------------------------------------------------
// fb_get_width / fb_get_height / fb_get_bpp / fb_get_stride
// Getter functions for screen info
// ---------------------------------------------------------------------------
fn fb_get_width() -> int { return g_fb_width; }
fn fb_get_height() -> int { return g_fb_height; }
fn fb_get_bpp() -> int { return g_fb_bpp; }
fn fb_get_stride() -> int { return g_fb_stride; }
fn fb_get_size() -> int { return g_fb_size; }
fn fb_get_mem() -> char* { return g_fb_mem; }
fn fb_get_back() -> char* { return g_fb_back; }

// ---------------------------------------------------------------------------
// fb_scale_channel -- ضبط قناة لون إلى طولها النسبي
// Scale an 8-bit channel (0..255) into `len` bits (1..8).
// e.g. len=5 -> 0..31, len=6 -> 0..63, len=8 -> 0..255.
// ---------------------------------------------------------------------------
fn fb_scale_channel(int v, int len) -> int {
    if (len >= 8) { return v; }
    if (len <= 0) { return 0; }
    if (v < 0) { v = 0; }
    if (v > 255) { v = 255; }
    int max = 1;
    int i = 1;
    while (i < len) {
        max = max * 2 + 1;
        i = i + 1;
    }
    return (v * max) / 255;
}

// fb_shl -- إزاحة يسار آمنة (بدون دعم الأعداد السالبة غير اللازم هنا)
fn fb_shl(int v, int n) -> int {
    int r = v;
    while (n > 0) {
        r = r * 2;
        n = n - 1;
    }
    return r;
}

// ---------------------------------------------------------------------------
// rgb_pack -- تحويل ألوان RGB إلى قيمة بكسل حسب عمق اللون
// Convert RGB (0-255 each) to a packed pixel value based on the *driver
// reported* channel offsets/lengths, so it is correct for RGB565, RGB555,
// XRGB8888, ARGB8888, BGRA... whatever fb_var_screeninfo says.
// Falls back to plain 0x00RRGGBB when the framebuffer is not initialized.
// ---------------------------------------------------------------------------
fn rgb_pack(int r, int g, int b) -> int {
    if (g_fb_bpp == 16) {
        return fb_shl(fb_scale_channel(r, g_fb_red_len), g_fb_red_off)
             | fb_shl(fb_scale_channel(g, g_fb_green_len), g_fb_green_off)
             | fb_shl(fb_scale_channel(b, g_fb_blue_len), g_fb_blue_off);
    }
    if (g_fb_bpp == 24) {
        return fb_shl(fb_scale_channel(r, g_fb_red_len), g_fb_red_off)
             | fb_shl(fb_scale_channel(g, g_fb_green_len), g_fb_green_off)
             | fb_shl(fb_scale_channel(b, g_fb_blue_len), g_fb_blue_off);
    }
    if (g_fb_bpp == 32) {
        return fb_shl(fb_scale_channel(r, g_fb_red_len), g_fb_red_off)
             | fb_shl(fb_scale_channel(g, g_fb_green_len), g_fb_green_off)
             | fb_shl(fb_scale_channel(b, g_fb_blue_len), g_fb_blue_off);
    }
    // framebuffer not open (or exotic depth): plain 0x00RRGGBB
    return r * 65536 + g * 256 + b;
}

// ---------------------------------------------------------------------------
// fb_store32 -- كتابة 32 بت (4 بايت) مباشرة في الذاكرة
// Fast native 4-byte store at byte offset `off`.
//
// Magnetar `int*` pointers are BYTE-addressed but store 4 bytes, so a single
// store replaces four putb() calls (each carrying a division). Benchmarked on
// this build: ~18x faster than the byte helpers for full-screen blits.
// x86_64 allows unaligned 4-byte stores, so no alignment care is needed.
// ---------------------------------------------------------------------------
fn fb_store32(char* mem, int off, int v) -> void {
    int* p = cast<int*>(mem + off);
    *p = v;
}

// ---------------------------------------------------------------------------
// fb_copy_bytes -- نسخ سريع بين منطقتين في الذاكرة
// Fast memcpy: 4 bytes per iteration through a temporary (the temp form is
// required -- a direct `*(d+i) = *(s+i)` miscompiles in magc).
// The 8-byte load at the tail is bounded by `i + 8 <= n` so it can never run
// past the end of the mapping; remaining bytes fall back to byte copies.
// ---------------------------------------------------------------------------
fn fb_copy_bytes(char* dst, char* src, int n) -> void {
    int* d = cast<int*>(dst);
    int* s = cast<int*>(src);
    int i = 0;
    while (i + 8 <= n) {
        int t = *(s + i);
        *(d + i) = t;
        i = i + 4;
    }
    while (i < n) {
        putb(dst, i, getb(src, i));
        i = i + 1;
    }
}

// ---------------------------------------------------------------------------
// fb_put_pixel -- رسم بكسل واحد على المخزن المؤقت
// Draw a single pixel at (x, y) with packed color value on the backbuffer.
// Bounds-checked to prevent writes outside the framebuffer.
// ---------------------------------------------------------------------------
fn fb_put_pixel(int x, int y, int color) -> void {
    // Bounds check -- فحص الحدود
    if (x < 0) { return; }
    if (y < 0) { return; }
    if (x >= g_fb_width) { return; }
    if (y >= g_fb_height) { return; }

    int bytes_pp = g_fb_bpp / 8;
    int offset = y * g_fb_stride + x * bytes_pp;

    // 32bpp: one native store (fast path -- the common VirtualBox/VMSVGA case)
    if (g_fb_bpp == 32) {
        fb_store32(g_fb_back, offset, color);
        return;
    }
    if (g_fb_bpp == 24) {
        putb(g_fb_back, offset, bval(color));
        putb(g_fb_back, offset + 1, bval(color / 256));
        putb(g_fb_back, offset + 2, bval(color / 65536));
    }
    if (g_fb_bpp == 16) {
        putb(g_fb_back, offset, bval(color));
        putb(g_fb_back, offset + 1, bval(color / 256));
    }
}

// ---------------------------------------------------------------------------
// fb_put_pixel_direct -- رسم بكسل مباشرة على الفريم بفر (بدون مخزن مؤقت)
// Draw directly to framebuffer, bypassing backbuffer. Used for cursor.
// ---------------------------------------------------------------------------
fn fb_put_pixel_direct(int x, int y, int color) -> void {
    if (x < 0) { return; }
    if (y < 0) { return; }
    if (x >= g_fb_width) { return; }
    if (y >= g_fb_height) { return; }

    int bytes_pp = g_fb_bpp / 8;
    int offset = y * g_fb_stride + x * bytes_pp;

    if (g_fb_bpp == 32) {
        putb(g_fb_mem, offset, bval(color));
        putb(g_fb_mem, offset + 1, bval(color / 256));
        putb(g_fb_mem, offset + 2, bval(color / 65536));
        putb(g_fb_mem, offset + 3, bval(color / 16777216));
    }
    if (g_fb_bpp == 24) {
        putb(g_fb_mem, offset, bval(color));
        putb(g_fb_mem, offset + 1, bval(color / 256));
        putb(g_fb_mem, offset + 2, bval(color / 65536));
    }
    if (g_fb_bpp == 16) {
        putb(g_fb_mem, offset, bval(color));
        putb(g_fb_mem, offset + 1, bval(color / 256));
    }
}

// ---------------------------------------------------------------------------
// fb_fill_span -- ملء سطر من البكسلات في ذاكرة واحدة (بلا فحص حدود)
// Fill `count` consecutive pixels starting at byte offset `off` of `mem`.
// The caller is responsible for keeping the span inside the framebuffer.
// One bounds check per span instead of one per pixel: ~6x faster on large
// areas (a 1920x1080 clear is 2M pixels).
// ---------------------------------------------------------------------------
fn fb_fill_span(char* mem, int off, int count, int color) -> void {
    int i = 0;
    if (g_fb_bpp == 32) {
        while (i < count) {
            fb_store32(mem, off + i * 4, color);
            i = i + 1;
        }
        return;
    }
    if (g_fb_bpp == 24) {
        while (i < count) {
            int p = off + i * 3;
            putb(mem, p, bval(color));
            putb(mem, p + 1, bval(color / 256));
            putb(mem, p + 2, bval(color / 65536));
            i = i + 1;
        }
        return;
    }
    if (g_fb_bpp == 16) {
        while (i < count) {
            int p = off + i * 2;
            putb(mem, p, bval(color));
            putb(mem, p + 1, bval(color / 256));
            i = i + 1;
        }
        return;
    }
}

// ---------------------------------------------------------------------------
// fb_clear -- مسح الشاشة بلون واحد
// Clear the entire backbuffer with a single color (row-wise, no per-pixel
// bounds checks).
// ---------------------------------------------------------------------------
fn fb_clear(int color) -> void {
    if (g_fb_height <= 0) { return; }
    int y = 0;
    while (y < g_fb_height) {
        fb_fill_span(g_fb_back, y * g_fb_stride, g_fb_width, color);
        y = y + 1;
    }
}

// ---------------------------------------------------------------------------
// fb_flip -- نسخ المخزن المؤقت إلى الفريم بفر (عرض الإطار)
// Copy the backbuffer to the actual framebuffer (page flip).
// This is the only place where the user sees changes.
// ---------------------------------------------------------------------------
fn fb_flip() -> void {
    if (g_fb_back == g_fb_mem) { return; } // no separate backbuffer
    fb_copy_bytes(g_fb_mem, g_fb_back, g_fb_size);
}

// ---------------------------------------------------------------------------
// fb_peek -- قراءة بكسل من المخزن المؤقت (للاختبار الذاتي)
// Read back a packed pixel from the backbuffer at (x, y). Returns -1 when the
// coordinate is off-screen.  Used by --selftest; never shown to the user.
// ---------------------------------------------------------------------------
fn fb_peek(int x, int y) -> int {
    if (x < 0) { return -1; }
    if (y < 0) { return -1; }
    if (x >= g_fb_width) { return -1; }
    if (y >= g_fb_height) { return -1; }

    int bytes_pp = g_fb_bpp / 8;
    int off = y * g_fb_stride + x * bytes_pp;
    if (g_fb_bpp == 32) { return getd(g_fb_back, off); }
    if (g_fb_bpp == 24) {
        return getb(g_fb_back, off) + getb(g_fb_back, off + 1) * 256
             + getb(g_fb_back, off + 2) * 65536;
    }
    if (g_fb_bpp == 16) { return getw(g_fb_back, off); }
    return -1;
}

// ---------------------------------------------------------------------------
// fb_fill_rect_fast -- ملء مستطيل بسرعة مباشرة على المخزن المؤقت
// Fast rectangle fill - clipped once per edge, then one bounds check per row.
// ---------------------------------------------------------------------------
fn fb_fill_rect_fast(int rx, int ry, int rw, int rh, int color) -> void {
    if (rw <= 0) { return; }
    if (rh <= 0) { return; }
    if (g_fb_height <= 0) { return; }

    int x0 = rx;
    int y0 = ry;
    int x1 = rx + rw;
    int y1 = ry + rh;
    if (x0 < 0) { x0 = 0; }
    if (y0 < 0) { y0 = 0; }
    if (x1 > g_fb_width) { x1 = g_fb_width; }
    if (y1 > g_fb_height) { y1 = g_fb_height; }
    if (x1 <= x0) { return; }
    if (y1 <= y0) { return; }

    int bytes_pp = g_fb_bpp / 8;
    int span = x1 - x0;
    int y = y0;
    while (y < y1) {
        fb_fill_span(g_fb_back, y * g_fb_stride + x0 * bytes_pp, span, color);
        y = y + 1;
    }
}

// ---------------------------------------------------------------------------
// fb_close -- إغلاق الفريم بفر
// Clean up framebuffer resources.
// ---------------------------------------------------------------------------
fn fb_close() -> void {
    sys_close(g_fb_fd);
}

// ---------------------------------------------------------------------------
// fb_print_info -- طباعة معلومات الشاشة (للتصحيح)
// Print screen information for debugging.
// ---------------------------------------------------------------------------
fn fb_print_info() -> void {
    // We write info to stderr (fd 2) for diagnostics
    char* buf = cast<char*>(sys_mmap(0, 256, 3, 34, -1, 0));
    sys_write(2, "fb_hal: screen ", 15);
    // format width x height x bpp
    int k = 0;
    int n = g_fb_width;
    if (n == 0) { putb(buf, k, 48); k = k + 1; }
    while (n > 0) {
        int d = n - (n / 10) * 10;
        putb(buf, k, 48 + d);
        k = k + 1;
        n = n / 10;
    }
    // reverse the digits
    int a = 0;
    int b = k - 1;
    while (a < b) {
        int tmp = getb(buf, a);
        putb(buf, a, getb(buf, b));
        putb(buf, b, tmp);
        a = a + 1;
        b = b - 1;
    }
    sys_write(2, buf, k);
    sys_write(2, "x", 1);

    k = 0;
    n = g_fb_height;
    if (n == 0) { putb(buf, k, 48); k = k + 1; }
    while (n > 0) {
        int d = n - (n / 10) * 10;
        putb(buf, k, 48 + d);
        k = k + 1;
        n = n / 10;
    }
    a = 0;
    b = k - 1;
    while (a < b) {
        int tmp = getb(buf, a);
        putb(buf, a, getb(buf, b));
        putb(buf, b, tmp);
        a = a + 1;
        b = b - 1;
    }
    sys_write(2, buf, k);
    sys_write(2, "x", 1);

    k = 0;
    n = g_fb_bpp;
    if (n == 0) { putb(buf, k, 48); k = k + 1; }
    while (n > 0) {
        int d = n - (n / 10) * 10;
        putb(buf, k, 48 + d);
        k = k + 1;
        n = n / 10;
    }
    a = 0;
    b = k - 1;
    while (a < b) {
        int tmp = getb(buf, a);
        putb(buf, a, getb(buf, b));
        putb(buf, b, tmp);
        a = a + 1;
        b = b - 1;
    }
    sys_write(2, buf, k);
    sys_write(2, "bpp stride=", 11);

    k = 0;
    n = g_fb_stride;
    if (n == 0) { putb(buf, k, 48); k = k + 1; }
    while (n > 0) {
        int d = n - (n / 10) * 10;
        putb(buf, k, 48 + d);
        k = k + 1;
        n = n / 10;
    }
    a = 0;
    b = k - 1;
    while (a < b) {
        int tmp = getb(buf, a);
        putb(buf, a, getb(buf, b));
        putb(buf, b, tmp);
        a = a + 1;
        b = b - 1;
    }
    sys_write(2, buf, k);
    sys_write(2, "\n", 1);
}
