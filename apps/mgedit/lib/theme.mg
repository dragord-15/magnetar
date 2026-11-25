struct Theme {
    int bg;
    int gutter;
    int gutter_text;
    int border;
    int text;
    int muted;
    int accent;
    int key;
    int type;
    int func;
    int str;
    int num;
    int comment;
    int line;
    int sel;
    int sel_fg;
    int caret;
    int header_top;
    int header_bottom;
    int btn;
    int btn_on;
    int status;
    int green;
    int orange;
    int message_bg;
    int tree_bg;
    int tree_text;
    int tree_sel;
    int panel;
}

static Theme* TH;
static int THEME_DARK;

fn theme_load_dark() -> void {
    TH.bg = gui_rgb(13, 17, 23);
    TH.gutter = gui_rgb(19, 24, 32);
    TH.gutter_text = gui_rgb(90, 102, 122);
    TH.border = gui_rgb(38, 47, 62);
    TH.text = gui_rgb(222, 228, 240);
    TH.muted = gui_rgb(138, 149, 168);
    TH.accent = gui_rgb(88, 166, 255);
    TH.key = gui_rgb(255, 121, 198);
    TH.type = gui_rgb(121, 192, 255);
    TH.func = gui_rgb(210, 168, 255);
    TH.str = gui_rgb(158, 206, 106);
    TH.num = gui_rgb(247, 184, 104);
    TH.comment = gui_rgb(109, 124, 145);
    TH.line = gui_rgb(22, 28, 38);
    TH.sel = gui_rgb(38, 79, 120);
    TH.sel_fg = gui_rgb(255, 255, 255);
    TH.caret = gui_rgb(240, 240, 240);
    TH.header_top = gui_rgb(20, 26, 36);
    TH.header_bottom = gui_rgb(13, 17, 23);
    TH.btn = gui_rgb(31, 39, 53);
    TH.btn_on = gui_rgb(28, 74, 48);
    TH.status = gui_rgb(17, 22, 30);
    TH.green = gui_rgb(110, 220, 150);
    TH.orange = gui_rgb(247, 184, 104);
    TH.message_bg = gui_rgb(30, 38, 52);
    TH.tree_bg = gui_rgb(17, 22, 30);
    TH.tree_text = gui_rgb(184, 195, 214);
    TH.tree_sel = gui_rgb(34, 52, 74);
    TH.panel = gui_rgb(20, 26, 35);
}

fn theme_load_light() -> void {
    TH.bg = gui_rgb(246, 248, 252);
    TH.gutter = gui_rgb(233, 237, 245);
    TH.gutter_text = gui_rgb(115, 125, 145);
    TH.border = gui_rgb(205, 212, 225);
    TH.text = gui_rgb(34, 42, 56);
    TH.muted = gui_rgb(105, 116, 136);
    TH.accent = gui_rgb(32, 110, 210);
    TH.key = gui_rgb(175, 35, 125);
    TH.type = gui_rgb(24, 100, 170);
    TH.func = gui_rgb(110, 60, 170);
    TH.str = gui_rgb(48, 120, 58);
    TH.num = gui_rgb(170, 90, 20);
    TH.comment = gui_rgb(125, 134, 150);
    TH.line = gui_rgb(237, 242, 250);
    TH.sel = gui_rgb(190, 216, 248);
    TH.sel_fg = gui_rgb(20, 30, 45);
    TH.caret = gui_rgb(25, 35, 50);
    TH.header_top = gui_rgb(240, 244, 251);
    TH.header_bottom = gui_rgb(229, 235, 245);
    TH.btn = gui_rgb(222, 229, 240);
    TH.btn_on = gui_rgb(196, 231, 205);
    TH.status = gui_rgb(235, 239, 247);
    TH.green = gui_rgb(35, 140, 80);
    TH.orange = gui_rgb(190, 105, 30);
    TH.message_bg = gui_rgb(225, 233, 245);
    TH.tree_bg = gui_rgb(237, 241, 249);
    TH.tree_text = gui_rgb(55, 66, 82);
    TH.tree_sel = gui_rgb(198, 219, 245);
    TH.panel = gui_rgb(240, 244, 251);
}

fn theme_apply(int dark) -> void {
    if (dark == 1) { theme_load_dark(); } else { theme_load_light(); }
    THEME_DARK = dark;
    CFG_THEME = dark;
}

fn theme_init() -> void {
    TH = new Theme;
    theme_apply(CFG_THEME);
}

fn theme_toggle() -> void {
    theme_apply(1 - THEME_DARK);
}

fn theme_dark() -> int {
    return THEME_DARK;
}

fn theme_syntax_color(int kind) -> int {
    if (kind == 1) { return TH.key; }
    if (kind == 2) { return TH.str; }
    if (kind == 3) { return TH.num; }
    if (kind == 4) { return TH.comment; }
    if (kind == 5) { return TH.type; }
    if (kind == 6) { return TH.func; }
    return TH.text;
}
