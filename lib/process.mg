// lib/process.mg - minimal process spawning helpers for Magnetar/Linux

extern fn sys_fork() -> int;
extern fn sys_execve(string path, char** argv, char** envp) -> int;
extern fn sys_wait4(int pid, int* wstatus, int options, char* rusage) -> int;
extern fn sys_exit(int code) -> void;
extern fn print_str(string s) -> void;

fn proc_spawn(string path, char** argv) -> int {
    int pid = sys_fork();
    if (pid < 0) { return -1; }
    if (pid == 0) {
        sys_execve(path, argv, null);
        print_str("[process] exec failed: ");
        print_str(path);
        print_str("\n");
        sys_exit(127);
    }
    return pid;
}

fn proc_wait(int pid) -> int {
    int status = 0;
    sys_wait4(pid, &status, 0, null);
    return status;
}

fn proc_run(string path, char** argv) -> int {
    int pid = proc_spawn(path, argv);
    if (pid < 0) { return -1; }
    return proc_wait(pid);
}
