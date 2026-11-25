// widgets.mg -- الوحدة 5: المكونات التفاعلية (Widgets)
// BlackhatOS GUI Core - Interactive UI widgets
//
// This module provides:
//   - Button widget (clickable, with hover effect)
//   - Text input widget (editable text field)
//   - Dropdown menu widget
//   - Label widget (static text)
//
// All widgets use flat memory layout, similar to window manager.
// Each widget is bound to a parent window.
//
// No libc: every syscall is a hand-written trampoline provided by magc.

extern fn sys_mmap(char* addr, int length, int prot, int flags, int fd, int offset) -> int;
extern fn sys_write(int fd, char* data, int count) -> int;

// External deps
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
extern fn rgb_pack(int r, int g, int b) -> int;

// from gfx_primitives.mg
extern fn draw_filled_rect(int x, int y, int w, int h, int color) -> void;
extern fn draw_rect(int x, int y, int w, int h, int color) -> void;
extern fn draw_string(int px, int py, char* str, int color) -> void;
extern fn draw_string_clipped(int px, int py, char* str, int max_width, int color) -> void;
extern fn draw_string_window(int px, int py, char* str, int start_char, int max_width, int color) -> void;
extern fn draw_string_scale(int px, int py, char* str, int scale, int color) -> void;
extern fn draw_string_bg(int px, int py, char* str, int fg, int bg) -> void;
extern fn draw_char_bg(int px, int py, int ch, int fg, int bg) -> void;
extern fn draw_string_len(int px, int py, char* str, int len, int color) -> void;
extern fn draw_rounded_rect(int rx, int ry, int rw, int rh, int rad, int color) -> void;
extern fn draw_gradient_rect(int x, int y, int w, int h, int r0, int g0, int b0, int r1, int g1, int b1) -> void;
extern fn draw_gradient_rounded_rect(int x, int y, int w, int h, int radius, int r0, int g0, int b0, int r1, int g1, int b1) -> void;
extern fn draw_soft_shadow(int x, int y, int w, int h, int radius, int color) -> void;
extern fn draw_rounded_outline(int x, int y, int w, int h, int radius, int border, int surface) -> void;
extern fn draw_hline(int x0, int x1, int y, int color) -> void;
extern fn draw_line(int x0, int y0, int x1, int y1, int color) -> void;

// from fn_addr
extern fn fn_addr(string name) -> int;

// ===========================================================================
// Widget types -- أنواع المكونات
// ===========================================================================
// TYPE_BUTTON    = 1
// TYPE_TEXTINPUT = 2
// TYPE_DROPDOWN  = 3
// TYPE_LABEL     = 4

// ===========================================================================
// Widget structure layout (96 bytes per widget)
// ===========================================================================
// Offset   Field           Size   Description
//    0     type            4      نوع المكون
//    4     x               4      إحداثي X (نسبي لمحتوى النافذة)
//    8     y               4      إحداثي Y (نسبي)
//   12     width           4      عرض المكون
//   16     height          4      ارتفاع المكون
//   20     state           4      حالة (0=عادي, 1=hover, 2=مضغوط, 3=مركز)
//   24     parent_win      4      فهرس النافذة الأم
//   28     id              4      معرف المكون
//   32     text_ptr        8      مؤشر النص/العنوان
//   40     callback_ptr    8      مؤشر دالة الاستدعاء (للأزرار)
//   48     value           4      قيمة (للقائمة: الخيار المحدد)
//   52     max_len         4      الحد الأقصى لطول النص (لحقل الإدخال)
//   56     cursor_pos      4      موضع المؤشر في حقل الإدخال
//   60     text_buf        8      مخزن النص المؤقت لحقل الإدخال
//   68     items_ptr       8      مؤشر عناصر القائمة المنسدلة
//   76     item_count      4      عدد العناصر
//   80     open            4      هل القائمة مفتوحة؟
//   84     fg_color        4      لون النص
//   88     bg_color        4      لون الخلفية
//   92     reserved        4

// MAX_WIDGETS = 128

// ---------------------------------------------------------------------------
// Globals
// ---------------------------------------------------------------------------
static char* g_widgets;           // مصفوفة المكونات (128 مكون × 96 بايت)
static int g_widget_count;        // عدد المكونات النشطة
static int g_widget_focus;        // فهرس المكون المركز (-1 = لا شيء)
static int g_widget_next_id;      // المعرف التالي

