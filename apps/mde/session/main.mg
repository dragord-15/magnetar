// MDE Session - supervises compositor, panel, launcher.
// Build: ./magc mde/session/main.mg -o build/mde-session

use "lib/cli.mg";

extern fn print_str(string s) -> void;
extern fn sys_fork() -> int;
extern fn sys_execve(string path, char** argv, char** envp) -> int;
extern fn sys_wait4(int pid, int* wstatus, int options, char* rusage) -> int;
extern fn sys_exit(int code) -> void;
extern fn sys_access(string path, int mode) -> int;
extern fn sleep_ms(int ms) -> void;

fn exists(string path) -> bool { return sys_access(path, 0) == 0; }

fn resolve(string preferred, string fb1, string fb2) -> string {
    if (exists(preferred)) { return preferred; }
    if (exists(fb1)) { return fb1; }
    return fb2;
}

fn spawn_bg(string path, char** argv) -> int {
    int pid = sys_fork();
    if (pid < 0) { return -1; }
    if (pid == 0) {
        sys_execve(path, argv, null);
        print_str("[mde-session] exec failed: "); print_str(path); print_str("\n");
        sys_exit(127);
    }
    return pid;
}

fn waitpid(int pid) -> int {
    int status = 0;
    sys_wait4(pid, &status, 0, null);
    return status;
}

fn main(int argc, char** argv) -> int {
    string mode = cli_get_option(argc, argv, "--mode=", "dev");
    string comp = cli_get_option(argc, argv, "--compositor=", "/usr/lib/mde/mde-compositor");
    comp = resolve(comp, "/tmp/mde-compositor", "./build/mde-compositor");
    string panel = resolve("/usr/lib/mde/mde-panel", "/tmp/mde-panel", "./build/mde-panel");
    string launcher = resolve("/usr/lib/mde/mde-launcher", "/tmp/mde-launcher", "./build/mde-launcher");

    print_str("[mde-session] mode="); print_str(mode); print_str("\n");
    print_str("[mde-session] compositor="); print_str(comp); print_str("\n");

    // Start compositor
    char** cargv = alloc<char*>(4);
    cargv[0] = cast<char*>(comp);
    if (mode == "dev") { cargv[1] = cast<char*>("--dev"); cargv[2] = null; }
    else { cargv[1] = null; }
    int cpid = spawn_bg(comp, cargv);
    if (cpid < 0) { print_str("[mde-session] failed to spawn compositor\n"); return 1; }
    print_str("[mde-session] compositor started\n");

    // Give compositor time to create IPC socket
    sleep_ms(500);

    // Start panel (optional)
    int ppid = 0 - 1;
    if (exists(panel)) {
        char** pargv = alloc<char*>(2);
        pargv[0] = cast<char*>(panel);
        pargv[1] = null;
        ppid = spawn_bg(panel, pargv);
        print_str("[mde-session] panel started\n");
    }

    // Start launcher (optional, hidden by default; app handles itself)
    // Launcher is on-demand in MVP; not auto-spawned.

    // Wait for compositor (main process)
    waitpid(cpid);
    print_str("[mde-session] compositor exited\n");

    // TODO: signal/terminate panel/launcher cleanly
    if (ppid > 0) { waitpid(ppid); }
    return 0;
}
