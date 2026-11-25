// sysmon/network.mg - SysMon Network Monitoring (hardware-direct, heap-free, no bitwise ops)

use "sysmon/utils.mg";

extern fn inl(int port) -> int;
extern fn outl(int port, int value) -> void;

struct NetStats {
    int rx_bytes;
    int tx_bytes;
    int link_up;
    int rx_packets;
    int tx_packets;
};

static int S_NET_BAR = 0;
static int S_NET_DEV = -1;
static int S_NET_PREV_RX = 0;
static int S_NET_PREV_TX = 0;

fn sysmon_net_find_e1000() -> int {
    int dev = 0;
    while (dev < 32) {
        int v = sysmon_pci_conf_read32(0, dev, 0, 0);
        if (v != -1 && v != 0) {
            int class_code = sysmon_pci_conf_read32(0, dev, 0, 8);
            int pci_class = sysmon_bits(class_code, 8, 65535);
            if (pci_class == 512) {
                int vendor = sysmon_bits(v, 0, 65535);
                int device = sysmon_bits(v, 16, 65535);
                if (vendor == 32902 && (device == 4110 || device == 4111 || device == 5427 || device == 5378 || device == 5379)) {
                    S_NET_DEV = dev;
                    int bar0 = sysmon_pci_conf_read32(0, dev, 0, 16);
                    S_NET_BAR = bar0 - (bar0 / 16) * 16;
                    int cmd = sysmon_pci_conf_read32(0, dev, 0, 4);
                    cmd = cmd + 6;
                    sysmon_pci_conf_write32(0, dev, 0, 4, cmd);
                    return 1;
                }
            }
        }
        dev = dev + 1;
    }
    return 0;
}

fn sysmon_net_open() -> int {
    if (S_NET_BAR != 0) { return 1; }
    return sysmon_net_find_e1000();
}

fn sysmon_net_link_up() -> int {
    if (S_NET_BAR == 0) { return 0; }
    int status = *(cast<int*>(S_NET_BAR + 8));
    if (sysmon_bits(status, 1, 1) != 0) { return 1; }
    return 0;
}

fn sysmon_net_stats_into(int* rx, int* tx) -> void {
    if (S_NET_BAR == 0) {
        *rx = 0;
        *tx = 0;
        return;
    }
    int gorcl = *(cast<int*>(S_NET_BAR + 16520));
    int gorch = *(cast<int*>(S_NET_BAR + 16524));
    int gotcl = *(cast<int*>(S_NET_BAR + 16528));
    int gotch = *(cast<int*>(S_NET_BAR + 16532));
    *rx = gorcl;
    if (gorch > 0) { *rx = *rx + (gorch * 4294967); }
    *tx = gotcl;
    if (gotch > 0) { *tx = *tx + (gotch * 4294967); }
}

fn sysmon_get_net_stats_into(NetStats* ns) -> void {
    ns.rx_bytes = 0;
    ns.tx_bytes = 0;
    ns.link_up = 0;
    ns.rx_packets = 0;
    ns.tx_packets = 0;
    if (sysmon_net_open() == 1) {
        ns.link_up = sysmon_net_link_up();
        sysmon_net_stats_into(&ns.rx_bytes, &ns.tx_bytes);
    }
}

class SysNetwork {
    int prev_rx;
    int prev_tx;

    fn init() -> void {
        this.prev_rx = 0;
        this.prev_tx = 0;
        sysmon_net_open();
    }

    fn getRxTotalKB() -> int {
        int rx = 0; int tx = 0;
        sysmon_net_stats_into(&rx, &tx);
        return rx / 1024;
    }

    fn getTxTotalKB() -> int {
        int rx = 0; int tx = 0;
        sysmon_net_stats_into(&rx, &tx);
        return tx / 1024;
    }

    fn getLinkState() -> int {
        return sysmon_net_link_up();
    }

    fn getRxRateKB() -> int {
        int rx = 0; int tx = 0;
        sysmon_net_stats_into(&rx, &tx);
        if (this.prev_rx == 0) { this.prev_rx = rx; return 0; }
        int dr = rx - this.prev_rx;
        this.prev_rx = rx;
        if (dr < 0) { dr = 0; }
        return dr / 1024;
    }

    fn getTxRateKB() -> int {
        int rx = 0; int tx = 0;
        sysmon_net_stats_into(&rx, &tx);
        if (this.prev_tx == 0) { this.prev_tx = tx; return 0; }
        int dt = tx - this.prev_tx;
        this.prev_tx = tx;
        if (dt < 0) { dt = 0; }
        return dt / 1024;
    }
};