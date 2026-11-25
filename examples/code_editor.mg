use "gui.mg";
use "file.mg";
use "string.mg";

extern fn sys_fork() -> int;
extern fn sys_pipe(char* fds) -> int;
extern fn sys_dup2(int oldfd, int newfd) -> int;
extern fn sys_execve(string path, char** argv, char** envp) -> int;
extern fn sys_wait4(int pid, int* wstatus, int options, char* rusage) -> int;
extern fn sys_exit(int code) -> void;

const int TEXT_CAP = 262144;
const int MAX_LINES = 65536;
const int CLIP_CAP = 131072;
const int HEADER_H = 58;
const int STATUS_H = 26;
const int GUTTER_W = 56;
const int CHAR_W = 8;
const int LINE_H = 18;
const int AUTOSAVE_FRAMES = 120;
const int MSG_FRAMES = 120;

static char* TEXT;
static int TEXT_LEN;
static int CURSOR;
static int SEL_ANCHOR;
static int* LINES;
static int LINE_COUNT;
static int SCROLL_X;
static int SCROLL_Y;
static int DIRTY;
static int AUTOSAVE_ON;
static int FRAME;
static int LAST_EDIT_FRAME;
static int LAST_AUTOSAVE_TRY;
static char* FILE_PATH;
static char* AUTOSAVE_PATH;
static char* CLIP;
static int CLIP_LEN;
static char* MSG_BUF;
static int MSG_TTL;
static char* STATUS_LINE;
static char* ENV_BUF;
static char** ENV_PTRS;
static int ENV_COUNT;
static char* PICK_BUF;
static char* KEY_BUF;
static int ED_RUNNING;
static int MOUSE_SELECTING;
static int C_BG;
static int C_GUTTER;
static int C_GUTTER_TEXT;
static int C_BORDER;
static int C_TEXT;
static int C_MUTED;
static int C_ACCENT;
static int C_KEY;
static int C_TYPE;
static int C_FUNC;
static int C_STRING;
static int C_NUM;
static int C_COMMENT;
static int C_LINE;
static int C_SEL;
static int C_SEL_FG;
static int C_CARET;
static int C_HEADER_TOP;
static int C_HEADER_BOT;
static int C_BTN;
static int C_BTN_ON;
static int C_STATUS;
static int C_GREEN;
static int C_ORANGE;
static int C_MSG_BG;

fn ed_byte(char* p, int i) -> int {
    int v = cast<int>(*(p + i));
    if (v < 0) { v = v + 256; }
    return v;
}

fn ed_len(char* p) -> int {
    int n = 0;
    while (ed_byte(p, n) != 0) { n = n + 1; }
    return n;
}

fn ed_get_u32(char* p, int off) -> int {
    return ed_byte(p, off) + ed_byte(p, off + 1) * 256 + ed_byte(p, off + 2) * 65536 + ed_byte(p, off + 3) * 16777216;
}

fn ed_copy(char* dst, int cap, string src) -> void {
    if (cap <= 0) { return; }
    char* p = cast<char*>(src);
    int n = ed_len(p);
    if (n > cap - 1) { n = cap - 1; }
    int i = 0;
    while (i < n) { *(dst + i) = *(p + i); i = i + 1; }
    *(dst + n) = 0;
}

fn ed_append(char* dst, int cap, int di, string src) -> int {
    char* p = cast<char*>(src);
    int i = 0;
    while (ed_byte(p, i) != 0 && di < cap - 1) {
        *(dst + di) = *(p + i);
        di = di + 1;
        i = i + 1;
    }
    *(dst + di) = 0;
    return di;
}

fn ed_msg(string s) -> void {
    ed_copy(MSG_BUF, 192, s);
    MSG_TTL = MSG_FRAMES;
}

fn ed_init_colors() -> void {
    C_BG = gui_rgb(15, 18, 24);
    C_GUTTER = gui_rgb(21, 25, 34);
    C_GUTTER_TEXT = gui_rgb(90, 100, 120);
    C_BORDER = gui_rgb(38, 45, 60);
    C_TEXT = gui_rgb(220, 226, 240);
    C_MUTED = gui_rgb(135, 145, 165);
    C_ACCENT = gui_rgb(88, 166, 255);
    C_KEY = gui_rgb(255, 121, 198);
    C_TYPE = gui_rgb(121, 192, 255);
    C_FUNC = gui_rgb(210, 168, 255);
    C_STRING = gui_rgb(158, 206, 106);
    C_NUM = gui_rgb(247, 184, 104);
    C_COMMENT = gui_rgb(110, 125, 145);
    C_LINE = gui_rgb(23, 29, 40);
    C_SEL = gui_rgb(38, 79, 120);
    C_SEL_FG = gui_rgb(255, 255, 255);
    C_CARET = gui_rgb(240, 240, 240);
    C_HEADER_TOP = gui_rgb(20, 26, 36);
    C_HEADER_BOT = gui_rgb(15, 18, 24);
    C_BTN = gui_rgb(31, 38, 52);
    C_BTN_ON = gui_rgb(30, 70, 45);
    C_STATUS = gui_rgb(18, 22, 30);
    C_GREEN = gui_rgb(110, 220, 150);
    C_ORANGE = gui_rgb(247, 184, 104);
    C_MSG_BG = gui_rgb(30, 37, 50);
}

fn ed_rebuild_lines() -> void {
    LINE_COUNT = 0;
    LINES[0] = 0;
    LINE_COUNT = 1;
    int i = 0;
    while (i < TEXT_LEN) {
        if (ed_byte(TEXT, i) == 10 && LINE_COUNT < MAX_LINES) {
            LINES[LINE_COUNT] = i + 1;
            LINE_COUNT = LINE_COUNT + 1;
        }
        i = i + 1;
    }
}

fn ed_line_index(int offset) -> int {
    if (offset < 0) { offset = 0; }
    if (offset > TEXT_LEN) { offset = TEXT_LEN; }
    int lo = 0;
    int hi = LINE_COUNT - 1;
    while (lo <= hi) {
        int mid = (lo + hi) / 2;
        if (LINES[mid] <= offset) { lo = mid + 1; }
        else { hi = mid - 1; }
    }
    if (hi < 0) { hi = 0; }
    if (hi >= LINE_COUNT) { hi = LINE_COUNT - 1; }
    return hi;
}

