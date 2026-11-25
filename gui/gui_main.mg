// gui_main.mg -- الوحدة 6: الحلقة الرئيسية للواجهة (GUI Main)
// BlackhatOS GUI Core - Main event loop and desktop environment
//
// This is the entry point that ties every other module together:
//
//     fb_hal.mg        -> framebuffer HAL          (/dev/fb0)
//     gfx_primitives.mg-> drawing primitives        (lines, rects, 8x8 font)
//     window_manager.mg-> window compositor         (z-order, taskbar, drag)
//     widgets.mg       -> UI widgets                (buttons, inputs, dropdown)
//     input_handler.mg -> keyboard + mouse          (/dev/input/event*)
//
// `main()` is the process entry point when linked on its own.  When the file
// is compiled into PID-1 (blackhat-init) instead, the init code can simply
// call `gui_run()` / `gui_tick()` -- there is no global state collision.
//
// No libc: every syscall is a hand-written trampoline provided by magc.

// ---------------------------------------------------------------------------
// Syscalls
// ---------------------------------------------------------------------------
extern fn sys_mmap(char* addr, int length, int prot, int flags, int fd, int offset) -> int;
extern fn sys_write(int fd, char* data, int count) -> int;
extern fn sys_read(int fd, char* buf, int count) -> int;
extern fn sys_open(char* path, int flags) -> int;
extern fn sys_close(int fd) -> int;
extern fn sys_exit_group(int code) -> int;
extern fn sys_nanosleep(void* req, void* rem) -> int;
extern fn sys_ioctl(int fd, int request, char* arg) -> int;

// ---------------------------------------------------------------------------
// Helpers (defined below; declared here so included modules patch cleanly)
// ---------------------------------------------------------------------------
extern fn bval(int v) -> int;
extern fn putb(char* p, int off, int v) -> void;
extern fn getb(char* p, int off) -> int;
extern fn putd(char* p, int off, int v) -> void;
extern fn getd(char* p, int off) -> int;
extern fn name_len(char* p) -> int;
extern fn copy_str(char* dst, int doff, char* src) -> int;
extern fn fn_addr(string name) -> int;

// ---------------------------------------------------------------------------
// Module dependencies -- ORDER MATTERS.
// Each module declares the functions it needs from the later ones as `extern`,
// so the extern-then-definition pair must resolve in this order.
// ---------------------------------------------------------------------------
use "gui/fb_hal.mg";
use "gui/gfx_primitives.mg";
use "gui/window_manager.mg";
use "gui/widgets.mg";
use "gui/input_handler.mg";

// ---------------------------------------------------------------------------
// Widget type ids (mirror widgets.mg)
// ---------------------------------------------------------------------------
// TYPE_BUTTON    = 1
// TYPE_TEXTINPUT = 2
// TYPE_DROPDOWN  = 3
// TYPE_LABEL     = 4

// ===========================================================================
// String / memory helpers -- مساعدات النصوص والذاكرة
//
// fb_hal.mg defines bval/putb/getb/putd/getd/name_len but NOT copy_str, yet
// window_manager.mg and widgets.mg declare it `extern`.  gui_main uses it, so
// it must be defined exactly once -- and this is that place.  (An extern that
// is never referenced emits no relocation, which is why this went unnoticed
// until now; an extern that IS referenced with no definition would leave a
// patch pointing at address 0 and fault on the first call.)
// ===========================================================================

// ---------------------------------------------------------------------------
// copy_str -- نسخ نص إلى مخزن مع إنهائه ببايت صفر، وإرجاع الطول
// ---------------------------------------------------------------------------
fn copy_str(char* dst, int doff, char* src) -> int {
    int i = 0;
    while (bval(*(src + i)) != 0) {
        putb(dst, doff + i, bval(*(src + i)));
        i = i + 1;
    }
    putb(dst, doff + i, 0);
    return i;
}

// ---------------------------------------------------------------------------
// gui_str_eq -- مقارنة نصين
// ---------------------------------------------------------------------------
fn gui_str_eq(char* a, char* b) -> int {
    int i = 0;
    while (1) {
        int ca = bval(*(a + i));
        int cb = bval(*(b + i));
        if (ca != cb) { return 0; }
        if (ca == 0) { return 1; }
        i = i + 1;
    }
}

