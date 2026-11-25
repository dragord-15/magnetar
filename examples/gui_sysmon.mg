use "gui.mg";
use "sysmon/sysmon_all.mg";

extern fn sleep_ms(int ms) -> void;
extern fn get_timestamp() -> int;
extern fn sys_open(string path, int flags, int mode) -> int;
extern fn sys_close(int fd) -> int;
extern fn sys_read(int fd, char* buf, int count) -> int;
extern fn sys_getdents64(int fd, char* dirp, int count) -> int;

fn inb(int port) -> int { return 0; }
fn outb(int port, int value) -> void { }
fn inw(int port) -> int { return 0; }
fn outw(int port, int value) -> void { }
fn inl(int port) -> int { return 0; }
fn outl(int port, int value) -> void { }

fn cpuid(int leaf, int subleaf, int* out0, int* out1, int* out2, int* out3) -> void {
    asm {
        mov eax, [leaf];
        mov ecx, [subleaf];
        cpuid;
        mov r8, [out0];
        mov [r8], eax;
        mov r8, [out1];
        mov [r8], ebx;
        mov r8, [out2];
        mov [r8], ecx;
        mov r8, [out3];
        mov [r8], edx;
    }
}

fn rdmsr(int msr, int* lo, int* hi) -> void {
    *lo = 0;
    *hi = 0;
}

fn rdtsc(int* lo, int* hi) -> void {
    asm {
        rdtsc;
        mov r8, [lo];
        mov [r8], eax;
        mov r8, [hi];
        mov [r8], edx;
    }
}

static const int HIST_LEN = 90;

static char* SM_FILE;
static char* SM_MEM;
static char* SM_NET;
static char* SM_DISK;
static char* SM_CPUINFO;
static char* SM_DIRBUF;
static char* SM_HOST;
static char* SM_KERNEL;
static char* SM_BRAND;
static char* SM_VENDOR;
static char* SM_SIZE;
static char* SM_RATE;
static char* SM_UPTIME;
static char* SM_LOAD;
static char* SM_CLOCK;
static char* SM_DATE;
static char* SM_PCT;
static char* SM_TEMP;

static int* SM_CPU_HIST;
static int* SM_MEM_HIST;
static int SM_HIST_POS;
static int SM_HIST_COUNT;

static int SM_FILE_LEN;
static int SM_POS;
static int SM_CPU_CORES;
static int SM_CPU_BASE_MHZ;
static int SM_CPU_MHZ;
static int SM_CPU_TEMP;
static int SM_CPU_PCT;
static int SM_MEM_PCT;
static int SM_MEM_TOTAL;
static int SM_MEM_AVAIL;
static int SM_MEM_USED;
static int SM_MEM_SWAP_TOTAL;
static int SM_MEM_SWAP_USED;
static int SM_LOAD1;
static int SM_LOAD5;
static int SM_LOAD15;
static int SM_UPTIME_SEC;
static int SM_NET_RX_TOTAL;
static int SM_NET_TX_TOTAL;
static int SM_NET_RX_RATE;
static int SM_NET_TX_RATE;
static int SM_NET_IFACES;
static int SM_DISK_READ_TOTAL;
static int SM_DISK_WRITE_TOTAL;
static int SM_DISK_READ_RATE;
static int SM_DISK_WRITE_RATE;
static int SM_DISK_DEVICES;
static int SM_PROC_RUNNING;
static int SM_PROC_TOTAL;
static int SM_PROC_BLOCKED;

static int SM_PREV_CPU_TOTAL;
static int SM_PREV_CPU_IDLE;
static int SM_HAVE_CPU;
static int SM_PREV_NET_RX;
static int SM_PREV_NET_TX;
static int SM_HAVE_NET;
static int SM_PREV_DISK_R;
static int SM_PREV_DISK_W;
static int SM_HAVE_DISK;

fn sm_byte(char* p, int i) -> int {
    int v = cast<int>(*(p + i));
    if (v < 0) { v = v + 256; }
    return v;
}

fn sm_zlen(char* p) -> int {
    int n = 0;
    while (sm_byte(p, n) != 0) { n = n + 1; }
    return n;
}

fn sm_copy_to(char* dst, int di, string src) -> int {
    char* p = cast<char*>(src);
    int i = 0;
    while (sm_byte(p, i) != 0) {
        *(dst + di) = *(p + i);
        di = di + 1;
        i = i + 1;
    }
    return di;
}

fn sm_read_file(string path, char* buf, int cap) -> int {
    int fd = sys_open(path, 0, 0);
    if (fd < 0) { *(buf) = 0; return 0; }
    int n = sys_read(fd, buf, cap - 1);
    sys_close(fd);
    if (n < 0) { n = 0; }
    *(buf + n) = 0;
    return n;
}

fn sm_find(char* buf, int len, string key) -> int {
    char* kp = cast<char*>(key);
    int kl = 0;
    while (sm_byte(kp, kl) != 0) { kl = kl + 1; }
    int i = 0;
    while (i + kl <= len) {
        int j = 0;
        int ok = 1;
        while (j < kl) {
            if (sm_byte(buf, i + j) != sm_byte(kp, j)) { ok = 0; }
            j = j + 1;
        }
        if (ok == 1) { return i; }
        i = i + 1;
    }
    return 0 - 1;
}

fn sm_is_digit(int c) -> int {
    if (c >= 48 && c <= 57) { return 1; }
    return 0;
}

