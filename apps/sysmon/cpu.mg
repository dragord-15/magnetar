// sysmon/cpu.mg - SysMon CPU Monitoring (hardware-direct, heap-free, no bitwise ops)

use "sysmon/utils.mg";

struct CpuTicks {
    int user;
    int nice;
    int system;
    int idle;
    int iowait;
    int irq;
    int softirq;
};

extern fn cpuid(int leaf, int subleaf, int* out0, int* out1, int* out2, int* out3) -> void;
extern fn rdmsr(int msr, int* lo, int* hi) -> void;
extern fn rdtsc(int* lo, int* hi) -> void;

fn sysmon_cpu_has_aperf() -> int {
    int r0 = 0; int r1 = 0; int r2 = 0; int r3 = 0;
    cpuid(6, 0, &r0, &r1, &r2, &r3);
    return sysmon_bits(r2, 0, 1);
}

fn sysmon_cpu_has_dts() -> int {
    int r0 = 0; int r1 = 0; int r2 = 0; int r3 = 0;
    cpuid(6, 0, &r0, &r1, &r2, &r3);
    return sysmon_bits(r2, 2, 1);
}

fn sysmon_cpu_has_tsc() -> int {
    int r0 = 0; int r1 = 0; int r2 = 0; int r3 = 0;
    cpuid(1, 0, &r0, &r1, &r2, &r3);
    return sysmon_bits(r3, 4, 1);
}

fn sysmon_cpu_num_cores() -> int {
    int r0 = 0; int r1 = 0; int r2 = 0; int r3 = 0;
    cpuid(1, 0, &r0, &r1, &r2, &r3);
    int c = sysmon_bits(r1, 16, 255);
    if (c == 0) { c = 1; }
    return c;
}

fn sysmon_cpu_mhz() -> int {
    int r0 = 0; int r1 = 0; int r2 = 0; int r3 = 0;
    cpuid(0x16, 0, &r0, &r1, &r2, &r3);
    int mhz = r0;
    if (mhz == 0) {
        cpuid(0x15, 0, &r0, &r1, &r2, &r3);
        if (r0 != 0 && r1 != 0 && r2 != 0) {
            mhz = (r2 * r0) / r1;
        }
    }
    return mhz;
}

fn sysmon_cpu_vendor_str(char* buf) -> void {
    int r0 = 0; int r1 = 0; int r2 = 0; int r3 = 0;
    cpuid(0, 0, &r0, &r1, &r2, &r3);
    // out[0..3] hold EAX,EBX,ECX,EDX as 64-bit ints; vendor = EBX,EDX,ECX.
    sysmon_put32(buf + 0, r1);
    sysmon_put32(buf + 4, r3);
    sysmon_put32(buf + 8, r2);
    *(buf + 12) = 0;
}

fn sysmon_cpu_brand_str(char* buf) -> void {
    int r0 = 0; int r1 = 0; int r2 = 0; int r3 = 0;
    cpuid(0x80000002, 0, &r0, &r1, &r2, &r3);
    sysmon_put32(buf + 0, r0); sysmon_put32(buf + 4, r1);
    sysmon_put32(buf + 8, r2); sysmon_put32(buf + 12, r3);
    cpuid(0x80000003, 0, &r0, &r1, &r2, &r3);
    sysmon_put32(buf + 16, r0); sysmon_put32(buf + 20, r1);
    sysmon_put32(buf + 24, r2); sysmon_put32(buf + 28, r3);
    cpuid(0x80000004, 0, &r0, &r1, &r2, &r3);
    sysmon_put32(buf + 32, r0); sysmon_put32(buf + 36, r1);
    sysmon_put32(buf + 40, r2); sysmon_put32(buf + 44, r3);
    *(buf + 48) = 0;
}

static int S_CU_PREV_A = 0;
static int S_CU_PREV_M = 0;

fn sysmon_cpu_usage_percent() -> int {
    if (sysmon_cpu_has_aperf() == 0) { return 0 - 1; }
    int a_lo = 0; int a_hi = 0;
    int m_lo = 0; int m_hi = 0;
    rdmsr(0xE8, &a_lo, &a_hi);
    rdmsr(0xE7, &m_lo, &m_hi);
    int a = a_lo;
    int m = m_lo;
    if (S_CU_PREV_M == 0) {
        S_CU_PREV_A = a;
        S_CU_PREV_M = m;
        return 0;
    }
    int da = a - S_CU_PREV_A;
    int dm = m - S_CU_PREV_M;
    S_CU_PREV_A = a;
    S_CU_PREV_M = m;
    if (dm <= 0 || da < 0 || da > dm) { return 0; }
    return (da * 100) / dm;
}

fn sysmon_get_cpu_ticks_into(CpuTicks* t) -> void {
    if (sysmon_cpu_has_aperf() == 0) {
        t.user = 0; t.nice = 0; t.system = 0; t.idle = 0;
        t.iowait = 0; t.irq = 0; t.softirq = 0;
        return;
    }
    int a_lo = 0; int a_hi = 0;
    int m_lo = 0; int m_hi = 0;
    rdmsr(0xE8, &a_lo, &a_hi);
    rdmsr(0xE7, &m_lo, &m_hi);
    t.user = 0;
    t.nice = 0;
    t.system = a_lo;
    t.idle = m_lo - a_lo;
    if (t.idle < 0) { t.idle = 0; }
    t.iowait = 0; t.irq = 0; t.softirq = 0;
}

class SysCpu {
    int prev_busy;
    int prev_wall;

    fn init() -> void {
        this.prev_busy = 0;
        this.prev_wall = 0;
    }

    fn getUsagePercent() -> int {
        if (sysmon_cpu_has_aperf() == 0) { return 0 - 1; }
        int a_lo = 0; int a_hi = 0;
        int m_lo = 0; int m_hi = 0;
        rdmsr(0xE8, &a_lo, &a_hi);
        rdmsr(0xE7, &m_lo, &m_hi);
        int a = a_lo;
        int m = m_lo;
        if (this.prev_wall == 0) {
            this.prev_busy = a;
            this.prev_wall = m;
            return 0;
        }
        int da = a - this.prev_busy;
        int dm = m - this.prev_wall;
        this.prev_busy = a;
        this.prev_wall = m;
        if (dm <= 0 || da < 0 || da > dm) { return 0; }
        return (da * 100) / dm;
    }

    fn getCoreCount() -> int {
        return sysmon_cpu_num_cores();
    }

    fn getMhz() -> int {
        return sysmon_cpu_mhz();
    }

    fn getVendor(char* buf) -> void {
        sysmon_cpu_vendor_str(buf);
    }

    fn getBrand(char* buf) -> void {
        sysmon_cpu_brand_str(buf);
    }
};