// window_manager.mg -- الوحدة 3: إدارة النوافذ (Window Manager)
// BlackhatOS GUI Core - Compositing window manager
//
// This module provides:
//   - Window struct management (position, size, title, z-order)
//   - Window creation and destruction
//   - Window rendering with title bar, close button, borders
//   - Compositing (drawing all windows in z-order)
//   - Window focus management and dragging
//
// No libc: all syscalls via magc trampolines.

extern fn sys_mmap(char* addr, int length, int prot, int flags, int fd, int offset) -> int;
extern fn sys_write(int fd, char* data, int count) -> int;

// ---------------------------------------------------------------------------
// External dependencies
// ---------------------------------------------------------------------------
extern fn bval(int v) -> int;
extern fn putb(char* p, int off, int v) -> void;
extern fn getb(char* p, int off) -> int;
extern fn putd(char* p, int off, int v) -> void;
extern fn getd(char* p, int off) -> int;
extern fn putq(char* p, int off, int v) -> void;
extern fn getq(char* p, int off) -> int;
extern fn name_len(char* p) -> int;
extern fn copy_str(char* dst, int doff, char* src) -> int;

// from fb_hal.mg
extern fn fb_put_pixel(int x, int y, int color) -> void;
extern fn fb_get_width() -> int;
extern fn fb_get_height() -> int;
extern fn fb_clear(int color) -> void;
extern fn fb_flip() -> void;
extern fn rgb_pack(int r, int g, int b) -> int;

// from gfx_primitives.mg
extern fn draw_filled_rect(int x, int y, int w, int h, int color) -> void;
extern fn draw_rect(int x, int y, int w, int h, int color) -> void;
extern fn draw_line(int x0, int y0, int x1, int y1, int color) -> void;
extern fn draw_string(int px, int py, char* str, int color) -> void;
extern fn draw_string_bg(int px, int py, char* str, int fg, int bg) -> void;
extern fn draw_filled_circle(int cx, int cy, int r, int color) -> void;
extern fn draw_hline(int x0, int x1, int y, int color) -> void;
extern fn draw_rounded_rect(int rx, int ry, int rw, int rh, int rad, int color) -> void;

// from widgets.mg -- نسمة الرسم تتم داخل wm_draw_window حتى تحترم ترتيب z
extern fn wdg_draw_all_for_window(int win_idx, int win_x, int win_y) -> void;

// ---------------------------------------------------------------------------
// Window structure layout (stored as flat memory, 128 bytes per window)
// ---------------------------------------------------------------------------
// Offset   Field           Size   Description
//    0     x               4      عرض الإحداثي X
//    4     y               4      عرض الإحداثي Y
//    8     width           4      عرض النافذة
//   12     height          4      ارتفاع النافذة
//   16     focused         4      حالة التركيز (1=مركزة)
//   20     visible         4      حالة الظهور (1=مرئية)
//   24     flags           4      أعلام إضافية
//   28     z_order         4      ترتيب العمق
//   32     title_ptr       8      مؤشر العنوان (char*)
//   40     bg_color        4      لون الخلفية
//   44     title_bg_color  4      لون شريط العنوان
//   48     border_color    4      لون الإطار
//   52     content_buf     8      مؤشر المحتوى المؤقت (للرسم الفرعي)
//   60     id              4      معرف النافذة
//   64-127 reserved               محجوز للمستقبل

// Constants
// TITLE_BAR_HEIGHT = 24 -- ارتفاع شريط العنوان
// CLOSE_BTN_SIZE = 16 -- حجم زر الإغلاق
// BORDER_WIDTH = 2 -- عرض الإطار
// MAX_WINDOWS = 32 -- الحد الأقصى للنوافذ