fn sm_is_space(int c) -> int {
    if (c == 32 || c == 9 || c == 10 || c == 13) { return 1; }
    return 0;
}

fn sm_num_next(char* buf, int limit) -> int {
    int i = SM_POS;
    while (i < limit && sm_is_digit(sm_byte(buf, i)) == 0) { i = i + 1; }
    if (i >= limit) { SM_POS = limit; return 0; }
    int v = 0;
    while (i < limit && sm_is_digit(sm_byte(buf, i)) == 1) {
        v = v * 10 + sm_byte(buf, i) - 48;
        i = i + 1;
    }
    SM_POS = i;
    return v;
}

fn sm_value_buf(char* buf, int len, string key) -> int {
    int pos = sm_find(buf, len, key);
    if (pos < 0) { return 0; }
    SM_POS = pos;
    return sm_num_next(buf, len);
}

fn sm_find_char(char* buf, int start, int end, int ch) -> int {
    int i = start;
    while (i < end) {
        if (sm_byte(buf, i) == ch) { return i; }
        i = i + 1;
    }
    return 0 - 1;
}

fn sm_trim_line(char* buf, int len) -> void {
    int i = 0;
    while (i < len) {
        int c = sm_byte(buf, i);
        if (c == 10 || c == 13) { *(buf + i) = 0; return; }
        i = i + 1;
    }
}

fn sm_trim_spaces(char* buf) -> char* {
    int n = sm_zlen(buf);
    int end = n;
    while (end > 0 && sm_is_space(sm_byte(buf, end - 1)) == 1) {
        end = end - 1;
        *(buf + end) = 0;
    }
    int start = 0;
    while (start < end && sm_is_space(sm_byte(buf, start)) == 1) { start = start + 1; }
    return buf + start;
}

fn sm_fmt_size(int kb) -> string {
    if (kb < 0) { kb = 0; }
    int whole = 0;
    int frac = 0;
    int di = 0;
    if (kb >= 1048576) {
        whole = kb / 1048576;
        frac = (kb - whole * 1048576) * 10 / 1048576;
        di = sm_copy_to(SM_SIZE, 0, dsk_itoa(whole));
        *(SM_SIZE + di) = 46; di = di + 1;
        di = sm_copy_to(SM_SIZE, di, dsk_itoa_pad(frac, 1));
        di = sm_copy_to(SM_SIZE, di, " GB");
    } else if (kb >= 1024) {
        whole = kb / 1024;
        frac = (kb - whole * 1024) * 10 / 1024;
        di = sm_copy_to(SM_SIZE, 0, dsk_itoa(whole));
        *(SM_SIZE + di) = 46; di = di + 1;
        di = sm_copy_to(SM_SIZE, di, dsk_itoa_pad(frac, 1));
        di = sm_copy_to(SM_SIZE, di, " MB");
    } else {
        di = sm_copy_to(SM_SIZE, 0, dsk_itoa(kb));
        di = sm_copy_to(SM_SIZE, di, " KB");
    }
    *(SM_SIZE + di) = 0;
    return cast<string>(SM_SIZE);
}

fn sm_fmt_rate(int kb) -> string {
    string s = sm_fmt_size(kb);
    int di = sm_copy_to(SM_RATE, 0, s);
    di = sm_copy_to(SM_RATE, di, "/s");
    *(SM_RATE + di) = 0;
    return cast<string>(SM_RATE);
}

fn sm_fmt_pct(int v) -> string {
    if (v < 0) { v = 0; }
    if (v > 100) { v = 100; }
    int di = sm_copy_to(SM_PCT, 0, dsk_itoa(v));
    *(SM_PCT + di) = 37;
    *(SM_PCT + di + 1) = 0;
    return cast<string>(SM_PCT);
}

fn sm_fmt_temp(int c) -> string {
    if (c < 0) { return "N/A"; }
    int di = sm_copy_to(SM_TEMP, 0, dsk_itoa(c));
    di = sm_copy_to(SM_TEMP, di, " C");
    *(SM_TEMP + di) = 0;
    return cast<string>(SM_TEMP);
}

fn sm_append_hundredths(char* buf, int di, int h) -> int {
    int whole = h / 100;
    int frac = h - whole * 100;
    di = sm_copy_to(buf, di, dsk_itoa(whole));
    *(buf + di) = 46; di = di + 1;
    di = sm_copy_to(buf, di, dsk_itoa_pad(frac, 2));
    return di;
}

fn sm_build_loads() -> void {
    int di = 0;
    di = sm_copy_to(SM_LOAD, di, "1m ");
    di = sm_append_hundredths(SM_LOAD, di, SM_LOAD1);
    di = sm_copy_to(SM_LOAD, di, "   5m ");
    di = sm_append_hundredths(SM_LOAD, di, SM_LOAD5);
    di = sm_copy_to(SM_LOAD, di, "   15m ");
    di = sm_append_hundredths(SM_LOAD, di, SM_LOAD15);
    *(SM_LOAD + di) = 0;
}

