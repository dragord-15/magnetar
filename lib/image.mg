// ============================================================================
// Magnetar Standard Library: Image Processing (lib/image.mg)
// Pure Magnetar image library (no libc, no external dependencies).
//
// Supported load formats:
//   - PNG  : color types 0/2/3/4/6, bit depths 1/2/4/8/16, Adam7 interlace
//   - BMP  : 1/4/8-bit palette, 16/24/32-bit, BI_RGB + BI_BITFIELDS
//   - PPM  : P6 / P3 (binary + ASCII RGB)
//   - PGM  : P5 / P2 (binary + ASCII grayscale)
//   - TGA  : true-color/grayscale, uncompressed + RLE (types 2,3,10,11)
//
// Supported save formats:
//   - PNG (RGBA, 8-bit, lossless stored-deflate)
//   - BMP (24-bit)
//   - PPM (P6 binary RGB)
//   - PGM (P5 binary grayscale)
//   - TGA (32-bit uncompressed true-color, top-left origin)
//
// Pixels are stored internally as 8-bit RGBA:
//   index = (y * width + x) * 4  ->  R, G, B, A
//
// Basic usage:
//   use "lib/image.mg";
//   Image* img = image_load("photo.png");
//   image_set_pixel(img, 10, 20, 255, 0, 0, 255);
//   image_save(img, "out.bmp");
//   image_destroy(img);
// ============================================================================

// -------------------------------------------------------------
// Linux x86_64 syscall bindings (self-contained)
// -------------------------------------------------------------
extern fn sys_open(string path, int flags, int mode) -> int;
extern fn sys_close(int fd) -> int;
extern fn sys_read(int fd, char* buf, int count) -> int;
extern fn sys_write(int fd, char* data, int count) -> int;
extern fn sys_lseek(int fd, int offset, int whence) -> int;
extern fn print_str(string s) -> void;

const int IMAGE_O_RDONLY = 0;
const int IMAGE_O_WRITE  = 577; // O_WRONLY | O_CREAT | O_TRUNC
const int IMAGE_PERM     = 420; // 0644
const int IMAGE_SEEK_SET = 0;
const int IMAGE_SEEK_CUR = 1;
const int IMAGE_SEEK_END = 2;

const int IMAGE_FMT_UNKNOWN = 0;
const int IMAGE_FMT_PNG     = 1;
const int IMAGE_FMT_BMP     = 2;
const int IMAGE_FMT_PPM     = 3;
const int IMAGE_FMT_PGM     = 4;
const int IMAGE_FMT_TGA     = 5;

// ============================================================================
// 1. Core Image Type and Memory Management
// ============================================================================

struct Image {
    int width;
    int height;
    int channels;   // always 4 internally (RGBA)
    int stride;     // bytes per row (width * 4)
    char* data;     // RGBA bytes
    int owns_data;
};

fn image_new(int width, int height) -> Image* {
    if (width <= 0 || height <= 0) {
        return null;
    }
    Image* img = new Image;
    img.width = width;
    img.height = height;
    img.channels = 4;
    img.stride = width * 4;
    img.owns_data = 1;
    img.data = alloc<char>(img.stride * height);
    if (img.data == null) {
        free(img);
        return null;
    }
    image_fill(img, 0, 0, 0, 255);
    return img;
}

fn image_init(Image* img, int width, int height) -> bool {
    if (img == null || width <= 0 || height <= 0) {
        return false;
    }
    char* buf = alloc<char>(width * height * 4);
    if (buf == null) {
        return false;
    }
    img.width = width;
    img.height = height;
    img.channels = 4;
    img.stride = width * 4;
    img.data = buf;
    img.owns_data = 1;
    image_fill(img, 0, 0, 0, 255);
    return true;
}

fn image_free_data(Image* img) -> void {
    if (img == null) {
        return;
    }
    if (img.owns_data == 1 && img.data != null) {
        free(img.data);
    }
    img.data = null;
    img.width = 0;
    img.height = 0;
    img.stride = 0;
    img.owns_data = 0;
}

fn image_destroy(Image* img) -> void {
    if (img == null) {
        return;
    }
    image_free_data(img);
    free(img);
}

fn image_clone(Image* src) -> Image* {
    if (src == null || src.data == null || src.width <= 0 || src.height <= 0) {
        return null;
    }
    Image* out = image_new(src.width, src.height);
    if (out == null) {
        return null;
    }
    int total = src.width * src.height * 4;
    for (int i = 0; i < total; i = i + 1) {
        *(out.data + i) = cast<char>(_img_bytep(src.data + i));
    }
    return out;
}

fn image_is_valid(Image* img) -> bool {
    if (img == null) {
        return false;
    }
    return img.width > 0 && img.height > 0 && img.data != null;
}

// ============================================================================
// 2. Pixel Access, Blending, and Filling
// ============================================================================

fn _img_clamp255(int v) -> int {
    if (v < 0) { return 0; }
    if (v > 255) { return 255; }
    return v;
}

fn _img_abs(int v) -> int {
    if (v < 0) { return -v; }
    return v;
}

fn image_index(Image* img, int x, int y) -> int {
    return y * img.stride + x * 4;
}

fn image_get_pixel(Image* img, int x, int y) -> int {
    if (!image_is_valid(img) || x < 0 || y < 0 || x >= img.width || y >= img.height) {
        return 0;
    }
    int i = image_index(img, x, y);
    char* p = img.data + i;
    int r = _img_bytep(p + 0);
    int g = _img_bytep(p + 1);
    int b = _img_bytep(p + 2);
    int a = _img_bytep(p + 3);
    return (a << 24) | (r << 16) | (g << 8) | b;
}

fn image_get_r(Image* img, int x, int y) -> int {
    int v = image_get_pixel(img, x, y);
    return (v >> 16) & 255;
}

fn image_get_g(Image* img, int x, int y) -> int {
    int v = image_get_pixel(img, x, y);
    return (v >> 8) & 255;
}

fn image_get_b(Image* img, int x, int y) -> int {
    int v = image_get_pixel(img, x, y);
    return v & 255;
}

fn image_get_a(Image* img, int x, int y) -> int {
    int v = image_get_pixel(img, x, y);
    return (v >> 24) & 255;
}

fn image_set_pixel(Image* img, int x, int y, int r, int g, int b, int a) -> void {
    if (!image_is_valid(img) || x < 0 || y < 0 || x >= img.width || y >= img.height) {
        return;
    }
    int i = image_index(img, x, y);
    char* p = img.data + i;
    *(p + 0) = cast<char>(_img_clamp255(r));
    *(p + 1) = cast<char>(_img_clamp255(g));
    *(p + 2) = cast<char>(_img_clamp255(b));
    *(p + 3) = cast<char>(_img_clamp255(a));
}

fn image_set_rgb(Image* img, int x, int y, int r, int g, int b) -> void {
    image_set_pixel(img, x, y, r, g, b, 255);
}

fn image_copy_pixel(Image* dst, int dx, int dy, Image* src, int sx, int sy) -> void {
    if (!image_is_valid(dst) || !image_is_valid(src)) {
        return;
    }
    if (dx < 0 || dy < 0 || dx >= dst.width || dy >= dst.height) {
        return;
    }
    int v = image_get_pixel(src, sx, sy);
    image_set_pixel(dst, dx, dy,
        (v >> 16) & 255,
        (v >> 8) & 255,
        v & 255,
        (v >> 24) & 255);
}

fn image_blend_pixel(Image* img, int x, int y, int r, int g, int b, int a) -> void {
    if (!image_is_valid(img) || x < 0 || y < 0 || x >= img.width || y >= img.height) {
        return;
    }
    a = _img_clamp255(a);
    if (a == 0) {
        return;
    }
    if (a == 255) {
        image_set_pixel(img, x, y, r, g, b, 255);
        return;
    }
    int v = image_get_pixel(img, x, y);
    int dr = (v >> 16) & 255;
    int dg = (v >> 8) & 255;
    int db = v & 255;
    int da = (v >> 24) & 255;
    int outa = a + (da * (255 - a)) / 255;
    if (outa <= 0) {
        image_set_pixel(img, x, y, 0, 0, 0, 0);
        return;
    }
    int outr = (r * a + dr * da * (255 - a) / 255) / outa;
    int outg = (g * a + dg * da * (255 - a) / 255) / outa;
    int outb = (b * a + db * da * (255 - a) / 255) / outa;
    image_set_pixel(img, x, y, outr, outg, outb, outa);
}

fn image_fill(Image* img, int r, int g, int b, int a) -> void {
    if (!image_is_valid(img)) {
        return;
    }
    for (int y = 0; y < img.height; y = y + 1) {
        for (int x = 0; x < img.width; x = x + 1) {
            image_set_pixel(img, x, y, r, g, b, a);
        }
    }
}

fn image_clear(Image* img) -> void {
    image_fill(img, 0, 0, 0, 255);
}

fn image_replace_color(Image* img, int oldr, int oldg, int oldb, int newr, int newg, int newb, int tolerance) -> int {
    int count = 0;
    if (!image_is_valid(img)) {
        return 0;
    }
    for (int y = 0; y < img.height; y = y + 1) {
        for (int x = 0; x < img.width; x = x + 1) {
            int v = image_get_pixel(img, x, y);
            int r = (v >> 16) & 255;
            int g = (v >> 8) & 255;
            int b = v & 255;
            if (_img_abs(r - oldr) <= tolerance && _img_abs(g - oldg) <= tolerance && _img_abs(b - oldb) <= tolerance) {
                image_set_pixel(img, x, y, newr, newg, newb, (v >> 24) & 255);
                count = count + 1;
            }
        }
    }
    return count;
}

// ============================================================================
// 3. Blitting, Cropping, Resizing, Rotation, and Flips
// ============================================================================

fn image_blit(Image* dst, Image* src, int dx, int dy) -> void {
    if (!image_is_valid(dst) || !image_is_valid(src)) {
        return;
    }
    for (int y = 0; y < src.height; y = y + 1) {
        for (int x = 0; x < src.width; x = x + 1) {
            int v = image_get_pixel(src, x, y);
            int a = (v >> 24) & 255;
            if (a == 255) {
                image_copy_pixel(dst, dx + x, dy + y, src, x, y);
            } else if (a > 0) {
                image_blend_pixel(dst, dx + x, dy + y, (v >> 16) & 255, (v >> 8) & 255, v & 255, a);
            }
        }
    }
}

fn image_crop(Image* src, int x, int y, int w, int h) -> Image* {
    if (!image_is_valid(src) || w <= 0 || h <= 0) {
        return null;
    }
    Image* out = image_new(w, h);
    if (out == null) {
        return null;
    }
    for (int j = 0; j < h; j = j + 1) {
        for (int i = 0; i < w; i = i + 1) {
            image_copy_pixel(out, i, j, src, x + i, y + j);
        }
    }
    return out;
}

fn image_resize_nearest(Image* src, int nw, int nh) -> Image* {
    if (!image_is_valid(src) || nw <= 0 || nh <= 0) {
        return null;
    }
    Image* out = image_new(nw, nh);
    if (out == null) {
        return null;
    }
    for (int y = 0; y < nh; y = y + 1) {
        int sy = (y * src.height) / nh;
        if (sy >= src.height) { sy = src.height - 1; }
        for (int x = 0; x < nw; x = x + 1) {
            int sx = (x * src.width) / nw;
            if (sx >= src.width) { sx = src.width - 1; }
            image_copy_pixel(out, x, y, src, sx, sy);
        }
    }
    return out;
}