fn ed_line_end(int li) -> int {
    if (li < 0) { li = 0; }
    if (li >= LINE_COUNT) { li = LINE_COUNT - 1; }
    int st = LINES[li];
    int en = TEXT_LEN;
    if (li + 1 < LINE_COUNT) { en = LINES[li + 1] - 1; }
    if (en > st && ed_byte(TEXT, en - 1) == 13) { en = en - 1; }
    return en;
}

fn ed_visual_col(int st, int pos) -> int {
    if (pos < st) { pos = st; }
    if (pos > TEXT_LEN) { pos = TEXT_LEN; }
    int vc = 0;
    int i = st;
    while (i < pos) {
        int c = ed_byte(TEXT, i);
        if (c == 9) { vc = vc + (4 - (vc - (vc / 4) * 4)); }
        else { vc = vc + 1; }
        i = i + 1;
    }
    return vc;
}

fn ed_offset_from_visual_col(int li, int target) -> int {
    if (target < 0) { target = 0; }
    int st = LINES[li];
    int en = ed_line_end(li);
    int vc = 0;
    int i = st;
    while (i < en) {
        int c = ed_byte(TEXT, i);
        int adv = 1;
        if (c == 9) { adv = 4 - (vc - (vc / 4) * 4); }
        if (vc + adv > target) { return i; }
        vc = vc + adv;
        i = i + 1;
    }
    return en;
}

fn ed_text_x() -> int {
    return GUTTER_W + 8;
}

fn ed_text_w() -> int {
    int w = dsk_screen_w() - GUTTER_W - 16;
    if (w < 40) { w = 40; }
    return w;
}

fn ed_rows() -> int {
    int h = dsk_screen_h() - HEADER_H - STATUS_H - 8;
    int r = h / LINE_H;
    if (r < 1) { r = 1; }
    return r;
}

fn ed_cols() -> int {
    int c = ed_text_w() / CHAR_W;
    if (c < 8) { c = 8; }
    return c;
}

fn ed_ensure_visible() -> void {
    int li = ed_line_index(CURSOR);
    int vc = ed_visual_col(LINES[li], CURSOR);
    int rows = ed_rows();
    int cols = ed_cols();
    if (li < SCROLL_Y) { SCROLL_Y = li; }
    if (li >= SCROLL_Y + rows) { SCROLL_Y = li - rows + 1; }
    if (vc < SCROLL_X) { SCROLL_X = vc; }
    if (vc >= SCROLL_X + cols - 2) { SCROLL_X = vc - cols + 3; }
    if (SCROLL_X < 0) { SCROLL_X = 0; }
    if (SCROLL_Y < 0) { SCROLL_Y = 0; }
    int maxy = LINE_COUNT - rows;
    if (maxy < 0) { maxy = 0; }
    if (SCROLL_Y > maxy) { SCROLL_Y = maxy; }
}

fn ed_mark_dirty() -> void {
    DIRTY = 1;
    LAST_EDIT_FRAME = FRAME;
}

fn ed_has_selection() -> int {
    if (SEL_ANCHOR != CURSOR) { return 1; }
    return 0;
}

fn ed_sel_start() -> int {
    if (SEL_ANCHOR < CURSOR) { return SEL_ANCHOR; }
    return CURSOR;
}

fn ed_sel_end() -> int {
    if (SEL_ANCHOR > CURSOR) { return SEL_ANCHOR; }
    return CURSOR;
}

fn ed_set_cursor_raw(int pos, int extend) -> void {
    if (pos < 0) { pos = 0; }
    if (pos > TEXT_LEN) { pos = TEXT_LEN; }
    if (extend == 0) { SEL_ANCHOR = pos; }
    CURSOR = pos;
    ed_ensure_visible();
}

fn ed_set_text(string s) -> void {
    char* p = cast<char*>(s);
    int n = ed_len(p);
    if (n > TEXT_CAP - 1) { n = TEXT_CAP - 1; }
    int i = 0;
    while (i < n) { *(TEXT + i) = *(p + i); i = i + 1; }
    TEXT_LEN = n;
    *(TEXT + n) = 0;
    CURSOR = 0;
    SEL_ANCHOR = 0;
    SCROLL_X = 0;
    SCROLL_Y = 0;
    DIRTY = 0;
    ed_rebuild_lines();
}

fn ed_strip_cr() -> void {
    int w = 0;
    int i = 0;
    while (i < TEXT_LEN) {
        if (ed_byte(TEXT, i) != 13) {
            *(TEXT + w) = *(TEXT + i);
            w = w + 1;
        }
        i = i + 1;
    }
    TEXT_LEN = w;
    *(TEXT + w) = 0;
}

fn ed_set_path(string p) -> void {
    ed_copy(FILE_PATH, 1024, p);
}

fn ed_cmdline_path() -> string {
    int fd = sys_open("/proc/self/cmdline", 0, 0);
    if (fd < 0) { return ""; }
    char* buf = alloc<char>(4096);
    int n = sys_read(fd, buf, 4095);
    sys_close(fd);
    if (n <= 0) { free(buf); return ""; }
    *(buf + n) = 0;
    int i = 0;
    while (i < n && ed_byte(buf, i) != 0) { i = i + 1; }
    i = i + 1;
    if (i >= n) { free(buf); return ""; }
    int st = i;
    while (i < n && ed_byte(buf, i) != 0) { i = i + 1; }
    int l = i - st;
    if (l <= 0) { free(buf); return ""; }
    char* out = alloc<char>(l + 1);
    int j = 0;
    while (j < l) { *(out + j) = *(buf + st + j); j = j + 1; }
    *(out + l) = 0;
    free(buf);
    return cast<string>(out);
}

fn ed_build_envp(int n) -> void {
    ENV_COUNT = 0;
    int i = 0;
    while (i < n && ENV_COUNT < 255) {
        if (ed_byte(ENV_BUF, i) != 0) {
            ENV_PTRS[ENV_COUNT] = ENV_BUF + i;
            ENV_COUNT = ENV_COUNT + 1;
        }
        while (i < n && ed_byte(ENV_BUF, i) != 0) { i = i + 1; }
        i = i + 1;
    }
    ENV_PTRS[ENV_COUNT] = null;
    if (ENV_COUNT == 0) {
        ENV_PTRS[0] = cast<char*>("DISPLAY=:0");
        ENV_PTRS[1] = cast<char*>("HOME=/tmp");
        ENV_PTRS[2] = null;
        ENV_COUNT = 2;
    }
}