fn sm_fmt_uptime(int sec) -> string {
    if (sec < 0) { sec = 0; }
    int di = 0;
    int days = sec / 86400;
    int rem = sec - days * 86400;
    int h = rem / 3600;
    int m = (rem - h * 3600) / 60;
    int s = rem - h * 3600 - m * 60;
    if (days > 0) {
        di = sm_copy_to(SM_UPTIME, di, dsk_itoa(days));
        *(SM_UPTIME + di) = 100; di = di + 1;
        *(SM_UPTIME + di) = 32; di = di + 1;
    }
    di = sm_copy_to(SM_UPTIME, di, dsk_itoa_pad(h, 2));
    *(SM_UPTIME + di) = 58; di = di + 1;
    di = sm_copy_to(SM_UPTIME, di, dsk_itoa_pad(m, 2));
    *(SM_UPTIME + di) = 58; di = di + 1;
    di = sm_copy_to(SM_UPTIME, di, dsk_itoa_pad(s, 2));
    *(SM_UPTIME + di) = 0;
    return cast<string>(SM_UPTIME);
}

fn sm_build_clock() -> void {
    int ts = get_timestamp();
    int day = ts / 86400;
    int secs = ts - day * 86400;
    int h = secs / 3600;
    int m = (secs - h * 3600) / 60;
    int s = secs - h * 3600 - m * 60;
    int di = 0;
    di = sm_copy_to(SM_CLOCK, 0, dsk_itoa_pad(h, 2));
    *(SM_CLOCK + di) = 58; di = di + 1;
    di = sm_copy_to(SM_CLOCK, di, dsk_itoa_pad(m, 2));
    *(SM_CLOCK + di) = 58; di = di + 1;
    di = sm_copy_to(SM_CLOCK, di, dsk_itoa_pad(s, 2));
    *(SM_CLOCK + di) = 0;

    int zz = day + 719468;
    int era = zz / 146097;
    int doe = zz - era * 146097;
    int yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    int y = yoe + era * 400;
    int doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    int mp = (5 * doy + 2) / 153;
    int d = doy - (153 * mp + 2) / 5 + 1;
    int mo = mp + 3;
    if (mp >= 10) { mo = mp - 9; }
    if (mo <= 2) { y = y + 1; }
    di = sm_copy_to(SM_DATE, 0, dsk_itoa(y));
    *(SM_DATE + di) = 45; di = di + 1;
    di = sm_copy_to(SM_DATE, di, dsk_itoa_pad(mo, 2));
    *(SM_DATE + di) = 45; di = di + 1;
    di = sm_copy_to(SM_DATE, di, dsk_itoa_pad(d, 2));
    *(SM_DATE + di) = 0;
}

fn sm_sample_cpu() -> void {
    SM_FILE_LEN = sm_read_file("/proc/stat", SM_FILE, 16383);
    int pos = sm_find(SM_FILE, SM_FILE_LEN, "cpu ");
    if (pos < 0) { return; }
    SM_POS = pos + 4;
    int user = sm_num_next(SM_FILE, SM_FILE_LEN);
    int nice = sm_num_next(SM_FILE, SM_FILE_LEN);
    int system = sm_num_next(SM_FILE, SM_FILE_LEN);
    int idle = sm_num_next(SM_FILE, SM_FILE_LEN);
    int iowait = sm_num_next(SM_FILE, SM_FILE_LEN);
    int irq = sm_num_next(SM_FILE, SM_FILE_LEN);
    int softirq = sm_num_next(SM_FILE, SM_FILE_LEN);
    int steal = sm_num_next(SM_FILE, SM_FILE_LEN);
    int total = user + nice + system + idle + iowait + irq + softirq + steal;
    int idle_all = idle + iowait;
    if (SM_HAVE_CPU == 1) {
        int dt = total - SM_PREV_CPU_TOTAL;
        int di = idle_all - SM_PREV_CPU_IDLE;
        if (dt > 0) {
            int busy = dt - di;
            if (busy < 0) { busy = 0; }
            SM_CPU_PCT = busy * 100 / dt;
            if (SM_CPU_PCT < 0) { SM_CPU_PCT = 0; }
            if (SM_CPU_PCT > 100) { SM_CPU_PCT = 100; }
        }
    }
    SM_PREV_CPU_TOTAL = total;
    SM_PREV_CPU_IDLE = idle_all;
    SM_HAVE_CPU = 1;
}

fn sm_sample_memory() -> void {
    int n = sm_read_file("/proc/meminfo", SM_MEM, 16383);
    SM_MEM_TOTAL = sm_value_buf(SM_MEM, n, "MemTotal:");
    SM_MEM_AVAIL = sm_value_buf(SM_MEM, n, "MemAvailable:");
    if (SM_MEM_AVAIL <= 0) { SM_MEM_AVAIL = sm_value_buf(SM_MEM, n, "MemFree:"); }
    SM_MEM_USED = SM_MEM_TOTAL - SM_MEM_AVAIL;
    if (SM_MEM_USED < 0) { SM_MEM_USED = 0; }
    SM_MEM_PCT = 0;
    if (SM_MEM_TOTAL > 0) { SM_MEM_PCT = SM_MEM_USED * 100 / SM_MEM_TOTAL; }

    SM_MEM_SWAP_TOTAL = sm_value_buf(SM_MEM, n, "SwapTotal:");
    int swap_free = sm_value_buf(SM_MEM, n, "SwapFree:");
    SM_MEM_SWAP_USED = SM_MEM_SWAP_TOTAL - swap_free;
    if (SM_MEM_SWAP_USED < 0) { SM_MEM_SWAP_USED = 0; }
}