// Default widget colors -- ألوان المكونات الافتراضية
static int g_wdg_btn_bg;         // خلفية الزر
static int g_wdg_btn_hover;      // خلفية الزر عند التمرير
static int g_wdg_btn_press;      // خلفية الزر عند الضغط
static int g_wdg_btn_text;       // نص الزر
static int g_wdg_input_bg;       // خلفية حقل الإدخال
static int g_wdg_input_border;   // إطار حقل الإدخال
static int g_wdg_input_focus;    // إطار حقل الإدخال المركز
static int g_wdg_input_text;     // نص حقل الإدخال
static int g_wdg_dropdown_bg;    // خلفية القائمة المنسدلة
static int g_wdg_dropdown_sel;   // الخيار المحدد

// ---------------------------------------------------------------------------
// widgets_init -- تهيئة نظام المكونات
// Initialize the widget system: allocate table, set default colors.
// ---------------------------------------------------------------------------
fn widgets_init() -> void {
    // 128 widgets * 96 bytes = 12288 bytes
    g_widgets = cast<char*>(sys_mmap(0, 16384, 3, 34, -1, 0));
    g_widget_count = 0;
    g_widget_focus = -1;
    g_widget_next_id = 1;

    // Default color scheme -- نظام ألوان افتراضي
    g_wdg_btn_bg = rgb_pack(55, 90, 160);
    g_wdg_btn_hover = rgb_pack(70, 110, 190);
    g_wdg_btn_press = rgb_pack(40, 70, 130);
    g_wdg_btn_text = rgb_pack(240, 240, 255);
    g_wdg_input_bg = rgb_pack(25, 25, 35);
    g_wdg_input_border = rgb_pack(70, 70, 90);
    g_wdg_input_focus = rgb_pack(80, 120, 200);
    g_wdg_input_text = rgb_pack(230, 230, 240);
    g_wdg_dropdown_bg = rgb_pack(40, 40, 55);
    g_wdg_dropdown_sel = rgb_pack(55, 90, 160);
}

// ---------------------------------------------------------------------------
// Widget field accessors -- دوال الوصول لحقول المكونات
// ---------------------------------------------------------------------------
fn wdg_get_type(int idx) -> int { return getd(g_widgets, idx * 96 + 0); }
fn wdg_get_x(int idx) -> int { return getd(g_widgets, idx * 96 + 4); }
fn wdg_get_y(int idx) -> int { return getd(g_widgets, idx * 96 + 8); }
fn wdg_get_w(int idx) -> int { return getd(g_widgets, idx * 96 + 12); }
fn wdg_get_h(int idx) -> int { return getd(g_widgets, idx * 96 + 16); }
fn wdg_get_state(int idx) -> int { return getd(g_widgets, idx * 96 + 20); }
fn wdg_get_parent(int idx) -> int { return getd(g_widgets, idx * 96 + 24); }
fn wdg_get_id(int idx) -> int { return getd(g_widgets, idx * 96 + 28); }
fn wdg_get_text(int idx) -> char* { return cast<char*>(getq(g_widgets, idx * 96 + 32)); }
fn wdg_get_callback(int idx) -> int { return getq(g_widgets, idx * 96 + 40); }
fn wdg_get_value(int idx) -> int { return getd(g_widgets, idx * 96 + 48); }
fn wdg_get_maxlen(int idx) -> int { return getd(g_widgets, idx * 96 + 52); }
fn wdg_get_cursor(int idx) -> int { return getd(g_widgets, idx * 96 + 56); }
fn wdg_get_textbuf(int idx) -> char* { return cast<char*>(getq(g_widgets, idx * 96 + 60)); }
fn wdg_get_items(int idx) -> char* { return cast<char*>(getq(g_widgets, idx * 96 + 68)); }
fn wdg_get_itemcount(int idx) -> int { return getd(g_widgets, idx * 96 + 76); }
fn wdg_get_open(int idx) -> int { return getd(g_widgets, idx * 96 + 80); }
fn wdg_get_fg(int idx) -> int { return getd(g_widgets, idx * 96 + 84); }
fn wdg_get_bg(int idx) -> int { return getd(g_widgets, idx * 96 + 88); }