fn image_resize_bilinear(Image* src, int nw, int nh) -> Image* {
    if (!image_is_valid(src) || nw <= 0 || nh <= 0) {
        return null;
    }
    Image* out = image_new(nw, nh);
    if (out == null) {
        return null;
    }
    for (int y = 0; y < nh; y = y + 1) {
        int fy;
        if (nh > 1) {
            fy = (y * (src.height - 1) * 256) / (nh - 1);
        } else {
            fy = 0;
        }
        int y0 = fy / 256;
        int wy = fy % 256;
        int y1 = y0 + 1;
        if (y1 >= src.height) { y1 = src.height - 1; }
        for (int x = 0; x < nw; x = x + 1) {
            int fx;
            if (nw > 1) {
                fx = (x * (src.width - 1) * 256) / (nw - 1);
            } else {
                fx = 0;
            }
            int x0 = fx / 256;
            int wx = fx % 256;
            int x1 = x0 + 1;
            if (x1 >= src.width) { x1 = src.width - 1; }

            int v00 = image_get_pixel(src, x0, y0);
            int v10 = image_get_pixel(src, x1, y0);
            int v01 = image_get_pixel(src, x0, y1);
            int v11 = image_get_pixel(src, x1, y1);

            int r0 = ((v00 >> 16) & 255) * (256 - wx) + ((v10 >> 16) & 255) * wx;
            int g0 = ((v00 >> 8) & 255) * (256 - wx) + ((v10 >> 8) & 255) * wx;
            int b0 = (v00 & 255) * (256 - wx) + (v10 & 255) * wx;
            int a0 = ((v00 >> 24) & 255) * (256 - wx) + ((v10 >> 24) & 255) * wx;

            int r1 = ((v01 >> 16) & 255) * (256 - wx) + ((v11 >> 16) & 255) * wx;
            int g1 = ((v01 >> 8) & 255) * (256 - wx) + ((v11 >> 8) & 255) * wx;
            int b1 = (v01 & 255) * (256 - wx) + (v11 & 255) * wx;
            int a1 = ((v01 >> 24) & 255) * (256 - wx) + ((v11 >> 24) & 255) * wx;

            int r = (r0 * (256 - wy) + r1 * wy) / 65536;
            int g = (g0 * (256 - wy) + g1 * wy) / 65536;
            int b = (b0 * (256 - wy) + b1 * wy) / 65536;
            int a = (a0 * (256 - wy) + a1 * wy) / 65536;
            image_set_pixel(out, x, y, r, g, b, a);
        }
    }
    return out;
}

fn image_flip_horizontal(Image* src) -> Image* {
    if (!image_is_valid(src)) {
        return null;
    }
    Image* out = image_new(src.width, src.height);
    if (out == null) {
        return null;
    }
    for (int y = 0; y < src.height; y = y + 1) {
        for (int x = 0; x < src.width; x = x + 1) {
            image_copy_pixel(out, x, y, src, src.width - 1 - x, y);
        }
    }
    return out;
}

fn image_flip_vertical(Image* src) -> Image* {
    if (!image_is_valid(src)) {
        return null;
    }
    Image* out = image_new(src.width, src.height);
    if (out == null) {
        return null;
    }
    for (int y = 0; y < src.height; y = y + 1) {
        for (int x = 0; x < src.width; x = x + 1) {
            image_copy_pixel(out, x, y, src, x, src.height - 1 - y);
        }
    }
    return out;
}

fn image_rotate90(Image* src) -> Image* {
    if (!image_is_valid(src)) {
        return null;
    }
    Image* out = image_new(src.height, src.width);
    if (out == null) {
        return null;
    }
    for (int y = 0; y < out.height; y = y + 1) {
        for (int x = 0; x < out.width; x = x + 1) {
            image_copy_pixel(out, x, y, src, y, src.height - 1 - x);
        }
    }
    return out;
}

fn image_rotate180(Image* src) -> Image* {
    if (!image_is_valid(src)) {
        return null;
    }
    Image* out = image_new(src.width, src.height);
    if (out == null) {
        return null;
    }
    for (int y = 0; y < src.height; y = y + 1) {
        for (int x = 0; x < src.width; x = x + 1) {
            image_copy_pixel(out, x, y, src, src.width - 1 - x, src.height - 1 - y);
        }
    }
    return out;
}

fn image_rotate270(Image* src) -> Image* {
    if (!image_is_valid(src)) {
        return null;
    }
    Image* out = image_new(src.height, src.width);
    if (out == null) {
        return null;
    }
    for (int y = 0; y < out.height; y = y + 1) {
        for (int x = 0; x < out.width; x = x + 1) {
            image_copy_pixel(out, x, y, src, src.width - 1 - y, x);
        }
    }
    return out;
}

// ============================================================================
// 4. Color Adjustments and Filters
// ============================================================================

fn image_grayscale(Image* img) -> void {
    if (!image_is_valid(img)) {
        return;
    }
    for (int y = 0; y < img.height; y = y + 1) {
        for (int x = 0; x < img.width; x = x + 1) {
            int v = image_get_pixel(img, x, y);
            int r = (v >> 16) & 255;
            int g = (v >> 8) & 255;
            int b = v & 255;
            int gray = (r * 299 + g * 587 + b * 114) / 1000;
            image_set_pixel(img, x, y, gray, gray, gray, (v >> 24) & 255);
        }
    }
}

fn image_invert(Image* img) -> void {
    if (!image_is_valid(img)) {
        return;
    }
    for (int y = 0; y < img.height; y = y + 1) {
        for (int x = 0; x < img.width; x = x + 1) {
            int v = image_get_pixel(img, x, y);
            image_set_pixel(img, x, y,
                255 - ((v >> 16) & 255),
                255 - ((v >> 8) & 255),
                255 - (v & 255),
                (v >> 24) & 255);
        }
    }
}

fn image_brightness(Image* img, int amount) -> void {
    if (!image_is_valid(img)) {
        return;
    }
    for (int y = 0; y < img.height; y = y + 1) {
        for (int x = 0; x < img.width; x = x + 1) {
            int v = image_get_pixel(img, x, y);
            image_set_pixel(img, x, y,
                _img_clamp255(((v >> 16) & 255) + amount),
                _img_clamp255(((v >> 8) & 255) + amount),
                _img_clamp255((v & 255) + amount),
                (v >> 24) & 255);
        }
    }
}

fn image_contrast(Image* img, int percent) -> void {
    if (!image_is_valid(img)) {
        return;
    }
    for (int y = 0; y < img.height; y = y + 1) {
        for (int x = 0; x < img.width; x = x + 1) {
            int v = image_get_pixel(img, x, y);
            int r = ((v >> 16) & 255);
            int g = ((v >> 8) & 255);
            int b = (v & 255);
            r = _img_clamp255(((r - 128) * percent) / 100 + 128);
            g = _img_clamp255(((g - 128) * percent) / 100 + 128);
            b = _img_clamp255(((b - 128) * percent) / 100 + 128);
            image_set_pixel(img, x, y, r, g, b, (v >> 24) & 255);
        }
    }
}

fn image_threshold(Image* img, int level) -> void {
    if (!image_is_valid(img)) {
        return;
    }
    for (int y = 0; y < img.height; y = y + 1) {
        for (int x = 0; x < img.width; x = x + 1) {
            int v = image_get_pixel(img, x, y);
            int gray = (((v >> 16) & 255) * 299 + ((v >> 8) & 255) * 587 + (v & 255) * 114) / 1000;
            int c = 0;
            if (gray >= level) { c = 255; }
            image_set_pixel(img, x, y, c, c, c, (v >> 24) & 255);
        }
    }
}

fn image_sepia(Image* img) -> void {
    if (!image_is_valid(img)) {
        return;
    }
    for (int y = 0; y < img.height; y = y + 1) {
        for (int x = 0; x < img.width; x = x + 1) {
            int v = image_get_pixel(img, x, y);
            int r = (v >> 16) & 255;
            int g = (v >> 8) & 255;
            int b = v & 255;
            int nr = (r * 393 + g * 769 + b * 189) / 1000;
            int ng = (r * 349 + g * 686 + b * 168) / 1000;
            int nb = (r * 272 + g * 534 + b * 131) / 1000;
            image_set_pixel(img, x, y, nr, ng, nb, (v >> 24) & 255);
        }
    }
}

fn image_box_blur(Image* img, int radius) -> void {
    if (!image_is_valid(img) || radius <= 0) {
        return;
    }
    Image* src = image_clone(img);
    if (src == null) {
        return;
    }
    int diameter = radius * 2 + 1;
    int area = diameter * diameter;
    for (int y = 0; y < img.height; y = y + 1) {
        for (int x = 0; x < img.width; x = x + 1) {
            int sr = 0;
            int sg = 0;
            int sb = 0;
            int sa = 0;
            int count = 0;
            for (int ky = -radius; ky <= radius; ky = ky + 1) {
                int sy = y + ky;
                if (sy < 0 || sy >= src.height) { continue; }
                for (int kx = -radius; kx <= radius; kx = kx + 1) {
                    int sx = x + kx;
                    if (sx < 0 || sx >= src.width) { continue; }
                    int v = image_get_pixel(src, sx, sy);
                    sr = sr + ((v >> 16) & 255);
                    sg = sg + ((v >> 8) & 255);
                    sb = sb + (v & 255);
                    sa = sa + ((v >> 24) & 255);
                    count = count + 1;
                }
            }
            if (count > 0) {
                image_set_pixel(img, x, y, sr / count, sg / count, sb / count, sa / count);
            }
        }
    }
    image_destroy(src);
}

// ============================================================================
// 5. Drawing Primitives
// ============================================================================

fn image_draw_line(Image* img, int x0, int y0, int x1, int y1, int r, int g, int b, int a) -> void {
    int dx = _img_abs(x1 - x0);
    int dy = -_img_abs(y1 - y0);
    int sx = 1;
    if (x0 > x1) { sx = -1; }
    int sy = 1;
    if (y0 > y1) { sy = -1; }
    int err = dx + dy;
    while (true) {
        image_blend_pixel(img, x0, y0, r, g, b, a);
        if (x0 == x1 && y0 == y1) { break; }
        int e2 = err * 2;
        if (e2 >= dy) {
            err = err + dy;
            x0 = x0 + sx;
        }
        if (e2 <= dx) {
            err = err + dx;
            y0 = y0 + sy;
        }
    }
}

fn image_fill_rect(Image* img, int x, int y, int w, int h, int r, int g, int b, int a) -> void {
    for (int j = y; j < y + h; j = j + 1) {
        for (int i = x; i < x + w; i = i + 1) {
            image_blend_pixel(img, i, j, r, g, b, a);
        }
    }
}

fn image_draw_rect(Image* img, int x, int y, int w, int h, int r, int g, int b, int a) -> void {
    if (w <= 0 || h <= 0) { return; }
    image_draw_line(img, x, y, x + w - 1, y, r, g, b, a);
    image_draw_line(img, x, y + h - 1, x + w - 1, y + h - 1, r, g, b, a);
    image_draw_line(img, x, y, x, y + h - 1, r, g, b, a);
    image_draw_line(img, x + w - 1, y, x + w - 1, y + h - 1, r, g, b, a);
}