fn sm_sample_load() -> void {
    int n = sm_read_file("/proc/loadavg", SM_FILE, 255);
    SM_POS = 0;
    SM_LOAD1 = sm_num_next(SM_FILE, n);
    int dec = sm_num_next(SM_FILE, n);
    SM_LOAD1 = SM_LOAD1 * 100 + dec;
    SM_LOAD5 = sm_num_next(SM_FILE, n);
    dec = sm_num_next(SM_FILE, n);
    SM_LOAD5 = SM_LOAD5 * 100 + dec;
    SM_LOAD15 = sm_num_next(SM_FILE, n);
    dec = sm_num_next(SM_FILE, n);
    SM_LOAD15 = SM_LOAD15 * 100 + dec;
    sm_build_loads();
}

fn sm_sample_uptime() -> void {
    int n = sm_read_file("/proc/uptime", SM_FILE, 127);
    SM_POS = 0;
    SM_UPTIME_SEC = sm_num_next(SM_FILE, n);
}

fn sm_sample_cpuinfo() -> void {
    int n = sm_read_file("/proc/cpuinfo", SM_CPUINFO, 16383);
    int pos = sm_find(SM_CPUINFO, n, "cpu MHz");
    if (pos >= 0) {
        SM_POS = pos;
        int mhz = sm_num_next(SM_CPUINFO, n);
        if (mhz > 0) { SM_CPU_MHZ = mhz; }
    }
}

fn sm_sample_temp_path(string path) -> int {
    int n = sm_read_file(path, SM_FILE, 127);
    if (n <= 0) { return 0 - 1; }
    SM_POS = 0;
    int v = sm_num_next(SM_FILE, n);
    if (v <= 0 || v > 200000) { return 0 - 1; }
    return v / 1000;
}

fn sm_sample_temp() -> void {
    SM_CPU_TEMP = sm_sample_temp_path("/sys/class/thermal/thermal_zone0/temp");
    if (SM_CPU_TEMP < 0) { SM_CPU_TEMP = sm_sample_temp_path("/sys/class/hwmon/hwmon0/temp1_input"); }
    if (SM_CPU_TEMP < 0) { SM_CPU_TEMP = sm_sample_temp_path("/sys/class/hwmon/hwmon1/temp1_input"); }
    if (SM_CPU_TEMP < 0) { SM_CPU_TEMP = sm_sample_temp_path("/sys/class/hwmon/hwmon2/temp1_input"); }
    if (SM_CPU_TEMP < 0) { SM_CPU_TEMP = sm_sample_temp_path("/sys/class/hwmon/hwmon3/temp1_input"); }
}

fn sm_sample_network() -> void {
    int n = sm_read_file("/proc/net/dev", SM_NET, 16383);
    int i = 0;
    int rx = 0;
    int tx = 0;
    int ifs = 0;
    while (i < n) {
        int ls = i;
        while (i < n && sm_byte(SM_NET, i) != 10) { i = i + 1; }
        int le = i;
        int colon = sm_find_char(SM_NET, ls, le, 58);
        if (colon >= 0) {
            int ns = ls;
            while (ns < colon && sm_is_space(sm_byte(SM_NET, ns)) == 1) { ns = ns + 1; }
            int is_loop = 0;
            if (ns + 2 == colon && sm_byte(SM_NET, ns) == 108 && sm_byte(SM_NET, ns + 1) == 111) {
                is_loop = 1;
            }
            if (is_loop == 0) {
                SM_POS = colon + 1;
                int f = 0;
                while (f < 16) {
                    int v = sm_num_next(SM_NET, le);
                    if (f == 0) { rx = rx + v; }
                    if (f == 8) { tx = tx + v; }
                    f = f + 1;
                }
                ifs = ifs + 1;
            }
        }
        i = le + 1;
    }
    if (SM_HAVE_NET == 1) {
        int dr = rx - SM_PREV_NET_RX;
        int dt = tx - SM_PREV_NET_TX;
        if (dr < 0) { dr = 0; }
        if (dt < 0) { dt = 0; }
        SM_NET_RX_RATE = dr / 1024;
        SM_NET_TX_RATE = dt / 1024;
    }
    SM_PREV_NET_RX = rx;
    SM_PREV_NET_TX = tx;
    SM_HAVE_NET = 1;
    SM_NET_RX_TOTAL = rx;
    SM_NET_TX_TOTAL = tx;
    SM_NET_IFACES = ifs;
}

