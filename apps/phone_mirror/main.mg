// phone_mirror/main.mg - Falcon Phone Mirror & Remote Control
// Pure Magnetar desktop application to mirror and control an Android phone over USB.
// Build: ./magc phone_mirror/main.mg -o build/phone_mirror
// Run:   DISPLAY=:2 ./build/phone_mirror

use "lib/gui.mg";
use "lib/adb.mg";
use "lib/image.mg";

extern fn sleep_ms(int ms) -> void;
extern fn print_str(string s) -> void;
extern fn print_int(int n) -> void;

const int SC_W = 400;
const int SC_H = 780;

static int G_PHONE_W = 720;
static int G_PHONE_H = 1600;
static int* G_PHONE_FRAME = null;
static int G_FRAME_READY = 0;

static int G_ASYNC_PID = 0 - 1;
static int G_REQUEST_CAPTURE = 1;
static int G_AUTO_LIVE = 1;

static int G_TOUCH_X = 0 - 1;
static int G_TOUCH_Y = 0 - 1;
static int G_TOUCH_FRAMES = 0;

fn start_async_capture() -> void {
    if (G_ASYNC_PID > 0) {
        int status = 0;
        int res = sys_wait4(G_ASYNC_PID, &status, 1, null);
        if (res == 0) { return; }
        G_ASYNC_PID = 0 - 1;
    }
    if (adb_device_authorized() == false) { return; }

    int pid = sys_fork();
    if (pid == 0) {
        char** argv = alloc<char*>(16);
        argv[0] = cast<char*>("/bin/sh");
        argv[1] = cast<char*>("-c");
        argv[2] = cast<char*>("adb exec-out screencap -p | ffmpeg -nostdin -loglevel quiet -y -i - -vf 'scale=400:780:force_original_aspect_ratio=decrease,pad=400:780:(ow-iw)/2:(oh-ih)/2:color=0x0E1420,format=bgra' -f image2 -c:v bmp /tmp/falcon_live.bmp");
        argv[3] = null;
        sys_execve("/bin/sh", argv, null);
        sys_exit(127);
    }
    G_ASYNC_PID = pid;
}

fn check_and_update_stream() -> void {
    if (G_ASYNC_PID <= 0) {
        if (G_AUTO_LIVE == 1 || G_REQUEST_CAPTURE == 1) {
            G_REQUEST_CAPTURE = 0;
            start_async_capture();
        }
        return;
    }

    int status = 0;
    int res = sys_wait4(G_ASYNC_PID, &status, 1, null);
    if (res == G_ASYNC_PID) {
        G_ASYNC_PID = 0 - 1;
        Image* img = image_load("/tmp/falcon_live.bmp");
        if (img != null && img.width == SC_W && img.height == SC_H) {
            char* src = img.data;
            int total = SC_W * SC_H;
            for (int i = 0; i < total; i = i + 1) {
                char* sp = src + i * 4;
                int r = cast<int>(*(sp + 0)) & 255;
                int g = cast<int>(*(sp + 1)) & 255;
                int b = cast<int>(*(sp + 2)) & 255;
                G_PHONE_FRAME[i] = (r * 65536) + (g * 256) + b;
            }
            G_FRAME_READY = 1;
            image_destroy(img);
        } else if (img != null) {
            image_destroy(img);
        }

        if (G_AUTO_LIVE == 1 || G_REQUEST_CAPTURE == 1) {
            G_REQUEST_CAPTURE = 0;
            start_async_capture();
        }
    }
}

fn trigger_capture() -> void {
    G_REQUEST_CAPTURE = 1;
    if (G_ASYNC_PID <= 0) { start_async_capture(); }
}

fn parse_screen_resolution() -> void {
    string size_str = adb_screen_size();
    if (_adb_strlen(size_str) == 0) { return; }
    char* p = cast<char*>(size_str);
    int slen = _adb_strlen(size_str);

    int x_idx = 0 - 1;
    for (int i = 0; i < slen; i = i + 1) {
        if (_adb_byte(p, i) == 120) { x_idx = i; break; }
    }
    if (x_idx <= 0) { return; }

    int w_start = x_idx - 1;
    while (w_start >= 0 && _adb_byte(p, w_start) >= 48 && _adb_byte(p, w_start) <= 57) {
        w_start = w_start - 1;
    }
    w_start = w_start + 1;

    int pw = 0;
    for (int a = w_start; a < x_idx; a = a + 1) {
        pw = pw * 10 + (_adb_byte(p, a) - 48);
    }

    int h_start = x_idx + 1;
    int ph = 0;
    while (h_start < slen && _adb_byte(p, h_start) >= 48 && _adb_byte(p, h_start) <= 57) {
        ph = ph * 10 + (_adb_byte(p, h_start) - 48);
        h_start = h_start + 1;
    }

    if (pw > 0 && ph > 0) {
        G_PHONE_W = pw;
        G_PHONE_H = ph;
    }
}