// ===========================================================================
// Global state -- الحالة العامة
// ===========================================================================
static int g_gui_running;      // 1 = الحلقة تعمل
static int g_gui_frame;        // رقم الإطار
static int g_gui_win_main;     // نافذة رئيسية
static int g_gui_win_about;    // نافذة "حول"
static int g_gui_input;        // حقل الإدخال
static int g_gui_status;       // نص الحالة
static int g_gui_btn_greet;    // زر الترحيب
static int g_gui_btn_clear;    // زر المسح
static int g_gui_btn_theme;    // زر المظهر
static int g_gui_dropdown;     // القائمة المنسدلة
static int g_gui_theme;        // المظهر الحالي (0=داكن)

static char* g_gui_status_buf; // مخزن نص الحالة
static char* g_gui_scratch;    // مخزن مؤقت للنصوص
static char* g_gui_sleep;      // struct timespec لـ nanosleep

// Callback ids (filled in gui_build_desktop via fn_addr)
static int g_cb_greet;
static int g_cb_clear;
static int g_cb_theme;
static int g_cb_close_about;

// ===========================================================================
// Callbacks -- دوال الاستدعاء (تُستدعى عند الضغط على الأزرار)
// ===========================================================================

// gui_on_greet -- بناء تحية من نص حقل الإدخال
fn gui_on_greet() -> void {
    char* txt = wdg_textinput_get_text(g_gui_input);
    int n = name_len(txt);
    if (n == 0) {
        gui_set_status("Hello!, something");
        return;
    }
    copy_str(g_gui_status_buf, 0, "yoy Hello ");
    int k = copy_str(g_gui_status_buf, 10, txt);
    if (k > 40) { k = 40; }
    putb(g_gui_status_buf, 11 + k, 0);
    gui_set_status(g_gui_status_buf);
    wm_set_dirty();
}

// gui_on_clear -- تفريغ حقل الإدخال والنص
fn gui_on_clear() -> void {
    char* buf = wdg_textinput_get_text(g_gui_input);
    putb(buf, 0, 0);
    wdg_handle_key(0, 0); // no-op, keeps focus semantics obvious
    gui_set_status("Recite Done");
    wm_set_dirty();
}

// gui_on_theme -- تبديل المظهر (داكن/فاتح)
fn gui_on_theme() -> void {
    if (g_gui_theme == 0) {
        g_gui_theme = 1;
        wm_set_theme(1);
        gui_set_status("ligth theme");
    } else {
        g_gui_theme = 0;
        wm_set_theme(0);
        gui_set_status("Dark theme");
    }
    wm_set_dirty();
}

// gui_on_close_about -- إغلاق نافذة "حول"
fn gui_on_close_about() -> void {
    wm_close_window(g_gui_win_about);
    if (g_gui_status >= 0) { gui_set_status("you closed a window"); }
    wm_set_dirty();
}

// ===========================================================================
// Status line -- سطر الحالة
// ===========================================================================
fn gui_set_status(char* s) -> void {
    copy_str(g_gui_status_buf, 0, s);
    if (g_gui_status >= 0) {
        putb(g_gui_status_buf, name_len(s), 0);
        wdg_set_text(g_gui_status, g_gui_status_buf);
    }
    wm_set_dirty();
}

