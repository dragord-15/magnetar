// demo_game3d.mg - Minimal 3D software-render demo (standalone, no game3d lib)
// Build: ./magc examples/demo_game3d.mg -o build/demo_game3d
// Run:   ./build/demo_game3d   (requires GUI/X11)

use "lib/gui.mg";

fn absf(float v) -> float { if (v < 0.0) { return 0.0 - v; } return v; }

fn sinf(float x) -> float {
    float pi = 3.14159265;
    float tpi = 6.2831853;
    while (x > pi) { x = x - tpi; }
    while (x < 0.0 - pi) { x = x + tpi; }
    float x2 = x * x;
    float x3 = x2 * x;
    float x5 = x3 * x2;
    float x7 = x5 * x2;
    return x - x3 / 6.0 + x5 / 120.0 - x7 / 5040.0;
}

fn cosf(float x) -> float {
    float pi = 3.14159265;
    float tpi = 6.2831853;
    while (x > pi) { x = x - tpi; }
    while (x < 0.0 - pi) { x = x + tpi; }
    float x2 = x * x;
    float x4 = x2 * x2;
    float x6 = x4 * x2;
    return 1.0 - x2 / 2.0 + x4 / 24.0 - x6 / 720.0;
}

fn draw_line(int x0, int y0, int x1, int y1, int color) -> void {
    int dx = x1 - x0; if (dx < 0) { dx = 0 - dx; }
    int sx = -1; if (x0 < x1) { sx = 1; }
    int dy = y1 - y0; if (dy < 0) { dy = 0 - dy; }
    dy = 0 - dy;
    int sy = -1; if (y0 < y1) { sy = 1; }
    int err = dx + dy;
    int x = x0; int y = y0;
    int guard = 0;
    while (guard < 20000) {
        gui_put_pixel(x, y, color);
        if (x == x1) { if (y == y1) { break; } }
        int e2 = err + err;
        if (e2 >= dy) { if (x == x1) { break; } err = err + dy; x = x + sx; }
        if (e2 <= dx) { if (y == y1) { break; } err = err + dx; y = y + sy; }
        guard = guard + 1;
    }
}

fn fill_tri(int x0, int y0, int x1, int y1, int x2, int y2, int color) -> void {
    if (y0 > y1) { int tx=x0; x0=x1; x1=tx; int ty=y0; y0=y1; y1=ty; }
    if (y1 > y2) { int tx=x1; x1=x2; x2=tx; int ty=y1; y1=y2; y2=ty; }
    if (y0 > y1) { int tx=x0; x0=x1; x1=tx; int ty=y0; y0=y1; y1=ty; }
    if (y2 == y0) { return; }
    int y = y0;
    while (y <= y2) {
        bool second = (y > y1) || (y1 == y0);
        int seg = y2 - y0; if (seg == 0) { seg = 1; }
        int xa = x0 + (x2 - x0) * (y - y0) / seg;
        int xb = xa;
        if (!second) {
            int seg1 = y1 - y0;
            if (seg1 != 0) { xb = x0 + (x1 - x0) * (y - y0) / seg1; } else { xb = x1; }
        } else {
            int seg2 = y2 - y1;
            if (seg2 != 0) { xb = x1 + (x2 - x1) * (y - y1) / seg2; } else { xb = x2; }
        }
        if (xa > xb) { int t = xa; xa = xb; xb = t; }
        if (y >= 0 && y < 600) {
            int cx0 = xa; if (cx0 < 0) { cx0 = 0; }
            int cx1 = xb; if (cx1 >= 800) { cx1 = 799; }
            if (cx1 >= cx0) { gui_fill_rect(cx0, y, cx1 - cx0 + 1, 1, color); }
        }
        y = y + 1;
    }
}

fn shade(int color, int num, int den) -> int {
    if (den <= 0) { den = 1; }
    if (num < 0) { num = 0; }
    if (num > den) { num = den; }
    int r = color / 65536;
    int g = (color / 256) - r * 256;
    int b = color - (color / 256) * 256;
    r = r * num / den;
    g = g * num / den;
    b = b * num / den;
    return r * 65536 + g * 256 + b;
}

