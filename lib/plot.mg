// lib/plot.mg — Matplotlib-style Charting & Statistics Library for Magnetar
// Built on top of lib/gui.mg for high-performance 60 FPS graphics and direct card0/X11 rendering.

use "gui.mg";

extern fn print_str(string s) -> void;
extern fn print_int(int n) -> void;
extern fn sleep_ms(int ms) -> void;

// ─── Matplotlib Color Palette (Tableau 10 & Scientific) ──────────
static const int PLT_BLUE    = 0x1F77B4; // #1f77b4 Classic Blue
static const int PLT_ORANGE  = 0xFF7F0E; // #ff7f0e Bright Orange
static const int PLT_GREEN   = 0x2CA02C; // #2ca02c Forest Green
static const int PLT_RED     = 0xD62728; // #d62728 Crimson Red
static const int PLT_PURPLE  = 0x9467BD; // #9467bd Royal Purple
static const int PLT_BROWN   = 0x8C564B; // #8c564b Earth Brown
static const int PLT_PINK    = 0xE377C2; // #e377c2 Orchid Pink
static const int PLT_GRAY    = 0x7F7F7F; // #7f7f7f Neutral Gray
static const int PLT_OLIVE   = 0xBCBD22; // #bcbd22 Olive Gold
static const int PLT_CYAN    = 0x17BECF; // #17becf Aqua Cyan
static const int PLT_WHITE   = 0xFFFFFF;
static const int PLT_YELLOW  = 0xF1C40F;
static const int PLT_MINT    = 0x26A69A; // Trading Green

// ─── Plot Types ──────────────────────────────────────────
static const int PLT_TYPE_LINE       = 1;
static const int PLT_TYPE_SCATTER    = 2;
static const int PLT_TYPE_BAR        = 3;
static const int PLT_TYPE_BARH       = 4;
static const int PLT_TYPE_HIST       = 5;
static const int PLT_TYPE_PIE        = 6;
static const int PLT_TYPE_AREA       = 7;
static const int PLT_TYPE_REGRESSION = 8;
static const int PLT_TYPE_CANDLE     = 9;

// ─── Math & Geometry Helpers ─────────────────────────────
fn math_isqrt(int n) -> int {
    if (n <= 0) { return 0; }
    if (n == 1) { return 1; }
    int x = n;
    int y = (x + 1) / 2;
    while (y < x) {
        x = y;
        y = (x + n / x) / 2;
    }
    return x;
}

// Fast integer atan2 returning 0..359 degrees
fn math_atan2_deg(int dy, int dx) -> int {
    if (dx == 0 && dy == 0) { return 0; }
    int ax = dx;
    if (ax < 0) { ax = 0 - ax; }
    int ay = dy;
    if (ay < 0) { ay = 0 - ay; }

    int angle = 0;
    if (ax > ay) {
        angle = (45 * ay) / ax;
    } else {
        angle = 90 - (45 * ax) / ay;
    }

    if (dx < 0 && dy >= 0) {
        angle = 180 - angle;
    } else if (dx < 0 && dy < 0) {
        angle = 180 + angle;
    } else if (dx >= 0 && dy < 0) {
        angle = 360 - angle;
    }
    return angle;
}

// ─── Comprehensive Statistics Functions (scipy / numpy style) ───

fn stat_sum(int* arr, int n) -> int {
    int s = 0;
    int i = 0;
    while (i < n) {
        s = s + arr[i];
        i = i + 1;
    }
    return s;
}

fn stat_mean(int* arr, int n) -> int {
    if (n <= 0) { return 0; }
    return stat_sum(arr, n) / n;
}

fn stat_min(int* arr, int n) -> int {
    if (n <= 0) { return 0; }
    int m = arr[0];
    int i = 1;
    while (i < n) {
        if (arr[i] < m) { m = arr[i]; }
        i = i + 1;
    }
    return m;
}

fn stat_max(int* arr, int n) -> int {
    if (n <= 0) { return 0; }
    int m = arr[0];
    int i = 1;
    while (i < n) {
        if (arr[i] > m) { m = arr[i]; }
        i = i + 1;
    }
    return m;
}

fn stat_range(int* arr, int n) -> int {
    if (n <= 0) { return 0; }
    return stat_max(arr, n) - stat_min(arr, n);
}

fn stat_variance(int* arr, int n) -> int {
    if (n <= 1) { return 0; }
    int avg = stat_mean(arr, n);
    int sum_sq = 0;
    int i = 0;
    while (i < n) {
        int diff = arr[i] - avg;
        sum_sq = sum_sq + diff * diff;
        i = i + 1;
    }
    return sum_sq / (n - 1);
}

fn stat_std_dev(int* arr, int n) -> int {
    return math_isqrt(stat_variance(arr, n));
}

fn stat_median(int* arr, int n) -> int {
    if (n <= 0) { return 0; }
    int* s_arr = alloc<int>(n);
    int i = 0;
    while (i < n) {
        s_arr[i] = arr[i];
        i = i + 1;
    }
    // Insertion sort
    i = 1;
    while (i < n) {
        int key = s_arr[i];
        int j = i - 1;
        while (j >= 0 && s_arr[j] > key) {
            s_arr[j + 1] = s_arr[j];
            j = j - 1;
        }
        s_arr[j + 1] = key;
        i = i + 1;
    }
    int med = 0;
    if (n - (n / 2) * 2 == 1) {
        med = s_arr[n / 2];
    } else {
        med = (s_arr[n / 2 - 1] + s_arr[n / 2]) / 2;
    }
    free(s_arr);
    return med;
}

