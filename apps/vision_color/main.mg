// vision_color/main.mg - Fast GUI camera color object recognition (Magnetar)
// Detects colored materials/objects from camera, draws bounding box, shows size.
// Optimized: continuous ffmpeg stream (no per-frame spawn), reused buffers, scaled view.
// Build: ./magc vision_color/main.mg -o build/vision_color
// Run:   ./build/vision_color [device] [width] [height]
// Requires: X11 or framebuffer display, ffmpeg, V4L2 camera (/dev/video0)

use "lib/gui.mg";
use "lib/image.mg";
use "lib/vision.mg";

extern fn print_str(string s) -> void;
extern fn sleep_ms(int ms) -> void;

// ---- helpers ----
fn vc_byte(char* p, int i) -> int {
    int v = cast<int>(*(p + i));
    if (v < 0) { v = v + 256; }
    return v;
}

fn vc_abs(int x) -> int { if (x < 0) { return 0 - x; } return x; }

fn vc_i2s(int n, char* buf) -> void {
    if (n == 0) { *(buf) = 48; *(buf + 1) = 0; return; }
    int neg = 0;
    int v = n;
    if (v < 0) { neg = 1; v = 0 - v; }
    char* tmp = alloc<char>(24);
    int i = 0;
    while (v > 0) {
        int d = v - (v / 10) * 10;
        *(tmp + i) = cast<char>(48 + d);
        v = v / 10;
        i = i + 1;
    }
    int out = 0;
    if (neg == 1) { *(buf + out) = 45; out = out + 1; }
    int j = i - 1;
    while (j >= 0) {
        *(buf + out) = *(tmp + j);
        out = out + 1;
        j = j - 1;
    }
    *(buf + out) = 0;
    free(tmp);
}

fn vc_append(char* dst, int pos, string s) -> int {
    if (s == null) { return pos; }
    char* p = cast<char*>(s);
    int i = 0;
    while (*(p + i) != 0) {
        *(dst + pos) = *(p + i);
        pos = pos + 1;
        i = i + 1;
    }
    *(dst + pos) = 0;
    return pos;
}

fn vc_append_int(char* dst, int pos, int n) -> int {
    char* b = alloc<char>(24);
    vc_i2s(n, b);
    pos = vc_append(dst, pos, cast<string>(b));
    free(b);
    return pos;
}

// draw scaled camera frame into GUI backbuffer at (ox,oy) with size (dw,dh)
// fast direct blit (avoids per-pixel function call/bounds overhead)
fn vc_draw_image_scaled(Image* img, int ox, int oy, int dw, int dh) -> void {
    if (img == null) { return; }
    if (G_DRAW <= 0) { return; }
    int sw = img.width;
    int sh = img.height;
    int xres = G_XRES;
    int yres = G_YRES;
    char* dst_base = cast<char*>(G_DRAW);
    char* src_base = img.data;
    int y = 0;
    while (y < dh) {
        int dy = oy + y;
        if (dy >= 0 && dy < yres) {
            int sy = y * sh / dh;
            if (sy >= sh) { sy = sh - 1; }
            int srow = sy * img.stride;
            int drow = dy * xres * 4;
            int x = 0;
            while (x < dw) {
                int dx = ox + x;
                if (dx >= 0 && dx < xres) {
                    int sx = x * sw / dw;
                    if (sx >= sw) { sx = sw - 1; }
                    int soff = srow + sx * 4;
                    int doff = drow + dx * 4;
                    // framebuffer is B,G,R,X; source image is R,G,B,A
                    *(dst_base + doff) = *(src_base + soff + 2);
                    *(dst_base + doff + 1) = *(src_base + soff + 1);
                    *(dst_base + doff + 2) = *(src_base + soff);
                    *(dst_base + doff + 3) = 0;
                }
                x = x + 1;
            }
        }
        y = y + 1;
    }
}