fn wdg_set_type(int idx, int v) -> void { putd(g_widgets, idx * 96 + 0, v); }
fn wdg_set_x(int idx, int v) -> void { putd(g_widgets, idx * 96 + 4, v); }
fn wdg_set_y(int idx, int v) -> void { putd(g_widgets, idx * 96 + 8, v); }
fn wdg_set_w(int idx, int v) -> void { putd(g_widgets, idx * 96 + 12, v); }
fn wdg_set_h(int idx, int v) -> void { putd(g_widgets, idx * 96 + 16, v); }
fn wdg_set_state(int idx, int v) -> void { putd(g_widgets, idx * 96 + 20, v); }
fn wdg_set_parent(int idx, int v) -> void { putd(g_widgets, idx * 96 + 24, v); }
fn wdg_set_id(int idx, int v) -> void { putd(g_widgets, idx * 96 + 28, v); }
fn wdg_set_text(int idx, char* v) -> void { putq(g_widgets, idx * 96 + 32, cast<int>(v)); }
fn wdg_set_callback(int idx, int v) -> void { putq(g_widgets, idx * 96 + 40, v); }
fn wdg_set_value(int idx, int v) -> void { putd(g_widgets, idx * 96 + 48, v); }
fn wdg_set_maxlen(int idx, int v) -> void { putd(g_widgets, idx * 96 + 52, v); }
fn wdg_set_cursor(int idx, int v) -> void { putd(g_widgets, idx * 96 + 56, v); }
fn wdg_set_textbuf(int idx, char* v) -> void { putq(g_widgets, idx * 96 + 60, cast<int>(v)); }
fn wdg_set_items(int idx, char* v) -> void { putq(g_widgets, idx * 96 + 68, cast<int>(v)); }
fn wdg_set_itemcount(int idx, int v) -> void { putd(g_widgets, idx * 96 + 76, v); }
fn wdg_set_open(int idx, int v) -> void { putd(g_widgets, idx * 96 + 80, v); }
fn wdg_set_fg(int idx, int v) -> void { putd(g_widgets, idx * 96 + 84, v); }
fn wdg_set_bg(int idx, int v) -> void { putd(g_widgets, idx * 96 + 88, v); }

// ===========================================================================
// BUTTON WIDGET -- مكون الزر
// ===========================================================================

// ---------------------------------------------------------------------------
// wdg_create_button -- إنشاء زر
// Create a button widget in a parent window.
// callback_name: name of the function to call when clicked (via fn_addr).
// Returns widget index.
// ---------------------------------------------------------------------------
fn wdg_create_button(int parent, int x, int y, int w, int h, char* label) -> int {
    if (g_widget_count >= 128) { return -1; }
    int idx = g_widget_count;
    g_widget_count = g_widget_count + 1;

    wdg_set_type(idx, 1);  // TYPE_BUTTON
    wdg_set_x(idx, x);
    wdg_set_y(idx, y);
    wdg_set_w(idx, w);
    wdg_set_h(idx, h);
    wdg_set_state(idx, 0);
    wdg_set_parent(idx, parent);
    wdg_set_id(idx, g_widget_next_id);
    g_widget_next_id = g_widget_next_id + 1;
    wdg_set_text(idx, label);
    wdg_set_callback(idx, 0);
    wdg_set_fg(idx, g_wdg_btn_text);
    wdg_set_bg(idx, g_wdg_btn_bg);

    return idx;
}