fn ed_load_env() -> void {
    int fd = sys_open("/proc/self/environ", 0, 0);
    if (fd < 0) { ed_build_envp(0); return; }
    int n = sys_read(fd, ENV_BUF, 8191);
    sys_close(fd);
    if (n <= 0) { ed_build_envp(0); return; }
    ed_build_envp(n);
}

fn ed_pick_path(int save_mode) -> int {
    if (file_exists("/usr/bin/zenity") == false) {
        ed_msg("File picker unavailable: zenity is not installed.");
        return 0;
    }
    if (ENV_COUNT == 0) { ed_load_env(); }
    char* fds = alloc<char>(8);
    int i = 0;
    while (i < 8) { *(fds + i) = 0; i = i + 1; }
    if (sys_pipe(fds) != 0) {
        free(fds);
        ed_msg("Could not open the file picker.");
        return 0;
    }
    int rd = ed_get_u32(fds, 0);
    int wr = ed_get_u32(fds, 4);
    int pid = sys_fork();
    if (pid == 0) {
        sys_close(rd);
        sys_dup2(wr, 1);
        if (wr > 2) { sys_close(wr); }
        char** argv = alloc<char*>(10);
        argv[0] = cast<char*>("env");
        argv[1] = cast<char*>("GDK_BACKEND=x11");
        argv[2] = cast<char*>("zenity");
        argv[3] = cast<char*>("--file-selection");
        if (save_mode == 1) {
            argv[4] = cast<char*>("--save");
            argv[5] = cast<char*>("--confirm-overwrite");
            argv[6] = cast<char*>("--title=Save Magnetar file");
            argv[7] = cast<char*>("--file-filter=Code | *.mg *.txt *.md *.json *.c *.h *.py *.sh");
            argv[8] = null;
        } else {
            argv[4] = cast<char*>("--title=Open Magnetar file");
            argv[5] = cast<char*>("--file-filter=Code | *.mg *.txt *.md *.json *.c *.h *.py *.sh");
            argv[6] = null;
        }
        sys_execve("/usr/bin/env", argv, ENV_PTRS);
        sys_exit(127);
    }
    sys_close(wr);
    int n = sys_read(rd, PICK_BUF, 1023);
    sys_close(rd);
    int status = 0;
    sys_wait4(pid, &status, 0, null);
    free(fds);
    while (gui_key_available() > 0) { gui_key_poll(); }
    if (n <= 0) {
        ed_msg("File selection cancelled.");
        return 0;
    }
    *(PICK_BUF + n) = 0;
    string picked = cast<string>(PICK_BUF);
    string cleaned = str_trim(picked);
    ed_copy(PICK_BUF, 1024, cleaned);
    if (len(cast<string>(PICK_BUF)) == 0) {
        ed_msg("File selection cancelled.");
        return 0;
    }
    return 1;
}

fn ed_save_internal(string target, int announce) -> int {
    if (len(target) == 0) { return 0; }
    if (file_write_all(target, cast<string>(TEXT)) == false) {
        ed_msg("Could not save the file.");
        return 0;
    }
    DIRTY = 0;
    LAST_EDIT_FRAME = FRAME;
    if (announce == 1) { ed_msg("Saved."); }
    return 1;
}

fn ed_flush() -> void {
    if (DIRTY == 0) { return; }
    string target = cast<string>(FILE_PATH);
    if (len(target) == 0) { target = cast<string>(AUTOSAVE_PATH); }
    if (ed_save_internal(target, 0) == 1) {
        if (len(cast<string>(FILE_PATH)) == 0) { ed_msg("Autosaved to /tmp."); }
        else { ed_msg("Autosaved."); }
    }
}

fn ed_autosave() -> void {
    if (AUTOSAVE_ON == 0) { return; }
    if (DIRTY == 0) { return; }
    if (FRAME - LAST_AUTOSAVE_TRY < AUTOSAVE_FRAMES) { return; }
    LAST_AUTOSAVE_TRY = FRAME;
    ed_flush();
}

fn ed_open_file(string path) -> int {
    if (file_is_file(path) == false) {
        ed_msg("Not a regular file.");
        return 0;
    }
    int sz = file_size(path);
    if (sz > TEXT_CAP - 1) {
        ed_msg("File is too large for this editor.");
        return 0;
    }
    string data = file_read_all(path);
    ed_set_text(data);
    if (len(data) > 0) { free(cast<char*>(data)); }
    ed_strip_cr();
    ed_rebuild_lines();
    ed_set_path(path);
    CURSOR = 0;
    SEL_ANCHOR = 0;
    SCROLL_X = 0;
    SCROLL_Y = 0;
    DIRTY = 0;
    LAST_EDIT_FRAME = FRAME;
    ed_msg("Opened file.");
    return 1;
}

fn ed_new_action() -> void {
    ed_flush();
    TEXT_LEN = 0;
    *(TEXT) = 0;
    CURSOR = 0;
    SEL_ANCHOR = 0;
    SCROLL_X = 0;
    SCROLL_Y = 0;
    *(FILE_PATH) = 0;
    DIRTY = 0;
    MOUSE_SELECTING = 0;
    ed_rebuild_lines();
    ed_msg("New document.");
}

fn ed_open_action() -> void {
    ed_flush();
    if (ed_pick_path(0) == 0) { return; }
    ed_open_file(cast<string>(PICK_BUF));
}

fn ed_save_action() -> void {
    if (len(cast<string>(FILE_PATH)) == 0) {
        if (ed_pick_path(1) == 0) { return; }
        ed_set_path(cast<string>(PICK_BUF));
    }
    ed_save_internal(cast<string>(FILE_PATH), 1);
}

fn ed_save_as_action() -> void {
    if (ed_pick_path(1) == 0) { return; }
    ed_set_path(cast<string>(PICK_BUF));
    ed_save_internal(cast<string>(FILE_PATH), 1);
}

fn ed_quit() -> void {
    ed_flush();
    ED_RUNNING = 0;
}