// ---------------------------------------------------------------------------
// Globals
// ---------------------------------------------------------------------------
static char* g_wm_windows;       // مصفوفة النوافذ (32 نافذة × 128 بايت)
static int g_wm_count;           // عدد النوافذ النشطة
static int g_wm_focus;           // فهرس النافذة المركزة (-1 = لا شيء)
static int g_wm_next_id;         // المعرف التالي
static int g_wm_drag;            // هل يتم سحب نافذة؟ (1=نعم)
static int g_wm_drag_idx;        // فهرس النافذة المسحوبة
static int g_wm_drag_ox;         // إزاحة السحب X
static int g_wm_drag_oy;         // إزاحة السحب Y
static int g_wm_dirty;           // هل نحتاج إعادة رسم؟ (1=نعم)
static char* g_wm_order;         // مخزن ترتيب العمق (يُخصَّص مرة واحدة في wm_init)

// Desktop color palette -- ألوان سطح المكتب
static int g_clr_desktop;        // لون الخلفية
static int g_clr_titlebar;       // لون شريط العنوان (نافذة مركزة)
static int g_clr_titlebar_blur;  // لون شريط العنوان (نافذة غير مركزة)
static int g_clr_close_btn;      // لون زر الإغلاق
static int g_clr_close_hover;    // لون زر الإغلاق عند التمرير
static int g_clr_border;         // لون الإطار
static int g_clr_win_bg;         // لون خلفية النافذة
static int g_clr_text;           // لون النص
static int g_clr_text_dim;       // لون النص الخافت
static int g_clr_taskbar;        // لون شريط المهام

// ---------------------------------------------------------------------------
// wm_init -- تهيئة مدير النوافذ
// Initialize the window manager: allocate window table, set colors.
// ---------------------------------------------------------------------------
fn wm_init() -> void {
    // Allocate window table: 32 windows * 128 bytes = 4096 bytes
    g_wm_windows = cast<char*>(sys_mmap(0, 4096, 3, 34, -1, 0));
    // z-order scratch: 32 * 4 bytes.  Allocated exactly once - an earlier
    // revision mmap'd 256 bytes on EVERY frame, which leaks ~4K per frame
    // (a gigabyte after ~70 minutes at 60 fps).
    if (g_wm_order == cast<char*>(0)) {
        g_wm_order = cast<char*>(sys_mmap(0, 4096, 3, 34, -1, 0));
    }
    g_wm_count = 0;
    g_wm_focus = -1;
    g_wm_next_id = 1;
    g_wm_drag = 0;
    g_wm_drag_idx = -1;
    g_wm_dirty = 1;

    // Set default color palette -- ألوان افتراضية أنيقة
    // Dark theme inspired by modern Linux desktop environments
    g_clr_desktop = rgb_pack(25, 25, 35);          // خلفية داكنة مع لمسة زرقاء
    g_clr_titlebar = rgb_pack(55, 90, 160);         // شريط عنوان أزرق غامق
    g_clr_titlebar_blur = rgb_pack(60, 60, 70);     // شريط عنوان رمادي للنوافذ غير المركزة
    g_clr_close_btn = rgb_pack(220, 60, 60);        // أحمر لزر الإغلاق
    g_clr_close_hover = rgb_pack(255, 80, 80);      // أحمر فاتح عند التمرير
    g_clr_border = rgb_pack(70, 70, 90);            // إطار رمادي-أزرق
    g_clr_win_bg = rgb_pack(35, 35, 45);            // خلفية النافذة
    g_clr_text = rgb_pack(230, 230, 240);           // نص أبيض
    g_clr_text_dim = rgb_pack(140, 140, 160);       // نص خافت
    g_clr_taskbar = rgb_pack(20, 20, 30);           // شريط المهام
}

