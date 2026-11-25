// sysmon/pci.mg - SysMon PCI bus enumeration (hardware-direct, heap-free, no bitwise ops)
//
// Walks the PCI configuration space through the 0xCF8/0xCFC mechanism.
// Stateless: every call re-reads the hardware, so the kernel can iterate the
// bus without any heap or static buffers.

use "sysmon/utils.mg";

extern fn inl(int port) -> int;
extern fn outl(int port, int value) -> void;

fn sysmon_pci_present(int bus, int dev, int func) -> int {
    int v = sysmon_pci_conf_read32(bus, dev, func, 0);
    if (v == -1 || v == 0) { return 0; }
    return 1;
}

fn sysmon_pci_vendor(int bus, int dev, int func) -> int {
    int v = sysmon_pci_conf_read32(bus, dev, func, 0);
    return sysmon_bits(v, 0, 65535);
}

fn sysmon_pci_device_id(int bus, int dev, int func) -> int {
    int v = sysmon_pci_conf_read32(bus, dev, func, 0);
    return sysmon_bits(v, 16, 65535);
}

fn sysmon_pci_class(int bus, int dev, int func) -> int {
    int c = sysmon_pci_conf_read32(bus, dev, func, 8);
    return sysmon_bits(c, 8, 65535);       // base class + sub class
}

fn sysmon_pci_base_class(int bus, int dev, int func) -> int {
    int c = sysmon_pci_conf_read32(bus, dev, func, 8);
    return sysmon_bits(c, 16, 255);
}

fn sysmon_pci_sub_class(int bus, int dev, int func) -> int {
    int c = sysmon_pci_conf_read32(bus, dev, func, 8);
    return sysmon_bits(c, 8, 255);
}

fn sysmon_pci_header_type(int bus, int dev, int func) -> int {
    int d = sysmon_pci_conf_read32(bus, dev, func, 12);
    return sysmon_bits(d, 0, 255);
}

fn sysmon_pci_multi_function(int bus, int dev, int func) -> int {
    int h = sysmon_pci_header_type(bus, dev, func);
    return sysmon_bits(h, 7, 1);
}

// Number of devices/functions present on bus 0.
fn sysmon_pci_scan_count() -> int {
    int count = 0;
    int dev = 0;
    while (dev < 32) {
        if (sysmon_pci_present(0, dev, 0) == 1) {
            count = count + 1;
            if (sysmon_pci_multi_function(0, dev, 0) == 1) {
                int func = 1;
                while (func < 8) {
                    if (sysmon_pci_present(0, dev, func) == 1) { count = count + 1; }
                    func = func + 1;
                }
            }
        }
        dev = dev + 1;
    }
    return count;
}

// Find the Nth present function on bus 0 (0-based). Returns 1 and fills
// out[0..3] = bus,dev,func,vendor if found; else returns 0.
fn sysmon_pci_at(int index, int* out) -> int {
    int count = 0;
    int dev = 0;
    while (dev < 32) {
        if (sysmon_pci_present(0, dev, 0) == 1) {
            if (count == index) {
                out[0] = 0; out[1] = dev; out[2] = 0;
                out[3] = sysmon_pci_vendor(0, dev, 0);
                return 1;
            }
            count = count + 1;
            if (sysmon_pci_multi_function(0, dev, 0) == 1) {
                int func = 1;
                while (func < 8) {
                    if (sysmon_pci_present(0, dev, func) == 1) {
                        if (count == index) {
                            out[0] = 0; out[1] = dev; out[2] = func;
                            out[3] = sysmon_pci_vendor(0, dev, func);
                            return 1;
                        }
                        count = count + 1;
                    }
                    func = func + 1;
                }
            }
        }
        dev = dev + 1;
    }
    return 0;
}

class SysPci {
    fn getDeviceCount() -> int { return sysmon_pci_scan_count(); }
    fn getAt(int index, int* out) -> int { return sysmon_pci_at(index, out); }
    fn getVendor(int bus, int dev, int func) -> int { return sysmon_pci_vendor(bus, dev, func); }
    fn getDeviceId(int bus, int dev, int func) -> int { return sysmon_pci_device_id(bus, dev, func); }
    fn getClass(int bus, int dev, int func) -> int { return sysmon_pci_class(bus, dev, func); }
};