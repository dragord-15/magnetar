// sysmon/memory.mg - SysMon Memory Monitoring (hardware-direct, heap-free, no bitwise ops)

use "sysmon/utils.mg";

struct MemInfo {
    int total_kb;
    int free_kb;
    int available_kb;
    int used_kb;
    int used_percent;
};

static const int MB_INFO_ADDR = 3170312;

fn sysmon_rd32(int p) -> int {
    int v = *(cast<int*>(p));
    int lo = v - (v / 65536) * 65536;
    int hi = (v / 65536) - ((v / 65536) / 65536) * 65536;
    return lo + hi * 65536;
}

fn sysmon_parse_multiboot_mmap(int* total_kb, int* free_kb) -> int {
    int mbi = *(cast<int*>(MB_INFO_ADDR));
    if (mbi == 0) { return 0; }
    int magic = *(cast<int*>(MB_INFO_ADDR + 16));
    
    if (magic == 0x36D76289) {
        int tag = mbi + 8;
        int end = mbi + *(cast<int*>(mbi));
        *total_kb = 0;
        *free_kb = 0;
        while (tag < end) {
            int ttype = sysmon_rd32(tag);
            int tsize = sysmon_rd32(tag + 4);
            if (ttype == 0) { return 1; }
            if (ttype == 6) {
                int entry_size = sysmon_rd32(tag + 8);
                int e = tag + 16;
                int mmap_end = tag + tsize;
                while (e + entry_size <= mmap_end) {
                    int base_lo = sysmon_rd32(e);
                    int base_hi = sysmon_rd32(e + 4);
                    int len_lo = sysmon_rd32(e + 8);
                    int len_hi = sysmon_rd32(e + 12);
                    int etype = sysmon_rd32(e + 16);
                    int len_kb = len_lo / 1024;
                    if (len_hi > 0) { len_kb = len_kb + (len_hi * 4294967); }
                    if (etype >= 1 && etype <= 4) {
                        *total_kb = *total_kb + len_kb;
                    }
                    if (etype == 1) {
                        *free_kb = *free_kb + len_kb;
                    }
                    e = e + entry_size;
                }
            }
            if (tsize == 0) { return 1; }
            tag = tag + tsize;
            int amod = tag - (tag / 8) * 8;
            if (amod != 0) { tag = tag + 8 - amod; }
        }
        return 1;
    } else if (magic == 0x2BADB002) {
        int flags = *(cast<int*>(mbi));
        if ((flags - (flags / 2) * 2) != 0) {
            int lower = *(cast<int*>(mbi + 4));
            int upper = *(cast<int*>(mbi + 8));
            *total_kb = lower + upper;
            *free_kb = *total_kb;
            return 1;
        }
        return 0;
    }
    return 0;
}

fn sysmon_total_ram_kb() -> int {
    int t = 0; int f = 0;
    if (sysmon_parse_multiboot_mmap(&t, &f) != 0) { return t; }
    // CMOS 0x17 = extended memory above 1 MB, in KB (systems < 16 MB).
    // Total conventional memory is 640 KB, so total = 640 + ext.
    int ext = sysmon_cmos_read(0x17);
    if (ext != 0) {
        return 640 + ext;
    }
    int ext_low = sysmon_cmos_read(0x30);
    int ext_high = sysmon_cmos_read(0x31);
    if (ext_low != 0 || ext_high != 0) {
        return 640 + ext_low + (ext_high * 256);
    }
    return 640;
}

fn sysmon_free_ram_kb() -> int {
    int t = 0; int f = 0;
    if (sysmon_parse_multiboot_mmap(&t, &f) != 0) { return f; }
    return sysmon_total_ram_kb();
}

fn sysmon_used_ram_kb() -> int {
    int t = sysmon_total_ram_kb();
    int f = sysmon_free_ram_kb();
    if (t > f) { return t - f; }
    return 0;
}

fn sysmon_used_percent() -> int {
    int t = sysmon_total_ram_kb();
    if (t <= 0) { return 0; }
    int u = sysmon_used_ram_kb();
    return (u * 100) / t;
}

fn sysmon_get_memory_info_into(MemInfo* info) -> void {
    info.total_kb = sysmon_total_ram_kb();
    info.free_kb = sysmon_free_ram_kb();
    info.used_kb = sysmon_used_ram_kb();
    info.used_percent = sysmon_used_percent();
    info.available_kb = info.free_kb;
}

class SysMemory {
    fn getTotalKB() -> int { return sysmon_total_ram_kb(); }
    fn getTotalMB() -> int { return sysmon_total_ram_kb() / 1024; }
    fn getFreeKB() -> int { return sysmon_free_ram_kb(); }
    fn getFreeMB() -> int { return sysmon_free_ram_kb() / 1024; }
    fn getUsedKB() -> int { return sysmon_used_ram_kb(); }
    fn getUsedMB() -> int { return sysmon_used_ram_kb() / 1024; }
    fn getUsagePercent() -> int { return sysmon_used_percent(); }
    fn getInfo() -> MemInfo* {
        MemInfo info;
        sysmon_get_memory_info_into(&info);
        return cast<MemInfo*>(&info);
    }
};