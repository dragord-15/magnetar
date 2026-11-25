// ============================================================================
// Magnetar 2D Game Library (lib/game2d.mg)
// 2D game primitives built on top of lib/gui.mg (and optionally lib/image.mg).
//
// Provides:
//   - Basic drawing: line, rect, circle, triangle
//   - Math/helpers: clamp, abs, lerp
//   - Vec2i, Rect2D
//   - Sprite2D (color or Image-based), Transform2D
//   - Camera2D
//   - Tilemap2D
//   - Animation2D (frame timing)
//   - Input helpers (keyboard/mouse wrappers over gui)
//
// Usage:
//   use "lib/gui.mg";
//   use "lib/image.mg";   // optional, for image sprites
//   use "lib/game2d.mg";
//   ...
//   g2d_init_window(800,600,"My Game");
//   while (g2d_running()) { g2d_begin(); ... g2d_end(); }
//
// Note: This library expects gui.mg to be available in the same compilation
// unit (include gui.mg before or let this module include it).
// ============================================================================

use "lib/gui.mg";

// -----------------------------
// Math / helpers
// -----------------------------
fn g2d_abs(int v) -> int { if (v < 0) { return -v; } return v; }
fn g2d_min(int a, int b) -> int { if (a < b) { return a; } return b; }
fn g2d_max(int a, int b) -> int { if (a > b) { return a; } return b; }
fn g2d_clamp(int v, int lo, int hi) -> int { if (v < lo) { return lo; } if (v > hi) { return hi; } return v; }
fn g2d_lerp(int a, int b, int t, int denom) -> int {
    if (denom <= 0) { return a; }
    return a + (b - a) * t / denom;
}
fn g2d_sign(int v) -> int { if (v < 0) { return -1; } if (v > 0) { return 1; } return 0; }

// -----------------------------
// Basic types
// -----------------------------
struct Vec2i { int x; int y; }
struct Rect2D { int x; int y; int w; int h; }

fn v2i(int x, int y) -> Vec2i { Vec2i v; v.x = x; v.y = y; return v; }
fn rect2d(int x, int y, int w, int h) -> Rect2D { Rect2D r; r.x = x; r.y = y; r.w = w; r.h = h; return r; }

fn g2d_rects_overlap(Rect2D a, Rect2D b) -> bool {
    if (a.x + a.w <= b.x) { return false; }
    if (b.x + b.w <= a.x) { return false; }
    if (a.y + a.h <= b.y) { return false; }
    if (b.y + b.h <= a.y) { return false; }
    return true;
}

fn g2d_rect_contains(Rect2D r, int px, int py) -> bool {
    if (px < r.x || py < r.y) { return false; }
    if (px >= r.x + r.w || py >= r.y + r.h) { return false; }
    return true;
}

// -----------------------------
// Window / frame helpers
// -----------------------------
fn g2d_init_window(int w, int h, string title) -> int {
    return gui_init_window(w, h, title);
}

fn g2d_running() -> bool {
    return gui_close_requested() == 0;
}

fn g2d_begin() -> void {
    gui_read_mouse();
}

fn g2d_clear(int color) -> void {
    gui_clear(color);
}

fn g2d_end() -> void {
    gui_present();
}

fn g2d_present() -> void {
    gui_present();
}

fn g2d_shutdown() -> void {
    gui_shutdown();
}

fn g2d_screen_w() -> int { return G_XRES; }
fn g2d_screen_h() -> int { return G_YRES; }

// -----------------------------
// Drawing primitives
// -----------------------------
fn g2d_pixel(int x, int y, int color) -> void { gui_put_pixel(x, y, color); }

fn g2d_fill_rect(int x, int y, int w, int h, int color) -> void { gui_fill_rect(x, y, w, h, color); }

fn g2d_draw_rect(int x, int y, int w, int h, int color) -> void { gui_draw_rect(x, y, w, h, color); }