fn ed_delete_range(int a, int b) -> void {
    if (a < 0) { a = 0; }
    if (b > TEXT_LEN) { b = TEXT_LEN; }
    if (a >= b) { return; }
    int n = b - a;
    int i = b;
    while (i <= TEXT_LEN) {
        *(TEXT + i - n) = *(TEXT + i);
        i = i + 1;
    }
    TEXT_LEN = TEXT_LEN - n;
    CURSOR = a;
    SEL_ANCHOR = a;
    ed_rebuild_lines();
    ed_mark_dirty();
    ed_ensure_visible();
}

fn ed_delete_selection() -> void {
    int a = ed_sel_start();
    int b = ed_sel_end();
    if (a == b) { return; }
    ed_delete_range(a, b);
}

fn ed_insert_text(string s) -> void {
    if (ed_has_selection() == 1) { ed_delete_selection(); }
    char* p = cast<char*>(s);
    int n = ed_len(p);
    int i = 0;
    while (i < n && TEXT_LEN < TEXT_CAP - 1) {
        int c = ed_byte(p, i);
        if (c != 13) {
            int j = TEXT_LEN;
            while (j >= CURSOR) {
                TEXT[j + 1] = TEXT[j];
                j = j - 1;
            }
            *(TEXT + CURSOR) = c;
            CURSOR = CURSOR + 1;
            TEXT_LEN = TEXT_LEN + 1;
        }
        i = i + 1;
    }
    ed_rebuild_lines();
    if (n > 0) { ed_mark_dirty(); }
    ed_ensure_visible();
}

fn ed_backspace() -> void {
    if (ed_has_selection() == 1) {
        ed_delete_selection();
        return;
    }
    if (CURSOR <= 0) { return; }
    ed_delete_range(CURSOR - 1, CURSOR);
}

fn ed_delete_forward() -> void {
    if (ed_has_selection() == 1) {
        ed_delete_selection();
        return;
    }
    if (CURSOR >= TEXT_LEN) { return; }
    ed_delete_range(CURSOR, CURSOR + 1);
}

fn ed_copy_sel() -> int {
    int a = ed_sel_start();
    int b = ed_sel_end();
    if (a == b) { ed_msg("Nothing selected."); return 0; }
    int n = b - a;
    if (n > CLIP_CAP - 1) { n = CLIP_CAP - 1; }
    int i = 0;
    while (i < n) {
        *(CLIP + i) = *(TEXT + a + i);
        i = i + 1;
    }
    *(CLIP + n) = 0;
    CLIP_LEN = n;
    ed_msg("Copied.");
    return 1;
}

fn ed_cut_sel() -> void {
    if (ed_copy_sel() == 1) { ed_delete_selection(); }
}

fn ed_paste_clip() -> void {
    if (CLIP_LEN <= 0) { ed_msg("Clipboard is empty."); return; }
    ed_insert_text(cast<string>(CLIP));
}

fn ed_move_vertical(int delta, int shift) -> void {
    int li = ed_line_index(CURSOR);
    int vc = ed_visual_col(LINES[li], CURSOR);
    int target = li + delta;
    if (target < 0) { target = 0; }
    if (target >= LINE_COUNT) { target = LINE_COUNT - 1; }
    int pos = ed_offset_from_visual_col(target, vc);
    ed_set_cursor_raw(pos, shift);
}

fn ed_move_left(int shift) -> void {
    if (shift == 0 && ed_has_selection() == 1) {
        ed_set_cursor_raw(ed_sel_start(), 0);
        return;
    }
    ed_set_cursor_raw(CURSOR - 1, shift);
}

fn ed_move_right(int shift) -> void {
    if (shift == 0 && ed_has_selection() == 1) {
        ed_set_cursor_raw(ed_sel_end(), 0);
        return;
    }
    ed_set_cursor_raw(CURSOR + 1, shift);
}

fn ed_move_home(int shift) -> void {
    int li = ed_line_index(CURSOR);
    ed_set_cursor_raw(LINES[li], shift);
}

fn ed_move_end(int shift) -> void {
    int li = ed_line_index(CURSOR);
    ed_set_cursor_raw(ed_line_end(li), shift);
}

fn ed_select_all() -> void {
    SEL_ANCHOR = 0;
    CURSOR = TEXT_LEN;
    ed_ensure_visible();
}

fn ed_lower(int k) -> int {
    if (k >= 65 && k <= 90) { return k + 32; }
    return k;
}

fn ed_handle_ctrl(int k, int shift) -> void {
    int ck = ed_lower(k);
    if (ck == 115) {
        if (shift == 1) { ed_save_as_action(); }
        else { ed_save_action(); }
        return;
    }
    if (ck == 111) { ed_open_action(); return; }
    if (ck == 110) { ed_new_action(); return; }
    if (ck == 97) { ed_select_all(); return; }
    if (ck == 99) { ed_copy_sel(); return; }
    if (ck == 120) { ed_cut_sel(); return; }
    if (ck == 118) { ed_paste_clip(); return; }
    if (ck == 113) { ed_quit(); return; }
    if (k == 132) {
        SEL_ANCHOR = 0;
        CURSOR = 0;
        ed_ensure_visible();
        return;
    }
    if (k == 133) {
        CURSOR = TEXT_LEN;
        if (shift == 0) { SEL_ANCHOR = TEXT_LEN; }
        ed_ensure_visible();
        return;
    }
}

fn ed_handle_normal(int k, int shift) -> void {
    if (k == 8) { ed_backspace(); return; }
    if (k == 127) { ed_delete_forward(); return; }
    if (k == 10) { ed_insert_text("\n"); return; }
    if (k == 9) { ed_insert_text("    "); return; }
    if (k == 128) { ed_move_vertical(0 - 1, shift); return; }
    if (k == 129) { ed_move_vertical(1, shift); return; }
    if (k == 130) { ed_move_left(shift); return; }
    if (k == 131) { ed_move_right(shift); return; }
    if (k == 132) { ed_move_home(shift); return; }
    if (k == 133) { ed_move_end(shift); return; }
    if (k == 134) { ed_move_vertical(0 - (ed_rows() - 1), shift); return; }
    if (k == 135) { ed_move_vertical(ed_rows() - 1, shift); return; }
    if (k >= 32 && k <= 126) {
        *(KEY_BUF) = k;
        *(KEY_BUF + 1) = 0;
        ed_insert_text(cast<string>(KEY_BUF));
    }
}

