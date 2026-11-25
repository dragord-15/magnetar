use "lib/image.mg";
use "lib/string.mg";

struct ColorProfile {
    int ok;
    int width;
    int height;
    int sample_w;
    int sample_h;
    int avg_r;
    int avg_g;
    int avg_b;
    int sat_pct;
    int bright_pct;
    int colorful_pct;
    int edge_pct;
    int strong_edge_pm;
    int hist_spread;
    int peak_pct;
    int second_peak_pct;
    int text_risk;
    int text_free;
    int palette_count;
    int pr[6];
    int pg[6];
    int pb[6];
    int pp[6];
    string dominant_name;
    string palette_names;
    string palette_hex;
    string search_color;
    string search_query;
    string classification;
};

fn ii_abs(int v) -> int {
    if (v < 0) { return -v; }
    return v;
}

fn ii_clamp(int v, int lo, int hi) -> int {
    if (v < lo) { return lo; }
    if (v > hi) { return hi; }
    return v;
}

fn ii_sqrt(int n) -> int {
    if (n <= 0) { return 0; }
    int x = n;
    int y = (x + 1) / 2;
    while (y < x) {
        x = y;
        y = (x + n / x) / 2;
    }
    return x;
}

fn ii_hex_digit(int v) -> char {
    if (v < 10) { return cast<char>(48 + v); }
    return cast<char>(55 + v);
}

fn ii_hex_color(int r, int g, int b) -> string {
    char* out = alloc<char>(8);
    *(out + 0) = 35;
    *(out + 1) = ii_hex_digit((r >> 4) & 15);
    *(out + 2) = ii_hex_digit(r & 15);
    *(out + 3) = ii_hex_digit((g >> 4) & 15);
    *(out + 4) = ii_hex_digit(g & 15);
    *(out + 5) = ii_hex_digit((b >> 4) & 15);
    *(out + 6) = ii_hex_digit(b & 15);
    *(out + 7) = 0;
    return cast<string>(out);
}

fn ii_hue(int r, int g, int b) -> int {
    int hi = r;
    if (g > hi) { hi = g; }
    if (b > hi) { hi = b; }
    int lo = r;
    if (g < lo) { lo = g; }
    if (b < lo) { lo = b; }
    int d = hi - lo;
    if (d == 0) { return 0; }
    int h = 0;
    if (hi == r) {
        h = (60 * (g - b)) / d;
    } else if (hi == g) {
        h = 120 + (60 * (b - r)) / d;
    } else {
        h = 240 + (60 * (r - g)) / d;
    }
    if (h < 0) { h = h + 360; }
    if (h >= 360) { h = h - 360; }
    return h;
}

fn ii_color_name(int r, int g, int b) -> string {
    int hi = r;
    if (g > hi) { hi = g; }
    if (b > hi) { hi = b; }
    int lo = r;
    if (g < lo) { lo = g; }
    if (b < lo) { lo = b; }
    int d = hi - lo;
    int h = ii_hue(r, g, b);
    int s = 0;
    if (hi > 0) { s = d * 100 / hi; }
    int v = hi * 100 / 255;
    if (v < 12) { return "black"; }
    if (s < 12 && v > 88) { return "white"; }
    if (s < 14) {
        if (v < 45) { return "dark gray"; }
        return "gray";
    }
    if (h < 15 || h >= 345) { return "red"; }
    if (h < 45) {
        if (v < 55) { return "brown"; }
        return "orange";
    }
    if (h < 70) { return "yellow"; }
    if (h < 165) { return "green"; }
    if (h < 195) { return "teal"; }
    if (h < 255) { return "blue"; }
    if (h < 290) { return "purple"; }
    if (h < 325) { return "magenta"; }
    return "pink";
}

fn ii_canonical_color(int r, int g, int b) -> string {
    string n = ii_color_name(r, g, b);
    if (n == "red") { return "red"; }
    if (n == "orange") { return "orange"; }
    if (n == "yellow") { return "yellow"; }
    if (n == "green") { return "green"; }
    if (n == "teal") { return "teal"; }
    if (n == "blue") { return "blue"; }
    if (n == "purple") { return "purple"; }
    if (n == "magenta") { return "purple"; }
    if (n == "pink") { return "pink"; }
    if (n == "brown") { return "brown"; }
    if (n == "black") { return "black"; }
    if (n == "white") { return "white"; }
    return "gray";
}

fn ii_join_name(string current, string next) -> string {
    if (len(current) == 0) { return next; }
    return str_concat(current, str_concat(" / ", next));
}

