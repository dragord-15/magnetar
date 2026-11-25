// gfx_primitives.mg -- الوحدة 2: عناصر الرسم الأساسية (Graphics Primitives)
// BlackhatOS GUI Core - Drawing primitives and bitmap font renderer
//
// This module provides:
//   - Bresenham line drawing
//   - Rectangle (filled and outline)
//   - Midpoint circle algorithm
//   - Embedded 8x8 ASCII bitmap font
//   - Character and string rendering
//
// All functions draw to the backbuffer via fb_put_pixel from fb_hal.mg

// ---------------------------------------------------------------------------
// External dependencies from fb_hal.mg
// ---------------------------------------------------------------------------
extern fn fb_put_pixel(int x, int y, int color) -> void;
extern fn fb_get_width() -> int;
extern fn fb_get_height() -> int;
extern fn bval(int v) -> int;
extern fn putb(char* p, int off, int v) -> void;
extern fn getb(char* p, int off) -> int;
extern fn sys_mmap(char* addr, int length, int prot, int flags, int fd, int offset) -> int;
extern fn fb_fill_rect_fast(int x, int y, int w, int h, int color) -> void;
extern fn rgb_pack(int r, int g, int b) -> int;
extern fn name_len(char* p) -> int;
extern fn draw_string(int px, int py, char* str, int color) -> void;

// ---------------------------------------------------------------------------
// abs -- القيمة المطلقة
// ---------------------------------------------------------------------------
fn gfx_abs(int v) -> int {
    if (v < 0) { return -v; }
    return v;
}

// ---------------------------------------------------------------------------
// draw_line -- رسم خط مستقيم باستخدام خوارزمية Bresenham
// Bresenham's line algorithm: draws a line from (x0,y0) to (x1,y1).
// ---------------------------------------------------------------------------
fn draw_line(int x0, int y0, int x1, int y1, int color) -> void {
    int dx = gfx_abs(x1 - x0);
    int dy = -gfx_abs(y1 - y0);
    int sx = 1;
    int sy = 1;
    if (x0 > x1) { sx = -1; }
    if (y0 > y1) { sy = -1; }
    int err = dx + dy;
    int x = x0;
    int y = y0;

    while (1) {
        fb_put_pixel(x, y, color);
        if ((x == x1) && (y == y1)) { return; }
        int e2 = err * 2;
        if (e2 >= dy) {
            if (x == x1) { return; }
            err = err + dy;
            x = x + sx;
        }
        if (e2 <= dx) {
            if (y == y1) { return; }
            err = err + dx;
            y = y + sy;
        }
    }
}

// ---------------------------------------------------------------------------
// draw_hline -- رسم خط أفقي (سريع)
// Optimized horizontal line for rectangle fills.
// ---------------------------------------------------------------------------
fn draw_hline(int x0, int x1, int y, int color) -> void {
    int start = x0;
    int end = x1;
    if (start > end) {
        start = x1;
        end = x0;
    }
    int x = start;
    while (x <= end) {
        fb_put_pixel(x, y, color);
        x = x + 1;
    }
}

// ---------------------------------------------------------------------------
// draw_rect -- رسم إطار مستطيل (outline)
// Draw a rectangle outline from (x, y) with dimensions (w, h).
// ---------------------------------------------------------------------------
fn draw_rect(int x, int y, int w, int h, int color) -> void {
    // Top edge - الحافة العلوية
    draw_hline(x, x + w - 1, y, color);
    // Bottom edge - الحافة السفلية
    draw_hline(x, x + w - 1, y + h - 1, color);
    // Left edge - الحافة اليسرى
    int i = y;
    while (i < y + h) {
        fb_put_pixel(x, i, color);
        i = i + 1;
    }
    // Right edge - الحافة اليمنى
    i = y;
    while (i < y + h) {
        fb_put_pixel(x + w - 1, i, color);
        i = i + 1;
    }
}

// ---------------------------------------------------------------------------
// draw_filled_rect -- رسم مستطيل مملوء
// Draw a filled rectangle from (x, y) with dimensions (w, h).
// ---------------------------------------------------------------------------
fn draw_filled_rect(int x, int y, int w, int h, int color) -> void {
    // Fast path: one clipped span fill per row instead of a per-pixel
    // bounds check.  Falls back to the generic loop if fb_hal was not linked.
    fb_fill_rect_fast(x, y, w, h, color);
}

// ---------------------------------------------------------------------------
// draw_circle -- رسم دائرة باستخدام خوارزمية Midpoint
// Midpoint circle algorithm: draws a circle outline.
// ---------------------------------------------------------------------------
fn draw_circle(int cx, int cy, int r, int color) -> void {
    int x = r;
    int y = 0;
    int d = 1 - r;

    while (x >= y) {
        // رسم 8 نقاط متماثلة
        fb_put_pixel(cx + x, cy + y, color);
        fb_put_pixel(cx - x, cy + y, color);
        fb_put_pixel(cx + x, cy - y, color);
        fb_put_pixel(cx - x, cy - y, color);
        fb_put_pixel(cx + y, cy + x, color);
        fb_put_pixel(cx - y, cy + x, color);
        fb_put_pixel(cx + y, cy - x, color);
        fb_put_pixel(cx - y, cy - x, color);

        y = y + 1;
        if (d <= 0) {
            d = d + 2 * y + 1;
        } else {
            x = x - 1;
            d = d + 2 * y - 2 * x + 1;
        }
    }
}

// ---------------------------------------------------------------------------
// draw_filled_circle -- رسم دائرة مملوءة
// Filled circle using horizontal lines between symmetric points.
// ---------------------------------------------------------------------------
fn draw_filled_circle(int cx, int cy, int r, int color) -> void {
    int x = r;
    int y = 0;
    int d = 1 - r;

    while (x >= y) {
        draw_hline(cx - x, cx + x, cy + y, color);
        draw_hline(cx - x, cx + x, cy - y, color);
        draw_hline(cx - y, cx + y, cy + x, color);
        draw_hline(cx - y, cx + y, cy - x, color);
        y = y + 1;
        if (d <= 0) {
            d = d + 2 * y + 1;
        } else {
            x = x - 1;
            d = d + 2 * y - 2 * x + 1;
        }
    }
}

// ---------------------------------------------------------------------------
// draw_rounded_rect -- رسم مستطيل بأركان مستديرة
// Draw a filled rounded rectangle. Corner radius = rad.
// ---------------------------------------------------------------------------
fn draw_rounded_rect(int rx, int ry, int rw, int rh, int rad, int color) -> void {
    if (rw <= 0) { return; }
    if (rh <= 0) { return; }
    if (rad < 0) { rad = 0; }
    int max_rad = rw / 2;
    if (rh / 2 < max_rad) { max_rad = rh / 2; }
    if (rad > max_rad) { rad = max_rad; }
    if (rad == 0) {
        draw_filled_rect(rx, ry, rw, rh, color);
        return;
    }
    // Center body (without corners)
    draw_filled_rect(rx + rad, ry, rw - 2 * rad, rh, color);
    // Left strip
    draw_filled_rect(rx, ry + rad, rad, rh - 2 * rad, color);
    // Right strip
    draw_filled_rect(rx + rw - rad, ry + rad, rad, rh - 2 * rad, color);

    // Four corner circles (quarter circles)
    int x = rad;
    int y = 0;
    int d = 1 - rad;
    while (x >= y) {
        // Top-left corner
        draw_hline(rx + rad - x, rx + rad, ry + rad - y, color);
        draw_hline(rx + rad - y, rx + rad, ry + rad - x, color);
        // Top-right corner
        draw_hline(rx + rw - rad - 1, rx + rw - rad - 1 + x, ry + rad - y, color);
        draw_hline(rx + rw - rad - 1, rx + rw - rad - 1 + y, ry + rad - x, color);
        // Bottom-left corner
        draw_hline(rx + rad - x, rx + rad, ry + rh - rad - 1 + y, color);
        draw_hline(rx + rad - y, rx + rad, ry + rh - rad - 1 + x, color);
        // Bottom-right corner
        draw_hline(rx + rw - rad - 1, rx + rw - rad - 1 + x, ry + rh - rad - 1 + y, color);
        draw_hline(rx + rw - rad - 1, rx + rw - rad - 1 + y, ry + rh - rad - 1 + x, color);

        y = y + 1;
        if (d <= 0) {
            d = d + 2 * y + 1;
        } else {
            x = x - 1;
            d = d + 2 * y - 2 * x + 1;
        }
    }
}

