// plot_hist_demo.mg — Histogram and Frequency Distribution example in Falcon
use "plot.mg";

extern fn print_str(string s) -> void;
extern fn print_int(int n) -> void;

fn main() -> int {
    print_str("Creating Falcon Frequency Histogram...\n");

    // 1. Raw Distribution Data (e.g. test scores or latency in ms)
    int latencies[24] = {
        12, 15, 14, 18, 19, 22, 25, 27, 24, 29, 31, 35,
        28, 32, 33, 40, 42, 45, 48, 55, 60, 68, 75, 82
    };

    // Statistical profile
    print_str("=== Network Latency Profile ===\n");
    print_str("Sample Size: "); print_int(24); print_str("\n");
    print_str("Median Latency: "); print_int(stat_median(latencies, 24)); print_str(" ms\n");
    print_str("Mean Latency:   "); print_int(stat_mean(latencies, 24));   print_str(" ms\n");
    print_str("Std Deviation:  "); print_int(stat_std_dev(latencies, 24));print_str(" ms\n");
    print_str("IQR:            "); print_int(stat_iqr(latencies, 24));    print_str(" ms\n");

    // 2. Setup Figure
    plt_figure(920, 600, "Falcon Plot — Latency Histogram");
    plt_title("System Request Latency Distribution (Histogram)");
    plt_xlabel("Latency Range (Milliseconds)");
    plt_ylabel("Frequency Count (Requests)");
    plt_grid(1);

    // 3. Add Histogram with 6 Bins
    plt_hist(latencies, 24, 6, PLT_PURPLE, "Latency Frequencies");

    // 4. Show Window
    plt_show();

    return 0;
}
