// ============================================================================
// Magnetar 3D Game Library (lib/game3d.mg)
// Software 3D renderer and math utilities for Magnetar.
//
// Features:
//   - Fixed-point friendly Vec3/Mat4 helpers and float-based transforms
//   - 3D vector math (add, sub, scale, dot, cross, length, normalize)
//   - 4x4 matrices (identity, multiply, translation, scale, rotation X/Y/Z,
//     perspective, viewport-like projection helpers)
//   - Projection (perspective divide) and screen mapping
//   - Drawing: 3D lines (wireframe), filled triangles with z/painter sort
//   - Mesh structure with vertex/face arrays and transforms
//   - Camera3D with position/target/yaw-pitch helpers
//   - Simple lighting (flat shading by face normal vs light direction)
//
// Rendering uses gui_put_pixel / gui_fill_rect / line rasterization.
// Usage:
//   use "lib/gui.mg";
//   use "lib/game3d.mg";
//   g3d_init(800,600); ...
//   g3d_clear(0x101020);
//   g3d_draw_mesh_wire(...); or g3d_draw_mesh_flat(...);
//   g3d_present();
//
// Notes:
//   - Designed for integer screen output; math uses float where available.
//   - Depth handling for filled faces uses painter's algorithm (avg Z).
// ============================================================================

use "lib/gui.mg";

// -----------------------------
// Scalar helpers
// -----------------------------
fn g3d_absf(float v) -> float { if (v < 0.0) { return 0.0 - v; } return v; }
fn g3d_minf(float a, float b) -> float { if (a < b) { return a; } return b; }
fn g3d_maxf(float a, float b) -> float { if (a > b) { return a; } return b; }
fn g3d_clampf(float v, float lo, float hi) -> float { if (v < lo) { return lo; } if (v > hi) { return hi; } return v; }
fn g3d_absi(int v) -> int { if (v < 0) { return -v; } return v; }
fn g3d_mini(int a, int b) -> int { if (a < b) { return a; } return b; }
fn g3d_maxi(int a, int b) -> int { if (a > b) { return a; } return b; }
fn g3d_clampi(int v, int lo, int hi) -> int { if (v < lo) { return lo; } if (v > hi) { return hi; } return v; }

// -----------------------------
// Vectors / matrices
// -----------------------------
struct Vec3 { float x; float y; float z; }
struct Vec4 { float x; float y; float z; float w; }
struct Vec2i3 { int x; int y; float z; } // projected point with depth

struct Mat4 {
    float m0; float m1; float m2; float m3;
    float m4; float m5; float m6; float m7;
    float m8; float m9; float m10; float m11;
    float m12; float m13; float m14; float m15;
}

fn vec3(float x, float y, float z) -> Vec3 { Vec3 v; v.x=x; v.y=y; v.z=z; return v; }
fn vec4(float x, float y, float z, float w) -> Vec4 { Vec4 v; v.x=x; v.y=y; v.z=z; v.w=w; return v; }

fn v3_add(Vec3 a, Vec3 b) -> Vec3 { return vec3(a.x+b.x, a.y+b.y, a.z+b.z); }
fn v3_sub(Vec3 a, Vec3 b) -> Vec3 { return vec3(a.x-b.x, a.y-b.y, a.z-b.z); }
fn v3_scale(Vec3 a, float s) -> Vec3 { return vec3(a.x*s, a.y*s, a.z*s); }
fn v3_dot(Vec3 a, Vec3 b) -> float { return a.x*b.x + a.y*b.y + a.z*b.z; }
fn v3_cross(Vec3 a, Vec3 b) -> Vec3 {
    return vec3(a.y*b.z - a.z*b.y, a.z*b.x - a.x*b.z, a.x*b.y - a.y*b.x);
}
fn v3_len(Vec3 a) -> float {
    float s = a.x*a.x + a.y*a.y + a.z*a.z;
    if (s <= 0.0) { return 0.0; }
    // Newton sqrt
    float x = s;
    int i = 0;
    while (i < 16) { x = 0.5 * (x + s / x); i = i + 1; }
    return x;
}
fn v3_norm(Vec3 a) -> Vec3 {
    float l = v3_len(a);
    if (l <= 0.00001) { return vec3(0.0, 0.0, 0.0); }
    return vec3(a.x/l, a.y/l, a.z/l);
}