// Filled vertical gradient. RGB values are interpolated before packing so
// the helper works with RGB565 as well as 24/32-bit framebuffers.
fn draw_gradient_rect(int x, int y, int w, int h, int r0, int g0, int b0, int r1, int g1, int b1) -> void {
    if (w <= 0) { return; }
    if (h <= 0) { return; }
    int row = 0;
    while (row < h) {
        int den = h - 1;
        if (den < 1) { den = 1; }
        int rr = r0 + ((r1 - r0) * row) / den;
        int gg = g0 + ((g1 - g0) * row) / den;
        int bb = b0 + ((b1 - b0) * row) / den;
        draw_filled_rect(x, y + row, w, 1, rgb_pack(rr, gg, bb));
        row = row + 1;
    }
}

// Vertical gradient clipped to rounded corners, for polished button and card
// surfaces without square pixels leaking past the silhouette.
fn draw_gradient_rounded_rect(int x, int y, int w, int h, int radius, int r0, int g0, int b0, int r1, int g1, int b1) -> void {
    if (w <= 0) { return; }
    if (h <= 0) { return; }
    if (radius < 0) { radius = 0; }
    int max_radius = w / 2;
    if (h / 2 < max_radius) { max_radius = h / 2; }
    if (radius > max_radius) { radius = max_radius; }
    int row = 0;
    while (row < h) {
        int inset = 0;
        if (radius > 0 && row < radius) {
            int dy = radius - row - 1;
            while (inset < radius) {
                int dx = radius - inset - 1;
                if (dx * dx + dy * dy <= radius * radius) { break; }
                inset = inset + 1;
            }
        } else if (radius > 0 && row >= h - radius) {
            int dy = row - (h - radius);
            while (inset < radius) {
                int dx = radius - inset - 1;
                if (dx * dx + dy * dy <= radius * radius) { break; }
                inset = inset + 1;
            }
        }
        int den = h - 1;
        if (den < 1) { den = 1; }
        int rr = r0 + ((r1 - r0) * row) / den;
        int gg = g0 + ((g1 - g0) * row) / den;
        int bb = b0 + ((b1 - b0) * row) / den;
        int span = w - 2 * inset;
        if (span > 0) { draw_filled_rect(x + inset, y + row, span, 1, rgb_pack(rr, gg, bb)); }
        row = row + 1;
    }
}

// Soft compact shadow made from progressively larger translucent-looking
// (solid color) layers; callers choose a muted color matching their surface.
fn draw_soft_shadow(int x, int y, int w, int h, int radius, int color) -> void {
    if (w <= 0) { return; }
    if (h <= 0) { return; }
    int i = radius;
    while (i > 0) {
        draw_rounded_rect(x + i, y + i, w, h, 8, color);
        i = i - 1;
    }
}

// Border around a rounded rectangle. The inner fill uses the surface color.
fn draw_rounded_outline(int x, int y, int w, int h, int radius, int border, int surface) -> void {
    if (w <= 0) { return; }
    if (h <= 0) { return; }
    draw_rounded_rect(x, y, w, h, radius, border);
    if (w > 2 && h > 2) {
        int inner_radius = radius - 1;
        if (inner_radius < 0) { inner_radius = 0; }
        draw_rounded_rect(x + 1, y + 1, w - 2, h - 2, inner_radius, surface);
    }
}

// Reusable progress bar with a rounded track and a clamped 0..100 value.
fn draw_progress_bar(int x, int y, int w, int h, int value, int track, int fill) -> void {
    if (w <= 0) { return; }
    if (h <= 0) { return; }
    if (value < 0) { value = 0; }
    if (value > 100) { value = 100; }
    int radius = h / 2;
    draw_rounded_rect(x, y, w, h, radius, track);
    int fw = (w * value) / 100;
    if (fw > 0) { draw_rounded_rect(x, y, fw, h, radius, fill); }
}

// Small rounded status badge. Text is centered using the built-in 8x8 font.
fn draw_badge(int x, int y, int w, int h, char* text, int bg, int fg) -> void {
    if (w <= 0) { return; }
    if (h <= 0) { return; }
    draw_rounded_rect(x, y, w, h, h / 2, bg);
    int tw = name_len(text) * 8;
    draw_string(x + (w - tw) / 2, y + (h - 8) / 2, text, fg);
}

// Resolution-independent controls. These are drawing primitives; applications
// can keep their existing input handling and pass the current value/state.
fn draw_checkbox(int x, int y, int size, int checked, int surface, int accent, int border) -> void {
    if (size < 6) { return; }
    draw_rounded_outline(x, y, size, size, 3, border, surface);
    if (checked != 0) {
        draw_rounded_rect(x + 2, y + 2, size - 4, size - 4, 2, accent);
        draw_line(x + size / 4, y + size / 2, x + size / 2 - 1, y + size * 3 / 4, surface);
        draw_line(x + size / 2 - 1, y + size * 3 / 4, x + size * 4 / 5, y + size / 4, surface);
    }
}

fn draw_toggle(int x, int y, int w, int h, int enabled, int off_color, int on_color, int knob_color) -> void {
    if (w <= 0) { return; }
    if (h <= 0) { return; }
    int radius = h / 2;
    int track = off_color;
    if (enabled != 0) { track = on_color; }
    draw_rounded_rect(x, y, w, h, radius, track);
    int knob = h - 4;
    if (knob < 2) { knob = h; }
    int kx = x + 2;
    if (enabled != 0) { kx = x + w - knob - 2; }
    draw_filled_circle(kx + knob / 2, y + h / 2, knob / 2, knob_color);
}

fn draw_slider(int x, int y, int w, int h, int value, int track_color, int fill_color, int knob_color) -> void {
    if (w < 3) { return; }
    if (h < 3) { return; }
    if (value < 0) { value = 0; }
    if (value > 100) { value = 100; }
    int track_h = h / 3;
    if (track_h < 2) { track_h = 2; }
    int track_y = y + (h - track_h) / 2;
    int radius = h / 2;
    if (radius > (w - 1) / 2) { radius = (w - 1) / 2; }
    if (radius < 1) { radius = 1; }
    int usable = w - 2 * radius;
    if (usable < 0) { usable = 0; }
    int pos = usable * value / 100;
    int track_x = x + radius;
    int track_w = usable;
    if (track_w < 1) { track_w = 1; }
    draw_rounded_rect(track_x, track_y, track_w, track_h, track_h / 2, track_color);
    if (pos > 0) { draw_rounded_rect(track_x, track_y, pos + 1, track_h, track_h / 2, fill_color); }
    draw_filled_circle(track_x + pos, y + h / 2, radius, knob_color);
    draw_circle(track_x + pos, y + h / 2, radius, fill_color);
}

// ===========================================================================
// BITMAP FONT -- خط bitmap مدمج 8x8 بكسل لحروف ASCII 32-126
// Embedded 8x8 bitmap font for printable ASCII (space through tilde).
// Each character is 8 bytes, one byte per row, MSB = leftmost pixel.
// ===========================================================================

// Global pointer to the font data (allocated and filled in gfx_font_init)
static char* g_font8x8;