fn image_fill_circle(Image* img, int cx, int cy, int radius, int r, int g, int b, int a) -> void {
    if (radius < 0) { return; }
    int rr = radius * radius;
    for (int y = -radius; y <= radius; y = y + 1) {
        for (int x = -radius; x <= radius; x = x + 1) {
            if (x * x + y * y <= rr) {
                image_blend_pixel(img, cx + x, cy + y, r, g, b, a);
            }
        }
    }
}

fn image_draw_circle(Image* img, int cx, int cy, int radius, int r, int g, int b, int a) -> void {
    if (radius < 0) { return; }
    int x = radius;
    int y = 0;
    int err = 1 - radius;
    while (x >= y) {
        image_blend_pixel(img, cx + x, cy + y, r, g, b, a);
        image_blend_pixel(img, cx + y, cy + x, r, g, b, a);
        image_blend_pixel(img, cx - y, cy + x, r, g, b, a);
        image_blend_pixel(img, cx - x, cy + y, r, g, b, a);
        image_blend_pixel(img, cx - x, cy - y, r, g, b, a);
        image_blend_pixel(img, cx - y, cy - x, r, g, b, a);
        image_blend_pixel(img, cx + y, cy - x, r, g, b, a);
        image_blend_pixel(img, cx + x, cy - y, r, g, b, a);
        y = y + 1;
        if (err < 0) {
            err = err + 2 * y + 1;
        } else {
            x = x - 1;
            err = err + 2 * (y - x) + 1;
        }
    }
}

// ============================================================================
// 6. Low-Level Binary and File Helpers
// ============================================================================

fn _img_bytep(char* p) -> int {
    return cast<int>(*p) & 255;
}

fn _img_rd_u16le(char* p, int o) -> int {
    return _img_bytep(p + o) | (_img_bytep(p + o + 1) << 8);
}

fn _img_rd_u32le(char* p, int o) -> int {
    return _img_bytep(p + o)
         | (_img_bytep(p + o + 1) << 8)
         | (_img_bytep(p + o + 2) << 16)
         | (_img_bytep(p + o + 3) << 24);
}

fn _img_rd_i32le(char* p, int o) -> int {
    int v = _img_rd_u32le(p, o);
    if ((v & 0x80000000) != 0) {
        return v - 4294967296;
    }
    return v;
}

fn _img_rd_u16be(char* p, int o) -> int {
    return (_img_bytep(p + o) << 8) | _img_bytep(p + o + 1);
}

fn _img_rd_u32be(char* p, int o) -> int {
    return (_img_bytep(p + o) << 24)
         | (_img_bytep(p + o + 1) << 16)
         | (_img_bytep(p + o + 2) << 8)
         | _img_bytep(p + o + 3);
}

fn _img_wr_u16le(char* p, int o, int v) -> void {
    *(p + o) = cast<char>(v & 255);
    *(p + (o + 1)) = cast<char>((v >> 8) & 255);
}

fn _img_wr_u32le(char* p, int o, int v) -> void {
    *(p + o) = cast<char>(v & 255);
    *(p + (o + 1)) = cast<char>((v >> 8) & 255);
    *(p + (o + 2)) = cast<char>((v >> 16) & 255);
    *(p + (o + 3)) = cast<char>((v >> 24) & 255);
}

fn _img_wr_u32be(char* p, int o, int v) -> void {
    *(p + o) = cast<char>((v >> 24) & 255);
    *(p + (o + 1)) = cast<char>((v >> 16) & 255);
    *(p + (o + 2)) = cast<char>((v >> 8) & 255);
    *(p + (o + 3)) = cast<char>(v & 255);
}

fn _img_zero(char* p, int n) -> void {
    for (int i = 0; i < n; i = i + 1) {
        *(p + i) = cast<char>(0);
    }
}

fn _img_copy(char* dst, int doff, char* src, int soff, int n) -> void {
    for (int i = 0; i < n; i = i + 1) {
        *(dst + (doff + i)) = cast<char>(_img_bytep(src + soff + i));
    }
}

fn _img_read_file(string path, int* out_size) -> char* {
    *out_size = 0;
    int fd = sys_open(path, IMAGE_O_RDONLY, 0);
    if (fd < 0) {
        return null;
    }
    int size = sys_lseek(fd, 0, IMAGE_SEEK_END);
    if (size <= 0) {
        sys_close(fd);
        return null;
    }
    sys_lseek(fd, 0, IMAGE_SEEK_SET);
    char* buf = alloc<char>(size + 1);
    if (buf == null) {
        sys_close(fd);
        return null;
    }
    int total = 0;
    while (total < size) {
        int n = sys_read(fd, buf + total, size - total);
        if (n <= 0) {
            break;
        }
        total = total + n;
    }
    sys_close(fd);
    if (total <= 0) {
        free(buf);
        return null;
    }
    *(buf + total) = cast<char>(0);
    *out_size = total;
    return buf;
}

fn _img_write_file(string path, char* data, int size) -> bool {
    int fd = sys_open(path, IMAGE_O_WRITE, IMAGE_PERM);
    if (fd < 0) {
        return false;
    }
    int total = 0;
    while (total < size) {
        int n = sys_write(fd, data + total, size - total);
        if (n <= 0) {
            sys_close(fd);
            return false;
        }
        total = total + n;
    }
    sys_close(fd);
    return true;
}

fn _img_str_len(string s) -> int {
    char* p = cast<char*>(s);
    if (p == null) { return 0; }
    int n = 0;
    while (_img_bytep(p + n) != 0) {
        n = n + 1;
    }
    return n;
}

fn _img_char_lower(char c) -> char {
    if (c >= 'A' && c <= 'Z') {
        return cast<char>(cast<int>(c) + 32);
    }
    return c;
}

fn _img_has_ext(string path, string ext) -> bool {
    int lp = _img_str_len(path);
    int le = _img_str_len(ext);
    if (le <= 0 || le > lp) {
        return false;
    }
    if (lp - le - 1 >= 0) {
        if (_img_bytep(cast<char*>(path) + lp - le - 1) != 46) {
            return false;
        }
    } else {
        return false;
    }
    for (int i = 0; i < le; i = i + 1) {
        char a = _img_char_lower(*(cast<char*>(path) + (lp - le + i)));
        char b = _img_char_lower(*(cast<char*>(ext) + i));
        if (a != b) {
            return false;
        }
    }
    return true;
}

fn _img_detect_format(char* d, int size, string path) -> int {
    if (size >= 8 && _img_bytep(d + 0) == 137 && _img_bytep(d + 1) == 80 && _img_bytep(d + 2) == 78 && _img_bytep(d + 3) == 71) {
        return IMAGE_FMT_PNG;
    }
    if (size >= 2 && _img_bytep(d + 0) == 'B' && _img_bytep(d + 1) == 'M') {
        return IMAGE_FMT_BMP;
    }
    if (size >= 2 && _img_bytep(d + 0) == 'P') {
        char c = *(d + 1);
        if (c == '6' || c == '3') { return IMAGE_FMT_PPM; }
        if (c == '5' || c == '2') { return IMAGE_FMT_PGM; }
    }
    if (_img_has_ext(path, "png")) { return IMAGE_FMT_PNG; }
    if (_img_has_ext(path, "bmp")) { return IMAGE_FMT_BMP; }
    if (_img_has_ext(path, "ppm") || _img_has_ext(path, "pnm")) { return IMAGE_FMT_PPM; }
    if (_img_has_ext(path, "pgm")) { return IMAGE_FMT_PGM; }
    if (_img_has_ext(path, "tga")) { return IMAGE_FMT_TGA; }
    return IMAGE_FMT_TGA;
}

// ============================================================================
// 7. BMP Decoder and Encoder
// ============================================================================

fn _img_mask_shift(int mask) -> int {
    if (mask == 0) { return 0; }
    int s = 0;
    while ((mask & 1) == 0) {
        mask = mask >> 1;
        s = s + 1;
    }
    return s;
}

fn _img_mask_bits(int mask) -> int {
    int s = _img_mask_shift(mask);
    mask = mask >> s;
    int n = 0;
    while ((mask & 1) != 0) {
        n = n + 1;
        mask = mask >> 1;
    }
    return n;
}

fn _img_extract_mask(int v, int mask) -> int {
    if (mask == 0) { return 0; }
    int s = _img_mask_shift(mask);
    int bits = _img_mask_bits(mask);
    int maxv = (1 << bits) - 1;
    int rawbuf = (v >> s) & maxv;
    return (rawbuf * 255) / maxv;
}

fn _img_decode_bmp(Image* out, char* d, int size) -> bool {
    if (size < 26 || _img_bytep(d + 0) != 'B' || _img_bytep(d + 1) != 'M') {
        return false;
    }
    int pixel_off = _img_rd_u32le(d, 10);
    int dib = _img_rd_u32le(d, 14);
    int w = 0;
    int h = 0;
    int bpp = 0;
    int compression = 0;
    int palette_off = 0;
    int palette_entry = 4;
    if (dib == 12) {
        w = _img_rd_u16le(d, 18);
        h = _img_rd_u16le(d, 20);
        bpp = _img_rd_u16le(d, 24);
        palette_off = 26;
        palette_entry = 3;
    } else {
        if (dib < 40) { return false; }
        w = _img_rd_i32le(d, 18);
        h = _img_rd_i32le(d, 22);
        bpp = _img_rd_u16le(d, 28);
        compression = _img_rd_u32le(d, 30);
        palette_off = 14 + dib;
    }
    bool top_down = false;
    if (h < 0) {
        h = -h;
        top_down = true;
    }
    if (w <= 0 || h <= 0) { return false; }
    if (bpp != 1 && bpp != 4 && bpp != 8 && bpp != 16 && bpp != 24 && bpp != 32) { return false; }
    if (compression != 0 && compression != 3) { return false; }

    int rmask = 0;
    int gmask = 0;
    int bmask = 0;
    int amask = 0;
    int mask_off = 14 + dib;
    if (compression == 3 && dib >= 40 && size >= mask_off + 12) {
        rmask = _img_rd_u32le(d, mask_off);
        gmask = _img_rd_u32le(d, mask_off + 4);
        bmask = _img_rd_u32le(d, mask_off + 8);
        if (size >= mask_off + 16) {
            amask = _img_rd_u32le(d, mask_off + 12);
        }
        palette_off = mask_off + 12;
        if (amask != 0) { palette_off = mask_off + 16; }
    }

    int stride = ((w * bpp + 31) / 32) * 4;
    if (pixel_off < 0 || pixel_off + stride * h > size) {
        return false;
    }
    char* pixels = alloc<char>(w * h * 4);
    if (pixels == null) { return false; }

    for (int y = 0; y < h; y = y + 1) {
        int sy = y;
        if (!top_down) { sy = h - 1 - y; }
        char* row = d + pixel_off + sy * stride;
        for (int x = 0; x < w; x = x + 1) {
            int r = 0;
            int g = 0;
            int b = 0;
            int a = 255;
            if (bpp == 24) {
                b = _img_bytep(row + x * 3 + 0);
                g = _img_bytep(row + x * 3 + 1);
                r = _img_bytep(row + x * 3 + 2);
            } else if (bpp == 32) {
                int v = _img_bytep(row + x * 4 + 0)
                      | (_img_bytep(row + x * 4 + 1) << 8)
                      | (_img_bytep(row + x * 4 + 2) << 16)
                      | (_img_bytep(row + x * 4 + 3) << 24);
                if (compression == 3) {
                    r = _img_extract_mask(v, rmask);
                    g = _img_extract_mask(v, gmask);
                    b = _img_extract_mask(v, bmask);
                    if (amask != 0) { a = _img_extract_mask(v, amask); }
                } else {
                    b = _img_bytep(row + x * 4 + 0);
                    g = _img_bytep(row + x * 4 + 1);
                    r = _img_bytep(row + x * 4 + 2);
                }
            } else if (bpp == 16) {
                int v = _img_rd_u16le(row, x * 2);
                if (compression == 3) {
                    r = _img_extract_mask(v, rmask);
                    g = _img_extract_mask(v, gmask);
                    b = _img_extract_mask(v, bmask);
                } else {
                    r = ((v >> 10) & 31) * 255 / 31;
                    g = ((v >> 5) & 31) * 255 / 31;
                    b = (v & 31) * 255 / 31;
                }
            } else {
                int idx = 0;
                if (bpp == 8) {
                    idx = _img_bytep(row + x);
                } else if (bpp == 4) {
                    int bval = _img_bytep(row + x / 2);
                    if ((x & 1) == 0) { idx = (bval >> 4) & 15; } else { idx = bval & 15; }
                } else {
                    int bval = _img_bytep(row + x / 8);
                    int shift = 7 - (x & 7);
                    idx = (bval >> shift) & 1;
                }
                int po = palette_off + idx * palette_entry;
                if (po + 2 < size) {
                    b = _img_bytep(d + po + 0);
                    g = _img_bytep(d + po + 1);
                    r = _img_bytep(d + po + 2);
                }
            }
            int oi = (y * w + x) * 4;
            *(pixels + (oi + 0)) = cast<char>(r);
            *(pixels + (oi + 1)) = cast<char>(g);
            *(pixels + (oi + 2)) = cast<char>(b);
            *(pixels + (oi + 3)) = cast<char>(a);
        }
    }

    out.width = w;
    out.height = h;
    out.channels = 4;
    out.stride = w * 4;
    out.data = pixels;
    out.owns_data = 1;
    return true;
}

