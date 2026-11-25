// ============================================================================
// Magnetar Vision Library (lib/vision.mg)
// Camera capture + object detection helpers for small robots.
//
// Features:
//   - Camera frame capture via ffmpeg + V4L2 (/dev/videoX) into PPM
//   - Frame loading as Image* (lib/image.mg)
//   - RGB <-> HSV conversion and color-range matching
//   - Blob/object detection by RGB or HSV range (connected components)
//   - Results: bounding box, centroid, area, average color, label
//   - Annotation drawing and robot steering helpers
//
// Typical robot loop:
//   use "lib/image.mg";
//   use "lib/vision.mg";
//
//   VisionResult res;
//   vision_result_init(&res, 16);
//   Image* frame = vision_grab_frame("/dev/video0", 320, 240);
//   if (frame != null) {
//       vision_detect_blue(frame, 80, &res);          // label 3
//       int i = vision_find_largest(&res);
//       if (i >= 0) {
//           VisionObject obj = vision_get_object(&res, i);
//           int steer = vision_object_steer_x(obj, frame.width); // -100..100
//           int near  = vision_object_area_ratio(obj, frame.width, frame.height);
//       }
//       image_destroy(frame);
//   }
//   vision_result_free(&res);
//
// Notes:
//   - Capture requires ffmpeg with v4l2 support (external tool, fork/exec).
//   - Detection is color/blob based (fast/practical for markers & colored objects).
//   - Designed for small robot frames (e.g. 160x120 .. 320x240).
// ============================================================================

use "lib/image.mg";

extern fn sys_open(string path, int flags, int mode) -> int;
extern fn sys_close(int fd) -> int;
extern fn sys_read(int fd, char* buf, int count) -> int;
extern fn sys_write(int fd, char* data, int count) -> int;
extern fn sys_unlink(string path) -> int;
extern fn sys_pipe(char* fds) -> int;
extern fn sys_dup2(int oldfd, int newfd) -> int;
extern fn sys_fork() -> int;
extern fn sys_execve(string path, char** argv, char** envp) -> int;
extern fn sys_wait4(int pid, int* wstatus, int options, char* rusage) -> int;
extern fn sys_kill(int pid, int sig) -> int;
extern fn sys_exit(int code) -> void;
extern fn sys_access(string path, int mode) -> int;

// -----------------------------
// Data structures
// -----------------------------

struct VisionColorHSV {
    int h; // 0..360
    int s; // 0..100
    int v; // 0..100
}

struct VisionObject {
    int id;
    int label;
    int x;
    int y;
    int w;
    int h;
    int cx;
    int cy;
    int area;
    int r;
    int g;
    int b;
}

struct VisionResult {
    int count;
    int capacity;
    int width;
    int height;
    char* ids;
    char* labels;
    char* xs;
    char* ys;
    char* ws;
    char* hs;
    char* cxs;
    char* cys;
    char* areas;
    char* rs;
    char* gs;
    char* bs;
}

struct VisionMotion {
    Image* prev;
    int w;
    int h;
    int threshold;
    int initialized;
}

struct VisionStream {
    int pid;
    int fd;
    int w;
    int h;
    int frame_size;  // w*h*3 (rgb24)
    int active;
    char* buf;       // rgb24 read buffer
}

static char** VISION_ENVP = null;
static int VISION_ENV_LOADED = 0;
static int VISION_TMP_COUNTER = 0;

static char* V_SCRATCH_MASK = null;
static char* V_SCRATCH_Q = null;
static int V_SCRATCH_SIZE = 0;

// -----------------------------
// Low-level helpers
// -----------------------------

fn vision_init_env() -> void {
    if (VISION_ENV_LOADED == 1) { return; }
    VISION_ENVP = alloc<char*>(8);
    VISION_ENVP[0] = cast<char*>("PATH=/usr/local/bin:/usr/bin:/bin");
    VISION_ENVP[1] = cast<char*>("HOME=/tmp");
    VISION_ENVP[2] = null;
    VISION_ENV_LOADED = 1;
}

fn v_abs(int x) -> int { if (x < 0) { return 0 - x; } return x; }
fn v_min(int a, int b) -> int { if (a < b) { return a; } return b; }
fn v_max(int a, int b) -> int { if (a > b) { return a; } return b; }
fn v_clamp(int v, int lo, int hi) -> int { if (v < lo) { return lo; } if (v > hi) { return hi; } return v; }

fn v_byte(char* p, int i) -> int {
    int v = cast<int>(*(p + i));
    if (v < 0) { v = v + 256; }
    return v;
}