// ---------------------------------------------------------------------------
// gfx_font_init -- تهيئة الخط المدمج
// Initialize the embedded 8x8 font. Must be called once at startup.
// The font covers ASCII 32 (space) through 126 (~), total 95 characters.
// Each character = 8 bytes, total = 95 * 8 = 760 bytes.
// ---------------------------------------------------------------------------
fn gfx_font_init() -> void {
    g_font8x8 = cast<char*>(sys_mmap(0, 4096, 3, 34, -1, 0));

    // Space (32) - all zeros
    int fbase = 0;
    putb(g_font8x8, fbase + 0, 0x00); putb(g_font8x8, fbase + 1, 0x00);
    putb(g_font8x8, fbase + 2, 0x00); putb(g_font8x8, fbase + 3, 0x00);
    putb(g_font8x8, fbase + 4, 0x00); putb(g_font8x8, fbase + 5, 0x00);
    putb(g_font8x8, fbase + 6, 0x00); putb(g_font8x8, fbase + 7, 0x00);

    // ! (33)
    fbase = 8;
    putb(g_font8x8, fbase + 0, 0x18); putb(g_font8x8, fbase + 1, 0x18);
    putb(g_font8x8, fbase + 2, 0x18); putb(g_font8x8, fbase + 3, 0x18);
    putb(g_font8x8, fbase + 4, 0x18); putb(g_font8x8, fbase + 5, 0x00);
    putb(g_font8x8, fbase + 6, 0x18); putb(g_font8x8, fbase + 7, 0x00);

    // " (34)
    fbase = 16;
    putb(g_font8x8, fbase + 0, 0x6C); putb(g_font8x8, fbase + 1, 0x6C);
    putb(g_font8x8, fbase + 2, 0x24); putb(g_font8x8, fbase + 3, 0x00);
    putb(g_font8x8, fbase + 4, 0x00); putb(g_font8x8, fbase + 5, 0x00);
    putb(g_font8x8, fbase + 6, 0x00); putb(g_font8x8, fbase + 7, 0x00);

    // # (35)
    fbase = 24;
    putb(g_font8x8, fbase + 0, 0x24); putb(g_font8x8, fbase + 1, 0x7E);
    putb(g_font8x8, fbase + 2, 0x24); putb(g_font8x8, fbase + 3, 0x24);
    putb(g_font8x8, fbase + 4, 0x7E); putb(g_font8x8, fbase + 5, 0x24);
    putb(g_font8x8, fbase + 6, 0x00); putb(g_font8x8, fbase + 7, 0x00);

    // $ (36)
    fbase = 32;
    putb(g_font8x8, fbase + 0, 0x08); putb(g_font8x8, fbase + 1, 0x3E);
    putb(g_font8x8, fbase + 2, 0x48); putb(g_font8x8, fbase + 3, 0x3C);
    putb(g_font8x8, fbase + 4, 0x12); putb(g_font8x8, fbase + 5, 0x7C);
    putb(g_font8x8, fbase + 6, 0x10); putb(g_font8x8, fbase + 7, 0x00);

    // % (37)
    fbase = 40;
    putb(g_font8x8, fbase + 0, 0x62); putb(g_font8x8, fbase + 1, 0x64);
    putb(g_font8x8, fbase + 2, 0x08); putb(g_font8x8, fbase + 3, 0x10);
    putb(g_font8x8, fbase + 4, 0x26); putb(g_font8x8, fbase + 5, 0x46);
    putb(g_font8x8, fbase + 6, 0x00); putb(g_font8x8, fbase + 7, 0x00);

    // & (38)
    fbase = 48;
    putb(g_font8x8, fbase + 0, 0x30); putb(g_font8x8, fbase + 1, 0x48);
    putb(g_font8x8, fbase + 2, 0x30); putb(g_font8x8, fbase + 3, 0x56);
    putb(g_font8x8, fbase + 4, 0x48); putb(g_font8x8, fbase + 5, 0x34);
    putb(g_font8x8, fbase + 6, 0x00); putb(g_font8x8, fbase + 7, 0x00);

    // ' (39)
    fbase = 56;
    putb(g_font8x8, fbase + 0, 0x18); putb(g_font8x8, fbase + 1, 0x18);
    putb(g_font8x8, fbase + 2, 0x08); putb(g_font8x8, fbase + 3, 0x00);
    putb(g_font8x8, fbase + 4, 0x00); putb(g_font8x8, fbase + 5, 0x00);
    putb(g_font8x8, fbase + 6, 0x00); putb(g_font8x8, fbase + 7, 0x00);

    // ( (40)
    fbase = 64;
    putb(g_font8x8, fbase + 0, 0x0C); putb(g_font8x8, fbase + 1, 0x18);
    putb(g_font8x8, fbase + 2, 0x30); putb(g_font8x8, fbase + 3, 0x30);
    putb(g_font8x8, fbase + 4, 0x30); putb(g_font8x8, fbase + 5, 0x18);
    putb(g_font8x8, fbase + 6, 0x0C); putb(g_font8x8, fbase + 7, 0x00);

    // ) (41)
    fbase = 72;
    putb(g_font8x8, fbase + 0, 0x30); putb(g_font8x8, fbase + 1, 0x18);
    putb(g_font8x8, fbase + 2, 0x0C); putb(g_font8x8, fbase + 3, 0x0C);
    putb(g_font8x8, fbase + 4, 0x0C); putb(g_font8x8, fbase + 5, 0x18);
    putb(g_font8x8, fbase + 6, 0x30); putb(g_font8x8, fbase + 7, 0x00);

    // * (42)
    fbase = 80;
    putb(g_font8x8, fbase + 0, 0x00); putb(g_font8x8, fbase + 1, 0x24);
    putb(g_font8x8, fbase + 2, 0x18); putb(g_font8x8, fbase + 3, 0x7E);
    putb(g_font8x8, fbase + 4, 0x18); putb(g_font8x8, fbase + 5, 0x24);
    putb(g_font8x8, fbase + 6, 0x00); putb(g_font8x8, fbase + 7, 0x00);

    // + (43)
    fbase = 88;
    putb(g_font8x8, fbase + 0, 0x00); putb(g_font8x8, fbase + 1, 0x18);
    putb(g_font8x8, fbase + 2, 0x18); putb(g_font8x8, fbase + 3, 0x7E);
    putb(g_font8x8, fbase + 4, 0x18); putb(g_font8x8, fbase + 5, 0x18);
    putb(g_font8x8, fbase + 6, 0x00); putb(g_font8x8, fbase + 7, 0x00);

    // , (44)
    fbase = 96;
    putb(g_font8x8, fbase + 0, 0x00); putb(g_font8x8, fbase + 1, 0x00);
    putb(g_font8x8, fbase + 2, 0x00); putb(g_font8x8, fbase + 3, 0x00);
    putb(g_font8x8, fbase + 4, 0x18); putb(g_font8x8, fbase + 5, 0x18);
    putb(g_font8x8, fbase + 6, 0x08); putb(g_font8x8, fbase + 7, 0x00);

    // - (45)
    fbase = 104;
    putb(g_font8x8, fbase + 0, 0x00); putb(g_font8x8, fbase + 1, 0x00);
    putb(g_font8x8, fbase + 2, 0x00); putb(g_font8x8, fbase + 3, 0x7E);
    putb(g_font8x8, fbase + 4, 0x00); putb(g_font8x8, fbase + 5, 0x00);
    putb(g_font8x8, fbase + 6, 0x00); putb(g_font8x8, fbase + 7, 0x00);

    // . (46)
    fbase = 112;
    putb(g_font8x8, fbase + 0, 0x00); putb(g_font8x8, fbase + 1, 0x00);
    putb(g_font8x8, fbase + 2, 0x00); putb(g_font8x8, fbase + 3, 0x00);
    putb(g_font8x8, fbase + 4, 0x00); putb(g_font8x8, fbase + 5, 0x18);
    putb(g_font8x8, fbase + 6, 0x18); putb(g_font8x8, fbase + 7, 0x00);

    // / (47)
    fbase = 120;
    putb(g_font8x8, fbase + 0, 0x02); putb(g_font8x8, fbase + 1, 0x04);
    putb(g_font8x8, fbase + 2, 0x08); putb(g_font8x8, fbase + 3, 0x10);
    putb(g_font8x8, fbase + 4, 0x20); putb(g_font8x8, fbase + 5, 0x40);
    putb(g_font8x8, fbase + 6, 0x00); putb(g_font8x8, fbase + 7, 0x00);

    // 0 (48)
    fbase = 128;
    putb(g_font8x8, fbase + 0, 0x3C); putb(g_font8x8, fbase + 1, 0x66);
    putb(g_font8x8, fbase + 2, 0x6E); putb(g_font8x8, fbase + 3, 0x76);
    putb(g_font8x8, fbase + 4, 0x66); putb(g_font8x8, fbase + 5, 0x66);
    putb(g_font8x8, fbase + 6, 0x3C); putb(g_font8x8, fbase + 7, 0x00);

    // 1 (49)
    fbase = 136;
    putb(g_font8x8, fbase + 0, 0x18); putb(g_font8x8, fbase + 1, 0x38);
    putb(g_font8x8, fbase + 2, 0x18); putb(g_font8x8, fbase + 3, 0x18);
    putb(g_font8x8, fbase + 4, 0x18); putb(g_font8x8, fbase + 5, 0x18);
    putb(g_font8x8, fbase + 6, 0x7E); putb(g_font8x8, fbase + 7, 0x00);

    // 2 (50)
    fbase = 144;
    putb(g_font8x8, fbase + 0, 0x3C); putb(g_font8x8, fbase + 1, 0x66);
    putb(g_font8x8, fbase + 2, 0x06); putb(g_font8x8, fbase + 3, 0x1C);
    putb(g_font8x8, fbase + 4, 0x30); putb(g_font8x8, fbase + 5, 0x60);
    putb(g_font8x8, fbase + 6, 0x7E); putb(g_font8x8, fbase + 7, 0x00);

    // 3 (51)
    fbase = 152;
    putb(g_font8x8, fbase + 0, 0x3C); putb(g_font8x8, fbase + 1, 0x66);
    putb(g_font8x8, fbase + 2, 0x06); putb(g_font8x8, fbase + 3, 0x1C);
    putb(g_font8x8, fbase + 4, 0x06); putb(g_font8x8, fbase + 5, 0x66);
    putb(g_font8x8, fbase + 6, 0x3C); putb(g_font8x8, fbase + 7, 0x00);

    // 4 (52)
    fbase = 160;
    putb(g_font8x8, fbase + 0, 0x0C); putb(g_font8x8, fbase + 1, 0x1C);
    putb(g_font8x8, fbase + 2, 0x2C); putb(g_font8x8, fbase + 3, 0x4C);
    putb(g_font8x8, fbase + 4, 0x7E); putb(g_font8x8, fbase + 5, 0x0C);
    putb(g_font8x8, fbase + 6, 0x0C); putb(g_font8x8, fbase + 7, 0x00);

    // 5 (53)
    fbase = 168;
    putb(g_font8x8, fbase + 0, 0x7E); putb(g_font8x8, fbase + 1, 0x60);
    putb(g_font8x8, fbase + 2, 0x7C); putb(g_font8x8, fbase + 3, 0x06);
    putb(g_font8x8, fbase + 4, 0x06); putb(g_font8x8, fbase + 5, 0x66);
    putb(g_font8x8, fbase + 6, 0x3C); putb(g_font8x8, fbase + 7, 0x00);

    // 6 (54)
    fbase = 176;
    putb(g_font8x8, fbase + 0, 0x1C); putb(g_font8x8, fbase + 1, 0x30);
    putb(g_font8x8, fbase + 2, 0x60); putb(g_font8x8, fbase + 3, 0x7C);
    putb(g_font8x8, fbase + 4, 0x66); putb(g_font8x8, fbase + 5, 0x66);
    putb(g_font8x8, fbase + 6, 0x3C); putb(g_font8x8, fbase + 7, 0x00);

    // 7 (55)
    fbase = 184;
    putb(g_font8x8, fbase + 0, 0x7E); putb(g_font8x8, fbase + 1, 0x06);
    putb(g_font8x8, fbase + 2, 0x0C); putb(g_font8x8, fbase + 3, 0x18);
    putb(g_font8x8, fbase + 4, 0x30); putb(g_font8x8, fbase + 5, 0x30);
    putb(g_font8x8, fbase + 6, 0x30); putb(g_font8x8, fbase + 7, 0x00);

    // 8 (56)
    fbase = 192;
    putb(g_font8x8, fbase + 0, 0x3C); putb(g_font8x8, fbase + 1, 0x66);
    putb(g_font8x8, fbase + 2, 0x66); putb(g_font8x8, fbase + 3, 0x3C);
    putb(g_font8x8, fbase + 4, 0x66); putb(g_font8x8, fbase + 5, 0x66);
    putb(g_font8x8, fbase + 6, 0x3C); putb(g_font8x8, fbase + 7, 0x00);

    // 9 (57)
    fbase = 200;
    putb(g_font8x8, fbase + 0, 0x3C); putb(g_font8x8, fbase + 1, 0x66);
    putb(g_font8x8, fbase + 2, 0x66); putb(g_font8x8, fbase + 3, 0x3E);
    putb(g_font8x8, fbase + 4, 0x06); putb(g_font8x8, fbase + 5, 0x0C);
    putb(g_font8x8, fbase + 6, 0x38); putb(g_font8x8, fbase + 7, 0x00);

    // : (58)
    fbase = 208;
    putb(g_font8x8, fbase + 0, 0x00); putb(g_font8x8, fbase + 1, 0x18);
    putb(g_font8x8, fbase + 2, 0x18); putb(g_font8x8, fbase + 3, 0x00);
    putb(g_font8x8, fbase + 4, 0x18); putb(g_font8x8, fbase + 5, 0x18);
    putb(g_font8x8, fbase + 6, 0x00); putb(g_font8x8, fbase + 7, 0x00);

    // ; (59)
    fbase = 216;
    putb(g_font8x8, fbase + 0, 0x00); putb(g_font8x8, fbase + 1, 0x18);
    putb(g_font8x8, fbase + 2, 0x18); putb(g_font8x8, fbase + 3, 0x00);
    putb(g_font8x8, fbase + 4, 0x18); putb(g_font8x8, fbase + 5, 0x18);
    putb(g_font8x8, fbase + 6, 0x08); putb(g_font8x8, fbase + 7, 0x00);

    // < (60)
    fbase = 224;
    putb(g_font8x8, fbase + 0, 0x06); putb(g_font8x8, fbase + 1, 0x0C);
    putb(g_font8x8, fbase + 2, 0x18); putb(g_font8x8, fbase + 3, 0x30);
    putb(g_font8x8, fbase + 4, 0x18); putb(g_font8x8, fbase + 5, 0x0C);
    putb(g_font8x8, fbase + 6, 0x06); putb(g_font8x8, fbase + 7, 0x00);

    // = (61)
    fbase = 232;
    putb(g_font8x8, fbase + 0, 0x00); putb(g_font8x8, fbase + 1, 0x00);
    putb(g_font8x8, fbase + 2, 0x7E); putb(g_font8x8, fbase + 3, 0x00);
    putb(g_font8x8, fbase + 4, 0x7E); putb(g_font8x8, fbase + 5, 0x00);
    putb(g_font8x8, fbase + 6, 0x00); putb(g_font8x8, fbase + 7, 0x00);

    // > (62)
    fbase = 240;
    putb(g_font8x8, fbase + 0, 0x60); putb(g_font8x8, fbase + 1, 0x30);
    putb(g_font8x8, fbase + 2, 0x18); putb(g_font8x8, fbase + 3, 0x0C);
    putb(g_font8x8, fbase + 4, 0x18); putb(g_font8x8, fbase + 5, 0x30);
    putb(g_font8x8, fbase + 6, 0x60); putb(g_font8x8, fbase + 7, 0x00);

    // ? (63)
    fbase = 248;
    putb(g_font8x8, fbase + 0, 0x3C); putb(g_font8x8, fbase + 1, 0x66);
    putb(g_font8x8, fbase + 2, 0x06); putb(g_font8x8, fbase + 3, 0x0C);
    putb(g_font8x8, fbase + 4, 0x18); putb(g_font8x8, fbase + 5, 0x00);
    putb(g_font8x8, fbase + 6, 0x18); putb(g_font8x8, fbase + 7, 0x00);

    // @ (64)
    fbase = 256;
    putb(g_font8x8, fbase + 0, 0x3C); putb(g_font8x8, fbase + 1, 0x42);
    putb(g_font8x8, fbase + 2, 0x5E); putb(g_font8x8, fbase + 3, 0x56);
    putb(g_font8x8, fbase + 4, 0x5E); putb(g_font8x8, fbase + 5, 0x40);
    putb(g_font8x8, fbase + 6, 0x3C); putb(g_font8x8, fbase + 7, 0x00);

    // A (65)
    fbase = 264;
    putb(g_font8x8, fbase + 0, 0x18); putb(g_font8x8, fbase + 1, 0x3C);
    putb(g_font8x8, fbase + 2, 0x66); putb(g_font8x8, fbase + 3, 0x66);
    putb(g_font8x8, fbase + 4, 0x7E); putb(g_font8x8, fbase + 5, 0x66);
    putb(g_font8x8, fbase + 6, 0x66); putb(g_font8x8, fbase + 7, 0x00);

    // B (66)
    fbase = 272;
    putb(g_font8x8, fbase + 0, 0x7C); putb(g_font8x8, fbase + 1, 0x66);
    putb(g_font8x8, fbase + 2, 0x66); putb(g_font8x8, fbase + 3, 0x7C);
    putb(g_font8x8, fbase + 4, 0x66); putb(g_font8x8, fbase + 5, 0x66);
    putb(g_font8x8, fbase + 6, 0x7C); putb(g_font8x8, fbase + 7, 0x00);

    // C (67)
    fbase = 280;
    putb(g_font8x8, fbase + 0, 0x3C); putb(g_font8x8, fbase + 1, 0x66);
    putb(g_font8x8, fbase + 2, 0x60); putb(g_font8x8, fbase + 3, 0x60);
    putb(g_font8x8, fbase + 4, 0x60); putb(g_font8x8, fbase + 5, 0x66);
    putb(g_font8x8, fbase + 6, 0x3C); putb(g_font8x8, fbase + 7, 0x00);

    // D (68)
    fbase = 288;
    putb(g_font8x8, fbase + 0, 0x78); putb(g_font8x8, fbase + 1, 0x6C);
    putb(g_font8x8, fbase + 2, 0x66); putb(g_font8x8, fbase + 3, 0x66);
    putb(g_font8x8, fbase + 4, 0x66); putb(g_font8x8, fbase + 5, 0x6C);
    putb(g_font8x8, fbase + 6, 0x78); putb(g_font8x8, fbase + 7, 0x00);

    // E (69)
    fbase = 296;
    putb(g_font8x8, fbase + 0, 0x7E); putb(g_font8x8, fbase + 1, 0x60);
    putb(g_font8x8, fbase + 2, 0x60); putb(g_font8x8, fbase + 3, 0x7C);
    putb(g_font8x8, fbase + 4, 0x60); putb(g_font8x8, fbase + 5, 0x60);
    putb(g_font8x8, fbase + 6, 0x7E); putb(g_font8x8, fbase + 7, 0x00);

    // F (70)
    fbase = 304;
    putb(g_font8x8, fbase + 0, 0x7E); putb(g_font8x8, fbase + 1, 0x60);
    putb(g_font8x8, fbase + 2, 0x60); putb(g_font8x8, fbase + 3, 0x7C);
    putb(g_font8x8, fbase + 4, 0x60); putb(g_font8x8, fbase + 5, 0x60);
    putb(g_font8x8, fbase + 6, 0x60); putb(g_font8x8, fbase + 7, 0x00);

    // G (71)
    fbase = 312;
    putb(g_font8x8, fbase + 0, 0x3C); putb(g_font8x8, fbase + 1, 0x66);
    putb(g_font8x8, fbase + 2, 0x60); putb(g_font8x8, fbase + 3, 0x6E);
    putb(g_font8x8, fbase + 4, 0x66); putb(g_font8x8, fbase + 5, 0x66);
    putb(g_font8x8, fbase + 6, 0x3E); putb(g_font8x8, fbase + 7, 0x00);

    // H (72)
    fbase = 320;
    putb(g_font8x8, fbase + 0, 0x66); putb(g_font8x8, fbase + 1, 0x66);
    putb(g_font8x8, fbase + 2, 0x66); putb(g_font8x8, fbase + 3, 0x7E);
    putb(g_font8x8, fbase + 4, 0x66); putb(g_font8x8, fbase + 5, 0x66);
    putb(g_font8x8, fbase + 6, 0x66); putb(g_font8x8, fbase + 7, 0x00);

    // I (73)
    fbase = 328;
    putb(g_font8x8, fbase + 0, 0x3C); putb(g_font8x8, fbase + 1, 0x18);
    putb(g_font8x8, fbase + 2, 0x18); putb(g_font8x8, fbase + 3, 0x18);
    putb(g_font8x8, fbase + 4, 0x18); putb(g_font8x8, fbase + 5, 0x18);
    putb(g_font8x8, fbase + 6, 0x3C); putb(g_font8x8, fbase + 7, 0x00);

    // J (74)
    fbase = 336;
    putb(g_font8x8, fbase + 0, 0x1E); putb(g_font8x8, fbase + 1, 0x06);
    putb(g_font8x8, fbase + 2, 0x06); putb(g_font8x8, fbase + 3, 0x06);
    putb(g_font8x8, fbase + 4, 0x46); putb(g_font8x8, fbase + 5, 0x66);
    putb(g_font8x8, fbase + 6, 0x3C); putb(g_font8x8, fbase + 7, 0x00);

    // K (75)
    fbase = 344;
    putb(g_font8x8, fbase + 0, 0x66); putb(g_font8x8, fbase + 1, 0x6C);
    putb(g_font8x8, fbase + 2, 0x78); putb(g_font8x8, fbase + 3, 0x70);
    putb(g_font8x8, fbase + 4, 0x78); putb(g_font8x8, fbase + 5, 0x6C);
    putb(g_font8x8, fbase + 6, 0x66); putb(g_font8x8, fbase + 7, 0x00);

    // L (76)
    fbase = 352;
    putb(g_font8x8, fbase + 0, 0x60); putb(g_font8x8, fbase + 1, 0x60);
    putb(g_font8x8, fbase + 2, 0x60); putb(g_font8x8, fbase + 3, 0x60);
    putb(g_font8x8, fbase + 4, 0x60); putb(g_font8x8, fbase + 5, 0x60);
    putb(g_font8x8, fbase + 6, 0x7E); putb(g_font8x8, fbase + 7, 0x00);

    // M (77)
    fbase = 360;
    putb(g_font8x8, fbase + 0, 0x63); putb(g_font8x8, fbase + 1, 0x77);
    putb(g_font8x8, fbase + 2, 0x7F); putb(g_font8x8, fbase + 3, 0x6B);
    putb(g_font8x8, fbase + 4, 0x63); putb(g_font8x8, fbase + 5, 0x63);
    putb(g_font8x8, fbase + 6, 0x63); putb(g_font8x8, fbase + 7, 0x00);

    // N (78)
    fbase = 368;
    putb(g_font8x8, fbase + 0, 0x66); putb(g_font8x8, fbase + 1, 0x76);
    putb(g_font8x8, fbase + 2, 0x7E); putb(g_font8x8, fbase + 3, 0x7E);
    putb(g_font8x8, fbase + 4, 0x6E); putb(g_font8x8, fbase + 5, 0x66);
    putb(g_font8x8, fbase + 6, 0x66); putb(g_font8x8, fbase + 7, 0x00);

    // O (79)
    fbase = 376;
    putb(g_font8x8, fbase + 0, 0x3C); putb(g_font8x8, fbase + 1, 0x66);
    putb(g_font8x8, fbase + 2, 0x66); putb(g_font8x8, fbase + 3, 0x66);
    putb(g_font8x8, fbase + 4, 0x66); putb(g_font8x8, fbase + 5, 0x66);
    putb(g_font8x8, fbase + 6, 0x3C); putb(g_font8x8, fbase + 7, 0x00);

    // P (80)
    fbase = 384;
    putb(g_font8x8, fbase + 0, 0x7C); putb(g_font8x8, fbase + 1, 0x66);
    putb(g_font8x8, fbase + 2, 0x66); putb(g_font8x8, fbase + 3, 0x7C);
    putb(g_font8x8, fbase + 4, 0x60); putb(g_font8x8, fbase + 5, 0x60);
    putb(g_font8x8, fbase + 6, 0x60); putb(g_font8x8, fbase + 7, 0x00);

    // Q (81)
    fbase = 392;
    putb(g_font8x8, fbase + 0, 0x3C); putb(g_font8x8, fbase + 1, 0x66);
    putb(g_font8x8, fbase + 2, 0x66); putb(g_font8x8, fbase + 3, 0x66);
    putb(g_font8x8, fbase + 4, 0x6A); putb(g_font8x8, fbase + 5, 0x6C);
    putb(g_font8x8, fbase + 6, 0x36); putb(g_font8x8, fbase + 7, 0x00);

    // R (82)
    fbase = 400;
    putb(g_font8x8, fbase + 0, 0x7C); putb(g_font8x8, fbase + 1, 0x66);
    putb(g_font8x8, fbase + 2, 0x66); putb(g_font8x8, fbase + 3, 0x7C);
    putb(g_font8x8, fbase + 4, 0x6C); putb(g_font8x8, fbase + 5, 0x66);
    putb(g_font8x8, fbase + 6, 0x66); putb(g_font8x8, fbase + 7, 0x00);

    // S (83)
    fbase = 408;
    putb(g_font8x8, fbase + 0, 0x3C); putb(g_font8x8, fbase + 1, 0x66);
    putb(g_font8x8, fbase + 2, 0x60); putb(g_font8x8, fbase + 3, 0x3C);
    putb(g_font8x8, fbase + 4, 0x06); putb(g_font8x8, fbase + 5, 0x66);
    putb(g_font8x8, fbase + 6, 0x3C); putb(g_font8x8, fbase + 7, 0x00);

    // T (84)
    fbase = 416;
    putb(g_font8x8, fbase + 0, 0x7E); putb(g_font8x8, fbase + 1, 0x18);
    putb(g_font8x8, fbase + 2, 0x18); putb(g_font8x8, fbase + 3, 0x18);
    putb(g_font8x8, fbase + 4, 0x18); putb(g_font8x8, fbase + 5, 0x18);
    putb(g_font8x8, fbase + 6, 0x18); putb(g_font8x8, fbase + 7, 0x00);

    // U (85)
    fbase = 424;
    putb(g_font8x8, fbase + 0, 0x66); putb(g_font8x8, fbase + 1, 0x66);
    putb(g_font8x8, fbase + 2, 0x66); putb(g_font8x8, fbase + 3, 0x66);
    putb(g_font8x8, fbase + 4, 0x66); putb(g_font8x8, fbase + 5, 0x66);
    putb(g_font8x8, fbase + 6, 0x3C); putb(g_font8x8, fbase + 7, 0x00);

    // V (86)
    fbase = 432;
    putb(g_font8x8, fbase + 0, 0x66); putb(g_font8x8, fbase + 1, 0x66);
    putb(g_font8x8, fbase + 2, 0x66); putb(g_font8x8, fbase + 3, 0x66);
    putb(g_font8x8, fbase + 4, 0x66); putb(g_font8x8, fbase + 5, 0x3C);
    putb(g_font8x8, fbase + 6, 0x18); putb(g_font8x8, fbase + 7, 0x00);

    // W (87)
    fbase = 440;
    putb(g_font8x8, fbase + 0, 0x63); putb(g_font8x8, fbase + 1, 0x63);
    putb(g_font8x8, fbase + 2, 0x63); putb(g_font8x8, fbase + 3, 0x6B);
    putb(g_font8x8, fbase + 4, 0x7F); putb(g_font8x8, fbase + 5, 0x77);
    putb(g_font8x8, fbase + 6, 0x63); putb(g_font8x8, fbase + 7, 0x00);

    // X (88)
    fbase = 448;
    putb(g_font8x8, fbase + 0, 0x66); putb(g_font8x8, fbase + 1, 0x66);
    putb(g_font8x8, fbase + 2, 0x3C); putb(g_font8x8, fbase + 3, 0x18);
    putb(g_font8x8, fbase + 4, 0x3C); putb(g_font8x8, fbase + 5, 0x66);
    putb(g_font8x8, fbase + 6, 0x66); putb(g_font8x8, fbase + 7, 0x00);

    // Y (89)
    fbase = 456;
    putb(g_font8x8, fbase + 0, 0x66); putb(g_font8x8, fbase + 1, 0x66);
    putb(g_font8x8, fbase + 2, 0x66); putb(g_font8x8, fbase + 3, 0x3C);
    putb(g_font8x8, fbase + 4, 0x18); putb(g_font8x8, fbase + 5, 0x18);
    putb(g_font8x8, fbase + 6, 0x18); putb(g_font8x8, fbase + 7, 0x00);

    // Z (90)
    fbase = 464;
    putb(g_font8x8, fbase + 0, 0x7E); putb(g_font8x8, fbase + 1, 0x06);
    putb(g_font8x8, fbase + 2, 0x0C); putb(g_font8x8, fbase + 3, 0x18);
    putb(g_font8x8, fbase + 4, 0x30); putb(g_font8x8, fbase + 5, 0x60);
    putb(g_font8x8, fbase + 6, 0x7E); putb(g_font8x8, fbase + 7, 0x00);

    // [ (91)
    fbase = 472;
    putb(g_font8x8, fbase + 0, 0x3C); putb(g_font8x8, fbase + 1, 0x30);
    putb(g_font8x8, fbase + 2, 0x30); putb(g_font8x8, fbase + 3, 0x30);
    putb(g_font8x8, fbase + 4, 0x30); putb(g_font8x8, fbase + 5, 0x30);
    putb(g_font8x8, fbase + 6, 0x3C); putb(g_font8x8, fbase + 7, 0x00);

    // \ (92)
    fbase = 480;
    putb(g_font8x8, fbase + 0, 0x40); putb(g_font8x8, fbase + 1, 0x20);
    putb(g_font8x8, fbase + 2, 0x10); putb(g_font8x8, fbase + 3, 0x08);
    putb(g_font8x8, fbase + 4, 0x04); putb(g_font8x8, fbase + 5, 0x02);
    putb(g_font8x8, fbase + 6, 0x00); putb(g_font8x8, fbase + 7, 0x00);

    // ] (93)
    fbase = 488;
    putb(g_font8x8, fbase + 0, 0x3C); putb(g_font8x8, fbase + 1, 0x0C);
    putb(g_font8x8, fbase + 2, 0x0C); putb(g_font8x8, fbase + 3, 0x0C);
    putb(g_font8x8, fbase + 4, 0x0C); putb(g_font8x8, fbase + 5, 0x0C);
    putb(g_font8x8, fbase + 6, 0x3C); putb(g_font8x8, fbase + 7, 0x00);

    // ^ (94)
    fbase = 496;
    putb(g_font8x8, fbase + 0, 0x18); putb(g_font8x8, fbase + 1, 0x3C);
    putb(g_font8x8, fbase + 2, 0x66); putb(g_font8x8, fbase + 3, 0x00);
    putb(g_font8x8, fbase + 4, 0x00); putb(g_font8x8, fbase + 5, 0x00);
    putb(g_font8x8, fbase + 6, 0x00); putb(g_font8x8, fbase + 7, 0x00);

    // _ (95)
    fbase = 504;
    putb(g_font8x8, fbase + 0, 0x00); putb(g_font8x8, fbase + 1, 0x00);
    putb(g_font8x8, fbase + 2, 0x00); putb(g_font8x8, fbase + 3, 0x00);
    putb(g_font8x8, fbase + 4, 0x00); putb(g_font8x8, fbase + 5, 0x00);
    putb(g_font8x8, fbase + 6, 0x7E); putb(g_font8x8, fbase + 7, 0x00);

    // ` (96)
    fbase = 512;
    putb(g_font8x8, fbase + 0, 0x30); putb(g_font8x8, fbase + 1, 0x18);
    putb(g_font8x8, fbase + 2, 0x0C); putb(g_font8x8, fbase + 3, 0x00);
    putb(g_font8x8, fbase + 4, 0x00); putb(g_font8x8, fbase + 5, 0x00);
    putb(g_font8x8, fbase + 6, 0x00); putb(g_font8x8, fbase + 7, 0x00);

    // a (97)
    fbase = 520;
    putb(g_font8x8, fbase + 0, 0x00); putb(g_font8x8, fbase + 1, 0x00);
    putb(g_font8x8, fbase + 2, 0x3C); putb(g_font8x8, fbase + 3, 0x06);
    putb(g_font8x8, fbase + 4, 0x3E); putb(g_font8x8, fbase + 5, 0x66);
    putb(g_font8x8, fbase + 6, 0x3E); putb(g_font8x8, fbase + 7, 0x00);

    // b (98)
    fbase = 528;
    putb(g_font8x8, fbase + 0, 0x60); putb(g_font8x8, fbase + 1, 0x60);
    putb(g_font8x8, fbase + 2, 0x7C); putb(g_font8x8, fbase + 3, 0x66);
    putb(g_font8x8, fbase + 4, 0x66); putb(g_font8x8, fbase + 5, 0x66);
    putb(g_font8x8, fbase + 6, 0x7C); putb(g_font8x8, fbase + 7, 0x00);

    // c (99)
    fbase = 536;
    putb(g_font8x8, fbase + 0, 0x00); putb(g_font8x8, fbase + 1, 0x00);
    putb(g_font8x8, fbase + 2, 0x3C); putb(g_font8x8, fbase + 3, 0x60);
    putb(g_font8x8, fbase + 4, 0x60); putb(g_font8x8, fbase + 5, 0x60);
    putb(g_font8x8, fbase + 6, 0x3C); putb(g_font8x8, fbase + 7, 0x00);

    // d (100)
    fbase = 544;
    putb(g_font8x8, fbase + 0, 0x06); putb(g_font8x8, fbase + 1, 0x06);
    putb(g_font8x8, fbase + 2, 0x3E); putb(g_font8x8, fbase + 3, 0x66);
    putb(g_font8x8, fbase + 4, 0x66); putb(g_font8x8, fbase + 5, 0x66);
    putb(g_font8x8, fbase + 6, 0x3E); putb(g_font8x8, fbase + 7, 0x00);

    // e (101)
    fbase = 552;
    putb(g_font8x8, fbase + 0, 0x00); putb(g_font8x8, fbase + 1, 0x00);
    putb(g_font8x8, fbase + 2, 0x3C); putb(g_font8x8, fbase + 3, 0x66);
    putb(g_font8x8, fbase + 4, 0x7E); putb(g_font8x8, fbase + 5, 0x60);
    putb(g_font8x8, fbase + 6, 0x3C); putb(g_font8x8, fbase + 7, 0x00);

    // f (102)
    fbase = 560;
    putb(g_font8x8, fbase + 0, 0x1C); putb(g_font8x8, fbase + 1, 0x30);
    putb(g_font8x8, fbase + 2, 0x7C); putb(g_font8x8, fbase + 3, 0x30);
    putb(g_font8x8, fbase + 4, 0x30); putb(g_font8x8, fbase + 5, 0x30);
    putb(g_font8x8, fbase + 6, 0x30); putb(g_font8x8, fbase + 7, 0x00);

    // g (103)
    fbase = 568;
    putb(g_font8x8, fbase + 0, 0x00); putb(g_font8x8, fbase + 1, 0x00);
    putb(g_font8x8, fbase + 2, 0x3E); putb(g_font8x8, fbase + 3, 0x66);
    putb(g_font8x8, fbase + 4, 0x66); putb(g_font8x8, fbase + 5, 0x3E);
    putb(g_font8x8, fbase + 6, 0x06); putb(g_font8x8, fbase + 7, 0x3C);

    // h (104)
    fbase = 576;
    putb(g_font8x8, fbase + 0, 0x60); putb(g_font8x8, fbase + 1, 0x60);
    putb(g_font8x8, fbase + 2, 0x7C); putb(g_font8x8, fbase + 3, 0x66);
    putb(g_font8x8, fbase + 4, 0x66); putb(g_font8x8, fbase + 5, 0x66);
    putb(g_font8x8, fbase + 6, 0x66); putb(g_font8x8, fbase + 7, 0x00);

    // i (105)
    fbase = 584;
    putb(g_font8x8, fbase + 0, 0x18); putb(g_font8x8, fbase + 1, 0x00);
    putb(g_font8x8, fbase + 2, 0x38); putb(g_font8x8, fbase + 3, 0x18);
    putb(g_font8x8, fbase + 4, 0x18); putb(g_font8x8, fbase + 5, 0x18);
    putb(g_font8x8, fbase + 6, 0x3C); putb(g_font8x8, fbase + 7, 0x00);

    // j (106)
    fbase = 592;
    putb(g_font8x8, fbase + 0, 0x0C); putb(g_font8x8, fbase + 1, 0x00);
    putb(g_font8x8, fbase + 2, 0x1C); putb(g_font8x8, fbase + 3, 0x0C);
    putb(g_font8x8, fbase + 4, 0x0C); putb(g_font8x8, fbase + 5, 0x0C);
    putb(g_font8x8, fbase + 6, 0x4C); putb(g_font8x8, fbase + 7, 0x38);

    // k (107)
    fbase = 600;
    putb(g_font8x8, fbase + 0, 0x60); putb(g_font8x8, fbase + 1, 0x60);
    putb(g_font8x8, fbase + 2, 0x66); putb(g_font8x8, fbase + 3, 0x6C);
    putb(g_font8x8, fbase + 4, 0x78); putb(g_font8x8, fbase + 5, 0x6C);
    putb(g_font8x8, fbase + 6, 0x66); putb(g_font8x8, fbase + 7, 0x00);

    // l (108)
    fbase = 608;
    putb(g_font8x8, fbase + 0, 0x38); putb(g_font8x8, fbase + 1, 0x18);
    putb(g_font8x8, fbase + 2, 0x18); putb(g_font8x8, fbase + 3, 0x18);
    putb(g_font8x8, fbase + 4, 0x18); putb(g_font8x8, fbase + 5, 0x18);
    putb(g_font8x8, fbase + 6, 0x3C); putb(g_font8x8, fbase + 7, 0x00);

    // m (109)
    fbase = 616;
    putb(g_font8x8, fbase + 0, 0x00); putb(g_font8x8, fbase + 1, 0x00);
    putb(g_font8x8, fbase + 2, 0x76); putb(g_font8x8, fbase + 3, 0x7F);
    putb(g_font8x8, fbase + 4, 0x6B); putb(g_font8x8, fbase + 5, 0x63);
    putb(g_font8x8, fbase + 6, 0x63); putb(g_font8x8, fbase + 7, 0x00);

    // n (110)
    fbase = 624;
    putb(g_font8x8, fbase + 0, 0x00); putb(g_font8x8, fbase + 1, 0x00);
    putb(g_font8x8, fbase + 2, 0x7C); putb(g_font8x8, fbase + 3, 0x66);
    putb(g_font8x8, fbase + 4, 0x66); putb(g_font8x8, fbase + 5, 0x66);
    putb(g_font8x8, fbase + 6, 0x66); putb(g_font8x8, fbase + 7, 0x00);

    // o (111)
    fbase = 632;
    putb(g_font8x8, fbase + 0, 0x00); putb(g_font8x8, fbase + 1, 0x00);
    putb(g_font8x8, fbase + 2, 0x3C); putb(g_font8x8, fbase + 3, 0x66);
    putb(g_font8x8, fbase + 4, 0x66); putb(g_font8x8, fbase + 5, 0x66);
    putb(g_font8x8, fbase + 6, 0x3C); putb(g_font8x8, fbase + 7, 0x00);

    // p (112)
    fbase = 640;
    putb(g_font8x8, fbase + 0, 0x00); putb(g_font8x8, fbase + 1, 0x00);
    putb(g_font8x8, fbase + 2, 0x7C); putb(g_font8x8, fbase + 3, 0x66);
    putb(g_font8x8, fbase + 4, 0x66); putb(g_font8x8, fbase + 5, 0x7C);
    putb(g_font8x8, fbase + 6, 0x60); putb(g_font8x8, fbase + 7, 0x60);

    // q (113)
    fbase = 648;
    putb(g_font8x8, fbase + 0, 0x00); putb(g_font8x8, fbase + 1, 0x00);
    putb(g_font8x8, fbase + 2, 0x3E); putb(g_font8x8, fbase + 3, 0x66);
    putb(g_font8x8, fbase + 4, 0x66); putb(g_font8x8, fbase + 5, 0x3E);
    putb(g_font8x8, fbase + 6, 0x06); putb(g_font8x8, fbase + 7, 0x06);

    // r (114)
    fbase = 656;
    putb(g_font8x8, fbase + 0, 0x00); putb(g_font8x8, fbase + 1, 0x00);
    putb(g_font8x8, fbase + 2, 0x6C); putb(g_font8x8, fbase + 3, 0x76);
    putb(g_font8x8, fbase + 4, 0x60); putb(g_font8x8, fbase + 5, 0x60);
    putb(g_font8x8, fbase + 6, 0x60); putb(g_font8x8, fbase + 7, 0x00);

    // s (115)
    fbase = 664;
    putb(g_font8x8, fbase + 0, 0x00); putb(g_font8x8, fbase + 1, 0x00);
    putb(g_font8x8, fbase + 2, 0x3E); putb(g_font8x8, fbase + 3, 0x60);
    putb(g_font8x8, fbase + 4, 0x3C); putb(g_font8x8, fbase + 5, 0x06);
    putb(g_font8x8, fbase + 6, 0x7C); putb(g_font8x8, fbase + 7, 0x00);

    // t (116)
    fbase = 672;
    putb(g_font8x8, fbase + 0, 0x30); putb(g_font8x8, fbase + 1, 0x30);
    putb(g_font8x8, fbase + 2, 0x7C); putb(g_font8x8, fbase + 3, 0x30);
    putb(g_font8x8, fbase + 4, 0x30); putb(g_font8x8, fbase + 5, 0x30);
    putb(g_font8x8, fbase + 6, 0x1C); putb(g_font8x8, fbase + 7, 0x00);

    // u (117)
    fbase = 680;
    putb(g_font8x8, fbase + 0, 0x00); putb(g_font8x8, fbase + 1, 0x00);
    putb(g_font8x8, fbase + 2, 0x66); putb(g_font8x8, fbase + 3, 0x66);
    putb(g_font8x8, fbase + 4, 0x66); putb(g_font8x8, fbase + 5, 0x66);
    putb(g_font8x8, fbase + 6, 0x3E); putb(g_font8x8, fbase + 7, 0x00);

    // v (118)
    fbase = 688;
    putb(g_font8x8, fbase + 0, 0x00); putb(g_font8x8, fbase + 1, 0x00);
    putb(g_font8x8, fbase + 2, 0x66); putb(g_font8x8, fbase + 3, 0x66);
    putb(g_font8x8, fbase + 4, 0x66); putb(g_font8x8, fbase + 5, 0x3C);
    putb(g_font8x8, fbase + 6, 0x18); putb(g_font8x8, fbase + 7, 0x00);

    // w (119)
    fbase = 696;
    putb(g_font8x8, fbase + 0, 0x00); putb(g_font8x8, fbase + 1, 0x00);
    putb(g_font8x8, fbase + 2, 0x63); putb(g_font8x8, fbase + 3, 0x6B);
    putb(g_font8x8, fbase + 4, 0x7F); putb(g_font8x8, fbase + 5, 0x36);
    putb(g_font8x8, fbase + 6, 0x22); putb(g_font8x8, fbase + 7, 0x00);

    // x (120)
    fbase = 704;
    putb(g_font8x8, fbase + 0, 0x00); putb(g_font8x8, fbase + 1, 0x00);
    putb(g_font8x8, fbase + 2, 0x66); putb(g_font8x8, fbase + 3, 0x3C);
    putb(g_font8x8, fbase + 4, 0x18); putb(g_font8x8, fbase + 5, 0x3C);
    putb(g_font8x8, fbase + 6, 0x66); putb(g_font8x8, fbase + 7, 0x00);

    // y (121)
    fbase = 712;
    putb(g_font8x8, fbase + 0, 0x00); putb(g_font8x8, fbase + 1, 0x00);
    putb(g_font8x8, fbase + 2, 0x66); putb(g_font8x8, fbase + 3, 0x66);
    putb(g_font8x8, fbase + 4, 0x66); putb(g_font8x8, fbase + 5, 0x3E);
    putb(g_font8x8, fbase + 6, 0x06); putb(g_font8x8, fbase + 7, 0x3C);

    // z (122)
    fbase = 720;
    putb(g_font8x8, fbase + 0, 0x00); putb(g_font8x8, fbase + 1, 0x00);
    putb(g_font8x8, fbase + 2, 0x7E); putb(g_font8x8, fbase + 3, 0x0C);
    putb(g_font8x8, fbase + 4, 0x18); putb(g_font8x8, fbase + 5, 0x30);
    putb(g_font8x8, fbase + 6, 0x7E); putb(g_font8x8, fbase + 7, 0x00);

    // { (123)
    fbase = 728;
    putb(g_font8x8, fbase + 0, 0x0E); putb(g_font8x8, fbase + 1, 0x18);
    putb(g_font8x8, fbase + 2, 0x18); putb(g_font8x8, fbase + 3, 0x70);
    putb(g_font8x8, fbase + 4, 0x18); putb(g_font8x8, fbase + 5, 0x18);
    putb(g_font8x8, fbase + 6, 0x0E); putb(g_font8x8, fbase + 7, 0x00);

    // | (124)
    fbase = 736;
    putb(g_font8x8, fbase + 0, 0x18); putb(g_font8x8, fbase + 1, 0x18);
    putb(g_font8x8, fbase + 2, 0x18); putb(g_font8x8, fbase + 3, 0x18);
    putb(g_font8x8, fbase + 4, 0x18); putb(g_font8x8, fbase + 5, 0x18);
    putb(g_font8x8, fbase + 6, 0x18); putb(g_font8x8, fbase + 7, 0x00);

    // } (125)
    fbase = 744;
    putb(g_font8x8, fbase + 0, 0x70); putb(g_font8x8, fbase + 1, 0x18);
    putb(g_font8x8, fbase + 2, 0x18); putb(g_font8x8, fbase + 3, 0x0E);
    putb(g_font8x8, fbase + 4, 0x18); putb(g_font8x8, fbase + 5, 0x18);
    putb(g_font8x8, fbase + 6, 0x70); putb(g_font8x8, fbase + 7, 0x00);

    // ~ (126)
    fbase = 752;
    putb(g_font8x8, fbase + 0, 0x00); putb(g_font8x8, fbase + 1, 0x00);
    putb(g_font8x8, fbase + 2, 0x31); putb(g_font8x8, fbase + 3, 0x6B);
    putb(g_font8x8, fbase + 4, 0x46); putb(g_font8x8, fbase + 5, 0x00);
    putb(g_font8x8, fbase + 6, 0x00); putb(g_font8x8, fbase + 7, 0x00);
}