// ---------------------------------------------------------------------------
// wdg_draw_button -- رسم الزر
// Draw a button widget at absolute coordinates.
// ---------------------------------------------------------------------------
fn wdg_draw_button(int idx, int abs_x, int abs_y) -> void {
    int w = wdg_get_w(idx);
    int h = wdg_get_h(idx);
    int state = wdg_get_state(idx);

    // Choose background color based on state -- اختيار اللون حسب الحالة
    int bg = g_wdg_btn_bg;
    if (state == 1) { bg = g_wdg_btn_hover; }   // hover
    if (state == 2) { bg = g_wdg_btn_press; }   // pressed

    // Rounded gradient surface with a restrained drop shadow.
    int radius = h / 3;
    if (radius > 10) { radius = 10; }
    if (state != 2) {
        draw_soft_shadow(abs_x, abs_y, w, h, 2, rgb_pack(12, 14, 25));
    }
    int top_r = 65;
    int top_g = 112;
    int top_b = 205;
    int bot_r = 42;
    int bot_g = 75;
    int bot_b = 158;
    if (state == 1) {
        top_r = 88; top_g = 139; top_b = 235;
        bot_r = 57; bot_g = 96; bot_b = 190;
    }
    if (state == 2) {
        top_r = 38; top_g = 65; top_b = 135;
        bot_r = 30; bot_g = 52; bot_b = 112;
    }
    draw_rounded_rect(abs_x, abs_y, w, h, radius, bg);
    draw_gradient_rounded_rect(abs_x, abs_y, w, h, radius, top_r, top_g, top_b, bot_r, bot_g, bot_b);
    if (w > radius * 2) {
        draw_hline(abs_x + radius, abs_x + w - radius - 1, abs_y, rgb_pack(105, 150, 235));
    }

    // Draw text centered -- رسم النص في الوسط
    char* text = wdg_get_text(idx);
    int text_len = name_len(text);
    int text_w = text_len * 8;
    int tx = abs_x + (w - text_w) / 2;
    int ty = abs_y + (h - 8) / 2;
    draw_string(tx, ty, text, wdg_get_fg(idx));
}

// ===========================================================================
// TEXT INPUT WIDGET -- مكون حقل الإدخال النصي
// ===========================================================================

// ---------------------------------------------------------------------------
// wdg_create_textinput -- إنشاء حقل إدخال نصي
// Create a text input field. max_len = maximum string length.
// Returns widget index.
// ---------------------------------------------------------------------------
fn wdg_create_textinput(int parent, int x, int y, int w, int h, int max_len) -> int {
    if (g_widget_count >= 128) { return -1; }
    int idx = g_widget_count;
    g_widget_count = g_widget_count + 1;

    wdg_set_type(idx, 2);  // TYPE_TEXTINPUT
    wdg_set_x(idx, x);
    wdg_set_y(idx, y);
    wdg_set_w(idx, w);
    wdg_set_h(idx, h);
    wdg_set_state(idx, 0);
    wdg_set_parent(idx, parent);
    wdg_set_id(idx, g_widget_next_id);
    g_widget_next_id = g_widget_next_id + 1;
    wdg_set_maxlen(idx, max_len);
    wdg_set_cursor(idx, 0);
    wdg_set_fg(idx, g_wdg_input_text);
    wdg_set_bg(idx, g_wdg_input_bg);

    // Allocate text buffer -- تخصيص مخزن النص
    char* buf = cast<char*>(sys_mmap(0, max_len + 16, 3, 34, -1, 0));
    putb(buf, 0, 0); // empty string
    wdg_set_textbuf(idx, buf);
    wdg_set_text(idx, buf);

    return idx;
}

// ---------------------------------------------------------------------------
// wdg_draw_textinput -- رسم حقل الإدخال
// Draw a text input field at absolute coordinates.
// ---------------------------------------------------------------------------
fn wdg_draw_textinput(int idx, int abs_x, int abs_y) -> void {
    int w = wdg_get_w(idx);
    int h = wdg_get_h(idx);
    int focused = 0;
    if (g_widget_focus == idx) { focused = 1; }

    // Background -- الخلفية
    draw_rounded_rect(abs_x, abs_y, w, h, 7, g_wdg_input_bg);

    // Border (blue if focused) -- الإطار
    int bc = g_wdg_input_border;
    if (focused == 1) { bc = g_wdg_input_focus; }
    if (focused == 1) {
        draw_rounded_outline(abs_x - 1, abs_y - 1, w + 2, h + 2, 8, rgb_pack(55, 105, 210), g_wdg_input_bg);
        draw_rounded_outline(abs_x, abs_y, w, h, 7, bc, g_wdg_input_bg);
    } else {
        draw_rounded_outline(abs_x, abs_y, w, h, 7, bc, g_wdg_input_bg);
    }

    // Text -- النص
    char* text = wdg_get_textbuf(idx);
    int max_width = w - 8;
    if (max_width < 0) { max_width = 0; }
    int visible_chars = max_width / 8;
    int cursor_pos = wdg_get_cursor(idx);
    int scroll = 0;
    if (focused == 1 && visible_chars > 0 && cursor_pos >= visible_chars) {
        scroll = cursor_pos - visible_chars + 1;
    }
    draw_string_window(abs_x + 4, abs_y + (h - 8) / 2, text, scroll, max_width, g_wdg_input_text);

    // Cursor (blinking effect via simple toggle) -- مؤشر الكتابة
    if (focused == 1) {
        int visible_cursor = cursor_pos - scroll;
        if (visible_cursor < 0) { visible_cursor = 0; }
        if (visible_cursor > visible_chars) { visible_cursor = visible_chars; }
        int cx = abs_x + 4 + visible_cursor * 8;
        int cy = abs_y + (h - 8) / 2;
        // Draw cursor line
        int cursor_color = rgb_pack(200, 200, 255);
        draw_line(cx, cy, cx, cy + 7, cursor_color);
    }
}