fn sm_sample_disk() -> void {
    int n = sm_read_file("/proc/diskstats", SM_DISK, 16383);
    int i = 0;
    int sr = 0;
    int sw = 0;
    int devs = 0;
    while (i < n) {
        int ls = i;
        while (i < n && sm_byte(SM_DISK, i) != 10) { i = i + 1; }
        int le = i;
        SM_POS = ls;
        sm_num_next(SM_DISK, le);
        sm_num_next(SM_DISK, le);
        while (SM_POS < le && sm_is_space(sm_byte(SM_DISK, SM_POS)) == 1) { SM_POS = SM_POS + 1; }
        int ns = SM_POS;
        while (SM_POS < le && sm_is_space(sm_byte(SM_DISK, SM_POS)) == 0) { SM_POS = SM_POS + 1; }
        int ne = SM_POS;
        int include = 1;
        if (ne - ns >= 4) {
            if (sm_byte(SM_DISK, ns) == 108 && sm_byte(SM_DISK, ns + 1) == 111 && sm_byte(SM_DISK, ns + 2) == 111) { include = 0; }
            if (sm_byte(SM_DISK, ns) == 114 && sm_byte(SM_DISK, ns + 1) == 97 && sm_byte(SM_DISK, ns + 2) == 109) { include = 0; }
            if (sm_byte(SM_DISK, ns) == 100 && sm_byte(SM_DISK, ns + 1) == 109 && sm_byte(SM_DISK, ns + 2) == 45) { include = 0; }
        }
        if (include == 1) {
            int f = 0;
            while (f < 10) {
                int v = sm_num_next(SM_DISK, le);
                if (f == 2) { sr = sr + v; }
                if (f == 6) { sw = sw + v; }
                f = f + 1;
            }
            devs = devs + 1;
        }
        i = le + 1;
    }
    int rkb = sr / 2;
    int wkb = sw / 2;
    if (SM_HAVE_DISK == 1) {
        int dr = rkb - SM_PREV_DISK_R;
        int dw = wkb - SM_PREV_DISK_W;
        if (dr < 0) { dr = 0; }
        if (dw < 0) { dw = 0; }
        SM_DISK_READ_RATE = dr;
        SM_DISK_WRITE_RATE = dw;
    }
    SM_PREV_DISK_R = rkb;
    SM_PREV_DISK_W = wkb;
    SM_HAVE_DISK = 1;
    SM_DISK_READ_TOTAL = rkb;
    SM_DISK_WRITE_TOTAL = wkb;
    SM_DISK_DEVICES = devs;
}

fn sm_count_pids() -> int {
    int fd = sys_open("/proc", 0, 0);
    if (fd < 0) { return 0; }
    int count = 0;
    int n = sys_getdents64(fd, SM_DIRBUF, 8192);
    while (n > 0) {
        int pos = 0;
        while (pos < n) {
            int reclen = sm_byte(SM_DIRBUF, pos + 16) + sm_byte(SM_DIRBUF, pos + 17) * 256;
            if (reclen <= 0) { break; }
            int name = pos + 19;
            if (sm_is_digit(sm_byte(SM_DIRBUF, name)) == 1) { count = count + 1; }
            pos = pos + reclen;
        }
        n = sys_getdents64(fd, SM_DIRBUF, 8192);
    }
    sys_close(fd);
    return count;
}

fn sm_sample_processes() -> void {
    int n = sm_read_file("/proc/stat", SM_FILE, 16383);
    int running = sm_value_buf(SM_FILE, n, "procs_running");
    int blocked = sm_value_buf(SM_FILE, n, "procs_blocked");
    int total = sm_count_pids();
    sysmon_proc_set(running, total);
    SM_PROC_RUNNING = sysmon_proc_running();
    SM_PROC_TOTAL = sysmon_proc_total();
    SM_PROC_BLOCKED = blocked;
}

fn sm_hist_push() -> void {
    SM_CPU_HIST[SM_HIST_POS] = SM_CPU_PCT;
    SM_MEM_HIST[SM_HIST_POS] = SM_MEM_PCT;
    SM_HIST_POS = SM_HIST_POS + 1;
    if (SM_HIST_POS >= HIST_LEN) { SM_HIST_POS = 0; }
    if (SM_HIST_COUNT < HIST_LEN) { SM_HIST_COUNT = SM_HIST_COUNT + 1; }
}

fn sm_sample_all() -> void {
    sm_sample_cpu();
    sm_sample_memory();
    sm_sample_load();
    sm_sample_uptime();
    sm_sample_cpuinfo();
    sm_sample_temp();
    sm_sample_network();
    sm_sample_disk();
    sm_sample_processes();
    sm_build_clock();
    sm_hist_push();
}

fn sm_init() -> void {
    SM_FILE = alloc<char>(16384);
    SM_MEM = alloc<char>(16384);
    SM_NET = alloc<char>(16384);
    SM_DISK = alloc<char>(16384);
    SM_CPUINFO = alloc<char>(16384);
    SM_DIRBUF = alloc<char>(8192);
    SM_HOST = alloc<char>(256);
    SM_KERNEL = alloc<char>(256);
    SM_BRAND = alloc<char>(128);
    SM_VENDOR = alloc<char>(64);
    SM_SIZE = alloc<char>(64);
    SM_RATE = alloc<char>(80);
    SM_UPTIME = alloc<char>(64);
    SM_LOAD = alloc<char>(128);
    SM_CLOCK = alloc<char>(32);
    SM_DATE = alloc<char>(32);
    SM_PCT = alloc<char>(16);
    SM_TEMP = alloc<char>(24);

    SM_CPU_HIST = alloc<int>(HIST_LEN);
    SM_MEM_HIST = alloc<int>(HIST_LEN);
    int i = 0;
    while (i < HIST_LEN) {
        SM_CPU_HIST[i] = 0;
        SM_MEM_HIST[i] = 0;
        i = i + 1;
    }

    SM_CPU_CORES = sysmon_cpu_num_cores();
    SM_CPU_BASE_MHZ = sysmon_cpu_mhz();
    SM_CPU_MHZ = SM_CPU_BASE_MHZ;
    sysmon_cpu_vendor_str(SM_VENDOR);
    sysmon_cpu_brand_str(SM_BRAND);
    SM_BRAND = sm_trim_spaces(SM_BRAND);
    SM_VENDOR = sm_trim_spaces(SM_VENDOR);
    if (sm_zlen(SM_BRAND) == 0) { SM_BRAND = "Unknown CPU"; }
    if (sm_zlen(SM_VENDOR) == 0) { SM_VENDOR = "Unknown"; }

    int n = sm_read_file("/proc/sys/kernel/hostname", SM_HOST, 255);
    sm_trim_line(SM_HOST, n);
    if (sm_zlen(SM_HOST) == 0) { SM_HOST = "localhost"; }
    n = sm_read_file("/proc/sys/kernel/osrelease", SM_KERNEL, 255);
    sm_trim_line(SM_KERNEL, n);
    if (sm_zlen(SM_KERNEL) == 0) { SM_KERNEL = "Linux"; }
}