// ---------------------------------------------------------------------------
// draw_char -- رسم حرف واحد (8x8 بكسل)
// Draw a single ASCII character at position (px, py).
// Uses the embedded 8x8 bitmap font.
// ---------------------------------------------------------------------------
fn draw_char(int px, int py, int ch, int color) -> void {
    // Only printable ASCII (32-126)
    if (ch < 32) { return; }
    if (ch > 126) { return; }

    int idx = ch - 32;
    int fbase = idx * 8;

    int row = 0;
    while (row < 8) {
        int bits = getb(g_font8x8, fbase + row);
        int col = 0;
        while (col < 8) {
            // MSB = leftmost pixel
            // Check if bit (7-col) is set
            int mask = 128;
            int shift = col;
            while (shift > 0) {
                mask = mask / 2;
                shift = shift - 1;
            }
            if ((bits / mask) - ((bits / mask) / 2) * 2 != 0) {
                fb_put_pixel(px + col, py + row, color);
            }
            col = col + 1;
        }
        row = row + 1;
    }
}

// Nearest-neighbor bitmap scaling. Scale 1 preserves the original 8x8 font;
// scales 2-4 make headings readable on larger displays.
fn draw_char_scale(int px, int py, int ch, int scale, int color) -> void {
    if (ch < 32) { return; }
    if (ch > 126) { return; }
    if (scale < 1) { scale = 1; }
    if (scale > 4) { scale = 4; }
    int row = 0;
    while (row < 8) {
        int bits = getb(g_font8x8, (ch - 32) * 8 + row);
        int col = 0;
        while (col < 8) {
            int mask = 128;
            int shift = col;
            while (shift > 0) { mask = mask / 2; shift = shift - 1; }
            if ((bits / mask) - ((bits / mask) / 2) * 2 != 0) {
                draw_filled_rect(px + col * scale, py + row * scale, scale, scale, color);
            }
            col = col + 1;
        }
        row = row + 1;
    }
}

