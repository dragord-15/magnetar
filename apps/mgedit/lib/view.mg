const int VIEW_HEADER_H = 58;
const int VIEW_STATUS_H = 26;
const int VIEW_LINE_H = 18;
const int VIEW_CHAR_W = 8;
const int VIEW_GUTTER_W = 56;
const int VIEW_TREE_W = 190;
const int VIEW_PAD = 8;
const int VIEW_LINT_H = 132;

static int VIEW_W;
static int VIEW_H;
static int VIEW_SCROLL_X;
static int VIEW_SCROLL_Y;
static int VIEW_ROWS;
static int VIEW_COLS;
static int VIEW_TEXT_X;
static int VIEW_TEXT_W;
static int VIEW_TEXT_Y;
static int VIEW_EDITOR_H;
static int VIEW_TREE_ON;
static int VIEW_LINT_ON;

fn view_init() -> void {
    VIEW_SCROLL_X = 0;
    VIEW_SCROLL_Y = 0;
    VIEW_TREE_ON = 0;
    VIEW_LINT_ON = 0;
    view_update_layout();
}

fn view_update_layout() -> void {
    VIEW_W = dsk_screen_w();
    VIEW_H = dsk_screen_h();
    VIEW_TEXT_Y = VIEW_HEADER_H + 3;
    VIEW_EDITOR_H = VIEW_H - VIEW_HEADER_H - VIEW_STATUS_H;
    int left = VIEW_GUTTER_W + VIEW_PAD;
    if (VIEW_TREE_ON == 1) { left = left + VIEW_TREE_W; }
    VIEW_TEXT_X = left;
    VIEW_TEXT_W = VIEW_W - left - 12;
    if (VIEW_TEXT_W < 80) { VIEW_TEXT_W = 80; }
    int bottom = VIEW_H - VIEW_STATUS_H - 8;
    if (VIEW_LINT_ON == 1) { bottom = bottom - VIEW_LINT_H; }
    int h = bottom - VIEW_HEADER_H;
    VIEW_ROWS = h / VIEW_LINE_H;
    if (VIEW_ROWS < 1) { VIEW_ROWS = 1; }
    VIEW_COLS = VIEW_TEXT_W / VIEW_CHAR_W;
    if (VIEW_COLS < 8) { VIEW_COLS = 8; }
}

fn view_rows() -> int {
    view_update_layout();
    return VIEW_ROWS;
}

fn view_cols() -> int {
    view_update_layout();
    return VIEW_COLS;
}

fn view_ensure_cursor_visible() -> void {
    view_update_layout();
    int li = doc_line_index(doc_cursor());
    int vc = doc_visual_col(doc_line_start(li), doc_cursor());
    if (li < VIEW_SCROLL_Y) { VIEW_SCROLL_Y = li; }
    if (li >= VIEW_SCROLL_Y + VIEW_ROWS) { VIEW_SCROLL_Y = li - VIEW_ROWS + 1; }
    if (vc < VIEW_SCROLL_X) { VIEW_SCROLL_X = vc; }
    if (vc >= VIEW_SCROLL_X + VIEW_COLS - 2) { VIEW_SCROLL_X = vc - VIEW_COLS + 3; }
    view_clamp_scroll();
}

fn view_clamp_scroll() -> void {
    view_update_layout();
    if (VIEW_SCROLL_X < 0) { VIEW_SCROLL_X = 0; }
    if (VIEW_SCROLL_Y < 0) { VIEW_SCROLL_Y = 0; }
    int maxy = doc_line_count() - VIEW_ROWS;
    if (maxy < 0) { maxy = 0; }
    if (VIEW_SCROLL_Y > maxy) { VIEW_SCROLL_Y = maxy; }
}

fn view_reset_scroll() -> void {
    VIEW_SCROLL_X = 0;
    VIEW_SCROLL_Y = 0;
}

fn view_scroll(int dx, int dy) -> void {
    VIEW_SCROLL_X = VIEW_SCROLL_X + dx;
    VIEW_SCROLL_Y = VIEW_SCROLL_Y + dy;
    view_clamp_scroll();
}

fn view_toggle_tree() -> void {
    VIEW_TREE_ON = 1 - VIEW_TREE_ON;
    view_update_layout();
    view_ensure_cursor_visible();
}

fn view_toggle_lint() -> void {
    VIEW_LINT_ON = 1 - VIEW_LINT_ON;
    view_update_layout();
    view_ensure_cursor_visible();
}

fn view_tree_on() -> int {
    return VIEW_TREE_ON;
}
