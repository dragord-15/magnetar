extern fn get_timestamp() -> int;
// gui_desktop.mg — A full desktop shell running multiple apps in windows
// Apps: Calculator, Clock, System Monitor, About. Click the taskbar to focus.
use "gui.mg";

extern fn sleep_ms(int ms) -> void;
extern fn os_get_platform() -> string;
extern fn os_get_env(string key) -> string;

static char* FILE_BUF;
static char* FMT_BUF;
static char* DATE_BUF;

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
    while (*(p + j) != 0) {
        *(dst + di) = *(p + j);
        di = di + 1;
        j = j + 1;
    }
    return di;
}

fn fmt_fixed(int whole, int frac) -> string {
    int i = copy_to(FMT_BUF, 0, dsk_itoa(whole));
    *(FMT_BUF + i) = 46; i = i + 1;
    i = copy_to(FMT_BUF, i, dsk_itoa_pad(frac, 2));
    *(FMT_BUF + i) = 0;
    return cast<string>(FMT_BUF);
}

fn two_digits(int v) -> string { return dsk_itoa_pad(v, 2); }

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
    i = copy_to(DATE_BUF, i, dsk_itoa(y));
    *(DATE_BUF + i) = 45; i = i + 1;
    i = copy_to(DATE_BUF, i, dsk_itoa_pad(m, 2));
    *(DATE_BUF + i) = 45; i = i + 1;
    i = copy_to(DATE_BUF, i, dsk_itoa_pad(d, 2));
    *(DATE_BUF + i) = 0;
    return cast<string>(DATE_BUF);
}

