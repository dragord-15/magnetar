static char* RG_LINE;
static char* RG_STATUS;
static char* RG_TREE_NAME;
static int RG_SELECTING;

fn render_gui_init() -> void {
    RG_LINE = alloc<char>(2048);
    RG_STATUS = alloc<char>(512);
    RG_TREE_NAME = alloc<char>(256);
    *(RG_LINE) = 0;
    *(RG_STATUS) = 0;
    *(RG_TREE_NAME) = 0;
    RG_SELECTING = 0;
}

fn rg_append(char* dst, int cap, int at, string src) -> int {
    char* p = cast<char*>(src);
    int i = 0;
    while (*(p + i) != 0 && at < cap - 1) {
        *(dst + at) = *(p + i);
        at = at + 1;
        i = i + 1;
    }
    *(dst + at) = 0;
    return at;
}

fn rg_text(int x, int y, string s, int color, int scale) -> void {
    int old = gui_get_scale();
    if (old != scale) { gui_set_scale(scale); }
    gui_draw_text_fg(x, y, s, color, 255);
    if (old != scale) { gui_set_scale(old); }
}

fn rg_text_clip(int x, int y, string s, int color, int maxw, int scale) -> void {
    int old = gui_get_scale();
    if (old != scale) { gui_set_scale(scale); }
    dsk_text_clip_fg(x, y, s, color, maxw);
    if (old != scale) { gui_set_scale(old); }
}

fn rg_text_center(int x, int y, int w, string s, int color) -> void {
    int old = gui_get_scale();
    if (old != 1) { gui_set_scale(1); }
    dsk_text_center_fg(x, y, w, s, color);
    if (old != 1) { gui_set_scale(old); }
}

fn rg_draw_button(int x, int y, int w, int h, string label, int active) -> void {
    int bg = TH.btn;
    int fg = TH.text;
    if (active == 1) {
        bg = TH.btn_on;
        fg = TH.green;
    }
    gui_fill_rounded_rect(x, y, w, h, 5, bg);
    gui_fill_rect(x + 3, y, w - 6, 1, TH.border);
    gui_fill_rect(x + 3, y + h - 1, w - 6, 1, TH.border);
    rg_text_center(x, y + 9, w, label, fg);
}

fn rg_btn_start(int w) -> int {
    return w - 566;
}

fn rg_btn_x(int w, int i) -> int {
    return rg_btn_start(w) + i * 68;
}

fn rg_draw_header(int w) -> void {
    gui_fill_gradient_v(0, 0, w, VIEW_HEADER_H, TH.header_top, TH.header_bottom);
    gui_fill_rect(0, VIEW_HEADER_H - 1, w, 1, TH.border);
    gui_fill_rounded_rect(14, 14, 4, 30, 2, TH.accent);
    rg_text(24, 9, "MGEDIT", TH.text, 2);
    string path = doc_path();
    if (doc_path_len() == 0) { path = "UNTITLED"; }
    string state = "UNSAVED";
    int state_col = TH.orange;
    if (doc_is_dirty() == 0) {
        state = "SAVED";
        state_col = TH.green;
    }
    int sw = gui_text_width(state, 1);
    int maxw = rg_btn_start(w) - 24 - sw - 16;
    if (maxw < 60) { maxw = 60; }
    rg_text_clip(24, 34, path, TH.muted, maxw, 1);
    rg_text(rg_btn_start(w) - 12 - sw, 34, state, state_col, 1);
    int bx = rg_btn_start(w);
    rg_draw_button(bx, 12, 62, 26, "NEW", 0);
    rg_draw_button(bx + 68, 12, 62, 26, "OPEN", 0);
    rg_draw_button(bx + 136, 12, 62, 26, "DIR", 0);
    rg_draw_button(bx + 204, 12, 62, 26, "SAVE", 0);
    rg_draw_button(bx + 272, 12, 62, 26, "BUILD", 0);
    rg_draw_button(bx + 340, 12, 62, 26, "MERGE", 0);
    rg_draw_button(bx + 408, 12, 62, 26, "FILES", VIEW_TREE_ON);
    rg_draw_button(bx + 476, 12, 62, 26, "THEME", 0);
}

