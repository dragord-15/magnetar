// game_3d_duel.mg - Complete 3D two-player duel game (Magnetar)
// Build: ./magc examples/game_3d_duel.mg -o build/game_3d_duel
// Run:   ./build/game_3d_duel   (requires GUI/X11 or framebuffer)
//
// Controls:
//   Player 1 (Blue): W/A/S/D move, Q/E turn, SPACE shoot
//   Player 2 (Red):  Arrow keys move, J/L turn, ENTER shoot
//   R restart (after game over), ESC quit

use "lib/gui.mg";

extern fn sleep_ms(int ms) -> void;

fn absf(float v) -> float { if (v < 0.0) { return 0.0 - v; } return v; }
fn clampf(float v, float lo, float hi) -> float { if (v < lo) { return lo; } if (v > hi) { return hi; } return v; }
fn absi(int v) -> int { if (v < 0) { return -v; } return v; }

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
    while (guard < 40000) {
        if (x >= 0 && x < 800 && y >= 0 && y < 600) { gui_put_pixel(x, y, color); }
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
    r = r * num / den; g = g * num / den; b = b * num / den;
    return r * 65536 + g * 256 + b;
}

fn world_to_screen(float px, float py, float pz,
                   float camx, float camy, float camz,
                   float cpy, float spy, float cpx, float spx,
                   int* sx, int* sy, float* outz) -> int {
    float x = px - camx;
    float y = py - camy;
    float z = pz - camz;
    float x1 = x * cpy + z * spy;
    float z1 = (0.0 - x) * spy + z * cpy;
    float y1 = y * cpx - z1 * spx;
    float z2 = y * spx + z1 * cpx;
    *outz = z2;
    if (z2 <= 0.3) { *sx = 0; *sy = 0; return 0; }
    float f = 520.0;
    *sx = 400 + cast<int>(x1 * f / z2);
    *sy = 300 - cast<int>(y1 * f / z2);
    return 1;
}

