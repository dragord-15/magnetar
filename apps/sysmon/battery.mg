// sysmon/battery.mg - SysMon Battery Monitoring (hardware-direct, heap-free, no bitwise ops)
//
// What really ships in the PC are three pieces of "battery" hardware:
//   1. The RTC/CMOS battery (kept alive bit) - read via CMOS registers 0x0D/0x0E.
//   2. The ACPI Embedded Controller (EC) at the ACPI ports 0x62/0x66 - the
//      gatekeeper for smart-battery percentage on real laptops.
//   3. The battery percentage itself, which ACPI exposes only through AML
//      methods (_BIF/_BST) evaluated on the EC. That needs an AML interpreter,
//      so we probe the EC and report presence; percentage stays N/A.

use "sysmon/utils.mg";

extern fn inb(int port) -> int;
extern fn outb(int port, int value) -> void;

static const int EC_DATA = 98;    // 0x62 - ACPI EC data port
static const int EC_CMD  = 102;   // 0x66 - ACPI EC command/status port

// ── RTC/CMOS battery ──
fn sysmon_cmos_rtc_battery_ok() -> int {
    outb(0x70, 0x0D + 128);
    int st = inb(0x71);
    if ((st - (st / 128) * 128) == 0) { return 0; }
    outb(0x70, 0x0E + 128);
    int diag = inb(0x71);
    if (sysmon_bits(diag, 6, 1) != 0) { return 0; }
    return 1;
}

// ── ACPI Root System Description Pointer lookup ──
// Scans the real-mode BIOS memory areas for the "RSD PTR " signature
// (physical memory is identity-mapped by the kernel).
fn sysmon_acpi_find_rsdp() -> int {
    // EBDA segment lives in the BDA double-word at 0x40E.
    int ebda = sysmon_byte_val(*(cast<char*>(0x40E))) + sysmon_byte_val(*(cast<char*>(0x40F))) * 256;
    if (ebda != 0 && ebda < 0x10000) {
        int seg = (ebda - (ebda % 16));
        int addr = seg * 16;
        int end = addr + 1024;
        while (addr + 16 <= end) {
            if (sysmon_streq_n(cast<char*>(addr), "RSD PTR ") == 1) { return addr; }
            addr = addr + 16;
        }
    }
    // Legacy BIOS area scan: 0xE0000..0xFFFFF, 16-byte aligned.
    int addr2 = 917504;
    while (addr2 + 16 <= 1048576) {
        if (sysmon_streq_n(cast<char*>(addr2), "RSD PTR ") == 1) { return addr2; }
        addr2 = addr2 + 16;
    }
    return 0;
}

fn sysmon_acpi_present() -> int {
    if (sysmon_acpi_find_rsdp() != 0) { return 1; }
    return 0;
}

// ── ACPI Embedded Controller probe ──
// Standard EC handshake: wait for the input buffer to drain, then poke the
// data port. If the ports talk back (not pulled high / all-ones), an EC is there.
fn sysmon_ec_wait_ibf_clear() -> int {
    int tries = 0;
    while (tries < 4000) {
        int st = inb(EC_CMD);
        if (sysmon_bits(st, 1, 1) == 0) { return 1; }
        tries = tries + 1;
    }
    return 0;
}

fn sysmon_ec_status() -> int {
    return inb(EC_CMD);
}

fn sysmon_ec_present() -> int {
    if (sysmon_ec_wait_ibf_clear() == 0) { return 0; }
    int s1 = inb(EC_CMD);
    int d1 = inb(EC_DATA);
    int s2 = inb(EC_CMD);
    int d2 = inb(EC_DATA);
    if (s1 == 255 && s2 == 255 && d1 == 255 && d2 == 255) { return 0; }
    return 1;
}

// ── Battery state (as far as bare-metal code can tell without AML) ──
fn sysmon_battery_present() -> int {
    if (sysmon_ec_present() == 1) { return 1; }
    return 0;
}

// ACPI smart-battery percentage requires evaluating the _BST AML method on
// the EC; without an AML interpreter we report "unknown" (-1).
fn sysmon_battery_percent() -> int {
    if (sysmon_ec_present() == 0) { return 0 - 1; }
    return 0 - 1;
}

fn sysmon_battery_ac_power() -> int {
    // AC power state also lives behind AML (_PSR). EC probe tells us the
    // controller exists but not the state, so report unknown (-1).
    if (sysmon_ec_present() == 0) { return 0 - 1; }
    return 0 - 1;
}

class SysBattery {
    fn getPercent() -> int { return sysmon_battery_percent(); }
    fn isPresent() -> int { return sysmon_battery_present(); }
    fn isCharging() -> int { return sysmon_battery_ac_power(); }
    fn hasRtcBattery() -> int { return sysmon_cmos_rtc_battery_ok(); }
    fn acpi() -> int { return sysmon_acpi_present(); }
    fn ec() -> int { return sysmon_ec_present(); }
};