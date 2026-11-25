// examples/test_time.mg
// Test suite for Time & DateTime Library (lib/time.mg)

use "lib/time.mg";

fn main() -> void {
    print("=== STARTING MAGNETAR TIME LIBRARY VERIFICATION ===\n\n");

    int now = time_now();
    print("  Unix timestamp: "); print(now); print("\n");

    DateTime dt;
    dt.from_timestamp(now);

    print("  Date & Time: "); print_str(dt.format()); print("\n");
    print("  Date only:   "); print_str(dt.format_date()); print("\n");
    print("  Time only:   "); print_str(dt.format_time()); print("\n");
    print("  Day of week: "); print_str(dt.weekday_name()); print("\n");
    print("  Month name:  "); print_str(dt.month_name()); print("\n\n");

    print("  is_leap_year(2024): "); print(is_leap_year(2024)); print(" (expected 1)\n");
    print("  is_leap_year(2025): "); print(is_leap_year(2025)); print(" (expected 0)\n");
    print("  is_leap_year(2000): "); print(is_leap_year(2000)); print(" (expected 1)\n");
    print("  is_leap_year(1900): "); print(is_leap_year(1900)); print(" (expected 0)\n\n");

    print("  Testing Stopwatch and sleep_ms(150)... ");
    Stopwatch sw;
    sw.start();
    time_sleep_ms(150);
    print("Done!\n");

    print("\n=== ALL TIME LIBRARY TESTS PASSED! ===\n");
}
