extern fn sys_pipe(char* fds) -> int;

const int ED_MODE_NORMAL = 0;
const int ED_MODE_SEARCH = 1;
const int ED_MSG_FRAMES = 140;

static int ED_RUNNING;
static int ED_FRAME;
static int ED_MODE;
static char* ED_MSG_BUF;
static int ED_MSG_TTL;
static char* ED_PICK_BUF;
static char* ED_ENV_BUF;
static char** ED_ENV_PTRS;
static int ED_ENV_COUNT;
static char* ED_KEY_BUF;
static int ED_MOUSE_SELECTING;
static char* ED_STATUS_BUF;
static int ED_LAST_AUTOSAVE_MSG;

fn edit_byte(char* p, int i) -> int {
    int v = cast<int>(*(p + i));
    if (v < 0) { v = v + 256; }
    return v;
}

fn edit_len(char* p) -> int {
    int n = 0;
    while (edit_byte(p, n) != 0) { n = n + 1; }
    return n;
}

fn edit_get_u32(char* p, int off) -> int {
    return edit_byte(p, off) + edit_byte(p, off + 1) * 256 + edit_byte(p, off + 2) * 65536 + edit_byte(p, off + 3) * 16777216;
}

fn edit_copy(char* dst, int cap, string src) -> void {
    if (cap <= 0) { return; }
    char* p = cast<char*>(src);
    int n = edit_len(p);
    if (n > cap - 1) { n = cap - 1; }
    int i = 0;
    while (i < n) { *(dst + i) = *(p + i); i = i + 1; }
    *(dst + n) = 0;
}

fn editor_msg(string s) -> void {
    edit_copy(ED_MSG_BUF, 256, s);
    ED_MSG_TTL = ED_MSG_FRAMES;
}

fn editor_begin_search() -> void {
    ED_MODE = ED_MODE_SEARCH;
    search_begin();
    editor_msg("Find: type text, Enter to search, Esc to cancel.");
}

fn editor_end_search() -> void {
    ED_MODE = ED_MODE_NORMAL;
    search_cancel();
}

fn editor_commit_search() -> void {
    ED_MODE = ED_MODE_NORMAL;
    search_cancel();
    if (search_find(1) == 1) { editor_msg("Found."); }
    else { editor_msg("Not found."); }
}

fn editor_cmdline_path() -> string {
    int fd = sys_open("/proc/self/cmdline", 0, 0);
    if (fd < 0) { return ""; }
    char* buf = alloc<char>(4096);
    int n = sys_read(fd, buf, 4095);
    sys_close(fd);
    if (n <= 0) { free(buf); return ""; }
    *(buf + n) = 0;
    int i = 0;
    while (i < n && edit_byte(buf, i) != 0) { i = i + 1; }
    i = i + 1;
    if (i >= n) { free(buf); return ""; }
    int st = i;
    while (i < n && edit_byte(buf, i) != 0) { i = i + 1; }
    int l = i - st;
    if (l <= 0) { free(buf); return ""; }
    char* out = alloc<char>(l + 1);
    int j = 0;
    while (j < l) {
        *(out + j) = *(buf + st + j);
        j = j + 1;
    }
    *(out + l) = 0;
    free(buf);
    return cast<string>(out);
}

fn editor_build_envp(int n) -> void {
    ED_ENV_COUNT = 0;
    int i = 0;
    while (i < n && ED_ENV_COUNT < 250) {
        if (edit_byte(ED_ENV_BUF, i) != 0) {
            ED_ENV_PTRS[ED_ENV_COUNT] = ED_ENV_BUF + i;
            ED_ENV_COUNT = ED_ENV_COUNT + 1;
        }
        while (i < n && edit_byte(ED_ENV_BUF, i) != 0) { i = i + 1; }
        i = i + 1;
    }
    ED_ENV_PTRS[ED_ENV_COUNT] = null;
    if (ED_ENV_COUNT == 0) {
        ED_ENV_PTRS[0] = cast<char*>("DISPLAY=:0");
        ED_ENV_PTRS[1] = cast<char*>("HOME=/tmp");
        ED_ENV_PTRS[2] = null;
        ED_ENV_COUNT = 2;
    }
}

fn editor_load_env() -> void {
    int fd = sys_open("/proc/self/environ", 0, 0);
    if (fd < 0) { editor_build_envp(0); return; }
    int n = sys_read(fd, ED_ENV_BUF, 8191);
    sys_close(fd);
    if (n <= 0) { editor_build_envp(0); return; }
    editor_build_envp(n);
}

