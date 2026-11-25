// MDE Settings app
// Build: ./magc mde/apps/settings/main.mg -o build/mde-settings
use "gui.mg";
extern fn sleep_ms(int ms) -> void;
extern fn os_get_env(string key) -> string;
extern fn os_get_platform() -> string;
fn main() -> int {
    int err = dsk_init_window(640, 420, "MDE Settings");
    if (err != 0) { return err; }
    dsk_set_theme(1);
    int win = dsk_root();
    dsk_add_widget(win, WT_LABEL, 24, 20, 300, 24, "MDE Settings", 0, 0, 0);
    dsk_add_widget(win, WT_SEPARATOR, 24, 52, 580, 2, "", 0, 0, 0);
    dsk_add_widget(win, WT_LABEL, 24, 72, 140, 20, "User", 0, 0, 0);
    dsk_add_widget(win, WT_TEXTBOX, 180, 68, 300, 28, os_get_env("USER"), 0, 0, 0);
    dsk_add_widget(win, WT_LABEL, 24, 112, 140, 20, "Platform", 0, 0, 0);
    dsk_add_widget(win, WT_TEXTBOX, 180, 108, 300, 28, os_get_platform(), 0, 0, 0);
    dsk_add_widget(win, WT_LABEL, 24, 152, 140, 20, "Theme", 0, 0, 0);
    int b0 = dsk_add_widget(win, WT_BUTTON, 180, 148, 90, 30, "Default", 0, 0, 0);
    int b1 = dsk_add_widget(win, WT_BUTTON, 280, 148, 90, 30, "Dark", 0, 0, 0);
    int b2 = dsk_add_widget(win, WT_BUTTON, 380, 148, 90, 30, "Cyber", 0, 0, 0);
    int b3 = dsk_add_widget(win, WT_BUTTON, 480, 148, 90, 30, "Emerald", 0, 0, 0);
    dsk_add_widget(win, WT_LABEL, 24, 200, 140, 20, "Session", 0, 0, 0);
    dsk_add_widget(win, WT_TEXTBOX, 180, 196, 300, 28, "MDE / Debian-family", 0, 0, 0);
    int quit = dsk_add_widget(win, WT_BUTTON, 24, 340, 120, 34, "Close", 0, 0, 0);
    while (dsk_running() == 1) {
        int c = dsk_frame();
        if (c == b0) { dsk_set_theme(0); }
        if (c == b1) { dsk_set_theme(1); }
        if (c == b2) { dsk_set_theme(2); }
        if (c == b3) { dsk_set_theme(3); }
        if (c == quit || gui_close_requested() == 1) { dsk_stop(); }
    }
    dsk_shutdown();
    return 0;
}