// ---------------------------------------------------------------------------
// wm_set_theme -- تبديل المظهر (0 = داكن، 1 = فاتح)
// Swap the whole desktop palette and mark everything dirty.  Owned here so
// widgets that share these colors (drawn via wm) stay consistent.
// ---------------------------------------------------------------------------
fn wm_set_theme(int theme) -> void {
    if (theme == 1) {
        // Light theme -- مظهر فاتح
        g_clr_desktop = rgb_pack(220, 225, 235);
        g_clr_titlebar = rgb_pack(70, 120, 200);
        g_clr_titlebar_blur = rgb_pack(190, 195, 205);
        g_clr_close_btn = rgb_pack(220, 60, 60);
        g_clr_close_hover = rgb_pack(255, 80, 80);
        g_clr_border = rgb_pack(150, 155, 170);
        g_clr_win_bg = rgb_pack(245, 246, 250);
        g_clr_text = rgb_pack(30, 30, 40);
        g_clr_text_dim = rgb_pack(90, 95, 110);
        g_clr_taskbar = rgb_pack(205, 210, 220);
    } else {
        // Dark theme -- مظهر داكن (الافتراضي)
        g_clr_desktop = rgb_pack(25, 25, 35);
        g_clr_titlebar = rgb_pack(55, 90, 160);
        g_clr_titlebar_blur = rgb_pack(60, 60, 70);
        g_clr_close_btn = rgb_pack(220, 60, 60);
        g_clr_close_hover = rgb_pack(255, 80, 80);
        g_clr_border = rgb_pack(70, 70, 90);
        g_clr_win_bg = rgb_pack(35, 35, 45);
        g_clr_text = rgb_pack(230, 230, 240);
        g_clr_text_dim = rgb_pack(140, 140, 160);
        g_clr_taskbar = rgb_pack(20, 20, 30);
    }
    // Re-point the window background of every live window too.
    int i = 0;
    while (i < g_wm_count) {
        wm_set_bg(i, g_clr_win_bg);
        i = i + 1;
    }
    g_wm_dirty = 1;
}

// ---------------------------------------------------------------------------
// wm_set_dirty -- تعيين علامة إعادة الرسم
// ---------------------------------------------------------------------------
fn wm_set_dirty() -> void {
    g_wm_dirty = 1;
}

fn wm_is_dirty() -> int {
    return g_wm_dirty;
}

fn wm_clear_dirty() -> void {
    g_wm_dirty = 0;
}

// ---------------------------------------------------------------------------
// Window field accessors -- دوال الوصول لحقول النافذة
// ---------------------------------------------------------------------------
fn wm_get_x(int idx) -> int { return getd(g_wm_windows, idx * 128 + 0); }
fn wm_get_y(int idx) -> int { return getd(g_wm_windows, idx * 128 + 4); }
fn wm_get_w(int idx) -> int { return getd(g_wm_windows, idx * 128 + 8); }
fn wm_get_h(int idx) -> int { return getd(g_wm_windows, idx * 128 + 12); }
fn wm_get_focused(int idx) -> int { return getd(g_wm_windows, idx * 128 + 16); }
fn wm_get_visible(int idx) -> int { return getd(g_wm_windows, idx * 128 + 20); }
fn wm_get_flags(int idx) -> int { return getd(g_wm_windows, idx * 128 + 24); }
fn wm_get_zorder(int idx) -> int { return getd(g_wm_windows, idx * 128 + 28); }
fn wm_get_title(int idx) -> char* { return cast<char*>(getq(g_wm_windows, idx * 128 + 32)); }
fn wm_get_bg(int idx) -> int { return getd(g_wm_windows, idx * 128 + 40); }
fn wm_get_title_bg(int idx) -> int { return getd(g_wm_windows, idx * 128 + 44); }
fn wm_get_border(int idx) -> int { return getd(g_wm_windows, idx * 128 + 48); }
fn wm_get_id(int idx) -> int { return getd(g_wm_windows, idx * 128 + 60); }