fn v_wr32(char* p, int off, int v) -> void {
    *(p + off) = cast<char>(v & 255);
    *(p + off + 1) = cast<char>((v / 256) & 255);
    *(p + off + 2) = cast<char>((v / 65536) & 255);
    *(p + off + 3) = cast<char>((v / 16777216) & 255);
}

fn v_rd32(char* p, int off) -> int {
    int b0 = v_byte(p, off);
    int b1 = v_byte(p, off + 1);
    int b2 = v_byte(p, off + 2);
    int b3 = v_byte(p, off + 3);
    return b0 + b1 * 256 + b2 * 65536 + b3 * 16777216;
}

fn v_strcpy(char* dst, string src) -> int {
    if (src == null) { *dst = 0; return 0; }
    char* p = cast<char*>(src);
    int i = 0;
    while (*(p + i) != 0) {
        *(dst + i) = *(p + i);
        i = i + 1;
    }
    *(dst + i) = 0;
    return i;
}

fn v_i2s(int n, char* buf) -> int {
    if (n == 0) { *(buf) = 48; *(buf + 1) = 0; return 1; }
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
    return out;
}

fn v_make_size_str(int w, int h, char* out) -> void {
    char* a = alloc<char>(16);
    char* b = alloc<char>(16);
    v_i2s(w, a);
    v_i2s(h, b);
    int p = v_strcpy(out, cast<string>(a));
    *(out + p) = 120; // 'x'
    p = p + 1;
    p = p + v_strcpy(out + p, cast<string>(b));
    *(out + p) = 0;
    free(a);
    free(b);
}

fn v_make_scale_str(int w, int h, char* out) -> void {
    char* a = alloc<char>(16);
    char* b = alloc<char>(16);
    v_i2s(w, a);
    v_i2s(h, b);
    int p = v_strcpy(out, "scale=");
    p = p + v_strcpy(out + p, cast<string>(a));
    *(out + p) = 58; // ':'
    p = p + 1;
    p = p + v_strcpy(out + p, cast<string>(b));
    *(out + p) = 0;
    free(a);
    free(b);
}

fn v_tmp_path(char* out) -> void {
    VISION_TMP_COUNTER = VISION_TMP_COUNTER + 1;
    char* nbuf = alloc<char>(16);
    v_i2s(VISION_TMP_COUNTER, nbuf);
    int p = v_strcpy(out, "/tmp/mg_vision_");
    p = p + v_strcpy(out + p, cast<string>(nbuf));
    p = p + v_strcpy(out + p, ".ppm");
    *(out + p) = 0;
    free(nbuf);
}

// -----------------------------
// Camera capture (ffmpeg / V4L2)
// -----------------------------

fn vision_camera_available(string device) -> bool {
    if (sys_access(device, 0) == 0) { return true; }
    return false;
}

fn vision_ffmpeg_available() -> bool {
    if (sys_access("/usr/bin/ffmpeg", 1) == 0) { return true; }
    if (sys_access("/bin/ffmpeg", 1) == 0) { return true; }
    return false;
}

fn _v_exec_capture(string device, int w, int h, string out_path) -> int {
    vision_init_env();
    string ff = "/usr/bin/ffmpeg";
    if (sys_access("/usr/bin/ffmpeg", 1) != 0) {
        if (sys_access("/bin/ffmpeg", 1) == 0) { ff = "/bin/ffmpeg"; }
        else { return -1; }
    }
    char* sizebuf = alloc<char>(32);
    v_make_size_str(w, h, sizebuf);

    int pid = sys_fork();
    if (pid < 0) { free(sizebuf); return -1; }
    if (pid == 0) {
        char** argv = alloc<char*>(20);
        argv[0] = cast<char*>("ffmpeg");
        argv[1] = cast<char*>("-nostdin");
        argv[2] = cast<char*>("-loglevel");
        argv[3] = cast<char*>("error");
        argv[4] = cast<char*>("-f");
        argv[5] = cast<char*>("v4l2");
        argv[6] = cast<char*>("-video_size");
        argv[7] = sizebuf;
        argv[8] = cast<char*>("-i");
        argv[9] = cast<char*>(device);
        argv[10] = cast<char*>("-frames:v");
        argv[11] = cast<char*>("1");
        argv[12] = cast<char*>("-y");
        argv[13] = cast<char*>(out_path);
        argv[14] = null;
        sys_execve(ff, argv, VISION_ENVP);
        sys_execve("/bin/ffmpeg", argv, VISION_ENVP);
        sys_exit(127);
    }
    int status = 0;
    sys_wait4(pid, &status, 0, null);
    free(sizebuf);
    return status / 256;
}

