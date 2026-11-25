// desktop_app_demo.mg — Showcase modern Desktop GUI in Magnetar (Falcon Engine)
use "gui.mg";

extern fn sleep_ms(int ms) -> void;
extern fn print_str(string s) -> void;
extern fn print_int(int n) -> void;

fn main() -> int {
    print_str("Starting Falcon Modern Desktop Application...\n");

    int app_w = 880;
    int app_h = 600;

    int err = dsk_init_window(app_w, app_h, "Falcon Desktop Application (Professional UI)");
    if (err != 0) {
        print_str("Failed to initialize GUI engine\n");
        return err;
    }

    if (gui_is_x11() == 1) {
        print_str("Running in Desktop Window mode (X11 socket protocol, 60 FPS)\n");
    } else {
        print_str("Running in Direct Hardware mode (/dev/dri/card0 DRM/KMS)\n");
    }

    // Set initial dark theme
    dsk_theme_dark();

    // Create main application window inside canvas
    int win = dsk_add_window("Falcon Control Center", 30, 20, 820, 520);

    // Header & Badges
    dsk_add_widget(win, WT_LABEL, 24, 40, 500, 26, "Falcon Desktop Application Studio", 0, 0, 0);
    dsk_add_widget(win, WT_LABEL, 24, 68, 500, 20, "Dual-mode native Linux GUI: X11 Windowed or Direct card0", 0, 0, 0);
    int badge_status = dsk_add_widget(win, WT_BADGE, 660, 40, 130, 26, "SYSTEM ACTIVE", 1, 0, 0);

    // Horizontal Separator
    dsk_add_widget(win, WT_SEPARATOR, 24, 100, 770, 2, "", 0, 0, 0);

    // Form Section 1: User & Input
    dsk_add_widget(win, WT_LABEL, 24, 120, 140, 26, "Operator ID:", 0, 0, 0);
    dsk_add_widget(win, WT_TEXTBOX, 180, 118, 360, 30, "oussama@falcon", 0, 0, 0);

    // Section 2: Toggle Switches (Modern iOS/Material Style)
    dsk_add_widget(win, WT_LABEL, 24, 168, 140, 26, "Fast Scanout:", 0, 0, 0);
    int sw_scanout = dsk_add_widget(win, WT_SWITCH, 180, 168, 220, 24, "Direct DRM / KMS Fallback", 1, 0, 0);

    dsk_add_widget(win, WT_LABEL, 24, 204, 140, 26, "Full Buffer:", 0, 0, 0);
    int sw_buffer  = dsk_add_widget(win, WT_SWITCH, 180, 204, 220, 24, "32-bit Dynamic Re-mmap", 1, 0, 0);

    // Section 3: Checkboxes
    dsk_add_widget(win, WT_LABEL, 24, 244, 140, 26, "Options:", 0, 0, 0);
    int chk_auto = dsk_add_widget(win, WT_CHECKBOX, 180, 244, 260, 24, "Auto-refresh backbuffer", 1, 0, 0);

    // Section 4: Sliders & Progress Bar
    dsk_add_widget(win, WT_LABEL, 24, 285, 140, 26, "Render Quality:", 0, 0, 0);
    int sld_qual = dsk_add_widget(win, WT_SLIDER, 180, 285, 360, 26, "", 90, 0, 100);

    dsk_add_widget(win, WT_LABEL, 24, 325, 140, 26, "Engine Load:", 0, 0, 0);
    int prog_load = dsk_add_widget(win, WT_PROGRESS, 180, 325, 360, 24, "", 45, 0, 100);

    // Horizontal Separator
    dsk_add_widget(win, WT_SEPARATOR, 24, 370, 770, 2, "", 0, 0, 0);

    // Action Buttons
    int btn_cycle_theme = dsk_add_widget(win, WT_BUTTON, 180, 395, 180, 38, "Switch Theme", 0, 0, 0);
    int btn_boost       = dsk_add_widget(win, WT_BUTTON, 380, 395, 160, 38, "Boost Progress", 0, 0, 0);
    int btn_exit        = dsk_add_widget(win, WT_BUTTON, 560, 395, 120, 38, "Exit", 0, 0, 0);

    int cur_theme = 1; // 0=default, 1=dark, 2=cyberpunk, 3=emerald
    int cur_load  = 45;

    // Main 60 FPS Event Loop
    while (dsk_running() == 1) {
        int clicked = dsk_update();

        if (clicked == btn_cycle_theme) {
            cur_theme = cur_theme + 1;
            if (cur_theme > 3) { cur_theme = 0; }
            dsk_set_theme(cur_theme);
            print_str("Theme switched to: ");
            print_int(cur_theme);
            print_str("\n");
        }

        if (clicked == btn_boost) {
            cur_load = cur_load + 15;
            if (cur_load > 100) { cur_load = 10; }
            dsk_widget_set(prog_load, cur_load);
        }

        if (clicked == sw_scanout) {
            print_str("Scanout toggle switched!\n");
        }

        if (clicked == btn_exit || gui_close_requested() == 1) {
            dsk_stop();
        }

        gui_present();
        sleep_ms(16); // 60 FPS smooth rendering
    }

    dsk_shutdown();
    print_str("Application exited cleanly.\n");
    return 0;
}
