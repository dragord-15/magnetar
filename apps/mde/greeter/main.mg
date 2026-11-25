// MDE Greeter - login/session selector UI (MVP)
// Real PAM auth is handled by display-manager/integration layer; greeter provides UI.
// Build: ./magc mde/greeter/main.mg -o build/mde-greeter
use "gui.mg";
extern fn sleep_ms(int ms) -> void;
extern fn os_get_env(string key) -> string;
extern fn print_str(string s) -> void;
fn main() -> int {
    int err = dsk_init_window(720, 420, "MDE Login");
    if (err != 0) { return err; }
    dsk_set_theme(1);
    int win = dsk_root();
    dsk_add_widget(win, WT_LABEL, 220, 40, 300, 28, "Magnetar Desktop Environment", 0, 0, 0);
    dsk_add_widget(win, WT_SEPARATOR, 120, 76, 480, 2, "", 0, 0, 0);
    dsk_add_widget(win, WT_LABEL, 160, 120, 120, 22, "User", 0, 0, 0);
    string user = os_get_env("USER");
    if (_str_len(user) == 0) { user = "oussama"; }
    int user_box = dsk_add_widget(win, WT_TEXTBOX, 280, 116, 260, 30, user, 0, 0, 0);
    dsk_add_widget(win, WT_LABEL, 160, 164, 120, 22, "Session", 0, 0, 0);
    dsk_add_widget(win, WT_TEXTBOX, 280, 160, 260, 30, "MDE (Magnetar)", 0, 0, 0);
    int msg = dsk_add_widget(win, WT_LABEL, 160, 210, 420, 20, "MVP: press Login to start session.", 0, 0, 0);
    int login = dsk_add_widget(win, WT_BUTTON, 280, 250, 120, 36, "Login", 0, 0, 0);
    int shutdown = dsk_add_widget(win, WT_BUTTON, 420, 250, 120, 36, "Exit", 0, 0, 0);
    while (dsk_running() == 1) {
        int c = dsk_frame();
        if (c == login) {
            print_str("[mde-greeter] login user="); print_str(dsk_widget_text(user_box)); print_str("\n");
            dsk_shutdown();
            return 0;
        }
        if (c == shutdown || gui_close_requested() == 1) { dsk_shutdown(); return 1; }
    }
    dsk_shutdown();
    return 1;
}