fn main() -> int {
    int err = dsk_init();
    if (err != 0) { return err; }
    FILE_BUF = alloc<char>(4096);
    FMT_BUF = alloc<char>(32);
    DATE_BUF = alloc<char>(32);

    // ── Calculator window ──
    int cwin = dsk_add_window("Calculator", 30, 50, 240, 340);
    int disp = dsk_add_widget(cwin, WT_TEXTBOX, 18, 36, 204, 42, "0", 0, 0, 0);
    array<int, 16> bid;
    array<int, 16> bkind;
    array<int, 16> bdigit;
    int gi = 0;
    int r = 0;
    while (r < 4) {
        int c = 0;
        while (c < 4) {
            int kind = 0;
            int dig = 0;
            char* lp = alloc<char>(2);
            *(lp + 0) = 0;
            *(lp + 1) = 0;
            if (r == 3) {
                if (c == 0) { kind = 6; *(lp + 0) = 67; }
                else if (c == 1) { kind = 0; dig = 0; *(lp + 0) = 48; }
                else if (c == 2) { kind = 5; *(lp + 0) = 61; }
                else { kind = 1; *(lp + 0) = 43; }
            } else {
                if (c == 3) {
                    if (r == 0) { kind = 4; *(lp + 0) = 47; }
                    if (r == 1) { kind = 3; *(lp + 0) = 42; }
                    if (r == 2) { kind = 2; *(lp + 0) = 45; }
                } else {
                    int d = (3 - r) * 3 + c + 1;
                    dig = d;
                    *(lp + 0) = 48 + d;
                }
            }
            bid[gi] = dsk_add_widget(cwin, WT_BUTTON, 18 + c * 52, 92 + r * 46, 46, 46, cast<string>(lp), 0, 0, 0);
            bkind[gi] = kind;
            bdigit[gi] = dig;
            gi = gi + 1;
            c = c + 1;
        }
        r = r + 1;
    }

    // ── Clock window ──
    int kwin = dsk_add_window("Clock", 290, 50, 300, 300);
    int hh = dsk_add_widget(kwin, WT_TEXTBOX, 22, 32, 84, 42, "00", 0, 0, 0);
    int mm = dsk_add_widget(kwin, WT_TEXTBOX, 110, 32, 84, 42, "00", 0, 0, 0);
    int ss = dsk_add_widget(kwin, WT_TEXTBOX, 198, 32, 80, 42, "00", 0, 0, 0);
    int date_lbl = dsk_add_widget(kwin, WT_LABEL, 22, 84, 260, 20, "date", 0, 0, 0);
    array<int, 12> dirx;
    array<int, 12> diry;
    dirx[0] = 0;    diry[0] = -100;
    dirx[1] = 50;   diry[1] = -87;
    dirx[2] = 87;   diry[2] = -50;
    dirx[3] = 100;  diry[3] = 0;
    dirx[4] = 87;   diry[4] = 50;
    dirx[5] = 50;   diry[5] = 87;
    dirx[6] = 0;    diry[6] = 100;
    dirx[7] = -50;  diry[7] = 87;
    dirx[8] = -87;  diry[8] = 50;
    dirx[9] = -100; diry[9] = 0;
    dirx[10] = -87; diry[10] = -50;
    dirx[11] = -50; diry[11] = -87;
    int ccx = 290 + 150;
    int ccy = 50 + 215;

    // ── System monitor window ──
    int swin = dsk_add_window("System Monitor", 610, 50, 360, 330);
    int mem_bar = dsk_add_widget(swin, WT_PROGRESS, 24, 96, 312, 16, "", 0, 0, 100);
    dsk_add_widget(swin, WT_LABEL, 24, 76, 160, 16, "RAM usage", 0, 0, 0);
    int val_mem = dsk_add_widget(swin, WT_LABEL, 250, 76, 90, 16, "0", 0, 0, 0);
    dsk_add_widget(swin, WT_LABEL, 24, 122, 160, 16, "Total (kB)", 0, 0, 0);
    int val_total = dsk_add_widget(swin, WT_LABEL, 210, 122, 126, 16, "0", 0, 0, 0);
    dsk_add_widget(swin, WT_LABEL, 24, 146, 160, 16, "Available (kB)", 0, 0, 0);
    int val_avail = dsk_add_widget(swin, WT_LABEL, 210, 146, 126, 16, "0", 0, 0, 0);
    int swap_bar = dsk_add_widget(swin, WT_PROGRESS, 24, 190, 312, 16, "", 0, 0, 100);
    dsk_add_widget(swin, WT_LABEL, 24, 170, 160, 16, "Swap usage", 0, 0, 0);
    int val_swap = dsk_add_widget(swin, WT_LABEL, 250, 170, 90, 16, "0", 0, 0, 0);
    dsk_add_widget(swin, WT_LABEL, 24, 216, 160, 16, "Load 1m", 0, 0, 0);
    int val_load = dsk_add_widget(swin, WT_LABEL, 210, 216, 126, 16, "0.00", 0, 0, 0);
    dsk_add_widget(swin, WT_LABEL, 24, 240, 160, 16, "Uptime (s)", 0, 0, 0);
    int val_up = dsk_add_widget(swin, WT_LABEL, 210, 240, 126, 16, "0", 0, 0, 0);
    dsk_add_widget(swin, WT_LABEL, 24, 282, 312, 16, "Live from /proc", 0, 0, 0);

    // ── About window ──
    int awin = dsk_add_window("About", 290, 370, 430, 290);
    dsk_add_widget(awin, WT_LABEL, 24, 44, 380, 20, "Falcon Desktop Environment", 0, 0, 0);
    dsk_add_widget(awin, WT_LABEL, 24, 74, 380, 20, "High-level apps on Magnetar GUI", 0, 0, 0);
    dsk_add_widget(awin, WT_LABEL, 24, 116, 120, 20, "Platform", 0, 0, 0);
    dsk_add_widget(awin, WT_TEXTBOX, 150, 112, 256, 28, os_get_platform(), 0, 0, 0);
    dsk_add_widget(awin, WT_LABEL, 24, 154, 120, 20, "User", 0, 0, 0);
    dsk_add_widget(awin, WT_TEXTBOX, 150, 150, 256, 28, os_get_env("USER"), 0, 0, 0);
    dsk_add_widget(awin, WT_LABEL, 24, 192, 120, 20, "Screen", 0, 0, 0);
    dsk_add_widget(awin, WT_TEXTBOX, 150, 188, 120, 28, dsk_itoa(dsk_screen_w()), 0, 0, 0);
    dsk_add_widget(awin, WT_LABEL, 278, 192, 12, 20, "x", 0, 0, 0);
    dsk_add_widget(awin, WT_TEXTBOX, 294, 188, 112, 28, dsk_itoa(dsk_screen_h()), 0, 0, 0);
    int hideb = dsk_add_widget(awin, WT_BUTTON, 150, 234, 120, 34, "Hide", 0, 0, 0);

    // ── Calculator state ──
    int cur = 0;
    int acc = 0;
    int op = 0;
    int entering = 0;

    int tick = 0;
    while (dsk_running() == 1) {
        dsk_widget_set_label(disp, dsk_itoa(cur));

        int ts = get_timestamp();
        int day = ts / 86400;
        int secs = ts - day * 86400;
        int h = secs / 3600;
        int mnow = (secs - h * 3600) / 60;
        int s = secs - h * 3600 - mnow * 60;
        dsk_widget_set_label(hh, two_digits(h));
        dsk_widget_set_label(mm, two_digits(mnow));
        dsk_widget_set_label(ss, two_digits(s));
        dsk_widget_set_label(date_lbl, days_to_date(day));

        int total = proc_value("/proc/meminfo", "MemTotal:");
        int avail = proc_value("/proc/meminfo", "MemAvailable:");
        int pct = 0;
        if (total > 0) { pct = (total - avail) * 100 / total; }
        dsk_widget_set(mem_bar, pct);
        dsk_widget_set_label(val_mem, dsk_itoa(pct));
        dsk_widget_set_label(val_total, dsk_itoa(total));
        dsk_widget_set_label(val_avail, dsk_itoa(avail));
        int stt = proc_value("/proc/meminfo", "SwapTotal:");
        int sfr = proc_value("/proc/meminfo", "SwapFree:");
        int spct = 0;
        if (stt > 0) { spct = (stt - sfr) * 100 / stt; }
        dsk_widget_set(swap_bar, spct);
        dsk_widget_set_label(val_swap, dsk_itoa(spct));
        int nu = read_file("/proc/uptime", FILE_BUF, 128);
        dsk_widget_set_label(val_up, dsk_itoa(parse_num(FILE_BUF, 0, nu)));
        int nl = read_file("/proc/loadavg", FILE_BUF, 128);
        int dot = find_key(FILE_BUF, nl, ".");
        dsk_widget_set_label(val_load, fmt_fixed(parse_num(FILE_BUF, 0, nl), parse_num(FILE_BUF, dot + 1, nl)));

        int clicked = dsk_update();

        int hi = h - (h / 12) * 12;
        dsk_line(ccx, ccy, ccx + dirx[hi] * 42 / 100, ccy + diry[hi] * 42 / 100, gui_rgb(30, 40, 70));
        int mi = mnow / 5;
        dsk_line(ccx, ccy, ccx + dirx[mi] * 64 / 100, ccy + diry[mi] * 64 / 100, gui_rgb(30, 90, 160));
        int si = s / 5;
        dsk_line(ccx, ccy, ccx + dirx[si] * 78 / 100, ccy + diry[si] * 78 / 100, gui_rgb(200, 40, 40));
        gui_fill_rect(ccx - 3, ccy - 3, 7, 7, gui_rgb(30, 40, 70));

        if (clicked >= 0) {
            if (clicked == hideb) {
                dsk_toggle_window(awin);
            } else {
                int i = 0;
                while (i < 16) {
                    if (bid[i] == clicked) {
                        if (bkind[i] == 0) {
                            if (entering == 1) { cur = cur * 10 + bdigit[i]; }
                            else { cur = bdigit[i]; entering = 1; }
                        } else if (bkind[i] == 6) {
                            cur = 0; acc = 0; op = 0; entering = 0;
                        } else if (bkind[i] == 5) {
                            if (op == 1) { cur = acc + cur; }
                            if (op == 2) { cur = acc - cur; }
                            if (op == 3) { cur = acc * cur; }
                            if (op == 4) { if (cur != 0) { cur = acc / cur; } else { cur = 0; } }
                            op = 0; entering = 0;
                        } else {
                            if (op == 1) { cur = acc + cur; }
                            if (op == 2) { cur = acc - cur; }
                            if (op == 3) { cur = acc * cur; }
                            if (op == 4) { if (cur != 0) { cur = acc / cur; } else { cur = 0; } }
                            acc = cur;
                            if (bkind[i] == 1) { op = 1; }
                            if (bkind[i] == 2) { op = 2; }
                            if (bkind[i] == 3) { op = 3; }
                            if (bkind[i] == 4) { op = 4; }
                            entering = 0;
                        }
                    }
                    i = i + 1;
                }
            }
        }

        dsk_draw_cursor(gui_mouse_x(), gui_mouse_y());
        gui_present();
        sleep_ms(50);
    }

    dsk_shutdown();
    return 0;
}