fn draw_text_width(char* text, int scale) -> int {
    if (scale < 1) { scale = 1; }
    if (scale > 4) { scale = 4; }
    return name_len(text) * 8 * scale;
}

fn draw_string_scale(int px, int py, char* text, int scale, int color) -> void {
    if (scale < 1) { scale = 1; }
    if (scale > 4) { scale = 4; }
    int i = 0;
    while (bval(*(text + i)) != 0) {
        draw_char_scale(px + i * 8 * scale, py, bval(*(text + i)), scale, color);
        i = i + 1;
    }
}

fn draw_string_centered(int center_x, int y, char* text, int scale, int color) -> void {
    int width = draw_text_width(text, scale);
    draw_string_scale(center_x - width / 2, y, text, scale, color);
}

fn draw_string_right(int right_x, int y, char* text, int scale, int color) -> void {
    int width = draw_text_width(text, scale);
    draw_string_scale(right_x - width, y, text, scale, color);
}

// Draw only whole characters that fit inside max_width.
fn draw_string_clipped(int px, int py, char* text, int max_width, int color) -> void {
    if (max_width <= 0) { return; }
    int max_chars = max_width / 8;
    int i = 0;
    while (i < max_chars && bval(*(text + i)) != 0) {
        draw_char(px + i * 8, py, bval(*(text + i)), color);
        i = i + 1;
    }
}