fn vision_capture(string device, int w, int h, string out_path) -> bool {
    int rc = _v_exec_capture(device, w, h, out_path);
    if (rc != 0) { return false; }
    if (sys_access(out_path, 0) != 0) { return false; }
    return true;
}

fn vision_grab_frame(string device, int w, int h) -> Image* {
    char* tmp = alloc<char>(64);
    v_tmp_path(tmp);
    string path = cast<string>(tmp);
    Image* img = null;
    if (vision_capture(device, w, h, path) == true) {
        img = image_load(path);
    }
    sys_unlink(path);
    free(tmp);
    return img;
}

// -----------------------------
// Continuous camera stream (fast, ffmpeg rawvideo pipe)
// -----------------------------

fn _v_read_exact(int fd, char* buf, int len) -> int {
    int got = 0;
    while (got < len) {
        int n = sys_read(fd, buf + got, len - got);
        if (n <= 0) { return got; }
        got = got + n;
    }
    return got;
}

fn _v_make_size_str2(int w, int h, char* out) -> void {
    v_make_size_str(w, h, out);
}

fn vision_stream_init(VisionStream* s) -> void {
    s.pid = -1;
    s.fd = -1;
    s.w = 0;
    s.h = 0;
    s.frame_size = 0;
    s.active = 0;
    s.buf = null;
}

fn vision_stream_close(VisionStream* s) -> void {
    if (s == null) { return; }
    if (s.fd >= 0) { sys_close(s.fd); s.fd = -1; }
    if (s.pid > 0) {
        sys_kill(s.pid, 15);
        int status = 0;
        sys_wait4(s.pid, &status, 0, null);
        s.pid = -1;
    }
    if (s.buf != null) { free(s.buf); s.buf = null; }
    s.active = 0;
    s.frame_size = 0;
}

fn vision_stream_open(VisionStream* s, string device, int w, int h) -> bool {
    if (s == null) { return false; }
    vision_stream_init(s);
    if (w <= 0 || h <= 0) { return false; }
    if (vision_ffmpeg_available() == false) { return false; }
    string ff = "/usr/bin/ffmpeg";
    if (sys_access("/usr/bin/ffmpeg", 1) != 0) {
        if (sys_access("/bin/ffmpeg", 1) == 0) { ff = "/bin/ffmpeg"; }
        else { return false; }
    }

    char* pfds = alloc<char>(8);
    *(pfds + 0) = 0; *(pfds + 1) = 0; *(pfds + 2) = 0; *(pfds + 3) = 0;
    *(pfds + 4) = 0; *(pfds + 5) = 0; *(pfds + 6) = 0; *(pfds + 7) = 0;
    if (sys_pipe(pfds) != 0) { free(pfds); return false; }
    int rfd = v_byte(pfds, 0) + v_byte(pfds, 1) * 256 + v_byte(pfds, 2) * 65536 + cast<int>(*(pfds + 3)) * 16777216;
    int wfd = v_byte(pfds, 4) + v_byte(pfds, 5) * 256 + v_byte(pfds, 6) * 65536 + cast<int>(*(pfds + 7)) * 16777216;
    free(pfds);

    char* sizebuf = alloc<char>(32);
    v_make_size_str(w, h, sizebuf);
    char* scalefilter = alloc<char>(64);
    v_make_scale_str(w, h, scalefilter);

    int pid = sys_fork();
    if (pid < 0) {
        sys_close(rfd); sys_close(wfd); free(sizebuf); free(scalefilter);
        return false;
    }
    if (pid == 0) {
        sys_dup2(wfd, 1);
        sys_close(rfd);
        if (wfd > 1) { sys_close(wfd); }
        int devnull = sys_open("/dev/null", 1, 0);
        if (devnull >= 0) { sys_dup2(devnull, 2); if (devnull > 2) { sys_close(devnull); } }

        char** argv = alloc<char*>(32);
        argv[0] = cast<char*>("ffmpeg");
        argv[1] = cast<char*>("-nostdin");
        argv[2] = cast<char*>("-loglevel");
        argv[3] = cast<char*>("error");
        argv[4] = cast<char*>("-fflags");
        argv[5] = cast<char*>("nobuffer");
        argv[6] = cast<char*>("-flags");
        argv[7] = cast<char*>("low_delay");
        argv[8] = cast<char*>("-f");
        argv[9] = cast<char*>("v4l2");
        argv[10] = cast<char*>("-framerate");
        argv[11] = cast<char*>("30");
        argv[12] = cast<char*>("-video_size");
        argv[13] = sizebuf;
        argv[14] = cast<char*>("-i");
        argv[15] = cast<char*>(device);
        argv[16] = cast<char*>("-an");
        argv[17] = cast<char*>("-vf");
        argv[18] = scalefilter;
        argv[19] = cast<char*>("-fps_mode");
        argv[20] = cast<char*>("passthrough");
        argv[21] = cast<char*>("-f");
        argv[22] = cast<char*>("rawvideo");
        argv[23] = cast<char*>("-pix_fmt");
        argv[24] = cast<char*>("rgb24");
        argv[25] = cast<char*>("-");
        argv[26] = null;
        sys_execve(ff, argv, VISION_ENVP);
        sys_execve("/bin/ffmpeg", argv, VISION_ENVP);
        sys_exit(127);
    }

    sys_close(wfd);
    free(sizebuf);
    free(scalefilter);

    s.pid = pid;
    s.fd = rfd;
    s.w = w;
    s.h = h;
    s.frame_size = w * h * 3;
    s.buf = alloc<char>(s.frame_size);
    s.active = 1;
    return true;
}