fn mat4_identity() -> Mat4 {
    Mat4 m;
    m.m0=1.0; m.m1=0.0; m.m2=0.0; m.m3=0.0;
    m.m4=0.0; m.m5=1.0; m.m6=0.0; m.m7=0.0;
    m.m8=0.0; m.m9=0.0; m.m10=1.0; m.m11=0.0;
    m.m12=0.0; m.m13=0.0; m.m14=0.0; m.m15=1.0;
    return m;
}

fn mat4_mul(Mat4 a, Mat4 b) -> Mat4 {
    Mat4 r;
    r.m0  = a.m0*b.m0  + a.m1*b.m4  + a.m2*b.m8   + a.m3*b.m12;
    r.m1  = a.m0*b.m1  + a.m1*b.m5  + a.m2*b.m9   + a.m3*b.m13;
    r.m2  = a.m0*b.m2  + a.m1*b.m6  + a.m2*b.m10  + a.m3*b.m14;
    r.m3  = a.m0*b.m3  + a.m1*b.m7  + a.m2*b.m11  + a.m3*b.m15;
    r.m4  = a.m4*b.m0  + a.m5*b.m4  + a.m6*b.m8   + a.m7*b.m12;
    r.m5  = a.m4*b.m1  + a.m5*b.m5  + a.m6*b.m9   + a.m7*b.m13;
    r.m6  = a.m4*b.m2  + a.m5*b.m6  + a.m6*b.m10  + a.m7*b.m14;
    r.m7  = a.m4*b.m3  + a.m5*b.m7  + a.m6*b.m11  + a.m7*b.m15;
    r.m8  = a.m8*b.m0  + a.m9*b.m4  + a.m10*b.m8  + a.m11*b.m12;
    r.m9  = a.m8*b.m1  + a.m9*b.m5  + a.m10*b.m9  + a.m11*b.m13;
    r.m10 = a.m8*b.m2  + a.m9*b.m6  + a.m10*b.m10 + a.m11*b.m14;
    r.m11 = a.m8*b.m3  + a.m9*b.m7  + a.m10*b.m11 + a.m11*b.m15;
    r.m12 = a.m12*b.m0 + a.m13*b.m4 + a.m14*b.m8  + a.m15*b.m12;
    r.m13 = a.m12*b.m1 + a.m13*b.m5 + a.m14*b.m9  + a.m15*b.m13;
    r.m14 = a.m12*b.m2 + a.m13*b.m6 + a.m14*b.m10 + a.m15*b.m14;
    r.m15 = a.m12*b.m3 + a.m13*b.m7 + a.m14*b.m11 + a.m15*b.m15;
    return r;
}

fn mat4_mul_vec4(Mat4 m, Vec4 v) -> Vec4 {
    Vec4 r;
    r.x = m.m0*v.x + m.m1*v.y + m.m2*v.z + m.m3*v.w;
    r.y = m.m4*v.x + m.m5*v.y + m.m6*v.z + m.m7*v.w;
    r.z = m.m8*v.x + m.m9*v.y + m.m10*v.z + m.m11*v.w;
    r.w = m.m12*v.x + m.m13*v.y + m.m14*v.z + m.m15*v.w;
    return r;
}

fn mat4_translate(float x, float y, float z) -> Mat4 {
    Mat4 m = mat4_identity();
    m.m3 = x; m.m7 = y; m.m11 = z;
    return m;
}

fn mat4_scale(float x, float y, float z) -> Mat4 {
    Mat4 m = mat4_identity();
    m.m0 = x; m.m5 = y; m.m10 = z;
    return m;
}