fn editor_pick_path(int save_mode) -> int {
    if (file_exists("/usr/bin/zenity") == false) {
        editor_msg("File picker unavailable: zenity is not installed.");
        return 0;
    }
    if (ED_ENV_COUNT == 0) { editor_load_env(); }
    char* fds = alloc<char>(8);
    int i = 0;
    while (i < 8) { *(fds + i) = 0; i = i + 1; }
    if (sys_pipe(fds) != 0) {
        free(fds);
        editor_msg("Could not open the file picker.");
        return 0;
    }
    int rd = edit_get_u32(fds, 0);
    int wr = edit_get_u32(fds, 4);
    int pid = sys_fork();
    if (pid == 0) {
        sys_close(rd);
        sys_dup2(wr, 1);
        if (wr > 2) { sys_close(wr); }
        char** argv = alloc<char*>(10);
        argv[0] = cast<char*>("env");
        argv[1] = cast<char*>("GDK_BACKEND=x11");
        argv[2] = cast<char*>("zenity");
        argv[3] = cast<char*>("--file-selection");
        if (save_mode == 1) {
            argv[4] = cast<char*>("--save");
            argv[5] = cast<char*>("--confirm-overwrite");
            argv[6] = cast<char*>("--title=Save Magnetar file");
            argv[7] = cast<char*>("--file-filter=Code | *.mg *.txt *.md *.json *.c *.h *.py *.sh");
            argv[8] = null;
        } else {
            argv[4] = cast<char*>("--title=Open Magnetar file");
            argv[5] = cast<char*>("--file-filter=Code | *.mg *.txt *.md *.json *.c *.h *.py *.sh");
            argv[6] = null;
        }
        sys_execve("/usr/bin/env", argv, ED_ENV_PTRS);
        sys_exit(127);
    }
    sys_close(wr);
    int n = sys_read(rd, ED_PICK_BUF, 1023);
    sys_close(rd);
    int status = 0;
    sys_wait4(pid, &status, 0, null);
    free(fds);
    while (gui_key_available() > 0) { gui_key_poll(); }
    if (n <= 0) {
        editor_msg("File selection cancelled.");
        return 0;
    }
    *(ED_PICK_BUF + n) = 0;
    string picked = cast<string>(ED_PICK_BUF);
    string cleaned = str_trim(picked);
    edit_copy(ED_PICK_BUF, 1024, cleaned);
    if (len(cast<string>(ED_PICK_BUF)) == 0) {
        editor_msg("File selection cancelled.");
        return 0;
    }
    return 1;
}

fn editor_open_path(string path) -> int {
    int r = doc_load_file(path);
    if (r == 0) {
        editor_msg("Not a regular file.");
        return 0;
    }
    if (r < 0) {
        editor_msg("File is too large for this editor.");
        return 0;
    }
    view_reset_scroll();
    view_ensure_cursor_visible();
    ft_reload_for_path(doc_path());
    editor_msg("Opened file.");
    return 1;
}

fn editor_new() -> void {
    doc_flush();
    doc_new();
    view_reset_scroll();
    editor_msg("New document.");
}

fn editor_open_dialog() -> void {
    doc_flush();
    if (editor_pick_path(0) == 0) { return; }
    editor_open_path(cast<string>(ED_PICK_BUF));
}

fn editor_save() -> void {
    if (doc_path_len() == 0) {
        editor_save_as();
        return;
    }
    if (doc_save_file(doc_path(), 0) == 1) { editor_msg("Saved."); }
    else { editor_msg("Could not save the file."); }
}

fn editor_save_as() -> void {
    if (editor_pick_path(1) == 0) { return; }
    doc_set_path(cast<string>(ED_PICK_BUF));
    if (doc_save_file(doc_path(), 0) == 1) {
        ft_reload_for_path(doc_path());
        editor_msg("Saved as.");
    } else {
        editor_msg("Could not save the file.");
    }
}

fn editor_quit() -> void {
    doc_flush();
    ED_RUNNING = 0;
}