fn draw_cube(float cx, float cy, float cz, float hx, float hy, float hz, float yaw,
             int color, int edge,
             float camx, float camy, float camz,
             float cpy, float spy, float cpx, float spx) -> void {
    float cyw = cosf(yaw);
    float syw = sinf(yaw);

    float lx0 = -hx; float ly0 = -hy; float lz0 = -hz;
    float lx1 =  hx; float ly1 = -hy; float lz1 = -hz;
    float lx2 =  hx; float ly2 =  hy; float lz2 = -hz;
    float lx3 = -hx; float ly3 =  hy; float lz3 = -hz;
    float lx4 = -hx; float ly4 = -hy; float lz4 =  hz;
    float lx5 =  hx; float ly5 = -hy; float lz5 =  hz;
    float lx6 =  hx; float ly6 =  hy; float lz6 =  hz;
    float lx7 = -hx; float ly7 =  hy; float lz7 =  hz;

    float wx0 = cx + lx0*cyw + lz0*syw; float wy0 = cy + ly0; float wz0 = cz + (0.0-lx0)*syw + lz0*cyw;
    float wx1 = cx + lx1*cyw + lz1*syw; float wy1 = cy + ly1; float wz1 = cz + (0.0-lx1)*syw + lz1*cyw;
    float wx2 = cx + lx2*cyw + lz2*syw; float wy2 = cy + ly2; float wz2 = cz + (0.0-lx2)*syw + lz2*cyw;
    float wx3 = cx + lx3*cyw + lz3*syw; float wy3 = cy + ly3; float wz3 = cz + (0.0-lx3)*syw + lz3*cyw;
    float wx4 = cx + lx4*cyw + lz4*syw; float wy4 = cy + ly4; float wz4 = cz + (0.0-lx4)*syw + lz4*cyw;
    float wx5 = cx + lx5*cyw + lz5*syw; float wy5 = cy + ly5; float wz5 = cz + (0.0-lx5)*syw + lz5*cyw;
    float wx6 = cx + lx6*cyw + lz6*syw; float wy6 = cy + ly6; float wz6 = cz + (0.0-lx6)*syw + lz6*cyw;
    float wx7 = cx + lx7*cyw + lz7*syw; float wy7 = cy + ly7; float wz7 = cz + (0.0-lx7)*syw + lz7*cyw;

    int sx0 = 0; int sy0 = 0; int sx1 = 0; int sy1 = 0; int sx2 = 0; int sy2 = 0; int sx3 = 0; int sy3 = 0;
    int sx4 = 0; int sy4 = 0; int sx5 = 0; int sy5 = 0; int sx6 = 0; int sy6 = 0; int sx7 = 0; int sy7 = 0;
    float oz0 = 0.0; float oz1 = 0.0; float oz2 = 0.0; float oz3 = 0.0;
    float oz4 = 0.0; float oz5 = 0.0; float oz6 = 0.0; float oz7 = 0.0;
    int v0 = world_to_screen(wx0,wy0,wz0,camx,camy,camz,cpy,spy,cpx,spx,&sx0,&sy0,&oz0);
    int v1 = world_to_screen(wx1,wy1,wz1,camx,camy,camz,cpy,spy,cpx,spx,&sx1,&sy1,&oz1);
    int v2 = world_to_screen(wx2,wy2,wz2,camx,camy,camz,cpy,spy,cpx,spx,&sx2,&sy2,&oz2);
    int v3 = world_to_screen(wx3,wy3,wz3,camx,camy,camz,cpy,spy,cpx,spx,&sx3,&sy3,&oz3);
    int v4 = world_to_screen(wx4,wy4,wz4,camx,camy,camz,cpy,spy,cpx,spx,&sx4,&sy4,&oz4);
    int v5 = world_to_screen(wx5,wy5,wz5,camx,camy,camz,cpy,spy,cpx,spx,&sx5,&sy5,&oz5);
    int v6 = world_to_screen(wx6,wy6,wz6,camx,camy,camz,cpy,spy,cpx,spx,&sx6,&sy6,&oz6);
    int v7 = world_to_screen(wx7,wy7,wz7,camx,camy,camz,cpy,spy,cpx,spx,&sx7,&sy7,&oz7);

    // draw visible faces (backface by screen cross), painter-ish per face pair by depth check inline
    // front (0,1,2,3)
    if (v0==1 && v1==1 && v2==1 && v3==1) {
        int ax = sx1-sx0; int ay = sy1-sy0; int bx = sx2-sx0; int by = sy2-sy0;
        if (ax*by - ay*bx < 0) {
            fill_tri(sx0,sy0,sx1,sy1,sx2,sy2,shade(color,85,100));
            fill_tri(sx0,sy0,sx2,sy2,sx3,sy3,shade(color,85,100));
            draw_line(sx0,sy0,sx1,sy1,edge); draw_line(sx1,sy1,sx2,sy2,edge);
            draw_line(sx2,sy2,sx3,sy3,edge); draw_line(sx3,sy3,sx0,sy0,edge);
        }
    }
    // back (5,4,7,6)
    if (v5==1 && v4==1 && v7==1 && v6==1) {
        int ax = sx4-sx5; int ay = sy4-sy5; int bx = sx7-sx5; int by = sy7-sy5;
        if (ax*by - ay*bx < 0) {
            fill_tri(sx5,sy5,sx4,sy4,sx7,sy7,shade(color,45,100));
            fill_tri(sx5,sy5,sx7,sy7,sx6,sy6,shade(color,45,100));
            draw_line(sx4,sy4,sx5,sy5,edge); draw_line(sx5,sy5,sx6,sy6,edge);
            draw_line(sx6,sy6,sx7,sy7,edge); draw_line(sx7,sy7,sx4,sy4,edge);
        }
    }
    // left (4,0,3,7)
    if (v4==1 && v0==1 && v3==1 && v7==1) {
        int ax = sx0-sx4; int ay = sy0-sy4; int bx = sx3-sx4; int by = sy3-sy4;
        if (ax*by - ay*bx < 0) {
            fill_tri(sx4,sy4,sx0,sy0,sx3,sy3,shade(color,60,100));
            fill_tri(sx4,sy4,sx3,sy3,sx7,sy7,shade(color,60,100));
            draw_line(sx4,sy4,sx0,sy0,edge); draw_line(sx0,sy0,sx3,sy3,edge);
            draw_line(sx3,sy3,sx7,sy7,edge); draw_line(sx7,sy7,sx4,sy4,edge);
        }
    }
    // right (1,5,6,2)
    if (v1==1 && v5==1 && v6==1 && v2==1) {
        int ax = sx5-sx1; int ay = sy5-sy1; int bx = sx6-sx1; int by = sy6-sy1;
        if (ax*by - ay*bx < 0) {
            fill_tri(sx1,sy1,sx5,sy5,sx6,sy6,shade(color,70,100));
            fill_tri(sx1,sy1,sx6,sy6,sx2,sy2,shade(color,70,100));
            draw_line(sx1,sy1,sx5,sy5,edge); draw_line(sx5,sy5,sx6,sy6,edge);
            draw_line(sx6,sy6,sx2,sy2,edge); draw_line(sx2,sy2,sx1,sy1,edge);
        }
    }
    // top (3,2,6,7)
    if (v3==1 && v2==1 && v6==1 && v7==1) {
        int ax = sx2-sx3; int ay = sy2-sy3; int bx = sx6-sx3; int by = sy6-sy3;
        if (ax*by - ay*bx < 0) {
            fill_tri(sx3,sy3,sx2,sy2,sx6,sy6,shade(color,95,100));
            fill_tri(sx3,sy3,sx6,sy6,sx7,sy7,shade(color,95,100));
            draw_line(sx3,sy3,sx2,sy2,edge); draw_line(sx2,sy2,sx6,sy6,edge);
            draw_line(sx6,sy6,sx7,sy7,edge); draw_line(sx7,sy7,sx3,sy3,edge);
        }
    }
    // bottom (4,5,1,0)
    if (v4==1 && v5==1 && v1==1 && v0==1) {
        int ax = sx5-sx4; int ay = sy5-sy4; int bx = sx1-sx4; int by = sy1-sy4;
        if (ax*by - ay*bx < 0) {
            fill_tri(sx4,sy4,sx5,sy5,sx1,sy1,shade(color,35,100));
            fill_tri(sx4,sy4,sx1,sy1,sx0,sy0,shade(color,35,100));
            draw_line(sx4,sy4,sx5,sy5,edge); draw_line(sx5,sy5,sx1,sy1,edge);
            draw_line(sx1,sy1,sx0,sy0,edge); draw_line(sx0,sy0,sx4,sy4,edge);
        }
    }
}