fn stat_quantile(int* arr, int n, int percent) -> int {
    if (n <= 0) { return 0; }
    if (percent <= 0) { return stat_min(arr, n); }
    if (percent >= 100) { return stat_max(arr, n); }
    int* s_arr = alloc<int>(n);
    int i = 0;
    while (i < n) {
        s_arr[i] = arr[i];
        i = i + 1;
    }
    i = 1;
    while (i < n) {
        int key = s_arr[i];
        int j = i - 1;
        while (j >= 0 && s_arr[j] > key) {
            s_arr[j + 1] = s_arr[j];
            j = j - 1;
        }
        s_arr[j + 1] = key;
        i = i + 1;
    }
    int idx = (percent * (n - 1)) / 100;
    int val = s_arr[idx];
    free(s_arr);
    return val;
}

fn stat_iqr(int* arr, int n) -> int {
    return stat_quantile(arr, n, 75) - stat_quantile(arr, n, 25);
}

fn stat_covariance(int* x, int* y, int n) -> int {
    if (n <= 1) { return 0; }
    int mx = stat_mean(x, n);
    int my = stat_mean(y, n);
    int s = 0;
    int i = 0;
    while (i < n) {
        s = s + (x[i] - mx) * (y[i] - my);
        i = i + 1;
    }
    return s / (n - 1);
}

// Pearson Correlation Coefficient r * 100 (e.g. 95 = 0.95, -80 = -0.80)
fn stat_correlation(int* x, int* y, int n) -> int {
    int cov = stat_covariance(x, y, n);
    int sx = stat_std_dev(x, n);
    int sy = stat_std_dev(y, n);
    if (sx == 0 || sy == 0) { return 0; }
    return (cov * 100) / (sx * sy);
}

// Linear Regression: y = (m/1000)*x + b
fn stat_linear_regression(int* x, int* y, int n, int* out_m_x1000, int* out_b) -> void {
    if (n <= 1) {
        *out_m_x1000 = 0;
        *out_b = 0;
        return;
    }
    int mx = stat_mean(x, n);
    int my = stat_mean(y, n);
    int num = 0;
    int den = 0;
    int i = 0;
    while (i < n) {
        int dx = x[i] - mx;
        int dy = y[i] - my;
        num = num + dx * dy;
        den = den + dx * dx;
        i = i + 1;
    }
    if (den == 0) {
        *out_m_x1000 = 0;
        *out_b = my;
        return;
    }
    int m1000 = (num * 1000) / den;
    int b = my - (m1000 * mx) / 1000;
    *out_m_x1000 = m1000;
    *out_b = b;
}

// Automatic histogram binning
fn stat_histogram(int* data, int n, int num_bins, int* out_edges, int* out_counts) -> void {
    if (n <= 0 || num_bins <= 0) { return; }
    int min_val = stat_min(data, n);
    int max_val = stat_max(data, n);
    if (min_val == max_val) { max_val = min_val + num_bins; }

    int span = max_val - min_val;
    int i = 0;
    while (i <= num_bins) {
        out_edges[i] = min_val + (i * span) / num_bins;
        i = i + 1;
    }

    int b = 0;
    while (b < num_bins) {
        out_counts[b] = 0;
        b = b + 1;
    }

    i = 0;
    while (i < n) {
        int v = data[i];
        int bin_idx = ((v - min_val) * num_bins) / span;
        if (bin_idx >= num_bins) { bin_idx = num_bins - 1; }
        if (bin_idx < 0) { bin_idx = 0; }
        out_counts[bin_idx] = out_counts[bin_idx] + 1;
        i = i + 1;
    }
}

// ─── Plot Engine State & Buffers ─────────────────────────
static int G_PLT_FIG_W = 960;
static int G_PLT_FIG_H = 640;
static string G_PLT_FIG_TITLE = "Falcon Plot — Data Visualization";

// Theme: 0 = Dark (Scientific/Modern), 1 = Light (Matplotlib classic)
static int G_PLT_THEME = 0;
static int G_PLT_BG_COLOR   = 0x181825;
static int G_PLT_PANEL_BG   = 0x1E1E2E;
static int G_PLT_BORDER     = 0x45475A;
static int G_PLT_GRID_COLOR = 0x313244;
static int G_PLT_AXIS_COLOR = 0xBAC2DE;
static int G_PLT_TEXT_COLOR = 0xCDD6F4;

// Active Viewport / Subplot inside figure
static int G_PLT_VIEW_X = 80;
static int G_PLT_VIEW_Y = 60;
static int G_PLT_VIEW_W = 820;
static int G_PLT_VIEW_H = 500;

static int G_PLT_GRID_ON   = 1;
static int G_PLT_LEGEND_ON = 1;
static string G_PLT_TITLE  = "";
static string G_PLT_XLABEL = "";
static string G_PLT_YLABEL = "";

// Scaling limits
static int G_PLT_AUTOSCALE = 1;
static int G_PLT_X_MIN = 0;
static int G_PLT_X_MAX = 100;
static int G_PLT_Y_MIN = 0;
static int G_PLT_Y_MAX = 100;

// Maximum 16 series per plot
static const int G_PLT_MAX_SERIES = 16;
static int G_PLT_SERIES_COUNT = 0;

static int* G_PLT_S_TYPE = 0;
static int* G_PLT_S_COLOR = 0;
static string* G_PLT_S_LABEL = 0;
static int* G_PLT_S_N = 0;
static int* G_PLT_S_X = 0;
static int* G_PLT_S_Y = 0;
static int* G_PLT_S_STR = 0;
static int* G_PLT_S_PARAM = 0;

// Pie chart state
static int G_PLT_PIE_ACTIVE = 0;
static int* G_PLT_PIE_VALS = 0;
static string* G_PLT_PIE_LBLS = 0;
static int G_PLT_PIE_N = 0;
static string G_PLT_PIE_TITLE = "";