fn draw_phone_screen_inside_window(int win_phone) -> void {
    if (dsk_window_visible(win_phone) == 0) { return; }

    int wx = dsk_window_x(win_phone);
    int wy = dsk_window_y(win_phone);
    int sc_x = wx + 15;
    int sc_y = wy + 35;

    gui_draw_rounded_rect(sc_x - 3, sc_y - 3, SC_W + 6, SC_H + 6, 8, 0x3E4B5E);

    if (G_FRAME_READY == 1 && G_PHONE_FRAME != null) {
        char* fb = cast<char*>(G_DRAW);
        for (int y = 0; y < SC_H; y = y + 1) {
            int dst_off = ((sc_y + y) * G_XRES + sc_x) * 4;
            int row_base = y * SC_W;
            for (int x = 0; x < SC_W; x = x + 1) {
                int c = G_PHONE_FRAME[row_base + x];
                int b = c & 255;
                int g = (c / 256) & 255;
                int r = c / 65536;
                int p = dst_off + x * 4;
                *(fb + p) = cast<char>(b);
                *(fb + p + 1) = cast<char>(g);
                *(fb + p + 2) = cast<char>(r);
                *(fb + p + 3) = cast<char>(0);
            }
        }
    } else {
        gui_fill_gradient_v(sc_x, sc_y, SC_W, SC_H, 0x0E1420, 0x1E2B45);
        gui_fill_rect(sc_x, sc_y, SC_W, 26, 0x080C14);
        gui_draw_text(sc_x + 14, sc_y + 6, "12:00", 0xAAAAAA, 0x080C14, 1);
        gui_draw_text(sc_x + SC_W - 75, sc_y + 6, "5G 99%", 0xAAAAAA, 0x080C14, 1);

        int cx = sc_x + 25;
        int cy = sc_y + 220;
        gui_fill_rounded_rect(cx, cy, SC_W - 50, 260, 14, 0x182030);
        gui_draw_rounded_rect(cx, cy, SC_W - 50, 260, 14, 0x2A3B54);
        gui_draw_text(cx + 65, cy + 30, "Falcon Phone Mirror", 0x4FACFE, 0x182030, 1);
        gui_draw_text(cx + 55, cy + 65, "USB Live Control Edition", 0x8898AA, 0x182030, 1);

        if (adb_device_authorized() == true) {
            gui_draw_text(cx + 70, cy + 110, "Status: CONNECTED", 0x00E676, 0x182030, 1);
            gui_draw_text(cx + 50, cy + 145, "Loading live screen...", 0xFFFFFF, 0x182030, 1);
            gui_draw_text(cx + 40, cy + 180, "Touch anywhere to tap!", 0x80D8FF, 0x182030, 1);
        } else if (adb_device_connected() == true) {
            gui_draw_text(cx + 55, cy + 110, "Status: UNAUTHORIZED", 0xFF9800, 0x182030, 1);
            gui_draw_text(cx + 35, cy + 145, "Please unlock phone &", 0xFFFFFF, 0x182030, 1);
            gui_draw_text(cx + 35, cy + 175, "Allow USB Debugging", 0xFFD54F, 0x182030, 1);
        } else {
            gui_draw_text(cx + 55, cy + 110, "Status: DISCONNECTED", 0xFF5252, 0x182030, 1);
            gui_draw_text(cx + 45, cy + 145, "Connect phone via USB", 0xCCCCCC, 0x182030, 1);
        }
    }

    if (G_TOUCH_FRAMES > 0 && G_TOUCH_X >= 0 && G_TOUCH_Y >= 0) {
        int radius = 18 - G_TOUCH_FRAMES * 2;
        if (radius < 4) { radius = 4; }
        gui_fill_circle(G_TOUCH_X, G_TOUCH_Y, radius, 0x00E5FF);
        G_TOUCH_FRAMES = G_TOUCH_FRAMES - 1;
    }
}