fn _img_save_bmp(Image* img, string path) -> bool {
    if (!image_is_valid(img)) { return false; }
    int row = img.width * 3;
    int stride = ((row + 3) / 4) * 4;
    int data_size = stride * img.height;
    int total = 54 + data_size;
    char* buf = alloc<char>(total);
    if (buf == null) { return false; }
    _img_zero(buf, total);

    *(buf + 0) = cast<char>('B');
    *(buf + 1) = cast<char>('M');
    _img_wr_u32le(buf, 2, total);
    _img_wr_u32le(buf, 10, 54);
    _img_wr_u32le(buf, 14, 40);
    _img_wr_u32le(buf, 18, img.width);
    _img_wr_u32le(buf, 22, img.height);
    _img_wr_u16le(buf, 26, 1);
    _img_wr_u16le(buf, 28, 24);
    _img_wr_u32le(buf, 30, 0);
    _img_wr_u32le(buf, 34, data_size);
    _img_wr_u32le(buf, 38, 2835);
    _img_wr_u32le(buf, 42, 2835);

    for (int y = 0; y < img.height; y = y + 1) {
        int sy = img.height - 1 - y;
        int off = 54 + y * stride;
        for (int x = 0; x < img.width; x = x + 1) {
            int v = image_get_pixel(img, x, sy);
            *(buf + (off + x * 3 + 0)) = cast<char>(v & 255);
            *(buf + (off + x * 3 + 1)) = cast<char>((v >> 8) & 255);
            *(buf + (off + x * 3 + 2)) = cast<char>((v >> 16) & 255);
        }
    }
    bool ok = _img_write_file(path, buf, total);
    free(buf);
    return ok;
}

// ============================================================================
// 8. PPM / PGM Decoder and Encoder
// ============================================================================

fn _img_ppm_skip(char* d, int size, int* pos) -> void {
    while (*pos < size) {
        int c = _img_bytep(d + *pos);
        if (c == 35) { // '#'
            while (*pos < size && _img_bytep(d + *pos) != 10) {
                *pos = *pos + 1;
            }
        } else if (c == 32 || c == 9 || c == 10 || c == 13 || c == 11 || c == 12) {
            *pos = *pos + 1;
        } else {
            break;
        }
    }
}

fn _img_ppm_int(char* d, int size, int* pos) -> int {
    _img_ppm_skip(d, size, pos);
    if (*pos >= size) { return -1; }
    int v = 0;
    int digits = 0;
    while (*pos < size) {
        int c = _img_bytep(d + *pos);
        if (c < 48 || c > 57) { break; }
        v = v * 10 + (c - 48);
        digits = digits + 1;
        *pos = *pos + 1;
    }
    if (digits == 0) { return -1; }
    return v;
}

fn _img_decode_ppm(Image* out, char* d, int size, int force_gray) -> bool {
    if (size < 2 || _img_bytep(d + 0) != 'P') { return false; }
    char kind = *(d + 1);
    if (kind != '6' && kind != '3' && kind != '5' && kind != '2') { return false; }
    bool ascii = (kind == '3' || kind == '2');
    bool gray = force_gray == 1 || kind == '5' || kind == '2';
    int pos = 2;
    int w = _img_ppm_int(d, size, &pos);
    int h = _img_ppm_int(d, size, &pos);
    int maxval = _img_ppm_int(d, size, &pos);
    if (w <= 0 || h <= 0 || maxval <= 0) { return false; }
    if (maxval > 65535) { return false; }
    int channels = 3;
    if (gray) { channels = 1; }

    char* pixels = alloc<char>(w * h * 4);
    if (pixels == null) { return false; }

    if (!ascii) {
        if (pos < size && _img_bytep(d + pos) == 13) { pos = pos + 1; }
        if (pos < size && _img_bytep(d + pos) == 10) { pos = pos + 1; }
        int bytes_per = 1;
        if (maxval > 255) { bytes_per = 2; }
        for (int y = 0; y < h; y = y + 1) {
            for (int x = 0; x < w; x = x + 1) {
                int r = 0;
                int g = 0;
                int b = 0;
                if (gray) {
                    int s = 0;
                    if (bytes_per == 1) {
                        if (pos >= size) { free(pixels); return false; }
                        s = _img_bytep(d + pos);
                        pos = pos + 1;
                    } else {
                        if (pos + 1 >= size) { free(pixels); return false; }
                        s = _img_rd_u16be(d, pos);
                        pos = pos + 2;
                    }
                    s = (s * 255) / maxval;
                    r = s; g = s; b = s;
                } else {
                    int rr = 0;
                    int gg = 0;
                    int bb = 0;
                    if (bytes_per == 1) {
                        if (pos + 2 >= size) { free(pixels); return false; }
                        rr = _img_bytep(d + pos);
                        gg = _img_bytep(d + pos + 1);
                        bb = _img_bytep(d + pos + 2);
                        pos = pos + 3;
                    } else {
                        if (pos + 5 >= size) { free(pixels); return false; }
                        rr = _img_rd_u16be(d, pos);
                        gg = _img_rd_u16be(d, pos + 2);
                        bb = _img_rd_u16be(d, pos + 4);
                        pos = pos + 6;
                    }
                    r = (rr * 255) / maxval;
                    g = (gg * 255) / maxval;
                    b = (bb * 255) / maxval;
                }
                int oi = (y * w + x) * 4;
                *(pixels + (oi + 0)) = cast<char>(r);
                *(pixels + (oi + 1)) = cast<char>(g);
                *(pixels + (oi + 2)) = cast<char>(b);
                *(pixels + (oi + 3)) = cast<char>(255);
            }
        }
    } else {
        for (int y = 0; y < h; y = y + 1) {
            for (int x = 0; x < w; x = x + 1) {
                int r = 0;
                int g = 0;
                int b = 0;
                if (gray) {
                    int s = _img_ppm_int(d, size, &pos);
                    if (s < 0) { free(pixels); return false; }
                    s = (s * 255) / maxval;
                    r = s; g = s; b = s;
                } else {
                    int rr = _img_ppm_int(d, size, &pos);
                    int gg = _img_ppm_int(d, size, &pos);
                    int bb = _img_ppm_int(d, size, &pos);
                    if (rr < 0 || gg < 0 || bb < 0) { free(pixels); return false; }
                    r = (rr * 255) / maxval;
                    g = (gg * 255) / maxval;
                    b = (bb * 255) / maxval;
                }
                int oi = (y * w + x) * 4;
                *(pixels + (oi + 0)) = cast<char>(r);
                *(pixels + (oi + 1)) = cast<char>(g);
                *(pixels + (oi + 2)) = cast<char>(b);
                *(pixels + (oi + 3)) = cast<char>(255);
            }
        }
    }

    out.width = w;
    out.height = h;
    out.channels = 4;
    out.stride = w * 4;
    out.data = pixels;
    out.owns_data = 1;
    return true;
}

fn _img_uint_len(int v) -> int {
    if (v == 0) { return 1; }
    int n = 0;
    while (v > 0) {
        n = n + 1;
        v = v / 10;
    }
    return n;
}

fn _img_write_uint(int fd, int v) -> void {
    if (v == 0) {
        sys_write(fd, "0", 1);
        return;
    }
    int n = _img_uint_len(v);
    char* buf = alloc<char>(n);
    int i = n - 1;
    while (v > 0) {
        *(buf + i) = cast<char>(48 + (v % 10));
        v = v / 10;
        i = i - 1;
    }
    sys_write(fd, buf, n);
    free(buf);
}

fn _img_save_ppm(Image* img, string path, int gray) -> bool {
    if (!image_is_valid(img)) { return false; }
    int fd = sys_open(path, IMAGE_O_WRITE, IMAGE_PERM);
    if (fd < 0) { return false; }
    if (gray == 1) {
        sys_write(fd, "P5\n", 3);
    } else {
        sys_write(fd, "P6\n", 3);
    }
    _img_write_uint(fd, img.width);
    sys_write(fd, " ", 1);
    _img_write_uint(fd, img.height);
    sys_write(fd, "\n255\n", 5);

    int channels = 3;
    if (gray == 1) { channels = 1; }
    char* row = alloc<char>(img.width * channels);
    if (row == null) {
        sys_close(fd);
        return false;
    }
    for (int y = 0; y < img.height; y = y + 1) {
        for (int x = 0; x < img.width; x = x + 1) {
            int v = image_get_pixel(img, x, y);
            int r = (v >> 16) & 255;
            int g = (v >> 8) & 255;
            int b = v & 255;
            if (gray == 1) {
                *(row + x) = cast<char>((r * 299 + g * 587 + b * 114) / 1000);
            } else {
                *(row + (x * 3 + 0)) = cast<char>(r);
                *(row + (x * 3 + 1)) = cast<char>(g);
                *(row + (x * 3 + 2)) = cast<char>(b);
            }
        }
        int n = sys_write(fd, row, img.width * channels);
        if (n <= 0) {
            free(row);
            sys_close(fd);
            return false;
        }
    }
    free(row);
    sys_close(fd);
    return true;
}

// ============================================================================
// 9. TGA Decoder and Encoder
// ============================================================================