fn _plt_ensure_init() -> void {
    if (G_PLT_S_TYPE != 0) { return; }
    G_PLT_S_TYPE  = alloc<int>(16);
    G_PLT_S_COLOR = alloc<int>(16);
    G_PLT_S_LABEL = alloc<string>(16);
    G_PLT_S_N     = alloc<int>(16);
    G_PLT_S_X     = alloc<int>(16);
    G_PLT_S_Y     = alloc<int>(16);
    G_PLT_S_STR   = alloc<int>(16);
    G_PLT_S_PARAM = alloc<int>(16);
}

// ─── Theme Setup ─────────────────────────────────────────
fn plt_theme(int theme_id) -> void {
    G_PLT_THEME = theme_id;
    if (theme_id == 1) {
        // Light Theme
        G_PLT_BG_COLOR   = 0xF8F9FA;
        G_PLT_PANEL_BG   = 0xFFFFFF;
        G_PLT_BORDER     = 0xCED4DA;
        G_PLT_GRID_COLOR = 0xE9ECEF;
        G_PLT_AXIS_COLOR = 0x495057;
        G_PLT_TEXT_COLOR = 0x212529;
    } else {
        // Dark Theme (Default)
        G_PLT_BG_COLOR   = 0x181825;
        G_PLT_PANEL_BG   = 0x1E1E2E;
        G_PLT_BORDER     = 0x45475A;
        G_PLT_GRID_COLOR = 0x313244;
        G_PLT_AXIS_COLOR = 0xBAC2DE;
        G_PLT_TEXT_COLOR = 0xCDD6F4;
    }
}

// ─── Configuration API ───────────────────────────────────
fn plt_clf() -> void {
    _plt_ensure_init();
    int s = 0;
    while (s < G_PLT_SERIES_COUNT) {
        if (G_PLT_S_X[s] != 0) { free(cast<int*>(G_PLT_S_X[s])); G_PLT_S_X[s] = 0; }
        if (G_PLT_S_Y[s] != 0) { free(cast<int*>(G_PLT_S_Y[s])); G_PLT_S_Y[s] = 0; }
        if (G_PLT_S_TYPE[s] == PLT_TYPE_CANDLE) {
            if (G_PLT_S_STR[s] != 0) { free(cast<int*>(G_PLT_S_STR[s])); G_PLT_S_STR[s] = 0; }
            if (G_PLT_S_PARAM[s] != 0) { free(cast<int*>(G_PLT_S_PARAM[s])); G_PLT_S_PARAM[s] = 0; }
        } else {
            if (G_PLT_S_STR[s] != 0) { free(cast<string*>(G_PLT_S_STR[s])); G_PLT_S_STR[s] = 0; }
        }
        s = s + 1;
    }
    G_PLT_SERIES_COUNT = 0;
    G_PLT_PIE_ACTIVE = 0;
    G_PLT_TITLE = "";
    G_PLT_XLABEL = "";
    G_PLT_YLABEL = "";
    G_PLT_AUTOSCALE = 1;
    G_PLT_GRID_ON = 1;
    G_PLT_LEGEND_ON = 1;
}

fn plt_figure(int w, int h, string title) -> void {
    _plt_ensure_init();
    G_PLT_FIG_W = w;
    G_PLT_FIG_H = h;
    G_PLT_FIG_TITLE = title;
    G_PLT_VIEW_X = 80;
    G_PLT_VIEW_Y = 60;
    G_PLT_VIEW_W = w - 120;
    G_PLT_VIEW_H = h - 140;
    plt_clf();
}

fn plt_title(string title) -> void { G_PLT_TITLE = title; }
fn plt_xlabel(string xlabel) -> void { G_PLT_XLABEL = xlabel; }
fn plt_ylabel(string ylabel) -> void { G_PLT_YLABEL = ylabel; }
fn plt_grid(int enable) -> void { G_PLT_GRID_ON = enable; }
fn plt_legend(int enable) -> void { G_PLT_LEGEND_ON = enable; }

fn plt_xlim(int min_x, int max_x) -> void {
    G_PLT_AUTOSCALE = 0;
    G_PLT_X_MIN = min_x;
    G_PLT_X_MAX = max_x;
}

fn plt_ylim(int min_y, int max_y) -> void {
    G_PLT_AUTOSCALE = 0;
    G_PLT_Y_MIN = min_y;
    G_PLT_Y_MAX = max_y;
}

// Subplots: 1-based index (e.g. 1..4 in a 2x2 grid)
fn plt_subplot(int nrows, int ncols, int index) -> void {
    if (nrows <= 0 || ncols <= 0 || index <= 0) { return; }
    int idx0 = index - 1;
    int r = idx0 / ncols;
    int c = idx0 - r * ncols;

    int cell_w = G_PLT_FIG_W / ncols;
    int cell_h = G_PLT_FIG_H / nrows;

    int pad_l = 60;
    int pad_r = 30;
    int pad_t = 45;
    int pad_b = 45;

    G_PLT_VIEW_X = c * cell_w + pad_l;
    G_PLT_VIEW_Y = r * cell_h + pad_t;
    G_PLT_VIEW_W = cell_w - (pad_l + pad_r);
    G_PLT_VIEW_H = cell_h - (pad_t + pad_b);
}

// ─── Coordinate Mapping ───────────────────────────────────
fn _plt_map_x(int val) -> int {
    int span = G_PLT_X_MAX - G_PLT_X_MIN;
    if (span <= 0) { return G_PLT_VIEW_X + G_PLT_VIEW_W / 2; }
    return G_PLT_VIEW_X + ((val - G_PLT_X_MIN) * G_PLT_VIEW_W) / span;
}