// draw thick rectangle on image (clamped)
fn vc_draw_box(Image* img, int bx, int by, int bw, int bh, int r, int g, int b, int thick) -> void {
    if (img == null) { return; }
    int t = 0;
    while (t < thick) {
        int x0 = bx + t;
        int y0 = by + t;
        int x1 = bx + bw - 1 - t;
        int y1 = by + bh - 1 - t;
        if (x0 < 0) { x0 = 0; }
        if (y0 < 0) { y0 = 0; }
        if (x1 >= img.width) { x1 = img.width - 1; }
        if (y1 >= img.height) { y1 = img.height - 1; }
        int x = x0;
        while (x <= x1) {
            image_set_pixel(img, x, y0, r, g, b, 255);
            image_set_pixel(img, x, y1, r, g, b, 255);
            x = x + 1;
        }
        int y = y0;
        while (y <= y1) {
            image_set_pixel(img, x0, y, r, g, b, 255);
            image_set_pixel(img, x1, y, r, g, b, 255);
            y = y + 1;
        }
        t = t + 1;
    }
    // center cross
    int cx = bx + bw / 2;
    int cy = by + bh / 2;
    int k = -5;
    while (k <= 5) {
        if (cx + k >= 0 && cx + k < img.width && cy >= 0 && cy < img.height) {
            image_set_pixel(img, cx + k, cy, r, g, b, 255);
        }
        if (cy + k >= 0 && cy + k < img.height && cx >= 0 && cx < img.width) {
            image_set_pixel(img, cx, cy + k, r, g, b, 255);
        }
        k = k + 1;
    }
}

// detect by selected mode
fn vc_detect(Image* img, VisionMotion* motion, int mode, int min_area, VisionResult* res) -> int {
    if (mode == 1) {
        return vision_detect_red(img, min_area, res);
    } else if (mode == 2) {
        return vision_detect_green(img, min_area, res);
    } else if (mode == 3) {
        return vision_detect_blue(img, min_area, res);
    } else if (mode == 4) {
        // yellow
        return vision_detect_hsv_range(img, 20, 40, 40, 45, 100, 100, min_area, 4, res);
    } else if (mode == 5) {
        return vision_motion_detect(motion, img, min_area, res);
    }
    vision_result_reset(res);
    return 0;
}

fn vc_mode_name(int mode) -> string {
    if (mode == 1) { return "RED"; }
    if (mode == 2) { return "GREEN"; }
    if (mode == 3) { return "BLUE"; }
    if (mode == 4) { return "YELLOW"; }
    if (mode == 5) { return "MOTION"; }
    return "NONE";
}

fn vc_mode_color(int mode) -> int {
    if (mode == 1) { return gui_rgb(255, 80, 80); }
    if (mode == 2) { return gui_rgb(80, 255, 120); }
    if (mode == 3) { return gui_rgb(80, 160, 255); }
    if (mode == 4) { return gui_rgb(255, 230, 60); }
    if (mode == 5) { return gui_rgb(120, 240, 255); }
    return gui_rgb(255, 255, 255);
}

fn vc_text(int x, int y, string t, int color) -> void {
    gui_draw_text_fg(x, y, t, color, 255);
}

fn vc_parse_int(char* s) -> int {
    if (s == null) { return 0; }
    int i = 0;
    int n = 0;
    while (*(s + i) != 0) {
        int c = cast<int>(*(s + i));
        if (c < 0) { c = c + 256; }
        if (c >= 48 && c <= 57) { n = n * 10 + (c - 48); }
        i = i + 1;
    }
    return n;
}