fn _img_decode_tga(Image* out, char* d, int size) -> bool {
    if (size < 18) { return false; }
    int id_len = _img_bytep(d + 0);
    int cmap_type = _img_bytep(d + 1);
    int type = _img_bytep(d + 2);
    int cmap_first = _img_rd_u16le(d, 3);
    int cmap_len = _img_rd_u16le(d, 5);
    int cmap_bits = _img_bytep(d + 7);
    int w = _img_rd_u16le(d, 12);
    int h = _img_rd_u16le(d, 14);
    int bpp = _img_bytep(d + 16);
    int desc = _img_bytep(d + 17);
    if (w <= 0 || h <= 0) { return false; }

    bool rle = (type == 10 || type == 11 || type == 9);
    bool gray = (type == 3 || type == 11);
    bool indexed = (type == 1 || type == 9);
    if (!gray && !indexed && type != 2 && type != 10) { return false; }
    if (gray && bpp != 8 && bpp != 16) { return false; }
    if (!gray && !indexed && bpp != 24 && bpp != 32 && bpp != 16) { return false; }
    if (indexed && bpp != 8 && bpp != 16) { return false; }

    int pos = 18 + id_len;
    int cmap_off = pos;
    int cmap_bytes = 0;
    if (indexed) {
        if (cmap_type != 1 || cmap_bits != 24 && cmap_bits != 32 && cmap_bits != 16) {
            return false;
        }
        cmap_bytes = cmap_len * (cmap_bits / 8);
        pos = pos + cmap_bytes;
    } else if (cmap_type == 1) {
        int skip = cmap_len * (cmap_bits / 8);
        pos = pos + skip;
    }

    int pix_bytes = bpp / 8;
    if (pix_bytes <= 0) { return false; }
    char* pixels = alloc<char>(w * h * 4);
    if (pixels == null) { return false; }

    int x = 0;
    int y = 0;
    int count = 0;
    char* pixel_buf = alloc<char>(4);
    if (pixel_buf == null) { free(pixels); return false; }

    while (count < w * h) {
        int run = 1;
        bool repeat = false;
        if (rle) {
            if (pos >= size) { break; }
            int packet = _img_bytep(d + pos);
            pos = pos + 1;
            run = (packet & 127) + 1;
            if ((packet & 128) != 0) { repeat = true; }
        }
        if (repeat) {
            if (pos + pix_bytes > size) { break; }
            _img_copy(pixel_buf, 0, d, pos, pix_bytes);
            pos = pos + pix_bytes;
        }
        for (int k = 0; k < run; k = k + 1) {
            if (count >= w * h) { break; }
            if (!repeat) {
                if (pos + pix_bytes > size) { break; }
                _img_copy(pixel_buf, 0, d, pos, pix_bytes);
                pos = pos + pix_bytes;
            }
            int r = 0;
            int g = 0;
            int b = 0;
            int a = 255;
            if (gray) {
                r = _img_bytep(pixel_buf + 0);
                g = r;
                b = r;
                if (bpp == 16) { a = _img_bytep(pixel_buf + 1); }
            } else if (indexed) {
                int idx = _img_bytep(pixel_buf + 0);
                if (bpp == 16) { idx = _img_rd_u16le(pixel_buf, 0); }
                idx = idx - cmap_first;
                int ebytes = cmap_bits / 8;
                int off = cmap_off + idx * ebytes;
                if (idx >= 0 && idx < cmap_len && off + ebytes <= size) {
                    if (cmap_bits == 16) {
                        int v = _img_rd_u16le(d, off);
                        r = ((v >> 10) & 31) * 255 / 31;
                        g = ((v >> 5) & 31) * 255 / 31;
                        b = (v & 31) * 255 / 31;
                    } else {
                        b = _img_bytep(d + off + 0);
                        g = _img_bytep(d + off + 1);
                        r = _img_bytep(d + off + 2);
                        if (cmap_bits == 32) { a = _img_bytep(d + off + 3); }
                    }
                }
            } else {
                if (bpp == 16) {
                    int v = _img_rd_u16le(pixel_buf, 0);
                    r = ((v >> 10) & 31) * 255 / 31;
                    g = ((v >> 5) & 31) * 255 / 31;
                    b = (v & 31) * 255 / 31;
                } else {
                    b = _img_bytep(pixel_buf + 0);
                    g = _img_bytep(pixel_buf + 1);
                    r = _img_bytep(pixel_buf + 2);
                    if (bpp == 32) { a = _img_bytep(pixel_buf + 3); }
                }
            }
            int dx = x;
            int dy = y;
            if ((desc & 16) != 0) { dx = w - 1 - x; }
            if ((desc & 32) == 0) { dy = h - 1 - y; }
            int oi = (dy * w + dx) * 4;
            *(pixels + (oi + 0)) = cast<char>(r);
            *(pixels + (oi + 1)) = cast<char>(g);
            *(pixels + (oi + 2)) = cast<char>(b);
            *(pixels + (oi + 3)) = cast<char>(a);
            count = count + 1;
            x = x + 1;
            if (x >= w) {
                x = 0;
                y = y + 1;
            }
        }
    }

    free(pixel_buf);
    if (count < w * h) {
        free(pixels);
        return false;
    }
    out.width = w;
    out.height = h;
    out.channels = 4;
    out.stride = w * 4;
    out.data = pixels;
    out.owns_data = 1;
    return true;
}

fn _img_save_tga(Image* img, string path) -> bool {
    if (!image_is_valid(img)) { return false; }
    int total = 18 + img.width * img.height * 4;
    char* buf = alloc<char>(total);
    if (buf == null) { return false; }
    _img_zero(buf, 18);
    *(buf + 2) = cast<char>(2);
    _img_wr_u16le(buf, 12, img.width);
    _img_wr_u16le(buf, 14, img.height);
    *(buf + 16) = cast<char>(32);
    *(buf + 17) = cast<char>(32); // top-left origin, 8 alpha bits
    int off = 18;
    for (int y = 0; y < img.height; y = y + 1) {
        for (int x = 0; x < img.width; x = x + 1) {
            int v = image_get_pixel(img, x, y);
            *(buf + (off + 0)) = cast<char>(v & 255);
            *(buf + (off + 1)) = cast<char>((v >> 8) & 255);
            *(buf + (off + 2)) = cast<char>((v >> 16) & 255);
            *(buf + (off + 3)) = cast<char>((v >> 24) & 255);
            off = off + 4;
        }
    }
    bool ok = _img_write_file(path, buf, total);
    free(buf);
    return ok;
}

// ============================================================================
// 10. PNG: Deflate Inflate Engine
// ============================================================================

static int _inf_bitpos = 0;
static char* _inf_in = null;
static int _inf_in_len = 0;
static char* _inf_out = null;
static int _inf_out_pos = 0;
static int _inf_out_cap = 0;

fn _inf_getbit() -> int {
    if (_inf_bitpos >= _inf_in_len * 8) {
        return 0;
    }
    int bytepos = _inf_bitpos >> 3;
    int bit = _inf_bitpos & 7;
    int v = _img_bytep(_inf_in + bytepos);
    _inf_bitpos = _inf_bitpos + 1;
    return (v >> bit) & 1;
}

fn _inf_getbits(int n) -> int {
    int v = 0;
    for (int i = 0; i < n; i = i + 1) {
        v = v | (_inf_getbit() << i);
    }
    return v;
}

fn _inf_align_byte() -> void {
    _inf_bitpos = ((_inf_bitpos + 7) >> 3) << 3;
}

fn _inf_put(int b) -> bool {
    if (_inf_out_pos >= _inf_out_cap) {
        return false;
    }
    *(_inf_out + _inf_out_pos) = cast<char>(b & 255);
    _inf_out_pos = _inf_out_pos + 1;
    return true;
}

fn _inf_build(int* lengths, int n, int* counts, int* symbols) -> bool {
    for (int i = 0; i < 16; i = i + 1) {
        counts[i] = 0;
    }
    for (int i = 0; i < n; i = i + 1) {
        int l = lengths[i];
        if (l < 0 || l > 15) { return false; }
        counts[l] = counts[l] + 1;
    }
    if (counts[0] == n) {
        return true;
    }
    int left = 1;
    for (int l = 1; l <= 15; l = l + 1) {
        left = (left << 1) - counts[l];
        if (left < 0) { return false; }
    }
    int* offsets = alloc<int>(16);
    if (offsets == null) { return false; }
    int off = 0;
    for (int l = 1; l <= 15; l = l + 1) {
        offsets[l] = off;
        off = off + counts[l];
    }
    for (int sym = 0; sym < n; sym = sym + 1) {
        int l = lengths[sym];
        if (l != 0) {
            symbols[offsets[l]] = sym;
            offsets[l] = offsets[l] + 1;
        }
    }
    free(offsets);
    return true;
}

fn _inf_decode(int* counts, int* symbols) -> int {
    int code = 0;
    int first = 0;
    int index = 0;
    for (int len = 1; len <= 15; len = len + 1) {
        code = code | _inf_getbit();
        int count = counts[len];
        if (code < first + count) {
            return symbols[index + (code - first)];
        }
        index = index + count;
        first = (first + count) << 1;
        code = code << 1;
    }
    return -1;
}

fn _inf_len_base(int c) -> int {
    if (c == 285) { return 258; }
    if (c < 8) { return c + 3; }
    if (c == 8) { return 11; }
    if (c == 9) { return 13; }
    if (c == 10) { return 15; }
    if (c == 11) { return 17; }
    if (c == 12) { return 19; }
    if (c == 13) { return 23; }
    if (c == 14) { return 27; }
    if (c == 15) { return 31; }
    if (c == 16) { return 35; }
    if (c == 17) { return 43; }
    if (c == 18) { return 51; }
    if (c == 19) { return 59; }
    if (c == 20) { return 67; }
    if (c == 21) { return 83; }
    if (c == 22) { return 99; }
    if (c == 23) { return 115; }
    if (c == 24) { return 131; }
    if (c == 25) { return 163; }
    if (c == 26) { return 195; }
    if (c == 27) { return 227; }
    if (c == 28) { return 258; }
    return 3;
}

fn _inf_len_extra(int c) -> int {
    if (c < 8) { return 0; }
    if (c == 8) { return 1; }
    if (c == 9) { return 1; }
    if (c == 10) { return 1; }
    if (c == 11) { return 1; }
    if (c == 12) { return 2; }
    if (c == 13) { return 2; }
    if (c == 14) { return 2; }
    if (c == 15) { return 2; }
    if (c == 16) { return 3; }
    if (c == 17) { return 3; }
    if (c == 18) { return 3; }
    if (c == 19) { return 3; }
    if (c == 20) { return 4; }
    if (c == 21) { return 4; }
    if (c == 22) { return 4; }
    if (c == 23) { return 4; }
    if (c == 24) { return 5; }
    if (c == 25) { return 5; }
    if (c == 26) { return 5; }
    if (c == 27) { return 5; }
    if (c == 28) { return 0; }
    return 0;
}