fn ed_handle_keys() -> void {
    int k = gui_key_poll();
    while (k >= 0) {
        int ctrl = gui_key_ctrl();
        int shift = gui_key_shift();
        if (ctrl == 1) { ed_handle_ctrl(k, shift); }
        else { ed_handle_normal(k, shift); }
        k = gui_key_poll();
    }
}

fn ed_text(int x, int y, string s, int color, int scale) -> void {
    int old = gui_get_scale();
    if (old != scale) { gui_set_scale(scale); }
    gui_draw_text_fg(x, y, s, color, 255);
    if (old != scale) { gui_set_scale(old); }
}

fn ed_text_clip(int x, int y, string s, int color, int maxw, int scale) -> void {
    int old = gui_get_scale();
    if (old != scale) { gui_set_scale(scale); }
    dsk_text_clip_fg(x, y, s, color, maxw);
    if (old != scale) { gui_set_scale(old); }
}

fn ed_text_center(int x, int y, int w, string s, int color) -> void {
    int old = gui_get_scale();
    if (old != 1) { gui_set_scale(1); }
    dsk_text_center_fg(x, y, w, s, color);
    if (old != 1) { gui_set_scale(old); }
}

fn ed_draw_button(int x, int y, int w, int h, string label, int active) -> void {
    int bg = C_BTN;
    int fg = C_TEXT;
    if (active == 1) {
        bg = C_BTN_ON;
        fg = C_GREEN;
    }
    gui_fill_rounded_rect(x, y, w, h, 5, bg);
    gui_fill_rect(x + 3, y, w - 6, 1, C_BORDER);
    gui_fill_rect(x + 3, y + h - 1, w - 6, 1, C_BORDER);
    ed_text_center(x, y + 9, w, label, fg);
}

fn ed_btn_start(int w) -> int {
    return w - 282;
}

fn ed_btn_x(int w, int i) -> int {
    return ed_btn_start(w) + i * 68;
}

fn ed_draw_header(int w) -> void {
    gui_fill_gradient_v(0, 0, w, HEADER_H, C_HEADER_TOP, C_HEADER_BOT);
    gui_fill_rect(0, HEADER_H - 1, w, 1, C_BORDER);
    gui_fill_rounded_rect(14, 14, 4, 30, 2, C_ACCENT);
    ed_text(24, 9, "FALCON CODE", C_TEXT, 2);
    string path = cast<string>(FILE_PATH);
    if (len(path) == 0) { path = "UNTITLED"; }
    string state = "UNSAVED";
    int state_col = C_ORANGE;
    if (DIRTY == 0) {
        state = "SAVED";
        state_col = C_GREEN;
    }
    int sw = gui_text_width(state, 1);
    int maxw = ed_btn_start(w) - 24 - sw - 16;
    if (maxw < 60) { maxw = 60; }
    ed_text_clip(24, 34, path, C_MUTED, maxw, 1);
    ed_text(ed_btn_start(w) - 12 - sw, 34, state, state_col, 1);
    int bx = ed_btn_start(w);
    ed_draw_button(bx, 12, 62, 26, "NEW", 0);
    ed_draw_button(bx + 68, 12, 62, 26, "OPEN", 0);
    ed_draw_button(bx + 136, 12, 62, 26, "SAVE", 0);
    ed_draw_button(bx + 204, 12, 62, 26, "AUTO", AUTOSAVE_ON);
}

fn ed_is_word_start(int c) -> int {
    if (c >= 65 && c <= 90) { return 1; }
    if (c >= 97 && c <= 122) { return 1; }
    if (c == 95) { return 1; }
    return 0;
}

fn ed_is_word_char(int c) -> int {
    if (ed_is_word_start(c) == 1) { return 1; }
    if (c >= 48 && c <= 57) { return 1; }
    return 0;
}

fn ed_word_eq(int st, int en, string kw) -> int {
    int kl = len(kw);
    if (en - st != kl) { return 0; }
    char* p = cast<char*>(kw);
    int i = 0;
    while (i < kl) {
        if (ed_byte(TEXT, st + i) != ed_byte(p, i)) { return 0; }
        i = i + 1;
    }
    return 1;
}

fn ed_word_is_type(int st, int en) -> int {
    if (ed_word_eq(st, en, "int") == 1) { return 1; }
    if (ed_word_eq(st, en, "float") == 1) { return 1; }
    if (ed_word_eq(st, en, "half") == 1) { return 1; }
    if (ed_word_eq(st, en, "bool") == 1) { return 1; }
    if (ed_word_eq(st, en, "char") == 1) { return 1; }
    if (ed_word_eq(st, en, "string") == 1) { return 1; }
    if (ed_word_eq(st, en, "void") == 1) { return 1; }
    if (ed_word_eq(st, en, "auto") == 1) { return 1; }
    if (ed_word_eq(st, en, "any") == 1) { return 1; }
    if (ed_word_eq(st, en, "byte") == 1) { return 1; }
    if (ed_word_eq(st, en, "word") == 1) { return 1; }
    if (ed_word_eq(st, en, "dword") == 1) { return 1; }
    if (ed_word_eq(st, en, "qword") == 1) { return 1; }
    if (ed_word_eq(st, en, "fixed") == 1) { return 1; }
    if (ed_word_eq(st, en, "slice") == 1) { return 1; }
    if (ed_word_eq(st, en, "array") == 1) { return 1; }
    if (ed_word_eq(st, en, "ref") == 1) { return 1; }
    if (ed_word_eq(st, en, "own") == 1) { return 1; }
    if (ed_word_eq(st, en, "raw") == 1) { return 1; }
    if (ed_word_eq(st, en, "dyn") == 1) { return 1; }
    if (ed_word_eq(st, en, "range") == 1) { return 1; }
    if (ed_word_eq(st, en, "tuple") == 1) { return 1; }
    return 0;
}