// Trig: use math.mg style integer degrees scaled 1000 via sin_deg/cos_deg if available,
// but for float pipeline we provide Taylor/approx via extern-like not possible; implement
// basic sin/cos approximation (radians).
fn g3d_sin(float x) -> float {
    // range reduce roughly to [-pi, pi]
    float pi = 3.14159265;
    float tpi = 6.2831853;
    while (x > pi) { x = x - tpi; }
    while (x < 0.0 - pi) { x = x + tpi; }
    float x2 = x*x;
    float x3 = x2*x;
    float x5 = x3*x2;
    float x7 = x5*x2;
    return x - x3/6.0 + x5/120.0 - x7/5040.0;
}
fn g3d_cos(float x) -> float {
    float pi = 3.14159265;
    float tpi = 6.2831853;
    while (x > pi) { x = x - tpi; }
    while (x < 0.0 - pi) { x = x + tpi; }
    float x2 = x*x;
    float x4 = x2*x2;
    float x6 = x4*x2;
    return 1.0 - x2/2.0 + x4/24.0 - x6/720.0;
}

fn mat4_rotate_x(float a) -> Mat4 {
    Mat4 m = mat4_identity();
    float c = g3d_cos(a); float s = g3d_sin(a);
    m.m5 = c; m.m6 = 0.0 - s;
    m.m9 = s; m.m10 = c;
    return m;
}
fn mat4_rotate_y(float a) -> Mat4 {
    Mat4 m = mat4_identity();
    float c = g3d_cos(a); float s = g3d_sin(a);
    m.m0 = c; m.m2 = s;
    m.m8 = 0.0 - s; m.m10 = c;
    return m;
}
fn mat4_rotate_z(float a) -> Mat4 {
    Mat4 m = mat4_identity();
    float c = g3d_cos(a); float s = g3d_sin(a);
    m.m0 = c; m.m1 = 0.0 - s;
    m.m4 = s; m.m5 = c;
    return m;
}

fn mat4_perspective(float fov_deg, float aspect, float near, float far) -> Mat4 {
    Mat4 m;
    m.m0=0.0; m.m1=0.0; m.m2=0.0; m.m3=0.0;
    m.m4=0.0; m.m5=0.0; m.m6=0.0; m.m7=0.0;
    m.m8=0.0; m.m9=0.0; m.m10=0.0; m.m11=0.0;
    m.m12=0.0; m.m13=0.0; m.m14=0.0; m.m15=0.0;
    float pi = 3.14159265;
    float fov = fov_deg * pi / 180.0;
    float t = g3d_sin(fov / 2.0);
    float c = g3d_cos(fov / 2.0);
    float f = c / t;
    m.m0 = f / aspect;
    m.m5 = f;
    m.m10 = (far + near) / (near - far);
    m.m11 = (2.0 * far * near) / (near - far);
    m.m14 = -1.0;
    return m;
}

// -----------------------------
// Camera / projection
// -----------------------------
struct Camera3D {
    Vec3 pos;
    float yaw;
    float pitch;
    float fov;
    float near;
    float far;
}

fn camera3d_new(Vec3 pos) -> Camera3D {
    Camera3D c; c.pos = pos; c.yaw = 0.0; c.pitch = 0.0; c.fov = 60.0; c.near = 0.1; c.far = 100.0; return c;
}

fn camera3d_view_matrix(Camera3D* cam) -> Mat4 {
    float px = cam.pos.x;
    float py = cam.pos.y;
    float pz = cam.pos.z;
    Mat4 tr = mat4_identity();
    tr.m3 = 0.0 - px;
    tr.m7 = 0.0 - py;
    tr.m11 = 0.0 - pz;

    float yaw = cam.yaw;
    float pitch = cam.pitch;
    if (yaw == 0.0) {
        if (pitch == 0.0) { return tr; }
    }

    float nyaw = 0.0 - yaw;
    float npitch = 0.0 - pitch;
    Mat4 ry = mat4_rotate_y(nyaw);
    Mat4 rx = mat4_rotate_x(npitch);
    Mat4 rot = mat4_mul(rx, ry);
    return mat4_mul(rot, tr);
}

// -----------------------------
// Screen / frame
// -----------------------------
static int G3D_W = 800;
static int G3D_H = 600;

