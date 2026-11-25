use "gui.mg";
use "file.mg";
use "string.mg";
use "config.mg";
use "theme.mg";
use "buffer.mg";
use "history.mg";
use "document.mg";
use "cursor.mg";
use "selection.mg";
use "syntax.mg";
use "view.mg";
use "search.mg";
use "autocomplete.mg";
use "filetree.mg";
use "build.mg";
use "lint.mg";
use "command.mg";
use "keymap.mg";
use "editor.mg";
use "render_tui.mg";
use "render_gui.mg";

fn main() -> int {
    int rc = dsk_init_window(1180, 760, "MGEdit");
    if (rc != 0) {
        print_str("Failed to open the MGEdit window.\n");
        return 1;
    }
    gui_set_scale(1);
    editor_init();
    editor_run();
    dsk_shutdown();
    return 0;
}