// ===========================================================================
// gui_build_desktop -- إنشاء سطح المكتب
// Build the main window, all widgets, and the About window.
// ===========================================================================
fn gui_build_desktop() -> void {
    g_gui_win_main = wm_create_window(80, 60, 520, 360, "BlackhatOS - controll panell");

    // Title label -- عنوان
    wdg_create_label(g_gui_win_main, 20, 16, "  controll panlle BlackhatOS", rgb_pack(200, 220, 255));

    // Name label + text input -- حقل الاسم
    wdg_create_label(g_gui_win_main, 20, 48, "Name", rgb_pack(200, 200, 215));
    g_gui_input = wdg_create_textinput(g_gui_win_main, 90, 42, 300, 26, 48);
    wdg_focus(g_gui_input);

    // Buttons -- الأزرار
    g_cb_greet = fn_addr("gui_on_greet");
    g_cb_clear = fn_addr("gui_on_clear");
    g_cb_theme = fn_addr("gui_on_theme");
    g_cb_close_about = fn_addr("gui_on_close_about");

    g_gui_btn_greet = wdg_create_button(g_gui_win_main, 20, 96, 120, 30, "Hello");
    wdg_set_callback(g_gui_btn_greet, g_cb_greet);

    g_gui_btn_clear = wdg_create_button(g_gui_win_main, 150, 96, 120, 30, "recite");
    wdg_set_callback(g_gui_btn_clear, g_cb_clear);

    g_gui_btn_theme = wdg_create_button(g_gui_win_main, 280, 96, 120, 30, "theme");
    wdg_set_callback(g_gui_btn_theme, g_cb_theme);

    // Dropdown -- قائمة منسدلة
    wdg_create_label(g_gui_win_main, 20, 150, "langeag", rgb_pack(200, 200, 215));
    g_gui_dropdown = wdg_create_dropdown(g_gui_win_main, 90, 142, 200, 26,
                                         gui_dropdown_items(), 3);

    // Status line -- سطر الحالة
    g_gui_status = wdg_create_label(g_gui_win_main, 20, 210, "readdy", rgb_pack(140, 230, 140));
    gui_set_status("readdy");

    // About window (created on top, focused) -- نافذة حول
    g_gui_win_about = wm_create_window(320, 220, 320, 180, "in ");
    wdg_create_label(g_gui_win_about, 20, 20, "BlackhatOS GUI Core v1.0", rgb_pack(230, 230, 240));
    wdg_create_label(g_gui_win_about, 20, 48, "Magnetar language GUI", rgb_pack(180, 180, 200));
    wdg_create_label(g_gui_win_about, 20, 76, "fb_hal + wm + widgets", rgb_pack(180, 180, 200));
    int close_idx = wdg_create_button(g_gui_win_about, 100, 110, 120, 30, "اغلاق");
    wdg_set_callback(close_idx, g_cb_close_about);

    wm_set_dirty();
}

// ---------------------------------------------------------------------------
// gui_dropdown_items -- مصفوفة عناصر القائمة المنسدلة
// Items are stored as 8-byte char* pointers in a small static block.
// ---------------------------------------------------------------------------
fn gui_dropdown_items() -> char* {
    char* items = g_gui_scratch;              // scratch page reused as item array
    putq(items, 0, cast<int>("Arabic"));
    putq(items, 8, cast<int>("English"));
    putq(items, 16, cast<int>("Francais"));
    return items;
}

// ===========================================================================
// Dispatch -- توزيع الاستدعاءات
// ===========================================================================
fn gui_dispatch(int cb) -> void {
    if (cb == 0) { return; }
    if (cb == g_cb_greet) { gui_on_greet(); return; }
    if (cb == g_cb_clear) { gui_on_clear(); return; }
    if (cb == g_cb_theme) { gui_on_theme(); return; }
    if (cb == g_cb_close_about) { gui_on_close_about(); return; }
}

// ===========================================================================
// Input handling -- معالجة الإدخال
// ===========================================================================
fn gui_handle_mouse() -> void {
    int mx = input_mouse_x();
    int my = input_mouse_y();

    // Hover states for the focused window
    int fw = wm_get_focus();
    if (fw >= 0) {
        wdg_update_hover(fw, wm_get_x(fw), wm_get_y(fw), mx, my);
    }

    if (input_mouse_released() == 1) {
        int fr = wdg_get_focused();
        if (fr >= 0) { wdg_handle_release(fr); }
        wm_set_dirty();
    }

    if (input_mouse_clicked() == 0) { return; }

    // Taskbar first (always on top) -- شريط المهام اولا
    int cand = -1;
    int tb = wm_hit_taskbar(mx, my);
    if (tb >= 0) { wm_focus_window(tb); wm_set_dirty(); return; }
    if (tb == -2) { gui_on_theme(); return; }

    // Topmost window under the cursor
    int win = wm_hit_test(mx, my);
    if (win < 0) { wdg_focus(-1); wm_set_dirty(); return; }

    wm_focus_window(win);
    int region = wm_hit_region(win, mx, my);

    if (region == 2) { // close button
        wm_close_window(win);
        if (g_gui_status >= 0) { gui_set_status("you closed window "); }
        wm_set_dirty();
        return;
    }
    if (region == 1) { // title bar -> drag
        wm_start_drag(win, mx, my);
        return;
    }

    // Content area -> widgets
    int widx = wdg_hit_test(win, wm_get_x(win), wm_get_y(win), mx, my);
    if (widx >= 0) {
        int handled = wdg_handle_click(widx, mx, my, wm_get_x(win), wm_get_y(win));
        if (handled == 1) {
            // Buttons fire their callback on release; we just mark pressed here.
            if (wdg_get_type(widx) != 1) {
                wm_set_dirty();
            } else {
                gui_dispatch(wdg_get_callback(widx));
                wdg_handle_release(widx);
                wm_set_dirty();
            }
        } else {
            wdg_focus(-1);
            wm_set_dirty();
        }
    } else {
        wdg_focus(-1);
        wm_set_dirty();
    }
}