// Draw a horizontally scrolled text window beginning at a character offset.
fn draw_string_window(int px, int py, char* text, int start_char, int max_width, int color) -> void {
    if (start_char < 0) { start_char = 0; }
    if (max_width <= 0) { return; }
    int max_chars = max_width / 8;
    int i = 0;
    while (i < max_chars && bval(*(text + start_char + i)) != 0) {
        draw_char(px + i * 8, py, bval(*(text + start_char + i)), color);
        i = i + 1;
    }
}

// ---------------------------------------------------------------------------
// draw_char_bg -- رسم حرف مع خلفية ملونة
// Draw a character with a background color (useful for text inputs).
// ---------------------------------------------------------------------------
fn draw_char_bg(int px, int py, int ch, int fg, int bg) -> void {
    if (ch < 32) { return; }
    if (ch > 126) { return; }

    int idx = ch - 32;
    int fbase = idx * 8;

    int row = 0;
    while (row < 8) {
        int bits = getb(g_font8x8, fbase + row);
        int col = 0;
        while (col < 8) {
            int mask = 128;
            int shift = col;
            while (shift > 0) {
                mask = mask / 2;
                shift = shift - 1;
            }
            if ((bits / mask) - ((bits / mask) / 2) * 2 != 0) {
                fb_put_pixel(px + col, py + row, fg);
            } else {
                fb_put_pixel(px + col, py + row, bg);
            }
            col = col + 1;
        }
        row = row + 1;
    }
}

