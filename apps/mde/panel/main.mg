// MDE Panel - top bar client (MVP)
// Connects to compositor IPC; for now also shows a standalone panel window in dev.
// Build: ./magc mde/panel/main.mg -o build/mde-panel
use "gui.mg";
use "lib/ipc.mg";
use "lib/mde_ipc.mg";
use "lib/json.mg";
extern fn sleep_ms(int ms) -> void;
extern fn get_timestamp() -> int;
extern fn os_get_env(string key) -> string;
extern fn print_str(string s) -> void;

static char* FMT;
fn copy_to(char* dst, int di, string src) -> int {
    char* p = cast<char*>(src); int j=0; while(*(p+j)!=0){*(dst+di)=*(p+j); di=di+1; j=j+1;} return di;
}
fn two(int v) -> string { return dsk_itoa_pad(v, 2); }
fn fmt_time(int ts) -> string {
    int day=ts/86400; int secs=ts-day*86400; int h=secs/3600; int m=(secs-h*3600)/60; int s=secs-h*3600-m*60;
    int i=0; i=copy_to(FMT,i,two(h)); *(FMT+i)=58; i=i+1; i=copy_to(FMT,i,two(m)); *(FMT+i)=58; i=i+1; i=copy_to(FMT,i,two(s)); *(FMT+i)=0;
    return cast<string>(FMT);
}

fn main() -> int {
    FMT = alloc<char>(32);
    // Try IPC hello
    int fd = ipc_client_connect("/tmp/mde-compositor.sock");
    if (fd >= 0) {
        ipc_send_line(fd, mde_req(1, "hello", "{\"role\":\"panel\",\"name\":\"mde-panel\"}"));
        char* buf = alloc<char>(1024);
        ipc_recv_line(fd, buf, 1024);
        print_str("[mde-panel] connected to compositor\n");
        ipc_close(fd);
    } else {
        print_str("[mde-panel] compositor IPC not available, standalone mode\n");
    }

    int err = dsk_init_window(900, 48, "MDE Panel");
    if (err != 0) { return err; }
    dsk_set_theme(1);
    int win = dsk_root();
    dsk_add_widget(win, WT_LABEL, 12, 12, 120, 20, "MDE Panel", 0, 0, 0);
    int clock = dsk_add_widget(win, WT_LABEL, 760, 12, 120, 20, "00:00:00", 0, 0, 0);
    int quit = dsk_add_widget(win, WT_BUTTON, 680, 8, 70, 28, "Quit", 0, 0, 0);
    while (dsk_running() == 1) {
        dsk_widget_set_label(clock, fmt_time(get_timestamp()));
        int c = dsk_frame();
        if (c == quit || gui_close_requested() == 1) { dsk_stop(); }
    }
    dsk_shutdown();
    return 0;
}