fn main(int argc, char** argv) -> int {
    string dev = "/dev/video0";
    int cam_w = 320;
    int cam_h = 240;
    if (argc > 1) { dev = cast<string>(argv[1]); }
    if (argc > 2) { int w = vc_parse_int(argv[2]); if (w >= 160) { cam_w = w; } }
    if (argc > 3) { int h = vc_parse_int(argv[3]); if (h >= 120) { cam_h = h; } }

    // Scaled display area (camera view). Bigger -> fills window.
    int disp_w = 640;
    int disp_h = 480;
    if (cam_w > 0 && cam_h > 0) {
        // keep aspect-ish scaling from capture
        disp_h = disp_w * cam_h / cam_w;
        if (disp_h < 360) { disp_h = 360; }
        if (disp_h > 520) { disp_h = 520; }
    }
    int vid_x = 16;
    int vid_y = 58;
    int panel_x = vid_x + disp_w + 24;
    int win_w = panel_x + 300;
    int win_h = vid_y + disp_h + 54;
    if (win_w < 980) { win_w = 980; }
    if (win_h < 560) { win_h = 560; }

    if (gui_init_window(win_w, win_h, "Magnetar Vision - Color Object Recognition") < 0) {
        print_str("Failed to initialize GUI.\n");
        return 1;
    }

    if (vision_ffmpeg_available() == false) {
        gui_clear(gui_rgb(20, 20, 30));
        vc_text(20, 20, "ffmpeg not found. Install ffmpeg to use camera capture.", gui_rgb(255, 120, 120));
        gui_present();
        while (gui_close_requested() == 0) {
            gui_read_mouse();
            while (gui_key_available() > 0) { int k = gui_key_poll(); if (k == 27 || k == 113 || k == 81) { gui_shutdown(); return 1; } }
            sleep_ms(30);
        }
        gui_shutdown();
        return 1;
    }
    if (vision_camera_available(dev) == false) {
        gui_clear(gui_rgb(20, 20, 30));
        vc_text(20, 20, "Camera device not available:", gui_rgb(255, 120, 120));
        vc_text(20, 44, dev, gui_rgb(220, 180, 120));
        gui_present();
        while (gui_close_requested() == 0) {
            gui_read_mouse();
            while (gui_key_available() > 0) { int k = gui_key_poll(); if (k == 27 || k == 113 || k == 81) { gui_shutdown(); return 1; } }
            sleep_ms(30);
        }
        gui_shutdown();
        return 1;
    }

    int mode = 5; // start in motion tracking mode
    int min_area = 80;
    int motion_thresh = 30;
    int px_per_cm = 0;
    int running = 1;

    VisionResult res;
    vision_result_init(&res, 24);

    Image* frame = image_new(cam_w, cam_h);
    if (frame == null) {
        gui_shutdown();
        print_str("Failed to allocate frame.\n");
        return 1;
    }

    VisionMotion motion;
    vision_motion_init(&motion, cam_w, cam_h, motion_thresh);

    VisionStream vs;
    vision_stream_init(&vs);
    int stream_ok = 0;
    if (vision_stream_open(&vs, dev, cam_w, cam_h) == true) { stream_ok = 1; }

    char* line = alloc<char>(256);
    int fail_streak = 0;

    while (running == 1 && gui_close_requested() == 0) {
        gui_read_mouse();
        while (gui_key_available() > 0) {
            int k = gui_key_poll();
            if (k == 27 || k == 113 || k == 81) { running = 0; }
            else if (k == 49 || k == 114 || k == 82) { mode = 1; } // 1/r
            else if (k == 50 || k == 103 || k == 71) { mode = 2; } // 2/g
            else if (k == 51 || k == 98  || k == 66) { mode = 3; } // 3/b
            else if (k == 52 || k == 121 || k == 89) { mode = 4; } // 4/y
            else if (k == 53 || k == 109 || k == 77) { mode = 5; vision_motion_reset(&motion); } // 5/m
            else if (k == 44) { if (motion_thresh > 6) { motion_thresh = motion_thresh - 4; motion.threshold = motion_thresh; } } // ,
            else if (k == 46) { motion_thresh = motion_thresh + 4; motion.threshold = motion_thresh; } // .
            else if (k == 43 || k == 61) { px_per_cm = px_per_cm + 1; } // +
            else if (k == 45 || k == 95) { if (px_per_cm > 0) { px_per_cm = px_per_cm - 1; } } // -
            else if (k == 91) { if (min_area > 10) { min_area = min_area - 10; } } // [
            else if (k == 93) { min_area = min_area + 10; } // ]
        }
        if (running == 0) { break; }

        gui_clear(gui_rgb(22, 26, 34));

        // header
        vc_text(16, 14, "Vision Tracking - moving objects (camera)", gui_rgb(240, 245, 255));
        int p = 0;
        p = vc_append(line, 0, "Mode[1-5,M=motion]: ");
        p = vc_append(line, p, vc_mode_name(mode));
        if (mode == 5) {
            p = vc_append(line, p, "  sens(,/.): ");
            p = vc_append_int(line, p, motion_thresh);
        }
        p = vc_append(line, p, "  min_area([/]): ");
        p = vc_append_int(line, p, min_area);
        p = vc_append(line, p, "  px/cm(+/-): ");
        if (px_per_cm > 0) { p = vc_append_int(line, p, px_per_cm); }
        else { p = vc_append(line, p, "off"); }
        p = vc_append(line, p, "  src: ");
        p = vc_append_int(line, p, cam_w); p = vc_append(line, p, "x"); p = vc_append_int(line, p, cam_h);
        vc_text(16, 34, cast<string>(line), vc_mode_color(mode));

        bool got = false;
        if (stream_ok == 1) {
            got = vision_stream_read(&vs, frame);
            if (got == false) { got = vision_stream_read(&vs, frame); }
            if (got == false) {
                vision_stream_close(&vs);
                stream_ok = 0;
            }
        }
        if (stream_ok == 0) {
            if (vision_stream_open(&vs, dev, cam_w, cam_h) == true) {
                stream_ok = 1;
                vision_motion_reset(&motion);
                got = vision_stream_read(&vs, frame);
            } else {
                sleep_ms(120);
            }
        }
        if (got == true) { fail_streak = 0; }
        else { fail_streak = fail_streak + 1; }

        if (got == true) {
            vc_detect(frame, &motion, mode, min_area, &res);

            int bi = vision_find_largest(&res);
            int i = 0;
            while (i < res.count) {
                VisionObject o = vision_get_object(&res, i);
                int rr = 80; int gg = 255; int bb = 80;
                int th = 2;
                if (i == bi) { rr = 255; gg = 240; bb = 60; th = 3; }
                vc_draw_box(frame, o.x, o.y, o.w, o.h, rr, gg, bb, th);
                i = i + 1;
            }

            vc_draw_image_scaled(frame, vid_x, vid_y, disp_w, disp_h);
            gui_draw_rect(vid_x - 1, vid_y - 1, disp_w + 2, disp_h + 2, gui_rgb(80, 90, 110));

            // info panel
            int px = panel_x;
            int py = vid_y;
            vc_text(px, py, "Detections:", gui_rgb(230, 230, 230)); py = py + 22;
            p = vc_append(line, 0, "Count: ");
            p = vc_append_int(line, p, res.count);
            vc_text(px, py, cast<string>(line), gui_rgb(200, 210, 220)); py = py + 26;

            if (res.count > 0 && bi >= 0) {
                VisionObject obj = vision_get_object(&res, bi);
                vc_text(px, py, "Largest object:", gui_rgb(255, 240, 120)); py = py + 22;

                p = vc_append(line, 0, "BBox: x="); p = vc_append_int(line,p,obj.x);
                p = vc_append(line,p," y="); p = vc_append_int(line,p,obj.y);
                p = vc_append(line,p," w="); p = vc_append_int(line,p,obj.w);
                p = vc_append(line,p," h="); p = vc_append_int(line,p,obj.h);
                vc_text(px, py, cast<string>(line), gui_rgb(210,220,230)); py = py + 20;

                p = vc_append(line, 0, "Center: ("); p = vc_append_int(line,p,obj.cx);
                p = vc_append(line,p,", "); p = vc_append_int(line,p,obj.cy); p = vc_append(line,p,")");
                vc_text(px, py, cast<string>(line), gui_rgb(210,220,230)); py = py + 20;

                p = vc_append(line, 0, "Area: "); p = vc_append_int(line,p,obj.area); p = vc_append(line,p," px^2");
                vc_text(px, py, cast<string>(line), gui_rgb(210,220,230)); py = py + 20;

                p = vc_append(line, 0, "Length(H): "); p = vc_append_int(line,p,obj.h); p = vc_append(line,p," px");
                vc_text(px, py, cast<string>(line), gui_rgb(160,255,180)); py = py + 20;
                p = vc_append(line, 0, "Width(W):  "); p = vc_append_int(line,p,obj.w); p = vc_append(line,p," px");
                vc_text(px, py, cast<string>(line), gui_rgb(160,255,180)); py = py + 20;

                if (px_per_cm > 0) {
                    int h_cm10 = obj.h * 10 / px_per_cm;
                    int w_cm10 = obj.w * 10 / px_per_cm;
                    p = vc_append(line, 0, "Size(cm): "); p = vc_append_int(line,p,w_cm10/10);
                    p = vc_append(line,p,"."); p = vc_append_int(line,p,vc_abs(w_cm10 - (w_cm10/10)*10));
                    p = vc_append(line,p," x "); p = vc_append_int(line,p,h_cm10/10);
                    p = vc_append(line,p,"."); p = vc_append_int(line,p,vc_abs(h_cm10 - (h_cm10/10)*10));
                    vc_text(px, py, cast<string>(line), gui_rgb(255,220,140)); py = py + 20;
                } else {
                    vc_text(px, py, "Size(cm): set px/cm with +/-", gui_rgb(150,150,160)); py = py + 20;
                }

                int steer = vision_object_steer_x(obj, frame.width);
                int ratio = vision_object_area_ratio(obj, frame.width, frame.height);
                p = vc_append(line, 0, "Steer: "); p = vc_append_int(line,p,steer);
                p = vc_append(line,p,"   ratio: "); p = vc_append_int(line,p,ratio); p = vc_append(line,p,"/1000");
                vc_text(px, py, cast<string>(line), gui_rgb(200,210,220)); py = py + 24;

                if (steer < -15) { vc_text(px, py, "Robot: TURN LEFT", gui_rgb(255,180,100)); }
                else if (steer > 15) { vc_text(px, py, "Robot: TURN RIGHT", gui_rgb(255,180,100)); }
                else {
                    if (ratio < 120) { vc_text(px, py, "Robot: MOVE FORWARD", gui_rgb(120,255,160)); }
                    else { vc_text(px, py, "Robot: TARGET NEAR/STOP", gui_rgb(255,120,120)); }
                }
                py = py + 22;
            } else {
                if (mode == 5) {
                    vc_text(px, py, "No movement detected.", gui_rgb(200, 140, 140)); py = py + 22;
                    vc_text(px, py, "Move an object in front of camera", gui_rgb(170,170,170)); py = py + 20;
                    vc_text(px, py, "or lower sensitivity with ','", gui_rgb(170,170,170)); py = py + 20;
                } else {
                    vc_text(px, py, "No object detected.", gui_rgb(200, 140, 140)); py = py + 22;
                    vc_text(px, py, "Point colored object at camera", gui_rgb(170,170,170)); py = py + 20;
                    vc_text(px, py, "or change mode (1-5).", gui_rgb(170,170,170)); py = py + 20;
                }
            }

            int hy = vid_y + disp_h + 14;
            vc_text(16, hy, "Keys: 5/M Motion  1-4 colors  ,/. sensitivity  [/] min_area  +/- px/cm  Q/ESC quit", gui_rgb(170,180,195));
            vc_text(16, hy + 18, "Motion mode tracks moving objects only; stationary ones fade into the background.", gui_rgb(140,150,165));
        } else {
            gui_fill_rect(vid_x, vid_y, disp_w, disp_h, gui_rgb(32, 38, 50));
            gui_draw_rect(vid_x - 1, vid_y - 1, disp_w + 2, disp_h + 2, gui_rgb(80, 90, 110));
            if (fail_streak > 8) {
                vc_text(vid_x + 16, vid_y + 20, "Camera not available - retrying...", gui_rgb(255, 220, 120));
                vc_text(vid_x + 16, vid_y + 44, dev, gui_rgb(220, 180, 120));
            } else {
                vc_text(vid_x + 16, vid_y + 20, "Waiting for next camera frame...", gui_rgb(255, 220, 120));
            }
            vc_text(panel_x, vid_y, "No frame from camera yet.", gui_rgb(200, 140, 140));
            int hy = vid_y + disp_h + 14;
            vc_text(16, hy, "Keys: Q/ESC quit", gui_rgb(170,180,195));
        }

        gui_present();
        // stream read itself paces to camera fps; no extra sleep needed
    }

    free(line);
    vision_stream_close(&vs);
    vision_motion_free(&motion);
    vision_result_free(&res);
    image_destroy(frame);
    gui_shutdown();
    print_str("Vision app closed.\n");
    return 0;
}
