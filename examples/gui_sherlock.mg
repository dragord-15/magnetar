use "gui.mg";
use "http.mg";
use "url.mg";
use "lib/security/osint.mg";
use "lib/image_intel.mg";

extern fn sleep_ms(int ms) -> void;
extern fn get_timestamp() -> int;
extern fn sys_open(string path, int flags, int mode) -> int;
extern fn sys_close(int fd) -> int;
extern fn sys_read(int fd, char* buf, int count) -> int;
extern fn sys_write(int fd, char* buf, int count) -> int;
extern fn sys_fork() -> int;
extern fn sys_pipe(char* fds) -> int;
extern fn sys_dup2(int oldfd, int newfd) -> int;
extern fn sys_unlink(string path) -> int;
extern fn sys_execve(string path, char** argv, char** envp) -> int;
extern fn sys_wait4(int pid, int* wstatus, int options, char* rusage) -> int;
extern fn sys_exit(int code) -> void;

static const int SITE_COUNT = 16;
static const int ROW_H = 31;
static const int ROW_Y = 214;

static const int L_X = 24;
static const int L_Y = 104;
static const int L_W = 390;
static const int L_H = 672;
static const int R_X = 430;
static const int R_Y = 104;
static const int R_W = 826;
static const int R_H = 672;

static const int USER_X = 46;
static const int USER_Y = 180;
static const int USER_W = 346;
static const int USER_H = 42;
static const int MODE_Y = 148;
static const int MODE_H = 24;
static const int MODE_W = 110;
static const int MODE_GAP = 8;
static const int SCAN_X = 46;
static const int SCAN_Y = 236;
static const int SCAN_W = 160;
static const int SCAN_H = 38;
static const int STOP_X = 214;
static const int STOP_W = 100;
static const int CLEAR_X = 322;
static const int CLEAR_W = 70;
static const int PROG_X = 46;
static const int PROG_Y = 286;
static const int PROG_W = 346;
static const int PROG_H = 8;
static const int STATS_Y = 336;
static const int STATS_W = 108;
static const int STATS_H = 70;
static const int OPEN_X = 46;
static const int OPEN_Y = 568;
static const int OPEN_W = 346;
static const int OPEN_H = 34;
static const int IMG_X = 46;
static const int IMG_Y = 634;
static const int IMG_W = 136;
static const int IMG_H = 34;
static const int IMG_FILE_X = 192;
static const int IMG_FILE_W = 84;
static const int IMG_AN_X = 282;
static const int IMG_AN_W = 110;
static const int IMG_INFO_Y = 674;
static const int IMG_PAL_Y = 690;
static const int IMG_SWATCH = 16;
static const int IMG_SWATCH_GAP = 4;
static const int IMG_BTN_Y1 = 712;
static const int IMG_BTN_Y2 = 746;
static const int IMG_BTN_W = 168;
static const int IMG_BTN_H = 28;
static const int IMG_SITE_MAX = 10;
static const int IMG_SITE_CAP = 96;
static const int SITE_MODAL_W = 760;
static const int SITE_MODAL_H = 560;
static const int SITE_MODAL_ROW_H = 34;
static const int CONTACT_MODAL_W = 760;
static const int CONTACT_MODAL_H = 520;
static const int CONTACT_ROW_H = 44;

static char* SITE_NAMES;
static char* SITE_TMPL;
static char* R_TITLE;
static char* R_STACK;
static char* R_URL;
static char* R_EVIDENCE;
static int* R_KIND;
static int* R_HTTP;
static int* R_REDIR;
static int* R_CHECKED;
static int* R_CONF;

static char* SCAN_USER;
static char* STATUS_BUF;
static char* MSG_BUF;
static char* HTTP_BUF;
static char* CONF_BUF;
static char* COLOR_URL;
static char* COLOR_TMP;
static char* COLOR_CONV;
static char* COLOR_LOCAL;
static char* COLOR_UPLOAD;
static char* YANDEX_JSON;
static char* YANDEX_CBIR;
static char* IMG_SITE_DOMAINS;
static char* IMG_SITE_SEARCH_URL;
static char* CONTACT_INPUT;
static char* CONTACT_NORM;
static char* CONTACT_DOMAIN;
static char* CONTACT_MX;
static char* CONTACT_GRAV;
static char* CONTACT_GRAV_URL;
static char* CONTACT_HIBP;
static char* CONTACT_COUNTRY;
static char* CONTACT_STATUS;
static char* CLOCK_BUF;
static char* DATE_BUF;
static char* ENV_BUF;
static char** ENV_PTRS;
static int ENV_COUNT;

static int USER_INPUT;
static int IMAGE_INPUT;
static ColorProfile* COLOR;
static int COLOR_READY;
static int IMG_SITE_COUNT;
static int IMG_SITE_TOTAL;
static int IMG_SITE_VISIBLE;
static int TARGET_MODE;
static int CONTACT_VISIBLE;
static int CONTACT_MODE;
static int CONTACT_OK;
static int CONTACT_DIGITS;
static int CONTACT_GRAV_OK;
static int CONTACT_HIBP_STATE;
static int CONTACT_HIBP_COUNT;
static int SCAN_INDEX;
static int SCAN_ACTIVE;
static int SELECTED;

static int SHA_BG;
static int SHA_CARD;
static int SHA_CARD2;
static int SHA_BORDER;
static int SHA_TEXT;
static int SHA_MUTED;
static int SHA_ACCENT;
static int SHA_GREEN;
static int SHA_RED;
static int SHA_ORANGE;
static int SHA_BLUE;
static int SHA_PURPLE;
static int SHA_TRACK;
static int SHA_DARK;

fn sha_set_palette() -> void {
    SHA_BG = gui_rgb(8, 12, 20);
    SHA_CARD = gui_rgb(18, 25, 38);
    SHA_CARD2 = gui_rgb(13, 19, 30);
    SHA_BORDER = gui_rgb(38, 52, 72);
    SHA_TEXT = gui_rgb(232, 239, 249);
    SHA_MUTED = gui_rgb(129, 146, 170);
    SHA_ACCENT = gui_rgb(77, 157, 255);
    SHA_GREEN = gui_rgb(54, 211, 153);
    SHA_RED = gui_rgb(255, 107, 129);
    SHA_ORANGE = gui_rgb(255, 155, 84);
    SHA_BLUE = gui_rgb(91, 192, 255);
    SHA_PURPLE = gui_rgb(167, 139, 250);
    SHA_TRACK = gui_rgb(32, 43, 61);
    SHA_DARK = gui_rgb(7, 11, 18);
}

fn sha_byte(char* p, int i) -> int {
    int v = cast<int>(*(p + i));
    if (v < 0) { v = v + 256; }
    return v;
}

fn sha_len(char* p) -> int {
    int n = 0;
    while (sha_byte(p, n) != 0) { n = n + 1; }
    return n;
}

fn sha_get_u32(char* p, int off) -> int {
    return sha_byte(p, off) + sha_byte(p, off + 1) * 256 + sha_byte(p, off + 2) * 65536 + sha_byte(p, off + 3) * 16777216;
}

fn sha_read_file(string path, char* buf, int cap) -> int {
    if (cap <= 1) { return 0; }
    int fd = sys_open(path, 0, 0);
    if (fd < 0) { return 0; }
    int total = 0;
    while (total < cap - 1) {
        int n = sys_read(fd, buf + total, cap - 1 - total);
        if (n <= 0) { break; }
        total = total + n;
    }
    sys_close(fd);
    *(buf + total) = 0;
    return total;
}

fn sha_find_bytes(char* p, int n, int start, string needle) -> int {
    char* q = cast<char*>(needle);
    int m = sha_len(q);
    if (m <= 0) { return -1; }
    if (start < 0) { start = 0; }
    int i = start;
    while (i + m <= n) {
        int j = 0;
        int ok = 1;
        while (j < m) {
            if (sha_byte(p, i + j) != sha_byte(q, j)) { ok = 0; break; }
            j = j + 1;
        }
        if (ok == 1) { return i; }
        i = i + 1;
    }
    return -1;
}

fn sha_reset_image_sites() -> void {
    IMG_SITE_COUNT = 0;
    IMG_SITE_TOTAL = 0;
    IMG_SITE_VISIBLE = 0;
    if (IMG_SITE_DOMAINS != null) { *(IMG_SITE_DOMAINS) = 0; }
    if (IMG_SITE_SEARCH_URL != null) { *(IMG_SITE_SEARCH_URL) = 0; }
}

fn sha_image_ready() -> int {
    if (COLOR_READY == 0) { return 0; }
    string src = str_trim(dsk_widget_text(IMAGE_INPUT));
    if (str_equals(src, cast<string>(COLOR_URL)) == 0) { return 0; }
    return 1;
}

fn sha_append(char* dst, int cap, int di, string src) -> int {
    if (src == null) { return di; }
    char* p = cast<char*>(src);
    int i = 0;
    while (di < cap - 1 && sha_byte(p, i) != 0) {
        *(dst + di) = *(p + i);
        di = di + 1;
        i = i + 1;
    }
    return di;
}

fn sha_set(char* dst, int cap, string src) -> void {
    int di = sha_append(dst, cap, 0, src);
    *(dst + di) = 0;
}

fn sha_put_clean(char* store, int index, int cap, string src) -> void {
    char* dst = store + index * cap;
    *(dst) = 0;
    if (src == null) { return; }
    string trimmed = str_trim(src);
    char* p = cast<char*>(trimmed);
    int i = 0;
    while (i < cap - 1 && sha_byte(p, i) != 0) {
        int c = sha_byte(p, i);
        if (c < 32 || c > 126) { c = 32; }
        *(dst + i) = cast<char>(c);
        i = i + 1;
    }
    *(dst + i) = 0;
    while (i > 0 && sha_byte(dst, i - 1) == 32) {
        i = i - 1;
        *(dst + i) = 0;
    }
}

fn sha_text(int x, int y, string s, int color, int scale) -> void {
    int old = gui_get_scale();
    if (old != scale) { gui_set_scale(scale); }
    gui_draw_text_fg(x, y, s, color, 255);
    if (old != scale) { gui_set_scale(old); }
}

fn sha_text_clip(int x, int y, string s, int color, int maxw, int scale) -> void {
    int old = gui_get_scale();
    if (old != scale) { gui_set_scale(scale); }
    dsk_text_clip_fg(x, y, s, color, maxw);
    if (old != scale) { gui_set_scale(old); }
}

fn sha_text_right(int right, int y, string s, int color, int scale) -> void {
    int w = gui_text_width(s, scale);
    sha_text(right - w, y, s, color, scale);
}

fn sha_text_center(int x, int y, int w, string s, int color, int scale) -> void {
    int tw = gui_text_width(s, scale);
    if (tw > w - 8) {
        sha_text_clip(x + 4, y, s, color, w - 8, scale);
    } else {
        sha_text(x + (w - tw) / 2, y, s, color, scale);
    }
}

fn sha_in_rect(int mx, int my, int x, int y, int w, int h) -> int {
    if (mx < x || mx >= x + w) { return 0; }
    if (my < y || my >= y + h) { return 0; }
    return 1;
}

fn sha_card(int x, int y, int w, int h, int accent) -> void {
    gui_fill_rounded_rect(x + 3, y + 5, w, h, 12, gui_rgb(4, 7, 12));
    gui_fill_rounded_rect(x, y, w, h, 12, SHA_CARD);
    gui_draw_rounded_rect(x, y, w, h, 12, SHA_BORDER);
    gui_fill_rounded_rect(x + 22, y, 52, 3, 1, accent);
}

fn sha_progress(int x, int y, int w, int h, int pct) -> void {
    if (pct < 0) { pct = 0; }
    if (pct > 100) { pct = 100; }
    gui_fill_rounded_rect(x, y, w, h, h / 2, SHA_TRACK);
    int fw = w * pct / 100;
    if (fw > 0) {
        if (fw < h) { fw = h; }
        gui_fill_rounded_rect(x, y, fw, h, h / 2, SHA_ACCENT);
    }
}

fn sha_button(int x, int y, int w, int h, string label, int enabled, int style) -> void {
    int hover = sha_in_rect(gui_mouse_x(), gui_mouse_y(), x, y, w, h);
    int bg = SHA_CARD2;
    int fg = SHA_TEXT;
    int border = SHA_BORDER;
    if (style == 1) {
        bg = SHA_ACCENT;
        fg = SHA_DARK;
        border = SHA_ACCENT;
    } else if (style == 2) {
        bg = gui_rgb(54, 28, 38);
        fg = SHA_RED;
        border = gui_rgb(111, 52, 69);
    } else if (style == 3) {
        bg = gui_rgb(27, 32, 56);
        fg = SHA_BLUE;
        border = gui_rgb(65, 78, 122);
    }
    if (hover == 1 && enabled == 1) {
        if (style == 1) { bg = gui_rgb(111, 181, 255); }
        else if (style == 2) { bg = gui_rgb(79, 39, 53); }
        else if (style == 3) { bg = gui_rgb(38, 46, 78); }
        else { bg = gui_rgb(30, 41, 62); }
    }
    if (enabled == 0) {
        bg = gui_rgb(21, 27, 39);
        fg = SHA_MUTED;
        border = gui_rgb(31, 41, 57);
    }
    gui_fill_rounded_rect(x, y, w, h, 6, bg);
    gui_draw_rounded_rect(x, y, w, h, 6, border);
    sha_text_center(x, y + (h - 16) / 2, w, label, fg, 1);
}