fn g3d_init(int w, int h) -> int {
    G3D_W = w; G3D_H = h;
    return gui_init_window(w, h, "Magnetar 3D");
}
fn g3d_clear(int color) -> void { gui_clear(color); }
fn g3d_present() -> void { gui_present(); }
fn g3d_close_requested() -> int { return gui_close_requested(); }

fn g3d_shutdown() -> void { gui_shutdown(); }

fn g3d_project(Vec4 v, int* sx, int* sy, float* outz) -> int {
    if (v.w == 0.0) { return 0; }
    float nx = v.x / v.w;
    float ny = v.y / v.w;
    float nz = v.z / v.w;
    *outz = nz;
    if (nz < -1.0 || nz > 1.0) { return 0; }
    *sx = cast<int>((nx + 1.0) * 0.5 * cast<float>(G3D_W));
    *sy = cast<int>((1.0 - ny) * 0.5 * cast<float>(G3D_H));
    return 1;
}

// -----------------------------
// 2D raster helpers (for 3D)
// -----------------------------
fn g3d_draw_line2d(int x0, int y0, int x1, int y1, int color) -> void {
    int dx = g3d_absi(x1 - x0);
    int sx = -1; if (x0 < x1) { sx = 1; }
    int dy = -g3d_absi(y1 - y0);
    int sy = -1; if (y0 < y1) { sy = 1; }
    int err = dx + dy;
    int x = x0; int y = y0;
    int guard = 0;
    while (guard < 100000) {
        gui_put_pixel(x, y, color);
        if (x == x1 && y == y1) { break; }
        int e2 = err + err;
        if (e2 >= dy) { if (x == x1) { break; } err = err + dy; x = x + sx; }
        if (e2 <= dx) { if (y == y1) { break; } err = err + dx; y = y + sy; }
        guard = guard + 1;
    }
}

fn g3d_fill_triangle2d(int x0, int y0, int x1, int y1, int x2, int y2, int color) -> void {
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
        if (xb >= 0 && xa < G3D_W && y >= 0 && y < G3D_H) {
            int cx0 = xa; if (cx0 < 0) { cx0 = 0; }
            int cx1 = xb; if (cx1 >= G3D_W) { cx1 = G3D_W - 1; }
            gui_fill_rect(cx0, y, cx1 - cx0 + 1, 1, color);
        }
        y = y + 1;
    }
}

// -----------------------------
// Mesh
// -----------------------------
struct Mesh3D {
    Vec3* verts;
    int vert_count;
    int* faces;      // triplets of vertex indices
    int face_count;  // number of triangles
    Vec3 pos;
    Vec3 rot;        // radians
    Vec3 scale;
    int color;
}

fn mesh3d_new(int vcount, int fcount) -> Mesh3D {
    Mesh3D m;
    m.verts = alloc<Vec3>(vcount);
    m.vert_count = vcount;
    m.faces = alloc<int>(fcount * 3);
    m.face_count = fcount;
    m.pos = vec3(0.0, 0.0, 0.0);
    m.rot = vec3(0.0, 0.0, 0.0);
    m.scale = vec3(1.0, 1.0, 1.0);
    m.color = gui_rgb(120, 180, 255);
    return m;
}

fn mesh3d_model_matrix(Mesh3D* m) -> Mat4 {
    Mat4 s = mat4_scale(m.scale.x, m.scale.y, m.scale.z);
    Mat4 rx = mat4_rotate_x(m.rot.x);
    Mat4 ry = mat4_rotate_y(m.rot.y);
    Mat4 rz = mat4_rotate_z(m.rot.z);
    Mat4 t = mat4_translate(m.pos.x, m.pos.y, m.pos.z);
    // t * rz * ry * rx * s
    Mat4 rxy = mat4_mul(ry, rx);
    Mat4 rxyz = mat4_mul(rz, rxy);
    Mat4 sr = mat4_mul(rxyz, s);
    return mat4_mul(t, sr);
}

