// gui_showcase.mg — كل عناصر مكتبة gui.mg في تطبيق واحد
// شغّل: ./magc examples/gui_showcase.mg -o /tmp/gui_showcase && /tmp/gui_showcase
use "gui.mg";

extern fn get_timestamp() -> int;

fn main() -> int {
    // استدعاء واحد: يفتح النافذة ويعيد مقبض النافذة الجذرية
    int win = dsk_open(1000, 680, "Falcon GUI Showcase");
    if (win < 0) { return 1; }

    dsk_set_theme(1);

    dsk_label(win, 24, 44, 520, 22, "Falcon Professional GUI Toolkit");

    int tab = dsk_tabs(win, 24, 78, 620, 34, "General|Appearance|About", 0);

    int badge = dsk_badge(win, 700, 44, 120, 26, "STABLE", 1);
    dsk_separator(win, 24, 126, 800);

    int card = dsk_card(win, 24, 146, 420, 210);
    dsk_label(win, 40, 162, 200, 20, "Profile");

    dsk_label(win, 40, 196, 120, 20, "User name");
    int name_in = dsk_input(win, 160, 192, 260, 30, "oussama");

    dsk_label(win, 40, 236, 120, 20, "Password");
    int pass_in = dsk_input(win, 160, 232, 260, 30, "");

    int remember = dsk_checkbox(win, 40, 276, 220, 22, "Remember me", 1);
    int notify = dsk_switch(win, 40, 306, "Notifications", 1);

    int card2 = dsk_card(win, 464, 146, 360, 210);
    dsk_label(win, 480, 162, 200, 20, "Controls");

    dsk_label(win, 480, 196, 100, 20, "Volume");
    int vol = dsk_slider(win, 580, 196, 220, 22, 65, 0, 100);

    dsk_label(win, 480, 232, 100, 20, "Progress");
    int prog = dsk_progress(win, 580, 236, 220, 16, 42, 100);

    dsk_label(win, 480, 272, 100, 20, "Search");
    int search = dsk_textbox(win, 580, 268, 220, 30, "type here");

    int spin = dsk_spinner(win, 480, 308, 28);

    dsk_label(win, 24, 380, 160, 20, "Choose an item");
    int list = dsk_listbox(win, 24, 406, 320, 150);
    dsk_add_list_item(list, "Alpha");
    dsk_add_list_item(list, "Bravo");
    dsk_add_list_item(list, "Charlie");
    dsk_add_list_item(list, "Delta");
    dsk_add_list_item(list, "Echo");

    int card3 = dsk_card(win, 368, 380, 456, 150);
    int status = dsk_label(win, 388, 402, 416, 20, "Ready.");
    int toast_btn = dsk_button(win, 388, 432, 140, 36, "Show toast");
    int theme_btn = dsk_button(win, 540, 432, 120, 36, "Theme");
    int about_btn = dsk_button(win, 672, 432, 132, 36, "About");
    int info_badge = dsk_badge(win, 388, 480, 100, 24, "INFO", 0);

    dsk_label(win, 24, 574, 800, 20, "Tip: click a field and type, Tab moves focus, Enter returns the input id.");

    int cur_theme = 1;
    int ticks = 0;

    while (dsk_running() == 1) {
        int clicked = dsk_frame();
        ticks = ticks + 1;

        if (dsk_widget_changed(name_in) == 1) {
            dsk_widget_clear_changed(name_in);
            dsk_widget_set_label(status, dsk_widget_text(name_in));
        }
        if (dsk_widget_changed(tab) == 1) {
            dsk_widget_clear_changed(tab);
            if (dsk_widget_val(tab) == 0) { dsk_widget_set_label(status, "General"); }
            if (dsk_widget_val(tab) == 1) { dsk_widget_set_label(status, "Appearance"); }
            if (dsk_widget_val(tab) == 2) { dsk_widget_set_label(status, "About"); }
        }
        if (clicked == toast_btn) {
            dsk_toast("Saved successfully!");
        }
        if (clicked == theme_btn) {
            cur_theme = cur_theme + 1;
            if (cur_theme > 4) { cur_theme = 0; }
            dsk_set_theme(cur_theme);
        }
        if (clicked == about_btn) {
            dsk_widget_set_label(status, "Falcon GUI v2.0");
        }
        if (clicked == list) {
            dsk_widget_set_label(status, dsk_list_item(list, dsk_widget_val(list)));
        }
        if (dsk_widget_changed(vol) == 1) {
            dsk_widget_clear_changed(vol);
            dsk_widget_set(prog, dsk_widget_val(vol));
        }
        if (dsk_widget_changed(notify) == 1) {
            dsk_widget_clear_changed(notify);
            if (dsk_widget_val(notify) == 1) { dsk_widget_set_label(status, "Notifications on"); }
            else { dsk_widget_set_label(status, "Notifications off"); }
        }
        if (dsk_widget_changed(remember) == 1) {
            dsk_widget_clear_changed(remember);
        }
        if (ticks > 1000000) { ticks = 0; }
    }

    dsk_shutdown();
    return 0;
}
