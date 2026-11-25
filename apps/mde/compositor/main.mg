// MDE Compositor - Magnetar Desktop Environment
// Dev mode: X11 window via lib/gui.mg. Target: DRM/KMS + evdev.
// IPC: Unix domain socket, line-delimited JSON (MDE IPC v1).
// Build: ./magc mde/compositor/main.mg -o build/mde-compositor

use "gui.mg";
use "lib/ipc.mg";
use "lib/mde_ipc.mg";
use "lib/json.mg";

extern fn sleep_ms(int ms) -> void;
extern fn get_timestamp() -> int;
extern fn os_get_env(string key) -> string;
extern fn os_get_platform() -> string;
extern fn sys_poll(char* fds, int nfds, int timeout) -> int;
extern fn sys_unlink(string path) -> int;
extern fn sys_mkdir(string path, int mode) -> int;
extern fn print_str(string s) -> void;

static char* FILE_BUF;
static char* FMT_BUF;
static char* DATE_BUF;
static char* IPC_BUF;
static int IPC_SFD = 0;
static int IPC_CFD = 0; // initialized to -1 in main
static int MDE_QUIT = 0;
static int WIN_ABOUT = 0;
static int WIN_SYS = 0;
static int WIN_LAUNCH = 0;
static int W_MEM_BAR = 0;
static int W_MEM_LBL = 0;
static int W_SWAP_BAR = 0;
static int W_SWAP_LBL = 0;
static int W_UP_LBL = 0;
static int W_DATE_LBL = 0;
static int W_LAUNCH_MSG = 0;
static int BTN_HIDE_ABOUT = 0;
static int BTN_QUIT = 0;
static int BTN_FILES = 0;
static int BTN_SETTINGS = 0;
static int BTN_TERM = 0;
static int BTN_ABOUT = 0;

fn read_file(string path, char* buf, int cap) -> int {
    int fd = sys_open(path, 0, 0);
    if (fd < 0) { *(buf + 0) = 0; return 0; }
    int n = sys_read(fd, buf, cap - 1);
    sys_close(fd);
    if (n < 0) { n = 0; }
    *(buf + n) = 0;
    return n;
}

fn find_key(char* buf, int len, string key) -> int {
    char* kp = cast<char*>(key);
    int kl = 0;
    while (*(kp + kl) != 0) { kl = kl + 1; }
    int i = 0;
    while (i + kl <= len) {
        int j = 0;
        int ok = 1;
        while (j < kl) {
            if (_byte_val(*(buf + i + j)) != _byte_val(*(kp + j))) { ok = 0; }
            j = j + 1;
        }
        if (ok == 1) { return i; }
        i = i + 1;
    }
    return 0 - 1;
}

fn parse_num(char* buf, int start, int len) -> int {
    int i = start;
    while (i < len) {
        int c = _byte_val(*(buf + i));
        if (c >= 48 && c <= 57) { break; }
        i = i + 1;
    }
    int v = 0;
    while (i < len) {
        int c = _byte_val(*(buf + i));
        if (c < 48 || c > 57) { break; }
        v = v * 10 + (c - 48);
        i = i + 1;
    }
    return v;
}

fn proc_value(string path, string key) -> int {
    int n = read_file(path, FILE_BUF, 4096);
    int pos = find_key(FILE_BUF, n, key);
    if (pos < 0) { return 0; }
    return parse_num(FILE_BUF, pos, n);
}

fn copy_to(char* dst, int di, string src) -> int {
    char* p = cast<char*>(src);
    int j = 0;
    while (*(p + j) != 0) { *(dst + di) = *(p + j); di = di + 1; j = j + 1; }
    return di;
}

fn two_digits(int v) -> string { return dsk_itoa_pad(v, 2); }

fn fmt_time(int ts) -> string {
    int day = ts / 86400;
    int secs = ts - day * 86400;
    int h = secs / 3600;
    int m = (secs - h * 3600) / 60;
    int s = secs - h * 3600 - m * 60;
    int i = 0;
    i = copy_to(FMT_BUF, i, two_digits(h)); *(FMT_BUF + i) = 58; i = i + 1;
    i = copy_to(FMT_BUF, i, two_digits(m)); *(FMT_BUF + i) = 58; i = i + 1;
    i = copy_to(FMT_BUF, i, two_digits(s)); *(FMT_BUF + i) = 0;
    return cast<string>(FMT_BUF);
}