// Read next frame into img (must be w x h RGBA). Returns true on success.
fn vision_stream_read(VisionStream* s, Image* img) -> bool {
    if (s == null || s.active == 0 || s.fd < 0) { return false; }
    if (img == null || img.data == null) { return false; }
    if (img.width != s.w || img.height != s.h) { return false; }
    int need = s.frame_size;
    int got = _v_read_exact(s.fd, s.buf, need);
    if (got != need) { return false; }
    // rgb24 -> rgba
    int pixels = s.w * s.h;
    int i = 0;
    int si = 0;
    while (i < pixels) {
        int di = i * 4;
        *(img.data + di) = *(s.buf + si);
        *(img.data + di + 1) = *(s.buf + si + 1);
        *(img.data + di + 2) = *(s.buf + si + 2);
        *(img.data + di + 3) = cast<char>(255);
        si = si + 3;
        i = i + 1;
    }
    return true;
}

// -----------------------------
// Color conversion / matching
// -----------------------------

fn vision_rgb_to_hsv(int r, int g, int b) -> VisionColorHSV {
    VisionColorHSV out;
    int maxv = r; if (g > maxv) { maxv = g; } if (b > maxv) { maxv = b; }
    int minv = r; if (g < minv) { minv = g; } if (b < minv) { minv = b; }
    int delta = maxv - minv;
    out.v = maxv * 100 / 255;
    if (maxv == 0) {
        out.s = 0; out.h = 0; return out;
    }
    out.s = delta * 100 / maxv;
    if (delta == 0) {
        out.h = 0; return out;
    }
    int h = 0;
    if (maxv == r) {
        h = 60 * (g - b) / delta;
    } else if (maxv == g) {
        h = 120 + 60 * (b - r) / delta;
    } else {
        h = 240 + 60 * (r - g) / delta;
    }
    if (h < 0) { h = h + 360; }
    if (h >= 360) { h = h - 360; }
    out.h = h;
    return out;
}

fn vision_hsv_match(VisionColorHSV c, int hmin, int smin, int vmin, int hmax, int smax, int vmax) -> bool {
    if (c.s < smin || c.s > smax) { return false; }
    if (c.v < vmin || c.v > vmax) { return false; }
    if (hmin <= hmax) {
        if (c.h < hmin || c.h > hmax) { return false; }
    } else {
        if (c.h < hmin && c.h > hmax) { return false; }
    }
    return true;
}

fn vision_rgb_match(int r, int g, int b, int rmin, int gmin, int bmin, int rmax, int gmax, int bmax) -> bool {
    if (r < rmin || r > rmax) { return false; }
    if (g < gmin || g > gmax) { return false; }
    if (b < bmin || b > bmax) { return false; }
    return true;
}

// -----------------------------
// Result management
// -----------------------------

fn vision_result_init(VisionResult* res, int capacity) -> void {
    if (capacity < 1) { capacity = 8; }
    res.count = 0;
    res.capacity = capacity;
    res.width = 0;
    res.height = 0;
    res.ids = alloc<char>(capacity * 4);
    res.labels = alloc<char>(capacity * 4);
    res.xs = alloc<char>(capacity * 4);
    res.ys = alloc<char>(capacity * 4);
    res.ws = alloc<char>(capacity * 4);
    res.hs = alloc<char>(capacity * 4);
    res.cxs = alloc<char>(capacity * 4);
    res.cys = alloc<char>(capacity * 4);
    res.areas = alloc<char>(capacity * 4);
    res.rs = alloc<char>(capacity * 4);
    res.gs = alloc<char>(capacity * 4);
    res.bs = alloc<char>(capacity * 4);
}