fn _plt_map_y(int val) -> int {
    int span = G_PLT_Y_MAX - G_PLT_Y_MIN;
    if (span <= 0) { return G_PLT_VIEW_Y + G_PLT_VIEW_H / 2; }
    return G_PLT_VIEW_Y + G_PLT_VIEW_H - ((val - G_PLT_Y_MIN) * G_PLT_VIEW_H) / span;
}

fn _plt_draw_thick_line(int x0, int y0, int x1, int y1, int color, int width) -> void {
    if (width <= 1) {
        dsk_line(x0, y0, x1, y1, color);
        return;
    }
    int h_val = width / 2;
    int w = 0 - h_val;
    while (w <= h_val) {
        dsk_line(x0 + w, y0, x1 + w, y1, color);
        dsk_line(x0, y0 + w, x1, y1 + w, color);
        w = w + 1;
    }
}

// ─── Add Series to Plot (with safe persistent copying) ────
fn _plt_add_series(int stype, int* x, int* y, string* str_labels, int n, int color, string label, int param) -> void {
    _plt_ensure_init();
    if (G_PLT_SERIES_COUNT >= G_PLT_MAX_SERIES) { return; }
    int id = G_PLT_SERIES_COUNT;
    G_PLT_S_TYPE[id] = stype;
    G_PLT_S_N[id] = n;
    G_PLT_S_COLOR[id] = color;
    G_PLT_S_LABEL[id] = label;
    G_PLT_S_PARAM[id] = param;

    // Persist data buffers into heap
    if (x != 0 && n > 0) {
        int* cx = alloc<int>(n);
        int i = 0;
        while (i < n) { cx[i] = x[i]; i = i + 1; }
        G_PLT_S_X[id] = cast<int>(cx);
    } else {
        G_PLT_S_X[id] = 0;
    }

    if (y != 0 && n > 0) {
        int* cy = alloc<int>(n);
        int i = 0;
        while (i < n) { cy[i] = y[i]; i = i + 1; }
        G_PLT_S_Y[id] = cast<int>(cy);
    } else {
        G_PLT_S_Y[id] = 0;
    }

    if (str_labels != 0 && n > 0) {
        string* cs = alloc<string>(n);
        int i = 0;
        while (i < n) { cs[i] = str_labels[i]; i = i + 1; }
        G_PLT_S_STR[id] = cast<int>(cs);
    } else {
        G_PLT_S_STR[id] = 0;
    }

    G_PLT_SERIES_COUNT = G_PLT_SERIES_COUNT + 1;
}

fn plt_plot(int* x, int* y, int n, int color, string label) -> void {
    _plt_add_series(PLT_TYPE_LINE, x, y, 0, n, color, label, 3);
}

fn plt_curve(int* x, int* y, int n, int color, string label) -> void {
    _plt_add_series(PLT_TYPE_LINE, x, y, 0, n, color, label, 3);
}

fn plt_scatter(int* x, int* y, int n, int radius, int color, string label) -> void {
    _plt_add_series(PLT_TYPE_SCATTER, x, y, 0, n, color, label, radius);
}

fn plt_area(int* x, int* y, int n, int color, string label) -> void {
    _plt_add_series(PLT_TYPE_AREA, x, y, 0, n, color, label, 2);
}

fn plt_bar(string* labels, int* values, int n, int color, string label) -> void {
    _plt_add_series(PLT_TYPE_BAR, 0, values, labels, n, color, label, 0);
}

fn plt_barh(string* labels, int* values, int n, int color, string label) -> void {
    _plt_add_series(PLT_TYPE_BARH, 0, values, labels, n, color, label, 0);
}

fn plt_hist(int* data, int n, int num_bins, int color, string label) -> void {
    int* edges = alloc<int>(num_bins + 1);
    int* counts = alloc<int>(num_bins);
    stat_histogram(data, n, num_bins, edges, counts);
    _plt_add_series(PLT_TYPE_HIST, edges, counts, 0, num_bins, color, label, 0);
    free(edges);
    free(counts);
}

fn plt_regression(int* x, int* y, int n, int color, string label) -> void {
    _plt_add_series(PLT_TYPE_REGRESSION, x, y, 0, n, color, label, 3);
}

// Japanese Candlestick / Trading chart: Open, High, Low, Close
fn plt_candlestick(int* p_open, int* p_high, int* p_low, int* p_close, int n, string label) -> void {
    _plt_ensure_init();
    if (G_PLT_SERIES_COUNT >= G_PLT_MAX_SERIES || n <= 0) { return; }
    int id = G_PLT_SERIES_COUNT;
    G_PLT_S_TYPE[id] = PLT_TYPE_CANDLE;
    G_PLT_S_N[id] = n;
    G_PLT_S_COLOR[id] = PLT_MINT;
    G_PLT_S_LABEL[id] = label;

    int* ch = alloc<int>(n);
    int* cl = alloc<int>(n);
    int* co = alloc<int>(n);
    int* cc = alloc<int>(n);
    int i = 0;
    while (i < n) {
        ch[i] = p_high[i];
        cl[i] = p_low[i];
        co[i] = p_open[i];
        cc[i] = p_close[i];
        i = i + 1;
    }
    G_PLT_S_X[id] = cast<int>(ch);
    G_PLT_S_Y[id] = cast<int>(cl);
    G_PLT_S_STR[id] = cast<int>(co);
    G_PLT_S_PARAM[id] = cast<int>(cc);
    G_PLT_SERIES_COUNT = G_PLT_SERIES_COUNT + 1;
}

