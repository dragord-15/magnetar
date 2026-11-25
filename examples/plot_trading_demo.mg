// plot_trading_demo.mg — Candlestick Trading Chart example in Falcon
use "plot.mg";

extern fn print_str(string s) -> void;
extern fn print_int(int n) -> void;

fn main() -> int {
    print_str("Creating Falcon Candlestick Trading Chart...\n");

    // Daily trading session prices (e.g. BTC/USD or Stocks)
    int open_p[8]  = {100, 105, 102, 110, 108, 115, 122, 118};
    int high_p[8]  = {108, 112, 106, 115, 116, 124, 125, 126};
    int low_p[8]   = {98,  101,  99, 107, 104, 112, 117, 115};
    int close_p[8] = {105, 102, 105, 108, 115, 122, 118, 125};

    print_str("=== Trading Session Summary ===\n");
    print_str("Starting Price: "); print_int(open_p[0]);  print_str(" $\n");
    print_str("Current Price:  "); print_int(close_p[7]); print_str(" $\n");
    print_str("Session High:   "); print_int(stat_max(high_p, 8)); print_str(" $\n");
    print_str("Session Low:    "); print_int(stat_min(low_p, 8));  print_str(" $\n");

    // Setup Figure
    plt_figure(960, 640, "Falcon Plot — Trading & Financial Charts");
    plt_title("BTC/USD Daily Candlestick Chart (Bullish 🟢 / Bearish 🔴)");
    plt_xlabel("Session Periods (Days)");
    plt_ylabel("Price (USD)");
    plt_grid(1);

    // Add Japanese Candlesticks
    plt_candlestick(open_p, high_p, low_p, close_p, 8, "Trading Candles");

    // Show Window (60 FPS)
    plt_show();

    return 0;
}