fn editor_pick_folder() -> int {
    if (file_exists("/usr/bin/zenity") == false) {
        editor_msg("Folder picker unavailable: zenity is not installed.");
        return 0;
    }
    if (ED_ENV_COUNT == 0) { editor_load_env(); }
    char* fds = alloc<char>(8);
    int i = 0;
    while (i < 8) { *(fds + i) = 0; i = i + 1; }
    if (sys_pipe(fds) != 0) {
        free(fds);
        editor_msg("Could not open the folder picker.");
        return 0;
    }
    int rd = edit_get_u32(fds, 0);
    int wr = edit_get_u32(fds, 4);
    int pid = sys_fork();
    if (pid == 0) {
        sys_close(rd);
        sys_dup2(wr, 1);
        if (wr > 2) { sys_close(wr); }
        char** argv = alloc<char*>(8);
        argv[0] = cast<char*>("env");
        argv[1] = cast<char*>("GDK_BACKEND=x11");
        argv[2] = cast<char*>("zenity");
        argv[3] = cast<char*>("--file-selection");
        argv[4] = cast<char*>("--directory");
        argv[5] = cast<char*>("--title=Open Magnetar folder");
        argv[6] = null;
        sys_execve("/usr/bin/env", argv, ED_ENV_PTRS);
        sys_exit(127);
    }
    sys_close(wr);
    int n = sys_read(rd, ED_PICK_BUF, 1023);
    sys_close(rd);
    int status = 0;
    sys_wait4(pid, &status, 0, null);
    free(fds);
    while (gui_key_available() > 0) { gui_key_poll(); }
    if (n <= 0) {
        editor_msg("Folder selection cancelled.");
        return 0;
    }
    *(ED_PICK_BUF + n) = 0;
    string cleaned = str_trim(cast<string>(ED_PICK_BUF));
    edit_copy(ED_PICK_BUF, 1024, cleaned);
    if (len(cast<string>(ED_PICK_BUF)) == 0) {
        editor_msg("Folder selection cancelled.");
        return 0;
    }
    return 1;
}

fn editor_open_folder_dialog() -> void {
    if (editor_pick_folder() == 0) { return; }
    ft_set_dir(cast<string>(ED_PICK_BUF));
    ft_scan();
    if (view_tree_on() == 0) { view_toggle_tree(); }
    view_ensure_cursor_visible();
    editor_msg("Folder opened.");
}

static char* BD_VISITED;
static int BD_VLEN;

fn bd_reset() -> void {
    if (BD_VISITED == null) { BD_VISITED = alloc<char>(16384); }
    *(BD_VISITED) = 0;
    BD_VLEN = 0;
}

fn bd_seen(string path) -> int {
    char* p = cast<char*>(path);
    int i = 0;
    while (i < BD_VLEN) {
        int j = 0;
        int same = 1;
        while (*(BD_VISITED + i + j) != 0 && *(BD_VISITED + i + j) != 10) {
            if (*(p + j) == 0 || *(p + j) != *(BD_VISITED + i + j)) { same = 0; }
            j = j + 1;
        }
        if (same == 1 && *(p + j) == 0 && *(BD_VISITED + i + j) == 10) { return 1; }
        while (i < BD_VLEN && *(BD_VISITED + i) != 10) { i = i + 1; }
        if (i < BD_VLEN && *(BD_VISITED + i) == 10) { i = i + 1; }
    }
    return 0;
}

fn bd_mark(string path) -> void {
    if (BD_VISITED == null) { bd_reset(); }
    char* p = cast<char*>(path);
    int i = 0;
    while (*(p + i) != 0 && BD_VLEN < 16380) {
        *(BD_VISITED + BD_VLEN) = *(p + i);
        BD_VLEN = BD_VLEN + 1;
        i = i + 1;
    }
    if (BD_VLEN < 16383) {
        *(BD_VISITED + BD_VLEN) = 10;
        BD_VLEN = BD_VLEN + 1;
    }
    *(BD_VISITED + BD_VLEN) = 0;
}

fn bd_dirname(string path, char* out, int cap) -> void {
    char* p = cast<char*>(path);
    int n = 0;
    while (*(p + n) != 0) { n = n + 1; }
    int last = -1;
    int i = 0;
    while (i < n) {
        if (*(p + i) == 47) { last = i; }
        i = i + 1;
    }
    if (last < 0) {
        if (cap > 1) { *(out) = 46; *(out + 1) = 0; } else { *(out) = 0; }
        return;
    }
    if (last == 0) {
        if (cap > 1) { *(out) = 47; *(out + 1) = 0; } else { *(out) = 0; }
        return;
    }
    if (last >= cap) { last = cap - 1; }
    i = 0;
    while (i < last) { *(out + i) = *(p + i); i = i + 1; }
    *(out + last) = 0;
}