// ---------------------------------------------------------------------------
// wdg_textinput_key -- معالجة ضغط مفتاح في حقل الإدخال
// Handle a key press in a text input field.
// scancode: Linux scancode, ascii: ASCII value
// ---------------------------------------------------------------------------
fn wdg_textinput_key(int idx, int scancode, int ascii) -> void {
    if (wdg_get_type(idx) != 2) { return; }

    char* buf = wdg_get_textbuf(idx);
    int len = name_len(buf);
    int cursor = wdg_get_cursor(idx);
    int max_len = wdg_get_maxlen(idx);

    // Backspace (scancode 14) -- حذف للخلف
    if (scancode == 14) {
        if (cursor > 0) {
            // Shift characters left
            int i = cursor - 1;
            while (i < len) {
                putb(buf, i, getb(buf, i + 1));
                i = i + 1;
            }
            wdg_set_cursor(idx, cursor - 1);
        }
        return;
    }

    // Delete (scancode 111)
    if (scancode == 111) {
        if (cursor < len) {
            int i = cursor;
            while (i < len) {
                putb(buf, i, getb(buf, i + 1));
                i = i + 1;
            }
        }
        return;
    }

    // Left arrow (scancode 105) -- سهم يسار
    if (scancode == 105) {
        if (cursor > 0) { wdg_set_cursor(idx, cursor - 1); }
        return;
    }

    // Right arrow (scancode 106) -- سهم يمين
    if (scancode == 106) {
        if (cursor < len) { wdg_set_cursor(idx, cursor + 1); }
        return;
    }

    // Home (scancode 102)
    if (scancode == 102) {
        wdg_set_cursor(idx, 0);
        return;
    }

    // End (scancode 107)
    if (scancode == 107) {
        wdg_set_cursor(idx, len);
        return;
    }

    // Printable ASCII -- حرف قابل للطباعة
    if ((ascii >= 32) && (ascii <= 126)) {
        if (len < max_len) {
            // Shift characters right to insert -- إدخال الحرف
            int i = len;
            while (i > cursor) {
                putb(buf, i, getb(buf, i - 1));
                i = i - 1;
            }
            putb(buf, cursor, ascii);
            putb(buf, len + 1, 0); // null terminate
            wdg_set_cursor(idx, cursor + 1);
        }
    }
}

// ---------------------------------------------------------------------------
// wdg_textinput_get_text -- الحصول على نص حقل الإدخال
// ---------------------------------------------------------------------------
fn wdg_textinput_get_text(int idx) -> char* {
    return wdg_get_textbuf(idx);
}

// ===========================================================================
// DROPDOWN MENU WIDGET -- مكون القائمة المنسدلة
// ===========================================================================

// ---------------------------------------------------------------------------
// wdg_create_dropdown -- إنشاء قائمة منسدلة
// items: pointer to array of char* (null-terminated list of item text pointers)
// stored as 8 bytes per pointer, null-terminated.
// count: number of items.
// Returns widget index.
// ---------------------------------------------------------------------------
fn wdg_create_dropdown(int parent, int x, int y, int w, int h, char* items, int count) -> int {
    if (g_widget_count >= 128) { return -1; }
    int idx = g_widget_count;
    g_widget_count = g_widget_count + 1;

    wdg_set_type(idx, 3);  // TYPE_DROPDOWN
    wdg_set_x(idx, x);
    wdg_set_y(idx, y);
    wdg_set_w(idx, w);
    wdg_set_h(idx, h);
    wdg_set_state(idx, 0);
    wdg_set_parent(idx, parent);
    wdg_set_id(idx, g_widget_next_id);
    g_widget_next_id = g_widget_next_id + 1;
    wdg_set_value(idx, 0);  // default selection = first item
    wdg_set_items(idx, items);
    wdg_set_itemcount(idx, count);
    wdg_set_open(idx, 0);
    wdg_set_fg(idx, g_wdg_input_text);
    wdg_set_bg(idx, g_wdg_dropdown_bg);

    return idx;
}