fn vision_result_reset(VisionResult* res) -> void {
    if (res != null) { res.count = 0; }
}

fn vision_result_free(VisionResult* res) -> void {
    if (res == null) { return; }
    if (res.capacity > 0) {
        if (res.ids != null) { free(res.ids); }
        if (res.labels != null) { free(res.labels); }
        if (res.xs != null) { free(res.xs); }
        if (res.ys != null) { free(res.ys); }
        if (res.ws != null) { free(res.ws); }
        if (res.hs != null) { free(res.hs); }
        if (res.cxs != null) { free(res.cxs); }
        if (res.cys != null) { free(res.cys); }
        if (res.areas != null) { free(res.areas); }
        if (res.rs != null) { free(res.rs); }
        if (res.gs != null) { free(res.gs); }
        if (res.bs != null) { free(res.bs); }
    }
    res.ids = null; res.labels = null; res.xs = null; res.ys = null;
    res.ws = null; res.hs = null; res.cxs = null; res.cys = null;
    res.areas = null; res.rs = null; res.gs = null; res.bs = null;
    res.count = 0; res.capacity = 0;
}

fn _v_result_set(VisionResult* res, int idx,
                 int id, int label, int x, int y, int w, int h,
                 int cx, int cy, int area, int r, int g, int b) -> void {
    int off = idx * 4;
    v_wr32(res.ids, off, id);
    v_wr32(res.labels, off, label);
    v_wr32(res.xs, off, x);
    v_wr32(res.ys, off, y);
    v_wr32(res.ws, off, w);
    v_wr32(res.hs, off, h);
    v_wr32(res.cxs, off, cx);
    v_wr32(res.cys, off, cy);
    v_wr32(res.areas, off, area);
    v_wr32(res.rs, off, r);
    v_wr32(res.gs, off, g);
    v_wr32(res.bs, off, b);
}

fn vision_result_add(VisionResult* res, VisionObject obj) -> void {
    if (res == null) { return; }
    if (res.count >= res.capacity) { return; }
    _v_result_set(res, res.count, obj.id, obj.label, obj.x, obj.y, obj.w, obj.h,
                  obj.cx, obj.cy, obj.area, obj.r, obj.g, obj.b);
    res.count = res.count + 1;
}

fn vision_get_object(VisionResult* res, int i) -> VisionObject {
    VisionObject o;
    o.id = 0; o.label = 0; o.x = 0; o.y = 0; o.w = 0; o.h = 0;
    o.cx = 0; o.cy = 0; o.area = 0; o.r = 0; o.g = 0; o.b = 0;
    if (res == null) { return o; }
    if (i < 0 || i >= res.count) { return o; }
    int off = i * 4;
    o.id = v_rd32(res.ids, off);
    o.label = v_rd32(res.labels, off);
    o.x = v_rd32(res.xs, off);
    o.y = v_rd32(res.ys, off);
    o.w = v_rd32(res.ws, off);
    o.h = v_rd32(res.hs, off);
    o.cx = v_rd32(res.cxs, off);
    o.cy = v_rd32(res.cys, off);
    o.area = v_rd32(res.areas, off);
    o.r = v_rd32(res.rs, off);
    o.g = v_rd32(res.gs, off);
    o.b = v_rd32(res.bs, off);
    return o;
}

fn vision_find_largest(VisionResult* res) -> int {
    if (res == null) { return -1; }
    if (res.count <= 0) { return -1; }
    int best = 0;
    int best_area = v_rd32(res.areas, 0);
    int i = 1;
    while (i < res.count) {
        int a = v_rd32(res.areas, i * 4);
        if (a > best_area) { best_area = a; best = i; }
        i = i + 1;
    }
    return best;
}

// -----------------------------
// Blob detection (connected components via BFS)
// -----------------------------

fn _v_ensure_scratch(int total) -> void {
    if (total <= 0) { return; }
    if (V_SCRATCH_SIZE >= total && V_SCRATCH_MASK != null && V_SCRATCH_Q != null) { return; }
    if (V_SCRATCH_MASK != null) { free(V_SCRATCH_MASK); V_SCRATCH_MASK = null; }
    if (V_SCRATCH_Q != null) { free(V_SCRATCH_Q); V_SCRATCH_Q = null; }
    V_SCRATCH_MASK = alloc<char>(total);
    V_SCRATCH_Q = alloc<char>(total * 8);
    V_SCRATCH_SIZE = total;
}