fn sm_text(int x, int y, string s, int color, int scale) -> void {
    int old = gui_get_scale();
    if (scale != old) { gui_set_scale(scale); }
    gui_draw_text_fg(x, y, s, color, 255);
    if (scale != old) { gui_set_scale(old); }
}

fn sm_text_clip(int x, int y, string s, int color, int maxw, int scale) -> void {
    int old = gui_get_scale();
    if (scale != old) { gui_set_scale(scale); }
    dsk_text_clip_fg(x, y, s, color, maxw);
    if (scale != old) { gui_set_scale(old); }
}

fn sm_text_right(int right, int y, string s, int color, int scale) -> void {
    int w = gui_text_width(s, scale);
    sm_text(right - w, y, s, color, scale);
}

fn sm_card(int x, int y, int w, int h, int accent, int bg, int border) -> void {
    gui_fill_rounded_rect(x + 3, y + 5, w, h, 10, gui_rgb(5, 8, 14));
    gui_fill_rounded_rect(x, y, w, h, 10, bg);
    gui_draw_rounded_rect(x, y, w, h, 10, border);
    gui_fill_rounded_rect(x + 20, y, 42, 3, 1, accent);
}

fn sm_bar(int x, int y, int w, int h, int pct, int color, int track) -> void {
    if (pct < 0) { pct = 0; }
    if (pct > 100) { pct = 100; }
    int r = h / 2;
    gui_fill_rounded_rect(x, y, w, h, r, track);
    int fw = w * pct / 100;
    if (fw > 0) {
        if (fw < h) { fw = h; }
        gui_fill_rounded_rect(x, y, fw, h, r, color);
    }
}

fn sm_telemetry(int x, int y, int w, string label, string value, int color, int value_color) -> void {
    sm_text(x, y, label, color, 1);
    sm_text_clip(x + 92, y, value, value_color, w - 92, 1);
}

fn sm_draw_header(int sw, int bg, int text, int muted, int accent, int line) -> void {
    gui_fill_rect(0, 0, sw, 78, bg);
    gui_fill_gradient_v(0, 0, sw, 78, gui_rgb(14, 20, 32), bg);
    gui_fill_rect(0, 78, sw, 1, line);
    gui_fill_rounded_rect(24, 18, 6, 40, 3, accent);
    sm_text(42, 16, "FALCON SYSTEM MONITOR", text, 2);
    sm_text(43, 50, "Live telemetry from procfs and hardware counters", muted, 1);
    sm_text_right(sw - 24, 17, SM_CLOCK, text, 2);
    sm_text_right(sw - 24, 51, SM_DATE, muted, 1);
    sm_text_right(sw - 170, 51, "LIVE", accent, 1);
    gui_fill_circle(sw - 183, 59, 3, accent);
}

fn sm_draw_cpu(int x, int y, int w, int h, int card, int border, int text, int muted, int accent, int green, int track) -> void {
    sm_card(x, y, w, h, accent, card, border);
    sm_text(x + 20, y + 13, "CPU", text, 2);
    sm_text_right(x + w - 20, y + 21, "PROCESSOR", muted, 1);
    sm_text(x + 20, y + 54, sm_fmt_pct(SM_CPU_PCT), text, 3);
    sm_text(x + 20, y + 108, "TOTAL UTILIZATION", muted, 1);
    sm_text_right(x + w - 20, y + 58, sm_fmt_temp(SM_CPU_TEMP), green, 2);
    sm_bar(x + 20, y + 126, w - 40, 10, SM_CPU_PCT, accent, track);
    sm_telemetry(x + 20, y + 149, w - 40, "Cores", dsk_itoa(SM_CPU_CORES), muted, text);
    sm_telemetry(x + 20, y + 169, w - 40, "Clock", dsk_itoa(SM_CPU_MHZ), muted, text);
    int cw = sm_zlen(SM_BRAND) * 8;
    sm_text_clip(x + 20, y + 189, SM_BRAND, muted, w - 40, 1);
    if (cw > w - 40) { sm_text_right(x + w - 20, y + 169, SM_VENDOR, muted, 1); }
}