fn image_intel_analyze(Image* src, ColorProfile* p) -> void {
    p.ok = 0;
    p.width = 0;
    p.height = 0;
    p.sample_w = 0;
    p.sample_h = 0;
    p.avg_r = 0;
    p.avg_g = 0;
    p.avg_b = 0;
    p.sat_pct = 0;
    p.bright_pct = 0;
    p.colorful_pct = 0;
    p.edge_pct = 0;
    p.strong_edge_pm = 0;
    p.hist_spread = 0;
    p.peak_pct = 0;
    p.second_peak_pct = 0;
    p.text_risk = 0;
    p.text_free = 0;
    p.palette_count = 0;
    p.dominant_name = "";
    p.palette_names = "";
    p.palette_hex = "";
    p.search_color = "gray";
    p.search_query = "";
    p.classification = "NO IMAGE";
    int k = 0;
    while (k < 6) {
        p.pr[k] = 0;
        p.pg[k] = 0;
        p.pb[k] = 0;
        p.pp[k] = 0;
        k = k + 1;
    }

    if (!image_is_valid(src)) { return; }
    p.ok = 1;
    p.width = src.width;
    p.height = src.height;

    int nw = src.width;
    int nh = src.height;
    int maxside = 192;
    if (nw >= nh && nw > maxside) {
        nh = src.height * maxside / src.width;
        nw = maxside;
    } else if (nh > nw && nh > maxside) {
        nw = src.width * maxside / src.height;
        nh = maxside;
    }
    if (nw < 4) { nw = 4; }
    if (nh < 4) { nh = 4; }
    Image* small = image_resize_bilinear(src, nw, nh);
    if (small == null) { return; }
    p.sample_w = nw;
    p.sample_h = nh;

    int total = nw * nh;
    int* bin_count = alloc<int>(4096);
    int* bin_r = alloc<int>(4096);
    int* bin_g = alloc<int>(4096);
    int* bin_b = alloc<int>(4096);
    int* hist = alloc<int>(32);
    int* lum = alloc<int>(total);
    int i = 0;
    while (i < 4096) {
        bin_count[i] = 0;
        bin_r[i] = 0;
        bin_g[i] = 0;
        bin_b[i] = 0;
        i = i + 1;
    }
    i = 0;
    while (i < 32) {
        hist[i] = 0;
        i = i + 1;
    }

    int valid = 0;
    int sum_r = 0;
    int sum_g = 0;
    int sum_b = 0;
    int sum_lum = 0;
    int sum_sat = 0;
    int sum_rg = 0;
    int sum_yb = 0;
    int sum_rg2 = 0;
    int sum_yb2 = 0;
    int y = 0;
    while (y < nh) {
        int x = 0;
        while (x < nw) {
            int v = image_get_pixel(small, x, y);
            int a = (v >> 24) & 255;
            int r = (v >> 16) & 255;
            int g = (v >> 8) & 255;
            int b = v & 255;
            int li = y * nw + x;
            if (a < 16) {
                lum[li] = 255;
                x = x + 1;
                continue;
            }
            int hi = r;
            if (g > hi) { hi = g; }
            if (b > hi) { hi = b; }
            int lo = r;
            if (g < lo) { lo = g; }
            if (b < lo) { lo = b; }
            int sat = 0;
            if (hi > 0) { sat = (hi - lo) * 255 / hi; }
            int luma = (r * 299 + g * 587 + b * 114) / 1000;
            lum[li] = luma;

            int rg = r - g;
            int yb = (r + g) / 2 - b;
            valid = valid + 1;
            sum_r = sum_r + r;
            sum_g = sum_g + g;
            sum_b = sum_b + b;
            sum_lum = sum_lum + luma;
            sum_sat = sum_sat + sat;
            sum_rg = sum_rg + rg;
            sum_yb = sum_yb + yb;
            sum_rg2 = sum_rg2 + rg * rg;
            sum_yb2 = sum_yb2 + yb * yb;

            int bi = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4);
            bin_count[bi] = bin_count[bi] + 1;
            bin_r[bi] = bin_r[bi] + r;
            bin_g[bi] = bin_g[bi] + g;
            bin_b[bi] = bin_b[bi] + b;
            hist[luma >> 3] = hist[luma >> 3] + 1;
            x = x + 1;
        }
        y = y + 1;
    }

    if (valid <= 0) { valid = 1; }
    p.avg_r = sum_r / valid;
    p.avg_g = sum_g / valid;
    p.avg_b = sum_b / valid;
    p.sat_pct = (sum_sat / valid) * 100 / 255;
    p.bright_pct = (sum_lum / valid) * 100 / 255;

    int mean_rg = sum_rg / valid;
    int mean_yb = sum_yb / valid;
    int var_rg = sum_rg2 / valid - mean_rg * mean_rg;
    int var_yb = sum_yb2 / valid - mean_yb * mean_yb;
    if (var_rg < 0) { var_rg = 0; }
    if (var_yb < 0) { var_yb = 0; }
    int sd_rg = ii_sqrt(var_rg);
    int sd_yb = ii_sqrt(var_yb);
    int mean_mag = ii_sqrt(mean_rg * mean_rg + mean_yb * mean_yb);
    int cf = ii_sqrt(sd_rg * sd_rg + sd_yb * sd_yb) + (3 * mean_mag) / 10;
    p.colorful_pct = ii_clamp(cf * 100 / 160, 0, 100);

    int peak = 0;
    int second = 0;
    int spread = 0;
    i = 0;
    while (i < 32) {
        int pct = hist[i] * 100 / valid;
        if (pct >= 1) { spread = spread + 1; }
        if (hist[i] > peak) {
            second = peak;
            peak = hist[i];
        } else if (hist[i] > second) {
            second = hist[i];
        }
        i = i + 1;
    }
    p.hist_spread = spread;
    p.peak_pct = peak * 100 / valid;
    p.second_peak_pct = second * 100 / valid;

    int edge_threshold = 190;
    int edges = 0;
    int strong_edges = 0;
    int inner = 0;
    y = 1;
    while (y < nh - 1) {
        int x = 1;
        while (x < nw - 1) {
            int i00 = lum[(y - 1) * nw + (x - 1)];
            int i10 = lum[(y - 1) * nw + x];
            int i20 = lum[(y - 1) * nw + (x + 1)];
            int i01 = lum[y * nw + (x - 1)];
            int i21 = lum[y * nw + (x + 1)];
            int i02 = lum[(y + 1) * nw + (x - 1)];
            int i12 = lum[(y + 1) * nw + x];
            int i22 = lum[(y + 1) * nw + (x + 1)];
            int gx = (i20 + 2 * i21 + i22) - (i00 + 2 * i01 + i02);
            int gy = (i02 + 2 * i12 + i22) - (i00 + 2 * i10 + i20);
            int mag = ii_abs(gx) + ii_abs(gy);
            if (mag >= edge_threshold) { edges = edges + 1; }
            if (mag >= 500) { strong_edges = strong_edges + 1; }
            inner = inner + 1;
            x = x + 1;
        }
        y = y + 1;
    }
    if (inner > 0) {
        p.edge_pct = edges * 100 / inner;
        p.strong_edge_pm = strong_edges * 1000 / inner;
    }

    int er[6];
    int eg[6];
    int eb[6];
    int ep[6];
    int top_idx[8];
    int top_n = 0;
    k = 0;
    while (k < 8) {
        int best = 0 - 1;
        int best_count = 0;
        i = 0;
        while (i < 4096) {
            int already = 0;
            int u = 0;
            while (u < k) {
                if (top_idx[u] == i) { already = 1; }
                u = u + 1;
            }
            if (already == 0 && bin_count[i] > best_count) {
                best_count = bin_count[i];
                best = i;
            }
            i = i + 1;
        }
        if (best >= 0 && best_count > 0) {
            top_idx[k] = best;
            top_n = top_n + 1;
        }
        k = k + 1;
    }
    p.palette_count = 0;
    k = 0;
    while (k < top_n) {
        int bi = top_idx[k];
        int cnt = bin_count[bi];
        if (cnt > 0) {
            int cr = bin_r[bi] / cnt;
            int cg = bin_g[bi] / cnt;
            int cb = bin_b[bi] / cnt;
            int merged = 0;
            int e = 0;
            while (e < p.palette_count) {
                int dr = cr - er[e];
                int dg = cg - eg[e];
                int db = cb - eb[e];
                if (dr * dr + dg * dg + db * db < 700) {
                    int newc = ep[e] + cnt;
                    er[e] = (er[e] * ep[e] + cr * cnt) / newc;
                    eg[e] = (eg[e] * ep[e] + cg * cnt) / newc;
                    eb[e] = (eb[e] * ep[e] + cb * cnt) / newc;
                    ep[e] = newc;
                    merged = 1;
                    e = p.palette_count;
                } else {
                    e = e + 1;
                }
            }
            if (merged == 0 && p.palette_count < 6) {
                er[p.palette_count] = cr;
                eg[p.palette_count] = cg;
                eb[p.palette_count] = cb;
                ep[p.palette_count] = cnt;
                p.palette_count = p.palette_count + 1;
            }
        }
        k = k + 1;
    }

    int a = 0;
    while (a < p.palette_count) {
        int b = a + 1;
        while (b < p.palette_count) {
            if (ep[b] > ep[a]) {
                int t = ep[a]; ep[a] = ep[b]; ep[b] = t;
                t = er[a]; er[a] = er[b]; er[b] = t;
                t = eg[a]; eg[a] = eg[b]; eg[b] = t;
                t = eb[a]; eb[a] = eb[b]; eb[b] = t;
            }
            b = b + 1;
        }
        a = a + 1;
    }
    k = 0;
    string names = "";
    string hexes = "";
    while (k < p.palette_count) {
        p.pr[k] = er[k];
        p.pg[k] = eg[k];
        p.pb[k] = eb[k];
        p.pp[k] = ep[k] * 100 / valid;
        string cn = ii_color_name(er[k], eg[k], eb[k]);
        names = ii_join_name(names, cn);
        if (len(hexes) > 0) { hexes = str_concat(hexes, " "); }
        hexes = str_concat(hexes, ii_hex_color(er[k], eg[k], eb[k]));
        k = k + 1;
    }
    p.palette_names = names;
    p.palette_hex = hexes;
    if (p.palette_count > 0) {
        p.dominant_name = ii_color_name(p.pr[0], p.pg[0], p.pb[0]);
        p.search_color = ii_canonical_color(p.pr[0], p.pg[0], p.pb[0]);
        p.search_query = str_concat(p.dominant_name, " color palette");
        if (p.palette_count > 1) {
            p.search_query = str_concat(p.search_query, str_concat(" ", ii_color_name(p.pr[1], p.pg[1], p.pb[1])));
        }
    } else {
        p.dominant_name = "unknown";
        p.search_color = "gray";
        p.search_query = "color palette";
    }

    int flat = 0;
    if (p.hist_spread <= 12) { flat = 1; }
    if (p.peak_pct >= 30) { flat = 1; }
    int risk = 0;
    if (flat == 1 && p.edge_pct > 3) {
        risk = risk + (p.edge_pct - 3) * 2;
        if (risk > 30) { risk = 30; }
    }
    if (flat == 1 && p.strong_edge_pm >= 10) {
        risk = risk + 18 + (p.strong_edge_pm - 10) / 3;
        if (risk > 62) { risk = 62; }
    } else if (flat == 1 && p.strong_edge_pm >= 8 && p.edge_pct > 1) {
        risk = risk + 12;
    }
    if (p.hist_spread <= 10 && p.peak_pct >= 35) { risk = risk + 10; }
    if (p.peak_pct >= 55 && p.edge_pct > 8) { risk = risk + 8; }
    if (flat == 1 && p.sat_pct < 18 && p.edge_pct > 4) { risk = risk + 10; }
    if (flat == 1 && p.colorful_pct < 18 && p.edge_pct > 4) { risk = risk + 8; }
    if (flat == 1 && p.palette_count <= 2 && p.edge_pct > 8) { risk = risk + 15; }
    p.text_risk = ii_clamp(risk, 0, 100);
    if (p.text_risk < 12) {
        if (p.hist_spread >= 14 && p.peak_pct < 25) { p.classification = "PHOTO"; }
        else { p.classification = "TEXT-FREE"; }
    } else if (p.text_risk < 35) { p.classification = "COLOR-SAFE"; }
    else if (p.text_risk < 55) { p.classification = "REVIEW"; }
    else { p.classification = "TEXT-LIKELY"; }
    p.text_free = 0;
    if (p.text_risk < 12) { p.text_free = 1; }

    free(bin_count);
    free(bin_r);
    free(bin_g);
    free(bin_b);
    free(hist);
    free(lum);
    image_destroy(small);
    return;
}

fn image_intel_load(string path, ColorProfile* p) -> void {
    p.ok = 0;
    p.classification = "NO IMAGE";
    p.dominant_name = "";
    p.palette_names = "";
    p.palette_hex = "";
    p.search_color = "gray";
    p.search_query = "color palette";
    p.palette_count = 0;
    p.text_risk = 0;
    p.text_free = 0;
    Image* img = image_load(path);
    if (img == null) { return; }
    image_intel_analyze(img, p);
    image_destroy(img);
}