fn ed_word_is_keyword(int st, int en) -> int {
    if (ed_word_eq(st, en, "fn") == 1) { return 1; }
    if (ed_word_eq(st, en, "entry") == 1) { return 1; }
    if (ed_word_eq(st, en, "let") == 1) { return 1; }
    if (ed_word_eq(st, en, "struct") == 1) { return 1; }
    if (ed_word_eq(st, en, "class") == 1) { return 1; }
    if (ed_word_eq(st, en, "enum") == 1) { return 1; }
    if (ed_word_eq(st, en, "union") == 1) { return 1; }
    if (ed_word_eq(st, en, "if") == 1) { return 1; }
    if (ed_word_eq(st, en, "else") == 1) { return 1; }
    if (ed_word_eq(st, en, "switch") == 1) { return 1; }
    if (ed_word_eq(st, en, "case") == 1) { return 1; }
    if (ed_word_eq(st, en, "default") == 1) { return 1; }
    if (ed_word_eq(st, en, "for") == 1) { return 1; }
    if (ed_word_eq(st, en, "while") == 1) { return 1; }
    if (ed_word_eq(st, en, "do") == 1) { return 1; }
    if (ed_word_eq(st, en, "break") == 1) { return 1; }
    if (ed_word_eq(st, en, "continue") == 1) { return 1; }
    if (ed_word_eq(st, en, "return") == 1) { return 1; }
    if (ed_word_eq(st, en, "goto") == 1) { return 1; }
    if (ed_word_eq(st, en, "defer") == 1) { return 1; }
    if (ed_word_eq(st, en, "match") == 1) { return 1; }
    if (ed_word_eq(st, en, "new") == 1) { return 1; }
    if (ed_word_eq(st, en, "delete") == 1) { return 1; }
    if (ed_word_eq(st, en, "use") == 1) { return 1; }
    if (ed_word_eq(st, en, "export") == 1) { return 1; }
    if (ed_word_eq(st, en, "as") == 1) { return 1; }
    if (ed_word_eq(st, en, "const") == 1) { return 1; }
    if (ed_word_eq(st, en, "static") == 1) { return 1; }
    if (ed_word_eq(st, en, "extern") == 1) { return 1; }
    if (ed_word_eq(st, en, "alloc") == 1) { return 1; }
    if (ed_word_eq(st, en, "free") == 1) { return 1; }
    if (ed_word_eq(st, en, "sizeof") == 1) { return 1; }
    if (ed_word_eq(st, en, "cast") == 1) { return 1; }
    if (ed_word_eq(st, en, "typeof") == 1) { return 1; }
    if (ed_word_eq(st, en, "nan") == 1) { return 1; }
    if (ed_word_eq(st, en, "inf") == 1) { return 1; }
    if (ed_word_eq(st, en, "inline") == 1) { return 1; }
    if (ed_word_eq(st, en, "volatile") == 1) { return 1; }
    if (ed_word_eq(st, en, "register") == 1) { return 1; }
    if (ed_word_eq(st, en, "unsafe") == 1) { return 1; }
    if (ed_word_eq(st, en, "copy") == 1) { return 1; }
    if (ed_word_eq(st, en, "clone") == 1) { return 1; }
    if (ed_word_eq(st, en, "borrow") == 1) { return 1; }
    if (ed_word_eq(st, en, "move") == 1) { return 1; }
    if (ed_word_eq(st, en, "true") == 1) { return 1; }
    if (ed_word_eq(st, en, "false") == 1) { return 1; }
    if (ed_word_eq(st, en, "null") == 1) { return 1; }
    if (ed_word_eq(st, en, "assert") == 1) { return 1; }
    if (ed_word_eq(st, en, "throw") == 1) { return 1; }
    if (ed_word_eq(st, en, "try") == 1) { return 1; }
    if (ed_word_eq(st, en, "catch") == 1) { return 1; }
    if (ed_word_eq(st, en, "finally") == 1) { return 1; }
    if (ed_word_eq(st, en, "this") == 1) { return 1; }
    if (ed_word_eq(st, en, "self") == 1) { return 1; }
    if (ed_word_eq(st, en, "super") == 1) { return 1; }
    if (ed_word_eq(st, en, "base") == 1) { return 1; }
    if (ed_word_eq(st, en, "extends") == 1) { return 1; }
    if (ed_word_eq(st, en, "impl") == 1) { return 1; }
    if (ed_word_eq(st, en, "print") == 1) { return 1; }
    if (ed_word_eq(st, en, "async") == 1) { return 1; }
    if (ed_word_eq(st, en, "await") == 1) { return 1; }
    if (ed_word_eq(st, en, "spawn") == 1) { return 1; }
    if (ed_word_eq(st, en, "parallel") == 1) { return 1; }
    if (ed_word_eq(st, en, "asm") == 1) { return 1; }
    return 0;
}