fn mesh3d_make_cube(float size) -> Mesh3D {
    Mesh3D m = mesh3d_new(8, 12);
    float h = size * 0.5;
    m.verts[0] = vec3(-h,-h,-h); m.verts[1] = vec3( h,-h,-h);
    m.verts[2] = vec3( h, h,-h); m.verts[3] = vec3(-h, h,-h);
    m.verts[4] = vec3(-h,-h, h); m.verts[5] = vec3( h,-h, h);
    m.verts[6] = vec3( h, h, h); m.verts[7] = vec3(-h, h, h);
    int f = 0;
    // front
    m.faces[f]=0; m.faces[f+1]=1; m.faces[f+2]=2; f=f+3;
    m.faces[f]=0; m.faces[f+1]=2; m.faces[f+2]=3; f=f+3;
    // back
    m.faces[f]=5; m.faces[f+1]=4; m.faces[f+2]=7; f=f+3;
    m.faces[f]=5; m.faces[f+1]=7; m.faces[f+2]=6; f=f+3;
    // left
    m.faces[f]=4; m.faces[f+1]=0; m.faces[f+2]=3; f=f+3;
    m.faces[f]=4; m.faces[f+1]=3; m.faces[f+2]=7; f=f+3;
    // right
    m.faces[f]=1; m.faces[f+1]=5; m.faces[f+2]=6; f=f+3;
    m.faces[f]=1; m.faces[f+1]=6; m.faces[f+2]=2; f=f+3;
    // top
    m.faces[f]=3; m.faces[f+1]=2; m.faces[f+2]=6; f=f+3;
    m.faces[f]=3; m.faces[f+1]=6; m.faces[f+2]=7; f=f+3;
    // bottom
    m.faces[f]=4; m.faces[f+1]=5; m.faces[f+2]=1; f=f+3;
    m.faces[f]=4; m.faces[f+1]=1; m.faces[f+2]=0; f=f+3;
    return m;
}

fn g3d_color_mul(int color, float k) -> int {
    if (k < 0.0) { k = 0.0; }
    if (k > 1.0) { k = 1.0; }
    int r = color / 65536;
    int g = (color / 256) - r * 256;
    int b = color - (color / 256) * 256;
    r = cast<int>(cast<float>(r) * k);
    g = cast<int>(cast<float>(g) * k);
    b = cast<int>(cast<float>(b) * k);
    if (r < 0) { r = 0; } if (r > 255) { r = 255; }
    if (g < 0) { g = 0; } if (g > 255) { g = 255; }
    if (b < 0) { b = 0; } if (b > 255) { b = 255; }
    return r * 65536 + g * 256 + b;
}

// Draw wireframe mesh
fn g3d_draw_mesh_wire(Mesh3D* mesh, Camera3D* cam, int color) -> void {
    float aspect = cast<float>(G3D_W) / cast<float>(G3D_H);
    Mat4 proj = mat4_perspective(cam.fov, aspect, cam.near, cam.far);
    Mat4 view = camera3d_view_matrix(cam);
    Mat4 model = mesh3d_model_matrix(mesh);
    Mat4 vm = mat4_mul(view, model);
    Mat4 mvp = mat4_mul(proj, vm);
    // project vertices
    Vec2i3* pv = alloc<Vec2i3>(mesh.vert_count);
    int* ok = alloc<int>(mesh.vert_count);
    int i = 0;
    while (i < mesh.vert_count) {
        Vec4 v = vec4(mesh.verts[i].x, mesh.verts[i].y, mesh.verts[i].z, 1.0);
        Vec4 tv = mat4_mul_vec4(mvp, v);
        int sx = 0; int sy = 0; float oz = 0.0;
        ok[i] = g3d_project(tv, &sx, &sy, &oz);
        pv[i].x = sx; pv[i].y = sy; pv[i].z = oz;
        i = i + 1;
    }
    i = 0;
    while (i < mesh.face_count) {
        int i0 = mesh.faces[i*3];
        int i1 = mesh.faces[i*3 + 1];
        int i2 = mesh.faces[i*3 + 2];
        if (ok[i0] == 1 && ok[i1] == 1) { g3d_draw_line2d(pv[i0].x, pv[i0].y, pv[i1].x, pv[i1].y, color); }
        if (ok[i1] == 1 && ok[i2] == 1) { g3d_draw_line2d(pv[i1].x, pv[i1].y, pv[i2].x, pv[i2].y, color); }
        if (ok[i2] == 1 && ok[i0] == 1) { g3d_draw_line2d(pv[i2].x, pv[i2].y, pv[i0].x, pv[i0].y, color); }
        i = i + 1;
    }
    free(pv);
    free(ok);
}