fn bd_join2(string dir, string name, char* out, int cap) -> void {
    char* d = cast<char*>(dir);
    char* nm = cast<char*>(name);
    int dl = 0; while (*(d + dl) != 0) { dl = dl + 1; }
    int nl = 0; while (*(nm + nl) != 0) { nl = nl + 1; }
    int sep = 0;
    if (dl > 0 && *(d + dl - 1) != 47) { sep = 1; }
    int i = 0;
    while (i < dl && i < cap - 1) { *(out + i) = *(d + i); i = i + 1; }
    if (sep == 1 && i < cap - 1) { *(out + i) = 47; i = i + 1; }
    int k = 0;
    while (k < nl && i < cap - 1) { *(out + i) = *(nm + k); i = i + 1; k = k + 1; }
    *(out + i) = 0;
}

fn bd_try(string path) -> int {
    if (file_is_file(path) == true) { return 1; }
    return 0;
}

fn bd_copy_str(char* out, int cap, string src) -> void {
    char* p = cast<char*>(src);
    int i = 0;
    while (*(p + i) != 0 && i < cap - 1) { *(out + i) = *(p + i); i = i + 1; }
    *(out + i) = 0;
}

fn bd_resolve(string base_dir, string mod, char* out, int cap) -> int {
    char* m = cast<char*>(mod);
    int has_slash = 0;
    int i = 0;
    while (*(m + i) != 0) { if (*(m + i) == 47) { has_slash = 1; } i = i + 1; }
    if (has_slash == 1) {
        bd_join2(base_dir, mod, out, cap);
        if (bd_try(cast<string>(out)) == 1) { return 1; }
        char* tmp = alloc<char>(1024);
        bd_join2(base_dir, mod, tmp, 1024);
        int tl = 0; while (*(tmp + tl) != 0) { tl = tl + 1; }
        *(tmp + tl) = 46; *(tmp + tl + 1) = 109; *(tmp + tl + 2) = 103; *(tmp + tl + 3) = 0;
        if (bd_try(cast<string>(tmp)) == 1) { bd_copy_str(out, cap, cast<string>(tmp)); free(tmp); return 1; }
        free(tmp);
        return 0;
    }
    char* t = alloc<char>(1024);
    char* libdir = alloc<char>(1024);
    bd_join2(base_dir, "lib", libdir, 1024);
    bd_join2(cast<string>(libdir), mod, t, 1024);
    int tl = 0; while (*(t + tl) != 0) { tl = tl + 1; }
    *(t + tl) = 46; *(t + tl + 1) = 109; *(t + tl + 2) = 103; *(t + tl + 3) = 0;
    if (bd_try(cast<string>(t)) == 1) { bd_copy_str(out, cap, cast<string>(t)); free(t); free(libdir); return 1; }
    bd_join2(cast<string>(libdir), mod, t, 1024);
    if (bd_try(cast<string>(t)) == 1) { bd_copy_str(out, cap, cast<string>(t)); free(t); free(libdir); return 1; }
    free(libdir);
    bd_join2(base_dir, mod, t, 1024);
    tl = 0; while (*(t + tl) != 0) { tl = tl + 1; }
    *(t + tl) = 46; *(t + tl + 1) = 109; *(t + tl + 2) = 103; *(t + tl + 3) = 0;
    if (bd_try(cast<string>(t)) == 1) { bd_copy_str(out, cap, cast<string>(t)); free(t); return 1; }
    bd_join2(base_dir, mod, t, 1024);
    if (bd_try(cast<string>(t)) == 1) { bd_copy_str(out, cap, cast<string>(t)); free(t); return 1; }
    free(t);
    return 0;
}

fn bd_extract_use(string line, char* mod, int cap) -> int {
    char* p = cast<char*>(line);
    int i = 0;
    while (*(p + i) == 32 || *(p + i) == 9) { i = i + 1; }
    if (*(p + i) != 117 || *(p + i + 1) != 115 || *(p + i + 2) != 101) { return 0; }
    int next = cast<int>(*(p + i + 3));
    if (next != 32 && next != 9 && next != 34) { return 0; }
    i = i + 3;
    while (*(p + i) == 32 || *(p + i) == 9) { i = i + 1; }
    int q = 0;
    if (*(p + i) == 34) { q = 34; i = i + 1; }
    int j = 0;
    while (*(p + i) != 0 && *(p + i) != 10) {
        int c = cast<int>(*(p + i));
        if (q != 0 && c == q) { break; }
        if (q == 0 && (c == 59 || c == 32 || c == 9)) { break; }
        if (j < cap - 1) { *(mod + j) = cast<char>(c); j = j + 1; }
        i = i + 1;
    }
    *(mod + j) = 0;
    if (j == 0) { return 0; }
    return 1;
}