fn _v_push_blob(VisionResult* res, int id, int label,
                int area, int sumx, int sumy,
                int minx, int miny, int maxx, int maxy,
                int sumr, int sumg, int sumb) -> void {
    if (area <= 0) { return; }
    if (res == null) { return; }
    if (res.count >= res.capacity) { return; }
    int wbox = maxx - minx + 1;
    int hbox = maxy - miny + 1;
    int cx = sumx / area;
    int cy = sumy / area;
    int ar = sumr / area;
    int ag = sumg / area;
    int ab = sumb / area;
    _v_result_set(res, res.count, id, label, minx, miny, wbox, hbox, cx, cy, area, ar, ag, ab);
    res.count = res.count + 1;
}

fn _v_detect_from_mask(Image* img, char* mask, int min_area, int label, VisionResult* res) -> int {
    int w = img.width;
    int h = img.height;
    int total = w * h;
    if (total <= 0) { return 0; }

    _v_ensure_scratch(total);
    char* q = V_SCRATCH_Q;
    int found = 0;
    int y = 0;
    while (y < h) {
        int x = 0;
        while (x < w) {
            int idx = y * w + x;
            if (*(mask + idx) == 1) {
                int head = 0;
                int tail = 0;
                v_wr32(q, 0, x);
                v_wr32(q, 4, y);
                tail = 1;
                *(mask + idx) = 0;

                int area = 0;
                int sumx = 0; int sumy = 0;
                int minx = x; int maxx = x; int miny = y; int maxy = y;
                int sumr = 0; int sumg = 0; int sumb = 0;

                while (head < tail) {
                    int cx = v_rd32(q, head * 8);
                    int cy = v_rd32(q, head * 8 + 4);
                    head = head + 1;

                    area = area + 1;
                    sumx = sumx + cx;
                    sumy = sumy + cy;
                    if (cx < minx) { minx = cx; }
                    if (cx > maxx) { maxx = cx; }
                    if (cy < miny) { miny = cy; }
                    if (cy > maxy) { maxy = cy; }

                    int coff = cy * img.stride + cx * 4;
                    sumr = sumr + v_byte(img.data, coff);
                    sumg = sumg + v_byte(img.data, coff + 1);
                    sumb = sumb + v_byte(img.data, coff + 2);

                    // 4-neighborhood
                    int nx = cx - 1;
                    if (nx >= 0) {
                        int nidx = cy * w + nx;
                        if (*(mask + nidx) == 1) {
                            *(mask + nidx) = 0;
                            v_wr32(q, tail * 8, nx);
                            v_wr32(q, tail * 8 + 4, cy);
                            tail = tail + 1;
                        }
                    }
                    nx = cx + 1;
                    if (nx < w) {
                        int nidx = cy * w + nx;
                        if (*(mask + nidx) == 1) {
                            *(mask + nidx) = 0;
                            v_wr32(q, tail * 8, nx);
                            v_wr32(q, tail * 8 + 4, cy);
                            tail = tail + 1;
                        }
                    }
                    int ny = cy - 1;
                    if (ny >= 0) {
                        int nidx = ny * w + cx;
                        if (*(mask + nidx) == 1) {
                            *(mask + nidx) = 0;
                            v_wr32(q, tail * 8, cx);
                            v_wr32(q, tail * 8 + 4, ny);
                            tail = tail + 1;
                        }
                    }
                    ny = cy + 1;
                    if (ny < h) {
                        int nidx = ny * w + cx;
                        if (*(mask + nidx) == 1) {
                            *(mask + nidx) = 0;
                            v_wr32(q, tail * 8, cx);
                            v_wr32(q, tail * 8 + 4, ny);
                            tail = tail + 1;
                        }
                    }
                }

                if (area >= min_area) {
                    _v_push_blob(res, found, label, area, sumx, sumy, minx, miny, maxx, maxy, sumr, sumg, sumb);
                    found = found + 1;
                }
            }
            x = x + 1;
        }
        y = y + 1;
    }

    return res.count;
}