fn g2d_draw_line(int x0, int y0, int x1, int y1, int color) -> void {
    int dx = g2d_abs(x1 - x0);
    int sx = -1;
    if (x0 < x1) { sx = 1; }
    int dy = -g2d_abs(y1 - y0);
    int sy = -1;
    if (y0 < y1) { sy = 1; }
    int err = dx + dy;
    int x = x0;
    int y = y0;
    while (true) {
        gui_put_pixel(x, y, color);
        if (x == x1 && y == y1) { break; }
        int e2 = err + err;
        if (e2 >= dy) {
            if (x == x1) { break; }
            err = err + dy;
            x = x + sx;
        }
        if (e2 <= dx) {
            if (y == y1) { break; }
            err = err + dx;
            y = y + sy;
        }
    }
}

fn g2d_draw_hline(int x, int y, int w, int color) -> void {
    if (w <= 0) { return; }
    gui_fill_rect(x, y, w, 1, color);
}

fn g2d_draw_vline(int x, int y, int h, int color) -> void {
    if (h <= 0) { return; }
    gui_fill_rect(x, y, 1, h, color);
}

fn g2d_draw_circle(int cx, int cy, int r, int color) -> void {
    int x = r;
    int y = 0;
    int err = 0;
    while (x >= y) {
        gui_put_pixel(cx + x, cy + y, color);
        gui_put_pixel(cx + y, cy + x, color);
        gui_put_pixel(cx - y, cy + x, color);
        gui_put_pixel(cx - x, cy + y, color);
        gui_put_pixel(cx - x, cy - y, color);
        gui_put_pixel(cx - y, cy - x, color);
        gui_put_pixel(cx + y, cy - x, color);
        gui_put_pixel(cx + x, cy - y, color);
        if (err <= 0) { y = y + 1; err = err + 2*y + 1; }
        if (err > 0) { x = x - 1; err = err - 2*x + 1; }
    }
}

fn g2d_fill_circle(int cx, int cy, int r, int color) -> void {
    gui_fill_circle(cx, cy, r, color);
}

fn g2d_draw_triangle(int x0, int y0, int x1, int y1, int x2, int y2, int color) -> void {
    g2d_draw_line(x0, y0, x1, y1, color);
    g2d_draw_line(x1, y1, x2, y2, color);
    g2d_draw_line(x2, y2, x0, y0, color);
}

fn g2d_fill_triangle_flat(int x0, int y0, int x1, int y1, int x2, int y2, int color) -> void {
    // Sort by y
    if (y0 > y1) { int tx=x0; x0=x1; x1=tx; int ty=y0; y0=y1; y1=ty; }
    if (y1 > y2) { int tx=x1; x1=x2; x2=tx; int ty=y1; y1=y2; y2=ty; }
    if (y0 > y1) { int tx=x0; x0=x1; x1=tx; int ty=y0; y0=y1; y1=ty; }
    if (y2 == y0) { return; }
    int y = y0;
    while (y <= y2) {
        bool second = (y > y1) || (y1 == y0);
        int seg = y2 - y0;
        if (seg == 0) { seg = 1; }
        int xa = x0 + (x2 - x0) * (y - y0) / seg;
        int xb = xa;
        if (!second) {
            int seg1 = y1 - y0;
            if (seg1 != 0) { xb = x0 + (x1 - x0) * (y - y0) / seg1; }
            else { xb = x1; }
        } else {
            int seg2 = y2 - y1;
            if (seg2 != 0) { xb = x1 + (x2 - x1) * (y - y1) / seg2; }
            else { xb = x2; }
        }
        if (xa > xb) { int t = xa; xa = xb; xb = t; }
        gui_fill_rect(xa, y, xb - xa + 1, 1, color);
        y = y + 1;
    }
}

fn g2d_text(int x, int y, string text, int color) -> void {
    gui_draw_text_fg(x, y, text, color, 255);
}

// -----------------------------
// Camera
// -----------------------------
struct Camera2D {
    int x;
    int y;
    int w;
    int h;
}

fn camera2d_new(int w, int h) -> Camera2D {
    Camera2D c; c.x = 0; c.y = 0; c.w = w; c.h = h; return c;
}

fn camera2d_world_to_screen(Camera2D* cam, int wx, int wy, int* sx, int* sy) -> void {
    *sx = wx - cam.x;
    *sy = wy - cam.y;
}