fn sha_kind_label(int kind) -> string {
    if (kind == 1) { return "FOUND"; }
    if (kind == 2) { return "NOT FOUND"; }
    if (kind == 3) { return "BLOCKED"; }
    if (kind == 4) { return "ERROR"; }
    if (kind == 5) { return "REDIRECT"; }
    if (kind == 6) { return "UNKNOWN"; }
    return "PENDING";
}

fn sha_kind_color(int kind) -> int {
    if (kind == 1) { return SHA_GREEN; }
    if (kind == 2) { return SHA_RED; }
    if (kind == 3) { return SHA_ORANGE; }
    if (kind == 4) { return SHA_ORANGE; }
    if (kind == 5) { return SHA_BLUE; }
    if (kind == 6) { return SHA_PURPLE; }
    return SHA_MUTED;
}

fn sha_site_name(int i) -> string {
    return cast<string>(SITE_NAMES + i * 64);
}

fn sha_site_template(int i) -> string {
    return cast<string>(SITE_TMPL + i * 160);
}

fn sha_title(int i) -> string {
    return cast<string>(R_TITLE + i * 96);
}

fn sha_stack(int i) -> string {
    return cast<string>(R_STACK + i * 72);
}

fn sha_evidence(int i) -> string {
    return cast<string>(R_EVIDENCE + i * 64);
}

fn sha_url(int i) -> string {
    return cast<string>(R_URL + i * 256);
}

fn sha_init_sites() -> void {
    SITE_NAMES = alloc<char>(SITE_COUNT * 64);
    SITE_TMPL = alloc<char>(SITE_COUNT * 160);
    R_TITLE = alloc<char>(SITE_COUNT * 96);
    R_STACK = alloc<char>(SITE_COUNT * 72);
    R_URL = alloc<char>(SITE_COUNT * 256);
    R_EVIDENCE = alloc<char>(SITE_COUNT * 64);
    R_KIND = alloc<int>(SITE_COUNT);
    R_HTTP = alloc<int>(SITE_COUNT);
    R_REDIR = alloc<int>(SITE_COUNT);
    R_CHECKED = alloc<int>(SITE_COUNT);
    R_CONF = alloc<int>(SITE_COUNT);

    sha_put_clean(SITE_NAMES, 0, 64, "GitHub");
    sha_put_clean(SITE_NAMES, 1, 64, "GitLab");
    sha_put_clean(SITE_NAMES, 2, 64, "Reddit");
    sha_put_clean(SITE_NAMES, 3, 64, "Instagram");
    sha_put_clean(SITE_NAMES, 4, 64, "X (Twitter)");
    sha_put_clean(SITE_NAMES, 5, 64, "TikTok");
    sha_put_clean(SITE_NAMES, 6, 64, "Pinterest");
    sha_put_clean(SITE_NAMES, 7, 64, "Telegram");
    sha_put_clean(SITE_NAMES, 8, 64, "PyPI");
    sha_put_clean(SITE_NAMES, 9, 64, "npm");
    sha_put_clean(SITE_NAMES, 10, 64, "Keybase");
    sha_put_clean(SITE_NAMES, 11, 64, "Twitch");
    sha_put_clean(SITE_NAMES, 12, 64, "Medium");
    sha_put_clean(SITE_NAMES, 13, 64, "Docker Hub");
    sha_put_clean(SITE_NAMES, 14, 64, "Hacker News");
    sha_put_clean(SITE_NAMES, 15, 64, "Dev.to");

    sha_put_clean(SITE_TMPL, 0, 160, "https://github.com/{u}");
    sha_put_clean(SITE_TMPL, 1, 160, "https://gitlab.com/{u}");
    sha_put_clean(SITE_TMPL, 2, 160, "https://www.reddit.com/user/{u}");
    sha_put_clean(SITE_TMPL, 3, 160, "https://www.instagram.com/{u}/");
    sha_put_clean(SITE_TMPL, 4, 160, "https://x.com/{u}");
    sha_put_clean(SITE_TMPL, 5, 160, "https://www.tiktok.com/@{u}");
    sha_put_clean(SITE_TMPL, 6, 160, "https://www.pinterest.com/{u}/");
    sha_put_clean(SITE_TMPL, 7, 160, "https://t.me/{u}");
    sha_put_clean(SITE_TMPL, 8, 160, "https://pypi.org/user/{u}/");
    sha_put_clean(SITE_TMPL, 9, 160, "https://www.npmjs.com/~{u}");
    sha_put_clean(SITE_TMPL, 10, 160, "https://keybase.io/{u}");
    sha_put_clean(SITE_TMPL, 11, 160, "https://www.twitch.tv/{u}");
    sha_put_clean(SITE_TMPL, 12, 160, "https://medium.com/@{u}");
    sha_put_clean(SITE_TMPL, 13, 160, "https://hub.docker.com/u/{u}");
    sha_put_clean(SITE_TMPL, 14, 160, "https://news.ycombinator.com/user?id={u}");
    sha_put_clean(SITE_TMPL, 15, 160, "https://dev.to/{u}");
}

fn sha_reset_results() -> void {
    int i = 0;
    while (i < SITE_COUNT) {
        R_KIND[i] = 0;
        R_HTTP[i] = 0;
        R_REDIR[i] = 0;
        R_CHECKED[i] = 0;
        R_CONF[i] = 0;
        *(R_TITLE + i * 96) = 0;
        *(R_STACK + i * 72) = 0;
        *(R_URL + i * 256) = 0;
        *(R_EVIDENCE + i * 64) = 0;
        i = i + 1;
    }
    SCAN_INDEX = 0;
}

fn sha_count_kind(int kind) -> int {
    int n = 0;
    int i = 0;
    while (i < SITE_COUNT) {
        if (R_CHECKED[i] == 1 && R_KIND[i] == kind) { n = n + 1; }
        i = i + 1;
    }
    return n;
}

fn sha_count_issues() -> int {
    int n = 0;
    int i = 0;
    while (i < SITE_COUNT) {
        if (R_CHECKED[i] == 1 && R_KIND[i] >= 3) { n = n + 1; }
        i = i + 1;
    }
    return n;
}

fn sha_set_msg(string msg) -> void {
    sha_set(MSG_BUF, 192, msg);
}

fn sha_finish_scan() -> void {
    SCAN_ACTIVE = 0;
    int found = sha_count_kind(1);
    int missing = sha_count_kind(2);
    int issues = sha_count_issues();
    int di = 0;
    di = sha_append(MSG_BUF, 192, 0, "Scan complete: ");
    di = sha_append(MSG_BUF, 192, di, dsk_itoa(found));
    di = sha_append(MSG_BUF, 192, di, " found, ");
    di = sha_append(MSG_BUF, 192, di, dsk_itoa(missing));
    di = sha_append(MSG_BUF, 192, di, " not found, ");
    di = sha_append(MSG_BUF, 192, di, dsk_itoa(issues));
    di = sha_append(MSG_BUF, 192, di, " issues.");
    *(MSG_BUF + di) = 0;
}

fn sha_start_scan() -> void {
    if (SCAN_ACTIVE == 1) { return; }
    string input_text = dsk_widget_text(USER_INPUT);
    string user = str_trim(input_text);
    if (len(user) == 0) {
        sha_set_msg("Enter a username before scanning.");
        return;
    }
    sha_set(SCAN_USER, 128, user);
    sha_reset_results();
    SELECTED = 0 - 1;
    SCAN_ACTIVE = 1;
    sha_set_msg("Preparing probes...");
    dsk_clear_focus();
}

fn sha_is_login_url(string url) -> int {
    string low = str_to_lower(url);
    if (str_contains(low, "login")) { return 1; }
    if (str_contains(low, "signin")) { return 1; }
    if (str_contains(low, "sign_in")) { return 1; }
    if (str_contains(low, "consent")) { return 1; }
    if (str_contains(low, "challenge")) { return 1; }
    if (str_contains(low, "captcha")) { return 1; }
    return 0;
}


fn sha_text_has_ci(string text, string sub) -> int {
    if (len(text) == 0 || len(sub) == 0) { return 0; }
    if (str_contains(str_to_lower(text), str_to_lower(sub))) { return 1; }
    return 0;
}

fn sha_soft404_title(string title) -> int {
    string low = str_to_lower(title);
    if (str_contains(low, "not found")) { return 1; }
    if (str_contains(low, "page not found")) { return 1; }
    if (str_contains(low, "user not found")) { return 1; }
    if (str_contains(low, "doesn't exist")) { return 1; }
    if (str_contains(low, "does not exist")) { return 1; }
    if (str_contains(low, "couldn't find")) { return 1; }
    if (str_contains(low, "could not find")) { return 1; }
    if (str_contains(low, "no longer available")) { return 1; }
    if (str_contains(low, "404")) { return 1; }
    return 0;
}

fn sha_conf_color(int conf) -> int {
    if (conf >= 75) { return SHA_GREEN; }
    if (conf >= 50) { return SHA_BLUE; }
    if (conf >= 30) { return SHA_ORANGE; }
    return SHA_RED;
}

fn sha_check_site(int index) -> void {
    string user = cast<string>(SCAN_USER);
    string encoded = url_encode_form_component(user);
    string target = str_replace(sha_site_template(index), "{u}", encoded);
    string headers = "User-Agent: Mozilla/5.0 (X11; Linux x86_64) MagnetarSherlock/2.0\r\n";
    headers = str_concat(headers, "Accept: text/html,application/xhtml+xml\r\n");
    headers = str_concat(headers, "Accept-Language: en-US,en;q=0.8\r\n");

    HttpResponse resp = http_request_ex("GET", target, "", "", headers, true, 4000, true);
    R_CHECKED[index] = 1;
    R_HTTP[index] = resp.status_code;
    R_REDIR[index] = resp.redirects;

    string final_url = resp.final_url;
    if (len(final_url) == 0) { final_url = target; }
    sha_put_clean(R_URL, index, 256, final_url);

    string stack = "";
    string server = http_header_value(resp.headers, "Server");
    string powered = http_header_value(resp.headers, "X-Powered-By");
    if (len(server) > 0) { stack = osint_fingerprint_server(server); }
    if (len(powered) > 0) {
        if (len(stack) > 0) { stack = str_concat(stack, " / "); }
        stack = str_concat(stack, osint_fingerprint_server(powered));
    }
    if (len(stack) == 0) { stack = "Unknown stack"; }
    sha_put_clean(R_STACK, index, 72, stack);

    string title = "";
    int conf = 45;
    string evidence = "transport error";
    if (resp.error != "") {
        R_KIND[index] = 4;
        title = resp.error;
        conf = 40;
        sha_put_clean(R_TITLE, index, 96, title);
    } else {
        if (resp.body_length > 0 && resp.body_length < 800000) {
            title = http_html_title(resp.body);
        }
        if (len(title) == 0) { title = "No page title available"; }
        sha_put_clean(R_TITLE, index, 96, title);

        int status = resp.status_code;
        int login = sha_is_login_url(final_url);
        int soft404 = sha_soft404_title(title);
        int body_user = 0;
        if (len(user) >= 3 && resp.body_length > 0 && resp.body_length < 800000) {
            if (str_contains(resp.body, user)) { body_user = 1; }
        }
        int title_user = sha_text_has_ci(title, user);
        int url_user = sha_text_has_ci(final_url, user);

        if (status == 200) {
            if (soft404 == 1) {
                R_KIND[index] = 2;
                conf = 88;
                evidence = "soft-404 page title";
            } else if (login == 1) {
                R_KIND[index] = 3;
                conf = 58;
                evidence = "login / consent wall";
            } else if (body_user == 1) {
                R_KIND[index] = 1;
                conf = 91;
                evidence = "username in page body";
            } else if (title_user == 1) {
                R_KIND[index] = 1;
                conf = 84;
                evidence = "username in page title";
            } else if (url_user == 1) {
                R_KIND[index] = 1;
                conf = 72;
                evidence = "username in profile URL";
            } else {
                R_KIND[index] = 1;
                conf = 48;
                evidence = "no username evidence";
                if (str_equals(title, "No page title available")) {
                    conf = 36;
                    evidence = "generic or empty title";
                }
                if (resp.body_length < 1500) {
                    conf = conf - 8;
                    if (conf < 20) { conf = 20; }
                    evidence = str_concat(evidence, " / thin page");
                }
            }
        } else if (status == 404) {
            R_KIND[index] = 2;
            conf = 94;
            evidence = "HTTP 404";
        } else if (status == 403 || status == 429 || status == 503) {
            R_KIND[index] = 3;
            conf = 64;
            evidence = "access blocked";
        } else if (status == 301 || status == 302 || status == 303 || status == 307 || status == 308) {
            R_KIND[index] = 5;
            conf = 56;
            evidence = "redirect only";
        } else if (status >= 200 && status < 300) {
            R_KIND[index] = 1;
            conf = 62;
            evidence = "HTTP 2xx page";
        } else {
            R_KIND[index] = 6;
            conf = 45;
            evidence = "unexpected status";
        }

        if (login == 1 && R_KIND[index] != 3) {
            conf = conf - 15;
            if (conf < 20) { conf = 20; }
            evidence = str_concat(evidence, " / login hint");
        }
        if (R_REDIR[index] > 0 && R_KIND[index] != 5) {
            if (conf > 55) { conf = conf - 5; }
            evidence = str_concat(evidence, " / redirect");
        }
    }

    if (conf < 0) { conf = 0; }
    if (conf > 100) { conf = 100; }
    R_CONF[index] = conf;
    sha_put_clean(R_EVIDENCE, index, 64, evidence);

    if (resp.body_data != null) { free(resp.body_data); }
}

