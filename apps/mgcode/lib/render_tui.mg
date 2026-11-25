extern fn print_str(string s) -> void;

static char* TUI_LINE;

fn tui_init() -> void {
    TUI_LINE = alloc<char>(1024);
    *(TUI_LINE) = 0;
}

fn tui_draw() -> void {
    print_str("MGCode\n");
    print_str("------\n");
    int li = doc_line_index(doc_cursor());
    int from = li - 8;
    if (from < 0) { from = 0; }
    int to = from + 18;
    if (to > doc_line_count()) { to = doc_line_count(); }
    int i = from;
    while (i < to) {
        doc_line_copy(i, TUI_LINE, 1024);
        print_str(cast<string>(TUI_LINE));
        print_str("\n");
        i = i + 1;
    }
}