fn ed_draw_span(int st, int en, int color, int y, int* vcp, int scroll, int sel_a, int sel_b, int line_bg) -> void {
    int tx = ed_text_x();
    int cols = ed_cols();
    int vc = *vcp;
    int i = st;
    while (i < en) {
        int c = ed_byte(TEXT, i);
        int adv = 1;
        int ch = c;
        if (c == 9) {
            adv = 4 - (vc - (vc / 4) * 4);
            ch = 32;
        } else if (c < 32 || c > 126) {
            ch = 32;
        }
        int a = 0;
        while (a < adv) {
            int col = vc + a;
            if (col >= scroll && col < scroll + cols) {
                int x = tx + (col - scroll) * CHAR_W;
                int bg = line_bg;
                int fg = color;
                if (i >= sel_a && i < sel_b) {
                    bg = C_SEL;
                    fg = C_SEL_FG;
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

fn ed_draw_code(int st, int en, int y, int scroll, int sel_a, int sel_b, int line_bg) -> void {
    int vc = 0;
    int i = st;
    while (i < en) {
        int c = ed_byte(TEXT, i);
        int nx = -1;
        if (i + 1 < en) { nx = ed_byte(TEXT, i + 1); }
        if (c == 47 && nx == 47) {
            ed_draw_span(i, en, C_COMMENT, y, &vc, scroll, sel_a, sel_b, line_bg);
            break;
        }
        if (c == 47 && nx == 42) {
            int j = i + 2;
            while (j + 1 < en) {
                if (ed_byte(TEXT, j) == 42 && ed_byte(TEXT, j + 1) == 47) {
                    j = j + 2;
                    break;
                }
                j = j + 1;
            }
            if (j > en) { j = en; }
            ed_draw_span(i, j, C_COMMENT, y, &vc, scroll, sel_a, sel_b, line_bg);
            i = j;
            continue;
        }
        if (c == 34 || c == 39) {
            int quote = c;
            int j = i + 1;
            while (j < en) {
                int cc = ed_byte(TEXT, j);
                if (cc == 92) { j = j + 2; }
                else if (cc == quote) { j = j + 1; break; }
                else { j = j + 1; }
            }
            if (j > en) { j = en; }
            ed_draw_span(i, j, C_STRING, y, &vc, scroll, sel_a, sel_b, line_bg);
            i = j;
            continue;
        }
        if (ed_is_word_start(c) == 1) {
            int j = i + 1;
            while (j < en && ed_is_word_char(ed_byte(TEXT, j)) == 1) { j = j + 1; }
            int col = C_TEXT;
            if (ed_word_is_type(i, j) == 1) { col = C_TYPE; }
            else if (ed_word_is_keyword(i, j) == 1) { col = C_KEY; }
            else {
                int k = j;
                while (k < en && ed_byte(TEXT, k) == 32) { k = k + 1; }
                if (k < en && ed_byte(TEXT, k) == 40) { col = C_FUNC; }
            }
            ed_draw_span(i, j, col, y, &vc, scroll, sel_a, sel_b, line_bg);
            i = j;
            continue;
        }
        if (c >= 48 && c <= 57) {
            int j = i + 1;
            while (j < en) {
                int cc = ed_byte(TEXT, j);
                if ((cc >= 48 && cc <= 57) || (cc >= 97 && cc <= 102) || (cc >= 65 && cc <= 70) || cc == 120 || cc == 88 || cc == 46 || cc == 95) { j = j + 1; }
                else { break; }
            }
            ed_draw_span(i, j, C_NUM, y, &vc, scroll, sel_a, sel_b, line_bg);
            i = j;
            continue;
        }
        ed_draw_span(i, i + 1, C_TEXT, y, &vc, scroll, sel_a, sel_b, line_bg);
        i = i + 1;
    }
}

fn ed_draw_line(int li, int y, int w) -> void {
    int ls = LINES[li];
    int le = ed_line_end(li);
    int cur_line = ed_line_index(CURSOR);
    int is_cur = 0;
    if (li == cur_line) { is_cur = 1; }
    int line_bg = C_BG;
    if (is_cur == 1) {
        line_bg = C_LINE;
        gui_fill_rect(GUTTER_W + 1, y - 1, w - GUTTER_W - 1, LINE_H, line_bg);
        gui_fill_rect(0, y - 1, 2, LINE_H, C_ACCENT);
    }
    string ns = dsk_itoa(li + 1);
    int nw = gui_text_width(ns, 1);
    int ncolor = C_GUTTER_TEXT;
    if (is_cur == 1) { ncolor = C_ACCENT; }
    dsk_text_clip(GUTTER_W - 8 - nw, y, ns, ncolor, C_GUTTER, GUTTER_W - 8);
    ed_draw_code(ls, le, y, SCROLL_X, ed_sel_start(), ed_sel_end(), line_bg);
    if (is_cur == 1) {
        int caret_vc = ed_visual_col(ls, CURSOR);
        if (caret_vc >= SCROLL_X && caret_vc < SCROLL_X + ed_cols()) {
            if ((FRAME / 30) - ((FRAME / 30) / 2) * 2 == 0) {
                int cx = ed_text_x() + (caret_vc - SCROLL_X) * CHAR_W;
                gui_fill_rect(cx, y, 2, LINE_H - 2, C_CARET);
            }
        }
    }
}

fn ed_draw_editor(int w, int h) -> void {
    int ey = HEADER_H;
    int eh = h - HEADER_H - STATUS_H;
    gui_fill_rect(0, ey, w, eh, C_BG);
    gui_fill_rect(0, ey, GUTTER_W, eh, C_GUTTER);
    gui_fill_rect(GUTTER_W, ey, 1, eh, C_BORDER);
    int rows = ed_rows();
    if (SCROLL_Y < 0) { SCROLL_Y = 0; }
    int maxy = LINE_COUNT - rows;
    if (maxy < 0) { maxy = 0; }
    if (SCROLL_Y > maxy) { SCROLL_Y = maxy; }
    int y = ey + 3;
    int li = SCROLL_Y;
    int count = 0;
    while (li < LINE_COUNT && count < rows) {
        ed_draw_line(li, y, w);
        li = li + 1;
        y = y + LINE_H;
        count = count + 1;
    }
}

fn ed_draw_status(int w, int h) -> void {
    int y = h - STATUS_H;
    gui_fill_rect(0, y, w, STATUS_H, C_STATUS);
    gui_fill_rect(0, y, w, 1, C_BORDER);
    int li = ed_line_index(CURSOR);
    int col = ed_visual_col(LINES[li], CURSOR) + 1;
    int di = 0;
    di = ed_append(STATUS_LINE, 256, di, "Ln ");
    di = ed_append(STATUS_LINE, 256, di, dsk_itoa(li + 1));
    di = ed_append(STATUS_LINE, 256, di, "   Col ");
    di = ed_append(STATUS_LINE, 256, di, dsk_itoa(col));
    di = ed_append(STATUS_LINE, 256, di, "   ");
    di = ed_append(STATUS_LINE, 256, di, dsk_itoa(LINE_COUNT));
    di = ed_append(STATUS_LINE, 256, di, " lines   ");
    di = ed_append(STATUS_LINE, 256, di, dsk_itoa(TEXT_LEN));
    di = ed_append(STATUS_LINE, 256, di, " chars");
    int maxw = w - 300;
    if (maxw < 80) { maxw = 80; }
    ed_text_clip(12, y + 9, cast<string>(STATUS_LINE), C_MUTED, maxw, 1);
    string au = "AUTOSAVE OFF";
    int au_col = C_MUTED;
    if (AUTOSAVE_ON == 1) {
        au = "AUTOSAVE ON";
        au_col = C_GREEN;
    }
    int aw = gui_text_width(au, 1);
    ed_text(w - aw - 14, y + 9, au, au_col, 1);
}

fn ed_draw_msg(int w, int h) -> void {
    string s = cast<string>(MSG_BUF);
    int tw = gui_text_width(s, 1);
    int bw = tw + 28;
    if (bw > w - 40) { bw = w - 40; }
    int x = (w - bw) / 2;
    int y = h - STATUS_H - 40;
    gui_fill_rounded_rect(x, y, bw, 28, 7, C_MSG_BG);
    gui_fill_rect(x + 2, y, bw - 4, 1, C_ACCENT);
    ed_text_center(x + 10, y + 10, bw - 20, s, C_TEXT);
}

fn ed_draw() -> void {
    int w = dsk_screen_w();
    int h = dsk_screen_h();
    gui_clear(C_BG);
    ed_draw_header(w);
    ed_draw_editor(w, h);
    ed_draw_status(w, h);
    if (MSG_TTL > 0) {
        ed_draw_msg(w, h);
        MSG_TTL = MSG_TTL - 1;
    }
    if (gui_is_x11() == 0) { dsk_draw_cursor(gui_mouse_x(), gui_mouse_y()); }
}

fn ed_set_cursor_from_mouse(int mx, int my, int extend) -> void {
    int li = SCROLL_Y + (my - HEADER_H) / LINE_H;
    if (li < 0) { li = 0; }
    if (li >= LINE_COUNT) { li = LINE_COUNT - 1; }
    int col = (mx - ed_text_x()) / CHAR_W + SCROLL_X;
    if (mx < ed_text_x()) { col = 0; }
    if (col < 0) { col = 0; }
    int pos = ed_offset_from_visual_col(li, col);
    ed_set_cursor_raw(pos, extend);
}

fn ed_handle_header_click(int mx, int my, int w) -> int {
    if (my < 10 || my > 42) { return 0; }
    int bx = ed_btn_start(w);
    if (mx >= bx && mx < bx + 62) { ed_new_action(); return 1; }
    if (mx >= bx + 68 && mx < bx + 130) { ed_open_action(); return 1; }
    if (mx >= bx + 136 && mx < bx + 198) { ed_save_action(); return 1; }
    if (mx >= bx + 204 && mx < bx + 266) {
        AUTOSAVE_ON = 1 - AUTOSAVE_ON;
        if (AUTOSAVE_ON == 1) { ed_msg("Autosave enabled."); }
        else { ed_msg("Autosave disabled."); }
        return 1;
    }
    return 0;
}

fn ed_handle_mouse(int mx, int my) -> void {
    int w = dsk_screen_w();
    int h = dsk_screen_h();
    int wheel = gui_mouse_wheel();
    if (wheel != 0 && my >= HEADER_H && my < h - STATUS_H) {
        SCROLL_Y = SCROLL_Y - wheel * 3;
        int maxy = LINE_COUNT - ed_rows();
        if (maxy < 0) { maxy = 0; }
        if (SCROLL_Y < 0) { SCROLL_Y = 0; }
        if (SCROLL_Y > maxy) { SCROLL_Y = maxy; }
    }
    if (gui_mouse_clicked() == 1) {
        if (my < HEADER_H) {
            ed_handle_header_click(mx, my, w);
            return;
        }
        if (my < h - STATUS_H) {
            ed_set_cursor_from_mouse(mx, my, gui_shift_down());
            MOUSE_SELECTING = 1;
            return;
        }
    }
    if (MOUSE_SELECTING == 1) {
        if (gui_mouse_left() == 1) {
            int ey = HEADER_H;
            int eh = h - HEADER_H - STATUS_H;
            int yy = my;
            if (yy < ey) { yy = ey; }
            if (yy >= ey + eh) { yy = ey + eh - 1; }
            ed_set_cursor_from_mouse(mx, yy, 1);
        } else {
            MOUSE_SELECTING = 0;
        }
    }
}

fn ed_tick() -> void {
    FRAME = FRAME + 1;
    gui_read_mouse();
    ed_handle_mouse(gui_mouse_x(), gui_mouse_y());
    ed_handle_keys();
    ed_autosave();
    ed_draw();
    gui_present();
    sleep_ms(16);
}

fn ed_init() -> int {
    TEXT = alloc<char>(TEXT_CAP);
    *(TEXT) = 0;
    TEXT_LEN = 0;
    CURSOR = 0;
    SEL_ANCHOR = 0;
    LINES = alloc<int>(MAX_LINES);
    LINE_COUNT = 1;
    LINES[0] = 0;
    FILE_PATH = alloc<char>(1024);
    *(FILE_PATH) = 0;
    AUTOSAVE_PATH = alloc<char>(1024);
    ed_copy(AUTOSAVE_PATH, 1024, "/tmp/falcon_editor_autosave.mg");
    CLIP = alloc<char>(CLIP_CAP);
    *(CLIP) = 0;
    CLIP_LEN = 0;
    MSG_BUF = alloc<char>(192);
    *(MSG_BUF) = 0;
    STATUS_LINE = alloc<char>(256);
    *(STATUS_LINE) = 0;
    ENV_BUF = alloc<char>(8192);
    *(ENV_BUF) = 0;
    ENV_PTRS = alloc<char*>(256);
    ENV_PTRS[0] = null;
    ENV_COUNT = 0;
    PICK_BUF = alloc<char>(1024);
    *(PICK_BUF) = 0;
    KEY_BUF = alloc<char>(8);
    *(KEY_BUF) = 0;
    SCROLL_X = 0;
    SCROLL_Y = 0;
    DIRTY = 0;
    AUTOSAVE_ON = 1;
    FRAME = 0;
    LAST_EDIT_FRAME = 0;
    LAST_AUTOSAVE_TRY = 0;
    MSG_TTL = 0;
    ED_RUNNING = 1;
    MOUSE_SELECTING = 0;
    ed_init_colors();
    ed_load_env();
    string p = ed_cmdline_path();
    if (len(p) > 0) {
        ed_set_path(p);
        if (file_is_file(p) == true) { ed_open_file(p); }
        else {
            ed_set_text("");
            ed_msg("New file. Autosave is on.");
        }
        free(cast<char*>(p));
    } else {
        ed_set_text("// Falcon Code Editor\n// Lightweight in-memory editor with autosave.\n// Ctrl+S save  Ctrl+O open  Ctrl+Shift+S save as\n\nfn main() -> int {\n    let message = \"Hello, Magnetar!\";\n    print(message);\n    return 0;\n}\n");
        ed_msg("Sample loaded. Ctrl+S saves. Autosave is on.");
    }
    return 0;
}

fn main() -> int {
    int rc = dsk_init_window(1100, 720, "Falcon Code Editor");
    if (rc != 0) {
        print_str("Failed to open the editor window.\n");
        return 1;
    }
    gui_set_scale(1);
    ed_init();
    while (ED_RUNNING == 1 && gui_close_requested() == 0) { ed_tick(); }
    ed_flush();
    dsk_shutdown();
    return 0;
}