fn plt_pie(int* values, string* labels, int n, string title) -> void {
    G_PLT_PIE_ACTIVE = 1;
    G_PLT_PIE_VALS = values;
    G_PLT_PIE_LBLS = labels;
    G_PLT_PIE_N = n;
    G_PLT_PIE_TITLE = title;
}

// ─── Rendering Engine ────────────────────────────────────

fn _plt_auto_scale() -> void {
    if (G_PLT_AUTOSCALE == 0) { return; }
    if (G_PLT_SERIES_COUNT <= 0) { return; }

    int min_x = 999999999;
    int max_x = 0 - 999999999;
    int min_y = 999999999;
    int max_y = 0 - 999999999;

    int s = 0;
    while (s < G_PLT_SERIES_COUNT) {
        int stype = G_PLT_S_TYPE[s];
        int n = G_PLT_S_N[s];
        int* px = cast<int*>(G_PLT_S_X[s]);
        int* py = cast<int*>(G_PLT_S_Y[s]);

        if (stype == PLT_TYPE_BAR) {
            min_x = 0;
            max_x = n;
            int ym = stat_min(py, n);
            int yM = stat_max(py, n);
            if (ym < min_y) { min_y = ym; }
            if (yM > max_y) { max_y = yM; }
        } else if (stype == PLT_TYPE_HIST) {
            int xm = px[0];
            int xM = px[n];
            if (xm < min_x) { min_x = xm; }
            if (xM > max_x) { max_x = xM; }
            int ym = 0;
            int yM = stat_max(py, n);
            if (ym < min_y) { min_y = ym; }
            if (yM > max_y) { max_y = yM; }
        } else if (stype == PLT_TYPE_CANDLE) {
            min_x = 0;
            max_x = n + 1;
            int ym = stat_min(py, n); // low
            int yM = stat_max(px, n); // high
            if (ym < min_y) { min_y = ym; }
            if (yM > max_y) { max_y = yM; }
        } else if (px != 0 && py != 0) {
            int xm = stat_min(px, n);
            int xM = stat_max(px, n);
            int ym = stat_min(py, n);
            int yM = stat_max(py, n);
            if (xm < min_x) { min_x = xm; }
            if (xM > max_x) { max_x = xM; }
            if (ym < min_y) { min_y = ym; }
            if (yM > max_y) { max_y = yM; }
        }
        s = s + 1;
    }

    if (min_x == max_x) { max_x = min_x + 10; }
    if (min_y == max_y) { max_y = min_y + 10; }

    // Add 8% margin headroom
    int span_x = max_x - min_x;
    int span_y = max_y - min_y;
    int pad_x = span_x / 12;
    if (pad_x < 1) { pad_x = 1; }
    int pad_y = span_y / 12;
    if (pad_y < 1) { pad_y = 1; }

    G_PLT_X_MIN = min_x - pad_x;
    G_PLT_X_MAX = max_x + pad_x;
    G_PLT_Y_MIN = min_y - pad_y;
    if (min_y >= 0 && G_PLT_Y_MIN < 0) { G_PLT_Y_MIN = 0; }
    G_PLT_Y_MAX = max_y + pad_y;
}

fn _plt_render_axes() -> void {
    // 1. Draw Plot Area Box
    gui_fill_rounded_rect(G_PLT_VIEW_X, G_PLT_VIEW_Y, G_PLT_VIEW_W, G_PLT_VIEW_H, 4, G_PLT_PANEL_BG);
    gui_draw_rounded_rect(G_PLT_VIEW_X, G_PLT_VIEW_Y, G_PLT_VIEW_W, G_PLT_VIEW_H, 4, G_PLT_BORDER);

    // 2. Grid lines & Axis Ticks
    int num_ticks = 5;

    // Y-Axis Ticks & Horizontal Grid Lines
    int t = 0;
    while (t <= num_ticks) {
        int y_val = G_PLT_Y_MIN + (t * (G_PLT_Y_MAX - G_PLT_Y_MIN)) / num_ticks;
        int sy = _plt_map_y(y_val);

        if (G_PLT_GRID_ON == 1 && t > 0 && t < num_ticks) {
            dsk_hline(G_PLT_VIEW_X + 1, sy, G_PLT_VIEW_W - 2, G_PLT_GRID_COLOR);
        }

        // Tick mark
        dsk_hline(G_PLT_VIEW_X - 5, sy, 5, G_PLT_AXIS_COLOR);

        // Tick Label
        string lbl = dsk_itoa(y_val);
        int tw = gui_text_width(lbl, 1);
        gui_draw_text(G_PLT_VIEW_X - tw - 9, sy - 7, lbl, G_PLT_TEXT_COLOR, G_PLT_BG_COLOR, 1);

        t = t + 1;
    }

    // X-Axis Ticks & Vertical Grid Lines
    t = 0;
    while (t <= num_ticks) {
        int x_val = G_PLT_X_MIN + (t * (G_PLT_X_MAX - G_PLT_X_MIN)) / num_ticks;
        int sx = _plt_map_x(x_val);

        if (G_PLT_GRID_ON == 1 && t > 0 && t < num_ticks) {
            dsk_vline(sx, G_PLT_VIEW_Y + 1, G_PLT_VIEW_H - 2, G_PLT_GRID_COLOR);
        }

        // Tick mark
        dsk_vline(sx, G_PLT_VIEW_Y + G_PLT_VIEW_H, 5, G_PLT_AXIS_COLOR);

        // Tick Label
        string lbl = dsk_itoa(x_val);
        int tw = gui_text_width(lbl, 1);
        gui_draw_text(sx - tw / 2, G_PLT_VIEW_Y + G_PLT_VIEW_H + 9, lbl, G_PLT_TEXT_COLOR, G_PLT_BG_COLOR, 1);

        t = t + 1;
    }

    // 3. Titles & Labels
    if (_str_len(G_PLT_TITLE) > 0) {
        int tw = gui_text_width(G_PLT_TITLE, 1);
        gui_draw_text(G_PLT_VIEW_X + (G_PLT_VIEW_W - tw) / 2, G_PLT_VIEW_Y - 28, G_PLT_TITLE, G_PLT_TEXT_COLOR, G_PLT_BG_COLOR, 1);
    }
    if (_str_len(G_PLT_XLABEL) > 0) {
        int tw = gui_text_width(G_PLT_XLABEL, 1);
        gui_draw_text(G_PLT_VIEW_X + (G_PLT_VIEW_W - tw) / 2, G_PLT_VIEW_Y + G_PLT_VIEW_H + 30, G_PLT_XLABEL, G_PLT_TEXT_COLOR, G_PLT_BG_COLOR, 1);
    }
    if (_str_len(G_PLT_YLABEL) > 0) {
        gui_draw_text(G_PLT_VIEW_X - 10, G_PLT_VIEW_Y - 24, G_PLT_YLABEL, G_PLT_TEXT_COLOR, G_PLT_BG_COLOR, 1);
    }
}