fn wm_set_x(int idx, int v) -> void { putd(g_wm_windows, idx * 128 + 0, v); }
fn wm_set_y(int idx, int v) -> void { putd(g_wm_windows, idx * 128 + 4, v); }
fn wm_set_w(int idx, int v) -> void { putd(g_wm_windows, idx * 128 + 8, v); }
fn wm_set_h(int idx, int v) -> void { putd(g_wm_windows, idx * 128 + 12, v); }
fn wm_set_focused(int idx, int v) -> void { putd(g_wm_windows, idx * 128 + 16, v); }
fn wm_set_visible(int idx, int v) -> void { putd(g_wm_windows, idx * 128 + 20, v); }
fn wm_set_flags(int idx, int v) -> void { putd(g_wm_windows, idx * 128 + 24, v); }
fn wm_set_zorder(int idx, int v) -> void { putd(g_wm_windows, idx * 128 + 28, v); }
fn wm_set_title(int idx, char* v) -> void { putq(g_wm_windows, idx * 128 + 32, cast<int>(v)); }
fn wm_set_bg(int idx, int v) -> void { putd(g_wm_windows, idx * 128 + 40, v); }
fn wm_set_title_bg(int idx, int v) -> void { putd(g_wm_windows, idx * 128 + 44, v); }
fn wm_set_border(int idx, int v) -> void { putd(g_wm_windows, idx * 128 + 48, v); }
fn wm_set_id(int idx, int v) -> void { putd(g_wm_windows, idx * 128 + 60, v); }

// ---------------------------------------------------------------------------
// wm_create_window -- إنشاء نافذة جديدة
// Create a new window and return its index (-1 if full).
// ---------------------------------------------------------------------------
fn wm_create_window(int x, int y, int w, int h, char* title) -> int {
    if (g_wm_count >= 32) { return -1; }

    int idx = g_wm_count;
    g_wm_count = g_wm_count + 1;

    wm_set_x(idx, x);
    wm_set_y(idx, y);
    wm_set_w(idx, w);
    wm_set_h(idx, h);
    wm_set_focused(idx, 0);
    wm_set_visible(idx, 1);
    wm_set_flags(idx, 0);
    wm_set_zorder(idx, idx);
    wm_set_title(idx, title);
    wm_set_bg(idx, g_clr_win_bg);
    wm_set_title_bg(idx, g_clr_titlebar);
    wm_set_border(idx, g_clr_border);
    wm_set_id(idx, g_wm_next_id);
    g_wm_next_id = g_wm_next_id + 1;

    // Focus the new window
    wm_focus_window(idx);
    g_wm_dirty = 1;

    return idx;
}

// ---------------------------------------------------------------------------
// wm_close_window -- إغلاق نافذة
// Close a window by marking it invisible.
// ---------------------------------------------------------------------------
fn wm_close_window(int idx) -> void {
    if (idx < 0) { return; }
    if (idx >= g_wm_count) { return; }
    wm_set_visible(idx, 0);
    if (g_wm_focus == idx) {
        g_wm_focus = -1;
        // Find next visible window to focus
        int i = g_wm_count - 1;
        while (i >= 0) {
            if ((i != idx) && (wm_get_visible(i) == 1)) {
                wm_focus_window(i);
                i = -1; // break
            }
            i = i - 1;
        }
    }
    g_wm_dirty = 1;
}

// ---------------------------------------------------------------------------
// wm_focus_window -- تركيز نافذة (تقديمها للأمام)
// Give focus to a window, bringing it to the front (highest z-order).
// ---------------------------------------------------------------------------
fn wm_focus_window(int idx) -> void {
    if (idx < 0) { return; }
    if (idx >= g_wm_count) { return; }
    if (wm_get_visible(idx) == 0) { return; }

    // Unfocus all
    int i = 0;
    while (i < g_wm_count) {
        wm_set_focused(i, 0);
        i = i + 1;
    }

    // Focus this one
    wm_set_focused(idx, 1);
    g_wm_focus = idx;

    // Raise to top z-order -- الأعلى في ترتيب العمق
    int max_z = 0;
    i = 0;
    while (i < g_wm_count) {
        if (wm_get_zorder(i) > max_z) { max_z = wm_get_zorder(i); }
        i = i + 1;
    }
    wm_set_zorder(idx, max_z + 1);
    g_wm_dirty = 1;
}

