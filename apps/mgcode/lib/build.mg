extern fn sys_fork() -> int;
extern fn sys_dup2(int oldfd, int newfd) -> int;
extern fn sys_execve(string path, char** argv, char** envp) -> int;
extern fn sys_wait4(int pid, int* wstatus, int options, char* rusage) -> int;
extern fn sys_exit(int code) -> void;

static char* BUILD_ENV_BUF;
static char** BUILD_ENV_PTRS;
static int BUILD_ENV_COUNT;
static int BUILD_STATUS;
static char* BUILD_MERGED_PATH;

fn build_init() -> void {
    BUILD_ENV_BUF = alloc<char>(8192);
    *(BUILD_ENV_BUF) = 0;
    BUILD_ENV_PTRS = alloc<char*>(256);
    BUILD_ENV_PTRS[0] = null;
    BUILD_ENV_COUNT = 0;
    BUILD_STATUS = -1;
    BUILD_MERGED_PATH = alloc<char>(512);
    char* mp = cast<char*>("/tmp/mgcode_merged.mg");
    int i = 0;
    while (*(mp + i) != 0) { *(BUILD_MERGED_PATH + i) = *(mp + i); i = i + 1; }
    *(BUILD_MERGED_PATH + i) = 0;
}

fn build_env_byte(char* p, int i) -> int {
    int v = cast<int>(*(p + i));
    if (v < 0) { v = v + 256; }
    return v;
}

fn build_load_env() -> void {
    BUILD_ENV_COUNT = 0;
    int fd = sys_open("/proc/self/environ", 0, 0);
    if (fd < 0) {
        BUILD_ENV_PTRS[0] = cast<char*>("PATH=/usr/local/bin:/usr/bin:/bin");
        BUILD_ENV_PTRS[1] = null;
        BUILD_ENV_COUNT = 1;
        return;
    }
    int n = sys_read(fd, BUILD_ENV_BUF, 8191);
    sys_close(fd);
    if (n <= 0) {
        BUILD_ENV_PTRS[0] = cast<char*>("PATH=/usr/local/bin:/usr/bin:/bin");
        BUILD_ENV_PTRS[1] = null;
        BUILD_ENV_COUNT = 1;
        return;
    }
    int i = 0;
    while (i < n && BUILD_ENV_COUNT < 250) {
        if (build_env_byte(BUILD_ENV_BUF, i) != 0) {
            BUILD_ENV_PTRS[BUILD_ENV_COUNT] = BUILD_ENV_BUF + i;
            BUILD_ENV_COUNT = BUILD_ENV_COUNT + 1;
        }
        while (i < n && build_env_byte(BUILD_ENV_BUF, i) != 0) { i = i + 1; }
        i = i + 1;
    }
    BUILD_ENV_PTRS[BUILD_ENV_COUNT] = null;
}

fn build_log_path() -> string {
    return "/tmp/mgcode_build.log";
}

fn build_output_path() -> string {
    return "/tmp/mgcode_build";
}

fn build_merged_path() -> string {
    return cast<string>(BUILD_MERGED_PATH);
}

fn build_run_path(string src, string outp) -> int {
    if (len(src) == 0) {
        BUILD_STATUS = -1;
        return 0;
    }
    if (BUILD_ENV_COUNT == 0) { build_load_env(); }
    int fd = sys_open(build_log_path(), 577, 420);
    int pid = sys_fork();
    if (pid == 0) {
        if (fd >= 0) {
            sys_dup2(fd, 1);
            sys_dup2(fd, 2);
            if (fd > 2) { sys_close(fd); }
        }
        char** argv = alloc<char*>(12);
        argv[0] = cast<char*>("magc");
        argv[1] = cast<char*>(src);
        argv[2] = cast<char*>("-o");
        argv[3] = cast<char*>(outp);
        argv[4] = null;
        sys_execve("/usr/local/bin/magc", argv, BUILD_ENV_PTRS);
        argv[0] = cast<char*>("magc");
        sys_execve("/usr/bin/magc", argv, BUILD_ENV_PTRS);
        char** eargv = alloc<char*>(12);
        eargv[0] = cast<char*>("env");
        eargv[1] = cast<char*>("magc");
        eargv[2] = cast<char*>(src);
        eargv[3] = cast<char*>("-o");
        eargv[4] = cast<char*>(outp);
        eargv[5] = null;
        sys_execve("/usr/bin/env", eargv, BUILD_ENV_PTRS);
        sys_exit(127);
    }
    if (fd >= 0) { sys_close(fd); }
    int status = 0;
    sys_wait4(pid, &status, 0, null);
    BUILD_STATUS = status / 256;
    if (BUILD_STATUS == 0) { return 1; }
    return 0;
}

fn build_run() -> int {
    if (doc_path_len() == 0) {
        BUILD_STATUS = -1;
        return 0;
    }
    doc_flush();
    return build_run_path(doc_path(), build_output_path());
}

fn build_last_status() -> int {
    return BUILD_STATUS;
}