fn _plt_render_series(int s) -> void {
    int stype = G_PLT_S_TYPE[s];
    int n = G_PLT_S_N[s];
    int* px = cast<int*>(G_PLT_S_X[s]);
    int* py = cast<int*>(G_PLT_S_Y[s]);
    string* pstr = cast<string*>(G_PLT_S_STR[s]);
    int color = G_PLT_S_COLOR[s];
    int param = G_PLT_S_PARAM[s];

    if (stype == PLT_TYPE_LINE) {
        int i = 0;
        while (i < n - 1) {
            int sx0 = _plt_map_x(px[i]);
            int sy0 = _plt_map_y(py[i]);
            int sx1 = _plt_map_x(px[i + 1]);
            int sy1 = _plt_map_y(py[i + 1]);
            _plt_draw_thick_line(sx0, sy0, sx1, sy1, color, param);
            gui_fill_circle(sx0, sy0, 4, color);
            gui_fill_circle(sx0, sy0, 2, PLT_WHITE);
            i = i + 1;
        }
        if (n > 0) {
            int sx = _plt_map_x(px[n - 1]);
            int sy = _plt_map_y(py[n - 1]);
            gui_fill_circle(sx, sy, 4, color);
            gui_fill_circle(sx, sy, 2, PLT_WHITE);
        }
    }
    else if (stype == PLT_TYPE_AREA) {
        int base_y = _plt_map_y(0);
        if (base_y > G_PLT_VIEW_Y + G_PLT_VIEW_H) { base_y = G_PLT_VIEW_Y + G_PLT_VIEW_H; }
        int i = 0;
        while (i < n - 1) {
            int sx0 = _plt_map_x(px[i]);
            int sy0 = _plt_map_y(py[i]);
            int sx1 = _plt_map_x(px[i + 1]);
            int sy1 = _plt_map_y(py[i + 1]);
            // Draw filled vertical column
            int cx = sx0;
            while (cx <= sx1) {
                int interp_y = sy0;
                if (sx1 != sx0) {
                    interp_y = sy0 + ((sy1 - sy0) * (cx - sx0)) / (sx1 - sx0);
                }
                dsk_vline(cx, interp_y, base_y - interp_y, color - 0x101010);
                cx = cx + 1;
            }
            _plt_draw_thick_line(sx0, sy0, sx1, sy1, color, 2);
            i = i + 1;
        }
    }
    else if (stype == PLT_TYPE_SCATTER) {
        int rad = param;
        if (rad < 3) { rad = 5; }
        int i = 0;
        while (i < n) {
            int sx = _plt_map_x(px[i]);
            int sy = _plt_map_y(py[i]);
            gui_fill_circle(sx, sy, rad, color);
            gui_fill_circle(sx, sy, rad - 2, PLT_WHITE);
            i = i + 1;
        }
    }
    else if (stype == PLT_TYPE_BAR) {
        int base_y = _plt_map_y(0);
        if (base_y > G_PLT_VIEW_Y + G_PLT_VIEW_H) { base_y = G_PLT_VIEW_Y + G_PLT_VIEW_H; }
        int bar_step = G_PLT_VIEW_W / n;
        int bar_w = (bar_step * 7) / 10;
        if (bar_w < 6) { bar_w = 6; }

        int i = 0;
        while (i < n) {
            int bx = G_PLT_VIEW_X + i * bar_step + (bar_step - bar_w) / 2;
            int by = _plt_map_y(py[i]);
            int bh = base_y - by;
            if (bh > 0) {
                gui_fill_rounded_rect(bx, by, bar_w, bh, 3, color);
                gui_draw_rounded_rect(bx, by, bar_w, bh, 3, color - 0x151515);
            }

            // Print bar top value
            string val_s = dsk_itoa(py[i]);
            int vw = gui_text_width(val_s, 1);
            gui_draw_text(bx + (bar_w - vw) / 2, by - 16, val_s, G_PLT_TEXT_COLOR, G_PLT_PANEL_BG, 1);

            // Print category label
            if (pstr != 0) {
                string cat = pstr[i];
                int cw = gui_text_width(cat, 1);
                gui_draw_text(bx + (bar_w - cw) / 2, G_PLT_VIEW_Y + G_PLT_VIEW_H + 9, cat, G_PLT_TEXT_COLOR, G_PLT_BG_COLOR, 1);
            }
            i = i + 1;
        }
    }
    else if (stype == PLT_TYPE_HIST) {
        int base_y = _plt_map_y(0);
        if (base_y > G_PLT_VIEW_Y + G_PLT_VIEW_H) { base_y = G_PLT_VIEW_Y + G_PLT_VIEW_H; }
        int i = 0;
        while (i < n) {
            int bx0 = _plt_map_x(px[i]);
            int bx1 = _plt_map_x(px[i + 1]);
            int bw = bx1 - bx0;
            if (bw < 2) { bw = 2; }
            int by = _plt_map_y(py[i]);
            int bh = base_y - by;
            if (bh > 0) {
                gui_fill_rect(bx0, by, bw, bh, color);
                gui_draw_rect(bx0, by, bw, bh, G_PLT_PANEL_BG);
            }
            i = i + 1;
        }
    }
    else if (stype == PLT_TYPE_REGRESSION) {
        int m1000 = 0;
        int b = 0;
        stat_linear_regression(px, py, n, &m1000, &b);
        int sx0 = _plt_map_x(G_PLT_X_MIN);
        int sy0 = _plt_map_y((m1000 * G_PLT_X_MIN) / 1000 + b);
        int sx1 = _plt_map_x(G_PLT_X_MAX);
        int sy1 = _plt_map_y((m1000 * G_PLT_X_MAX) / 1000 + b);
        _plt_draw_thick_line(sx0, sy0, sx1, sy1, color, 3);
    }
    else if (stype == PLT_TYPE_CANDLE) {
        int* p_high  = cast<int*>(G_PLT_S_X[s]);
        int* p_low   = cast<int*>(G_PLT_S_Y[s]);
        int* p_open  = cast<int*>(G_PLT_S_STR[s]);
        int* p_close = cast<int*>(G_PLT_S_PARAM[s]);

        int step = G_PLT_VIEW_W / (n + 1);
        int cw = (step * 7) / 10;
        if (cw < 4) { cw = 4; }

        int i = 0;
        while (i < n) {
            int cx = G_PLT_VIEW_X + (i + 1) * step;
            int y_high = _plt_map_y(p_high[i]);
            int y_low  = _plt_map_y(p_low[i]);
            int y_open = _plt_map_y(p_open[i]);
            int y_close= _plt_map_y(p_close[i]);

            int candle_col = PLT_MINT; // Bullish
            int top_body = y_close;
            int bot_body = y_open;
            if (p_close[i] < p_open[i]) {
                candle_col = PLT_RED; // Bearish
                top_body = y_open;
                bot_body = y_close;
            }

            int bh = bot_body - top_body;
            if (bh < 2) { bh = 2; }

            // Wick line
            dsk_vline(cx, y_high, y_low - y_high, candle_col);

            // Candle Body
            gui_fill_rect(cx - cw / 2, top_body, cw, bh, candle_col);
            gui_draw_rect(cx - cw / 2, top_body, cw, bh, PLT_WHITE);

            i = i + 1;
        }
    }
}

