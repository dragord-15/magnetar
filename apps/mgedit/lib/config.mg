static int CFG_AUTOSAVE;
static int CFG_TAB_SIZE;
static int CFG_SHOW_LINES;
static int CFG_THEME;
static int CFG_AUTOSAVE_FRAMES;

fn config_init() -> void {
    CFG_AUTOSAVE = 1;
    CFG_TAB_SIZE = 4;
    CFG_SHOW_LINES = 1;
    CFG_THEME = 0;
    CFG_AUTOSAVE_FRAMES = 120;
}

fn config_toggle_autosave() -> void {
    CFG_AUTOSAVE = 1 - CFG_AUTOSAVE;
}

fn config_toggle_lines() -> void {
    CFG_SHOW_LINES = 1 - CFG_SHOW_LINES;
}