fn _inf_dist_base(int c) -> int {
    if (c == 0) { return 1; }
    if (c == 1) { return 2; }
    if (c == 2) { return 3; }
    if (c == 3) { return 4; }
    if (c == 4) { return 5; }
    if (c == 5) { return 7; }
    if (c == 6) { return 9; }
    if (c == 7) { return 13; }
    if (c == 8) { return 17; }
    if (c == 9) { return 25; }
    if (c == 10) { return 33; }
    if (c == 11) { return 49; }
    if (c == 12) { return 65; }
    if (c == 13) { return 97; }
    if (c == 14) { return 129; }
    if (c == 15) { return 193; }
    if (c == 16) { return 257; }
    if (c == 17) { return 385; }
    if (c == 18) { return 513; }
    if (c == 19) { return 769; }
    if (c == 20) { return 1025; }
    if (c == 21) { return 1537; }
    if (c == 22) { return 2049; }
    if (c == 23) { return 3073; }
    if (c == 24) { return 4097; }
    if (c == 25) { return 6145; }
    if (c == 26) { return 8193; }
    if (c == 27) { return 12289; }
    if (c == 28) { return 16385; }
    if (c == 29) { return 24577; }
    return 1;
}

fn _inf_dist_extra(int c) -> int {
    if (c <= 3) { return 0; }
    if (c <= 5) { return 1; }
    if (c <= 7) { return 2; }
    if (c <= 9) { return 3; }
    if (c <= 11) { return 4; }
    if (c <= 13) { return 5; }
    if (c <= 15) { return 6; }
    if (c <= 17) { return 7; }
    if (c <= 19) { return 8; }
    if (c <= 21) { return 9; }
    if (c <= 23) { return 10; }
    if (c <= 25) { return 11; }
    if (c <= 27) { return 12; }
    if (c <= 29) { return 13; }
    return 0;
}

fn _inf_fixed_trees(int* lit_counts, int* lit_symbols, int* dist_counts, int* dist_symbols) -> bool {
    int* lengths = alloc<int>(288);
    if (lengths == null) { return false; }
    for (int i = 0; i < 288; i = i + 1) {
        if (i < 144) {
            lengths[i] = 8;
        } else if (i < 256) {
            lengths[i] = 9;
        } else if (i < 280) {
            lengths[i] = 7;
        } else {
            lengths[i] = 8;
        }
    }
    bool ok = _inf_build(lengths, 288, lit_counts, lit_symbols);
    if (ok) {
        for (int i = 0; i < 32; i = i + 1) {
            lengths[i] = 5;
        }
        ok = _inf_build(lengths, 32, dist_counts, dist_symbols);
    }
    free(lengths);
    return ok;
}

fn _inf_dynamic_trees(int* lit_counts, int* lit_symbols, int* dist_counts, int* dist_symbols) -> bool {
    int hlit = _inf_getbits(5) + 257;
    int hdist = _inf_getbits(5) + 1;
    int hclen = _inf_getbits(4) + 4;
    if (hlit > 286 || hdist > 30) { return false; }

    fixed<int, 19> order = {16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15};
    int* cl_lengths = alloc<int>(19);
    int* cl_counts = alloc<int>(16);
    int* cl_symbols = alloc<int>(19);
    if (cl_lengths == null || cl_counts == null || cl_symbols == null) {
        if (cl_lengths != null) { free(cl_lengths); }
        if (cl_counts != null) { free(cl_counts); }
        if (cl_symbols != null) { free(cl_symbols); }
        return false;
    }
    for (int i = 0; i < 19; i = i + 1) { cl_lengths[i] = 0; }
    for (int i = 0; i < hclen; i = i + 1) {
        cl_lengths[order[i]] = _inf_getbits(3);
    }
    if (!_inf_build(cl_lengths, 19, cl_counts, cl_symbols)) {
        free(cl_lengths); free(cl_counts); free(cl_symbols);
        return false;
    }

    int total = hlit + hdist;
    int* lengths = alloc<int>(total);
    if (lengths == null) {
        free(cl_lengths); free(cl_counts); free(cl_symbols);
        return false;
    }
    for (int i = 0; i < total; i = i + 1) { lengths[i] = 0; }

    int i = 0;
    while (i < total) {
        int sym = _inf_decode(cl_counts, cl_symbols);
        if (sym < 0) {
            free(cl_lengths); free(cl_counts); free(cl_symbols); free(lengths);
            return false;
        }
        if (sym < 16) {
            lengths[i] = sym;
            i = i + 1;
        } else if (sym == 16) {
            if (i == 0) {
                free(cl_lengths); free(cl_counts); free(cl_symbols); free(lengths);
                return false;
            }
            int repeat = _inf_getbits(2) + 3;
            int prev = lengths[i - 1];
            for (int k = 0; k < repeat && i < total; k = k + 1) {
                lengths[i] = prev;
                i = i + 1;
            }
        } else if (sym == 17) {
            int repeat = _inf_getbits(3) + 3;
            for (int k = 0; k < repeat && i < total; k = k + 1) {
                lengths[i] = 0;
                i = i + 1;
            }
        } else if (sym == 18) {
            int repeat = _inf_getbits(7) + 11;
            for (int k = 0; k < repeat && i < total; k = k + 1) {
                lengths[i] = 0;
                i = i + 1;
            }
        } else {
            free(cl_lengths); free(cl_counts); free(cl_symbols); free(lengths);
            return false;
        }
    }
    free(cl_lengths); free(cl_counts); free(cl_symbols);

    bool ok = _inf_build(lengths, hlit, lit_counts, lit_symbols);
    if (ok) {
        int* dlengths = alloc<int>(hdist);
        if (dlengths == null) {
            ok = false;
        } else {
            for (int j = 0; j < hdist; j = j + 1) {
                dlengths[j] = lengths[hlit + j];
            }
            ok = _inf_build(dlengths, hdist, dist_counts, dist_symbols);
            free(dlengths);
        }
    }
    free(lengths);
    return ok;
}

fn _inf_inflate(char* in, int in_len, char* out, int out_cap) -> int {
    _inf_in = in;
    _inf_in_len = in_len;
    _inf_out = out;
    _inf_out_pos = 0;
    _inf_out_cap = out_cap;
    _inf_bitpos = 16; // skip zlib header (CMF + FLG)

    int* lit_lengths = alloc<int>(286);
    int* dist_lengths = alloc<int>(30);
    int* lit_counts = alloc<int>(16);
    int* dist_counts = alloc<int>(16);
    int* lit_symbols = alloc<int>(288);
    int* dist_symbols = alloc<int>(32);
    if (lit_lengths == null || dist_lengths == null || lit_counts == null || dist_counts == null || lit_symbols == null || dist_symbols == null) {
        if (lit_lengths != null) { free(lit_lengths); }
        if (dist_lengths != null) { free(dist_lengths); }
        if (lit_counts != null) { free(lit_counts); }
        if (dist_counts != null) { free(dist_counts); }
        if (lit_symbols != null) { free(lit_symbols); }
        if (dist_symbols != null) { free(dist_symbols); }
        return -1;
    }

    bool final = false;
    bool error = false;
    while (!final && !error) {
        final = _inf_getbit() == 1;
        int btype = _inf_getbits(2);
        if (btype == 0) {
            _inf_align_byte();
            int len = _img_bytep(in + (_inf_bitpos >> 3))
                    | (_img_bytep(in + (_inf_bitpos >> 3) + 1) << 8);
            _inf_bitpos = _inf_bitpos + 32;
            for (int k = 0; k < len; k = k + 1) {
                if (!_inf_put(_img_bytep(in + (_inf_bitpos >> 3)))) {
                    error = true;
                    break;
                }
                _inf_bitpos = _inf_bitpos + 8;
            }
        } else if (btype == 1) {
            if (!_inf_fixed_trees(lit_counts, lit_symbols, dist_counts, dist_symbols)) {
                error = true;
            }
        } else if (btype == 2) {
            if (!_inf_dynamic_trees(lit_counts, lit_symbols, dist_counts, dist_symbols)) {
                error = true;
            }
        } else {
            error = true;
        }

        if (error) { break; }
        if (btype == 0) { continue; }

        while (true) {
            int sym = _inf_decode(lit_counts, lit_symbols);
            if (sym < 0) { error = true; break; }
            if (sym < 256) {
                if (!_inf_put(sym)) { error = true; break; }
            } else if (sym == 256) {
                break;
            } else if (sym >= 257 && sym <= 285) {
                int lc = sym - 257;
                int length = _inf_len_base(lc) + _inf_getbits(_inf_len_extra(lc));
                int dsym = _inf_decode(dist_counts, dist_symbols);
                if (dsym < 0 || dsym > 29) { error = true; break; }
                int dist = _inf_dist_base(dsym) + _inf_getbits(_inf_dist_extra(dsym));
                if (dist <= 0 || dist > _inf_out_pos) { error = true; break; }
                for (int k = 0; k < length; k = k + 1) {
                    int b = _img_bytep(out + _inf_out_pos - dist);
                    if (!_inf_put(b)) { error = true; break; }
                }
                if (error) { break; }
            } else {
                error = true;
                break;
            }
        }
    }

    int result = _inf_out_pos;
    if (error) { result = -1; }
    free(lit_lengths);
    free(dist_lengths);
    free(lit_counts);
    free(dist_counts);
    free(lit_symbols);
    free(dist_symbols);
    _inf_in = null;
    _inf_out = null;
    return result;
}

// ============================================================================
// 11. PNG: Filters, Decoder, CRC, and Encoder
// ============================================================================

fn _png_paeth(int a, int b, int c) -> int {
    int p = a + b - c;
    int pa = _img_abs(p - a);
    int pb = _img_abs(p - b);
    int pc = _img_abs(p - c);
    if (pa <= pb && pa <= pc) { return a; }
    if (pb <= pc) { return b; }
    return c;
}

fn _png_unfilter(char* row, char* prev, int rowbytes, int bpp, int filter) -> bool {
    if (filter == 0) {
        return true;
    }
    for (int i = 0; i < rowbytes; i = i + 1) {
        int x = _img_bytep(row + i);
        int a = 0;
        int b = 0;
        int c = 0;
        if (i >= bpp) { a = _img_bytep(row + i - bpp); }
        if (prev != null) {
            b = _img_bytep(prev + i);
            if (i >= bpp) { c = _img_bytep(prev + i - bpp); }
        }
        int v = x;
        if (filter == 1) {
            v = x + a;
        } else if (filter == 2) {
            v = x + b;
        } else if (filter == 3) {
            v = x + ((a + b) / 2);
        } else if (filter == 4) {
            v = x + _png_paeth(a, b, c);
        } else {
            return false;
        }
        *(row + i) = cast<char>(v & 255);
    }
    return true;
}

fn _png_sample(char* row, int bitpos, int bd) -> int {
    if (bd == 8) {
        return _img_bytep(row + (bitpos >> 3));
    }
    if (bd == 16) {
        int i = bitpos >> 3;
        return (_img_bytep(row + i) << 8) | _img_bytep(row + i + 1);
    }
    int i = bitpos >> 3;
    int shift = 8 - bd - (bitpos & 7);
    int mask = (1 << bd) - 1;
    return (_img_bytep(row + i) >> shift) & mask;
}

fn _png_scale(int s, int bd) -> int {
    if (bd == 8) { return s; }
    if (bd == 16) { return s >> 8; }
    return (s * 255) / ((1 << bd) - 1);
}

