// plot_demo.mg — Showcase matplotlib-style charts in Magnetar
use "plot.mg";

extern fn print_str(string s) -> void;
extern fn print_int(int n) -> void;

fn main() -> int {
    print_str("Starting Falcon Matplotlib-style Charting Engine...
");

    // 1. Setup Data for Line & Scatter Plot
    int x[10] = {1,  2,  3,  4,  5,  6,  7,  8,  9, 10};
    int y1[10] = {12, 18, 29, 35, 42, 58, 65, 78, 88, 95};
    int y2[10] = {8,  14, 20, 24, 30, 40, 48, 55, 62, 70};

    // Calculate Statistics using stat_* module
    print_str("=== Statistical Summary for Series 1 ===
");
    print_str("Mean:     "); print_int(stat_mean(y1, 10));    print_str("
");
    print_str("Median:   "); print_int(stat_median(y1, 10));  print_str("
");
    print_str("Min:      "); print_int(stat_min(y1, 10));     print_str("
");
    print_str("Max:      "); print_int(stat_max(y1, 10));     print_str("
");
    print_str("Std Dev:  "); print_int(stat_std_dev(y1, 10)); print_str("
");
    print_str("Variance: "); print_int(stat_variance(y1, 10));print_str("
");
    print_str("Corr(y1, y2): "); print_int(stat_correlation(y1, y2, 10)); print_str("%
");

    // 2. Setup Figure
    plt_figure(980, 640, "Falcon Plot — Scientific & Statistical Visualization");
    plt_title("Monthly Growth & Regression Analysis");
    plt_xlabel("Timeline (Months)");
    plt_ylabel("Output Performance (Units)");
    plt_grid(1);
    plt_legend(1);

    // 3. Add Series
    plt_plot(x, y1, 10, PLT_BLUE, "Actual Growth");
    plt_scatter(x, y1, 10, 5, PLT_CYAN, "Measurements");
    plt_plot(x, y2, 10, PLT_ORANGE, "Baseline Target");
    plt_regression(x, y1, 10, PLT_GREEN, "Best-fit Trendline");

    // 4. Show Interactive Window (60 FPS with hover tooltips)
    plt_show();

    return 0;
}
