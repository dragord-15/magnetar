const int CMD_NONE = 0;
const int CMD_NEW = 1;
const int CMD_OPEN = 2;
const int CMD_SAVE = 3;
const int CMD_SAVE_AS = 4;
const int CMD_QUIT = 5;
const int CMD_UNDO = 6;
const int CMD_REDO = 7;
const int CMD_COPY = 8;
const int CMD_CUT = 9;
const int CMD_PASTE = 10;
const int CMD_SELECT_ALL = 11;
const int CMD_FIND = 12;
const int CMD_FIND_NEXT = 13;
const int CMD_FIND_PREV = 14;
const int CMD_BUILD = 15;
const int CMD_LINT = 16;
const int CMD_TOGGLE_TREE = 17;
const int CMD_TOGGLE_THEME = 18;
const int CMD_TOGGLE_AUTOSAVE = 19;
const int CMD_COMPLETE = 20;
const int CMD_TOGGLE_LINES = 21;
const int CMD_OPEN_FOLDER = 22;
const int CMD_BUNDLE = 23;

fn cmd_run(int id) -> int {
    if (id == CMD_NEW) { editor_new(); return 1; }
    if (id == CMD_OPEN) { editor_open_dialog(); return 1; }
    if (id == CMD_SAVE) { editor_save(); return 1; }
    if (id == CMD_SAVE_AS) { editor_save_as(); return 1; }
    if (id == CMD_QUIT) { editor_quit(); return 1; }
    if (id == CMD_UNDO) {
        if (doc_undo() == 1) { editor_msg("Undo."); view_ensure_cursor_visible(); }
        else { editor_msg("Nothing to undo."); }
        return 1;
    }
    if (id == CMD_REDO) {
        if (doc_redo() == 1) { editor_msg("Redo."); view_ensure_cursor_visible(); }
        else { editor_msg("Nothing to redo."); }
        return 1;
    }
    if (id == CMD_COPY) {
        if (sel_copy() > 0) { editor_msg("Copied."); }
        else { editor_msg("Nothing selected."); }
        return 1;
    }
    if (id == CMD_CUT) {
        if (sel_cut() == 1) {
            editor_msg("Cut.");
            view_ensure_cursor_visible();
        } else {
            editor_msg("Nothing selected.");
        }
        return 1;
    }
    if (id == CMD_PASTE) {
        if (sel_paste() == 1) {
            editor_msg("Pasted.");
            view_ensure_cursor_visible();
        } else {
            editor_msg("Clipboard is empty.");
        }
        return 1;
    }
    if (id == CMD_SELECT_ALL) {
        sel_select_all();
        editor_msg("Selected all.");
        return 1;
    }
    if (id == CMD_FIND) { editor_begin_search(); return 1; }
    if (id == CMD_FIND_NEXT) {
        if (search_find(1) == 1) { editor_msg("Found."); }
        else { editor_msg("Not found."); }
        return 1;
    }
    if (id == CMD_FIND_PREV) {
        if (search_find(0) == 1) { editor_msg("Found."); }
        else { editor_msg("Not found."); }
        return 1;
    }
    if (id == CMD_BUILD) {
        if (doc_path_len() == 0) {
            editor_msg("Save the file before building.");
            return 0;
        }
        int ok = build_run();
        lint_load();
        if (ok == 1) {
            editor_msg("Build succeeded.");
        } else {
            if (VIEW_LINT_ON == 0) { view_toggle_lint(); }
            editor_msg("Build failed. Check the lint panel.");
        }
        return ok;
    }
    if (id == CMD_LINT) {
        lint_toggle();
        if (VIEW_LINT_ON == 1) {
            int e = lint_errors();
            if (e > 0) { editor_msg("Lint errors found."); }
            else { editor_msg("Lint panel shown."); }
        } else {
            editor_msg("Lint panel hidden.");
        }
        return 1;
    }
    if (id == CMD_TOGGLE_TREE) {
        ft_toggle();
        if (view_tree_on() == 1) { editor_msg("File tree shown."); }
        else { editor_msg("File tree hidden."); }
        return 1;
    }
    if (id == CMD_TOGGLE_THEME) {
        theme_toggle();
        if (theme_dark() == 1) { editor_msg("Dark theme."); }
        else { editor_msg("Light theme."); }
        return 1;
    }
    if (id == CMD_TOGGLE_AUTOSAVE) {
        config_toggle_autosave();
        if (CFG_AUTOSAVE == 1) { editor_msg("Autosave enabled."); }
        else { editor_msg("Autosave disabled."); }
        return 1;
    }
    if (id == CMD_COMPLETE) {
        int n = ac_complete();
        if (n > 0) {
            editor_msg("Completed.");
            view_ensure_cursor_visible();
        } else {
            editor_msg("No completion.");
        }
        return 1;
    }
    if (id == CMD_TOGGLE_LINES) {
        config_toggle_lines();
        editor_msg("Line numbers toggled.");
        return 1;
    }
    if (id == CMD_OPEN_FOLDER) { editor_open_folder_dialog(); return 1; }
    if (id == CMD_BUNDLE) { editor_bundle_project(); return 1; }
    return 0;
}

fn cmd_name(int id) -> string {
    if (id == CMD_NEW) { return "New"; }
    if (id == CMD_OPEN) { return "Open"; }
    if (id == CMD_OPEN_FOLDER) { return "Open Folder"; }
    if (id == CMD_SAVE) { return "Save"; }
    if (id == CMD_SAVE_AS) { return "Save As"; }
    if (id == CMD_QUIT) { return "Quit"; }
    if (id == CMD_UNDO) { return "Undo"; }
    if (id == CMD_REDO) { return "Redo"; }
    if (id == CMD_BUILD) { return "Build"; }
    if (id == CMD_BUNDLE) { return "Bundle"; }
    if (id == CMD_LINT) { return "Lint"; }
    if (id == CMD_TOGGLE_TREE) { return "Files"; }
    if (id == CMD_TOGGLE_THEME) { return "Theme"; }
    return "Command";
}
