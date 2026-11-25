// sysmon/process.mg - SysMon Process Monitoring (OS-writable counters, heap-free)

use "sysmon/utils.mg";

struct ProcInfo {
    int running;
    int total;
    int sleeping;
    int zombie;
};

static int S_PROC_RUNNING = 1;
static int S_PROC_TOTAL = 1;
static int S_PROC_SLEEPING = 0;
static int S_PROC_ZOMBIE = 0;

fn sysmon_proc_running() -> int {
    return S_PROC_RUNNING;
}

fn sysmon_proc_total() -> int {
    return S_PROC_TOTAL;
}

fn sysmon_proc_set(int running, int total) -> void {
    if (running >= 0) { S_PROC_RUNNING = running; }
    if (total >= 0) { S_PROC_TOTAL = total; }
}

fn sysmon_get_proc_info_into(ProcInfo* p) -> void {
    p.running = S_PROC_RUNNING;
    p.total = S_PROC_TOTAL;
    p.sleeping = S_PROC_SLEEPING;
    p.zombie = S_PROC_ZOMBIE;
}

class SysProcess {
    fn getRunning() -> int { return S_PROC_RUNNING; }
    fn getTotal() -> int { return S_PROC_TOTAL; }
    fn setCount(int running, int total) -> void { sysmon_proc_set(running, total); }
    fn getInfo() -> ProcInfo* {
        ProcInfo pi;
        sysmon_get_proc_info_into(&pi);
        return cast<ProcInfo*>(&pi);
    }
};