// termgfx.mg - Pure Magnetar Terminal Graphics Library
// No external dependencies - uses ANSI escape codes

fn _esc(string seq) -> void {
    char esc = 27;
    print(esc, seq);
}

fn _esc_3(string a, int b, string c) -> void {
    char esc = 27;
    print(esc, a, b, c);
}

fn _esc_5(string a, int b, string c, int d, string e) -> void {
    char esc = 27;
    print(esc, a, b, c, d, e);
}

fn _esc_7(string a, int b, string c, int d, string e, int f, string g) -> void {
    char esc = 27;
    print(esc, a, b, c, d, e, f, g);
}

fn _esc_9(string a, int b, string c, int d, string e, int f, string g, int h, string i) -> void {
    char esc = 27;
    print(esc, a, b, c, d, e, f, g, h, i);
}

fn _color4(int r, int g, int b, string mode) -> void {
    _esc_7("[", r, ";", g, ";", b, mode);
}

fn _color8(int r, int g, int b, int r2, int g2, int b2, string mode) -> void {
    _esc_9("[", r, ";", g, ";", b, mode);
}

fn _rgb(int r, int g, int b) -> void {
    _color4(r, g, b, "m");
}

fn _bg_rgb(int r, int g, int b) -> void {
    _color4(r, g, b, "m");
}

fn _fg_rgb(int r, int g, int b) -> void {
    _color4(r, g, b, "m");
}

fn _esc_str(string prefix, string s, string suffix) -> void {
    char esc = 27;
    print(esc, prefix, s, suffix);
}

fn _esc_int(string prefix, int n, string suffix) -> void {
    char esc = 27;
    print(esc, prefix, n, suffix);
}

fn _repeat(string s, int count) -> void {
    int i = 0;
    while (i < count) {
        print(s);
        i = i + 1;
    }
}

// ── Screen Management ──

fn tg_init() -> void {
    _esc("[?25l");
    _esc("[2J");
    _esc("[H");
}

fn tg_clear(int r, int g, int b) -> void {
    int cols = 80;
    int rows = 24;
    int i = 1;
    _fg_rgb(r, g, b);
    while (i <= rows) {
        _esc_3("[", i, ";1H");
        _repeat(" ", cols);
        i = i + 1;
    }
}

fn tg_present() -> void {
    _esc("[H");
}

fn tg_shutdown() -> void {
    _esc("[0m");
    _esc("[2J");
    _esc("[H");
    _esc("[?25h");
}

fn tg_cursor_to(int row, int col) -> void {
    _esc_3("[", row, ";", col, "H");
}

fn tg_set_fg(int r, int g, int b) -> void {
    _esc_5("[38;2;", r, ";", g, ";", b, "m");
}

fn tg_set_bg(int r, int g, int b) -> void {
    _esc_5("[48;2;", r, ";", g, ";", b, "m");
}

fn tg_reset() -> void {
    _esc("[0m");
}

// ── Drawing Primitives ──

fn tg_draw_char(int row, int col, string ch) -> void {
    _esc_3("[", row, ";", col, "H");
    print(ch);
}

fn tg_draw_text(int row, int col, string text) -> void {
    _esc_3("[", row, ";", col, "H");
    print(text);
}

fn tg_draw_text_color(int row, int col, string text, int r, int g, int b) -> void {
    _esc_5("[", row, ";", col, "H");
    _fg_rgb(r, g, b);
    print(text);
    tg_reset();
}

fn tg_fill_rect(int row, int col, int height, int width, int r, int g, int b) -> void {
    int y = 0;
    while (y < height) {
        _esc_3("[", row + y, ";", col, "H");
        _fg_rgb(r, g, b);
        _repeat(" ", width);
        y = y + 1;
    }
    tg_reset();
}

fn tg_fill_rect_bg(int row, int col, int height, int width, int r, int g, int b) -> void {
    int y = 0;
    while (y < height) {
        _esc_3("[", row + y, ";", col, "H");
        _bg_rgb(r, g, b);
        _repeat(" ", width);
        y = y + 1;
    }
    tg_reset();
}