// Draw flat-shaded mesh with painter's algorithm
fn g3d_draw_mesh_flat(Mesh3D* mesh, Camera3D* cam, Vec3 light_dir) -> void {
    float aspect = cast<float>(G3D_W) / cast<float>(G3D_H);
    Mat4 proj = mat4_perspective(cam.fov, aspect, cam.near, cam.far);
    Mat4 view = camera3d_view_matrix(cam);
    Mat4 model = mesh3d_model_matrix(mesh);
    Mat4 vm = mat4_mul(view, model);
    Mat4 mvp = mat4_mul(proj, vm);

    // world-space transform for lighting
    Vec3* wv = alloc<Vec3>(mesh.vert_count);
    Vec2i3* pv = alloc<Vec2i3>(mesh.vert_count);
    int* ok = alloc<int>(mesh.vert_count);
    int i = 0;
    while (i < mesh.vert_count) {
        Vec4 v = vec4(mesh.verts[i].x, mesh.verts[i].y, mesh.verts[i].z, 1.0);
        Vec4 tvw = mat4_mul_vec4(model, v);
        wv[i] = vec3(tvw.x, tvw.y, tvw.z);
        Vec4 tv = mat4_mul_vec4(mvp, v);
        int sx = 0; int sy = 0; float oz = 0.0;
        ok[i] = g3d_project(tv, &sx, &sy, &oz);
        pv[i].x = sx; pv[i].y = sy; pv[i].z = oz;
        i = i + 1;
    }

    // compute face depths and order
    float* fz = alloc<float>(mesh.face_count);
    int* ord = alloc<int>(mesh.face_count);
    i = 0;
    while (i < mesh.face_count) {
        int i0 = mesh.faces[i*3]; int i1 = mesh.faces[i*3+1]; int i2 = mesh.faces[i*3+2];
        fz[i] = (pv[i0].z + pv[i1].z + pv[i2].z) / 3.0;
        ord[i] = i;
        i = i + 1;
    }
    // simple selection sort by depth descending (painter's)
    i = 0;
    while (i < mesh.face_count) {
        int maxj = i;
        int j = i + 1;
        while (j < mesh.face_count) {
            if (fz[ord[j]] > fz[ord[maxj]]) { maxj = j; }
            j = j + 1;
        }
        int tmp = ord[i]; ord[i] = ord[maxj]; ord[maxj] = tmp;
        i = i + 1;
    }

    Vec3 ld = v3_norm(light_dir);
    i = 0;
    while (i < mesh.face_count) {
        int fi = ord[i];
        int i0 = mesh.faces[fi*3]; int i1 = mesh.faces[fi*3+1]; int i2 = mesh.faces[fi*3+2];
        if (ok[i0] == 1 && ok[i1] == 1 && ok[i2] == 1) {
            int ax = pv[i1].x - pv[i0].x;
            int ay = pv[i1].y - pv[i0].y;
            int bx = pv[i2].x - pv[i0].x;
            int by = pv[i2].y - pv[i0].y;
            int crossz = ax * by - ay * bx;
            if (crossz != 0) {
                Vec3 e1 = v3_sub(wv[i1], wv[i0]);
                Vec3 e2 = v3_sub(wv[i2], wv[i0]);
                Vec3 n = v3_norm(v3_cross(e1, e2));
                float diff = v3_dot(n, ld);
                if (diff < 0.0) { diff = 0.0 - diff; }
                float shade = 0.35 + diff * 0.65;
                int col = g3d_color_mul(mesh.color, shade);
                g3d_fill_triangle2d(pv[i0].x, pv[i0].y, pv[i1].x, pv[i1].y, pv[i2].x, pv[i2].y, col);
            }
        }
        i = i + 1;
    }

    free(wv); free(pv); free(ok); free(fz); free(ord);
}