fn gui_handle_keyboard() -> void {
    if (input_kbd_pressed() == 0) { return; }
    int sc = input_kbd_key();
    int ascii = input_kbd_ascii();

    // Escape: close the About window if open, otherwise quit the GUI.
    // ESC: إغلاق نافذة "حول" إن كانت مفتوحة، وإلا الخروج من الواجهة.
    if (sc == 1) {
        if ((g_gui_win_about >= 0) && (wm_get_visible(g_gui_win_about) == 1)) {
            gui_on_close_about();
        } else {
            gui_stop();
        }
        return;
    }
    // Ctrl+Alt+Q always quits -- للخروج دائماً
    if ((sc == 16) && (input_kbd_ctrl() == 1) && (input_kbd_alt() == 1)) {
        gui_stop();
        return;
    }
    // Enter on the input field triggers the greet callback -- Enter
    if (sc == 28) {
        if (wdg_get_focused() == g_gui_input) {
            gui_on_greet();
        }
        return;
    }

    if (wdg_get_focused() >= 0) {
        wdg_handle_key(sc, ascii);
        wm_set_dirty();
    }
}

// ===========================================================================
// gui_init -- تهيئة الواجهة بالكامل
// Returns 0 on success, -1 on failure.
// ===========================================================================
fn gui_init() -> int {
    g_gui_running = 1;
    g_gui_frame = 0;
    g_gui_theme = 0;
    g_gui_status_buf = cast<char*>(sys_mmap(0, 4096, 3, 34, -1, 0));
    g_gui_scratch = cast<char*>(sys_mmap(0, 4096, 3, 34, -1, 0));
    g_gui_sleep = cast<char*>(sys_mmap(0, 4096, 3, 34, -1, 0));

    if (fb_init() < 0) {
        sys_write(2, "gui: framebuffer init failed\n", 29);
        return -1;
    }

    // Take the active VT away from the text console (KD_GRAPHICS) so fbcon
    // stops repainting its cursor/console over our pixels.  This is what makes
    // the GUI own the whole screen instead of drawing inside the tty.
    gui_grab_display();

    gfx_font_init();
    wm_init();
    widgets_init();

    g_gui_win_about = -1;
    g_gui_win_main = -1;
    g_gui_input = -1;
    g_gui_status = -1;

    gui_build_desktop();

    // Input is opened LAST: if it fails we still have a usable (if inanimate)
    // desktop, and we can report it instead of aborting.
    if (input_init() < 0) {
        gui_set_status("warning input failed");
    }

    return 0;
}

// ===========================================================================
// gui_tick -- إطار واحد
// One frame: poll input, handle it, composite, flip, draw the cursor.
// The cursor is drawn *after* the flip so it never lands in the backbuffer.
// ===========================================================================
fn gui_tick() -> void {
    input_poll();
    gui_handle_mouse();

    if (wm_is_dragging() == 1) {
        wm_update_drag(input_mouse_x(), input_mouse_y());
    }
    gui_handle_keyboard();

    // Fullscreen takeover: composite the desktop into the backbuffer, draw the
    // cursor on top of the backbuffer (so it never smears), then present the
    // whole frame every time.  There is no longer a text console underneath to
    // restore the pixels we overwrite, so flipping only when "dirty" would
    // leave cursor trails behind.
    wm_composite();
    input_draw_cursor();
    fb_flip();
    wm_clear_dirty();
    g_gui_frame = g_gui_frame + 1;
}

// ===========================================================================
// gui_sleep_frame -- نوم قصير بين الإطارات
// Sleeps ~16ms using a hand-filled timespec.
// ===========================================================================
fn gui_sleep_frame() -> void {
    putq(g_gui_sleep, 0, 0);          // tv_sec = 0
    putq(g_gui_sleep, 8, 16000000);   // tv_nsec = 16ms
    sys_nanosleep(g_gui_sleep, cast<void*>(0));
}