// ---------------------------------------------------------------------------
// draw_string -- رسم سلسلة نصية
// Draw a null-terminated string starting at (px, py).
// Each character is 8 pixels wide.
// ---------------------------------------------------------------------------
fn draw_string(int px, int py, char* str, int color) -> void {
    int i = 0;
    while (bval(*(str + i)) != 0) {
        int ch = bval(*(str + i));
        draw_char(px + i * 8, py, ch, color);
        i = i + 1;
    }
}

// ---------------------------------------------------------------------------
// draw_string_bg -- رسم سلسلة نصية مع خلفية
// Draw a string with foreground and background colors.
// ---------------------------------------------------------------------------
fn draw_string_bg(int px, int py, char* str, int fg, int bg) -> void {
    int i = 0;
    while (bval(*(str + i)) != 0) {
        int ch = bval(*(str + i));
        draw_char_bg(px + i * 8, py, ch, fg, bg);
        i = i + 1;
    }
}

// ---------------------------------------------------------------------------
// draw_string_len -- رسم عدد محدد من الحروف
// Draw exactly `len` characters from a string.
// ---------------------------------------------------------------------------
fn draw_string_len(int px, int py, char* str, int len, int color) -> void {
    int i = 0;
    while (i < len) {
        int ch = bval(*(str + i));
        if (ch == 0) { return; }
        draw_char(px + i * 8, py, ch, color);
        i = i + 1;
    }
}

// ---------------------------------------------------------------------------
// gfx_string_width -- حساب عرض النص بالبكسل
// Calculate the pixel width of a null-terminated string (8px per char).
// ---------------------------------------------------------------------------
fn gfx_string_width(char* str) -> int {
    return name_len(str) * 8;
}