// ---------------------------------------------------------------------------
// wdg_dropdown_get_item -- الحصول على نص عنصر في القائمة
// Get the text of item at index `item_idx` from a dropdown.
// Items are stored as 8-byte pointers.
// ---------------------------------------------------------------------------
fn wdg_dropdown_get_item(int idx, int item_idx) -> char* {
    char* items = wdg_get_items(idx);
    return cast<char*>(getq(items, item_idx * 8));
}

// ---------------------------------------------------------------------------
// wdg_draw_dropdown -- رسم القائمة المنسدلة
// Draw a dropdown widget at absolute coordinates.
// ---------------------------------------------------------------------------
fn wdg_draw_dropdown(int idx, int abs_x, int abs_y) -> void {
    int w = wdg_get_w(idx);
    int h = wdg_get_h(idx);
    int count = wdg_get_itemcount(idx);
    int selected = wdg_get_value(idx);
    int is_open = wdg_get_open(idx);

    // Draw closed dropdown header -- رسم رأس القائمة المغلقة
    draw_rounded_rect(abs_x, abs_y, w, h, 7, g_wdg_dropdown_bg);
    draw_rounded_outline(abs_x, abs_y, w, h, 7, g_wdg_input_border, g_wdg_dropdown_bg);

    // Draw selected item text
    if (count > 0) {
        char* sel_text = wdg_dropdown_get_item(idx, selected);
        if (sel_text != cast<char*>(0)) {
            draw_string(abs_x + 8, abs_y + (h - 8) / 2, sel_text, g_wdg_input_text);
        }
    }

    // Draw arrow indicator (▼) -- رسم سهم القائمة
    int arrow_x = abs_x + w - 16;
    int arrow_y = abs_y + (h - 8) / 2;
    int ac = g_wdg_input_text;
    draw_line(arrow_x, arrow_y, arrow_x + 4, arrow_y + 4, ac);
    draw_line(arrow_x + 4, arrow_y + 4, arrow_x + 8, arrow_y, ac);

    // Draw open dropdown list -- رسم القائمة المفتوحة
    if (is_open == 1) {
        int ly = abs_y + h;
        int i = 0;
        while (i < count) {
            int item_bg = g_wdg_dropdown_bg;
            if (i == selected) {
                item_bg = g_wdg_dropdown_sel;
            }
            draw_filled_rect(abs_x, ly, w, h, item_bg);
            draw_rect(abs_x, ly, w, h, g_wdg_input_border);

            char* item_text = wdg_dropdown_get_item(idx, i);
            if (item_text != cast<char*>(0)) {
                int tc = g_wdg_input_text;
                draw_string(abs_x + 8, ly + (h - 8) / 2, item_text, tc);
            }
            ly = ly + h;
            i = i + 1;
        }
    }
}

// ---------------------------------------------------------------------------
// wdg_dropdown_toggle -- فتح/إغلاق القائمة
// Toggle dropdown open/close state.
// ---------------------------------------------------------------------------
fn wdg_dropdown_toggle(int idx) -> void {
    int current = wdg_get_open(idx);
    if (current == 1) {
        wdg_set_open(idx, 0);
    } else {
        wdg_set_open(idx, 1);
    }
}