// ---------------------------------------------------------------------------
// wm_draw_close_button -- رسم زر الإغلاق
// Draw the close button (X) on the title bar.
// ---------------------------------------------------------------------------
fn wm_draw_close_button(int bx, int by, int color) -> void {
    // Draw an "X" inside a 16x16 area
    int btn_color = g_clr_close_btn;
    // Filled circle background
    draw_filled_circle(bx + 8, by + 8, 7, btn_color);
    // X mark
    int xc = rgb_pack(255, 255, 255);
    draw_line(bx + 4, by + 4, bx + 12, by + 12, xc);
    draw_line(bx + 12, by + 4, bx + 4, by + 12, xc);
}

// ---------------------------------------------------------------------------
// wm_draw_window -- رسم نافذة واحدة
// Draw a single window: border, title bar, close button, content area.
// ---------------------------------------------------------------------------
fn wm_draw_window(int idx) -> void {
    if (wm_get_visible(idx) == 0) { return; }

    int wx = wm_get_x(idx);
    int wy = wm_get_y(idx);
    int ww = wm_get_w(idx);
    int wh = wm_get_h(idx);
    int focused = wm_get_focused(idx);

    // Shadow (subtle dark outline) -- ظل خفيف
    int shadow_color = rgb_pack(10, 10, 15);
    draw_filled_rect(wx + 3, wy + 3, ww, wh, shadow_color);

    // Window border -- الإطار
    int border_c = wm_get_border(idx);
    if (focused == 1) {
        border_c = rgb_pack(80, 120, 200);  // إطار أزرق للنافذة المركزة
    }
    draw_filled_rect(wx - 1, wy - 1, ww + 2, wh + 2, border_c);

    // Title bar -- شريط العنوان
    int tb_color = g_clr_titlebar_blur;
    if (focused == 1) {
        tb_color = g_clr_titlebar;
    }
    draw_filled_rect(wx, wy, ww, 24, tb_color);

    // Title bar gradient effect (subtle) -- تأثير تدرج خفيف
    int grad_color = rgb_pack(45, 80, 150);
    if (focused == 0) {
        grad_color = rgb_pack(55, 55, 65);
    }
    draw_hline(wx, wx + ww - 1, wy + 23, grad_color);

    // Title text -- نص العنوان
    char* title = wm_get_title(idx);
    int text_c = g_clr_text;
    if (focused == 0) { text_c = g_clr_text_dim; }
    draw_string(wx + 28, wy + 8, title, text_c);

    // Close button -- زر الإغلاق
    wm_draw_close_button(wx + 4, wy + 4, g_clr_close_btn);

    // Content area -- منطقة المحتوى
    draw_filled_rect(wx, wy + 24, ww, wh - 24, wm_get_bg(idx));

    // Widgets -- مكونات النافذة تُرسم داخلها فتُحترم ترتيب العمق (z-order)
    wdg_draw_all_for_window(idx, wx, wy);
}