fn _plt_render_legend() -> void {
    if (G_PLT_LEGEND_ON == 0 || G_PLT_SERIES_COUNT <= 0) { return; }

    int max_len = 0;
    int valid_series = 0;
    int s = 0;
    while (s < G_PLT_SERIES_COUNT) {
        if (_str_len(G_PLT_S_LABEL[s]) > 0) {
            valid_series = valid_series + 1;
            int l = _str_len(G_PLT_S_LABEL[s]);
            if (l > max_len) { max_len = l; }
        }
        s = s + 1;
    }
    if (valid_series == 0) { return; }

    int box_w = max_len * 8 + 48;
    int box_h = valid_series * 20 + 12;
    int box_x = G_PLT_VIEW_X + G_PLT_VIEW_W - box_w - 12;
    int box_y = G_PLT_VIEW_Y + 12;

    dsk_shadow(box_x, box_y, box_w, box_h);
    gui_fill_rounded_rect(box_x, box_y, box_w, box_h, 4, G_PLT_BG_COLOR);
    gui_draw_rounded_rect(box_x, box_y, box_w, box_h, 4, G_PLT_BORDER);

    int row = 0;
    s = 0;
    while (s < G_PLT_SERIES_COUNT) {
        if (_str_len(G_PLT_S_LABEL[s]) > 0) {
            int ry = box_y + 8 + row * 20;
            gui_fill_rounded_rect(box_x + 8, ry + 2, 16, 10, 2, G_PLT_S_COLOR[s]);
            gui_draw_text(box_x + 30, ry, G_PLT_S_LABEL[s], G_PLT_TEXT_COLOR, G_PLT_BG_COLOR, 1);
            row = row + 1;
        }
        s = s + 1;
    }
}

