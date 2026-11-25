// memory.mg — Memory Information & Statistics Library for Magnetar OS & Linux
use "system.mg";

// -------------------------------------------------------------
// Data Structures
// -------------------------------------------------------------

struct MemInfo {
    int total_kb;
    int free_kb;
    int available_kb;
    int buffers_kb;
    int cached_kb;
    int swap_total_kb;
    int swap_free_kb;
    int used_kb;
    int swap_used_kb;
    int used_percent;
    int swap_used_percent;
};

// Memory type constants (for OS kernel & hardware memory mapping)
const int MEMORY_TYPE_USABLE       = 1; // RAM متاحة بالنظام
const int MEMORY_TYPE_RESERVED     = 2; // محجوزة للعتاد
const int MEMORY_TYPE_ACPI_RECLAIM = 3; // محجوزة لبيانات ACPI
const int MEMORY_TYPE_NVS          = 4; // ذاكرة غير متطايرة
const int MEMORY_TYPE_BADRAM       = 5; // ذاكرة تالفة

// -------------------------------------------------------------
// Internal / Helper Functions
// -------------------------------------------------------------

fn _byte_val(int v) -> int {
    int b = v - (v / 256) * 256;
    if (b < 0) { b = b + 256; }
    return b;
}

fn _mem_read_proc(string path, char* buf, int max_len) -> int {
    int fd = sys_open(path, 0, 0);
    if (fd < 0) {
        *(buf + 0) = 0;
        return 0;
    }
    int bytes = sys_read(fd, buf, max_len - 1);
    sys_close(fd);
    if (bytes < 0) {
        bytes = 0;
    }
    *(buf + bytes) = 0;
    return bytes;
}

fn _mem_find_key(char* buf, int len, string key) -> int {
    char* kp = cast<char*>(key);
    int kl = 0;
    while (_byte_val(*(kp + kl)) != 0) {
        kl = kl + 1;
    }
    int i = 0;
    while (i + kl <= len) {
        int j = 0;
        int is_match = 1;
        while (j < kl && is_match == 1) {
            if (_byte_val(*(buf + i + j)) != _byte_val(*(kp + j))) {
                is_match = 0;
            } else {
                j = j + 1;
            }
        }
        if (is_match == 1) {
            return i;
        }
        i = i + 1;
    }
    return 0 - 1;
}

fn _mem_parse_num(char* buf, int start, int len) -> int {
    int i = start;
    int found_digit = 0;
    while (i < len && found_digit == 0) {
        int c = _byte_val(*(buf + i));
        if (c >= 48 && c <= 57) {
            found_digit = 1;
        } else {
            i = i + 1;
        }
    }
    
    int val = 0;
    int still_digit = 1;
    while (i < len && still_digit == 1) {
        int c = _byte_val(*(buf + i));
        if (c >= 48 && c <= 57) {
            val = val * 10 + (c - 48);
            i = i + 1;
        } else {
            still_digit = 0;
        }
    }
    return val;
}

fn get_proc_mem_value(string key) -> int {
    char* buf = alloc<char>(4096);
    int len = _mem_read_proc("/proc/meminfo", buf, 4096);
    if (len <= 0) {
        free(buf);
        return 0;
    }
    int pos = _mem_find_key(buf, len, key);
    if (pos < 0) {
        free(buf);
        return 0;
    }
    int val = _mem_parse_num(buf, pos, len);
    free(buf);
    return val;
}

// -------------------------------------------------------------
// Public Memory API
// -------------------------------------------------------------

fn get_memory_info() -> MemInfo* {
    MemInfo* info = new MemInfo;
    info.total_kb = get_proc_mem_value("MemTotal:");
    info.free_kb = get_proc_mem_value("MemFree:");
    info.available_kb = get_proc_mem_value("MemAvailable:");
    info.buffers_kb = get_proc_mem_value("Buffers:");
    info.cached_kb = get_proc_mem_value("Cached:");
    info.swap_total_kb = get_proc_mem_value("SwapTotal:");
    info.swap_free_kb = get_proc_mem_value("SwapFree:");

    if (info.available_kb > 0) {
        info.used_kb = info.total_kb - info.available_kb;
    } else {
        info.used_kb = info.total_kb - info.free_kb;
    }

    if (info.total_kb > 0) {
        info.used_percent = (info.used_kb * 100) / info.total_kb;
    } else {
        info.used_percent = 0;
    }

    if (info.swap_total_kb > 0) {
        info.swap_used_kb = info.swap_total_kb - info.swap_free_kb;
        info.swap_used_percent = (info.swap_used_kb * 100) / info.swap_total_kb;
    } else {
        info.swap_used_kb = 0;
        info.swap_used_percent = 0;
    }

    return info;
}