fn rg_draw_span(char* p, int st, int en, int ls, int color, int y, int* vcp, int scroll, int sel_a, int sel_b, int line_bg) -> void {
    int vc = *vcp;
    int cols = view_cols();
    int i = st;
    while (i < en) {
        int c = syn_byte(p, i);
        int adv = 1;
        int ch = c;
        if (c == 9) {
            int tab = CFG_TAB_SIZE;
            if (tab < 1) { tab = 4; }
            adv = tab - (vc - (vc / tab) * tab);
            ch = 32;
        } else if (c < 32 || c > 126) {
            ch = 32;
        }
        int a = 0;
        while (a < adv) {
            int col = vc + a;
            if (col >= scroll && col < scroll + cols) {
                int x = VIEW_TEXT_X + (col - scroll) * VIEW_CHAR_W;
                int bg = line_bg;
                int fg = color;
                if (ls + i >= sel_a && ls + i < sel_b) {
                    bg = TH.sel;
                    fg = TH.sel_fg;
                }
                gui_draw_char(x, y, ch, fg, bg, 1);
            }
            a = a + 1;
        }
        vc = vc + adv;
        i = i + 1;
    }
    *vcp = vc;
}

fn rg_draw_code(int ls, int y, int line_bg) -> void {
    int n = edit_len(RG_LINE);
    int vc = 0;
    int sel_a = doc_selection_start();
    int sel_b = doc_selection_end();
    int i = 0;
    while (i < n) {
        int kind = syn_kind_at(cast<string>(RG_LINE), i);
        int j = i + 1;
        while (j < n) {
            int k = syn_kind_at(cast<string>(RG_LINE), j);
            if (k != kind) { break; }
            j = j + 1;
        }
        rg_draw_span(RG_LINE, i, j, ls, theme_syntax_color(kind), y, &vc, VIEW_SCROLL_X, sel_a, sel_b, line_bg);
        i = j;
    }
}

fn rg_draw_line(int li, int y, int w) -> void {
    int ls = doc_line_start(li);
    int le = doc_line_end(li);
    int cur_line = doc_line_index(doc_cursor());
    int is_cur = 0;
    if (li == cur_line) { is_cur = 1; }
    int line_bg = TH.bg;
    int gx = 0;
    if (VIEW_TREE_ON == 1) { gx = VIEW_TREE_W; }
    if (is_cur == 1) {
        line_bg = TH.line;
        gui_fill_rect(gx + VIEW_GUTTER_W + 1, y - 1, w - gx - VIEW_GUTTER_W - 1, VIEW_LINE_H, line_bg);
        gui_fill_rect(gx, y - 1, 2, VIEW_LINE_H, TH.accent);
    }
    if (CFG_SHOW_LINES == 1) {
        string ns = dsk_itoa(li + 1);
        int nw = gui_text_width(ns, 1);
        int ncolor = TH.gutter_text;
        if (is_cur == 1) { ncolor = TH.accent; }
        dsk_text_clip(gx + VIEW_GUTTER_W - 8 - nw, y, ns, ncolor, TH.gutter, VIEW_GUTTER_W - 8);
    }
    doc_line_copy(li, RG_LINE, 2048);
    rg_draw_code(ls, y, line_bg);
    if (is_cur == 1) {
        int caret_vc = doc_visual_col(ls, doc_cursor());
        if (caret_vc >= VIEW_SCROLL_X && caret_vc < VIEW_SCROLL_X + view_cols()) {
            if ((ED_FRAME / 30) - ((ED_FRAME / 30) / 2) * 2 == 0) {
                int cx = VIEW_TEXT_X + (caret_vc - VIEW_SCROLL_X) * VIEW_CHAR_W;
                gui_fill_rect(cx, y, 2, VIEW_LINE_H - 2, TH.caret);
            }
        }
    }
}

fn rg_draw_tree(int w, int h) -> void {
    if (VIEW_TREE_ON == 0) { return; }
    int bottom = h - VIEW_STATUS_H;
    if (VIEW_LINT_ON == 1) { bottom = bottom - VIEW_LINT_H; }
    gui_fill_rect(0, VIEW_HEADER_H, VIEW_TREE_W, bottom - VIEW_HEADER_H, TH.tree_bg);
    gui_fill_rect(VIEW_TREE_W - 1, VIEW_HEADER_H, 1, bottom - VIEW_HEADER_H, TH.border);
    rg_text(14, VIEW_HEADER_H + 10, "FILES", TH.accent, 1);
    rg_text_clip(14, VIEW_HEADER_H + 34, cast<string>(FT_DIR), TH.muted, VIEW_TREE_W - 24, 1);
    int y = VIEW_HEADER_H + FT_TOP_OFFSET;
    int n = ft_count();
    int i = 0;
    while (i < n && y < bottom - FT_ROW_H) {
        int selected = 0;
        if (i == ft_selected()) { selected = 1; }
        if (selected == 1) {
            gui_fill_rounded_rect(6, y - 2, VIEW_TREE_W - 12, FT_ROW_H, 4, TH.tree_sel);
        }
        ft_name_at(i, RG_TREE_NAME, 256);
        int color = TH.tree_text;
        if (selected == 1) { color = TH.text; }
        rg_text_clip(16, y, cast<string>(RG_TREE_NAME), color, VIEW_TREE_W - 28, 1);
        y = y + FT_ROW_H;
        i = i + 1;
    }
}

