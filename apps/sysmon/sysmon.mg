// sysmon/sysmon.mg - Main SysMon Aggregator

use "sysmon/utils.mg";
use "sysmon/memory.mg";
use "sysmon/cpu.mg";
use "sysmon/battery.mg";
use "sysmon/temperature.mg";
use "sysmon/network.mg";
use "sysmon/disk.mg";
use "sysmon/process.mg";
use "sysmon/system_info.mg";
use "sysmon/rtc.mg";
use "sysmon/pci.mg";

class SysMonitor {
    SysCpu* cpu;
    SysMemory* memory;
    SysBattery* battery;
    SysTemperature* temp;
    SysNetwork* net;
    SysDisk* disk;
    SysProcess* proc;
    SysInfo* info;
    SysClock* clock;
    SysPci* pci;

    fn _init() -> void {
        this.cpu = new SysCpu;
        this.memory = new SysMemory;
        this.battery = new SysBattery;
        this.temp = new SysTemperature;
        this.net = new SysNetwork;
        this.disk = new SysDisk;
        this.proc = new SysProcess;
        this.info = new SysInfo;
        this.clock = new SysClock;
        this.pci = new SysPci;
    }
    
    fn _destroy() -> void {
        delete this.cpu;
        delete this.memory;
        delete this.battery;
        delete this.temp;
        delete this.net;
        delete this.disk;
        delete this.proc;
        delete this.info;
        delete this.clock;
        delete this.pci;
    }
};
