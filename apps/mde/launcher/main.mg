// MDE Launcher - app launcher client
// Build: ./magc mde/launcher/main.mg -o build/mde-launcher
use "gui.mg";
use "lib/ipc.mg";
use "lib/mde_ipc.mg";
extern fn sleep_ms(int ms) -> void;
extern fn print_str(string s) -> void;
extern fn sys_fork() -> int;
extern fn sys_execve(string path, char** argv, char** envp) -> int;
extern fn sys_exit(int code) -> void;

fn launch(string path) -> void {
    int pid = sys_fork();
    if (pid == 0) {
        char** argv = alloc<char*>(2);
        argv[0] = cast<char*>(path);
        argv[1] = null;
        sys_execve(path, argv, null);
        sys_exit(127);
    }
}

fn main() -> int {
    // Notify compositor (best effort)
    int fd = ipc_client_connect("/tmp/mde-compositor.sock");
    if (fd >= 0) {
        ipc_send_line(fd, mde_req(1, "hello", "{\"role\":\"launcher\",\"name\":\"mde-launcher\"}"));
        char* buf = alloc<char>(1024);
        ipc_recv_line(fd, buf, 1024);
        ipc_close(fd);
    }

    int err = dsk_init_window(560, 360, "MDE Launcher");
    if (err != 0) { return err; }
    dsk_set_theme(1);
    int win = dsk_root();
    dsk_add_widget(win, WT_LABEL, 24, 20, 300, 24, "Applications", 0, 0, 0);
    dsk_add_widget(win, WT_SEPARATOR, 24, 52, 500, 2, "", 0, 0, 0);
    int b_files = dsk_add_widget(win, WT_BUTTON, 24, 72, 240, 40, "Files", 0, 0, 0);
    int b_settings = dsk_add_widget(win, WT_BUTTON, 284, 72, 240, 40, "Settings", 0, 0, 0);
    int b_panel = dsk_add_widget(win, WT_BUTTON, 24, 124, 240, 40, "Panel", 0, 0, 0);
    int b_hello = dsk_add_widget(win, WT_BUTTON, 284, 124, 240, 40, "IPC Hello", 0, 0, 0);
    int msg = dsk_add_widget(win, WT_LABEL, 24, 190, 500, 20, "Select an app to launch.", 0, 0, 0);
    int quit = dsk_add_widget(win, WT_BUTTON, 24, 290, 120, 34, "Close", 0, 0, 0);
    while (dsk_running() == 1) {
        int c = dsk_frame();
        if (c == b_files) { launch("./build/mde-files"); dsk_widget_set_label(msg, "Launched Files"); }
        if (c == b_settings) { launch("./build/mde-settings"); dsk_widget_set_label(msg, "Launched Settings"); }
        if (c == b_panel) { launch("./build/mde-panel"); dsk_widget_set_label(msg, "Launched Panel"); }
        if (c == b_hello) { launch("./build/mde-hello"); dsk_widget_set_label(msg, "Launched IPC hello"); }
        if (c == quit || gui_close_requested() == 1) { dsk_stop(); }
    }
    dsk_shutdown();
    return 0;
}