fn draw_grid(float camx, float camy, float camz, float cpy, float spy, float cpx, float spx) -> void {
    int col = gui_rgb(50, 55, 70);
    int i = -6;
    while (i <= 6) {
        float p = cast<float>(i) * 2.0;
        // lines along Z
        int ax = 0; int ay = 0; int bx = 0; int by = 0;
        float az = 0.0; float bz = 0.0;
        int va = world_to_screen(p, 0.0, -12.0, camx,camy,camz,cpy,spy,cpx,spx,&ax,&ay,&az);
        int vb = world_to_screen(p, 0.0,  12.0, camx,camy,camz,cpy,spy,cpx,spx,&bx,&by,&bz);
        if (va==1 && vb==1) { draw_line(ax,ay,bx,by,col); }
        // lines along X
        va = world_to_screen(-12.0, 0.0, p, camx,camy,camz,cpy,spy,cpx,spx,&ax,&ay,&az);
        vb = world_to_screen( 12.0, 0.0, p, camx,camy,camz,cpy,spy,cpx,spx,&bx,&by,&bz);
        if (va==1 && vb==1) { draw_line(ax,ay,bx,by,col); }
        i = i + 1;
    }
    // boundary
    int bcol = gui_rgb(90, 100, 130);
    int x0=0; int y0=0; int x1=0; int y1=0; int x2=0; int y2=0; int x3=0; int y3=0;
    float z0=0.0; float z1=0.0; float z2=0.0; float z3=0.0;
    world_to_screen(-10.0,0.0,-10.0,camx,camy,camz,cpy,spy,cpx,spx,&x0,&y0,&z0);
    world_to_screen( 10.0,0.0,-10.0,camx,camy,camz,cpy,spy,cpx,spx,&x1,&y1,&z1);
    world_to_screen( 10.0,0.0, 10.0,camx,camy,camz,cpy,spy,cpx,spx,&x2,&y2,&z2);
    world_to_screen(-10.0,0.0, 10.0,camx,camy,camz,cpy,spy,cpx,spx,&x3,&y3,&z3);
    draw_line(x0,y0,x1,y1,bcol); draw_line(x1,y1,x2,y2,bcol);
    draw_line(x2,y2,x3,y3,bcol); draw_line(x3,y3,x0,y0,bcol);
}

