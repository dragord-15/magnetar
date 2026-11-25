// sysmon/rtc.mg - SysMon Real-Time Clock (CMOS clock, hardware-direct, heap-free, no bitwise ops)
//
// Reads the battery-backed RTC/MC146818 CMOS clock directly from the
// 0x70/0x71 ports. Registers store BCD digits by default; status register B
// bit 2 selects binary mode and bit 1 selects 12-hour mode.

use "sysmon/utils.mg";

extern fn inb(int port) -> int;
extern fn outb(int port, int value) -> void;

static int S_RTC_SEC = 0;
static int S_RTC_MIN = 0;
static int S_RTC_HOUR = 0;
static int S_RTC_WDAY = 0;
static int S_RTC_MDAY = 0;
static int S_RTC_MONTH = 0;
static int S_RTC_YEAR = 0;
static int S_RTC_CENTURY = 0;
static int S_RTC_VALID = 0;

fn sysmon_bcd_to_bin(int v) -> int {
    int b = v - (v / 16) * 16;
    if (b < 0) { b = b + 16; }
    int hi = (v / 16) - ((v / 16) / 16) * 16;
    return hi * 10 + b;
}

fn rtc_read_raw(int reg) -> int {
    outb(0x70, reg + 128);
    return inb(0x71);
}

fn rtc_read_bin(int reg, int binary) -> int {
    int v = rtc_read_raw(reg);
    if (binary == 1) { return v; }
    if (v < 0) { v = v + 256; }
    if (v > 153) { return 0 - 1; }   // not a valid BCD pair
    return sysmon_bcd_to_bin(v);
}

// Re-read every time slot of the clock into the static cache. Returns 1 on
// a good read, 0 if the RTC was mid-update / not running.
fn sysmon_rtc_refresh() -> int {
    S_RTC_VALID = 0;
    int sta = rtc_read_raw(0x0A);
    if (sysmon_bits(sta, 7, 1) != 0) { return 0; }        // update in progress
    int stb = rtc_read_raw(0x0B);
    if (sysmon_bits(stb, 7, 1) != 0) { return 0; }        // clock not running
    int binary = sysmon_bits(stb, 2, 1);
    int hour12 = sysmon_bits(stb, 1, 1);

    int s = rtc_read_bin(0x00, binary);
    int m = rtc_read_bin(0x02, binary);
    if (s < 0 || m < 0) { return 0; }
    S_RTC_SEC = s;
    S_RTC_MIN = m;

    int hraw = rtc_read_raw(0x04);
    int pm = 0;
    int hs = hraw;
    if (hour12 == 1) {
        pm = sysmon_bits(hraw, 7, 1);
        hs = hraw - (hraw / 128) * 128;                   // drop PM bit
        if (binary == 0) { hs = sysmon_bcd_to_bin(hs); }
        if (hs == 12) { hs = 0; }
        if (pm == 1) { hs = hs + 12; }
    } else {
        if (binary == 0) {
            hs = hraw - (hraw / 128) * 128;               // some chips set PM in 24h too
            hs = sysmon_bcd_to_bin(hs);
        }
    }
    S_RTC_HOUR = hs;

    int wd = rtc_read_bin(0x06, binary);
    int md = rtc_read_bin(0x07, binary);
    int mo = rtc_read_bin(0x08, binary);
    int yr = rtc_read_bin(0x09, binary);
    if (wd < 0 || md < 0 || mo < 0 || yr < 0) { return 0; }
    S_RTC_WDAY = wd;
    S_RTC_MDAY = md;
    S_RTC_MONTH = mo;
    S_RTC_YEAR = yr;

    int ce = rtc_read_bin(0x32, binary);
    if (ce < 0) { ce = 0; }
    S_RTC_CENTURY = ce;

    S_RTC_VALID = 1;
    return 1;
}

fn sysmon_rtc_valid() -> int {
    if (S_RTC_VALID == 0) { sysmon_rtc_refresh(); }
    return S_RTC_VALID;
}

fn sysmon_rtc_seconds() -> int { if (sysmon_rtc_valid() == 0) { return 0 - 1; } return S_RTC_SEC; }
fn sysmon_rtc_minutes() -> int { if (sysmon_rtc_valid() == 0) { return 0 - 1; } return S_RTC_MIN; }
fn sysmon_rtc_hours() -> int { if (sysmon_rtc_valid() == 0) { return 0 - 1; } return S_RTC_HOUR; }
fn sysmon_rtc_day() -> int { if (sysmon_rtc_valid() == 0) { return 0 - 1; } return S_RTC_MDAY; }
fn sysmon_rtc_month() -> int { if (sysmon_rtc_valid() == 0) { return 0 - 1; } return S_RTC_MONTH; }
fn sysmon_rtc_year() -> int { if (sysmon_rtc_valid() == 0) { return 0 - 1; } return S_RTC_YEAR; }
fn sysmon_rtc_century() -> int { if (sysmon_rtc_valid() == 0) { return 0 - 1; } return S_RTC_CENTURY; }
fn sysmon_rtc_weekday() -> int { if (sysmon_rtc_valid() == 0) { return 0 - 1; } return S_RTC_WDAY; }

class SysClock {
    fn getSeconds() -> int { return sysmon_rtc_seconds(); }
    fn getMinutes() -> int { return sysmon_rtc_minutes(); }
    fn getHours() -> int { return sysmon_rtc_hours(); }
    fn getDay() -> int { return sysmon_rtc_day(); }
    fn getMonth() -> int { return sysmon_rtc_month(); }
    fn getYear() -> int { return sysmon_rtc_year(); }
    fn getCentury() -> int { return sysmon_rtc_century(); }
};