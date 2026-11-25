// MDE Display Manager - boots greeter then session on Debian-family systems.
// MVP: greeter UI + session spawn; real PAM/logind/seat integration planned.
// Build: ./magc mde/display-manager/main.mg -o build/mde-display-manager

use "lib/cli.mg";

extern fn print_str(string s) -> void;
extern fn sys_fork() -> int;
extern fn sys_execve(string path, char** argv, char** envp) -> int;
extern fn sys_wait4(int pid, int* wstatus, int options, char* rusage) -> int;
extern fn sys_exit(int code) -> void;
extern fn sys_access(string path, int mode) -> int;
extern fn sys_setsid() -> int;

fn exists(string path) -> bool { return sys_access(path, 0) == 0; }

fn spawn_wait(string path, char** argv) -> int {
    int pid = sys_fork();
    if (pid < 0) { return -1; }
    if (pid == 0) {
        sys_setsid();
        sys_execve(path, argv, null);
        print_str("[mde-dm] exec failed\n");
        sys_exit(127);
    }
    int st = 0;
    sys_wait4(pid, &st, 0, null);
    return st;
}

fn resolve(string preferred, string fallback1, string fallback2) -> string {
    if (exists(preferred)) { return preferred; }
    if (exists(fallback1)) { return fallback1; }
    return fallback2;
}

fn main(int argc, char** argv) -> int {
    string greeter = cli_get_option(argc, argv, "--greeter=", "/usr/lib/mde/mde-greeter");
    greeter = resolve(greeter, "/tmp/mde-greeter", "./build/mde-greeter");
    string session = cli_get_option(argc, argv, "--session=", "/usr/lib/mde/mde-session");
    session = resolve(session, "/tmp/mde-session", "./build/mde-session");

    print_str("[mde-dm] greeter="); print_str(greeter); print_str("\n");
    print_str("[mde-dm] session="); print_str(session); print_str("\n");

    int nogreeter = cli_has_flag(argc, argv, "--no-greeter");
    if (nogreeter == 0 && exists(greeter)) {
        char** gargv = alloc<char*>(2);
        gargv[0] = cast<char*>(greeter);
        gargv[1] = null;
        int gst = spawn_wait(greeter, gargv);
        print_str("[mde-dm] greeter exited\n");
        // if greeter exits non-zero, do not start session
        if (gst != 0) { return gst; }
    }

    char** sargv = alloc<char*>(4);
    sargv[0] = cast<char*>(session);
    sargv[1] = cast<char*>("--mode=dev");
    sargv[2] = null;
    int sst = spawn_wait(session, sargv);
    print_str("[mde-dm] session exited\n");
    return 0;
}