fn tg_draw_rect(int row, int col, int height, int width, int r, int g, int b) -> void {
    int x = 0;
    _fg_rgb(r, g, b);
    // top
    _esc_3("[", row, ";", col, "H");
    _repeat("=", width);
    // bottom
    _esc_3("[", row + height - 1, ";", col, "H");
    _repeat("=", width);
    // sides
    int y = 1;
    while (y < height - 1) {
        _esc_3("[", row + y, ";", col, "H");
        print("|");
        _esc_3("[", row + y, ";", col + width - 1, "H");
        print("|");
        y = y + 1;
    }
    // corners
    _esc_3("[", row, ";", col, "H");
    print("+");
    _esc_3("[", row, ";", col + width - 1, "H");
    print("+");
    _esc_3("[", row + height - 1, ";", col, "H");
    print("+");
    _esc_3("[", row + height - 1, ";", col + width - 1, "H");
    print("+");
    tg_reset();
}

fn tg_draw_rect_filled(int row, int col, int height, int width, int border_r, int border_g, int border_b, int fill_r, int fill_g, int fill_b) -> void {
    tg_draw_rect(row, col, height, width, border_r, border_g, border_b);
    if (height > 2 && width > 2) {
        tg_fill_rect_bg(row + 1, col + 1, height - 2, width - 2, fill_r, fill_g, fill_b);
    }
}

// ── Horizontal Gradient ──

fn tg_draw_gradient_x(int row, int col, int height, int width, int r1, int g1, int b1, int r2, int g2, int b2) -> void {
    int y = 0;
    while (y < height) {
        float t = y;
        t = t / height;
        int r = r1 + (r2 - r1) * t;
        int g = g1 + (g2 - g1) * t;
        int b = b1 + (b2 - b1) * t;
        _esc_3("[", row + y, ";", col, "H");
        _bg_rgb(r, g, b);
        _repeat(" ", width);
        y = y + 1;
    }
    tg_reset();
}

// ── Horizontal line ──

fn tg_draw_line_h(int row, int col, int length, int r, int g, int b) -> void {
    _fg_rgb(r, g, b);
    _esc_3("[", row, ";", col, "H");
    int i = 0;
    while (i < length) {
        print("─");
        i = i + 1;
    }
    tg_reset();
}

fn tg_draw_line_v(int row, int col, int length, int r, int g, int b) -> void {
    _fg_rgb(r, g, b);
    int i = 0;
    while (i < length) {
        _esc_3("[", row + i, ";", col, "H");
        print("│");
        i = i + 1;
    }
    tg_reset();
}

// ── Window ──

fn tg_window(int row, int col, int height, int width, string title, 
             int title_r, int title_g, int title_b,
             int border_r, int border_g, int border_b,
             int bg_r, int bg_g, int bg_b) -> void {
    // Title bar
    tg_fill_rect_bg(row, col, 1, width, title_r, title_g, title_b);
    _esc_3("[", row, ";", col + 2, "H");
    print(title);
    
    // Body background
    if (height > 1) {
        tg_fill_rect_bg(row + 1, col, height - 1, width, bg_r, bg_g, bg_b);
    }
    
    // Border
    tg_draw_rect(row, col, height, width, border_r, border_g, border_b);
}

// ── Button ──

fn tg_button(int row, int col, int width, string label, 
             int bg_r, int bg_g, int bg_b,
             int fg_r, int fg_g, int fg_b) -> void {
    tg_fill_rect_bg(row, col, 1, width, bg_r, bg_g, bg_b);
    _fg_rgb(fg_r, fg_g, fg_b);
    int text_col = col + (width / 2) - (1);
    _esc_3("[", row, ";", text_col, "H");
    print(label);
    tg_reset();
}
// desktop.mg - Pure Falcon Desktop UI Library
// No external C dependencies - uses ANSI escape codes and built-in print

// ─── Terminal Control ───

fn _esc3(string a, int b, string c) -> void {
    char esc = 27;
    print(esc, a, b, c);
}