fn camera2d_follow(Camera2D* cam, int tx, int ty, int lerp_num, int lerp_den) -> void {
    int target_x = tx - cam.w / 2;
    int target_y = ty - cam.h / 2;
    if (lerp_den <= 0) { cam.x = target_x; cam.y = target_y; return; }
    cam.x = cam.x + (target_x - cam.x) * lerp_num / lerp_den;
    cam.y = cam.y + (target_y - cam.y) * lerp_num / lerp_den;
}

// -----------------------------
// Sprite / Entity
// -----------------------------
struct Sprite2D {
    int x;
    int y;
    int w;
    int h;
    int vx;
    int vy;
    int color;
    int visible;
    int solid;
    int frame;
    int frame_count;
    int frame_w;
    int frame_h;
    int anim_timer;
    int anim_speed; // ticks per frame
    int flip_x;
    int flip_y;
}

fn sprite2d_new(int x, int y, int w, int h, int color) -> Sprite2D {
    Sprite2D s;
    s.x = x; s.y = y; s.w = w; s.h = h;
    s.vx = 0; s.vy = 0;
    s.color = color;
    s.visible = 1; s.solid = 1;
    s.frame = 0; s.frame_count = 1; s.frame_w = w; s.frame_h = h;
    s.anim_timer = 0; s.anim_speed = 6;
    s.flip_x = 0; s.flip_y = 0;
    return s;
}

fn sprite2d_bounds(Sprite2D* s) -> Rect2D { return rect2d(s.x, s.y, s.w, s.h); }

fn sprite2d_move(Sprite2D* s) -> void {
    s.x = s.x + s.vx;
    s.y = s.y + s.vy;
}

fn sprite2d_update_anim(Sprite2D* s) -> void {
    if (s.frame_count <= 1) { return; }
    s.anim_timer = s.anim_timer + 1;
    if (s.anim_timer >= s.anim_speed) {
        s.anim_timer = 0;
        s.frame = s.frame + 1;
        if (s.frame >= s.frame_count) { s.frame = 0; }
    }
}

fn sprite2d_draw(Sprite2D* s, Camera2D* cam) -> void {
    if (s.visible == 0) { return; }
    int sx = s.x; int sy = s.y;
    if (cam != null) { sx = s.x - cam.x; sy = s.y - cam.y; }
    gui_fill_rect(sx, sy, s.w, s.h, s.color);
}

fn sprite2d_draw_outline(Sprite2D* s, Camera2D* cam, int outline) -> void {
    if (s.visible == 0) { return; }
    int sx = s.x; int sy = s.y;
    if (cam != null) { sx = s.x - cam.x; sy = s.y - cam.y; }
    gui_fill_rect(sx, sy, s.w, s.h, s.color);
    gui_draw_rect(sx, sy, s.w, s.h, outline);
}

fn sprite2d_collides(Sprite2D* a, Sprite2D* b) -> bool {
    if (a.solid == 0 || b.solid == 0) { return false; }
    Rect2D ra = sprite2d_bounds(a);
    Rect2D rb = sprite2d_bounds(b);
    return g2d_rects_overlap(ra, rb);
}

// Image-based sprite drawing (requires lib/image.mg Image struct/layout)
// Draws src image region scaled 1:1 at screen position (with optional camera).
// Color key: pixels with alpha == 0 are skipped.
struct ImageSprite2D {
    char* img_data;
    int img_w;
    int img_h;
    int x;
    int y;
    int src_x;
    int src_y;
    int w;
    int h;
    int visible;
}

fn imgsprite2d_new(char* data, int img_w, int img_h, int x, int y, int w, int h) -> ImageSprite2D {
    ImageSprite2D s;
    s.img_data = data; s.img_w = img_w; s.img_h = img_h;
    s.x = x; s.y = y; s.src_x = 0; s.src_y = 0; s.w = w; s.h = h; s.visible = 1;
    return s;
}