fn vision_detect_rgb_range(Image* img, int rmin, int gmin, int bmin, int rmax, int gmax, int bmax, int min_area, int label, VisionResult* res) -> int {
    if (res == null) { return 0; }
    vision_result_reset(res);
    if (img == null) { return 0; }
    if (img.data == null) { return 0; }
    res.width = img.width; res.height = img.height;
    int w = img.width;
    int h = img.height;
    int total = w * h;
    if (total <= 0) { return 0; }

    _v_ensure_scratch(total);
    char* mask = V_SCRATCH_MASK;
    int i = 0;
    while (i < total) {
        int py = i / w;
        int px = i - py * w;
        int off = py * img.stride + px * 4;
        int r = v_byte(img.data, off);
        int g = v_byte(img.data, off + 1);
        int b = v_byte(img.data, off + 2);
        if (vision_rgb_match(r, g, b, rmin, gmin, bmin, rmax, gmax, bmax) == true) {
            *(mask + i) = 1;
        } else {
            *(mask + i) = 0;
        }
        i = i + 1;
    }

    _v_detect_from_mask(img, mask, min_area, label, res);
    return res.count;
}

fn vision_detect_hsv_range(Image* img, int hmin, int smin, int vmin, int hmax, int smax, int vmax, int min_area, int label, VisionResult* res) -> int {
    if (res == null) { return 0; }
    vision_result_reset(res);
    if (img == null) { return 0; }
    if (img.data == null) { return 0; }
    res.width = img.width; res.height = img.height;
    int w = img.width;
    int h = img.height;
    int total = w * h;
    if (total <= 0) { return 0; }

    _v_ensure_scratch(total);
    char* mask = V_SCRATCH_MASK;
    int i = 0;
    while (i < total) {
        int py = i / w;
        int px = i - py * w;
        int off = py * img.stride + px * 4;
        int r = v_byte(img.data, off);
        int g = v_byte(img.data, off + 1);
        int b = v_byte(img.data, off + 2);
        VisionColorHSV hsv = vision_rgb_to_hsv(r, g, b);
        if (vision_hsv_match(hsv, hmin, smin, vmin, hmax, smax, vmax) == true) {
            *(mask + i) = 1;
        } else {
            *(mask + i) = 0;
        }
        i = i + 1;
    }

    _v_detect_from_mask(img, mask, min_area, label, res);
    return res.count;
}

// Convenience color presets (labels: 1=red, 2=green, 3=blue)
fn vision_detect_red(Image* img, int min_area, VisionResult* res) -> int {
    if (res == null) { return 0; }
    vision_result_reset(res);
    VisionResult tmp;
    vision_result_init(&tmp, 8);
    vision_detect_hsv_range(img, 345, 40, 30, 360, 100, 100, min_area, 1, res);
    vision_detect_hsv_range(img, 0, 40, 30, 15, 100, 100, min_area, 1, &tmp);
    int i = 0;
    while (i < tmp.count) {
        VisionObject o = vision_get_object(&tmp, i);
        vision_result_add(res, o);
        i = i + 1;
    }
    vision_result_free(&tmp);
    return res.count;
}

fn vision_detect_green(Image* img, int min_area, VisionResult* res) -> int {
    return vision_detect_hsv_range(img, 70, 30, 25, 170, 100, 100, min_area, 2, res);
}

fn vision_detect_blue(Image* img, int min_area, VisionResult* res) -> int {
    return vision_detect_hsv_range(img, 190, 30, 25, 260, 100, 100, min_area, 3, res);
}

// -----------------------------
// Motion detection (frame differencing)
// Reports only pixels that changed since the previous frame, so a
// stationary object disappears as soon as it stops moving.
// -----------------------------

fn vision_motion_init(VisionMotion* m, int w, int h, int threshold) -> void {
    if (m == null) { return; }
    m.w = w;
    m.h = h;
    m.threshold = threshold;
    m.initialized = 0;
    m.prev = null;
    if (w > 0 && h > 0) { m.prev = image_new(w, h); }
}

fn vision_motion_reset(VisionMotion* m) -> void {
    if (m != null) { m.initialized = 0; }
}

fn vision_motion_free(VisionMotion* m) -> void {
    if (m == null) { return; }
    if (m.prev != null) { image_destroy(m.prev); m.prev = null; }
    m.initialized = 0;
}

fn _v_frame_copy(Image* dst, Image* src) -> void {
    int w = src.width;
    int h = src.height;
    int y = 0;
    while (y < h) {
        int x = 0;
        while (x < w) {
            int off = y * src.stride + x * 4;
            int doff = y * dst.stride + x * 4;
            *(dst.data + doff) = *(src.data + off);
            *(dst.data + doff + 1) = *(src.data + off + 1);
            *(dst.data + doff + 2) = *(src.data + off + 2);
            *(dst.data + doff + 3) = cast<char>(255);
            x = x + 1;
        }
        y = y + 1;
    }
}

