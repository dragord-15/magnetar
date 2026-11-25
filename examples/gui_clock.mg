extern fn get_timestamp() -> int;
// gui_clock.mg — Digital + analog clock with calendar on the desktop framework
use "gui.mg";

extern fn sleep_ms(int ms) -> void;

static char* DATE_BUF;

fn two_digits(int v) -> string {
    return dsk_itoa_pad(v, 2);
}

fn str_copy_to(char* dst, int di, string src) -> int {
    char* p = cast<char*>(src);
    int j = 0;
    while (*(p + j) != 0) {
        *(dst + di) = *(p + j);
        di = di + 1;
        j = j + 1;
    }
    return di;
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
    i = str_copy_to(DATE_BUF, i, dsk_itoa(y));
    *(DATE_BUF + i) = 45; i = i + 1;
    i = str_copy_to(DATE_BUF, i, dsk_itoa_pad(m, 2));
    *(DATE_BUF + i) = 45; i = i + 1;
    i = str_copy_to(DATE_BUF, i, dsk_itoa_pad(d, 2));
    *(DATE_BUF + i) = 0;
    return cast<string>(DATE_BUF);
}

fn main() -> int {
    int err = dsk_init();
    if (err != 0) { return err; }
    DATE_BUF = alloc<char>(32);

    int win = dsk_add_window("Clock", 90, 60, 300, 300);
    int hh = dsk_add_widget(win, WT_TEXTBOX, 22, 32, 84, 42, "00", 0, 0, 0);
    int mm = dsk_add_widget(win, WT_TEXTBOX, 110, 32, 84, 42, "00", 0, 0, 0);
    int ss = dsk_add_widget(win, WT_TEXTBOX, 198, 32, 80, 42, "00", 0, 0, 0);
    int date_lbl = dsk_add_widget(win, WT_LABEL, 22, 84, 200, 20, "date", 0, 0, 0);

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

    int cx = 90 + 150;
    int cy = 60 + 215;

    while (dsk_running() == 1) {
        int ts = get_timestamp();
        int day = ts / 86400;
        int secs = ts - day * 86400;
        int h = secs / 3600;
        int m = (secs - h * 3600) / 60;
        int s = secs - h * 3600 - m * 60;

        dsk_widget_set_label(hh, two_digits(h));
        dsk_widget_set_label(mm, two_digits(m));
        dsk_widget_set_label(ss, two_digits(s));
        dsk_widget_set_label(date_lbl, days_to_date(day));

        dsk_update();

        int hi = h - (h / 12) * 12;
        dsk_line(cx, cy, cx + dirx[hi] * 42 / 100, cy + diry[hi] * 42 / 100, gui_rgb(30, 40, 70));

        int mi = m / 5;
        dsk_line(cx, cy, cx + dirx[mi] * 64 / 100, cy + diry[mi] * 64 / 100, gui_rgb(30, 90, 160));

        int si = s / 5;
        dsk_line(cx, cy, cx + dirx[si] * 78 / 100, cy + diry[si] * 78 / 100, gui_rgb(200, 40, 40));

        gui_fill_rect(cx - 3, cy - 3, 7, 7, gui_rgb(30, 40, 70));
        dsk_draw_cursor(gui_mouse_x(), gui_mouse_y());
        gui_present();
        sleep_ms(100);
    }

    dsk_shutdown();
    return 0;
}
