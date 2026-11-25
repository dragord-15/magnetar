// MDE Files app - simple file browser
// Build: ./magc mde/apps/files/main.mg -o build/mde-files
use "gui.mg";
extern fn sleep_ms(int ms) -> void;
extern fn sys_getcwd(char* buf, int size) -> int;
extern fn sys_getdents64(int fd, char* dirp, int count) -> int;
extern fn sys_open(string path, int flags, int mode) -> int;
extern fn sys_close(int fd) -> int;
extern fn print_str(string s) -> void;

fn cstr_len(char* p) -> int { int i=0; while(*(p+i)!=0){i=i+1;} return i; }
fn cstr_copy(char* dst, string src) -> void {
    char* p = cast<char*>(src); int i=0; while(*(p+i)!=0){*(dst+i)=*(p+i); i=i+1;} *(dst+i)=0;
}

fn load_dir(string path, int list_wid) -> void {
    dsk_list_clear(list_wid);
    int fd = sys_open(path, 0, 0);
    if (fd < 0) { dsk_add_list_item(list_wid, "(cannot open)"); return; }
    char* buf = alloc<char>(4096);
    int nread = sys_getdents64(fd, buf, 4096);
    while (nread > 0) {
        int bpos = 0;
        while (bpos < nread) {
            int reclen = (cast<int>(*(buf + bpos + 16)) & 255) + (cast<int>(*(buf + bpos + 17)) & 255) * 256;
            int dtype = cast<int>(*(buf + bpos + 18)) & 255;
            char* name = buf + bpos + 19;
            // skip . and ..
            if (!(*(name+0)==46 && *(name+1)==0) && !(*(name+0)==46 && *(name+1)==46 && *(name+2)==0)) {
                char* disp = alloc<char>(256);
                int k=0;
                if (dtype == 4) { *(disp+k)=91; k=k+1; } // [
                int j=0; while(*(name+j)!=0 && k < 240){*(disp+k)=*(name+j); k=k+1; j=j+1;}
                if (dtype == 4) { *(disp+k)=93; k=k+1; } // ]
                *(disp+k)=0;
                dsk_add_list_item(list_wid, cast<string>(disp));
            }
            bpos = bpos + reclen;
        }
        nread = sys_getdents64(fd, buf, 4096);
    }
    free(buf);
    sys_close(fd);
}

fn main() -> int {
    int err = dsk_init_window(720, 480, "MDE Files");
    if (err != 0) { return err; }
    dsk_set_theme(1);
    int win = dsk_root();
    char* cwd = alloc<char>(512);
    sys_getcwd(cwd, 512);
    dsk_add_widget(win, WT_LABEL, 24, 20, 80, 20, "Path:", 0, 0, 0);
    int path_box = dsk_add_widget(win, WT_TEXTBOX, 90, 16, 500, 28, cast<string>(cwd), 0, 0, 0);
    int btn_go = dsk_add_widget(win, WT_BUTTON, 600, 16, 80, 28, "Open", 0, 0, 0);
    int list = dsk_add_widget(win, WT_LISTBOX, 24, 60, 656, 340, "", 0, 0, 0);
    int quit = dsk_add_widget(win, WT_BUTTON, 24, 412, 100, 30, "Close", 0, 0, 0);
    load_dir(cast<string>(cwd), list);
    while (dsk_running() == 1) {
        int c = dsk_frame();
        if (c == btn_go) {
            string p = dsk_widget_text(path_box);
            load_dir(p, list);
        }
        if (c == quit || gui_close_requested() == 1) { dsk_stop(); }
    }
    dsk_shutdown();
    return 0;
}