fn rg_draw_editor(int w, int h) -> void {
    int bottom = h - VIEW_STATUS_H;
    if (VIEW_LINT_ON == 1) { bottom = bottom - VIEW_LINT_H; }
    int eh = bottom - VIEW_HEADER_H;
    gui_fill_rect(0, VIEW_HEADER_H, w, eh, TH.bg);
    int gx = 0;
    if (VIEW_TREE_ON == 1) { gx = VIEW_TREE_W; }
    gui_fill_rect(gx, VIEW_HEADER_H, VIEW_GUTTER_W, eh, TH.gutter);
    gui_fill_rect(gx + VIEW_GUTTER_W, VIEW_HEADER_H, 1, eh, TH.border);
    view_clamp_scroll();
    int y = VIEW_TEXT_Y;
    int li = VIEW_SCROLL_Y;
    int count = 0;
    while (li < doc_line_count() && count < VIEW_ROWS) {
        rg_draw_line(li, y, w);
        li = li + 1;
        y = y + VIEW_LINE_H;
        count = count + 1;
    }
}

fn rg_draw_status(int w, int h) -> void {
    int y = h - VIEW_STATUS_H;
    gui_fill_rect(0, y, w, VIEW_STATUS_H, TH.status);
    gui_fill_rect(0, y, w, 1, TH.border);
    if (ED_MODE == ED_MODE_SEARCH) {
        int at = 0;
        at = rg_append(RG_STATUS, 512, at, "Find: ");
        at = rg_append(RG_STATUS, 512, at, search_query_text());
        rg_text_clip(12, y + 9, cast<string>(RG_STATUS), TH.accent, w - 300, 1);
    } else {
        int li = doc_line_index(doc_cursor());
        int col = doc_visual_col(doc_line_start(li), doc_cursor()) + 1;
        int at = 0;
        at = rg_append(RG_STATUS, 512, at, "Ln ");
        at = rg_append(RG_STATUS, 512, at, dsk_itoa(li + 1));
        at = rg_append(RG_STATUS, 512, at, "   Col ");
        at = rg_append(RG_STATUS, 512, at, dsk_itoa(col));
        at = rg_append(RG_STATUS, 512, at, "   ");
        at = rg_append(RG_STATUS, 512, at, dsk_itoa(doc_line_count()));
        at = rg_append(RG_STATUS, 512, at, " lines   ");
        at = rg_append(RG_STATUS, 512, at, dsk_itoa(doc_len()));
        at = rg_append(RG_STATUS, 512, at, " chars");
        if (doc_is_dirty() == 1) {
            at = rg_append(RG_STATUS, 512, at, "   *");
        }
        int maxw = w - 340;
        if (maxw < 80) { maxw = 80; }
        rg_text_clip(12, y + 9, cast<string>(RG_STATUS), TH.muted, maxw, 1);
    }
    string au = "AUTOSAVE OFF";
    int au_col = TH.muted;
    if (CFG_AUTOSAVE == 1) {
        au = "AUTOSAVE ON";
        au_col = TH.green;
    }
    int aw = gui_text_width(au, 1);
    rg_text(w - aw - 14, y + 9, au, au_col, 1);
}

fn rg_draw_lint(int w, int h) -> void {
    if (VIEW_LINT_ON == 0) { return; }
    int y = h - VIEW_STATUS_H - VIEW_LINT_H;
    gui_fill_rect(0, y, w, VIEW_LINT_H, TH.panel);
    gui_fill_rect(0, y, w, 1, TH.border);
    int state = lint_state();
    string title = "LINT";
    int tc = TH.muted;
    if (state == 1) { title = "LINT / OK"; tc = TH.green; }
    if (state == 2) { title = "LINT / ERRORS"; tc = TH.orange; }
    rg_text(14, y + 9, title, tc, 1);
    string text = lint_text();
    if (len(text) == 0) {
        rg_text(14, y + 32, "No build log yet. Press Ctrl+B to build.", TH.muted, 1);
        return;
    }
    char* p = cast<char*>(text);
    int i = 0;
    int row = 0;
    int ty = y + 30;
    while (*(p + i) != 0 && row < 6) {
        int st = i;
        while (*(p + i) != 0 && *(p + i) != 10) { i = i + 1; }
        int n = i - st;
        int k = 0;
        while (k < n && k < 2047) {
            RG_LINE[k] = *(p + st + k);
            k = k + 1;
        }
        RG_LINE[k] = 0;
        if (k > 0) {
            int c = TH.tree_text;
            if (lint_has(cast<string>(RG_LINE), "error") == 1) { c = TH.orange; }
            rg_text_clip(14, ty, cast<string>(RG_LINE), c, w - 28, 1);
            ty = ty + 16;
            row = row + 1;
        }
        if (*(p + i) == 10) { i = i + 1; }
    }
}