fn sha_build_scanning() -> void {
    int di = 0;
    di = sha_append(STATUS_BUF, 160, 0, "Probing ");
    di = sha_append(STATUS_BUF, 160, di, sha_site_name(SCAN_INDEX));
    di = sha_append(STATUS_BUF, 160, di, "  (");
    di = sha_append(STATUS_BUF, 160, di, dsk_itoa(SCAN_INDEX + 1));
    di = sha_append(STATUS_BUF, 160, di, "/16)");
    *(STATUS_BUF + di) = 0;
}

fn sha_http_info(int i) -> string {
    int di = 0;
    if (R_CHECKED[i] == 0) {
        di = sha_append(HTTP_BUF, 96, 0, "Pending");
    } else {
        di = sha_append(HTTP_BUF, 96, 0, "HTTP ");
        di = sha_append(HTTP_BUF, 96, di, dsk_itoa(R_HTTP[i]));
        di = sha_append(HTTP_BUF, 96, di, "  CONF ");
        di = sha_append(HTTP_BUF, 96, di, dsk_itoa(R_CONF[i]));
        di = sha_append(HTTP_BUF, 96, di, "%");
        if (R_REDIR[i] > 0) {
            di = sha_append(HTTP_BUF, 96, di, "  /  ");
            di = sha_append(HTTP_BUF, 96, di, dsk_itoa(R_REDIR[i]));
            di = sha_append(HTTP_BUF, 96, di, "r");
        }
    }
    *(HTTP_BUF + di) = 0;
    return cast<string>(HTTP_BUF);
}

fn sha_build_clock() -> void {
    int ts = get_timestamp();
    int day = ts / 86400;
    int secs = ts - day * 86400;
    int h = secs / 3600;
    int m = (secs - h * 3600) / 60;
    int s = secs - h * 3600 - m * 60;
    int di = 0;
    di = sha_append(CLOCK_BUF, 16, 0, dsk_itoa_pad(h, 2));
    *(CLOCK_BUF + di) = 58; di = di + 1;
    di = sha_append(CLOCK_BUF, 16, di, dsk_itoa_pad(m, 2));
    *(CLOCK_BUF + di) = 58; di = di + 1;
    di = sha_append(CLOCK_BUF, 16, di, dsk_itoa_pad(s, 2));
    *(CLOCK_BUF + di) = 0;

    int zz = day + 719468;
    int era = zz / 146097;
    int doe = zz - era * 146097;
    int yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    int y = yoe + era * 400;
    int doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    int mp = (5 * doy + 2) / 153;
    int d = doy - (153 * mp + 2) / 5 + 1;
    int mo = mp + 3;
    if (mp >= 10) { mo = mp - 9; }
    if (mo <= 2) { y = y + 1; }
    di = sha_append(DATE_BUF, 16, 0, dsk_itoa(y));
    *(DATE_BUF + di) = 45; di = di + 1;
    di = sha_append(DATE_BUF, 16, di, dsk_itoa_pad(mo, 2));
    *(DATE_BUF + di) = 45; di = di + 1;
    di = sha_append(DATE_BUF, 16, di, dsk_itoa_pad(d, 2));
    *(DATE_BUF + di) = 0;
}