fn bd_bundle_file(string path, int outfd) -> int {
    if (bd_seen(path) == 1) { return 1; }
    bd_mark(path);
    if (file_is_file(path) == false) { return 0; }
    string data = file_read_all(path);
    if (len(data) == 0) { return 1; }
    char* dir = alloc<char>(1024);
    bd_dirname(path, dir, 1024);
    char* p = cast<char*>(data);
    int i = 0;
    while (*(p + i) != 0) {
        int st = i;
        while (*(p + i) != 0 && *(p + i) != 10) { i = i + 1; }
        int has_nl = 0;
        if (*(p + i) == 10) { has_nl = 1; }
        int n = i - st;
        char* line = alloc<char>(n + 1);
        int k = 0;
        while (k < n) { *(line + k) = *(p + st + k); k = k + 1; }
        *(line + n) = 0;
        char* mod = alloc<char>(512);
        *(mod) = 0;
        int is_use = bd_extract_use(cast<string>(line), mod, 512);
        int inlined = 0;
        if (is_use == 1) {
            char* rpath = alloc<char>(1024);
            if (bd_resolve(cast<string>(dir), cast<string>(mod), rpath, 1024) == 1) {
                if (bd_seen(cast<string>(rpath)) == 0) {
                    file_write_str(outfd, "// [mgedit bundle] begin ");
                    file_write_str(outfd, cast<string>(rpath));
                    file_write_str(outfd, "\n");
                    bd_bundle_file(cast<string>(rpath), outfd);
                    file_write_str(outfd, "// [mgedit bundle] end ");
                    file_write_str(outfd, cast<string>(rpath));
                    file_write_str(outfd, "\n");
                }
                inlined = 1;
            }
            free(rpath);
        }
        if (inlined == 0) {
            file_write(outfd, cast<string>(line), n);
            if (has_nl == 1) { file_write_str(outfd, "\n"); }
        }
        free(line);
        free(mod);
        if (has_nl == 1) { i = i + 1; }
    }
    free(cast<char*>(data));
    free(dir);
    return 1;
}

fn editor_bundle_project() -> void {
    if (doc_path_len() == 0) {
        editor_msg("Save/open a .mg file first to bundle.");
        return;
    }
    if (doc_is_dirty() == 1) { doc_flush(); }
    bd_reset();
    string merged = build_merged_path();
    int fd = sys_open(merged, 577, 420);
    if (fd < 0) {
        editor_msg("Could not create merged file.");
        return;
    }
    bd_bundle_file(doc_path(), fd);
    sys_close(fd);
    string outbin = "/tmp/mgedit_bundle_out";
    int ok = build_run_path(merged, outbin);
    lint_load();
    if (VIEW_LINT_ON == 0) { view_toggle_lint(); }
    if (ok == 1) {
        editor_msg("Bundled and built: /tmp/mgedit_bundle_out");
    } else {
        editor_msg("Bundle compile failed. See lint panel.");
    }
}

fn editor_autosave() -> void {
    if (CFG_AUTOSAVE == 0) { return; }
    int saved = doc_autosave(ED_FRAME);
    if (saved == 1) {
        if (ED_FRAME - ED_LAST_AUTOSAVE_MSG > 180) {
            ED_LAST_AUTOSAVE_MSG = ED_FRAME;
            if (doc_path_len() == 0) { editor_msg("Autosaved to /tmp."); }
            else { editor_msg("Autosaved."); }
        }
    }
}

fn editor_insert_tab() -> void {
    int n = CFG_TAB_SIZE;
    if (n < 1) { n = 4; }
    int i = 0;
    while (i < n) {
        doc_insert_char(32, 0);
        i = i + 1;
    }
}

fn editor_handle_search(int k, int ctrl, int shift) -> void {
    if (k == 27) {
        editor_end_search();
        editor_msg("Search cancelled.");
        return;
    }
    if (k == 10) {
        editor_commit_search();
        return;
    }
    if (k == 8) {
        search_backspace();
        return;
    }
    if (ctrl == 0 && k >= 32 && k <= 126) {
        search_input(k);
    }
}

