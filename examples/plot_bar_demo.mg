// plot_bar_demo.mg — Bar chart example in Falcon Matplotlib
use "plot.mg";

extern fn print_str(string s) -> void;
extern fn print_int(int n) -> void;

fn main() -> int {
    print_str("Creating Falcon Bar Chart...\n");

    // 1. Data
    string quarters[4] = {"Q1-Winter", "Q2-Spring", "Q3-Summer", "Q4-Autumn"};
    int sales[4] = {450, 720, 890, 610};

    // 2. Statistical calculation
    print_str("Total Sales:   "); print_int(stat_sum(sales, 4));  print_str("k $\n");
    print_str("Average Sales: "); print_int(stat_mean(sales, 4)); print_str("k $\n");
    print_str("Peak Sales:    "); print_int(stat_max(sales, 4));  print_str("k $\n");

    // 3. Setup Plot
    plt_figure(900, 600, "Falcon Plot — Quarterly Sales Revenue");
    plt_title("2026 Fiscal Performance by Quarter");
    plt_ylabel("Revenue (in Thousands USD)");
    plt_grid(1);

    // 4. Add Bar Chart
    plt_bar(quarters, sales, 4, PLT_BLUE, "Quarterly Revenue");

    // 5. Show Window
    plt_show();

    return 0;
}