fn _esc5(string a, int b, string c, int d, string e) -> void {
    char esc = 27;
    print(esc, a, b, c, d, e);
}

fn set_fg(int r, int g, int b) -> void {
    _esc5("[38;2;", r, ";", g, ";", b, "m");
}

fn set_bg(int r, int g, int b) -> void {
    _esc5("[48;2;", r, ";", g, ";", b, "m");
}

fn reset_attr() -> void {
    _esc("[0m");
}

fn cursor_to(int row, int col) -> void {
    _esc3("[", row, ";", col, "H");
}

fn show_cursor() -> void {
    _esc("[?25h");
}

fn hide_cursor() -> void {
    _esc("[?25l");
}

fn clear_screen() -> void {
    _esc("[2J");
    _esc("[H");
}

// ─── Color Helpers ───

fn darken_c(int c, float amount) -> int {
    int r = c * (1.0 - amount);
    if (r < 0) { r = 0; }
    return r;
}

fn lighten_c(int c, float amount) -> int {
    int r = c + (255 - c) * amount;
    if (r > 255) { r = 255; }
    return r;
}

// ─── Drawing Primitives ───

fn draw_text(int row, int col, string text) -> void {
    cursor_to(row, col);
    print(text);
}

fn draw_text_color(int row, int col, string text, int fg_r, int fg_g, int fg_b) -> void {
    set_fg(fg_r, fg_g, fg_b);
    cursor_to(row, col);
    print(text);
    reset_attr();
}

fn fill_rect(int row, int col, int height, int width, int r, int g, int b) -> void {
    int y = 0;
    set_bg(r, g, b);
    while (y < height) {
        cursor_to(row + y, col);
        _repeat(" ", width);
        y = y + 1;
    }
    reset_attr();
}

fn draw_rect(int row, int col, int height, int width, int r, int g, int b) -> void {
    set_fg(r, g, b);
    cursor_to(row, col);
    print("+");
    int x = 1;
    while (x < width - 1) {
        print("-");
        x = x + 1;
    }
    print("+");
    int y = 1;
    while (y < height - 1) {
        cursor_to(row + y, col);
        print("|");
        cursor_to(row + y, col + width - 1);
        print("|");
        y = y + 1;
    }
    cursor_to(row + height - 1, col);
    print("+");
    x = 1;
    while (x < width - 1) {
        print("-");
        x = x + 1;
    }
    print("+");
    reset_attr();
}

fn fill_rect_border(int row, int col, int height, int width, int bg_r, int bg_g, int bg_b, int bd_r, int bd_g, int bd_b) -> void {
    fill_rect(row, col, height, width, bg_r, bg_g, bg_b);
    draw_rect(row, col, height, width, bd_r, bd_g, bd_b);
}

fn draw_hline(int row, int col, int length, int r, int g, int b) -> void {
    set_fg(r, g, b);
    cursor_to(row, col);
    int i = 0;
    while (i < length) {
        print("-");
        i = i + 1;
    }
    reset_attr();
}

// ─── Window ───

fn draw_window(int row, int col, int height, int width, string title,
               int bg_r, int bg_g, int bg_b, int bd_r, int bd_g, int bd_b) -> void {
    // Title bar
    int tbr, tbg, tbb;
    tbr = darken_c(bg_r, 0.3);
    tbg = darken_c(bg_g, 0.3);
    tbb = darken_c(bg_b, 0.3);
    fill_rect(row, col, 3, width, tbr, tbg, tbb);
    set_fg(200, 200, 220);
    cursor_to(row + 1, col + 2);
    print(title);
    reset_attr();
    // Body
    fill_rect(row + 3, col, height - 3, width, bg_r, bg_g, bg_b);
    // Border
    draw_rect(row, col, height, width, bd_r, bd_g, bd_b);
}

// ─── Button ───