fn sm_draw_memory(int x, int y, int w, int h, int card, int border, int text, int muted, int purple, int green, int track) -> void {
    sm_card(x, y, w, h, purple, card, border);
    sm_text(x + 20, y + 13, "MEMORY", text, 2);
    sm_text_right(x + w - 20, y + 21, "RAM", muted, 1);
    sm_text(x + 20, y + 54, sm_fmt_pct(SM_MEM_PCT), text, 3);
    sm_text(x + 20, y + 108, "IN USE", muted, 1);
    sm_text_right(x + w - 20, y + 108, sm_fmt_size(SM_MEM_TOTAL), muted, 1);
    sm_bar(x + 20, y + 126, w - 40, 10, SM_MEM_PCT, purple, track);
    sm_telemetry(x + 20, y + 149, w - 40, "Used", sm_fmt_size(SM_MEM_USED), muted, text);
    sm_telemetry(x + 20, y + 169, w - 40, "Available", sm_fmt_size(SM_MEM_AVAIL), muted, green);
    int swap_pct = 0;
    if (SM_MEM_SWAP_TOTAL > 0) { swap_pct = SM_MEM_SWAP_USED * 100 / SM_MEM_SWAP_TOTAL; }
    sm_telemetry(x + 20, y + 189, w - 40, "Swap", sm_fmt_size(SM_MEM_SWAP_USED), muted, text);
    sm_bar(x + 112, y + 192, w - 132, 5, swap_pct, green, track);
}

fn sm_draw_processes(int x, int y, int w, int h, int card, int border, int text, int muted, int yellow, int track) -> void {
    sm_card(x, y, w, h, yellow, card, border);
    sm_text(x + 20, y + 13, "PROCESSES", text, 2);
    sm_text_right(x + w - 20, y + 21, "TASKS", muted, 1);
    sm_text(x + 20, y + 54, dsk_itoa(SM_PROC_RUNNING), text, 3);
    sm_text(x + 20, y + 108, "RUNNING NOW", muted, 1);
    sm_text_right(x + w - 20, y + 58, dsk_itoa(SM_PROC_TOTAL), yellow, 2);
    sm_text_right(x + w - 20, y + 88, "TOTAL", muted, 1);
    sm_telemetry(x + 20, y + 135, w - 40, "Total", dsk_itoa(SM_PROC_TOTAL), muted, text);
    sm_telemetry(x + 20, y + 155, w - 40, "Blocked", dsk_itoa(SM_PROC_BLOCKED), muted, yellow);
    sm_text(x + 20, y + 177, "LOAD AVERAGE", muted, 1);
    sm_text_clip(x + 20, y + 193, SM_LOAD, text, w - 40, 1);
}

fn sm_draw_network(int x, int y, int w, int h, int card, int border, int text, int muted, int green, int blue) -> void {
    sm_card(x, y, w, h, green, card, border);
    sm_text(x + 20, y + 13, "NETWORK", text, 2);
    sm_text_right(x + w - 20, y + 21, dsk_itoa(SM_NET_IFACES), muted, 1);
    sm_text(x + 20, y + 50, "DOWNLOAD", muted, 1);
    sm_text(x + 20, y + 64, sm_fmt_rate(SM_NET_RX_RATE), green, 2);
    sm_text(x + 20, y + 108, "UPLOAD", muted, 1);
    sm_text(x + 20, y + 122, sm_fmt_rate(SM_NET_TX_RATE), blue, 2);
    sm_telemetry(x + 20, y + 163, w - 40, "Received", sm_fmt_size(SM_NET_RX_TOTAL / 1024), muted, text);
    sm_telemetry(x + 20, y + 183, w - 40, "Sent", sm_fmt_size(SM_NET_TX_TOTAL / 1024), muted, text);
}

fn sm_draw_disk(int x, int y, int w, int h, int card, int border, int text, int muted, int orange, int blue) -> void {
    sm_card(x, y, w, h, orange, card, border);
    sm_text(x + 20, y + 13, "DISK I/O", text, 2);
    sm_text_right(x + w - 20, y + 21, dsk_itoa(SM_DISK_DEVICES), muted, 1);
    sm_text(x + 20, y + 50, "READ", muted, 1);
    sm_text(x + 20, y + 64, sm_fmt_rate(SM_DISK_READ_RATE), orange, 2);
    sm_text(x + 20, y + 108, "WRITE", muted, 1);
    sm_text(x + 20, y + 122, sm_fmt_rate(SM_DISK_WRITE_RATE), blue, 2);
    sm_telemetry(x + 20, y + 163, w - 40, "Read", sm_fmt_size(SM_DISK_READ_TOTAL), muted, text);
    sm_telemetry(x + 20, y + 183, w - 40, "Written", sm_fmt_size(SM_DISK_WRITE_TOTAL), muted, text);
}

fn sm_draw_system(int x, int y, int w, int h, int card, int border, int text, int muted, int accent, int green) -> void {
    sm_card(x, y, w, h, accent, card, border);
    sm_text(x + 20, y + 13, "SYSTEM", text, 2);
    sm_text_right(x + w - 20, y + 21, "HOST", muted, 1);
    sm_text_clip(x + 20, y + 49, SM_HOST, accent, w - 40, 2);
    sm_telemetry(x + 20, y + 92, w - 40, "Kernel", SM_KERNEL, muted, text);
    sm_telemetry(x + 20, y + 114, w - 40, "Uptime", sm_fmt_uptime(SM_UPTIME_SEC), muted, text);
    sm_telemetry(x + 20, y + 136, w - 40, "Cores", dsk_itoa(SM_CPU_CORES), muted, text);
    sm_telemetry(x + 20, y + 158, w - 40, "Base", dsk_itoa(SM_CPU_BASE_MHZ), muted, green);
    sm_telemetry(x + 20, y + 180, w - 40, "Vendor", SM_VENDOR, muted, text);
}