fn imgsprite2d_draw(ImageSprite2D* s, Camera2D* cam) -> void {
    if (s.visible == 0 || s.img_data == null) { return; }
    int dx0 = s.x; int dy0 = s.y;
    if (cam != null) { dx0 = s.x - cam.x; dy0 = s.y - cam.y; }
    int y = 0;
    while (y < s.h) {
        int sy = s.src_y + y;
        if (sy >= 0 && sy < s.img_h) {
            int x = 0;
            while (x < s.w) {
                int sx = s.src_x + x;
                if (sx >= 0 && sx < s.img_w) {
                    int idx = (sy * s.img_w + sx) * 4;
                    int r = cast<int>(*(s.img_data + idx)); if (r < 0) { r = r + 256; }
                    int g = cast<int>(*(s.img_data + idx + 1)); if (g < 0) { g = g + 256; }
                    int b = cast<int>(*(s.img_data + idx + 2)); if (b < 0) { b = b + 256; }
                    int a = cast<int>(*(s.img_data + idx + 3)); if (a < 0) { a = a + 256; }
                    if (a > 0) {
                        int color = r * 65536 + g * 256 + b;
                        gui_put_pixel(dx0 + x, dy0 + y, color);
                    }
                }
                x = x + 1;
            }
        }
        y = y + 1;
    }
}

// -----------------------------
// Tilemap
// -----------------------------
struct Tilemap2D {
    int* tiles;    // map_w*map_h tile ids (0 = empty)
    int map_w;
    int map_h;
    int tile_w;
    int tile_h;
    int* colors;   // palette: color per tile id
    int palette_size;
}

fn tilemap2d_new(int map_w, int map_h, int tile_w, int tile_h) -> Tilemap2D {
    Tilemap2D tm;
    tm.map_w = map_w; tm.map_h = map_h; tm.tile_w = tile_w; tm.tile_h = tile_h;
    int n = map_w * map_h;
    tm.tiles = alloc<int>(n);
    int i = 0; while (i < n) { *(tm.tiles + i) = 0; i = i + 1; }
    tm.colors = alloc<int>(64);
    tm.palette_size = 64;
    i = 0; while (i < 64) { *(tm.colors + i) = gui_rgb(80,80,80); i = i + 1; }
    return tm;
}

fn tilemap2d_set(Tilemap2D* tm, int tx, int ty, int id) -> void {
    if (tx < 0 || ty < 0 || tx >= tm.map_w || ty >= tm.map_h) { return; }
    *(tm.tiles + ty * tm.map_w + tx) = id;
}

fn tilemap2d_get(Tilemap2D* tm, int tx, int ty) -> int {
    if (tx < 0 || ty < 0 || tx >= tm.map_w || ty >= tm.map_h) { return 0; }
    return *(tm.tiles + ty * tm.map_w + tx);
}

fn tilemap2d_set_color(Tilemap2D* tm, int id, int color) -> void {
    if (id < 0 || id >= tm.palette_size) { return; }
    *(tm.colors + id) = color;
}

fn tilemap2d_draw(Tilemap2D* tm, Camera2D* cam) -> void {
    int y = 0;
    while (y < tm.map_h) {
        int x = 0;
        while (x < tm.map_w) {
            int id = *(tm.tiles + y * tm.map_w + x);
            if (id > 0) {
                int wx = x * tm.tile_w;
                int wy = y * tm.tile_h;
                int sx = wx; int sy = wy;
                if (cam != null) { sx = wx - cam.x; sy = wy - cam.y; }
                // cull
                if (sx + tm.tile_w >= 0 && sy + tm.tile_h >= 0 && sx < g2d_screen_w() && sy < g2d_screen_h()) {
                    int col = gui_rgb(120,120,120);
                    if (id < tm.palette_size) { col = *(tm.colors + id); }
                    gui_fill_rect(sx, sy, tm.tile_w, tm.tile_h, col);
                }
            }
            x = x + 1;
        }
        y = y + 1;
    }
}

fn tilemap2d_collides_rect(Tilemap2D* tm, Rect2D r) -> bool {
    int x0 = r.x / tm.tile_w;
    int y0 = r.y / tm.tile_h;
    int x1 = (r.x + r.w - 1) / tm.tile_w;
    int y1 = (r.y + r.h - 1) / tm.tile_h;
    int y = y0;
    while (y <= y1) {
        int x = x0;
        while (x <= x1) {
            if (tilemap2d_get(tm, x, y) > 0) { return true; }
            x = x + 1;
        }
        y = y + 1;
    }
    return false;
}