fn main() -> int {
    if (gui_init_window(800, 600, "Magnetar 3D Demo") < 0) {
        return 1;
    }

    float vx0 = -1.0; float vy0 = -1.0; float vz0 = -1.0;
    float vx1 =  1.0; float vy1 = -1.0; float vz1 = -1.0;
    float vx2 =  1.0; float vy2 =  1.0; float vz2 = -1.0;
    float vx3 = -1.0; float vy3 =  1.0; float vz3 = -1.0;
    float vx4 = -1.0; float vy4 = -1.0; float vz4 =  1.0;
    float vx5 =  1.0; float vy5 = -1.0; float vz5 =  1.0;
    float vx6 =  1.0; float vy6 =  1.0; float vz6 =  1.0;
    float vx7 = -1.0; float vy7 =  1.0; float vz7 =  1.0;

    float rx0 = 0.0; float ry0 = 0.0; float rz0 = 0.0;
    float rx1 = 0.0; float ry1 = 0.0; float rz1 = 0.0;
    float rx2 = 0.0; float ry2 = 0.0; float rz2 = 0.0;
    float rx3 = 0.0; float ry3 = 0.0; float rz3 = 0.0;
    float rx4 = 0.0; float ry4 = 0.0; float rz4 = 0.0;
    float rx5 = 0.0; float ry5 = 0.0; float rz5 = 0.0;
    float rx6 = 0.0; float ry6 = 0.0; float rz6 = 0.0;
    float rx7 = 0.0; float ry7 = 0.0; float rz7 = 0.0;

    int sx0 = 0; int sy0 = 0; int sx1 = 0; int sy1 = 0;
    int sx2 = 0; int sy2 = 0; int sx3 = 0; int sy3 = 0;
    int sx4 = 0; int sy4 = 0; int sx5 = 0; int sy5 = 0;
    int sx6 = 0; int sy6 = 0; int sx7 = 0; int sy7 = 0;

    // 12 triangles (indices a,b,c) and base colors
    int f0a=0; int f0b=1; int f0c=2; int f1a=0; int f1b=2; int f1c=3;
    int f2a=5; int f2b=4; int f2c=7; int f3a=5; int f3b=7; int f3c=6;
    int f4a=4; int f4b=0; int f4c=3; int f5a=4; int f5b=3; int f5c=7;
    int f6a=1; int f6b=5; int f6c=6; int f7a=1; int f7b=6; int f7c=2;
    int f8a=3; int f8b=2; int f8c=6; int f9a=3; int f9b=6; int f9c=7;
    int f10a=4; int f10b=5; int f10c=1; int f11a=4; int f11b=1; int f11c=0;

    int base = gui_rgb(90, 160, 255);
    float t = 0.0;

    while (gui_close_requested() == 0) {
        gui_read_mouse();
        while (gui_key_available() > 0) {
            int k = gui_key_poll();
            if (k == 27) {
                gui_shutdown();
                return 0;
            }
        }

        t = t + 0.03;
        float ca = cosf(t); float sa = sinf(t);
        float cb = cosf(t * 0.7); float sb = sinf(t * 0.7);

        // rotate & project each vertex
        float x = vx0; float y = vy0; float z = vz0;
        float x1r = x*ca + z*sa; float z1r = 0.0 - x*sa + z*ca; x = x1r; z = z1r;
        float y1r = y*cb - z*sb; float z2r = y*sb + z*cb; y = y1r; z = z2r;
        z = z + 4.0; rx0=x; ry0=y; rz0=z; sx0 = 400 + cast<int>(x * 260.0 / z); sy0 = 300 - cast<int>(y * 260.0 / z);

        x = vx1; y = vy1; z = vz1;
        x1r = x*ca + z*sa; z1r = 0.0 - x*sa + z*ca; x = x1r; z = z1r;
        y1r = y*cb - z*sb; z2r = y*sb + z*cb; y = y1r; z = z2r;
        z = z + 4.0; rx1=x; ry1=y; rz1=z; sx1 = 400 + cast<int>(x * 260.0 / z); sy1 = 300 - cast<int>(y * 260.0 / z);

        x = vx2; y = vy2; z = vz2;
        x1r = x*ca + z*sa; z1r = 0.0 - x*sa + z*ca; x = x1r; z = z1r;
        y1r = y*cb - z*sb; z2r = y*sb + z*cb; y = y1r; z = z2r;
        z = z + 4.0; rx2=x; ry2=y; rz2=z; sx2 = 400 + cast<int>(x * 260.0 / z); sy2 = 300 - cast<int>(y * 260.0 / z);

        x = vx3; y = vy3; z = vz3;
        x1r = x*ca + z*sa; z1r = 0.0 - x*sa + z*ca; x = x1r; z = z1r;
        y1r = y*cb - z*sb; z2r = y*sb + z*cb; y = y1r; z = z2r;
        z = z + 4.0; rx3=x; ry3=y; rz3=z; sx3 = 400 + cast<int>(x * 260.0 / z); sy3 = 300 - cast<int>(y * 260.0 / z);

        x = vx4; y = vy4; z = vz4;
        x1r = x*ca + z*sa; z1r = 0.0 - x*sa + z*ca; x = x1r; z = z1r;
        y1r = y*cb - z*sb; z2r = y*sb + z*cb; y = y1r; z = z2r;
        z = z + 4.0; rx4=x; ry4=y; rz4=z; sx4 = 400 + cast<int>(x * 260.0 / z); sy4 = 300 - cast<int>(y * 260.0 / z);

        x = vx5; y = vy5; z = vz5;
        x1r = x*ca + z*sa; z1r = 0.0 - x*sa + z*ca; x = x1r; z = z1r;
        y1r = y*cb - z*sb; z2r = y*sb + z*cb; y = y1r; z = z2r;
        z = z + 4.0; rx5=x; ry5=y; rz5=z; sx5 = 400 + cast<int>(x * 260.0 / z); sy5 = 300 - cast<int>(y * 260.0 / z);

        x = vx6; y = vy6; z = vz6;
        x1r = x*ca + z*sa; z1r = 0.0 - x*sa + z*ca; x = x1r; z = z1r;
        y1r = y*cb - z*sb; z2r = y*sb + z*cb; y = y1r; z = z2r;
        z = z + 4.0; rx6=x; ry6=y; rz6=z; sx6 = 400 + cast<int>(x * 260.0 / z); sy6 = 300 - cast<int>(y * 260.0 / z);

        x = vx7; y = vy7; z = vz7;
        x1r = x*ca + z*sa; z1r = 0.0 - x*sa + z*ca; x = x1r; z = z1r;
        y1r = y*cb - z*sb; z2r = y*sb + z*cb; y = y1r; z = z2r;
        z = z + 4.0; rx7=x; ry7=y; rz7=z; sx7 = 400 + cast<int>(x * 260.0 / z); sy7 = 300 - cast<int>(y * 260.0 / z);

        gui_clear(gui_rgb(18, 22, 34));

        // Draw 6 faces (2 tris each) with simple backface + painter ordering by avg z
        // face 0,1 (front)
        int ax = sx1-sx0; int ay = sy1-sy0; int bx = sx2-sx0; int by = sy2-sy0; int cz = ax*by - ay*bx;
        if (cz < 0) { fill_tri(sx0,sy0,sx1,sy1,sx2,sy2,shade(base,85,100)); fill_tri(sx0,sy0,sx2,sy2,sx3,sy3,shade(base,85,100)); draw_line(sx0,sy0,sx1,sy1,gui_rgb(230,240,255)); draw_line(sx1,sy1,sx2,sy2,gui_rgb(230,240,255)); draw_line(sx2,sy2,sx3,sy3,gui_rgb(230,240,255)); draw_line(sx3,sy3,sx0,sy0,gui_rgb(230,240,255)); }
        // face 2,3 (back)
        ax = sx4-sx5; ay = sy4-sy5; bx = sx7-sx5; by = sy7-sy5; cz = ax*by - ay*bx;
        if (cz < 0) { fill_tri(sx5,sy5,sx4,sy4,sx7,sy7,shade(base,45,100)); fill_tri(sx5,sy5,sx7,sy7,sx6,sy6,shade(base,45,100)); draw_line(sx4,sy4,sx5,sy5,gui_rgb(230,240,255)); draw_line(sx5,sy5,sx6,sy6,gui_rgb(230,240,255)); draw_line(sx6,sy6,sx7,sy7,gui_rgb(230,240,255)); draw_line(sx7,sy7,sx4,sy4,gui_rgb(230,240,255)); }
        // face 4,5 (left)
        ax = sx0-sx4; ay = sy0-sy4; bx = sx3-sx4; by = sy3-sy4; cz = ax*by - ay*bx;
        if (cz < 0) { fill_tri(sx4,sy4,sx0,sy0,sx3,sy3,shade(base,60,100)); fill_tri(sx4,sy4,sx3,sy3,sx7,sy7,shade(base,60,100)); draw_line(sx4,sy4,sx0,sy0,gui_rgb(230,240,255)); draw_line(sx0,sy0,sx3,sy3,gui_rgb(230,240,255)); draw_line(sx3,sy3,sx7,sy7,gui_rgb(230,240,255)); draw_line(sx7,sy7,sx4,sy4,gui_rgb(230,240,255)); }
        // face 6,7 (right)
        ax = sx5-sx1; ay = sy5-sy1; bx = sx6-sx1; by = sy6-sy1; cz = ax*by - ay*bx;
        if (cz < 0) { fill_tri(sx1,sy1,sx5,sy5,sx6,sy6,shade(base,70,100)); fill_tri(sx1,sy1,sx6,sy6,sx2,sy2,shade(base,70,100)); draw_line(sx1,sy1,sx5,sy5,gui_rgb(230,240,255)); draw_line(sx5,sy5,sx6,sy6,gui_rgb(230,240,255)); draw_line(sx6,sy6,sx2,sy2,gui_rgb(230,240,255)); draw_line(sx2,sy2,sx1,sy1,gui_rgb(230,240,255)); }
        // face 8,9 (top)
        ax = sx2-sx3; ay = sy2-sy3; bx = sx6-sx3; by = sy6-sy3; cz = ax*by - ay*bx;
        if (cz < 0) { fill_tri(sx3,sy3,sx2,sy2,sx6,sy6,shade(base,95,100)); fill_tri(sx3,sy3,sx6,sy6,sx7,sy7,shade(base,95,100)); draw_line(sx3,sy3,sx2,sy2,gui_rgb(230,240,255)); draw_line(sx2,sy2,sx6,sy6,gui_rgb(230,240,255)); draw_line(sx6,sy6,sx7,sy7,gui_rgb(230,240,255)); draw_line(sx7,sy7,sx3,sy3,gui_rgb(230,240,255)); }
        // face 10,11 (bottom)
        ax = sx5-sx4; ay = sy5-sy4; bx = sx1-sx4; by = sy1-sy4; cz = ax*by - ay*bx;
        if (cz < 0) { fill_tri(sx4,sy4,sx5,sy5,sx1,sy1,shade(base,35,100)); fill_tri(sx4,sy4,sx1,sy1,sx0,sy0,shade(base,35,100)); draw_line(sx4,sy4,sx5,sy5,gui_rgb(230,240,255)); draw_line(sx5,sy5,sx1,sy1,gui_rgb(230,240,255)); draw_line(sx1,sy1,sx0,sy0,gui_rgb(230,240,255)); draw_line(sx0,sy0,sx4,sy4,gui_rgb(230,240,255)); }

        gui_draw_text_fg(16, 16, "3D cube demo (ESC to quit)", gui_rgb(240, 240, 240), 255);
        gui_present();
    }

    gui_shutdown();
    return 0;
}