fn draw_button(int row, int col, int width, string label, int focused,
               int btn_r, int btn_g, int btn_b, int bd_r, int bd_g, int bd_b, int fg_r, int fg_g, int fg_b) -> void {
    int br, bg, bb;
    if (focused == 1) {
        br = lighten_c(btn_r, 0.3);
        bg = lighten_c(btn_g, 0.3);
        bb = lighten_c(btn_b, 0.3);
    } else {
        br = btn_r; bg = btn_g; bb = btn_b;
    }
    fill_rect(row, col, 3, width, br, bg, bb);
    draw_rect(row, col, 3, width, bd_r, bd_g, bd_b);
    set_fg(fg_r, fg_g, fg_b);
    int tx = col + (width / 2) - (1);
    cursor_to(row + 1, tx);
    print(label);
    reset_attr();
}

fn button_hit(int row, int col, int width, int mouse_row, int mouse_col) -> int {
    if (mouse_row >= row && mouse_row < row + 3 &&
        mouse_col >= col && mouse_col < col + width) {
        return 1;
    }
    return 0;
}

// ─── Progress Bar ───

fn draw_progress(int row, int col, int width, float value,
                 int bg_r, int bg_g, int bg_b, int ac_r, int ac_g, int ac_b) -> void {
    int fill_w = width * value;

    // Track background
    int tr, tg, tb;
    tr = lighten_c(bg_r, 0.15);
    tg = lighten_c(bg_g, 0.15);
    tb = lighten_c(bg_b, 0.15);
    fill_rect(row, col, 3, width, tr, tg, tb);

    // Fill
    if (fill_w > 0) {
        fill_rect(row, col, 3, fill_w, ac_r, ac_g, ac_b);
    }

    // Border
    draw_rect(row, col, 3, width, 60, 65, 100);

    // Percentage text
    set_fg(200, 200, 220);
    int pct = value * 100;
    cursor_to(row + 1, col + (width / 2) - 2);
    print(pct);
    print("%");
    reset_attr();
}

// ─── Label ───

fn draw_label(int row, int col, string text, int fg_r, int fg_g, int fg_b) -> void {
    set_fg(fg_r, fg_g, fg_b);
    cursor_to(row, col);
    print(text);
    reset_attr();
}

// ─── Panel ───

fn draw_panel(int row, int col, int height, int width, string title,
              int bg_r, int bg_g, int bg_b, int bd_r, int bd_g, int bd_b) -> void {
    int pr, pg, pb;
    pr = lighten_c(bg_r, 0.05);
    pg = lighten_c(bg_g, 0.05);
    pb = lighten_c(bg_b, 0.05);
    fill_rect(row, col, height, width, pr, pg, pb);
    draw_rect(row, col, height, width, bd_r, bd_g, bd_b);
    if (title != "") {
        set_fg(80, 160, 255);
        cursor_to(row, col + 2);
        print(title);
        reset_attr();
    }
}

// ─── Status Bar ───

fn draw_statusbar(int row, int col, int width, string text, string ctx,
                  int bg_r, int bg_g, int bg_b, int bd_r, int bd_g, int bd_b) -> void {
    int sr, sg, sb;
    sr = darken_c(bg_r, 0.2);
    sg = darken_c(bg_g, 0.2);
    sb = darken_c(bg_b, 0.2);
    fill_rect(row, col, 3, width, sr, sg, sb);
    draw_hline(row, col, width, bd_r, bd_g, bd_b);
    set_fg(100, 100, 130);
    cursor_to(row + 1, col + 2);
    print(text);
    if (ctx != "") {
        set_fg(80, 160, 255);
        int ctx_x = col + width - 2;
        cursor_to(row + 1, ctx_x - ctx.length);
        print(ctx);
    }
    reset_attr();
}

// ─── List Box Item ───

fn draw_list_item(int row, int col, string text, int width, int selected,
                  int ac_r, int ac_g, int ac_b, int fg_r, int fg_g, int fg_b) -> void {
    if (selected == 1) {
        fill_rect(row, col, 1, width, ac_r, ac_g, ac_b);
        set_fg(255, 255, 255);
    } else {
        set_fg(fg_r, fg_g, fg_b);
    }
    cursor_to(row, col + 1);
    print(text);
    reset_attr();
}