// ---------------------------------------------------------------------------
// wm_draw_taskbar -- رسم شريط المهام
// Draw the taskbar at the bottom of the screen.
// ---------------------------------------------------------------------------
fn wm_draw_taskbar() -> void {
    int sw = fb_get_width();
    int sh = fb_get_height();
    int tb_h = 32;
    int tb_y = sh - tb_h;

    // Taskbar background -- خلفية شريط المهام
    draw_filled_rect(0, tb_y, sw, tb_h, g_clr_taskbar);
    // Top border line
    int border_line = rgb_pack(50, 50, 70);
    draw_hline(0, sw - 1, tb_y, border_line);

    // "BH" logo/start button -- زر البداية
    int logo_bg = rgb_pack(60, 100, 180);
    draw_filled_rect(4, tb_y + 4, 48, 24, logo_bg);
    int logo_text = rgb_pack(255, 255, 255);
    draw_string(12, tb_y + 8, "BH", logo_text);

    // Window list in taskbar -- قائمة النوافذ في شريط المهام
    // Stop as soon as the next button would run past the clock area.
    int tx = 60;
    int i = 0;
    while ((i < g_wm_count) && (tx + 120 <= sw)) {
        if (wm_get_visible(i) == 1) {
            int tbg = rgb_pack(40, 40, 55);
            if (wm_get_focused(i) == 1) {
                tbg = rgb_pack(55, 90, 160);
            }
            draw_filled_rect(tx, tb_y + 4, 120, 24, tbg);
            char* title = wm_get_title(i);
            int tc = g_clr_text_dim;
            if (wm_get_focused(i) == 1) { tc = g_clr_text; }
            draw_string(tx + 8, tb_y + 8, title, tc);
            tx = tx + 128;
        }
        i = i + 1;
    }

    // Clock area placeholder -- منطقة الساعة
    draw_string(sw - 56, tb_y + 8, "00:00", g_clr_text);
}

// ---------------------------------------------------------------------------
// wm_composite -- إعادة رسم الشاشة بالكامل
// Composite all windows in z-order onto the backbuffer, then flip.
// This is the main rendering function called each frame.
// ---------------------------------------------------------------------------
fn wm_composite() -> void {
    int sw = fb_get_width();
    int sh = fb_get_height();

    // Clear to desktop background -- مسح الشاشة بلون الخلفية
    fb_clear(g_clr_desktop);

    // Draw a subtle desktop pattern -- نمط خلفية خفيف
    int pattern_color = rgb_pack(28, 28, 40);
    int py = 0;
    while (py < sh - 32) {
        if ((py / 32) - ((py / 32) / 2) * 2 == 0) {
            int px = 0;
            while (px < sw) {
                if ((px / 32) - ((px / 32) / 2) * 2 == 1) {
                    draw_filled_rect(px, py, 32, 32, pattern_color);
                }
                px = px + 32;
            }
        }
        py = py + 32;
    }

    // Sort windows by z-order for correct compositing -- ترتيب حسب العمق
    // Simple selection sort on z-order indices.  The scratch buffer lives in
    // g_wm_order (allocated once in wm_init) so compositing never allocates.
    char* order = g_wm_order;
    int i = 0;
    while (i < g_wm_count) {
        putd(order, i * 4, i);
        i = i + 1;
    }

    // Selection sort by z-order
    int a = 0;
    while (a < g_wm_count - 1) {
        int min_idx = a;
        int b = a + 1;
        while (b < g_wm_count) {
            int za = wm_get_zorder(getd(order, a * 4));
            int zb = wm_get_zorder(getd(order, b * 4));
            int zmin = wm_get_zorder(getd(order, min_idx * 4));
            if (zb < zmin) { min_idx = b; }
            b = b + 1;
        }
        if (min_idx != a) {
            int tmp = getd(order, a * 4);
            putd(order, a * 4, getd(order, min_idx * 4));
            putd(order, min_idx * 4, tmp);
        }
        a = a + 1;
    }

    // Draw windows in z-order (back to front)
    i = 0;
    while (i < g_wm_count) {
        int widx = getd(order, i * 4);
        wm_draw_window(widx);
        i = i + 1;
    }

    // Draw taskbar on top -- رسم شريط المهام فوق كل شيء
    wm_draw_taskbar();
}

// ---------------------------------------------------------------------------
// wm_hit_test -- اختبار الضغط (أي نافذة تم الضغط عليها)
// Find the topmost visible window at pixel (mx, my).
// Returns window index or -1 if none.
// Returns in *region: 0=content, 1=titlebar, 2=close button
// ---------------------------------------------------------------------------
fn wm_hit_test(int mx, int my) -> int {
    // Iterate backwards (highest z-order first)
    int best = -1;
    int best_z = -1;
    int i = 0;
    while (i < g_wm_count) {
        if (wm_get_visible(i) == 1) {
            int wx = wm_get_x(i);
            int wy = wm_get_y(i);
            int ww = wm_get_w(i);
            int wh = wm_get_h(i);
            if ((mx >= wx) && (mx < wx + ww) && (my >= wy) && (my < wy + wh)) {
                if (wm_get_zorder(i) > best_z) {
                    best = i;
                    best_z = wm_get_zorder(i);
                }
            }
        }
        i = i + 1;
    }
    return best;
}