fn sm_draw_chart(int x, int y, int w, int h, int* hist, int current, string title, int color, int text, int muted, int track) {
    sm_text(x, y, title, muted, 1);
    sm_text_right(x + w, y - 1, sm_fmt_pct(current), color, 1);
    int cy = y + 22;
    int ch = h - 26;
    if (ch < 20) { ch = 20; }
    gui_fill_rounded_rect(x, cy, w, ch, 5, track);
    int g = 1;
    while (g < 4) {
        int gy = cy + ch * g / 4;
        gui_fill_rect(x + 1, gy, w - 2, 1, gui_rgb(41, 53, 74));
        g = g + 1;
    }
    sm_text(x + 5, cy + 2, "100", muted, 1);
    sm_text(x + 5, cy + ch - 18, "0", muted, 1);

    int shown = SM_HIST_COUNT;
    if (shown > HIST_LEN) { shown = HIST_LEN; }
    int start = SM_HIST_POS - shown;
    while (start < 0) { start = start + HIST_LEN; }
    int step = w / HIST_LEN;
    if (step < 2) { step = 2; }
    int bw = step - 1;
    if (bw < 1) { bw = 1; }
    int i = 0;
    while (i < shown) {
        int idx = start + i;
        while (idx >= HIST_LEN) { idx = idx - HIST_LEN; }
        int v = hist[idx];
        if (v < 0) { v = 0; }
        if (v > 100) { v = 100; }
        int bh = (ch - 6) * v / 100;
        if (bh > 0) {
            int bx = x + 2 + i * step;
            int by = cy + ch - 3 - bh;
            gui_fill_rect(bx, by, bw, bh, color);
        }
        i = i + 1;
    }
}

fn sm_draw_activity(int x, int y, int w, int h, int card, int border, int text, int muted, int accent, int purple, int track) {
    sm_card(x, y, w, h, accent, card, border);
    sm_text(x + 20, y + 13, "ACTIVITY", text, 2);
    sm_text_right(x + w - 20, y + 21, "LAST 90 SECONDS", muted, 1);
    int gap = 32;
    int cw = (w - 60 - gap) / 2;
    int cy = y + 58;
    int ch = h - 84;
    sm_draw_chart(x + 30, cy, cw, ch, SM_CPU_HIST, SM_CPU_PCT, "CPU UTILIZATION", accent, text, muted, track);
    sm_draw_chart(x + 30 + cw + gap, cy, cw, ch, SM_MEM_HIST, SM_MEM_PCT, "MEMORY PRESSURE", purple, text, muted, track);
}

fn sm_draw() -> void {
    int sw = dsk_screen_w();
    int sh = dsk_screen_h();
    int bg = gui_rgb(9, 13, 21);
    int card = gui_rgb(20, 27, 40);
    int border = gui_rgb(39, 52, 72);
    int text = gui_rgb(230, 237, 247);
    int muted = gui_rgb(132, 148, 170);
    int accent = gui_rgb(64, 156, 255);
    int green = gui_rgb(64, 205, 140);
    int purple = gui_rgb(156, 122, 255);
    int yellow = gui_rgb(245, 190, 80);
    int orange = gui_rgb(255, 139, 92);
    int blue = gui_rgb(88, 190, 255);
    int track = gui_rgb(35, 45, 63);
    int line = gui_rgb(29, 40, 58);

    gui_fill_rect(0, 0, sw, sh, bg);
    sm_draw_header(sw, bg, text, muted, accent, line);

    int margin = 24;
    int gap = 16;
    int top = 94;
    int bottom_h = 190;
    int bottom_gap = 16;
    int card_h = (sh - top - margin - bottom_h - bottom_gap * 2) / 2;
    if (card_h < 150) { card_h = 150; }
    int colw = (sw - margin * 2 - gap * 2) / 3;
    int x1 = margin;
    int x2 = x1 + colw + gap;
    int x3 = x2 + colw + gap;

    sm_draw_cpu(x1, top, colw, card_h, card, border, text, muted, accent, green, track);
    sm_draw_memory(x2, top, colw, card_h, card, border, text, muted, purple, green, track);
    sm_draw_processes(x3, top, colw, card_h, card, border, text, muted, yellow, track);

    int row2 = top + card_h + gap;
    sm_draw_network(x1, row2, colw, card_h, card, border, text, muted, green, blue);
    sm_draw_disk(x2, row2, colw, card_h, card, border, text, muted, orange, blue);
    sm_draw_system(x3, row2, colw, card_h, card, border, text, muted, accent, green);

    int by = row2 + card_h + bottom_gap;
    int bh = sh - by - margin;
    if (bh < 120) { bh = 120; }
    sm_draw_activity(margin, by, sw - margin * 2, bh, card, border, text, muted, accent, purple, track);
}

fn main() -> int {
    int win = dsk_init_app(1180, 760, "Falcon System Monitor");
    if (win < 0) { return 1; }
    dsk_set_taskbar(0);
    dsk_theme_dark();
    sm_init();

    int tick = 0;
    while (dsk_running() == 1) {
        if (tick <= 0) {
            sm_sample_all();
            tick = 12;
        }
        tick = tick - 1;
        dsk_update();
        sm_build_clock();
        sm_draw();
        if (gui_is_x11() == 0) { dsk_draw_cursor(gui_mouse_x(), gui_mouse_y()); }
        gui_present();
        sleep_ms(80);
    }

    dsk_shutdown();
    return 0;
}
