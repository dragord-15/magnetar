// plot_pie_demo.mg — Pie chart with percentages and legend in Falcon
use "plot.mg";

extern fn print_str(string s) -> void;

fn main() -> int {
    print_str("Creating Falcon Pie Chart...\n");

    // 1. Data
    string browsers[5] = {"Chrome", "Safari", "Firefox", "Edge", "Falcon"};
    int shares[5] = {62, 18, 8, 5, 7};

    // 2. Setup Figure
    plt_figure(920, 600, "Falcon Plot — Global Market Share");

    // 3. Render Pie Chart
    plt_pie(shares, browsers, 5, "Global Desktop Web Browser Share (%)");

    // 4. Show Window
    plt_show();

    return 0;
}
