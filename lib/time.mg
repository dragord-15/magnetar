// ============================================================================
// Magnetar Standard Library: Time & DateTime (lib/time.mg)
// Timestamps, Formatting, Calendar Calculations, and Sleep Timers
// ============================================================================

use "lib/string.mg";

extern fn get_timestamp() -> int;
extern fn sleep_ms(int ms) -> void;
extern fn print_str(string s) -> void;

// -------------------------------------------------------------
// 1. Basic Time Functions
// -------------------------------------------------------------

// Returns current Unix timestamp in seconds (since Jan 1, 1970 UTC)
fn time_now() -> int {
    return get_timestamp();
}

// Sleep execution for specified milliseconds
fn time_sleep_ms(int ms) -> void {
    if (ms > 0) {
        sleep_ms(ms);
    }
}

// Sleep execution for specified seconds
fn time_sleep(int seconds) -> void {
    if (seconds > 0) {
        sleep_ms(seconds * 1000);
    }
}

// Check if a year is a leap year
fn is_leap_year(int year) -> bool {
    if ((year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)) {
        return true;
    }
    return false;
}

// Number of days in a given month (1 = Jan, ..., 12 = Dec)
fn days_in_month(int year, int month) -> int {
    if (month == 2) {
        if (is_leap_year(year)) {
            return 29;
        }
        return 28;
    }
    if (month == 4 || month == 6 || month == 9 || month == 11) {
        return 30;
    }
    return 31;
}

// -------------------------------------------------------------
// 2. DateTime Structure
// -------------------------------------------------------------

struct DateTime {
    int year;
    int month;
    int day;
    int hour;
    int minute;
    int second;
    int weekday; // 0=Sunday, 1=Monday, 2=Tuesday, 3=Wednesday, 4=Thursday, 5=Friday, 6=Saturday

    fn from_timestamp(int ts) -> void {
        int rem = ts;
        second = rem % 60;
        rem = rem / 60;
        minute = rem % 60;
        rem = rem / 60;
        hour = rem % 24;
        int total_days = rem / 24;

        // Jan 1 1970 was Thursday (index 4)
        weekday = (total_days + 4) % 7;

        int y = 1970;
        while (true) {
            int d_year = 365;
            if (is_leap_year(y)) {
                d_year = 366;
            }
            if (total_days < d_year) {
                break;
            }
            total_days = total_days - d_year;
            y = y + 1;
        }
        year = y;

        int m = 1;
        while (m <= 12) {
            int d_month = days_in_month(year, m);
            if (total_days < d_month) {
                break;
            }
            total_days = total_days - d_month;
            m = m + 1;
        }
        month = m;
        day = total_days + 1;
    }

    fn now() -> void {
        from_timestamp(time_now());
    }

    fn format() -> string {
        string s_y = int_to_str(year);
        string s_m = str_pad_left(int_to_str(month), 2, '0');
        string s_d = str_pad_left(int_to_str(day), 2, '0');
        string s_h = str_pad_left(int_to_str(hour), 2, '0');
        string s_min = str_pad_left(int_to_str(minute), 2, '0');
        string s_sec = str_pad_left(int_to_str(second), 2, '0');

        string date_part = str_concat(s_y, "-");
        date_part = str_concat(date_part, s_m);
        date_part = str_concat(date_part, "-");
        date_part = str_concat(date_part, s_d);

        string time_part = str_concat(s_h, ":");
        time_part = str_concat(time_part, s_min);
        time_part = str_concat(time_part, ":");
        time_part = str_concat(time_part, s_sec);

        string res = str_concat(date_part, " ");
        res = str_concat(res, time_part);
        return res;
    }

    fn format_date() -> string {
        string s_y = int_to_str(year);
        string s_m = str_pad_left(int_to_str(month), 2, '0');
        string s_d = str_pad_left(int_to_str(day), 2, '0');
        string res = str_concat(s_y, "-");
        res = str_concat(res, s_m);
        res = str_concat(res, "-");
        res = str_concat(res, s_d);
        return res;
    }

    fn format_time() -> string {
        string s_h = str_pad_left(int_to_str(hour), 2, '0');
        string s_min = str_pad_left(int_to_str(minute), 2, '0');
        string s_sec = str_pad_left(int_to_str(second), 2, '0');
        string res = str_concat(s_h, ":");
        res = str_concat(res, s_min);
        res = str_concat(res, ":");
        res = str_concat(res, s_sec);
        return res;
    }

    fn weekday_name() -> string {
        if (weekday == 0) { return "Sunday"; }
        if (weekday == 1) { return "Monday"; }
        if (weekday == 2) { return "Tuesday"; }
        if (weekday == 3) { return "Wednesday"; }
        if (weekday == 4) { return "Thursday"; }
        if (weekday == 5) { return "Friday"; }
        return "Saturday";
    }

    fn month_name() -> string {
        if (month == 1)  { return "January"; }
        if (month == 2)  { return "February"; }
        if (month == 3)  { return "March"; }
        if (month == 4)  { return "April"; }
        if (month == 5)  { return "May"; }
        if (month == 6)  { return "June"; }
        if (month == 7)  { return "July"; }
        if (month == 8)  { return "August"; }
        if (month == 9)  { return "September"; }
        if (month == 10) { return "October"; }
        if (month == 11) { return "November"; }
        return "December";
    }
};

// -------------------------------------------------------------
// 3. Stopwatch / Benchmark Timer
// -------------------------------------------------------------

struct Stopwatch {
    int start_time;

    fn start() -> void {
        start_time = time_now();
    }

    fn elapsed_sec() -> int {
        return time_now() - start_time;
    }
};