fn editor_handle_normal(int k, int ctrl, int shift) -> void {
    if (k == 8) { doc_backspace(); return; }
    if (k == 127) { doc_delete_forward(); return; }
    if (k == 10) { doc_insert_char(10, 0); return; }
    if (k == 9) { editor_insert_tab(); return; }
    if (k == 128) { cur_vertical(-1, shift); return; }
    if (k == 129) { cur_vertical(1, shift); return; }
    if (k == 130) {
        if (ctrl == 1) { cur_word_left(shift); } else { cur_left(shift); }
        return;
    }
    if (k == 131) {
        if (ctrl == 1) { cur_word_right(shift); } else { cur_right(shift); }
        return;
    }
    if (k == 132) {
        if (ctrl == 1) { cur_doc_start(shift); } else { cur_home(shift); }
        return;
    }
    if (k == 133) {
        if (ctrl == 1) { cur_doc_end(shift); } else { cur_end(shift); }
        return;
    }
    if (k == 134) { cur_page(-1, shift); return; }
    if (k == 135) { cur_page(1, shift); return; }
    if (ctrl == 0 && k >= 32 && k <= 126) {
        doc_insert_char(k, 0);
    }
}

fn editor_handle_keys() -> void {
    int k = gui_key_poll();
    while (k >= 0) {
        int ctrl = gui_key_ctrl();
        int shift = gui_key_shift();
        if (ED_MODE == ED_MODE_SEARCH) {
            editor_handle_search(k, ctrl, shift);
        } else {
            int cmd = keymap_command(k, ctrl, shift);
            if (cmd != CMD_NONE) {
                cmd_run(cmd);
            } else {
                editor_handle_normal(k, ctrl, shift);
            }
        }
        view_ensure_cursor_visible();
        k = gui_key_poll();
    }
}

fn editor_tick() -> void {
    ED_FRAME = ED_FRAME + 1;
    doc_set_frame(ED_FRAME);
    gui_read_mouse();
    render_gui_handle_mouse();
    editor_handle_keys();
    editor_autosave();
    render_gui_draw();
    gui_present();
    sleep_ms(16);
    if (ED_MSG_TTL > 0) { ED_MSG_TTL = ED_MSG_TTL - 1; }
}

fn editor_init() -> void {
    config_init();
    theme_init();
    doc_init();
    cur_init();
    sel_init();
    search_init();
    ac_init();
    build_init();
    lint_init();
    view_init();
    render_gui_init();
    ft_init();
    ED_MSG_BUF = alloc<char>(256);
    *(ED_MSG_BUF) = 0;
    ED_MSG_TTL = 0;
    ED_PICK_BUF = alloc<char>(1024);
    *(ED_PICK_BUF) = 0;
    ED_ENV_BUF = alloc<char>(8192);
    *(ED_ENV_BUF) = 0;
    ED_ENV_PTRS = alloc<char*>(256);
    ED_ENV_PTRS[0] = null;
    ED_ENV_COUNT = 0;
    ED_KEY_BUF = alloc<char>(8);
    *(ED_KEY_BUF) = 0;
    ED_STATUS_BUF = alloc<char>(320);
    *(ED_STATUS_BUF) = 0;
    ED_RUNNING = 1;
    ED_FRAME = 0;
    ED_MODE = ED_MODE_NORMAL;
    ED_MOUSE_SELECTING = 0;
    ED_LAST_AUTOSAVE_MSG = -1000;
    editor_load_env();
    string p = editor_cmdline_path();
    edit_copy(ED_PICK_BUF, 1024, p);
    free(cast<char*>(p));
    if (len(cast<string>(ED_PICK_BUF)) > 0) {
        if (file_is_file(cast<string>(ED_PICK_BUF)) == true) {
            editor_open_path(cast<string>(ED_PICK_BUF));
        } else {
            doc_set_path(cast<string>(ED_PICK_BUF));
            doc_new();
            editor_msg("New file. Autosave is on.");
        }
    } else {
        doc_set_text("// MGEdit modular editor\n// Ctrl+S save  Ctrl+O open  Ctrl+F find\n// Ctrl+B build  Ctrl+E lint  Ctrl+G next match\n\nfn main() -> int {\n    print(\"Hello, Magnetar!\");\n    return 0;\n}\n");
        editor_msg("Sample loaded. Ctrl+S saves. Autosave is on.");
    }
}

fn editor_run() -> void {
    while (ED_RUNNING == 1 && gui_close_requested() == 0) {
        editor_tick();
    }
    doc_flush();
}
