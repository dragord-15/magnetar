fn keymap_lower(int c) -> int {
    if (c >= 65 && c <= 90) { return c + 32; }
    return c;
}

fn keymap_command(int key, int ctrl, int shift) -> int {
    if (ctrl != 1) { return CMD_NONE; }
    int k = keymap_lower(key);
    if (k == 115) {
        if (shift == 1) { return CMD_SAVE_AS; }
        return CMD_SAVE;
    }
    if (k == 111) {
        if (shift == 1) { return CMD_OPEN_FOLDER; }
        return CMD_OPEN;
    }
    if (k == 110) { return CMD_NEW; }
    if (k == 113) { return CMD_QUIT; }
    if (k == 122) {
        if (shift == 1) { return CMD_REDO; }
        return CMD_UNDO;
    }
    if (k == 121) { return CMD_REDO; }
    if (k == 99) { return CMD_COPY; }
    if (k == 120) { return CMD_CUT; }
    if (k == 118) { return CMD_PASTE; }
    if (k == 97) {
        if (shift == 1) { return CMD_TOGGLE_AUTOSAVE; }
        return CMD_SELECT_ALL;
    }
    if (k == 102) { return CMD_FIND; }
    if (k == 103) {
        if (shift == 1) { return CMD_FIND_PREV; }
        return CMD_FIND_NEXT;
    }
    if (k == 98) { return CMD_BUILD; }
    if (k == 109) { return CMD_BUNDLE; }
    if (k == 101) { return CMD_LINT; }
    if (k == 116) { return CMD_TOGGLE_TREE; }
    if (k == 100) { return CMD_TOGGLE_THEME; }
    if (k == 108) { return CMD_TOGGLE_LINES; }
    if (key == 32) { return CMD_COMPLETE; }
    return CMD_NONE;
}