// ===========================================================================
// gui_run -- الحلقة الرئيسية
// Run frames until gui_stop() is called (or forever).
// ===========================================================================
fn gui_run() -> void {
    while (g_gui_running == 1) {
        gui_tick();
        gui_sleep_frame();
    }
}

fn gui_stop() -> void {
    g_gui_running = 0;
    // Hand the VT back to the text console so the shell appears clean on exit.
    gui_release_display();
    input_close();
}

fn gui_frame_count() -> int {
    return g_gui_frame;
}

// ===========================================================================
// Self test -- اختبار ذاتي (لا يلمس الشاشة الحقيقية)
//
// Every drawing primitive writes to the *backbuffer*, and only fb_flip()
// presents it.  So the self test can exercise the entire stack on a running
// host, verify pixels with fb_peek(), and never disturb the console.
// ===========================================================================
static int g_st_checks;
static int g_st_fails;

fn st_check(int cond, char* what) -> void {
    g_st_checks = g_st_checks + 1;
    if (cond == 0) {
        g_st_fails = g_st_fails + 1;
        sys_write(2, "FAIL: ", 6);
        sys_write(2, what, name_len(what));
        sys_write(2, "\n", 1);
    }
}

fn gui_selftest() -> int {
    g_st_checks = 0;
    g_st_fails = 0;
    g_gui_status_buf = cast<char*>(sys_mmap(0, 4096, 3, 34, -1, 0));
    g_gui_scratch = cast<char*>(sys_mmap(0, 4096, 3, 34, -1, 0));
    g_gui_sleep = cast<char*>(sys_mmap(0, 4096, 3, 34, -1, 0));

    sys_write(1, "== BlackhatOS GUI self-test ==\n", 30);

    if (fb_init() < 0) {
        sys_write(2, "FAIL: fb_init\n", 14);
        return 1;
    }
    gfx_font_init();
    wm_init();
    widgets_init();

    // --- 1. framebuffer geometry ---
    st_check(fb_get_width() > 0, "fb width");
    st_check(fb_get_height() > 0, "fb height");
    st_check(fb_get_stride() >= fb_get_width() * (fb_get_bpp() / 8), "fb stride");
    sys_write(1, " fb = ", 6);
    gui_print_int(fb_get_width());
    sys_write(1, "x", 1);
    gui_print_int(fb_get_height());
    sys_write(1, "x", 1);
    gui_print_int(fb_get_bpp());
    sys_write(1, "\n", 1);

    // --- 2. rgb_pack round trip (32bpp hosts) ---
    int red = rgb_pack(255, 0, 0);
    int grn = rgb_pack(0, 255, 0);
    int blu = rgb_pack(0, 0, 255);
    st_check(red != grn, "distinct red/green");
    st_check(grn != blu, "distinct green/blue");
    st_check(red != blu, "distinct red/blue");

    // --- 3. fill_rect + peek ---
    fb_clear(rgb_pack(0, 0, 0));
    fb_fill_rect_fast(4, 4, 10, 10, red);
    st_check(fb_peek(5, 5) == red, "fill_rect interior");
    st_check(fb_peek(3, 3) != red, "fill_rect exterior");
    st_check(fb_peek(14, 4) != red, "fill_rect right edge");

    // --- 4. clipping safety (must not crash / wrap) ---
    fb_fill_rect_fast(-50, -50, 30, 30, grn);
    fb_fill_rect_fast(fb_get_width() - 5, -10, 100, 100, blu);
    st_check(1, "clipped fills survived");

    // --- 5. draw_hline via primitives ---
    fb_clear(rgb_pack(0, 0, 0));
    draw_hline(10, 20, 7, grn);
    st_check(fb_peek(10, 7) == grn, "hline start");
    st_check(fb_peek(20, 7) == grn, "hline end");
    st_check(fb_peek(21, 7) != grn, "hline beyond");

    // --- 6. draw_filled_rect routes to the fast path ---
    fb_clear(rgb_pack(0, 0, 0));
    draw_filled_rect(30, 30, 12, 8, blu);
    st_check(fb_peek(31, 31) == blu, "filled_rect interior");
    st_check(fb_peek(41, 37) == blu, "filled_rect corner");

    // --- 7. font / text ---
    fb_clear(rgb_pack(0, 0, 0));
    int text_c = rgb_pack(255, 255, 255);
    draw_char(50, 50, 65, text_c); // 'A'
    int lit = 0;
    int fy = 0;
    while (fy < 8) {
        int fx = 0;
        while (fx < 8) {
            if (fb_peek(50 + fx, 50 + fy) == text_c) { lit = lit + 1; }
            fx = fx + 1;
        }
        fy = fy + 1;
    }
    st_check(lit > 0, "glyph 'A' has pixels");
    st_check(lit < 40, "glyph 'A' is not a solid block");

    // --- 8. window manager over the backbuffer ---
    int w1 = wm_create_window(10, 10, 100, 80, "one");
    st_check(w1 == 0, "wm_create_window #1");
    int w2 = wm_create_window(40, 40, 100, 80, "two");
    st_check(w2 == 1, "wm_create_window #2");
    st_check(wm_get_count() == 2, "wm count");
    st_check(wm_get_focus() == w2, "newest window focused");

    // hit test picks the topmost (z-order) window
    st_check(wm_hit_test(45, 45) == w2, "hit_test topmost");
    st_check(wm_hit_test(15, 15) == w1, "hit_test underlying");
    st_check(wm_hit_test(500, 500) == -1, "hit_test empty");

    // regions: close button / title bar / content
    st_check(wm_hit_region(w2, 46, 46) == 2, "close button region");
    st_check(wm_hit_region(w2, 90, 45) == 1, "title bar region");
    st_check(wm_hit_region(w2, 90, 70) == 0, "content region");

    // taskbar
    int sh = fb_get_height();
    st_check(wm_hit_taskbar(20, sh - 16) == -2, "taskbar start button");
    st_check(wm_hit_taskbar(20, sh - 64) == -1, "not taskbar");

    // theme switch updates the palette and window background
    wm_set_theme(1);
    st_check(wm_get_bg(w1) != rgb_pack(35, 35, 45), "light theme changes win bg");
    wm_set_theme(0);
    st_check(wm_get_bg(w1) == rgb_pack(35, 35, 45), "dark theme restores win bg");

    // --- 9. widgets ---
    int b = wdg_create_button(w1, 10, 10, 60, 20, "OK");
    st_check(b >= 0, "create button");
    st_check(wdg_get_type(b) == 1, "button type");
    int t = wdg_create_textinput(w1, 10, 40, 80, 20, 16);
    st_check(t >= 0, "create textinput");
    wdg_focus(t);
    // type "Hi" then backspace
    wdg_handle_key(30, 72); // 'H'
    wdg_handle_key(23, 105); // 'i'
    st_check(name_len(wdg_textinput_get_text(t)) == 2, "textinput typed 2 chars");
    st_check(wdg_get_cursor(t) == 2, "textinput cursor advanced");
    wdg_handle_key(14, 8); // backspace
    st_check(name_len(wdg_textinput_get_text(t)) == 1, "textinput backspace");
    wdg_handle_key(105, 0); // left arrow
    st_check(wdg_get_cursor(t) == 0, "textinput left arrow");
    wdg_handle_key(106, 0); // right arrow
    st_check(wdg_get_cursor(t) == 1, "textinput right arrow");
    // click hit test: window w1 at (10,10); button at widget (10,10) ->
    // content_y = 10+24 = 34, so button top-left = (20, 44).
    st_check(wdg_hit_test(w1, 10, 10, 25, 49) == b, "widget hit_test button");

    // --- 9b. copy_str (defined here; used by the status line) ---
    int cl = copy_str(g_gui_scratch, 0, "hello");
    st_check(cl == 5, "copy_str returns length");
    st_check(bval(*(g_gui_scratch + 0)) == 104, "copy_str first byte 'h'");
    st_check(bval(*(g_gui_scratch + 5)) == 0, "copy_str terminates");

    // --- 10. input event parsing (synthetic mouse move + click) ---
    char* ev = cast<char*>(sys_mmap(0, 4096, 3, 34, -1, 0));
    // REL_X = +5  (type=2, code=0, value=5)
    putw(ev, 16, 2); putw(ev, 18, 0); putd(ev, 20, 5);
    input_process_event(ev);
    st_check(1, "REL event parsed");
    // BTN_LEFT press (type=1, code=272, value=1)
    putw(ev, 16, 1); putw(ev, 18, 272); putd(ev, 20, 1);
    input_process_event(ev);
    st_check(input_mouse_left() == 1, "BTN_LEFT press");
    putw(ev, 16, 1); putw(ev, 18, 272); putd(ev, 20, 0);
    input_process_event(ev);
    st_check(input_mouse_left() == 0, "BTN_LEFT release");
    // modifier normalization + autorepeat treated as press
    putw(ev, 16, 1); putw(ev, 18, 42); putd(ev, 20, 2);
    input_process_event(ev);
    st_check(input_kbd_shift() == 1, "shift autorepeat -> pressed");
    putw(ev, 16, 1); putw(ev, 18, 42); putd(ev, 20, 0);
    input_process_event(ev);
    st_check(input_kbd_shift() == 0, "shift release");

    // --- 11. composition does not corrupt the backbuffer ---
    wm_set_dirty();
    wm_composite();
    st_check(1, "wm_composite survived");

    // --- 12. display takeover helpers are wired (no actual VT grab here) ---
    // fb_display_grabbed must be 0 during the self test -- grabbing /dev/tty0
    // would steal the host console.
    st_check(fb_display_grabbed() == 0, "selftest did not grab the VT");
    st_check(input_kbd_alt() == 0, "alt modifier getter");

    // --- 13. never touch the real framebuffer ---
    sys_write(1, "== done: ", 9);
    gui_print_int(g_st_checks - g_st_fails);
    sys_write(1, "/", 1);
    gui_print_int(g_st_checks);
    sys_write(1, " checks passed ==\n", 18);

    if (g_st_fails == 0) { return 0; }
    return 1;
}

