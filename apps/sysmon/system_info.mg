// sysmon/system_info.mg - SysMon System Information (hardware-direct, heap-free, no bitwise ops)

use "sysmon/utils.mg";

extern fn cpuid(int leaf, int subleaf, int* out0, int* out1, int* out2, int* out3) -> void;
extern fn rdmsr(int msr, int* lo, int* hi) -> void;
extern fn rdtsc(int* lo, int* hi) -> void;
extern fn inb(int port) -> int;
extern fn outb(int port, int value) -> void;

struct SysInfo {
    int uptime_s;
    int cpu_mhz;
    int cpu_cores;
    int total_ram_kb;
    int free_ram_kb;
    int cpu_temp_c;
};

static int S_TSC_FREQ = 0;
static int S_TSC_SET = 0;
static int S_T0_LO = 0;
static int S_T0_HI = 0;

fn sysmon_calibrate_tsc() -> int {
    if (S_TSC_FREQ != 0) { return S_TSC_FREQ; }
    int r0 = 0; int r1 = 0; int r2 = 0; int r3 = 0;
    cpuid(0x15, 0, &r0, &r1, &r2, &r3);
    if (r0 != 0 && r1 != 0 && r2 != 0) {
        S_TSC_FREQ = (r2 * r0) / r1;
        return S_TSC_FREQ;
    }
    cpuid(0x16, 0, &r0, &r1, &r2, &r3);
    if (r0 != 0) {
        S_TSC_FREQ = r0 * 1000000;
        return S_TSC_FREQ;
    }
    outb(0x43, 0xB0);
    outb(0x40, 0);
    outb(0x40, 0);
    int t0_lo = 0; int t0_hi = 0;
    int t1_lo = 0; int t1_hi = 0;
    rdtsc(&t0_lo, &t0_hi);
    int wait = 0;
    while (wait < 2000000) {
        outb(0x43, 0xE2);
        int c = inb(0x40) + inb(0x40) * 256;
        if (c > 32768) { break; }
        wait = wait + 1;
    }
    rdtsc(&t1_lo, &t1_hi);
    int dt_lo = t1_lo - t0_lo;
    int dt_hi = t1_hi - t0_hi;
    if (dt_hi > 0) { dt_lo = 2147483647; }
    if (dt_lo > 10000) {
        S_TSC_FREQ = (dt_lo * 10000) / 54925;
    }
    if (S_TSC_FREQ == 0) { S_TSC_FREQ = 2000000000; }
    return S_TSC_FREQ;
}

fn sysmon_tsc_freq_hz() -> int {
    if (S_TSC_FREQ == 0) { sysmon_calibrate_tsc(); }
    return S_TSC_FREQ;
}

fn sysmon_uptime_seconds() -> int {
    int t_lo = 0; int t_hi = 0;
    rdtsc(&t_lo, &t_hi);
    if (S_TSC_SET == 0) {
        S_T0_LO = t_lo;
        S_T0_HI = t_hi;
        S_TSC_SET = 1;
        return 0;
    }
    int freq = sysmon_tsc_freq_hz();
    int dhi = t_hi - S_T0_HI;
    int dlo = t_lo - S_T0_LO;
    int sec = 0;
    if (freq > 0) {
        int ratio = 4294967296 / freq;
        if (ratio > 0) {
            sec = dhi * ratio + dlo / freq;
        } else {
            sec = dhi + dlo / freq;
        }
    }
    return sec;
}

fn sysmon_cpu_cores() -> int {
    int r0 = 0; int r1 = 0; int r2 = 0; int r3 = 0;
    cpuid(1, 0, &r0, &r1, &r2, &r3);
    int c = sysmon_bits(r1, 16, 255);
    if (c == 0) { c = 1; }
    return c;
}

fn sysmon_cpu_temp_c() -> int {
    int r0 = 0; int r1 = 0; int r2 = 0; int r3 = 0;
    cpuid(6, 0, &r0, &r1, &r2, &r3);
    if (sysmon_bits(r2, 2, 1) == 0) { return 0 - 1; }
    int lo = 0; int hi = 0;
    rdmsr(0x19C, &lo, &hi);
    int dts = sysmon_bits(lo, 16, 127);
    rdmsr(0x1A2, &lo, &hi);
    int tjmax = sysmon_bits(lo, 16, 255);
    if (tjmax == 0) { tjmax = 100; }
    return tjmax - dts;
}

fn sysmon_get_sys_info_into(SysInfo* si) -> void {
    si.uptime_s = sysmon_uptime_seconds();
    si.cpu_mhz = sysmon_cpu_mhz();
    si.cpu_cores = sysmon_cpu_cores();
    si.total_ram_kb = sysmon_total_ram_kb();
    si.free_ram_kb = sysmon_free_ram_kb();
    si.cpu_temp_c = sysmon_cpu_temp_c();
}

class SysSystemInfo {
    fn getUptimeSec() -> int { return sysmon_uptime_seconds(); }
    fn getCpuMhz() -> int { return sysmon_cpu_mhz(); }
    fn getCpuCores() -> int { return sysmon_cpu_cores(); }
    fn getTotalRamKB() -> int { return sysmon_total_ram_kb(); }
    fn getFreeRamKB() -> int { return sysmon_free_ram_kb(); }
    fn getCpuTempC() -> int { return sysmon_cpu_temp_c(); }
    fn getInfo() -> SysInfo* {
        SysInfo si;
        sysmon_get_sys_info_into(&si);
        return cast<SysInfo*>(&si);
    }
};