// ─── Pie Chart Renderer ──────────────────────────────────
fn _plt_render_pie_chart() -> void {
    if (G_PLT_PIE_ACTIVE == 0 || G_PLT_PIE_N <= 0) { return; }

    gui_clear(G_PLT_BG_COLOR);

    int cx = G_PLT_FIG_W / 3;
    int cy = G_PLT_FIG_H / 2;
    int radius = cy - 60;
    if (radius > 180) { radius = 180; }

    int pal[8] = {PLT_BLUE, PLT_ORANGE, PLT_GREEN, PLT_RED, PLT_PURPLE, PLT_CYAN, PLT_OLIVE, PLT_PINK};

    int total = stat_sum(G_PLT_PIE_VALS, G_PLT_PIE_N);
    if (total <= 0) { total = 1; }

    int angles[9];
    angles[0] = 0;
    int i = 0;
    int acc = 0;
    while (i < G_PLT_PIE_N) {
        acc = acc + G_PLT_PIE_VALS[i];
        angles[i + 1] = (acc * 360) / total;
        i = i + 1;
    }
    angles[G_PLT_PIE_N] = 360;

    int r2 = radius * radius;
    int dy = 0 - radius;
    while (dy <= radius) {
        int dx = 0 - radius;
        while (dx <= radius) {
            int d2 = dx * dx + dy * dy;
            if (d2 <= r2) {
                int deg = math_atan2_deg(dy, dx);
                int s = 0;
                while (s < G_PLT_PIE_N) {
                    if (deg >= angles[s] && deg < angles[s + 1]) {
                        int col = pal[s - (s / 8) * 8];
                        gui_put_pixel(cx + dx, cy + dy, col);
                    }
                    s = s + 1;
                }
            }
            dx = dx + 1;
        }
        dy = dy + 1;
    }

    if (_str_len(G_PLT_PIE_TITLE) > 0) {
        int tw = gui_text_width(G_PLT_PIE_TITLE, 1);
        gui_draw_text((G_PLT_FIG_W - tw) / 2, 24, G_PLT_PIE_TITLE, G_PLT_TEXT_COLOR, G_PLT_BG_COLOR, 1);
    }

    int leg_x = G_PLT_FIG_W / 2 + 50;
    int leg_y = cy - (G_PLT_PIE_N * 28) / 2;

    i = 0;
    while (i < G_PLT_PIE_N) {
        int ry = leg_y + i * 28;
        int col = pal[i - (i / 8) * 8];
        gui_fill_rounded_rect(leg_x, ry + 2, 18, 14, 3, col);

        string lbl = G_PLT_PIE_LBLS[i];
        int pct = (G_PLT_PIE_VALS[i] * 100) / total;

        gui_draw_text(leg_x + 28, ry + 2, lbl, G_PLT_TEXT_COLOR, G_PLT_BG_COLOR, 1);

        string pct_s = dsk_itoa(pct);
        gui_draw_text(leg_x + 180, ry + 2, pct_s, G_PLT_TEXT_COLOR, G_PLT_BG_COLOR, 1);
        gui_draw_text(leg_x + 180 + gui_text_width(pct_s, 1), ry + 2, "%", G_PLT_TEXT_COLOR, G_PLT_BG_COLOR, 1);

        i = i + 1;
    }
}

// ─── Main Draw Function ──────────────────────────────────
fn plt_render() -> void {
    if (G_PLT_PIE_ACTIVE == 1) {
        _plt_render_pie_chart();
        return;
    }

    gui_clear(G_PLT_BG_COLOR);
    _plt_auto_scale();
    _plt_render_axes();

    int s = 0;
    while (s < G_PLT_SERIES_COUNT) {
        _plt_render_series(s);
        s = s + 1;
    }

    _plt_render_legend();
}

// ─── Interactive Plot Window (60 FPS with Tooltips) ──────
fn plt_show() -> void {
    int err = dsk_init_window(G_PLT_FIG_W, G_PLT_FIG_H, G_PLT_FIG_TITLE);
    if (err != 0) {
        print_str("Failed to initialize graphical window
");
        return;
    }

    while (dsk_running() == 1) {
        dsk_update();

        if (gui_close_requested() == 1) {
            dsk_stop();
        }

        plt_render();

        // Interactive mouse hover tooltip for scatter/line points
        int mx = gui_mouse_x();
        int my = gui_mouse_y();

        if (G_PLT_PIE_ACTIVE == 0) {
            int s = 0;
            int hovered = 0;
            while (s < G_PLT_SERIES_COUNT && hovered == 0) {
                int stype = G_PLT_S_TYPE[s];
                int n = G_PLT_S_N[s];
                int* px = cast<int*>(G_PLT_S_X[s]);
                int* py = cast<int*>(G_PLT_S_Y[s]);

                if ((stype == PLT_TYPE_LINE || stype == PLT_TYPE_SCATTER) && px != 0 && py != 0) {
                    int i = 0;
                    while (i < n && hovered == 0) {
                        int sx = _plt_map_x(px[i]);
                        int sy = _plt_map_y(py[i]);
                        int dist_x = mx - sx;
                        if (dist_x < 0) { dist_x = 0 - dist_x; }
                        int dist_y = my - sy;
                        if (dist_y < 0) { dist_y = 0 - dist_y; }

                        if (dist_x <= 10 && dist_y <= 10) {
                            string sx_str = dsk_itoa(px[i]);
                            string sy_str = dsk_itoa(py[i]);
                            int tw = gui_text_width(sx_str, 1) + gui_text_width(sy_str, 1) + 40;
                            int tip_x = sx + 12;
                            if (tip_x + tw > G_PLT_FIG_W - 10) { tip_x = sx - tw - 12; }
                            int tip_y = sy - 24;
                            if (tip_y < 10) { tip_y = sy + 16; }

                            dsk_shadow(tip_x, tip_y, tw, 24);
                            gui_fill_rounded_rect(tip_x, tip_y, tw, 24, 4, 0x11111B);
                            gui_draw_rounded_rect(tip_x, tip_y, tw, 24, 4, PLT_BLUE);

                            gui_draw_text(tip_x + 8, tip_y + 4, sx_str, PLT_TEXT_DARK, 0x11111B, 1);
                            gui_draw_text(tip_x + 8 + gui_text_width(sx_str, 1), tip_y + 4, ", ", PLT_TEXT_DARK, 0x11111B, 1);
                            gui_draw_text(tip_x + 22 + gui_text_width(sx_str, 1), tip_y + 4, sy_str, PLT_MINT, 0x11111B, 1);

                            hovered = 1;
                        }
                        i = i + 1;
                    }
                }
                s = s + 1;
            }
        }

        gui_present();
        sleep_ms(16); // 60 FPS
    }

    dsk_shutdown();
}