fn days_to_date(int z) -> string {
    int zz = z + 719468;
    int era = zz / 146097;
    int doe = zz - era * 146097;
    int yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    int y = yoe + era * 400;
    int doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    int mp = (5 * doy + 2) / 153;
    int d = doy - (153 * mp + 2) / 5 + 1;
    int m = mp + 3;
    if (mp >= 10) { m = mp - 9; }
    if (m <= 2) { y = y + 1; }
    int i = 0;
    i = copy_to(DATE_BUF, i, dsk_itoa(y)); *(DATE_BUF + i) = 45; i = i + 1;
    i = copy_to(DATE_BUF, i, dsk_itoa_pad(m, 2)); *(DATE_BUF + i) = 45; i = i + 1;
    i = copy_to(DATE_BUF, i, dsk_itoa_pad(d, 2)); *(DATE_BUF + i) = 0;
    return cast<string>(DATE_BUF);
}

fn draw_topbar(string user, string platform) -> void {
    int w = dsk_screen_w();
    gui_fill_gradient_h(0, 0, w, 34, gui_rgb(18, 24, 38), gui_rgb(30, 44, 70));
    gui_fill_rect(0, 34, w, 1, gui_rgb(70, 90, 130));
    gui_draw_text_fg(14, 9, "MDE - Magnetar Desktop Environment", gui_rgb(230, 238, 255), 255);
    gui_draw_text_fg(w - 210, 9, fmt_time(get_timestamp()), gui_rgb(210, 225, 255), 255);
    gui_draw_text_fg(w - 430, 9, platform, gui_rgb(160, 190, 220), 255);
    gui_draw_text_fg(w - 560, 9, user, gui_rgb(160, 190, 220), 255);
}

fn ipc_setup() -> void {
    string p = "/tmp/mde-compositor.sock";
    sys_mkdir("/tmp", 493);
    IPC_SFD = ipc_server_create(p);
    if (IPC_SFD >= 0) {
        ipc_set_nonblock(IPC_SFD);
        print_str("[mde-compositor] ipc listening: "); print_str(p); print_str("\n");
    } else {
        print_str("[mde-compositor] ipc listen failed\n");
    }
}

fn ipc_handle_line(string line) -> void {
    int id = json_get_int(line, "id", 0);
    string method = json_get_string(line, "method", "");
    if (_str_len(method) == 0) {
        ipc_send_line(IPC_CFD, mde_res_err(id, "bad_request", "missing method"));
        return;
    }
    if (str_equals(method, "hello")) {
        ipc_send_line(IPC_CFD, mde_res_ok(id, "{\"version\":1,\"session\":\"mde\"}"));
        return;
    }
    if (str_equals(method, "ping")) {
        ipc_send_line(IPC_CFD, mde_res_ok(id, "{\"pong\":true}"));
        return;
    }
    if (str_equals(method, "session.quit")) {
        MDE_QUIT = 1;
        ipc_send_line(IPC_CFD, mde_res_ok(id, "{\"quitting\":true}"));
        return;
    }
    if (str_equals(method, "window.show_launcher")) {
        dsk_window_show(WIN_LAUNCH); dsk_focus_window(WIN_LAUNCH);
        ipc_send_line(IPC_CFD, mde_res_ok(id, "{\"shown\":true}"));
        return;
    }
    if (str_equals(method, "window.show_about")) {
        dsk_window_show(WIN_ABOUT); dsk_focus_window(WIN_ABOUT);
        ipc_send_line(IPC_CFD, mde_res_ok(id, "{\"shown\":true}"));
        return;
    }
    ipc_send_line(IPC_CFD, mde_res_err(id, "not_found", method));
}

fn ipc_poll() -> void {
    if (IPC_SFD < 0) { return; }
    if (IPC_CFD < 0) {
        int cfd = ipc_server_accept(IPC_SFD);
        if (cfd >= 0) {
            IPC_CFD = cfd;
            ipc_set_nonblock(IPC_CFD);
            print_str("[mde-compositor] ipc client connected\n");
        } else {
        }
    }
    if (IPC_CFD >= 0) {
        int n = ipc_recv_line(IPC_CFD, IPC_BUF, 4096);
        if (n > 0) {
            ipc_handle_line(cast<string>(IPC_BUF));
        } else if (n == 0) {
            print_str("[mde-compositor] ipc client disconnected\n");
            ipc_close(IPC_CFD);
            IPC_CFD = 0 - 1;
        } else {
            // EAGAIN/no data for nonblock - ignore; recv returns -1
        }
    }
}