// ---------------------------------------------------------------------------
// wdg_dropdown_select -- اختيار عنصر من القائمة
// Select an item from the dropdown by click position.
// rel_y: mouse Y relative to the dropdown's absolute Y
// Returns 1 if an item was selected.
// ---------------------------------------------------------------------------
fn wdg_dropdown_select(int idx, int rel_y) -> int {
    int h = wdg_get_h(idx);
    int count = wdg_get_itemcount(idx);

    if (rel_y < h) {
        // Clicked on header -> toggle
        wdg_dropdown_toggle(idx);
        return 0;
    }

    if (wdg_get_open(idx) == 1) {
        int item_idx = (rel_y - h) / h;
        if ((item_idx >= 0) && (item_idx < count)) {
            wdg_set_value(idx, item_idx);
            wdg_set_open(idx, 0);
            return 1;
        }
    }

    return 0;
}

// ===========================================================================
// LABEL WIDGET -- مكون العنوان
// ===========================================================================

fn wdg_create_label(int parent, int x, int y, char* text, int color) -> int {
    if (g_widget_count >= 128) { return -1; }
    int idx = g_widget_count;
    g_widget_count = g_widget_count + 1;

    wdg_set_type(idx, 4);  // TYPE_LABEL
    wdg_set_x(idx, x);
    wdg_set_y(idx, y);
    wdg_set_w(idx, name_len(text) * 8);
    wdg_set_h(idx, 8);
    wdg_set_state(idx, 0);
    wdg_set_parent(idx, parent);
    wdg_set_id(idx, g_widget_next_id);
    g_widget_next_id = g_widget_next_id + 1;
    wdg_set_text(idx, text);
    wdg_set_fg(idx, color);
    putd(g_widgets, idx * 96 + 92, 1);

    return idx;
}

fn wdg_draw_label(int idx, int abs_x, int abs_y) -> void {
    char* text = wdg_get_text(idx);
    int scale = getd(g_widgets, idx * 96 + 92);
    if (scale < 1) { scale = 1; }
    if (scale > 4) { scale = 4; }
    draw_string_scale(abs_x, abs_y, text, scale, wdg_get_fg(idx));
}

// Heading is a label rendered at 2x-4x bitmap scale. The requested scale is
// clamped to keep memory and framebuffer work bounded.
fn wdg_create_heading(int parent, int x, int y, char* text, int color, int scale) -> int {
    if (scale < 2) { scale = 2; }
    if (scale > 4) { scale = 4; }
    int idx = wdg_create_label(parent, x, y, text, color);
    if (idx < 0) { return -1; }
    putd(g_widgets, idx * 96 + 92, scale);
    wdg_set_w(idx, name_len(text) * 8 * scale);
    wdg_set_h(idx, 8 * scale);
    return idx;
}

// ===========================================================================
// GENERIC WIDGET FUNCTIONS -- دوال مكونات عامة
// ===========================================================================

// ---------------------------------------------------------------------------
// wdg_draw -- رسم مكون حسب نوعه
// Draw any widget by dispatching to the correct type-specific draw function.
// abs_x, abs_y: absolute screen coordinates of the widget.
// ---------------------------------------------------------------------------
fn wdg_draw(int idx, int abs_x, int abs_y) -> void {
    int t = wdg_get_type(idx);
    if (t == 1) { wdg_draw_button(idx, abs_x, abs_y); }
    if (t == 2) { wdg_draw_textinput(idx, abs_x, abs_y); }
    if (t == 3) { wdg_draw_dropdown(idx, abs_x, abs_y); }
    if (t == 4) { wdg_draw_label(idx, abs_x, abs_y); }
}

// ---------------------------------------------------------------------------
// wdg_draw_all_for_window -- رسم جميع مكونات نافذة معينة
// Draw all widgets belonging to a specific parent window.
// win_idx: window index. win_x, win_y: window's absolute content origin.
// ---------------------------------------------------------------------------
fn wdg_draw_all_for_window(int win_idx, int win_x, int win_y) -> void {
    int content_y = win_y + 24; // after title bar
    int i = 0;
    while (i < g_widget_count) {
        if (wdg_get_parent(i) == win_idx) {
            int ax = win_x + wdg_get_x(i);
            int ay = content_y + wdg_get_y(i);
            wdg_draw(i, ax, ay);
        }
        i = i + 1;
    }
}