// -----------------------------
// Animation
// -----------------------------
struct Animation2D {
    int start_frame;
    int end_frame;
    int current;
    int speed;
    int timer;
    int loop;
    int playing;
}

fn anim2d_new(int start_f, int end_f, int speed, int loop) -> Animation2D {
    Animation2D a;
    a.start_frame = start_f; a.end_frame = end_f; a.current = start_f;
    a.speed = speed; a.timer = 0; a.loop = loop; a.playing = 1;
    return a;
}

fn anim2d_update(Animation2D* a) -> int {
    if (a.playing == 0) { return a.current; }
    a.timer = a.timer + 1;
    if (a.timer >= a.speed) {
        a.timer = 0;
        a.current = a.current + 1;
        if (a.current > a.end_frame) {
            if (a.loop == 1) { a.current = a.start_frame; }
            else { a.current = a.end_frame; a.playing = 0; }
        }
    }
    return a.current;
}

fn anim2d_reset(Animation2D* a) -> void {
    a.current = a.start_frame; a.timer = 0; a.playing = 1;
}

// -----------------------------
// Input helpers
// -----------------------------
fn g2d_key_poll() -> int { return gui_key_poll(); }
fn g2d_key_available() -> int { return gui_key_available(); }
fn g2d_key_ctrl() -> int { return gui_key_ctrl(); }
fn g2d_key_shift() -> int { return gui_key_shift(); }
fn g2d_mouse_x() -> int { return gui_mouse_x(); }
fn g2d_mouse_y() -> int { return gui_mouse_y(); }
fn g2d_mouse_left() -> int { return gui_mouse_left(); }
fn g2d_mouse_clicked() -> int { return gui_mouse_clicked(); }
fn g2d_mouse_right() -> int { return gui_mouse_right(); }
fn g2d_mouse_wheel() -> int { return gui_mouse_wheel(); }

// Simple key state tracker (call g2d_input_update each frame)
struct Input2D {
    int up;
    int down;
    int left;
    int right;
    int action;
    int action2;
    int quit;
    int last_key;
}

fn input2d_new() -> Input2D {
    Input2D inp;
    inp.up = 0; inp.down = 0; inp.left = 0; inp.right = 0;
    inp.action = 0; inp.action2 = 0; inp.quit = 0; inp.last_key = -1;
    return inp;
}

fn input2d_update(Input2D* inp) -> void {
    inp.action = 0; inp.action2 = 0; // edge-like resets per frame for actions
    while (gui_key_available() > 0) {
        int k = gui_key_poll();
        inp.last_key = k;
        if (k == 27) { inp.quit = 1; }
        if (k == 128 || k == 119 || k == 87) { inp.up = 1; }      // up / w
        if (k == 129 || k == 115 || k == 83) { inp.down = 1; }    // down / s
        if (k == 130 || k == 97 || k == 65) { inp.left = 1; }     // left / a
        if (k == 131 || k == 100 || k == 68) { inp.right = 1; }   // right / d
        if (k == 32 || k == 10) { inp.action = 1; }               // space/enter
        if (k == 122 || k == 90) { inp.action2 = 1; }             // z
        // key releases not tracked by gui_key_poll; provide clear helpers
    }
}

fn input2d_clear_dirs(Input2D* inp) -> void {
    inp.up = 0; inp.down = 0; inp.left = 0; inp.right = 0;
}

// -----------------------------
// Utility: simple timer
// -----------------------------
struct Timer2D {
    int frame;
}

fn timer2d_new() -> Timer2D { Timer2D t; t.frame = 0; return t; }
fn timer2d_tick(Timer2D* t) -> void { t.frame = t.frame + 1; }
fn timer2d_every(Timer2D* t, int n) -> bool {
    if (n <= 0) { return false; }
    return (t.frame - (t.frame / n) * n) == 0;
}