fn ui_init(string user, string platform) -> void {
    dsk_set_theme(1);
    WIN_ABOUT = dsk_add_window("Welcome to MDE", 40, 60, 520, 320);
    dsk_add_widget(WIN_ABOUT, WT_LABEL, 24, 42, 460, 24, "Magnetar Desktop Environment", 0, 0, 0);
    dsk_add_widget(WIN_ABOUT, WT_SEPARATOR, 24, 72, 470, 2, "", 0, 0, 0);
    dsk_add_widget(WIN_ABOUT, WT_LABEL, 24, 92, 120, 20, "User:", 0, 0, 0);
    dsk_add_widget(WIN_ABOUT, WT_TEXTBOX, 150, 88, 300, 28, user, 0, 0, 0);
    dsk_add_widget(WIN_ABOUT, WT_LABEL, 24, 128, 120, 20, "Platform:", 0, 0, 0);
    dsk_add_widget(WIN_ABOUT, WT_TEXTBOX, 150, 124, 300, 28, platform, 0, 0, 0);
    dsk_add_widget(WIN_ABOUT, WT_LABEL, 24, 164, 120, 20, "Mode:", 0, 0, 0);
    dsk_add_widget(WIN_ABOUT, WT_TEXTBOX, 150, 160, 300, 28, "dev-x11 (DRM target)", 0, 0, 0);
    BTN_HIDE_ABOUT = dsk_add_widget(WIN_ABOUT, WT_BUTTON, 150, 210, 120, 34, "Hide", 0, 0, 0);
    BTN_QUIT = dsk_add_widget(WIN_ABOUT, WT_BUTTON, 290, 210, 120, 34, "Logout", 0, 0, 0);

    WIN_SYS = dsk_add_window("System Monitor", 590, 60, 420, 320);
    dsk_add_widget(WIN_SYS, WT_LABEL, 24, 46, 160, 18, "RAM usage", 0, 0, 0);
    W_MEM_BAR = dsk_add_widget(WIN_SYS, WT_PROGRESS, 24, 68, 360, 16, "", 0, 0, 100);
    W_MEM_LBL = dsk_add_widget(WIN_SYS, WT_LABEL, 24, 92, 360, 18, "", 0, 0, 0);
    dsk_add_widget(WIN_SYS, WT_LABEL, 24, 124, 160, 18, "Swap usage", 0, 0, 0);
    W_SWAP_BAR = dsk_add_widget(WIN_SYS, WT_PROGRESS, 24, 146, 360, 16, "", 0, 0, 100);
    W_SWAP_LBL = dsk_add_widget(WIN_SYS, WT_LABEL, 24, 170, 360, 18, "", 0, 0, 0);
    W_UP_LBL = dsk_add_widget(WIN_SYS, WT_LABEL, 24, 206, 360, 18, "", 0, 0, 0);
    W_DATE_LBL = dsk_add_widget(WIN_SYS, WT_LABEL, 24, 232, 360, 18, "", 0, 0, 0);

    WIN_LAUNCH = dsk_add_window("Launcher", 220, 170, 460, 300);
    dsk_add_widget(WIN_LAUNCH, WT_LABEL, 24, 42, 400, 20, "Applications", 0, 0, 0);
    dsk_add_widget(WIN_LAUNCH, WT_SEPARATOR, 24, 70, 410, 2, "", 0, 0, 0);
    BTN_FILES = dsk_add_widget(WIN_LAUNCH, WT_BUTTON, 24, 92, 190, 38, "Files", 0, 0, 0);
    BTN_SETTINGS = dsk_add_widget(WIN_LAUNCH, WT_BUTTON, 234, 92, 190, 38, "Settings", 0, 0, 0);
    BTN_TERM = dsk_add_widget(WIN_LAUNCH, WT_BUTTON, 24, 142, 190, 38, "Terminal", 0, 0, 0);
    BTN_ABOUT = dsk_add_widget(WIN_LAUNCH, WT_BUTTON, 234, 142, 190, 38, "About MDE", 0, 0, 0);
    W_LAUNCH_MSG = dsk_add_widget(WIN_LAUNCH, WT_LABEL, 24, 210, 410, 20, "IPC: /tmp/mde-compositor.sock", 0, 0, 0);
}

