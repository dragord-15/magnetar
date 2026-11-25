// gui_about.mg — About / system information panel
use "gui.mg";

extern fn sleep_ms(int ms) -> void;
extern fn os_get_platform() -> string;
extern fn os_get_env(string key) -> string;

fn main() -> int {
    int err = dsk_init();
    if (err != 0) { return err; }

    int win = dsk_add_window("About", 220, 130, 420, 280);
    dsk_add_widget(win, WT_LABEL, 24, 48, 380, 20, "Falcon Desktop Environment", 0, 0, 0);
    dsk_add_widget(win, WT_LABEL, 24, 78, 380, 20, "High-level apps on the Magnetar GUI", 0, 0, 0);

    dsk_add_widget(win, WT_LABEL, 24, 122, 130, 20, "Platform", 0, 0, 0);
    dsk_add_widget(win, WT_TEXTBOX, 150, 118, 246, 28, os_get_platform(), 0, 0, 0);

    dsk_add_widget(win, WT_LABEL, 24, 160, 130, 20, "User", 0, 0, 0);
    dsk_add_widget(win, WT_TEXTBOX, 150, 156, 246, 28, os_get_env("USER"), 0, 0, 0);

    dsk_add_widget(win, WT_LABEL, 24, 198, 130, 20, "Screen", 0, 0, 0);
    dsk_add_widget(win, WT_TEXTBOX, 150, 194, 114, 28, dsk_itoa(dsk_screen_w()), 0, 0, 0);
    dsk_add_widget(win, WT_LABEL, 272, 198, 8, 20, "x", 0, 0, 0);
    dsk_add_widget(win, WT_TEXTBOX, 286, 194, 110, 28, dsk_itoa(dsk_screen_h()), 0, 0, 0);

    int closeb = dsk_add_widget(win, WT_BUTTON, 150, 234, 120, 32, "Close", 0, 0, 0);

    while (dsk_running() == 1) {
        int clicked = dsk_update();
        if (clicked == closeb) { dsk_stop(); }
        gui_present();
        sleep_ms(16);
    }

    dsk_shutdown();
    return 0;
}