fn vision_motion_detect(VisionMotion* m, Image* img, int min_area, VisionResult* res) -> int {
    if (res == null) { return 0; }
    vision_result_reset(res);
    if (m == null || m.prev == null || img == null || img.data == null) { return 0; }
    int w = img.width;
    int h = img.height;
    if (w <= 0 || h <= 0 || w != m.w || h != m.h) { return 0; }
    res.width = w;
    res.height = h;
    int total = w * h;
    _v_ensure_scratch(total);
    char* mask = V_SCRATCH_MASK;

    if (m.initialized == 0) {
        _v_frame_copy(m.prev, img);
        m.initialized = 1;
        return 0;
    }

    char* pdata = m.prev.data;
    int changed = 0;
    int i = 0;
    while (i < total) {
        int y = i / w;
        int x = i - y * w;
        int off = y * img.stride + x * 4;
        int poff = y * m.prev.stride + x * 4;
        int r = v_byte(img.data, off);
        int g = v_byte(img.data, off + 1);
        int b = v_byte(img.data, off + 2);
        int pr = v_byte(pdata, poff);
        int pg = v_byte(pdata, poff + 1);
        int pb = v_byte(pdata, poff + 2);
        int d = v_abs(r - pr) + v_abs(g - pg) + v_abs(b - pb);
        if (d > m.threshold) {
            *(mask + i) = 1;
            changed = changed + 1;
        } else {
            *(mask + i) = 0;
        }
        i = i + 1;
    }

    _v_frame_copy(m.prev, img);
    if (changed == 0 || changed * 3 > total) { return 0; }
    return _v_detect_from_mask(img, mask, min_area, 5, res);
}

// -----------------------------
// Annotation / robot helpers
// -----------------------------

fn vision_draw_object(Image* img, VisionObject obj, int r, int g, int b) -> void {
    if (img == null) { return; }
    if (img.data == null) { return; }
    int x0 = obj.x; int y0 = obj.y;
    int x1 = obj.x + obj.w - 1; int y1 = obj.y + obj.h - 1;
    if (x0 < 0) { x0 = 0; } if (y0 < 0) { y0 = 0; }
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
    int cx = obj.cx; int cy = obj.cy;
    int k = cx - 4;
    while (k <= cx + 4) { image_set_pixel(img, k, cy, r, g, b, 255); k = k + 1; }
    k = cy - 4;
    while (k <= cy + 4) { image_set_pixel(img, cx, k, r, g, b, 255); k = k + 1; }
}

fn vision_draw_objects(Image* img, VisionResult* res, int r, int g, int b) -> void {
    if (res == null) { return; }
    int i = 0;
    while (i < res.count) {
        VisionObject o = vision_get_object(res, i);
        vision_draw_object(img, o, r, g, b);
        i = i + 1;
    }
}

fn vision_object_steer_x(VisionObject obj, int img_w) -> int {
    if (img_w <= 0) { return 0; }
    int center = img_w / 2;
    if (center == 0) { return 0; }
    int dx = obj.cx - center;
    return dx * 100 / center; // -100 (left) .. 100 (right)
}

fn vision_object_steer_y(VisionObject obj, int img_h) -> int {
    if (img_h <= 0) { return 0; }
    int center = img_h / 2;
    if (center == 0) { return 0; }
    int dy = obj.cy - center;
    return dy * 100 / center; // -100 (up) .. 100 (down)
}

fn vision_object_area_ratio(VisionObject obj, int img_w, int img_h) -> int {
    int total = img_w * img_h;
    if (total <= 0) { return 0; }
    return obj.area * 1000 / total; // permille of image (0..1000)
}

fn vision_result_info(VisionResult* res) -> void {
    if (res == null) { print_str("Detections: <null>\n"); return; }
    print_str("Detections: ");
    print(res.count);
    print_str("\n");
    int i = 0;
    while (i < res.count) {
        VisionObject o = vision_get_object(res, i);
        print_str("  [");
        print(o.id);
        print_str("] label=");
        print(o.label);
        print_str(" area=");
        print(o.area);
        print_str(" bbox=(");
        print(o.x); print_str(","); print(o.y); print_str(",");
        print(o.w); print_str("x"); print(o.h);
        print_str(") center=(");
        print(o.cx); print_str(","); print(o.cy);
        print_str(") avg=(");
        print(o.r); print_str(","); print(o.g); print_str(","); print(o.b);
        print_str(")\n");
        i = i + 1;
    }
}
