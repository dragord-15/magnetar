// sysmon/temperature.mg - SysMon Temperature Monitoring (hardware-direct, heap-free, no bitwise ops)

use "sysmon/utils.mg";

extern fn cpuid(int leaf, int subleaf, int* out0, int* out1, int* out2, int* out3) -> void;
extern fn rdmsr(int msr, int* lo, int* hi) -> void;

fn sysmon_cpu_temp() -> int {
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

fn sysmon_cpu_temp_f() -> int {
    int c = sysmon_cpu_temp();
    if (c < 0) { return c; }
    return (c * 9) / 5 + 32;
}

class SysTemperature {
    fn getCelsius() -> int { return sysmon_cpu_temp(); }
    fn getFahrenheit() -> int { return sysmon_cpu_temp_f(); }
};