fn sha_build_envp(int n) -> void {
    ENV_COUNT = 0;
    int i = 0;
    while (i < n && ENV_COUNT < 255) {
        if (sha_byte(ENV_BUF, i) != 0) {
            ENV_PTRS[ENV_COUNT] = ENV_BUF + i;
            ENV_COUNT = ENV_COUNT + 1;
        }
        while (i < n && sha_byte(ENV_BUF, i) != 0) { i = i + 1; }
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

fn sha_load_env() -> void {
    int fd = sys_open("/proc/self/environ", 0, 0);
    if (fd < 0) { sha_build_envp(0); return; }
    int n = sys_read(fd, ENV_BUF, 8191);
    sys_close(fd);
    if (n <= 0) { sha_build_envp(0); return; }
    sha_build_envp(n);
}

fn sha_env_value(string key) -> string {
    int kl = len(key);
    if (kl == 0) { return ""; }
    int i = 0;
    while (i < ENV_COUNT) {
        string entry = cast<string>(ENV_PTRS[i]);
        if (len(entry) > kl && str_starts_with(entry, key)) {
            char* p = cast<char*>(entry);
            if (sha_byte(p, kl) == 61) {
                return str_substr(entry, kl + 1, len(entry) - kl - 1);
            }
        }
        i = i + 1;
    }
    return "";
}

fn sha_capture(string path, char** argv, char* out, int cap) -> int {
    if (cap <= 1) { return 0; }
    *(out) = 0;
    if (ENV_COUNT == 0) { sha_load_env(); }
    char* fds = alloc<char>(8);
    int i = 0;
    while (i < 8) { *(fds + i) = 0; i = i + 1; }
    if (sys_pipe(fds) != 0) {
        free(fds);
        return 0;
    }
    int rd = sha_get_u32(fds, 0);
    int wr = sha_get_u32(fds, 4);
    int pid = sys_fork();
    if (pid == 0) {
        sys_close(rd);
        sys_dup2(wr, 1);
        if (wr > 2) { sys_close(wr); }
        sys_execve(path, argv, ENV_PTRS);
        sys_exit(127);
    }
    sys_close(wr);
    int total = 0;
    while (total < cap - 1) {
        int n = sys_read(rd, out + total, cap - 1 - total);
        if (n <= 0) { break; }
        total = total + n;
    }
    sys_close(rd);
    int status = 0;
    sys_wait4(pid, &status, 0, null);
    *(out + total) = 0;
    free(fds);
    return total;
}

fn sha_open_url(string url) -> void {
    if (len(url) == 0) { return; }
    if (ENV_COUNT == 0) { sha_load_env(); }
    int pid = sys_fork();
    if (pid == 0) {
        char** argv = alloc<char*>(4);
        argv[0] = cast<char*>("xdg-open");
        argv[1] = cast<char*>(url);
        argv[2] = null;
        sys_execve("/usr/bin/xdg-open", argv, ENV_PTRS);
        sys_exit(127);
    } else if (pid > 0) {
        int status = 0;
        sys_wait4(pid, &status, 0, null);
    }
}

fn sha_file_exists(string path) -> int {
    int fd = sys_open(path, 0, 0);
    if (fd < 0) { return 0; }
    sys_close(fd);
    return 1;
}

fn sha_is_remote(string src) -> int {
    string low = str_to_lower(src);
    if (str_contains(low, "http://")) { return 1; }
    if (str_contains(low, "https://")) { return 1; }
    return 0;
}

fn sha_save_body(HttpResponse resp, string path) -> int {
    if (resp.body_data == null || resp.body_length <= 0) { return 0; }
    int fd = sys_open(path, 577, 420);
    if (fd < 0) { return 0; }
    int written = 0;
    while (written < resp.body_length) {
        int n = sys_write(fd, resp.body_data + written, resp.body_length - written);
        if (n <= 0) { break; }
        written = written + n;
    }
    sys_close(fd);
    if (written == resp.body_length) { return 1; }
    return 0;
}

fn sha_download_image(string src, string dst) -> int {
    if (sha_is_remote(src) == 0) {
        if (sha_file_exists(src) == 1) { return 1; }
        return 0;
    }
    string headers = "User-Agent: Mozilla/5.0 (X11; Linux x86_64) MagnetarSherlock/2.0\r\n";
    headers = str_concat(headers, "Accept: image/avif,image/webp,image/png,image/jpeg,image/*,*/*\r\n");
    HttpResponse resp = http_request_ex("GET", src, "", "", headers, true, 12000, true);
    int ok = 0;
    if (resp.error == "" && resp.status_code >= 200 && resp.status_code < 300) {
        if (resp.body_length > 0 && resp.body_length <= 12000000) {
            ok = sha_save_body(resp, dst);
        }
    }
    if (resp.body_data != null) { free(resp.body_data); }
    return ok;
}

fn sha_convert_image(string src, string dst) -> int {
    if (sha_file_exists(src) == 0) { return 0; }
    if (ENV_COUNT == 0) { sha_load_env(); }
    string first = str_concat(src, "[0]");
    int pid = sys_fork();
    if (pid == 0) {
        char** argv = alloc<char*>(5);
        argv[0] = cast<char*>("convert");
        argv[1] = cast<char*>(first);
        argv[2] = cast<char*>("-auto-orient");
        argv[3] = cast<char*>(dst);
        argv[4] = null;
        sys_execve("/usr/bin/convert", argv, ENV_PTRS);
        sys_exit(127);
    } else if (pid > 0) {
        int status = 0;
        sys_wait4(pid, &status, 0, null);
    }
    if (sha_file_exists(dst) == 1) { return 1; }
    return 0;
}

fn sha_analyze_image() -> void {
    string src = str_trim(dsk_widget_text(IMAGE_INPUT));
    if (len(src) == 0) {
        sha_set_msg("Enter an image URL or local path first.");
        return;
    }
    sha_set_msg("Analyzing image colors...");
    dsk_clear_focus();
    sha_reset_image_sites();
    string local = src;
    if (sha_is_remote(src) == 1) {
        if (sha_download_image(src, cast<string>(COLOR_TMP)) == 0) {
            COLOR_READY = 0;
            sha_set_msg("Image download failed. Check the URL.");
            return;
        }
        local = cast<string>(COLOR_TMP);
    } else if (sha_file_exists(src) == 0) {
        COLOR_READY = 0;
        sha_set_msg("Local image file not found.");
        return;
    }
    sha_set(COLOR_LOCAL, 512, local);

    image_intel_load(local, COLOR);
    if (COLOR.ok == 0) {
        if (sha_convert_image(local, cast<string>(COLOR_CONV)) == 1) {
            image_intel_load(cast<string>(COLOR_CONV), COLOR);
        }
    }
    if (COLOR.ok == 0) {
        COLOR_READY = 0;
        sha_set_msg("Could not decode this image.");
        return;
    }

    COLOR_READY = 1;
    sha_set(COLOR_URL, 512, src);
    int di = 0;
    di = sha_append(MSG_BUF, 192, 0, COLOR.classification);
    di = sha_append(MSG_BUF, 192, di, "  RISK ");
    di = sha_append(MSG_BUF, 192, di, dsk_itoa(COLOR.text_risk));
    di = sha_append(MSG_BUF, 192, di, "%  ");
    di = sha_append(MSG_BUF, 192, di, COLOR.dominant_name);
    *(MSG_BUF + di) = 0;
}

fn sha_pick_image_file() -> void {
    if (sha_file_exists("/usr/bin/zenity") == 0) {
        sha_set_msg("File picker unavailable: zenity is not installed.");
        return;
    }
    dsk_clear_focus();
    if (ENV_COUNT == 0) { sha_load_env(); }
    char* fds = alloc<char>(8);
    int i = 0;
    while (i < 8) { *(fds + i) = 0; i = i + 1; }
    if (sys_pipe(fds) != 0) {
        free(fds);
        sha_set_msg("Could not open the file picker.");
        return;
    }
    int rd = sha_get_u32(fds, 0);
    int wr = sha_get_u32(fds, 4);
    int pid = sys_fork();
    if (pid == 0) {
        sys_close(rd);
        sys_dup2(wr, 1);
        if (wr > 2) { sys_close(wr); }
        char** argv = alloc<char*>(8);
        argv[0] = cast<char*>("env");
        argv[1] = cast<char*>("GDK_BACKEND=x11");
        argv[2] = cast<char*>("zenity");
        argv[3] = cast<char*>("--file-selection");
        argv[4] = cast<char*>("--title=Select an image");
        argv[5] = cast<char*>("--file-filter=Images | *.png *.jpg *.jpeg *.webp *.gif *.bmp *.tga *.ppm *.pgm");
        argv[6] = null;
        sys_execve("/usr/bin/env", argv, ENV_PTRS);
        sys_exit(127);
    }
    sys_close(wr);
    char* buf = alloc<char>(1024);
    int n = sys_read(rd, buf, 1023);
    sys_close(rd);
    int status = 0;
    sys_wait4(pid, &status, 0, null);
    free(fds);
    if (n <= 0) {
        free(buf);
        sha_set_msg("File selection cancelled.");
        return;
    }
    *(buf + n) = 0;
    string path = str_trim(cast<string>(buf));
    free(buf);
    if (len(path) == 0) {
        sha_set_msg("File selection cancelled.");
        return;
    }
    dsk_widget_set_text(IMAGE_INPUT, path);
    sha_set_msg("Image selected. Analyzing...");
    sha_analyze_image();
}

fn sha_yandex_upload(string file) -> int {
    if (sha_file_exists(file) == 0) { return 0; }
    if (ENV_COUNT == 0) { sha_load_env(); }
    sys_unlink(cast<string>(YANDEX_JSON));
    string form = str_concat("upfile=@", file);
    form = str_concat(form, ";type=image/png");
    string url = "https://yandex.com/images/search?rpt=imageview&format=json&request=%7B%22blocks%22%3A%5B%7B%22block%22%3A%22b-page_type_search-by-image__link%22%7D%5D%7D";
    char** argv = alloc<char*>(14);
    int a = 0;
    argv[a] = cast<char*>("curl"); a = a + 1;
    argv[a] = cast<char*>("-sS"); a = a + 1;
    argv[a] = cast<char*>("-L"); a = a + 1;
    argv[a] = cast<char*>("-A"); a = a + 1;
    argv[a] = cast<char*>("Mozilla/5.0 (X11; Linux x86_64) MagnetarSherlock/2.0"); a = a + 1;
    argv[a] = cast<char*>("-F"); a = a + 1;
    argv[a] = cast<char*>(form); a = a + 1;
    argv[a] = cast<char*>("-o"); a = a + 1;
    argv[a] = cast<char*>(YANDEX_JSON); a = a + 1;
    argv[a] = cast<char*>("--max-time"); a = a + 1;
    argv[a] = cast<char*>("30"); a = a + 1;
    argv[a] = cast<char*>(url); a = a + 1;
    argv[a] = null;
    int pid = sys_fork();
    if (pid == 0) {
        sys_execve("/usr/bin/curl", argv, ENV_PTRS);
        sys_exit(127);
    } else if (pid > 0) {
        int status = 0;
        sys_wait4(pid, &status, 0, null);
    }
    free(argv);
    if (sha_file_exists(cast<string>(YANDEX_JSON)) == 1) { return 1; }
    return 0;
}

fn sha_read_cbir_id() -> int {
    char* buf = alloc<char>(8192);
    int n = sha_read_file(cast<string>(YANDEX_JSON), buf, 8192);
    if (n <= 0) { free(buf); return 0; }
    string cbir = http_json_get_string(cast<string>(buf), "cbirId");
    free(buf);
    if (len(cbir) == 0) { return 0; }
    sha_set(YANDEX_CBIR, 256, cbir);
    free(cast<char*>(cbir));
    return 1;
}

fn sha_site_domain(int i) -> string {
    return cast<string>(IMG_SITE_DOMAINS + i * IMG_SITE_CAP);
}

fn sha_collect_domains(char* body, int n, int max_items) -> int {
    IMG_SITE_COUNT = 0;
    IMG_SITE_TOTAL = 0;
    int start = sha_find_bytes(body, n, 0, "cbirSites");
    if (start < 0) { start = 0; }
    string key = "&quot;domain&quot;:&quot;";
    int key_len = sha_len(cast<char*>(key));
    int pos = start;
    while (pos < n) {
        int k = sha_find_bytes(body, n, pos, key);
        if (k < 0) { break; }
        int st = k + key_len;
        int en = st;
        while (en < n && sha_byte(body, en) != 34 && sha_byte(body, en) != 38) { en = en + 1; }
        if (en > st) {
            int dl = en - st;
            if (dl > IMG_SITE_CAP - 1) { dl = IMG_SITE_CAP - 1; }
            char* tmp = alloc<char>(dl + 1);
            int j = 0;
            while (j < dl) { *(tmp + j) = *(body + st + j); j = j + 1; }
            *(tmp + dl) = 0;
            string dom = str_trim(cast<string>(tmp));
            int unique = 1;
            if (len(dom) > 0) {
                int ci = 0;
                while (ci < IMG_SITE_COUNT) {
                    if (str_equals(sha_site_domain(ci), dom) == 1) { unique = 0; break; }
                    ci = ci + 1;
                }
            } else {
                unique = 0;
            }
            if (unique == 1) {
                IMG_SITE_TOTAL = IMG_SITE_TOTAL + 1;
                if (IMG_SITE_COUNT < max_items) {
                    sha_put_clean(IMG_SITE_DOMAINS, IMG_SITE_COUNT, IMG_SITE_CAP, dom);
                    IMG_SITE_COUNT = IMG_SITE_COUNT + 1;
                }
            }
            free(tmp);
        }
        if (en <= pos) { en = pos + 1; }
        pos = en + 1;
    }
    return IMG_SITE_TOTAL;
}

fn sha_fetch_image_sites(string cbir) -> int {
    string enc = url_encode_form_component(cbir);
    string url = str_concat("https://yandex.com/images/search?rpt=imageview&cbir_id=", enc);
    sha_set(IMG_SITE_SEARCH_URL, 512, url);
    string headers = "User-Agent: Mozilla/5.0 (X11; Linux x86_64) MagnetarSherlock/2.0\r\n";
    headers = str_concat(headers, "Accept: text/html,application/xhtml+xml\r\n");
    headers = str_concat(headers, "Accept-Language: en-US,en;q=0.9\r\n");
    HttpResponse resp = http_request_ex("GET", url, "", "", headers, true, 25000, true);
    int ok = 0;
    if (resp.error == "" && resp.status_code >= 200 && resp.status_code < 400 && resp.body_length > 0) {
        sha_collect_domains(resp.body_data, resp.body_length, IMG_SITE_MAX);
        ok = 1;
    }
    if (resp.body_data != null) { free(resp.body_data); }
    return ok;
}

fn sha_find_image_sites() -> void {
    string src = str_trim(dsk_widget_text(IMAGE_INPUT));
    if (len(src) == 0) {
        sha_set_msg("Select an image file first.");
        return;
    }
    if (sha_image_ready() == 0) {
        sha_set_msg("Press ANALYZE to verify the image first.");
        return;
    }
    if (COLOR.text_free == 0) {
        sha_set_msg("Image site search locked: image may contain text.");
        return;
    }
    if (len(cast<string>(COLOR_LOCAL)) == 0 || sha_file_exists(cast<string>(COLOR_LOCAL)) == 0) {
        sha_set_msg("Local image copy is not available. Analyze again.");
        return;
    }
    dsk_clear_focus();
    sha_reset_image_sites();
    sha_set_msg("Preparing image for Yandex...");
    if (sha_convert_image(cast<string>(COLOR_LOCAL), cast<string>(COLOR_UPLOAD)) == 0) {
        sha_set_msg("Could not prepare the image for upload.");
        return;
    }
    sha_set_msg("Uploading image and searching Yandex...");
    if (sha_yandex_upload(cast<string>(COLOR_UPLOAD)) == 0) {
        sha_set_msg("Yandex upload failed. Check your connection.");
        return;
    }
    if (sha_read_cbir_id() == 0) {
        sha_set_msg("Yandex did not return a search id.");
        return;
    }
    sha_set_msg("Loading sites that host this image...");
    if (sha_fetch_image_sites(cast<string>(YANDEX_CBIR)) == 0) {
        sha_set_msg("Yandex site lookup failed.");
        return;
    }
    IMG_SITE_VISIBLE = 1;
    if (IMG_SITE_TOTAL > 0) {
        int di = 0;
        di = sha_append(MSG_BUF, 192, 0, "Found ");
        di = sha_append(MSG_BUF, 192, di, dsk_itoa(IMG_SITE_TOTAL));
        di = sha_append(MSG_BUF, 192, di, " sites hosting this image.");
        *(MSG_BUF + di) = 0;
    } else {
        sha_set_msg("No hosting sites found. Try Google Lens or Bing.");
    }
}

fn sha_open_color_search(int idx) -> void {
    if (COLOR_READY == 0 || COLOR.palette_count == 0) {
        sha_set_msg("Analyze an image first.");
        return;
    }
    int ci = idx;
    if (ci < 0 || ci >= COLOR.palette_count) { ci = 0; }
    string name = ii_color_name(COLOR.pr[ci], COLOR.pg[ci], COLOR.pb[ci]);
    string canon = ii_canonical_color(COLOR.pr[ci], COLOR.pg[ci], COLOR.pb[ci]);
    string q = url_encode_form_component(str_concat(name, " color"));
    string url = str_concat("https://www.google.com/search?tbm=isch&q=", q);
    url = str_concat(url, "&tbs=ic:specific,isc:");
    url = str_concat(url, canon);
    sha_open_url(url);
    string msg = str_concat("Opening ", str_concat(name, " color image search..."));
    sha_set_msg(msg);
    dsk_clear_focus();
}

fn sha_open_provider(int provider) -> void {
    if (provider == 1) {
        sha_find_image_sites();
        return;
    }
    string src = str_trim(dsk_widget_text(IMAGE_INPUT));
    if (len(src) == 0) {
        sha_set_msg("Select an image or enter a URL first.");
        return;
    }
    if (sha_image_ready() == 0) {
        sha_set_msg("Press ANALYZE to verify the image first.");
        return;
    }
    if (COLOR.text_free == 0) {
        sha_set_msg("Reverse search locked: image may contain text.");
        return;
    }
    if (sha_is_remote(src) == 0) {
        sha_set_msg("This provider needs a public URL. Use FIND SITES for local files.");
        return;
    }
    string enc = url_encode_form_component(src);
    string url = "";
    string name = "";
    if (provider == 0) {
        url = str_concat("https://lens.google.com/uploadbyurl?url=", enc);
        name = "Google Lens";
    } else if (provider == 2) {
        url = str_concat("https://www.bing.com/images/search?view=detailv2&iss=sbi&form=SBIVSP&q=imgurl:", enc);
        name = "Bing Visual Search";
    } else {
        url = str_concat("https://tineye.com/search?url=", enc);
        name = "TinEye";
    }
    sha_open_url(url);
    string msg = str_concat("Opening ", str_concat(name, " in browser..."));
    sha_set_msg(msg);
    dsk_clear_focus();
}


fn sha_clear_contact() -> void {
    CONTACT_VISIBLE = 0;
    CONTACT_MODE = 0;
    CONTACT_OK = 0;
    CONTACT_DIGITS = 0;
    CONTACT_GRAV_OK = 0;
    CONTACT_HIBP_STATE = 0;
    CONTACT_HIBP_COUNT = 0;
    if (CONTACT_INPUT != null) { sha_set(CONTACT_INPUT, 320, ""); }
    if (CONTACT_NORM != null) { sha_set(CONTACT_NORM, 320, ""); }
    if (CONTACT_DOMAIN != null) { sha_set(CONTACT_DOMAIN, 256, ""); }
    if (CONTACT_MX != null) { sha_set(CONTACT_MX, 768, ""); }
    if (CONTACT_GRAV != null) { sha_set(CONTACT_GRAV, 320, ""); }
    if (CONTACT_GRAV_URL != null) { sha_set(CONTACT_GRAV_URL, 512, ""); }
    if (CONTACT_HIBP != null) { sha_set(CONTACT_HIBP, 320, ""); }
    if (CONTACT_COUNTRY != null) { sha_set(CONTACT_COUNTRY, 64, ""); }
    if (CONTACT_STATUS != null) { sha_set(CONTACT_STATUS, 192, ""); }
}

fn sha_domain_valid(string domain) -> int {
    int n = len(domain);
    if (n < 3 || n > 253) { return 0; }
    char* p = cast<char*>(domain);
    int first = sha_byte(p, 0);
    int last = sha_byte(p, n - 1);
    if (first == 46 || first == 45) { return 0; }
    if (last == 46 || last == 45) { return 0; }
    int i = 0;
    int dots = 0;
    int label = 0;
    while (i < n) {
        int c = sha_byte(p, i);
        if (c == 46) {
            if (label == 0) { return 0; }
            dots = dots + 1;
            label = 0;
        } else if (c == 45) {
            if (label == 0) { return 0; }
            label = label + 1;
        } else if ((c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122)) {
            label = label + 1;
        } else {
            return 0;
        }
        i = i + 1;
    }
    if (dots < 1 || label < 2) { return 0; }
    return 1;
}

fn sha_email_valid(string email) -> int {
    int n = len(email);
    if (n < 5 || n > 254) { return 0; }
    char* p = cast<char*>(email);
    int at = 0 - 1;
    int ats = 0;
    int i = 0;
    while (i < n) {
        int c = sha_byte(p, i);
        if (c == 64) {
            ats = ats + 1;
            at = i;
        } else if (c <= 32 || c >= 127) {
            return 0;
        }
        i = i + 1;
    }
    if (ats != 1 || at < 1 || at >= n - 1 || at > 64) { return 0; }
    string domain = str_substr(email, at + 1, n - at - 1);
    int ok = sha_domain_valid(domain);
    return ok;
}

fn sha_check_mx(string domain) -> void {
    sha_set(CONTACT_MX, 768, "No MX records");
    if (sha_file_exists("/usr/bin/dig") == 0) {
        sha_set(CONTACT_MX, 768, "dig is not installed");
        return;
    }
    char* out = alloc<char>(1024);
    char** argv = alloc<char*>(7);
    argv[0] = cast<char*>("dig");
    argv[1] = cast<char*>("+time=3");
    argv[2] = cast<char*>("+tries=1");
    argv[3] = cast<char*>("+short");
    argv[4] = cast<char*>("MX");
    argv[5] = cast<char*>(domain);
    argv[6] = null;
    int n = sha_capture("/usr/bin/dig", argv, out, 1024);
    free(argv);
    if (n > 0) {
        string flat = str_replace(cast<string>(out), "\r", "");
        flat = str_replace(flat, "\n", " / ");
        flat = str_trim(flat);
        if (len(flat) > 0) { sha_set(CONTACT_MX, 768, flat); }
    }
    free(out);
}

fn sha_check_gravatar(string email) -> void {
    CONTACT_GRAV_OK = 0;
    sha_set(CONTACT_GRAV, 320, "No public profile found");
    sha_set(CONTACT_GRAV_URL, 512, "");
    string hash = crypto_md5_hex(email);
    string base = str_concat("https://www.gravatar.com/", hash);
    string url = str_concat(base, ".json");
    string headers = "User-Agent: SherlockOSINT/2.0\r\n";
    headers = str_concat(headers, "Accept: application/json\r\n");
    HttpResponse resp = http_request_ex("GET", url, "", "", headers, true, 9000, true);
    if (resp.error != "") {
        sha_set(CONTACT_GRAV, 320, "Gravatar check failed");
    } else if (resp.status_code == 200) {
        string name = http_json_get_string(resp.body, "displayName");
        if (len(name) == 0) { name = http_json_get_string(resp.body, "preferredUsername"); }
        string profile = http_json_get_string(resp.body, "profileUrl");
        CONTACT_GRAV_OK = 1;
        if (len(name) > 0) {
            string label = str_concat("Public profile: ", name);
            sha_set(CONTACT_GRAV, 320, label);
        } else {
            sha_set(CONTACT_GRAV, 320, "Public profile found");
        }
        if (len(profile) > 0) {
            sha_set(CONTACT_GRAV_URL, 512, profile);
        } else {
            sha_set(CONTACT_GRAV_URL, 512, base);
        }
    } else if (resp.status_code == 404) {
        sha_set(CONTACT_GRAV, 320, "No public profile found");
    } else if (resp.status_code == 429) {
        sha_set(CONTACT_GRAV, 320, "Gravatar rate limit reached");
    } else {
        string msg = str_concat("Gravatar check failed: HTTP ", dsk_itoa(resp.status_code));
        sha_set(CONTACT_GRAV, 320, msg);
    }
    if (resp.body_data != null) { free(resp.body_data); }
}

fn sha_hibp_fill(string body) -> int {
    char* p = cast<char*>(body);
    int n = len(body);
    int pos = 0;
    int count = 0;
    char* names = alloc<char>(192);
    *(names) = 0;
    int ni = 0;
    while (pos < n) {
        int k = sha_find_bytes(p, n, pos, "\"Name\":\"");
        if (k < 0) { break; }
        int st = k + 8;
        int en = st;
        while (en < n && sha_byte(p, en) != 34) { en = en + 1; }
        if (en > st) {
            if (count < 3) {
                if (ni > 0) { ni = sha_append(names, 192, ni, ", "); }
                int take = en - st;
                if (take > 48) { take = 48; }
                char* tmp = alloc<char>(take + 1);
                int j = 0;
                while (j < take) { *(tmp + j) = *(p + st + j); j = j + 1; }
                *(tmp + take) = 0;
                ni = sha_append(names, 192, ni, cast<string>(tmp));
                free(tmp);
            }
            count = count + 1;
        }
        pos = en + 1;
    }
    if (count == 0) {
        sha_set(CONTACT_HIBP, 320, "0 known breaches (HIBP)");
    } else {
        int di = 0;
        di = sha_append(CONTACT_HIBP, 320, 0, dsk_itoa(count));
        di = sha_append(CONTACT_HIBP, 320, di, " breach");
        if (count != 1) { di = sha_append(CONTACT_HIBP, 320, di, "es"); }
        if (ni > 0) {
            di = sha_append(CONTACT_HIBP, 320, di, ": ");
            di = sha_append(CONTACT_HIBP, 320, di, cast<string>(names));
        }
        *(CONTACT_HIBP + di) = 0;
    }
    free(names);
    return count;
}

fn sha_check_hibp(string email) -> void {
    CONTACT_HIBP_STATE = 0;
    CONTACT_HIBP_COUNT = 0;
    string key = sha_env_value("HIBP_API_KEY");
    if (key == null || len(key) == 0) {
        sha_set(CONTACT_HIBP, 320, "Skipped (set HIBP_API_KEY)");
        return;
    }
    string enc = url_encode_form_component(email);
    string url = str_concat("https://haveibeenpwned.com/api/v3/breachedaccount/", enc);
    url = str_concat(url, "?truncateResponse=true");
    string headers = "User-Agent: SherlockOSINT/2.0\r\n";
    headers = str_concat(headers, "hibp-api-key: ");
    headers = str_concat(headers, key);
    headers = str_concat(headers, "\r\nAccept: application/json\r\n");
    HttpResponse resp = http_request_ex("GET", url, "", "", headers, true, 12000, true);
    if (resp.error != "") {
        CONTACT_HIBP_STATE = 3;
        sha_set(CONTACT_HIBP, 320, "HIBP check failed");
    } else if (resp.status_code == 200) {
        int count = sha_hibp_fill(resp.body);
        CONTACT_HIBP_COUNT = count;
        CONTACT_HIBP_STATE = 2;
    } else if (resp.status_code == 404) {
        CONTACT_HIBP_STATE = 1;
        sha_set(CONTACT_HIBP, 320, "0 known breaches (HIBP)");
    } else if (resp.status_code == 401 || resp.status_code == 403) {
        CONTACT_HIBP_STATE = 3;
        sha_set(CONTACT_HIBP, 320, "Invalid or unauthorized HIBP key");
    } else if (resp.status_code == 429) {
        CONTACT_HIBP_STATE = 3;
        sha_set(CONTACT_HIBP, 320, "HIBP rate limit reached");
    } else {
        CONTACT_HIBP_STATE = 3;
        string msg = str_concat("HIBP check failed: HTTP ", dsk_itoa(resp.status_code));
        sha_set(CONTACT_HIBP, 320, msg);
    }
    if (resp.body_data != null) { free(resp.body_data); }
}

fn sha_phone_country(string digits) -> string {
    if (str_starts_with(digits, "212")) { return "Morocco"; }
    if (str_starts_with(digits, "213")) { return "Algeria"; }
    if (str_starts_with(digits, "216")) { return "Tunisia"; }
    if (str_starts_with(digits, "218")) { return "Libya"; }
    if (str_starts_with(digits, "221")) { return "Senegal"; }
    if (str_starts_with(digits, "234")) { return "Nigeria"; }
    if (str_starts_with(digits, "254")) { return "Kenya"; }
    if (str_starts_with(digits, "961")) { return "Lebanon"; }
    if (str_starts_with(digits, "962")) { return "Jordan"; }
    if (str_starts_with(digits, "963")) { return "Syria"; }
    if (str_starts_with(digits, "964")) { return "Iraq"; }
    if (str_starts_with(digits, "965")) { return "Kuwait"; }
    if (str_starts_with(digits, "966")) { return "Saudi Arabia"; }
    if (str_starts_with(digits, "967")) { return "Yemen"; }
    if (str_starts_with(digits, "968")) { return "Oman"; }
    if (str_starts_with(digits, "970")) { return "Palestine"; }
    if (str_starts_with(digits, "971")) { return "UAE"; }
    if (str_starts_with(digits, "972")) { return "Israel"; }
    if (str_starts_with(digits, "973")) { return "Bahrain"; }
    if (str_starts_with(digits, "974")) { return "Qatar"; }
    if (str_starts_with(digits, "977")) { return "Nepal"; }
    if (str_starts_with(digits, "20")) { return "Egypt"; }
    if (str_starts_with(digits, "27")) { return "South Africa"; }
    if (str_starts_with(digits, "31")) { return "Netherlands"; }
    if (str_starts_with(digits, "32")) { return "Belgium"; }
    if (str_starts_with(digits, "33")) { return "France"; }
    if (str_starts_with(digits, "34")) { return "Spain"; }
    if (str_starts_with(digits, "39")) { return "Italy"; }
    if (str_starts_with(digits, "41")) { return "Switzerland"; }
    if (str_starts_with(digits, "43")) { return "Austria"; }
    if (str_starts_with(digits, "44")) { return "United Kingdom"; }
    if (str_starts_with(digits, "46")) { return "Sweden"; }
    if (str_starts_with(digits, "47")) { return "Norway"; }
    if (str_starts_with(digits, "48")) { return "Poland"; }
    if (str_starts_with(digits, "49")) { return "Germany"; }
    if (str_starts_with(digits, "52")) { return "Mexico"; }
    if (str_starts_with(digits, "54")) { return "Argentina"; }
    if (str_starts_with(digits, "55")) { return "Brazil"; }
    if (str_starts_with(digits, "60")) { return "Malaysia"; }
    if (str_starts_with(digits, "61")) { return "Australia"; }
    if (str_starts_with(digits, "62")) { return "Indonesia"; }
    if (str_starts_with(digits, "63")) { return "Philippines"; }
    if (str_starts_with(digits, "64")) { return "New Zealand"; }
    if (str_starts_with(digits, "65")) { return "Singapore"; }
    if (str_starts_with(digits, "66")) { return "Thailand"; }
    if (str_starts_with(digits, "81")) { return "Japan"; }
    if (str_starts_with(digits, "82")) { return "South Korea"; }
    if (str_starts_with(digits, "84")) { return "Vietnam"; }
    if (str_starts_with(digits, "86")) { return "China"; }
    if (str_starts_with(digits, "90")) { return "Turkey"; }
    if (str_starts_with(digits, "91")) { return "India"; }
    if (str_starts_with(digits, "92")) { return "Pakistan"; }
    if (str_starts_with(digits, "98")) { return "Iran"; }
    if (str_starts_with(digits, "1")) { return "USA / Canada"; }
    return "Unknown country code";
}

fn sha_phone_prepare(string phone_text) -> int {
    int n = len(phone_text);
    char* p = cast<char*>(phone_text);
    char* digits = alloc<char>(n + 2);
    int dc = 0;
    int plus = 0;
    int bad = 0;
    int i = 0;
    while (i < n) {
        int c = sha_byte(p, i);
        if (c >= 48 && c <= 57) {
            *(digits + dc) = cast<char>(c);
            dc = dc + 1;
        } else if (c == 43) {
            if (i == 0) { plus = 1; } else { bad = 1; }
        } else if (c == 32 || c == 45 || c == 40 || c == 41 || c == 46 || c == 47) {
        } else {
            bad = 1;
        }
        i = i + 1;
    }
    *(digits + dc) = 0;
    CONTACT_DIGITS = dc;
    if (dc < 8 || dc > 15) { bad = 1; }
    if (bad == 1) {
        free(digits);
        return 0;
    }
    char* norm = alloc<char>(dc + 2);
    int ni = 0;
    if (plus == 1) {
        *(norm) = 43;
        ni = 1;
    }
    int j = 0;
    while (j < dc) {
        *(norm + ni) = *(digits + j);
        ni = ni + 1;
        j = j + 1;
    }
    *(norm + ni) = 0;
    sha_set(CONTACT_NORM, 320, cast<string>(norm));
    if (plus == 1) {
        sha_set(CONTACT_COUNTRY, 64, sha_phone_country(cast<string>(digits)));
    } else {
        sha_set(CONTACT_COUNTRY, 64, "Unknown (no +country code)");
    }
    free(norm);
    free(digits);
    return 1;
}

fn sha_scan_email(string email) -> void {
    sha_set(CONTACT_NORM, 320, email);
    if (sha_email_valid(email) == 0) {
        CONTACT_OK = 0;
        sha_set(CONTACT_DOMAIN, 256, "");
        sha_set(CONTACT_MX, 768, "Skipped");
        sha_set(CONTACT_GRAV, 320, "Skipped");
        sha_set(CONTACT_HIBP, 320, "Skipped");
        sha_set(CONTACT_STATUS, 192, "Invalid email address.");
        sha_set_msg("Fix the email address and run checks again.");
        return;
    }
    CONTACT_OK = 1;
    string low = str_to_lower(email);
    int at = str_index_of(low, "@");
    string domain = str_substr(low, at + 1, len(low) - at - 1);
    sha_set(CONTACT_DOMAIN, 256, domain);
    sha_check_mx(domain);
    sha_check_gravatar(low);
    sha_check_hibp(low);
    sha_set(CONTACT_STATUS, 192, "Checks complete. Draft links need manual send.");
    sha_set_msg("Email verification report ready.");
}

fn sha_scan_phone(string phone_text) -> void {
    if (sha_phone_prepare(phone_text) == 0) {
        CONTACT_OK = 0;
        sha_set(CONTACT_STATUS, 192, "Invalid phone number or length.");
        sha_set_msg("Use 8 to 15 digits, optionally starting with +.");
        return;
    }
    CONTACT_OK = 1;
    sha_set(CONTACT_STATUS, 192, "Number is valid. SMS draft is manual only.");
    sha_set_msg("Phone verification report ready.");
}

fn sha_scan_contact() -> void {
    string input_text = dsk_widget_text(USER_INPUT);
    string val = str_trim(input_text);
    if (len(val) == 0) {
        if (TARGET_MODE == 1) {
            sha_set_msg("Enter an email address before running checks.");
        } else {
            sha_set_msg("Enter a phone number before running checks.");
        }
        return;
    }
    dsk_clear_focus();
    SCAN_ACTIVE = 0;
    IMG_SITE_VISIBLE = 0;
    sha_clear_contact();
    CONTACT_MODE = TARGET_MODE;
    CONTACT_VISIBLE = 1;
    sha_set(CONTACT_INPUT, 320, val);
    if (TARGET_MODE == 1) {
        sha_scan_email(val);
    } else {
        sha_scan_phone(val);
    }
}

fn sha_start_target() -> void {
    dsk_clear_focus();
    if (TARGET_MODE == 0) {
        if (SCAN_ACTIVE == 0) { sha_start_scan(); }
        return;
    }
    sha_scan_contact();
}

fn sha_set_mode(int mode) -> void {
    if (TARGET_MODE == mode) { return; }
    TARGET_MODE = mode;
    SCAN_ACTIVE = 0;
    sha_reset_results();
    SELECTED = 0 - 1;
    sha_clear_contact();
    dsk_widget_set_text(USER_INPUT, "");
    dsk_clear_focus();
    dsk_focus_widget(USER_INPUT);
    if (mode == 1) {
        sha_set_msg("Email mode. Enter an address and run checks.");
    } else if (mode == 2) {
        sha_set_msg("Phone mode. Enter a number and run checks.");
    } else {
        sha_set_msg("Username mode. Enter a handle and start the scan.");
    }
}

fn sha_open_mail_draft() -> void {
    if (len(cast<string>(CONTACT_NORM)) == 0) { return; }
    string url = str_concat("mailto:", cast<string>(CONTACT_NORM));
    sha_open_url(url);
    sha_set_msg("Opening a manual email draft. Nothing is sent automatically.");
}

fn sha_open_sms_draft() -> void {
    if (len(cast<string>(CONTACT_NORM)) == 0) { return; }
    string url = str_concat("sms:", cast<string>(CONTACT_NORM));
    sha_open_url(url);
    sha_set_msg("Opening a manual SMS draft. Nothing is sent automatically.");
}

fn sha_handle_events(int clicked) -> void {
    int mx = gui_mouse_x();
    int my = gui_mouse_y();
    int click = gui_mouse_clicked();

    if (click != 1) { return; }

    if (CONTACT_VISIBLE == 1) {
        int sw = dsk_screen_w();
        int sh = dsk_screen_h();
        int px = (sw - CONTACT_MODAL_W) / 2;
        int py = (sh - CONTACT_MODAL_H) / 2;
        int by = py + CONTACT_MODAL_H - 60;
        if (sha_in_rect(mx, my, px + CONTACT_MODAL_W - 160, by, 128, 34) == 1) {
            CONTACT_VISIBLE = 0;
            return;
        }
        if (CONTACT_MODE == 1 && CONTACT_OK == 1 && sha_in_rect(mx, my, px + 32, by, 180, 34) == 1) {
            sha_open_mail_draft();
            return;
        }
        if (CONTACT_MODE == 1 && len(cast<string>(CONTACT_GRAV_URL)) > 0 && sha_in_rect(mx, my, px + 222, by, 160, 34) == 1) {
            sha_open_url(cast<string>(CONTACT_GRAV_URL));
            sha_set_msg("Opening Gravatar profile in browser...");
            return;
        }
        if (CONTACT_MODE == 2 && CONTACT_OK == 1 && sha_in_rect(mx, my, px + 32, by, 180, 34) == 1) {
            sha_open_sms_draft();
            return;
        }
        return;
    }

    if (IMG_SITE_VISIBLE == 1) {
        int sw = dsk_screen_w();
        int sh = dsk_screen_h();
        int px = (sw - SITE_MODAL_W) / 2;
        int py = (sh - SITE_MODAL_H) / 2;
        int by = py + 500;
        if (sha_in_rect(mx, my, px + SITE_MODAL_W - 160, by, 128, 34) == 1) {
            IMG_SITE_VISIBLE = 0;
            return;
        }
        if (sha_in_rect(mx, my, px + 32, by, 180, 34) == 1) {
            if (len(cast<string>(IMG_SITE_SEARCH_URL)) > 0) {
                sha_open_url(cast<string>(IMG_SITE_SEARCH_URL));
            }
            return;
        }
        return;
    }

    if (sha_in_rect(mx, my, 46, MODE_Y, MODE_W, MODE_H) == 1) {
        sha_set_mode(0);
        return;
    }
    if (sha_in_rect(mx, my, 46 + MODE_W + MODE_GAP, MODE_Y, MODE_W, MODE_H) == 1) {
        sha_set_mode(1);
        return;
    }
    if (sha_in_rect(mx, my, 46 + (MODE_W + MODE_GAP) * 2, MODE_Y, MODE_W, MODE_H) == 1) {
        sha_set_mode(2);
        return;
    }

    if (sha_in_rect(mx, my, IMG_FILE_X, IMG_Y, IMG_FILE_W, IMG_H) == 1) {
        sha_pick_image_file();
        return;
    }
    if (sha_in_rect(mx, my, IMG_AN_X, IMG_Y, IMG_AN_W, IMG_H) == 1) {
        sha_analyze_image();
        return;
    }
    if (sha_image_ready() == 1) {
        int ci = 0;
        while (ci < COLOR.palette_count) {
            int cx = IMG_X + ci * (IMG_SWATCH + IMG_SWATCH_GAP);
            if (sha_in_rect(mx, my, cx, IMG_PAL_Y, IMG_SWATCH, IMG_SWATCH) == 1) {
                sha_open_color_search(ci);
                return;
            }
            ci = ci + 1;
        }
    }

    if (sha_in_rect(mx, my, SCAN_X, SCAN_Y, SCAN_W, SCAN_H) == 1) {
        if (SCAN_ACTIVE == 0) { sha_start_target(); }
        return;
    }
    if (sha_in_rect(mx, my, STOP_X, SCAN_Y, STOP_W, SCAN_H) == 1) {
        dsk_clear_focus();
        if (SCAN_ACTIVE == 1) {
            SCAN_ACTIVE = 0;
            sha_set_msg("Scan stopped by operator.");
        }
        return;
    }
    if (sha_in_rect(mx, my, CLEAR_X, SCAN_Y, CLEAR_W, SCAN_H) == 1) {
        dsk_clear_focus();
        SCAN_ACTIVE = 0;
        sha_reset_results();
        sha_clear_contact();
        SELECTED = 0 - 1;
        if (TARGET_MODE == 0) {
            sha_set_msg("Results cleared. Ready for a new target.");
        } else {
            sha_set_msg("Contact report cleared. Ready for a new target.");
        }
        return;
    }
    if (TARGET_MODE == 0 && sha_in_rect(mx, my, OPEN_X, OPEN_Y, OPEN_W, OPEN_H) == 1) {
        dsk_clear_focus();
        if (SELECTED >= 0 && R_CHECKED[SELECTED] == 1) {
            string url = sha_url(SELECTED);
            if (len(url) > 0) {
                sha_open_url(url);
                sha_set_msg("Opening selected profile in browser...");
            }
        }
        return;
    }
    if (sha_in_rect(mx, my, IMG_X, IMG_BTN_Y1, IMG_BTN_W, IMG_BTN_H) == 1) {
        sha_open_provider(0);
        return;
    }
    if (sha_in_rect(mx, my, IMG_X + IMG_BTN_W + 10, IMG_BTN_Y1, IMG_BTN_W, IMG_BTN_H) == 1) {
        sha_open_provider(1);
        return;
    }
    if (sha_in_rect(mx, my, IMG_X, IMG_BTN_Y2, IMG_BTN_W, IMG_BTN_H) == 1) {
        sha_open_provider(2);
        return;
    }
    if (sha_in_rect(mx, my, IMG_X + IMG_BTN_W + 10, IMG_BTN_Y2, IMG_BTN_W, IMG_BTN_H) == 1) {
        sha_open_provider(3);
        return;
    }

    if (TARGET_MODE == 0 && mx >= R_X && mx < R_X + R_W && my >= ROW_Y && my < ROW_Y + SITE_COUNT * ROW_H) {
        int i = (my - ROW_Y) / ROW_H;
        if (i >= 0 && i < SITE_COUNT) {
            SELECTED = i;
            dsk_clear_focus();
        }
    }
}

fn sha_draw_header(int sw) -> void {
    gui_fill_gradient_v(0, 0, sw, 92, gui_rgb(15, 23, 37), SHA_BG);
    gui_fill_rect(0, 91, sw, 1, SHA_BORDER);
    gui_fill_rounded_rect(24, 18, 6, 46, 3, SHA_ACCENT);
    sha_text(44, 13, "SHERLOCK", SHA_TEXT, 3);
    sha_text(45, 64, "PUBLIC USERNAME / EMAIL / PHONE OSINT CONSOLE", SHA_MUTED, 1);
    gui_fill_rounded_rect(sw - 280, 20, 132, 24, 12, gui_rgb(23, 37, 43));
    gui_draw_rounded_rect(sw - 280, 20, 132, 24, 12, gui_rgb(47, 99, 89));
    sha_text_center(sw - 280, 24, 132, "OSINT ONLINE", SHA_GREEN, 1);
    sha_text_right(sw - 24, 16, CLOCK_BUF, SHA_TEXT, 2);
    sha_text_right(sw - 24, 50, DATE_BUF, SHA_MUTED, 1);
    sha_text_right(sw - 180, 54, "16 PUBLIC SOURCES", SHA_MUTED, 1);
}

fn sha_draw_stats(int found, int missing, int issues) -> void {
    int x1 = 46;
    int x2 = 165;
    int x3 = 284;
    gui_fill_rounded_rect(x1, STATS_Y, STATS_W, STATS_H, 8, SHA_CARD2);
    gui_draw_rounded_rect(x1, STATS_Y, STATS_W, STATS_H, 8, SHA_BORDER);
    sha_text(x1 + 12, STATS_Y + 9, "FOUND", SHA_MUTED, 1);
    sha_text(x1 + 12, STATS_Y + 24, dsk_itoa(found), SHA_GREEN, 3);

    gui_fill_rounded_rect(x2, STATS_Y, STATS_W, STATS_H, 8, SHA_CARD2);
    gui_draw_rounded_rect(x2, STATS_Y, STATS_W, STATS_H, 8, SHA_BORDER);
    sha_text(x2 + 12, STATS_Y + 9, "MISSING", SHA_MUTED, 1);
    sha_text(x2 + 12, STATS_Y + 24, dsk_itoa(missing), SHA_RED, 3);

    gui_fill_rounded_rect(x3, STATS_Y, STATS_W, STATS_H, 8, SHA_CARD2);
    gui_draw_rounded_rect(x3, STATS_Y, STATS_W, STATS_H, 8, SHA_BORDER);
    sha_text(x3 + 12, STATS_Y + 9, "ISSUES", SHA_MUTED, 1);
    sha_text(x3 + 12, STATS_Y + 24, dsk_itoa(issues), SHA_ORANGE, 3);
}

fn sha_draw_detail() -> void {
    sha_text(46, 424, "SELECTED PROFILE", SHA_MUTED, 1);
    if (SELECTED < 0 || SELECTED >= SITE_COUNT) {
        sha_text(46, 448, "No profile selected", SHA_MUTED, 2);
        sha_text(46, 486, "Choose a row from the matrix to inspect", SHA_MUTED, 1);
        sha_text(46, 506, "its HTTP status, page title and stack.", SHA_MUTED, 1);
        return;
    }

    int kind = R_KIND[SELECTED];
    int kc = sha_kind_color(kind);
    sha_text_clip(46, 444, sha_site_name(SELECTED), SHA_TEXT, 214, 2);
    gui_fill_rounded_rect(280, 448, 112, 22, 11, kc);
    sha_text_center(280, 451, 112, sha_kind_label(kind), SHA_DARK, 1);

    string title = sha_title(SELECTED);
    string stack = sha_stack(SELECTED);
    string evidence = sha_evidence(SELECTED);
    string url = sha_url(SELECTED);
    if (R_CHECKED[SELECTED] == 0) {
        title = "Awaiting probe";
        stack = "Awaiting probe";
        evidence = "Awaiting probe";
        url = "Awaiting probe";
    }
    if (len(title) == 0) { title = "-"; }
    if (len(stack) == 0) { stack = "-"; }
    if (len(evidence) == 0) { evidence = stack; }
    else if (len(stack) > 0) { evidence = str_concat(evidence, str_concat(" / ", stack)); }
    if (len(url) == 0) { url = "-"; }

    int val_x = 122;
    int val_w = 270;
    sha_text(46, 486, "HTTP", SHA_MUTED, 1);
    sha_text_clip(val_x, 486, sha_http_info(SELECTED), SHA_TEXT, val_w, 1);
    sha_text(46, 506, "TITLE", SHA_MUTED, 1);
    sha_text_clip(val_x, 506, title, SHA_TEXT, val_w, 1);
    sha_text(46, 526, "EVIDENCE", SHA_MUTED, 1);
    sha_text_clip(val_x, 526, evidence, SHA_BLUE, val_w, 1);
    sha_text(46, 546, "URL", SHA_MUTED, 1);
    sha_text_clip(val_x, 546, url, SHA_MUTED, val_w, 1);

    int open_enabled = 0;
    if (SELECTED >= 0 && R_CHECKED[SELECTED] == 1 && len(url) > 0) { open_enabled = 1; }
    sha_button(OPEN_X, OPEN_Y, OPEN_W, OPEN_H, "OPEN SELECTED PROFILE", open_enabled, 1);
}

fn sha_draw_left(int found, int missing, int issues) -> void {
    sha_card(L_X, L_Y, L_W, L_H, SHA_ACCENT);
    sha_text(46, 124, "TARGET", SHA_TEXT, 2);
    int us = 0;
    int es = 0;
    int ps = 0;
    if (TARGET_MODE == 0) { us = 1; }
    if (TARGET_MODE == 1) { es = 1; }
    if (TARGET_MODE == 2) { ps = 1; }
    sha_button(46, MODE_Y, MODE_W, MODE_H, "USERNAME", 1, us);
    sha_button(46 + MODE_W + MODE_GAP, MODE_Y, MODE_W, MODE_H, "EMAIL", 1, es);
    sha_button(46 + (MODE_W + MODE_GAP) * 2, MODE_Y, MODE_W, MODE_H, "PHONE", 1, ps);
    sha_button(SCAN_X, SCAN_Y, SCAN_W, SCAN_H, "START SCAN", SCAN_ACTIVE == 0, 1);
    sha_button(STOP_X, SCAN_Y, STOP_W, SCAN_H, "STOP", SCAN_ACTIVE == 1, 2);
    sha_button(CLEAR_X, SCAN_Y, CLEAR_W, SCAN_H, "CLEAR", 1, 0);

    int pct = SCAN_INDEX * 100 / SITE_COUNT;
    sha_progress(PROG_X, PROG_Y, PROG_W, PROG_H, pct);
    if (SCAN_ACTIVE == 1) { sha_build_scanning(); }
    else { sha_set(STATUS_BUF, 160, cast<string>(MSG_BUF)); }
    sha_text_clip(46, 302, cast<string>(STATUS_BUF), SHA_MUTED, 346, 1);

    if (TARGET_MODE == 0) {
        sha_draw_stats(found, missing, issues);
        sha_draw_detail();
    } else {
        sha_text(46, STATS_Y + 4, "CONTACT VERIFICATION", SHA_MUTED, 1);
        if (TARGET_MODE == 1) {
            sha_text(46, STATS_Y + 30, "Email syntax + domain check", SHA_TEXT, 1);
            sha_text(46, STATS_Y + 50, "MX routing via dig", SHA_TEXT, 1);
            sha_text(46, STATS_Y + 70, "Gravatar public profile", SHA_TEXT, 1);
            sha_text(46, STATS_Y + 90, "HIBP breaches (optional key)", SHA_TEXT, 1);
        } else {
            sha_text(46, STATS_Y + 30, "E.164-style normalization", SHA_TEXT, 1);
            sha_text(46, STATS_Y + 50, "Country code lookup", SHA_TEXT, 1);
            sha_text(46, STATS_Y + 70, "Manual SMS draft only", SHA_TEXT, 1);
        }
        sha_text(46, STATS_Y + 132, "No messages are sent automatically.", SHA_GREEN, 1);
        sha_text(46, STATS_Y + 154, "Results open in a verification report.", SHA_MUTED, 1);
    }

    gui_fill_rect(46, 610, 346, 1, SHA_BORDER);
    sha_text(46, 618, "IMAGE PIVOT", SHA_TEXT, 1);
    sha_text_right(392, 618, "COLOR + REVERSE", SHA_MUTED, 1);
    sha_button(IMG_FILE_X, IMG_Y, IMG_FILE_W, IMG_H, "SELECT FILE", 1, 0);
    sha_button(IMG_AN_X, IMG_Y, IMG_AN_W, IMG_H, "ANALYZE", 1, 3);

    if (sha_image_ready() == 1) {
        string info = str_concat(COLOR.classification, " / ");
        info = str_concat(info, str_concat(dsk_itoa(COLOR.text_risk), "% RISK"));
        int ic = SHA_GREEN;
        if (COLOR.text_free == 0) { ic = SHA_ORANGE; }
        if (COLOR.text_risk >= 55) { ic = SHA_RED; }
        sha_text_clip(46, IMG_INFO_Y, info, ic, 346, 1);
        int ci = 0;
        while (ci < COLOR.palette_count && ci < 6) {
            int cx = IMG_X + ci * (IMG_SWATCH + IMG_SWATCH_GAP);
            int cc = gui_rgb(COLOR.pr[ci], COLOR.pg[ci], COLOR.pb[ci]);
            gui_fill_rounded_rect(cx, IMG_PAL_Y, IMG_SWATCH, IMG_SWATCH, 3, cc);
            gui_draw_rounded_rect(cx, IMG_PAL_Y, IMG_SWATCH, IMG_SWATCH, 3, SHA_BORDER);
            ci = ci + 1;
        }
        sha_text(176, IMG_PAL_Y + 4, "CLICK SWATCH = COLOR SEARCH", SHA_MUTED, 1);
    } else {
        sha_text(46, IMG_INFO_Y, "Press ANALYZE to classify text risk", SHA_MUTED, 1);
        sha_text(46, IMG_PAL_Y + 4, "Palette and color search unlock after analysis", SHA_MUTED, 1);
    }

    int reverse_enabled = 0;
    if (sha_image_ready() == 1 && COLOR.text_free == 1) { reverse_enabled = 1; }
    int url_enabled = 0;
    if (reverse_enabled == 1 && sha_is_remote(str_trim(dsk_widget_text(IMAGE_INPUT))) == 1) { url_enabled = 1; }
    sha_button(IMG_X, IMG_BTN_Y1, IMG_BTN_W, IMG_BTN_H, "GOOGLE LENS", url_enabled, 3);
    sha_button(IMG_X + IMG_BTN_W + 10, IMG_BTN_Y1, IMG_BTN_W, IMG_BTN_H, "FIND SITES", reverse_enabled, 1);
    sha_button(IMG_X, IMG_BTN_Y2, IMG_BTN_W, IMG_BTN_H, "BING VISUAL", url_enabled, 3);
    sha_button(IMG_X + IMG_BTN_W + 10, IMG_BTN_Y2, IMG_BTN_W, IMG_BTN_H, "TINEYE", url_enabled, 3);
}

fn sha_draw_row(int i, int hovered) -> void {
    int y = ROW_Y + i * ROW_H;
    int x = R_X + 12;
    int w = R_W - 24;
    int kind = R_KIND[i];
    int bg = SHA_CARD2;
    if (i - (i / 2) * 2 == 1) { bg = gui_rgb(16, 22, 34); }
    if (hovered == 1) { bg = gui_rgb(23, 33, 49); }
    if (SELECTED == i) { bg = gui_rgb(20, 39, 64); }
    gui_fill_rounded_rect(x, y, w, ROW_H - 2, 4, bg);
    if (SELECTED == i) {
        gui_draw_rounded_rect(x, y, w, ROW_H - 2, 4, SHA_ACCENT);
    } else if (hovered == 1) {
        gui_draw_rounded_rect(x, y, w, ROW_H - 2, 4, SHA_BORDER);
    }

    int ty = y + 6;
    sha_text_clip(454, ty, sha_site_name(i), SHA_TEXT, 142, 1);

    int kc = sha_kind_color(kind);
    int pill_bg = SHA_TRACK;
    int pill_fg = SHA_MUTED;
    if (kind != 0) { pill_bg = kc; pill_fg = SHA_DARK; }
    gui_fill_rounded_rect(610, y + 5, 92, 20, 10, pill_bg);
    sha_text_center(610, y + 7, 92, sha_kind_label(kind), pill_fg, 1);

    if (R_CHECKED[i] == 1) {
        sha_text(720, ty, dsk_itoa(R_HTTP[i]), kc, 1);
        int di = sha_append(CONF_BUF, 8, 0, dsk_itoa(R_CONF[i]));
        di = sha_append(CONF_BUF, 8, di, "%");
        *(CONF_BUF + di) = 0;
        sha_text(768, ty, cast<string>(CONF_BUF), sha_conf_color(R_CONF[i]), 1);
    } else {
        sha_text(720, ty, "-", SHA_MUTED, 1);
        sha_text(768, ty, "-", SHA_MUTED, 1);
    }

    string title = sha_title(i);
    if (R_CHECKED[i] == 0) {
        title = "Awaiting probe";
    }
    if (len(title) == 0) { title = "-"; }
    sha_text_clip(822, ty, title, SHA_TEXT, 388, 1);
}

fn sha_info_row(int x, int y, int w, string label, string desc) -> void {
    gui_fill_rounded_rect(x, y, w, 52, 6, SHA_CARD2);
    gui_draw_rounded_rect(x, y, w, 52, 6, SHA_BORDER);
    sha_text(x + 16, y + 9, label, SHA_TEXT, 1);
    sha_text_clip(x + 16, y + 29, desc, SHA_MUTED, w - 32, 1);
}

fn sha_draw_right(int found, int missing, int issues) -> void {
    sha_card(R_X, R_Y, R_W, R_H, SHA_PURPLE);
    if (TARGET_MODE != 0) {
        if (TARGET_MODE == 1) {
            sha_text(454, 124, "EMAIL VERIFICATION", SHA_TEXT, 2);
            sha_text(455, 160, "Safe checks using DNS and public profile APIs", SHA_MUTED, 1);
            sha_text_right(1232, 160, "NO INTRUSION", SHA_GREEN, 1);
            sha_info_row(454, 200, 778, "SYNTAX + DOMAIN", "Validates the address format and rejects malformed domains");
            sha_info_row(454, 264, 778, "MAIL ROUTING", "Reads public MX records with dig; no mail is sent");
            sha_info_row(454, 328, 778, "GRAVATAR PROFILE", "Checks for a public Gravatar profile linked to the email hash");
            sha_info_row(454, 392, 778, "HIBP BREACH CHECK", "Optional public breach lookup when HIBP_API_KEY is set");
            sha_text(454, 472, "HIBP requires a personal API key in the environment.", SHA_MUTED, 1);
            sha_text(454, 496, "Draft links only open your mail client. Nothing is sent automatically.", SHA_GREEN, 1);
        } else {
            sha_text(454, 124, "PHONE VERIFICATION", SHA_TEXT, 2);
            sha_text(455, 160, "Format validation and country metadata without carrier intrusion", SHA_MUTED, 1);
            sha_text_right(1232, 160, "NO INTRUSION", SHA_GREEN, 1);
            sha_info_row(454, 200, 778, "NUMBER FORMAT", "Normalizes digits and validates 8 to 15 digit length");
            sha_info_row(454, 264, 778, "COUNTRY CODE", "Identifies the country from the leading + prefix");
            sha_info_row(454, 328, 778, "SMS DRAFT", "Opens a manual messaging draft; nothing is sent automatically");
            sha_text(454, 408, "Carrier ownership and live location are not queried.", SHA_MUTED, 1);
            sha_text(454, 432, "No automated calls, SMS or messaging are performed.", SHA_GREEN, 1);
        }
        gui_fill_rect(442, 728, R_W - 24, 1, SHA_BORDER);
        sha_text(454, 744, "Only check contact data you own or have explicit permission to assess.", SHA_MUTED, 1);
        sha_text_right(1232, 744, "sherlock.mg / ethical OSINT", SHA_MUTED, 1);
        return;
    }
    sha_text(454, 124, "PUBLIC PROFILE MATRIX", SHA_TEXT, 2);
    sha_text(455, 160, "Live HTTP probes, redirects, titles and server fingerprints", SHA_MUTED, 1);
    sha_text_right(1232, 160, "SOCIAL / DEV / CREATOR", SHA_MUTED, 1);

    sha_text(454, 190, "SITE", SHA_MUTED, 1);
    sha_text(610, 190, "STATUS", SHA_MUTED, 1);
    sha_text(720, 190, "HTTP", SHA_MUTED, 1);
    sha_text(768, 190, "CONF", SHA_MUTED, 1);
    sha_text(822, 190, "RESPONSE TITLE", SHA_MUTED, 1);
    gui_fill_rect(442, 208, R_W - 24, 1, SHA_BORDER);

    int i = 0;
    int hovered = 0 - 1;
    int mx = gui_mouse_x();
    int my = gui_mouse_y();
    if (mx >= R_X && mx < R_X + R_W && my >= ROW_Y && my < ROW_Y + SITE_COUNT * ROW_H) {
        hovered = (my - ROW_Y) / ROW_H;
    }
    while (i < SITE_COUNT) {
        sha_draw_row(i, hovered);
        i = i + 1;
    }

    gui_fill_rect(442, 728, R_W - 24, 1, SHA_BORDER);
    sha_text(454, 744, "Only investigate accounts you own or have explicit permission to assess.", SHA_MUTED, 1);
    sha_text_right(1232, 744, "sherlock.mg / ethical OSINT", SHA_MUTED, 1);
}

fn sha_draw_sites_modal() -> void {
    int sw = dsk_screen_w();
    int sh = dsk_screen_h();
    int px = (sw - SITE_MODAL_W) / 2;
    int py = (sh - SITE_MODAL_H) / 2;
    gui_fill_rect(0, 0, sw, sh, SHA_DARK);
    sha_card(px, py, SITE_MODAL_W, SITE_MODAL_H, SHA_ACCENT);
    sha_text(px + 32, py + 22, "SITES HOSTING THIS IMAGE", SHA_TEXT, 2);
    sha_text(px + 32, py + 56, "Yandex reverse image / exact and similar host pages", SHA_MUTED, 1);

    char* count = alloc<char>(128);
    int di = 0;
    di = sha_append(count, 128, 0, dsk_itoa(IMG_SITE_TOTAL));
    di = sha_append(count, 128, di, " DOMAIN");
    if (IMG_SITE_TOTAL != 1) { di = sha_append(count, 128, di, "S"); }
    di = sha_append(count, 128, di, " FOUND");
    *(count + di) = 0;
    sha_text_right(px + SITE_MODAL_W - 32, py + 32, cast<string>(count), SHA_GREEN, 1);
    free(count);

    gui_fill_rect(px + 32, py + 88, SITE_MODAL_W - 64, 1, SHA_BORDER);
    if (IMG_SITE_COUNT == 0) {
        sha_text(px + 32, py + 118, "No hosting domains were returned for this image.", SHA_TEXT, 1);
        sha_text(px + 32, py + 142, "Try Google Lens or Bing Visual Search for more matches.", SHA_MUTED, 1);
    } else {
        int i = 0;
        while (i < IMG_SITE_COUNT) {
            int y = py + 104 + i * SITE_MODAL_ROW_H;
            int bg = SHA_CARD2;
            if (i - (i / 2) * 2 == 1) { bg = gui_rgb(16, 22, 34); }
            gui_fill_rounded_rect(px + 32, y, SITE_MODAL_W - 64, 30, 4, bg);
            sha_text(px + 44, y + 7, dsk_itoa(i + 1), SHA_MUTED, 1);
            sha_text_clip(px + 74, y + 7, sha_site_domain(i), SHA_TEXT, SITE_MODAL_W - 120, 1);
            i = i + 1;
        }
    }

    if (IMG_SITE_TOTAL > IMG_SITE_COUNT) {
        char* note = alloc<char>(128);
        int ni = 0;
        ni = sha_append(note, 128, 0, "Showing first ");
        ni = sha_append(note, 128, ni, dsk_itoa(IMG_SITE_COUNT));
        ni = sha_append(note, 128, ni, " of ");
        ni = sha_append(note, 128, ni, dsk_itoa(IMG_SITE_TOTAL));
        ni = sha_append(note, 128, ni, ". Open Yandex for the full list.");
        *(note + ni) = 0;
        sha_text(px + 32, py + 460, cast<string>(note), SHA_MUTED, 1);
        free(note);
    } else if (IMG_SITE_COUNT > 0) {
        sha_text(px + 32, py + 460, "All returned hosting domains are listed above.", SHA_MUTED, 1);
    }

    sha_button(px + 32, py + 500, 180, 34, "OPEN YANDEX", 1, 1);
    sha_button(px + SITE_MODAL_W - 160, py + 500, 128, 34, "CLOSE", 1, 0);
}

fn sha_contact_row(int px, int py, int idx, string label, string value, int color) -> void {
    int y = py + 104 + idx * CONTACT_ROW_H;
    sha_text(px + 32, y, label, SHA_MUTED, 1);
    sha_text_clip(px + 180, y, value, color, CONTACT_MODAL_W - 212, 1);
    gui_fill_rect(px + 32, y + 32, CONTACT_MODAL_W - 64, 1, SHA_BORDER);
}

fn sha_draw_contact_modal() -> void {
    int sw = dsk_screen_w();
    int sh = dsk_screen_h();
    int px = (sw - CONTACT_MODAL_W) / 2;
    int py = (sh - CONTACT_MODAL_H) / 2;
    gui_fill_rect(0, 0, sw, sh, SHA_DARK);
    if (CONTACT_MODE == 1) {
        sha_card(px, py, CONTACT_MODAL_W, CONTACT_MODAL_H, SHA_GREEN);
        sha_text(px + 32, py + 22, "EMAIL VERIFICATION REPORT", SHA_TEXT, 2);
        sha_text(px + 32, py + 56, "Syntax, public mail routing and opt-in breach metadata", SHA_MUTED, 1);
    } else {
        sha_card(px, py, CONTACT_MODAL_W, CONTACT_MODAL_H, SHA_BLUE);
        sha_text(px + 32, py + 22, "PHONE VERIFICATION REPORT", SHA_TEXT, 2);
        sha_text(px + 32, py + 56, "Format normalization and country metadata", SHA_MUTED, 1);
    }
    sha_text_right(px + CONTACT_MODAL_W - 32, py + 32, "SAFE MODE", SHA_GREEN, 1);
    gui_fill_rect(px + 32, py + 88, CONTACT_MODAL_W - 64, 1, SHA_BORDER);

    if (CONTACT_MODE == 1) {
        int syntax_color = SHA_RED;
        string syntax = "INVALID";
        if (CONTACT_OK == 1) {
            syntax_color = SHA_GREEN;
            syntax = "VALID";
        }
        int mx_color = SHA_TEXT;
        if (str_contains(cast<string>(CONTACT_MX), "No MX") == 1) { mx_color = SHA_ORANGE; }
        if (str_contains(cast<string>(CONTACT_MX), "not installed") == 1) { mx_color = SHA_ORANGE; }
        int grav_color = SHA_MUTED;
        if (CONTACT_GRAV_OK == 1) { grav_color = SHA_GREEN; }
        int hibp_color = SHA_MUTED;
        if (CONTACT_HIBP_STATE == 1) { hibp_color = SHA_GREEN; }
        if (CONTACT_HIBP_STATE == 2) { hibp_color = SHA_ORANGE; }
        if (CONTACT_HIBP_STATE == 3) { hibp_color = SHA_RED; }
        sha_contact_row(px, py, 0, "INPUT", cast<string>(CONTACT_INPUT), SHA_TEXT);
        sha_contact_row(px, py, 1, "SYNTAX", syntax, syntax_color);
        sha_contact_row(px, py, 2, "DOMAIN", cast<string>(CONTACT_DOMAIN), SHA_TEXT);
        sha_contact_row(px, py, 3, "MX ROUTING", cast<string>(CONTACT_MX), mx_color);
        sha_contact_row(px, py, 4, "GRAVATAR", cast<string>(CONTACT_GRAV), grav_color);
        sha_contact_row(px, py, 5, "HIBP BREACHES", cast<string>(CONTACT_HIBP), hibp_color);
        int status_color = SHA_RED;
        if (CONTACT_OK == 1) { status_color = SHA_GREEN; }
        sha_text_clip(px + 32, py + 390, cast<string>(CONTACT_STATUS), status_color, CONTACT_MODAL_W - 64, 1);
        sha_text(px + 32, py + 414, "No message is sent automatically. Draft opens your mail client.", SHA_MUTED, 1);
        sha_button(px + 32, py + 460, 180, 34, "OPEN MAIL DRAFT", CONTACT_OK, 1);
        int grav_enabled = 0;
        if (len(cast<string>(CONTACT_GRAV_URL)) > 0) { grav_enabled = 1; }
        sha_button(px + 222, py + 460, 160, 34, "OPEN GRAVATAR", grav_enabled, 3);
    } else {
        sha_contact_row(px, py, 0, "INPUT", cast<string>(CONTACT_INPUT), SHA_TEXT);
        sha_contact_row(px, py, 1, "NORMALIZED", cast<string>(CONTACT_NORM), SHA_TEXT);
        sha_contact_row(px, py, 2, "COUNTRY", cast<string>(CONTACT_COUNTRY), SHA_TEXT);
        sha_contact_row(px, py, 3, "DIGITS", dsk_itoa(CONTACT_DIGITS), SHA_TEXT);
        int status_color = SHA_RED;
        if (CONTACT_OK == 1) { status_color = SHA_GREEN; }
        sha_text_clip(px + 32, py + 300, cast<string>(CONTACT_STATUS), status_color, CONTACT_MODAL_W - 64, 1);
        sha_text(px + 32, py + 324, "No SMS is sent automatically. Draft opens your messaging app.", SHA_MUTED, 1);
        sha_button(px + 32, py + 460, 180, 34, "OPEN SMS DRAFT", CONTACT_OK, 1);
    }

    sha_button(px + CONTACT_MODAL_W - 160, py + 460, 128, 34, "CLOSE", 1, 0);
}

fn sha_draw() -> void {
    int sw = dsk_screen_w();
    int sh = dsk_screen_h();
    sha_set_palette();
    sha_build_clock();
    gui_fill_rect(0, 0, sw, sh, SHA_BG);
    sha_draw_header(sw);

    int found = sha_count_kind(1);
    int missing = sha_count_kind(2);
    int issues = sha_count_issues();
    sha_draw_left(found, missing, issues);
    sha_draw_right(found, missing, issues);
}

fn main() -> int {
    int win = dsk_init_app(1280, 800, "Sherlock OSINT GUI");
    if (win < 0) { return 1; }

    dsk_set_taskbar(0);
    dsk_theme_dark();

    SITE_NAMES = null;
    SITE_TMPL = null;
    R_TITLE = null;
    R_STACK = null;
    R_URL = null;
    R_EVIDENCE = null;
    R_KIND = null;
    R_HTTP = null;
    R_REDIR = null;
    R_CHECKED = null;
    R_CONF = null;

    SCAN_USER = alloc<char>(128);
    STATUS_BUF = alloc<char>(160);
    MSG_BUF = alloc<char>(192);
    HTTP_BUF = alloc<char>(96);
    CONF_BUF = alloc<char>(8);
    COLOR_URL = alloc<char>(512);
    COLOR_TMP = alloc<char>(128);
    COLOR_CONV = alloc<char>(128);
    COLOR_LOCAL = alloc<char>(512);
    COLOR_UPLOAD = alloc<char>(128);
    YANDEX_JSON = alloc<char>(128);
    YANDEX_CBIR = alloc<char>(256);
    IMG_SITE_DOMAINS = alloc<char>(IMG_SITE_MAX * IMG_SITE_CAP);
    IMG_SITE_SEARCH_URL = alloc<char>(512);
    CONTACT_INPUT = alloc<char>(320);
    CONTACT_NORM = alloc<char>(320);
    CONTACT_DOMAIN = alloc<char>(256);
    CONTACT_MX = alloc<char>(768);
    CONTACT_GRAV = alloc<char>(320);
    CONTACT_GRAV_URL = alloc<char>(512);
    CONTACT_HIBP = alloc<char>(320);
    CONTACT_COUNTRY = alloc<char>(64);
    CONTACT_STATUS = alloc<char>(192);
    sha_set(COLOR_TMP, 128, "/tmp/sherlock_colorlens_input.bin");
    sha_set(COLOR_CONV, 128, "/tmp/sherlock_colorlens_conv.png");
    sha_set(COLOR_LOCAL, 512, "");
    sha_set(COLOR_UPLOAD, 128, "/tmp/sherlock_reverse_upload.png");
    sha_set(YANDEX_JSON, 128, "/tmp/sherlock_yandex_upload.json");
    sha_set(YANDEX_CBIR, 256, "");
    sha_set(IMG_SITE_DOMAINS, IMG_SITE_MAX * IMG_SITE_CAP, "");
    sha_set(IMG_SITE_SEARCH_URL, 512, "");
    sha_set(CONTACT_INPUT, 320, "");
    sha_set(CONTACT_NORM, 320, "");
    sha_set(CONTACT_DOMAIN, 256, "");
    sha_set(CONTACT_MX, 768, "");
    sha_set(CONTACT_GRAV, 320, "");
    sha_set(CONTACT_GRAV_URL, 512, "");
    sha_set(CONTACT_HIBP, 320, "");
    sha_set(CONTACT_COUNTRY, 64, "");
    sha_set(CONTACT_STATUS, 192, "");
    IMG_SITE_COUNT = 0;
    IMG_SITE_TOTAL = 0;
    IMG_SITE_VISIBLE = 0;
    TARGET_MODE = 0;
    CONTACT_VISIBLE = 0;
    CONTACT_MODE = 0;
    CONTACT_OK = 0;
    CONTACT_DIGITS = 0;
    CONTACT_GRAV_OK = 0;
    CONTACT_HIBP_STATE = 0;
    CONTACT_HIBP_COUNT = 0;
    COLOR = alloc<ColorProfile>(1);
    COLOR_READY = 0;
    COLOR.palette_count = 0;
    COLOR.text_free = 0;
    COLOR.classification = "NO IMAGE";
    CLOCK_BUF = alloc<char>(16);
    DATE_BUF = alloc<char>(16);
    ENV_BUF = alloc<char>(8192);
    ENV_PTRS = alloc<char*>(256);
    ENV_PTRS[0] = null;
    ENV_COUNT = 0;

    sha_init_sites();
    sha_reset_results();
    sha_load_env();
    sha_set_msg("Ready. Choose USERNAME, EMAIL or PHONE.");
    SELECTED = 0 - 1;

    USER_INPUT = dsk_input(win, USER_X, USER_Y, USER_W, USER_H, "torvalds");
    IMAGE_INPUT = dsk_input(win, IMG_X, IMG_Y, IMG_W, IMG_H, "https://picsum.photos/seed/sherlock/512/512");
    dsk_focus_widget(USER_INPUT);

    while (dsk_running() == 1) {
        int clicked = dsk_update();
        sha_handle_events(clicked);

        sha_draw();
        dsk_draw_input(USER_INPUT);
        dsk_draw_input(IMAGE_INPUT);
        if (CONTACT_VISIBLE == 1) {
            sha_draw_contact_modal();
        } else if (IMG_SITE_VISIBLE == 1) {
            sha_draw_sites_modal();
        }
        if (gui_is_x11() == 0) { dsk_draw_cursor(gui_mouse_x(), gui_mouse_y()); }
        gui_present();

        if (SCAN_ACTIVE == 1) {
            sha_check_site(SCAN_INDEX);
            SCAN_INDEX = SCAN_INDEX + 1;
            if (SCAN_INDEX >= SITE_COUNT) {
                sha_finish_scan();
            }
            sleep_ms(60);
        } else {
            sleep_ms(45);
        }
    }

    dsk_shutdown();
    return 0;
}