// ---------------------------------------------------------------------------
// gui_print_int -- طباعة عدد صحيح (للاختبار والتشخيص)
// ---------------------------------------------------------------------------
fn gui_print_int(int v) -> void {
    char* t = g_gui_scratch;
    if (t == cast<char*>(0)) { return; }
    if (v < 0) { sys_write(1, "-", 1); v = -v; }
    if (v == 0) { sys_write(1, "0", 1); return; }
    int n = 0;
    int tmp = v;
    while (tmp > 0) { n = n + 1; tmp = tmp / 10; }
    int i = n;
    tmp = v;
    while (i > 0) {
        i = i - 1;
        putb(t, i, 48 + (tmp - (tmp / 10) * 10));
        tmp = tmp / 10;
    }
    sys_write(1, t, n);
}

// ===========================================================================
// main -- نقطة الدخول
//   gui            run the desktop
//   gui --selftest  run the self test, exit 0/1 (safe on a live host)
//   gui --frames N  run N frames then exit (headless smoke test)
// ===========================================================================
fn gui_arg_eq(char* argv, int idx, char* want) -> int {
    char* a = cast<char*>(getq(argv, idx * 8));
    if (a == cast<char*>(0)) { return 0; }
    return gui_str_eq(a, want);
}

fn gui_arg_int(char* argv, int idx) -> int {
    char* a = cast<char*>(getq(argv, idx * 8));
    int v = 0;
    int i = 0;
    while (1) {
        int c = bval(*(a + i));
        if (c < 48) { return v; }
        if (c > 57) { return v; }
        v = v * 10 + (c - 48);
        i = i + 1;
    }
}

fn main(int argc, char** argv, char** envp) -> int {
    int i = 1;
    while (i < argc) {
        if (gui_arg_eq(argv, i, "--selftest") == 1) {
            return gui_selftest();
        }
        if (gui_arg_eq(argv, i, "--frames") == 1) {
            int n = 0;
            if (i + 1 < argc) { n = gui_arg_int(argv, i + 1); }
            if (gui_init() < 0) { return 1; }
            int k = 0;
            while (k < n) {
                gui_tick();
                k = k + 1;
            }
            gui_release_display();
            return 0;
        }
        if (gui_arg_eq(argv, i, "--help") == 1) {
            sys_write(1, "usage: gui [--selftest] [--frames N]\n", 37);
            return 0;
        }
        i = i + 1;
    }

    if (gui_init() < 0) { return 1; }
    gui_run();
    return 0;
}