fn main() -> int {
    print_str("Starting Falcon Phone Mirror...\n");

    int err = dsk_init_window(1260, 920, "Falcon Phone Mirror - USB Control");
    if (err != 0) {
        print_str("Failed to initialize GUI engine\n");
        return err;
    }
    dsk_theme_dark();

    G_PHONE_FRAME = alloc<int>(SC_W * SC_H);

    dsk_add_widget(dsk_root(), WT_LABEL, 0, 0, 1, 1, "", 0, 0, 0);

    int win_phone = dsk_add_window("Android Phone Screen (شاشة الهاتف)", 30, 20, 430, 875);
    int btn_back = dsk_add_widget(win_phone, WT_BUTTON, 15, 825, 115, 36, "< Back", 0, 0, 0);
    int btn_home = dsk_add_widget(win_phone, WT_BUTTON, 155, 825, 120, 36, "O Home", 0, 0, 0);
    int btn_apps = dsk_add_widget(win_phone, WT_BUTTON, 300, 825, 115, 36, "[] Apps", 0, 0, 0);

    int win_ctrl = dsk_add_window("Falcon Control Center (لوحة التحكم)", 480, 20, 540, 875);

    dsk_add_widget(win_ctrl, WT_LABEL, 20, 38, 260, 24, "Android Device Status", 0, 0, 0);
    string initial_badge = "OFFLINE";
    if (adb_device_authorized() == true) { initial_badge = "CONNECTED"; }
    else if (adb_device_connected() == true) { initial_badge = "UNAUTHORIZED"; }
    int badge_dev = dsk_add_widget(win_ctrl, WT_BADGE, 350, 36, 160, 26, initial_badge, 1, 0, 0);
    dsk_add_widget(win_ctrl, WT_SEPARATOR, 20, 72, 490, 2, "", 0, 0, 0);

    string serial_val = adb_device_serial();
    if (_adb_strlen(serial_val) == 0) { serial_val = "None"; }
    string model_val = "Unknown";
    string ver_val = "Unknown";
    string bat_val = "?";
    if (adb_device_authorized() == true) {
        model_val = adb_device_model();
        ver_val = adb_android_version();
        bat_val = adb_battery_level();
        parse_screen_resolution();
    }

    dsk_add_widget(win_ctrl, WT_LABEL, 20, 85, 100, 20, "Serial:", 0, 0, 0);
    int lbl_serial = dsk_add_widget(win_ctrl, WT_LABEL, 120, 85, 160, 20, serial_val, 0, 0, 0);
    dsk_add_widget(win_ctrl, WT_LABEL, 290, 85, 90, 20, "Battery:", 0, 0, 0);
    int lbl_bat = dsk_add_widget(win_ctrl, WT_LABEL, 385, 85, 100, 20, bat_val, 0, 0, 0);
    dsk_add_widget(win_ctrl, WT_LABEL, 20, 110, 100, 20, "Model:", 0, 0, 0);
    int lbl_model = dsk_add_widget(win_ctrl, WT_LABEL, 120, 110, 160, 20, model_val, 0, 0, 0);
    dsk_add_widget(win_ctrl, WT_LABEL, 290, 110, 90, 20, "Android:", 0, 0, 0);
    int lbl_ver = dsk_add_widget(win_ctrl, WT_LABEL, 385, 110, 100, 20, ver_val, 0, 0, 0);
    dsk_add_widget(win_ctrl, WT_SEPARATOR, 20, 140, 490, 2, "", 0, 0, 0);

    dsk_add_widget(win_ctrl, WT_LABEL, 20, 155, 200, 20, "Live Stream Controls", 0, 0, 0);
    int sw_live = dsk_add_widget(win_ctrl, WT_SWITCH, 20, 182, 230, 26, "Auto-Sync Live Stream", 1, 0, 0);
    int btn_capture = dsk_add_widget(win_ctrl, WT_BUTTON, 265, 178, 120, 34, "Sync Now", 0, 0, 0);
    int btn_refresh = dsk_add_widget(win_ctrl, WT_BUTTON, 395, 178, 120, 34, "Refresh Info", 0, 0, 0);
    dsk_add_widget(win_ctrl, WT_SEPARATOR, 20, 226, 490, 2, "", 0, 0, 0);

    dsk_add_widget(win_ctrl, WT_LABEL, 20, 240, 200, 20, "Hardware Keys", 0, 0, 0);
    int btn_power = dsk_add_widget(win_ctrl, WT_BUTTON, 20, 268, 150, 34, "Power", 0, 0, 0);
    int btn_vol_up = dsk_add_widget(win_ctrl, WT_BUTTON, 185, 268, 155, 34, "Volume +", 0, 0, 0);
    int btn_vol_dn = dsk_add_widget(win_ctrl, WT_BUTTON, 355, 268, 155, 34, "Volume -", 0, 0, 0);
    dsk_add_widget(win_ctrl, WT_SEPARATOR, 20, 316, 490, 2, "", 0, 0, 0);

    dsk_add_widget(win_ctrl, WT_LABEL, 20, 330, 200, 20, "Swipe Gestures", 0, 0, 0);
    int btn_sw_up = dsk_add_widget(win_ctrl, WT_BUTTON, 20, 358, 110, 34, "Up", 0, 0, 0);
    int btn_sw_down = dsk_add_widget(win_ctrl, WT_BUTTON, 145, 358, 110, 34, "Down", 0, 0, 0);
    int btn_sw_left = dsk_add_widget(win_ctrl, WT_BUTTON, 270, 358, 110, 34, "Left", 0, 0, 0);
    int btn_sw_right = dsk_add_widget(win_ctrl, WT_BUTTON, 395, 358, 110, 34, "Right", 0, 0, 0);
    dsk_add_widget(win_ctrl, WT_SEPARATOR, 20, 406, 490, 2, "", 0, 0, 0);

    dsk_add_widget(win_ctrl, WT_LABEL, 20, 420, 260, 20, "Type & Send Text to Phone:", 0, 0, 0);
    int txt_input = dsk_add_widget(win_ctrl, WT_TEXTBOX, 20, 448, 350, 32, "Hello Falcon", 0, 0, 0);
    int btn_send_text = dsk_add_widget(win_ctrl, WT_BUTTON, 385, 448, 125, 32, "Send Text", 0, 0, 0);
    dsk_add_widget(win_ctrl, WT_SEPARATOR, 20, 496, 490, 2, "", 0, 0, 0);

    int btn_reboot = dsk_add_widget(win_ctrl, WT_BUTTON, 20, 515, 150, 36, "Reboot Phone", 0, 0, 0);
    int btn_theme = dsk_add_widget(win_ctrl, WT_BUTTON, 185, 515, 155, 36, "Switch Theme", 0, 0, 0);
    int btn_exit = dsk_add_widget(win_ctrl, WT_BUTTON, 355, 515, 155, 36, "Exit App", 0, 0, 0);

    int cur_theme = 1;
    dsk_toast("Falcon Phone Mirror Ready (Live Stream Active)");
    start_async_capture();

    while (dsk_running() == 1) {
        int clicked = dsk_update();
        int mx = gui_mouse_x();
        int my = gui_mouse_y();
        int is_click = gui_mouse_clicked();

        G_AUTO_LIVE = dsk_widget_val(sw_live);

        int wx = dsk_window_x(win_phone);
        int wy = dsk_window_y(win_phone);
        int sc_x = wx + 15;
        int sc_y = wy + 35;

        if (is_click == 1 && dsk_window_visible(win_phone) == 1) {
            if (mx >= sc_x && mx <= sc_x + SC_W && my >= sc_y && my <= sc_y + SC_H) {
                int rel_x = mx - sc_x;
                int rel_y = my - sc_y;
                int touch_px = (rel_x * G_PHONE_W) / SC_W;
                int touch_py = (rel_y * G_PHONE_H) / SC_H;
                G_TOUCH_X = mx;
                G_TOUCH_Y = my;
                G_TOUCH_FRAMES = 6;
                if (adb_device_authorized() == true) {
                    adb_input_tap(touch_px, touch_py);
                    dsk_toast("Tap sent to phone!");
                    trigger_capture();
                } else {
                    dsk_toast("Phone is not authorized!");
                }
            }
        }

        if (clicked == btn_back) {
            if (adb_device_authorized() == true) {
                adb_input_keyevent(4);
                trigger_capture();
            }
        } else if (clicked == btn_home) {
            if (adb_device_authorized() == true) {
                adb_input_keyevent(3);
                trigger_capture();
            }
        } else if (clicked == btn_apps) {
            if (adb_device_authorized() == true) {
                adb_input_keyevent(187);
                trigger_capture();
            }
        } else if (clicked == btn_capture) {
            trigger_capture();
            dsk_toast("Syncing phone screen...");
        } else if (clicked == btn_refresh) {
            if (adb_device_authorized() == true) {
                dsk_widget_set_label(badge_dev, "CONNECTED");
                dsk_widget_set_label(lbl_serial, adb_device_serial());
                dsk_widget_set_label(lbl_model, adb_device_model());
                dsk_widget_set_label(lbl_ver, adb_android_version());
                dsk_widget_set_label(lbl_bat, adb_battery_level());
                parse_screen_resolution();
                dsk_toast("Device connected & authorized!");
            } else if (adb_device_connected() == true) {
                dsk_widget_set_label(badge_dev, "UNAUTHORIZED");
                dsk_widget_set_label(lbl_serial, adb_device_serial());
                dsk_widget_set_label(lbl_model, "Unlock Phone");
                dsk_widget_set_label(lbl_ver, "-");
                dsk_widget_set_label(lbl_bat, "?");
                dsk_toast("Device UNAUTHORIZED! Allow USB debugging");
            } else {
                dsk_widget_set_label(badge_dev, "OFFLINE");
                dsk_widget_set_label(lbl_serial, "None");
                dsk_widget_set_label(lbl_model, "Unknown");
                dsk_widget_set_label(lbl_ver, "Unknown");
                dsk_widget_set_label(lbl_bat, "?");
                dsk_toast("No device connected");
            }
        } else if (clicked == btn_power) {
            if (adb_device_authorized() == true) { adb_input_keyevent(26); trigger_capture(); }
        } else if (clicked == btn_vol_up) {
            if (adb_device_authorized() == true) { adb_input_keyevent(24); trigger_capture(); }
        } else if (clicked == btn_vol_dn) {
            if (adb_device_authorized() == true) { adb_input_keyevent(25); trigger_capture(); }
        } else if (clicked == btn_sw_up) {
            if (adb_device_authorized() == true) {
                adb_input_swipe(G_PHONE_W / 2, (G_PHONE_H * 3) / 4, G_PHONE_W / 2, G_PHONE_H / 4, 300);
                trigger_capture();
            }
        } else if (clicked == btn_sw_down) {
            if (adb_device_authorized() == true) {
                adb_input_swipe(G_PHONE_W / 2, G_PHONE_H / 4, G_PHONE_W / 2, (G_PHONE_H * 3) / 4, 300);
                trigger_capture();
            }
        } else if (clicked == btn_sw_left) {
            if (adb_device_authorized() == true) {
                adb_input_swipe((G_PHONE_W * 3) / 4, G_PHONE_H / 2, G_PHONE_W / 4, G_PHONE_H / 2, 300);
                trigger_capture();
            }
        } else if (clicked == btn_sw_right) {
            if (adb_device_authorized() == true) {
                adb_input_swipe(G_PHONE_W / 4, G_PHONE_H / 2, (G_PHONE_W * 3) / 4, G_PHONE_H / 2, 300);
                trigger_capture();
            }
        } else if (clicked == btn_send_text) {
            if (adb_device_authorized() == true) {
                string text_to_send = dsk_widget_text(txt_input);
                if (_adb_strlen(text_to_send) > 0) {
                    adb_input_text(text_to_send);
                    trigger_capture();
                }
            } else {
                dsk_toast("Device not authorized");
            }
        } else if (clicked == btn_theme) {
            cur_theme = cur_theme + 1;
            if (cur_theme > 3) { cur_theme = 0; }
            dsk_set_theme(cur_theme);
        } else if (clicked == btn_reboot) {
            if (adb_device_authorized() == true) {
                dsk_toast("Rebooting device...");
                adb_reboot("");
            }
        } else if (clicked == btn_exit) {
            break;
        }

        check_and_update_stream();
        draw_phone_screen_inside_window(win_phone);
        dsk_draw_cursor(mx, my);
        gui_present();
        sleep_ms(16);
    }

    if (G_PHONE_FRAME != null) { free(G_PHONE_FRAME); }
    print_str("Falcon Phone Mirror closed.\n");
    return 0;
}