fn get_total_memory_kb() -> int {
    return get_proc_mem_value("MemTotal:");
}

fn get_total_memory_mb() -> int {
    return get_proc_mem_value("MemTotal:") / 1024;
}

fn get_available_memory_kb() -> int {
    return get_proc_mem_value("MemAvailable:");
}

fn get_available_memory_mb() -> int {
    return get_proc_mem_value("MemAvailable:") / 1024;
}

fn get_free_memory_kb() -> int {
    return get_proc_mem_value("MemFree:");
}

fn get_free_memory_mb() -> int {
    return get_proc_mem_value("MemFree:") / 1024;
}

fn get_used_memory_kb() -> int {
    int total = get_total_memory_kb();
    int avail = get_available_memory_kb();
    if (avail > 0) {
        return total - avail;
    }
    return total - get_free_memory_kb();
}

fn get_used_memory_mb() -> int {
    return get_used_memory_kb() / 1024;
}

fn get_memory_usage_percentage() -> int {
    int total = get_total_memory_kb();
    if (total <= 0) {
        return 0;
    }
    int used = get_used_memory_kb();
    return (used * 100) / total;
}

fn print_memory_info_summary() -> void {
    MemInfo* mem = get_memory_info();
    print_str("=== Memory Information (Magnetar OS) ===\n");
    print_str("Total RAM:         "); print_int(mem.total_kb / 1024); print_str(" MB ("); print_int(mem.total_kb); print_str(" KB)\n");
    print_str("Available RAM:     "); print_int(mem.available_kb / 1024); print_str(" MB ("); print_int(mem.available_kb); print_str(" KB)\n");
    print_str("Free RAM:          "); print_int(mem.free_kb / 1024); print_str(" MB ("); print_int(mem.free_kb); print_str(" KB)\n");
    print_str("Used RAM:          "); print_int(mem.used_kb / 1024); print_str(" MB ("); print_int(mem.used_kb); print_str(" KB)\n");
    print_str("Buffers:           "); print_int(mem.buffers_kb / 1024); print_str(" MB ("); print_int(mem.buffers_kb); print_str(" KB)\n");
    print_str("Cached:            "); print_int(mem.cached_kb / 1024); print_str(" MB ("); print_int(mem.cached_kb); print_str(" KB)\n");
    print_str("RAM Usage:         "); print_int(mem.used_percent); print_str(" %\n");
    print_str("Swap Total:        "); print_int(mem.swap_total_kb / 1024); print_str(" MB\n");
    print_str("Swap Free:         "); print_int(mem.swap_free_kb / 1024); print_str(" MB\n");
    print_str("Swap Usage:        "); print_int(mem.swap_used_percent); print_str(" %\n");
    print_str("=========================================\n");
    delete mem;
}

// -------------------------------------------------------------
// OOP Class Wrapper
// -------------------------------------------------------------

class Memory {
    fn getTotalKB() -> int { return get_total_memory_kb(); }
    fn getTotalMB() -> int { return get_total_memory_mb(); }
    fn getAvailableKB() -> int { return get_available_memory_kb(); }
    fn getAvailableMB() -> int { return get_available_memory_mb(); }
    fn getFreeKB() -> int { return get_free_memory_kb(); }
    fn getFreeMB() -> int { return get_free_memory_mb(); }
    fn getUsedKB() -> int { return get_used_memory_kb(); }
    fn getUsedMB() -> int { return get_used_memory_mb(); }
    fn getUsagePercent() -> int { return get_memory_usage_percentage(); }
    fn getSwapTotalKB() -> int { return get_proc_mem_value("SwapTotal:"); }
    fn getSwapFreeKB() -> int { return get_proc_mem_value("SwapFree:"); }
    fn getInfo() -> MemInfo* { return get_memory_info(); }
    fn printSummary() -> void { print_memory_info_summary(); }
};