fn rg_draw_msg(int w, int h) -> void {
    string s = cast<string>(ED_MSG_BUF);
    int tw = gui_text_width(s, 1);
    int bw = tw + 28;
    if (bw > w - 40) { bw = w - 40; }
    int x = (w - bw) / 2;
    int y = h - VIEW_STATUS_H - 42;
    gui_fill_rounded_rect(x, y, bw, 28, 7, TH.message_bg);
    gui_fill_rect(x + 2, y, bw - 4, 1, TH.accent);
    rg_text_center(x + 10, y + 10, bw - 20, s, TH.text);
}

fn render_gui_draw() -> void {
    view_update_layout();
    int w = dsk_screen_w();
    int h = dsk_screen_h();
    gui_clear(TH.bg);
    rg_draw_header(w);
    rg_draw_editor(w, h);
    rg_draw_tree(w, h);
    rg_draw_lint(w, h);
    rg_draw_status(w, h);
    if (ED_MSG_TTL > 0) { rg_draw_msg(w, h); }
    if (gui_is_x11() == 0) { dsk_draw_cursor(gui_mouse_x(), gui_mouse_y()); }
}

fn rg_set_cursor_from_mouse(int mx, int my, int extend) -> void {
    int li = VIEW_SCROLL_Y + (my - VIEW_TEXT_Y) / VIEW_LINE_H;
    if (li < 0) { li = 0; }
    if (li >= doc_line_count()) { li = doc_line_count() - 1; }
    int col = (mx - VIEW_TEXT_X) / VIEW_CHAR_W + VIEW_SCROLL_X;
    if (mx < VIEW_TEXT_X) { col = 0; }
    if (col < 0) { col = 0; }
    int pos = doc_offset_from_visual_col(li, col);
    doc_set_cursor(pos, extend);
    view_ensure_cursor_visible();
}

fn rg_handle_header_click(int mx, int my, int w) -> int {
    if (my < 10 || my > 42) { return 0; }
    int bx = rg_btn_start(w);
    int idx = (mx - bx) / 68;
    if (mx < bx) { return 0; }
    if (idx == 0) { cmd_run(CMD_NEW); return 1; }
    if (idx == 1) { cmd_run(CMD_OPEN); return 1; }
    if (idx == 2) { cmd_run(CMD_OPEN_FOLDER); return 1; }
    if (idx == 3) { cmd_run(CMD_SAVE); return 1; }
    if (idx == 4) { cmd_run(CMD_BUILD); return 1; }
    if (idx == 5) { cmd_run(CMD_BUNDLE); return 1; }
    if (idx == 6) { cmd_run(CMD_TOGGLE_TREE); return 1; }
    if (idx == 7) { cmd_run(CMD_TOGGLE_THEME); return 1; }
    return 0;
}

fn render_gui_handle_mouse() -> void {
    view_update_layout();
    int w = dsk_screen_w();
    int h = dsk_screen_h();
    int mx = gui_mouse_x();
    int my = gui_mouse_y();
    int wheel = gui_mouse_wheel();
    int bottom = h - VIEW_STATUS_H;
    if (VIEW_LINT_ON == 1) { bottom = bottom - VIEW_LINT_H; }
    if (wheel != 0 && my >= VIEW_HEADER_H && my < bottom) {
        view_scroll(0, -wheel * 3);
        return;
    }
    if (gui_mouse_clicked() == 1) {
        if (my < VIEW_HEADER_H) {
            rg_handle_header_click(mx, my, w);
            return;
        }
        if (VIEW_TREE_ON == 1 && mx < VIEW_TREE_W) {
            int idx = ft_index_at_y(my);
            if (idx >= 0) {
                ft_set_selected(idx);
                ft_open_index(idx);
            }
            return;
        }
        if (my >= VIEW_HEADER_H && my < bottom && mx >= VIEW_TEXT_X) {
            rg_set_cursor_from_mouse(mx, my, gui_shift_down());
            RG_SELECTING = 1;
            return;
        }
    }
    if (RG_SELECTING == 1) {
        if (gui_mouse_left() == 1) {
            int yy = my;
            if (yy < VIEW_TEXT_Y) { yy = VIEW_TEXT_Y; }
            if (yy >= bottom) { yy = bottom - 1; }
            rg_set_cursor_from_mouse(mx, yy, 1);
        } else {
            RG_SELECTING = 0;
        }
    }
}
