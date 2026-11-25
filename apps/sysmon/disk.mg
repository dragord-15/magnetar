// sysmon/disk.mg - SysMon Disk Monitoring (hardware-direct, heap-free, no bitwise ops)

use "sysmon/utils.mg";

extern fn inb(int port) -> int;
extern fn outb(int port, int value) -> void;
extern fn inw(int port) -> int;
extern fn outw(int port, int value) -> void;

static int S_DISK_BASE_0 = 0;
static int S_DISK_BASE_1 = 0;
static int S_DISK_BASE_2 = 0;
static int S_DISK_BASE_3 = 0;
static int S_DISK_UNIT_0 = 0;
static int S_DISK_UNIT_1 = 0;
static int S_DISK_UNIT_2 = 0;
static int S_DISK_UNIT_3 = 0;
static int S_DISK_COUNT = 0;

fn sysmon_disk_get_base(int idx) -> int {
    if (idx == 0) { return S_DISK_BASE_0; }
    if (idx == 1) { return S_DISK_BASE_1; }
    if (idx == 2) { return S_DISK_BASE_2; }
    return S_DISK_BASE_3;
}

fn sysmon_disk_set_base(int idx, int val) -> void {
    if (idx == 0) { S_DISK_BASE_0 = val; }
    else if (idx == 1) { S_DISK_BASE_1 = val; }
    else if (idx == 2) { S_DISK_BASE_2 = val; }
    else { S_DISK_BASE_3 = val; }
}

fn sysmon_disk_get_unit(int idx) -> int {
    if (idx == 0) { return S_DISK_UNIT_0; }
    if (idx == 1) { return S_DISK_UNIT_1; }
    if (idx == 2) { return S_DISK_UNIT_2; }
    return S_DISK_UNIT_3;
}

fn sysmon_disk_set_unit(int idx, int val) -> void {
    if (idx == 0) { S_DISK_UNIT_0 = val; }
    else if (idx == 1) { S_DISK_UNIT_1 = val; }
    else if (idx == 2) { S_DISK_UNIT_2 = val; }
    else { S_DISK_UNIT_3 = val; }
}

fn sysmon_ata_wait_ready(int bse) -> int {
    int tries = 0;
    while (tries < 20000) {
        int st = inb(bse + 7);
        if (sysmon_bits(st, 7, 1) == 0) { return 1; }
        tries = tries + 1;
    }
    return 0;
}

fn sysmon_ata_wait_drq(int bse) -> int {
    int tries = 0;
    while (tries < 20000) {
        int st = inb(bse + 7);
        if (sysmon_bits(st, 3, 1) != 0) { return 1; }
        if (sysmon_bits(st, 0, 1) != 0) { return 0; }
        tries = tries + 1;
    }
    return 0;
}

fn sysmon_ata_identify(int bse, int unit) -> int {
    outb(bse + 6, 160 + unit * 16);
    sysmon_ata_wait_ready(bse);
    outb(bse + 7, 0xEC);
    if (sysmon_ata_wait_ready(bse) == 0) { return 0; }
    if (sysmon_ata_wait_drq(bse) == 0) { return 0; }
    int st = inb(bse + 7);
    if (sysmon_bits(st, 0, 1) != 0) { return 0; }
    return 1;
}

fn sysmon_ata_identify_packet(int bse, int unit) -> int {
    outb(bse + 6, 160 + unit * 16);
    sysmon_ata_wait_ready(bse);
    outb(bse + 7, 0xA1);
    if (sysmon_ata_wait_ready(bse) == 0) { return 0; }
    if (sysmon_ata_wait_drq(bse) == 0) { return 0; }
    int st = inb(bse + 7);
    if (sysmon_bits(st, 0, 1) != 0) { return 0; }
    return 1;
}

fn sysmon_read_identify_sectors(int bse) -> int {
    int tries = 0;
    while (tries < 256) {
        int w = inw(bse);
        if (tries == 60) { return w; }
        if (tries == 61) { return w * 65536; }
        tries = tries + 1;
    }
    return 0;
}

fn sysmon_disk_count() -> int {
    return S_DISK_COUNT;
}

fn sysmon_probe_disks() -> int {
    int count = 0;
    int base0 = 496;
    int base1 = 368;
    int ch = 0;
    while (ch < 2) {
        int bse = 0;
        if (ch == 0) { bse = base0; } else { bse = base1; }
        int unit = 0;
        while (unit < 2) {
            if (sysmon_ata_identify(bse, unit) == 1) {
                sysmon_disk_set_base(count, bse);
                sysmon_disk_set_unit(count, unit);
                count = count + 1;
            } else if (sysmon_ata_identify_packet(bse, unit) == 1) {
                sysmon_disk_set_base(count, bse);
                sysmon_disk_set_unit(count, unit);
                count = count + 1;
            }
            unit = unit + 1;
        }
        ch = ch + 1;
    }
    S_DISK_COUNT = count;
    return count;
}

fn sysmon_get_disk_info(int index, int* out) -> int {
    if (index < 0 || index >= S_DISK_COUNT) { return 0; }
    int bse = sysmon_disk_get_base(index);
    int unit = sysmon_disk_get_unit(index);
    outb(bse + 6, 160 + unit * 16);
    sysmon_ata_wait_ready(bse);
    outb(bse + 7, 0xEC);
    if (sysmon_ata_wait_ready(bse) == 0 || sysmon_ata_wait_drq(bse) == 0) {
        outb(bse + 7, 0xA1);
        if (sysmon_ata_wait_ready(bse) == 0 || sysmon_ata_wait_drq(bse) == 0) {
            return 0;
        }
    }
    int sectors = sysmon_read_identify_sectors(bse);
    out[0] = 1;
    out[1] = sectors;
    out[2] = bse;
    out[3] = unit;
    return 1;
}

class SysDisk {
    fn getCount() -> int {
        if (S_DISK_COUNT == 0) { sysmon_probe_disks(); }
        return S_DISK_COUNT;
    }
    fn getInfo(int index, int* out) -> int {
        if (S_DISK_COUNT == 0) { sysmon_probe_disks(); }
        return sysmon_get_disk_info(index, out);
    }
};