fn ui_update() -> void {
    int ts = get_timestamp();
    dsk_widget_set_label(W_DATE_LBL, days_to_date(ts / 86400));
    int total = proc_value("/proc/meminfo", "MemTotal:");
    int avail = proc_value("/proc/meminfo", "MemAvailable:");
    int pct = 0; if (total > 0) { pct = (total - avail) * 100 / total; }
    dsk_widget_set(W_MEM_BAR, pct);
    dsk_widget_set_label(W_MEM_LBL, dsk_itoa(pct));
    int st = proc_value("/proc/meminfo", "SwapTotal:");
    int sf = proc_value("/proc/meminfo", "SwapFree:");
    int spct = 0; if (st > 0) { spct = (st - sf) * 100 / st; }
    dsk_widget_set(W_SWAP_BAR, spct);
    dsk_widget_set_label(W_SWAP_LBL, dsk_itoa(spct));
    int un = read_file("/proc/uptime", FILE_BUF, 128);
    dsk_widget_set_label(W_UP_LBL, dsk_itoa(parse_num(FILE_BUF, 0, un)));
}

fn ui_handle_click(int clicked) -> void {
    if (clicked < 0) { return; }
    if (clicked == BTN_HIDE_ABOUT) { dsk_toggle_window(WIN_ABOUT); }
    if (clicked == BTN_ABOUT) { dsk_window_show(WIN_ABOUT); dsk_focus_window(WIN_ABOUT); }
    if (clicked == BTN_QUIT) { MDE_QUIT = 1; }
    if (clicked == BTN_FILES) { dsk_widget_set_label(W_LAUNCH_MSG, "Files: planned mde/apps/files"); }
    if (clicked == BTN_SETTINGS) { dsk_widget_set_label(W_LAUNCH_MSG, "Settings: planned mde/apps/settings"); }
    if (clicked == BTN_TERM) { dsk_widget_set_label(W_LAUNCH_MSG, "Terminal: planned mde/apps/terminal"); }
}

fn main() -> int {
    IPC_SFD = 0 - 1;
    IPC_CFD = 0 - 1;
    WIN_ABOUT = 0 - 1; WIN_SYS = 0 - 1; WIN_LAUNCH = 0 - 1;
    W_MEM_BAR = 0 - 1; W_MEM_LBL = 0 - 1; W_SWAP_BAR = 0 - 1; W_SWAP_LBL = 0 - 1;
    W_UP_LBL = 0 - 1; W_DATE_LBL = 0 - 1; W_LAUNCH_MSG = 0 - 1;
    BTN_HIDE_ABOUT = 0 - 1; BTN_QUIT = 0 - 1; BTN_FILES = 0 - 1; BTN_SETTINGS = 0 - 1; BTN_TERM = 0 - 1; BTN_ABOUT = 0 - 1;
    FILE_BUF = alloc<char>(4096);
    FMT_BUF = alloc<char>(64);
    DATE_BUF = alloc<char>(32);
    IPC_BUF = alloc<char>(4096);

    int err = dsk_init();
    if (err != 0) { return err; }
    string user = os_get_env("USER");
    if (_str_len(user) == 0) { user = "user"; }
    string platform = os_get_platform();

    ui_init(user, platform);
    ipc_setup();

    int dbg_tick = 0;
    while (dsk_running() == 1 && MDE_QUIT == 0) {
        ui_update();
        int clicked = dsk_update();
        draw_topbar(user, platform);
        ui_handle_click(clicked);
        if (gui_close_requested() == 1) { MDE_QUIT = 1; }
        ipc_poll();
        dsk_draw_cursor(gui_mouse_x(), gui_mouse_y());
        gui_present();
        sleep_ms(16);
        dbg_tick = dbg_tick + 1;
    }

    if (IPC_CFD >= 0) { ipc_close(IPC_CFD); }
    if (IPC_SFD >= 0) { ipc_close(IPC_SFD); sys_unlink("/tmp/mde-compositor.sock"); }
    dsk_shutdown();
    return 0;
}
