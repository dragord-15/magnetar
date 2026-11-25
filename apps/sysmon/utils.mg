// sysmon/utils.mg - SysMon Core Utilities (hardware-direct, heap-free, no bitwise ops)

extern fn inb(int port) -> int;
extern fn outb(int port, int value) -> void;
extern fn inw(int port) -> int;
extern fn outw(int port, int value) -> void;
extern fn inl(int port) -> int;
extern fn outl(int port, int value) -> void;

fn sysmon_byte_val(int v) -> int {
    int b = v - (v / 256) * 256;
    if (b < 0) { b = b + 256; }
    return b;
}

fn sysmon_put32(char* b, int v) -> void {
    *(b + 0) = sysmon_byte_val(v);
    *(b + 1) = sysmon_byte_val(v / 256);
    *(b + 2) = sysmon_byte_val(v / 65536);
    *(b + 3) = sysmon_byte_val(v / 16777216);
}

fn sysmon_bits(int v, int shift, int mask) -> int {
    int p = 1;
    int s = shift;
    while (s > 0) { p = p * 2; s = s - 1; }
    int m1 = mask + 1;
    int q = v / p;
    int res = q - (q / m1) * m1;
    if (res < 0) { res = res + m1; }
    return res;
}

fn sysmon_find_key(char* buf, int len, string key) -> int {
    char* kp = cast<char*>(key);
    int kl = 0;
    while (sysmon_byte_val(*(kp + kl)) != 0) {
        kl = kl + 1;
    }
    int i = 0;
    while (i + kl <= len) {
        int j = 0;
        int is_match = 1;
        while (j < kl && is_match == 1) {
            if (sysmon_byte_val(*(buf + i + j)) != sysmon_byte_val(*(kp + j))) {
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

fn sysmon_parse_num(char* buf, int start, int len) -> int {
    int i = start;
    int found_digit = 0;
    while (i < len && found_digit == 0) {
        int c = sysmon_byte_val(*(buf + i));
        if (c >= 48 && c <= 57) {
            found_digit = 1;
        } else {
            i = i + 1;
        }
    }
    
    int val = 0;
    int still_digit = 1;
    while (i < len && still_digit == 1) {
        int c = sysmon_byte_val(*(buf + i));
        if (c >= 48 && c <= 57) {
            val = val * 10 + (c - 48);
            i = i + 1;
        } else {
            still_digit = 0;
        }
    }
    return val;
}

fn sysmon_strlen(string str) -> int {
    char* p = cast<char*>(str);
    int len = 0;
    while (sysmon_byte_val(*(p + len)) != 0) {
        len = len + 1;
    }
    return len;
}

fn sysmon_streq(char* a, char* b) -> int {
    int i = 0;
    while (1 == 1) {
        int c1 = sysmon_byte_val(*(a + i));
        int c2 = sysmon_byte_val(*(b + i));
        if (c1 != c2) { return 0; }
        if (c1 == 0) { return 1; }
        i = i + 1;
    }
    return 0;
}

// Compare a memory buffer against a string literal (n bytes, terminator from
// the literal). Used to match signatures like "RSD PTR " in raw memory.
fn sysmon_streq_n(char* a, string b) -> int {
    char* p = cast<char*>(b);
    int i = 0;
    while (sysmon_byte_val(*(p + i)) != 0) {
        if (sysmon_byte_val(*(a + i)) != sysmon_byte_val(*(p + i))) { return 0; }
        i = i + 1;
    }
    return 1;
}

fn sysmon_cmos_read(int reg) -> int {
    outb(0x70, reg + 128);
    return inb(0x71);
}

fn sysmon_cmos_write(int reg, int val) -> void {
    outb(0x70, reg + 128);
    outb(0x71, val);
}

fn sysmon_pci_conf_read32(int bus, int dev, int func, int reg) -> int {
    int addr = 2147483648 + bus * 65536 + dev * 2048 + func * 256 + reg;
    outl(0xCF8, addr);
    return inl(0xCFC);
}

fn sysmon_pci_conf_write32(int bus, int dev, int func, int reg, int val) -> void {
    int addr = 2147483648 + bus * 65536 + dev * 2048 + func * 256 + reg;
    outl(0xCF8, addr);
    outl(0xCFC, val);
}

fn sysmon_int_to_str(int val, char* buf) -> int {
    int v = val;
    int n = 0;
    int neg = 0;
    if (v < 0) { neg = 1; v = -v; }
    if (v == 0) {
        *(buf + 0) = 48;
        n = 1;
    }
    while (v > 0) {
        int d = v % 10;
        *(buf + n) = 48 + d;
        n = n + 1;
        v = v / 10;
    }
    if (neg == 1) {
        *(buf + n) = 45;
        n = n + 1;
    }
    int i = 0;
    while (i < n / 2) {
        char t = *(buf + i);
        *(buf + i) = *(buf + n - 1 - i);
        *(buf + n - 1 - i) = t;
        i = i + 1;
    }
    *(buf + n) = 0;
    return n;
}