// ---------------------------------------------------------------------------
// wdg_hit_test -- اختبار الضغط على مكون
// Find the widget at screen coordinates (mx, my) within a specific window.
// Returns widget index or -1.
// ---------------------------------------------------------------------------
fn wdg_hit_test(int win_idx, int win_x, int win_y, int mx, int my) -> int {
    int content_y = win_y + 24;
    int best = -1;
    int i = 0;
    while (i < g_widget_count) {
        if (wdg_get_parent(i) == win_idx) {
            int ax = win_x + wdg_get_x(i);
            int ay = content_y + wdg_get_y(i);
            int aw = wdg_get_w(i);
            int ah = wdg_get_h(i);

            // For open dropdowns, extend the hit area -- توسيع منطقة الضغط للقوائم المفتوحة
            if ((wdg_get_type(i) == 3) && (wdg_get_open(i) == 1)) {
                ah = ah + ah * wdg_get_itemcount(i);
            }

            if ((mx >= ax) && (mx < ax + aw) && (my >= ay) && (my < ay + ah)) {
                best = i;
            }
        }
        i = i + 1;
    }
    return best;
}

// ---------------------------------------------------------------------------
// wdg_focus -- تركيز مكون
// Set focus to a widget (for text input).
// ---------------------------------------------------------------------------
fn wdg_focus(int idx) -> void {
    g_widget_focus = idx;
}

fn wdg_get_focused() -> int {
    return g_widget_focus;
}

// ---------------------------------------------------------------------------
// wdg_handle_key -- معالجة ضغط مفتاح
// Route a key press to the focused widget (text input).
// ---------------------------------------------------------------------------
fn wdg_handle_key(int scancode, int ascii) -> void {
    if (g_widget_focus < 0) { return; }
    int idx = g_widget_focus;
    if (wdg_get_type(idx) == 2) {
        wdg_textinput_key(idx, scancode, ascii);
    }
}

// ---------------------------------------------------------------------------
// wdg_handle_click -- معالجة ضغط الماوس
// Handle a mouse click on a widget. Returns 1 if handled.
// ---------------------------------------------------------------------------
fn wdg_handle_click(int idx, int mx, int my, int win_x, int win_y) -> int {
    int t = wdg_get_type(idx);

    if (t == 1) { // Button
        wdg_set_state(idx, 2); // pressed
        return 1;
    }

    if (t == 2) { // Text input
        wdg_focus(idx);
        // Set cursor position based on click -- تحديد موضع المؤشر
        int content_y = win_y + 24;
        int ax = win_x + wdg_get_x(idx);
        int rel_x = mx - ax - 4;
        if (rel_x < 0) { rel_x = 0; }
        int pos = rel_x / 8;
        int len = name_len(wdg_get_textbuf(idx));
        if (pos > len) { pos = len; }
        wdg_set_cursor(idx, pos);
        return 1;
    }

    if (t == 3) { // Dropdown
        int content_y = win_y + 24;
        int ay = content_y + wdg_get_y(idx);
        int rel_y = my - ay;
        wdg_dropdown_select(idx, rel_y);
        return 1;
    }

    return 0;
}

// ---------------------------------------------------------------------------
// wdg_handle_release -- معالجة إفلات الماوس
// Handle mouse button release on a widget.
// ---------------------------------------------------------------------------
fn wdg_handle_release(int idx) -> void {
    int t = wdg_get_type(idx);
    if (t == 1) { // Button
        wdg_set_state(idx, 0);
        // TODO: call callback if set
    }
}

// ---------------------------------------------------------------------------
// wdg_update_hover -- تحديث حالة التمرير
// Update hover state for widgets in a window.
// ---------------------------------------------------------------------------
fn wdg_update_hover(int win_idx, int win_x, int win_y, int mx, int my) -> void {
    int content_y = win_y + 24;
    int i = 0;
    while (i < g_widget_count) {
        if (wdg_get_parent(i) == win_idx) {
            if (wdg_get_type(i) == 1) { // Button only
                int ax = win_x + wdg_get_x(i);
                int ay = content_y + wdg_get_y(i);
                int aw = wdg_get_w(i);
                int ah = wdg_get_h(i);
                if ((mx >= ax) && (mx < ax + aw) && (my >= ay) && (my < ay + ah)) {
                    if (wdg_get_state(i) != 2) { wdg_set_state(i, 1); } // hover
                } else {
                    if (wdg_get_state(i) != 2) { wdg_set_state(i, 0); } // normal
                }
            }
        }
        i = i + 1;
    }
}

fn wdg_get_count() -> int {
    return g_widget_count;
}