fn _img_decode_png(Image* out, char* d, int size) -> bool {
    if (size < 33) { return false; }
    if (_img_bytep(d + 0) != 137 || *(d + 1) != 'P' || *(d + 2) != 'N' || *(d + 3) != 'G') {
        return false;
    }
    int pos = 8;
    int w = 0;
    int h = 0;
    int bd = 0;
    int ct = 0;
    int interlace = 0;
    bool got_ihdr = false;
    bool got_iend = false;
    char* idat = alloc<char>(size);
    char* plte = null;
    int plte_len = 0;
    char* trns = null;
    int trns_len = 0;
    if (idat == null) { return false; }
    int idat_len = 0;

    while (pos + 12 <= size) {
        int clen = _img_rd_u32be(d, pos);
        if (clen < 0 || pos + 12 + clen > size) { break; }
        char* cdata = d + pos + 8;
        char c0 = *(d + (pos + 4));
        char c1 = *(d + (pos + 5));
        char c2 = *(d + (pos + 6));
        char c3 = *(d + (pos + 7));
        if (c0 == 'I' && c1 == 'H' && c2 == 'D' && c3 == 'R') {
            if (clen < 13) { break; }
            w = _img_rd_u32be(cdata, 0);
            h = _img_rd_u32be(cdata, 4);
            bd = _img_bytep(cdata + 8);
            ct = _img_bytep(cdata + 9);
            int comp = _img_bytep(cdata + 10);
            int filt = _img_bytep(cdata + 11);
            interlace = _img_bytep(cdata + 12);
            if (comp != 0 || filt != 0) { break; }
            got_ihdr = true;
        } else if (c0 == 'I' && c1 == 'D' && c2 == 'A' && c3 == 'T') {
            if (idat_len + clen > size) { break; }
            _img_copy(idat, idat_len, cdata, 0, clen);
            idat_len = idat_len + clen;
        } else if (c0 == 'P' && c1 == 'L' && c2 == 'T' && c3 == 'E') {
            if (plte != null) { free(plte); }
            plte = alloc<char>(clen);
            if (plte == null) { break; }
            _img_copy(plte, 0, cdata, 0, clen);
            plte_len = clen;
        } else if (c0 == 't' && c1 == 'R' && c2 == 'N' && c3 == 'S') {
            if (trns != null) { free(trns); }
            trns = alloc<char>(clen);
            if (trns == null) { break; }
            _img_copy(trns, 0, cdata, 0, clen);
            trns_len = clen;
        } else if (c0 == 'I' && c1 == 'E' && c2 == 'N' && c3 == 'D') {
            got_iend = true;
            break;
        }
        pos = pos + 12 + clen;
    }

    bool valid = got_ihdr && got_iend && w > 0 && h > 0 && idat_len > 0;
    if (valid) {
        if (ct == 0) {
            if (bd != 1 && bd != 2 && bd != 4 && bd != 8 && bd != 16) { valid = false; }
        } else if (ct == 2) {
            if (bd != 8 && bd != 16) { valid = false; }
        } else if (ct == 3) {
            if (bd != 1 && bd != 2 && bd != 4 && bd != 8) { valid = false; }
            if (plte == null || plte_len < 3) { valid = false; }
        } else if (ct == 4) {
            if (bd != 8 && bd != 16) { valid = false; }
        } else if (ct == 6) {
            if (bd != 8 && bd != 16) { valid = false; }
        } else {
            valid = false;
        }
        if (interlace != 0 && interlace != 1) { valid = false; }
    }
    if (!valid) {
        free(idat);
        if (plte != null) { free(plte); }
        if (trns != null) { free(trns); }
        return false;
    }

    int ch = 1;
    if (ct == 2) { ch = 3; }
    if (ct == 3) { ch = 1; }
    if (ct == 4) { ch = 2; }
    if (ct == 6) { ch = 4; }

    int raw_size = 0;
    if (interlace == 0) {
        raw_size = (1 + (w * ch * bd + 7) / 8) * h;
    } else {
        fixed<int, 7> xs = {0, 4, 0, 2, 0, 1, 0};
        fixed<int, 7> ys = {0, 0, 4, 0, 2, 0, 1};
        fixed<int, 7> dxs = {8, 8, 4, 4, 2, 2, 1};
        fixed<int, 7> dys = {8, 8, 8, 4, 4, 2, 2};
        for (int p = 0; p < 7; p = p + 1) {
            int pw = 0;
            int ph = 0;
            if (w > xs[p]) { pw = (w - xs[p] + dxs[p] - 1) / dxs[p]; }
            if (h > ys[p]) { ph = (h - ys[p] + dys[p] - 1) / dys[p]; }
            if (pw > 0 && ph > 0) {
                raw_size = raw_size + (1 + (pw * ch * bd + 7) / 8) * ph;
            }
        }
    }
    if (raw_size <= 0) {
        free(idat);
        if (plte != null) { free(plte); }
        if (trns != null) { free(trns); }
        return false;
    }

    char* rawbuf = alloc<char>(raw_size);
    if (rawbuf == null) {
        free(idat);
        if (plte != null) { free(plte); }
        if (trns != null) { free(trns); }
        return false;
    }
    int produced = _inf_inflate(idat, idat_len, rawbuf, raw_size);
    free(idat);
    if (produced != raw_size) {
        free(rawbuf);
        if (plte != null) { free(plte); }
        if (trns != null) { free(trns); }
        return false;
    }

    char* pixels = alloc<char>(w * h * 4);
    if (pixels == null) {
        free(rawbuf);
        if (plte != null) { free(plte); }
        if (trns != null) { free(trns); }
        return false;
    }
    for (int i = 0; i < w * h * 4; i = i + 1) {
        *(pixels + i) = cast<char>(0);
    }

    int rp = 0;
    bool ok = true;
    if (interlace == 0) {
        int rowbytes = (w * ch * bd + 7) / 8;
        int bpp = (ch * bd + 7) / 8;
        if (bpp < 1) { bpp = 1; }
        for (int y = 0; y < h && ok; y = y + 1) {
            int filter = _img_bytep(rawbuf + rp);
            rp = rp + 1;
            char* row = rawbuf + rp;
            char* prev = null;
            if (y > 0) { prev = row - rowbytes - 1; }
            if (!_png_unfilter(row, prev, rowbytes, bpp, filter)) {
                ok = false;
                break;
            }
            for (int x = 0; x < w; x = x + 1) {
                int r = 0;
                int g = 0;
                int b = 0;
                int a = 255;
                int bitpos = x * ch * bd;
                if (ct == 0) {
                    r = _png_scale(_png_sample(row, bitpos, bd), bd);
                    g = r; b = r;
                } else if (ct == 2) {
                    r = _png_scale(_png_sample(row, bitpos, bd), bd);
                    g = _png_scale(_png_sample(row, bitpos + bd, bd), bd);
                    b = _png_scale(_png_sample(row, bitpos + bd * 2, bd), bd);
                } else if (ct == 3) {
                    int idx = _png_sample(row, bitpos, bd);
                    if (idx * 3 + 2 < plte_len) {
                        r = _img_bytep(plte + idx * 3 + 0);
                        g = _img_bytep(plte + idx * 3 + 1);
                        b = _img_bytep(plte + idx * 3 + 2);
                    }
                    if (trns != null && idx < trns_len) {
                        a = _img_bytep(trns + idx);
                    }
                } else if (ct == 4) {
                    r = _png_scale(_png_sample(row, bitpos, bd), bd);
                    g = r; b = r;
                    a = _png_scale(_png_sample(row, bitpos + bd, bd), bd);
                } else if (ct == 6) {
                    r = _png_scale(_png_sample(row, bitpos, bd), bd);
                    g = _png_scale(_png_sample(row, bitpos + bd, bd), bd);
                    b = _png_scale(_png_sample(row, bitpos + bd * 2, bd), bd);
                    a = _png_scale(_png_sample(row, bitpos + bd * 3, bd), bd);
                }
                int oi = (y * w + x) * 4;
                *(pixels + (oi + 0)) = cast<char>(r);
                *(pixels + (oi + 1)) = cast<char>(g);
                *(pixels + (oi + 2)) = cast<char>(b);
                *(pixels + (oi + 3)) = cast<char>(a);
            }
            rp = rp + rowbytes;
        }
    } else {
        fixed<int, 7> xs = {0, 4, 0, 2, 0, 1, 0};
        fixed<int, 7> ys = {0, 0, 4, 0, 2, 0, 1};
        fixed<int, 7> dxs = {8, 8, 4, 4, 2, 2, 1};
        fixed<int, 7> dys = {8, 8, 8, 4, 4, 2, 2};
        for (int p = 0; p < 7 && ok; p = p + 1) {
            int pw = 0;
            int ph = 0;
            if (w > xs[p]) { pw = (w - xs[p] + dxs[p] - 1) / dxs[p]; }
            if (h > ys[p]) { ph = (h - ys[p] + dys[p] - 1) / dys[p]; }
            if (pw <= 0 || ph <= 0) { continue; }
            int rowbytes = (pw * ch * bd + 7) / 8;
            int bpp = (ch * bd + 7) / 8;
            if (bpp < 1) { bpp = 1; }
            for (int y = 0; y < ph && ok; y = y + 1) {
                int filter = _img_bytep(rawbuf + rp);
                rp = rp + 1;
                char* row = rawbuf + rp;
                char* prev = null;
                if (y > 0) { prev = row - rowbytes - 1; }
                if (!_png_unfilter(row, prev, rowbytes, bpp, filter)) {
                    ok = false;
                    break;
                }
                for (int x = 0; x < pw; x = x + 1) {
                    int r = 0;
                    int g = 0;
                    int b = 0;
                    int a = 255;
                    int bitpos = x * ch * bd;
                    if (ct == 0) {
                        r = _png_scale(_png_sample(row, bitpos, bd), bd);
                        g = r; b = r;
                    } else if (ct == 2) {
                        r = _png_scale(_png_sample(row, bitpos, bd), bd);
                        g = _png_scale(_png_sample(row, bitpos + bd, bd), bd);
                        b = _png_scale(_png_sample(row, bitpos + bd * 2, bd), bd);
                    } else if (ct == 3) {
                        int idx = _png_sample(row, bitpos, bd);
                        if (idx * 3 + 2 < plte_len) {
                            r = _img_bytep(plte + idx * 3 + 0);
                            g = _img_bytep(plte + idx * 3 + 1);
                            b = _img_bytep(plte + idx * 3 + 2);
                        }
                        if (trns != null && idx < trns_len) {
                            a = _img_bytep(trns + idx);
                        }
                    } else if (ct == 4) {
                        r = _png_scale(_png_sample(row, bitpos, bd), bd);
                        g = r; b = r;
                        a = _png_scale(_png_sample(row, bitpos + bd, bd), bd);
                    } else if (ct == 6) {
                        r = _png_scale(_png_sample(row, bitpos, bd), bd);
                        g = _png_scale(_png_sample(row, bitpos + bd, bd), bd);
                        b = _png_scale(_png_sample(row, bitpos + bd * 2, bd), bd);
                        a = _png_scale(_png_sample(row, bitpos + bd * 3, bd), bd);
                    }
                    int dx = xs[p] + x * dxs[p];
                    int dy = ys[p] + y * dys[p];
                    int oi = (dy * w + dx) * 4;
                    *(pixels + (oi + 0)) = cast<char>(r);
                    *(pixels + (oi + 1)) = cast<char>(g);
                    *(pixels + (oi + 2)) = cast<char>(b);
                    *(pixels + (oi + 3)) = cast<char>(a);
                }
                rp = rp + rowbytes;
            }
        }
    }

    free(rawbuf);
    if (plte != null) { free(plte); }
    if (trns != null) { free(trns); }
    if (!ok) {
        free(pixels);
        return false;
    }
    out.width = w;
    out.height = h;
    out.channels = 4;
    out.stride = w * 4;
    out.data = pixels;
    out.owns_data = 1;
    return true;
}