// ---------------------------------------------------------------------------
// wm_hit_region -- تحديد منطقة الضغط في نافذة
// Given a window index and mouse coords, return:
//   0 = content area
//   1 = title bar (draggable)
//   2 = close button
// ---------------------------------------------------------------------------
fn wm_hit_region(int idx, int mx, int my) -> int {
    int wx = wm_get_x(idx);
    int wy = wm_get_y(idx);
    int ww = wm_get_w(idx);

    // Close button: 16x16 at (wx+4, wy+4)
    if ((mx >= wx + 4) && (mx < wx + 20) && (my >= wy + 4) && (my < wy + 20)) {
        return 2;
    }
    // Title bar: full width, 24px height
    if ((my >= wy) && (my < wy + 24)) {
        return 1;
    }
    return 0;
}

// ---------------------------------------------------------------------------
// wm_hit_taskbar -- اختبار الضغط على شريط المهام
// Check if a click is in the taskbar area. Returns window index or -1.
// ---------------------------------------------------------------------------
fn wm_hit_taskbar(int mx, int my) -> int {
    int sh = fb_get_height();
    int sw = fb_get_width();
    if (my < sh - 32) { return -1; }

    // Check BH button
    if ((mx >= 4) && (mx < 52)) { return -2; } // -2 = start button

    // Check window buttons (same layout as wm_draw_taskbar)
    int tx = 60;
    int i = 0;
    while ((i < g_wm_count) && (tx + 120 <= sw)) {
        if (wm_get_visible(i) == 1) {
            if ((mx >= tx) && (mx < tx + 120)) {
                return i;
            }
            tx = tx + 128;
        }
        i = i + 1;
    }
    return -1;
}

// ---------------------------------------------------------------------------
// wm_start_drag -- بدء سحب نافذة
// Begin dragging a window.
// ---------------------------------------------------------------------------
fn wm_start_drag(int idx, int mx, int my) -> void {
    g_wm_drag = 1;
    g_wm_drag_idx = idx;
    g_wm_drag_ox = mx - wm_get_x(idx);
    g_wm_drag_oy = my - wm_get_y(idx);
}

// ---------------------------------------------------------------------------
// wm_update_drag -- تحديث موضع النافذة أثناء السحب
// Update the dragged window position.
// ---------------------------------------------------------------------------
fn wm_update_drag(int mx, int my) -> void {
    if (g_wm_drag == 0) { return; }
    int new_x = mx - g_wm_drag_ox;
    int new_y = my - g_wm_drag_oy;
    // Clamp to screen bounds -- تقييد ضمن حدود الشاشة
    if (new_y < 0) { new_y = 0; }
    if (new_x < -wm_get_w(g_wm_drag_idx) + 40) { new_x = -wm_get_w(g_wm_drag_idx) + 40; }
    wm_set_x(g_wm_drag_idx, new_x);
    wm_set_y(g_wm_drag_idx, new_y);
    g_wm_dirty = 1;
}

// ---------------------------------------------------------------------------
// wm_stop_drag -- إيقاف سحب النافذة
// Stop dragging.
// ---------------------------------------------------------------------------
fn wm_stop_drag() -> void {
    g_wm_drag = 0;
    g_wm_drag_idx = -1;
}

fn wm_is_dragging() -> int {
    return g_wm_drag;
}

fn wm_get_count() -> int {
    return g_wm_count;
}

fn wm_get_focus() -> int {
    return g_wm_focus;
}