fn draw_bar(int x, int y, int w, int h, int hp, int maxhp, int fg, int bg) -> void {
    gui_fill_rect(x, y, w, h, bg);
    if (maxhp <= 0) { maxhp = 1; }
    int fw = w * hp / maxhp;
    if (fw < 0) { fw = 0; }
    if (fw > w) { fw = w; }
    if (fw > 0) { gui_fill_rect(x, y, fw, h, fg); }
    gui_draw_rect(x, y, w, h, gui_rgb(230,230,230));
}

fn main() -> int {
    if (gui_init_window(800, 600, "Magnetar 3D Duel") < 0) {
        return 1;
    }

    float camx = 0.0; float camy = 11.0; float camz = -15.0;
    float campitch = -0.65; float camyaw = 0.0;
    float cpx = cosf(campitch); float spx = sinf(campitch);
    float cpy = cosf(camyaw); float spy = sinf(camyaw);

    int state = 0; // 0 menu, 1 play, 2 over
    int winner = 0;
    int p1_score = 0; int p2_score = 0;

    // players
    float p1x = -5.0; float p1z = 0.0; float p1yaw = 1.5708; int p1hp = 5; int p1cd = 0;
    float p2x =  5.0; float p2z = 0.0; float p2yaw = -1.5708; int p2hp = 5; int p2cd = 0;

    // bullets (6 per player)
    int b1a = 0; float b1x0=0.0; float b1z0=0.0; float b1vx0=0.0; float b1vz0=0.0; int b1l0=0;
    int b1b = 0; float b1x1=0.0; float b1z1=0.0; float b1vx1=0.0; float b1vz1=0.0; int b1l1=0;
    int b1c = 0; float b1x2=0.0; float b1z2=0.0; float b1vx2=0.0; float b1vz2=0.0; int b1l2=0;
    int b1d = 0; float b1x3=0.0; float b1z3=0.0; float b1vx3=0.0; float b1vz3=0.0; int b1l3=0;
    int b1e = 0; float b1x4=0.0; float b1z4=0.0; float b1vx4=0.0; float b1vz4=0.0; int b1l4=0;
    int b1f = 0; float b1x5=0.0; float b1z5=0.0; float b1vx5=0.0; float b1vz5=0.0; int b1l5=0;

    int b2a = 0; float b2x0=0.0; float b2z0=0.0; float b2vx0=0.0; float b2vz0=0.0; int b2l0=0;
    int b2b = 0; float b2x1=0.0; float b2z1=0.0; float b2vx1=0.0; float b2vz1=0.0; int b2l1=0;
    int b2c = 0; float b2x2=0.0; float b2z2=0.0; float b2vx2=0.0; float b2vz2=0.0; int b2l2=0;
    int b2d = 0; float b2x3=0.0; float b2z3=0.0; float b2vx3=0.0; float b2vz3=0.0; int b2l3=0;
    int b2e = 0; float b2x4=0.0; float b2z4=0.0; float b2vx4=0.0; float b2vz4=0.0; int b2l4=0;
    int b2f = 0; float b2x5=0.0; float b2z5=0.0; float b2vx5=0.0; float b2vz5=0.0; int b2l5=0;

    while (gui_close_requested() == 0) {
        gui_read_mouse();

        int ksp = 0; int kent = 0; int kr = 0;
        int p1u=0; int p1d=0; int p1l=0; int p1r=0; int p1tl=0; int p1tr=0; int p1sh=0;
        int p2u=0; int p2d=0; int p2l=0; int p2r=0; int p2tl=0; int p2tr=0; int p2sh=0;

        while (gui_key_available() > 0) {
            int k = gui_key_poll();
            if (k == 27) { gui_shutdown(); return 0; }
            if (k == 32) { ksp = 1; p1sh = 1; }
            if (k == 10 || k == 13) { kent = 1; p2sh = 1; }
            if (k == 114 || k == 82) { kr = 1; }
            // P1 WASD + Q/E
            if (k == 119 || k == 87) { p1u = 1; }
            if (k == 115 || k == 83) { p1d = 1; }
            if (k == 97  || k == 65) { p1l = 1; }
            if (k == 100 || k == 68) { p1r = 1; }
            if (k == 113 || k == 81) { p1tl = 1; }
            if (k == 101 || k == 69) { p1tr = 1; }
            // P2 arrows + J/L
            if (k == 128) { p2u = 1; }
            if (k == 129) { p2d = 1; }
            if (k == 130) { p2l = 1; }
            if (k == 131) { p2r = 1; }
            if (k == 106 || k == 74) { p2tl = 1; }
            if (k == 108 || k == 76) { p2tr = 1; }
        }

        if (state == 0) {
            if (ksp == 1 || kent == 1) {
                state = 1; winner = 0;
                p1x = -5.0; p1z = 0.0; p1yaw = 1.5708; p1hp = 5; p1cd = 0;
                p2x =  5.0; p2z = 0.0; p2yaw = -1.5708; p2hp = 5; p2cd = 0;
                b1a=0;b1b=0;b1c=0;b1d=0;b1e=0;b1f=0;
                b2a=0;b2b=0;b2c=0;b2d=0;b2e=0;b2f=0;
            }
        } else if (state == 2) {
            if (kr == 1 || ksp == 1 || kent == 1) {
                state = 1; winner = 0;
                p1x = -5.0; p1z = 0.0; p1yaw = 1.5708; p1hp = 5; p1cd = 0;
                p2x =  5.0; p2z = 0.0; p2yaw = -1.5708; p2hp = 5; p2cd = 0;
                b1a=0;b1b=0;b1c=0;b1d=0;b1e=0;b1f=0;
                b2a=0;b2b=0;b2c=0;b2d=0;b2e=0;b2f=0;
            }
        } else {
            float spd = 0.22;
            float turn = 0.12;
            // P1
            if (p1tl == 1) { p1yaw = p1yaw - turn; }
            if (p1tr == 1) { p1yaw = p1yaw + turn; }
            float fx1 = sinf(p1yaw); float fz1 = 0.0 - cosf(p1yaw);
            float rx1 = cosf(p1yaw); float rz1 = sinf(p1yaw);
            if (p1u == 1) { p1x = p1x + fx1*spd; p1z = p1z + fz1*spd; }
            if (p1d == 1) { p1x = p1x - fx1*spd; p1z = p1z - fz1*spd; }
            if (p1l == 1) { p1x = p1x - rx1*spd; p1z = p1z - rz1*spd; }
            if (p1r == 1) { p1x = p1x + rx1*spd; p1z = p1z + rz1*spd; }
            // P2
            if (p2tl == 1) { p2yaw = p2yaw - turn; }
            if (p2tr == 1) { p2yaw = p2yaw + turn; }
            float fx2 = sinf(p2yaw); float fz2 = 0.0 - cosf(p2yaw);
            float rx2 = cosf(p2yaw); float rz2 = sinf(p2yaw);
            if (p2u == 1) { p2x = p2x + fx2*spd; p2z = p2z + fz2*spd; }
            if (p2d == 1) { p2x = p2x - fx2*spd; p2z = p2z - fz2*spd; }
            if (p2l == 1) { p2x = p2x - rx2*spd; p2z = p2z - rz2*spd; }
            if (p2r == 1) { p2x = p2x + rx2*spd; p2z = p2z + rz2*spd; }

            // clamp arena
            p1x = clampf(p1x, -9.0, 9.0); p1z = clampf(p1z, -9.0, 9.0);
            p2x = clampf(p2x, -9.0, 9.0); p2z = clampf(p2z, -9.0, 9.0);

            if (p1cd > 0) { p1cd = p1cd - 1; }
            if (p2cd > 0) { p2cd = p2cd - 1; }

            // shoot P1
            if (p1sh == 1 && p1cd == 0) {
                float bvx = sinf(p1yaw) * 0.45; float bvz = (0.0 - cosf(p1yaw)) * 0.45;
                if (b1a == 0) { b1a=1; b1x0=p1x+bvx*2.0; b1z0=p1z+bvz*2.0; b1vx0=bvx; b1vz0=bvz; b1l0=90; p1cd=14; }
                else if (b1b == 0) { b1b=1; b1x1=p1x+bvx*2.0; b1z1=p1z+bvz*2.0; b1vx1=bvx; b1vz1=bvz; b1l1=90; p1cd=14; }
                else if (b1c == 0) { b1c=1; b1x2=p1x+bvx*2.0; b1z2=p1z+bvz*2.0; b1vx2=bvx; b1vz2=bvz; b1l2=90; p1cd=14; }
                else if (b1d == 0) { b1d=1; b1x3=p1x+bvx*2.0; b1z3=p1z+bvz*2.0; b1vx3=bvx; b1vz3=bvz; b1l3=90; p1cd=14; }
                else if (b1e == 0) { b1e=1; b1x4=p1x+bvx*2.0; b1z4=p1z+bvz*2.0; b1vx4=bvx; b1vz4=bvz; b1l4=90; p1cd=14; }
                else if (b1f == 0) { b1f=1; b1x5=p1x+bvx*2.0; b1z5=p1z+bvz*2.0; b1vx5=bvx; b1vz5=bvz; b1l5=90; p1cd=14; }
            }
            // shoot P2
            if (p2sh == 1 && p2cd == 0) {
                float bvx = sinf(p2yaw) * 0.45; float bvz = (0.0 - cosf(p2yaw)) * 0.45;
                if (b2a == 0) { b2a=1; b2x0=p2x+bvx*2.0; b2z0=p2z+bvz*2.0; b2vx0=bvx; b2vz0=bvz; b2l0=90; p2cd=14; }
                else if (b2b == 0) { b2b=1; b2x1=p2x+bvx*2.0; b2z1=p2z+bvz*2.0; b2vx1=bvx; b2vz1=bvz; b2l1=90; p2cd=14; }
                else if (b2c == 0) { b2c=1; b2x2=p2x+bvx*2.0; b2z2=p2z+bvz*2.0; b2vx2=bvx; b2vz2=bvz; b2l2=90; p2cd=14; }
                else if (b2d == 0) { b2d=1; b2x3=p2x+bvx*2.0; b2z3=p2z+bvz*2.0; b2vx3=bvx; b2vz3=bvz; b2l3=90; p2cd=14; }
                else if (b2e == 0) { b2e=1; b2x4=p2x+bvx*2.0; b2z4=p2z+bvz*2.0; b2vx4=bvx; b2vz4=bvz; b2l4=90; p2cd=14; }
                else if (b2f == 0) { b2f=1; b2x5=p2x+bvx*2.0; b2z5=p2z+bvz*2.0; b2vx5=bvx; b2vz5=bvz; b2l5=90; p2cd=14; }
            }

            // move bullets P1 and hit P2
            if (b1a==1) { b1x0=b1x0+b1vx0; b1z0=b1z0+b1vz0; b1l0=b1l0-1; if (b1l0<=0 || absf(b1x0)>10.5 || absf(b1z0)>10.5) { b1a=0; } else if (absf(b1x0-p2x)<1.0 && absf(b1z0-p2z)<1.0) { b1a=0; p2hp=p2hp-1; } }
            if (b1b==1) { b1x1=b1x1+b1vx1; b1z1=b1z1+b1vz1; b1l1=b1l1-1; if (b1l1<=0 || absf(b1x1)>10.5 || absf(b1z1)>10.5) { b1b=0; } else if (absf(b1x1-p2x)<1.0 && absf(b1z1-p2z)<1.0) { b1b=0; p2hp=p2hp-1; } }
            if (b1c==1) { b1x2=b1x2+b1vx2; b1z2=b1z2+b1vz2; b1l2=b1l2-1; if (b1l2<=0 || absf(b1x2)>10.5 || absf(b1z2)>10.5) { b1c=0; } else if (absf(b1x2-p2x)<1.0 && absf(b1z2-p2z)<1.0) { b1c=0; p2hp=p2hp-1; } }
            if (b1d==1) { b1x3=b1x3+b1vx3; b1z3=b1z3+b1vz3; b1l3=b1l3-1; if (b1l3<=0 || absf(b1x3)>10.5 || absf(b1z3)>10.5) { b1d=0; } else if (absf(b1x3-p2x)<1.0 && absf(b1z3-p2z)<1.0) { b1d=0; p2hp=p2hp-1; } }
            if (b1e==1) { b1x4=b1x4+b1vx4; b1z4=b1z4+b1vz4; b1l4=b1l4-1; if (b1l4<=0 || absf(b1x4)>10.5 || absf(b1z4)>10.5) { b1e=0; } else if (absf(b1x4-p2x)<1.0 && absf(b1z4-p2z)<1.0) { b1e=0; p2hp=p2hp-1; } }
            if (b1f==1) { b1x5=b1x5+b1vx5; b1z5=b1z5+b1vz5; b1l5=b1l5-1; if (b1l5<=0 || absf(b1x5)>10.5 || absf(b1z5)>10.5) { b1f=0; } else if (absf(b1x5-p2x)<1.0 && absf(b1z5-p2z)<1.0) { b1f=0; p2hp=p2hp-1; } }
            // move bullets P2 and hit P1
            if (b2a==1) { b2x0=b2x0+b2vx0; b2z0=b2z0+b2vz0; b2l0=b2l0-1; if (b2l0<=0 || absf(b2x0)>10.5 || absf(b2z0)>10.5) { b2a=0; } else if (absf(b2x0-p1x)<1.0 && absf(b2z0-p1z)<1.0) { b2a=0; p1hp=p1hp-1; } }
            if (b2b==1) { b2x1=b2x1+b2vx1; b2z1=b2z1+b2vz1; b2l1=b2l1-1; if (b2l1<=0 || absf(b2x1)>10.5 || absf(b2z1)>10.5) { b2b=0; } else if (absf(b2x1-p1x)<1.0 && absf(b2z1-p1z)<1.0) { b2b=0; p1hp=p1hp-1; } }
            if (b2c==1) { b2x2=b2x2+b2vx2; b2z2=b2z2+b2vz2; b2l2=b2l2-1; if (b2l2<=0 || absf(b2x2)>10.5 || absf(b2z2)>10.5) { b2c=0; } else if (absf(b2x2-p1x)<1.0 && absf(b2z2-p1z)<1.0) { b2c=0; p1hp=p1hp-1; } }
            if (b2d==1) { b2x3=b2x3+b2vx3; b2z3=b2z3+b2vz3; b2l3=b2l3-1; if (b2l3<=0 || absf(b2x3)>10.5 || absf(b2z3)>10.5) { b2d=0; } else if (absf(b2x3-p1x)<1.0 && absf(b2z3-p1z)<1.0) { b2d=0; p1hp=p1hp-1; } }
            if (b2e==1) { b2x4=b2x4+b2vx4; b2z4=b2z4+b2vz4; b2l4=b2l4-1; if (b2l4<=0 || absf(b2x4)>10.5 || absf(b2z4)>10.5) { b2e=0; } else if (absf(b2x4-p1x)<1.0 && absf(b2z4-p1z)<1.0) { b2e=0; p1hp=p1hp-1; } }
            if (b2f==1) { b2x5=b2x5+b2vx5; b2z5=b2z5+b2vz5; b2l5=b2l5-1; if (b2l5<=0 || absf(b2x5)>10.5 || absf(b2z5)>10.5) { b2f=0; } else if (absf(b2x5-p1x)<1.0 && absf(b2z5-p1z)<1.0) { b2f=0; p1hp=p1hp-1; } }

            if (p1hp <= 0) { state = 2; winner = 2; p2_score = p2_score + 1; }
            if (p2hp <= 0) { state = 2; winner = 1; p1_score = p1_score + 1; }
        }

        // render
        gui_clear(gui_rgb(14, 16, 24));
        draw_grid(camx,camy,camz,cpy,spy,cpx,spx);

        // draw players and bullets (simple order; arena small)
        draw_cube(p1x, 1.0, p1z, 0.9, 0.7, 1.1, p1yaw, gui_rgb(70,120,255), gui_rgb(220,235,255), camx,camy,camz,cpy,spy,cpx,spx);
        draw_cube(p2x, 1.0, p2z, 0.9, 0.7, 1.1, p2yaw, gui_rgb(240,80,80), gui_rgb(255,230,230), camx,camy,camz,cpy,spy,cpx,spx);

        int bc1 = gui_rgb(120,180,255);
        if (b1a==1) { draw_cube(b1x0,0.8,b1z0,0.18,0.18,0.18,0.0,bc1,gui_rgb(255,255,255),camx,camy,camz,cpy,spy,cpx,spx); }
        if (b1b==1) { draw_cube(b1x1,0.8,b1z1,0.18,0.18,0.18,0.0,bc1,gui_rgb(255,255,255),camx,camy,camz,cpy,spy,cpx,spx); }
        if (b1c==1) { draw_cube(b1x2,0.8,b1z2,0.18,0.18,0.18,0.0,bc1,gui_rgb(255,255,255),camx,camy,camz,cpy,spy,cpx,spx); }
        if (b1d==1) { draw_cube(b1x3,0.8,b1z3,0.18,0.18,0.18,0.0,bc1,gui_rgb(255,255,255),camx,camy,camz,cpy,spy,cpx,spx); }
        if (b1e==1) { draw_cube(b1x4,0.8,b1z4,0.18,0.18,0.18,0.0,bc1,gui_rgb(255,255,255),camx,camy,camz,cpy,spy,cpx,spx); }
        if (b1f==1) { draw_cube(b1x5,0.8,b1z5,0.18,0.18,0.18,0.0,bc1,gui_rgb(255,255,255),camx,camy,camz,cpy,spy,cpx,spx); }
        int bc2 = gui_rgb(255,140,140);
        if (b2a==1) { draw_cube(b2x0,0.8,b2z0,0.18,0.18,0.18,0.0,bc2,gui_rgb(255,255,255),camx,camy,camz,cpy,spy,cpx,spx); }
        if (b2b==1) { draw_cube(b2x1,0.8,b2z1,0.18,0.18,0.18,0.0,bc2,gui_rgb(255,255,255),camx,camy,camz,cpy,spy,cpx,spx); }
        if (b2c==1) { draw_cube(b2x2,0.8,b2z2,0.18,0.18,0.18,0.0,bc2,gui_rgb(255,255,255),camx,camy,camz,cpy,spy,cpx,spx); }
        if (b2d==1) { draw_cube(b2x3,0.8,b2z3,0.18,0.18,0.18,0.0,bc2,gui_rgb(255,255,255),camx,camy,camz,cpy,spy,cpx,spx); }
        if (b2e==1) { draw_cube(b2x4,0.8,b2z4,0.18,0.18,0.18,0.0,bc2,gui_rgb(255,255,255),camx,camy,camz,cpy,spy,cpx,spx); }
        if (b2f==1) { draw_cube(b2x5,0.8,b2z5,0.18,0.18,0.18,0.0,bc2,gui_rgb(255,255,255),camx,camy,camz,cpy,spy,cpx,spx); }

        // HUD
        gui_fill_rect(0, 0, 800, 70, gui_rgb(8,10,16));
        gui_draw_text_fg(20, 12, "P1 (Blue)  WASD move  Q/E turn  SPACE shoot", gui_rgb(120,170,255), 255);
        gui_draw_text_fg(20, 30, "P2 (Red)   Arrows move J/L turn  ENTER shoot", gui_rgb(255,130,130), 255);
        gui_draw_text_fg(20, 48, "ESC quit", gui_rgb(200,200,200), 255);
        draw_bar(420, 14, 160, 14, p1hp, 5, gui_rgb(70,120,255), gui_rgb(40,40,50));
        draw_bar(600, 14, 160, 14, p2hp, 5, gui_rgb(240,80,80), gui_rgb(40,40,50));
        gui_draw_text_fg(420, 32, "P1 HP", gui_rgb(180,210,255), 255);
        gui_draw_text_fg(600, 32, "P2 HP", gui_rgb(255,180,180), 255);

        if (state == 0) {
            gui_fill_rect(170, 220, 460, 140, gui_rgb(20,24,36));
            gui_draw_rect(170, 220, 460, 140, gui_rgb(120,140,200));
            gui_draw_text_fg(300, 250, "MAGNETAR 3D DUEL", gui_rgb(240,240,255), 255);
            gui_draw_text_fg(230, 285, "Two players - destroy the opponent!", gui_rgb(210,210,220), 255);
            gui_draw_text_fg(250, 315, "Press SPACE or ENTER to start", gui_rgb(255,220,120), 255);
        } else if (state == 2) {
            gui_fill_rect(200, 230, 400, 120, gui_rgb(20,24,36));
            gui_draw_rect(200, 230, 400, 120, gui_rgb(120,140,200));
            if (winner == 1) {
                gui_draw_text_fg(300, 260, "PLAYER 1 WINS!", gui_rgb(120,170,255), 255);
            } else {
                gui_draw_text_fg(300, 260, "PLAYER 2 WINS!", gui_rgb(255,130,130), 255);
            }
            gui_draw_text_fg(250, 295, "Press R / SPACE / ENTER to restart", gui_rgb(255,220,120), 255);
        }

        gui_present();
        sleep_ms(16);
    }

    gui_shutdown();
    return 0;
}