fn _png_crc32(char* type, char* data, int len) -> int {
    int crc = 0xffffffff;
    for (int i = 0; i < 4; i = i + 1) {
        crc = crc ^ _img_bytep(type + i);
        for (int k = 0; k < 8; k = k + 1) {
            if ((crc & 1) != 0) {
                crc = (crc >> 1) ^ 0xEDB88320;
            } else {
                crc = crc >> 1;
            }
            crc = crc & 0xffffffff;
        }
    }
    for (int i = 0; i < len; i = i + 1) {
        crc = crc ^ _img_bytep(data + i);
        for (int k = 0; k < 8; k = k + 1) {
            if ((crc & 1) != 0) {
                crc = (crc >> 1) ^ 0xEDB88320;
            } else {
                crc = crc >> 1;
            }
            crc = crc & 0xffffffff;
        }
    }
    return (crc ^ 0xffffffff) & 0xffffffff;
}

fn _png_adler32(char* data, int len) -> int {
    int s1 = 1;
    int s2 = 0;
    for (int i = 0; i < len; i = i + 1) {
        s1 = (s1 + _img_bytep(data + i)) % 65521;
        s2 = (s2 + s1) % 65521;
    }
    return (s2 << 16) | s1;
}

fn _png_build_chunk(char* dst, int off, char* type, char* data, int len) -> int {
    _img_wr_u32be(dst, off, len);
    *(dst + (off + 4)) = cast<char>(_img_bytep(type + 0));
    *(dst + (off + 5)) = cast<char>(_img_bytep(type + 1));
    *(dst + (off + 6)) = cast<char>(_img_bytep(type + 2));
    *(dst + (off + 7)) = cast<char>(_img_bytep(type + 3));
    if (len > 0) {
        _img_copy(dst, off + 8, data, 0, len);
    }
    int crc = _png_crc32(type, data, len);
    _img_wr_u32be(dst, off + 8 + len, crc);
    return off + 12 + len;
}

fn _img_save_png(Image* img, string path) -> bool {
    if (!image_is_valid(img)) { return false; }
    int raw_size = (img.width * 4 + 1) * img.height;
    int blocks = (raw_size + 65534) / 65535;
    if (blocks < 1) { blocks = 1; }
    int zlib_size = 2 + raw_size + blocks * 5 + 4;
    int total = 8 + 25 + 12 + zlib_size + 12;
    char* file = alloc<char>(total + 8);
    if (file == null) { return false; }
    _img_zero(file, total);

    // PNG signature
    *(file + 0) = cast<char>(137);
    *(file + 1) = cast<char>('P');
    *(file + 2) = cast<char>('N');
    *(file + 3) = cast<char>('G');
    *(file + 4) = cast<char>(13);
    *(file + 5) = cast<char>(10);
    *(file + 6) = cast<char>(26);
    *(file + 7) = cast<char>(10);

    // IHDR
    char* ihdr = alloc<char>(13);
    char* t_ihdr = alloc<char>(4);
    if (ihdr == null || t_ihdr == null) {
        if (ihdr != null) { free(ihdr); }
        if (t_ihdr != null) { free(t_ihdr); }
        free(file);
        return false;
    }
    _img_wr_u32be(ihdr, 0, img.width);
    _img_wr_u32be(ihdr, 4, img.height);
    *(ihdr + 8) = cast<char>(8);   // bit depth
    *(ihdr + 9) = cast<char>(6);   // RGBA
    *(ihdr + 10) = cast<char>(0);  // compression
    *(ihdr + 11) = cast<char>(0);  // filter
    *(ihdr + 12) = cast<char>(0);  // no interlace
    *(t_ihdr + 0) = cast<char>('I'); *(t_ihdr + 1) = cast<char>('H'); *(t_ihdr + 2) = cast<char>('D'); *(t_ihdr + 3) = cast<char>('R');
    int fpos = _png_build_chunk(file, 8, t_ihdr, ihdr, 13);
    free(ihdr);
    free(t_ihdr);

    // Build zlib stream (stored deflate blocks)
    char* z = file + fpos + 8; // chunk data starts after length+type
    *(z + 0) = cast<char>(0x78);
    *(z + 1) = cast<char>(0x01);
    int zp = 2;
    char* rawbuf = alloc<char>(raw_size);
    if (rawbuf == null) { free(file); return false; }
    int rp = 0;
    for (int y = 0; y < img.height; y = y + 1) {
        *(rawbuf + rp) = cast<char>(0);
        rp = rp + 1;
        for (int x = 0; x < img.width; x = x + 1) {
            int v = image_get_pixel(img, x, y);
            *(rawbuf + (rp + 0)) = cast<char>((v >> 16) & 255);
            *(rawbuf + (rp + 1)) = cast<char>((v >> 8) & 255);
            *(rawbuf + (rp + 2)) = cast<char>(v & 255);
            *(rawbuf + (rp + 3)) = cast<char>((v >> 24) & 255);
            rp = rp + 4;
        }
    }
    int consumed = 0;
    int block_index = 0;
    while (consumed < raw_size) {
        int n = raw_size - consumed;
        if (n > 65535) { n = 65535; }
        int is_final = 0;
        if (consumed + n >= raw_size) { is_final = 1; }
        *(z + zp) = cast<char>(is_final);
        zp = zp + 1;
        _img_wr_u16le(z, zp, n);
        zp = zp + 2;
        _img_wr_u16le(z, zp, 65535 - n);
        zp = zp + 2;
        _img_copy(z, zp, rawbuf, consumed, n);
        zp = zp + n;
        consumed = consumed + n;
        block_index = block_index + 1;
    }
    int adler = _png_adler32(rawbuf, raw_size);
    free(rawbuf);
    _img_wr_u32be(z, zp, adler);
    zp = zp + 4;

    // IDAT chunk
    char* t_idat = alloc<char>(4);
    if (t_idat == null) { free(file); return false; }
    *(t_idat + 0) = cast<char>('I'); *(t_idat + 1) = cast<char>('D'); *(t_idat + 2) = cast<char>('A'); *(t_idat + 3) = cast<char>('T');
    char* zcopy = alloc<char>(zp + 8);
    if (zcopy == null) { free(t_idat); free(file); return false; }
    _img_copy(zcopy, 0, z, 0, zp);
    fpos = _png_build_chunk(file, fpos, t_idat, zcopy, zp);
    free(zcopy);
    free(t_idat);

    // IEND
    char* t_iend = alloc<char>(4);
    if (t_iend == null) { free(file); return false; }
    *(t_iend + 0) = cast<char>('I'); *(t_iend + 1) = cast<char>('E'); *(t_iend + 2) = cast<char>('N'); *(t_iend + 3) = cast<char>('D');
    fpos = _png_build_chunk(file, fpos, t_iend, null, 0);
    free(t_iend);

    bool ok = _img_write_file(path, file, fpos);
    free(file);
    return ok;
}

// ============================================================================
// 12. Public Load / Save API
// ============================================================================

fn _img_decode(Image* out, char* d, int size, int fmt) -> bool {
    if (fmt == IMAGE_FMT_PNG) { return _img_decode_png(out, d, size); }
    if (fmt == IMAGE_FMT_BMP) { return _img_decode_bmp(out, d, size); }
    if (fmt == IMAGE_FMT_PPM) { return _img_decode_ppm(out, d, size, 0); }
    if (fmt == IMAGE_FMT_PGM) { return _img_decode_ppm(out, d, size, 1); }
    if (fmt == IMAGE_FMT_TGA) { return _img_decode_tga(out, d, size); }
    return false;
}

fn image_load(string path) -> Image* {
    int size = 0;
    char* data = _img_read_file(path, &size);
    if (data == null || size <= 0) {
        if (data != null) { free(data); }
        return null;
    }
    int fmt = _img_detect_format(data, size, path);
    Image* img = new Image;
    img.width = 0;
    img.height = 0;
    img.channels = 4;
    img.stride = 0;
    img.data = null;
    img.owns_data = 0;
    bool ok = _img_decode(img, data, size, fmt);
    free(data);
    if (!ok) {
        if (img.data != null) { free(img.data); }
        free(img);
        return null;
    }
    return img;
}

fn image_load_into(Image* img, string path) -> bool {
    if (img == null) { return false; }
    Image* loaded = image_load(path);
    if (loaded == null) { return false; }
    image_free_data(img);
    img.width = loaded.width;
    img.height = loaded.height;
    img.channels = 4;
    img.stride = loaded.stride;
    img.data = loaded.data;
    img.owns_data = 1;
    loaded.data = null;
    loaded.owns_data = 0;
    free(loaded);
    return true;
}

fn image_save(Image* img, string path) -> bool {
    if (!image_is_valid(img)) { return false; }
    if (_img_has_ext(path, "png")) { return _img_save_png(img, path); }
    if (_img_has_ext(path, "bmp")) { return _img_save_bmp(img, path); }
    if (_img_has_ext(path, "ppm") || _img_has_ext(path, "pnm")) { return _img_save_ppm(img, path, 0); }
    if (_img_has_ext(path, "pgm")) { return _img_save_ppm(img, path, 1); }
    if (_img_has_ext(path, "tga")) { return _img_save_tga(img, path); }
    return _img_save_png(img, path);
}

fn image_save_bmp(Image* img, string path) -> bool { return _img_save_bmp(img, path); }
fn image_save_png(Image* img, string path) -> bool { return _img_save_png(img, path); }
fn image_save_ppm(Image* img, string path) -> bool { return _img_save_ppm(img, path, 0); }
fn image_save_pgm(Image* img, string path) -> bool { return _img_save_ppm(img, path, 1); }
fn image_save_tga(Image* img, string path) -> bool { return _img_save_tga(img, path); }

fn image_load_bmp(string path) -> Image* { return image_load(path); }
fn image_load_png(string path) -> Image* { return image_load(path); }
fn image_load_ppm(string path) -> Image* { return image_load(path); }
fn image_load_tga(string path) -> Image* { return image_load(path); }
fn image_load_pgm(string path) -> Image* { return image_load(path); }

// ============================================================================
// 13. Convenience Utilities
// ============================================================================

fn image_print_info(Image* img) -> void {
    if (img == null) {
        print_str("Image: <null>\n");
        return;
    }
    print_str("Image: ");
    print(img.width);
    print_str("x");
    print(img.height);
    print_str(" RGBA\n");
}

fn image_save_thumbnail(Image* img, string path, int max_size) -> bool {
    if (!image_is_valid(img) || max_size <= 0) { return false; }
    int nw = img.width;
    int nh = img.height;
    if (nw >= nh && nw > max_size) {
        nh = (img.height * max_size) / img.width;
        nw = max_size;
    } else if (nh > nw && nh > max_size) {
        nw = (img.width * max_size) / img.height;
        nh = max_size;
    }
    Image* small = image_resize_bilinear(img, nw, nh);
    if (small == null) { return false; }
    bool ok = image_save(small, path);
    image_destroy(small);
    return ok;
}
