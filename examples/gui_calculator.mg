// gui_calculator.mg — Mouse-driven integer calculator on the desktop framework
use "gui.mg";

extern fn sleep_ms(int ms) -> void;

static const int BK_DIGIT = 0;
static const int BK_PLUS = 1;
static const int BK_MINUS = 2;
static const int BK_MUL = 3;
static const int BK_DIV = 4;
static const int BK_EQ = 5;
static const int BK_CLEAR = 6;

fn main() -> int {
    int err = dsk_init();
    if (err != 0) {
        print_str("framebuffer init failed\n");
        return err;
    }

    int win = dsk_add_window("Calculator", 80, 60, 240, 340);
    int disp = dsk_add_widget(win, WT_TEXTBOX, 18, 36, 204, 44, "0", 0, 0, 0);

    string labels_default = "789/456*123-0=C+";
    array<int, 16> bid;
    array<int, 16> bkind;
    array<int, 16> bdigit;

    int r = 0;
    int bx = 18;
    int by = 92;
    int bw = 46;
    int bh = 40;
    int gi = 0;
    while (r < 4) {
        int c = 0;
        while (c < 4) {
            int kind = BK_DIGIT;
            int dig = 0;
            char* lp = alloc<char>(2);
            *(lp + 0) = 0;
            *(lp + 1) = 0;

            if (r == 3) {
                if (c == 0) { kind = BK_CLEAR; *(lp + 0) = 67; }
                else if (c == 1) { kind = BK_DIGIT; dig = 0; *(lp + 0) = 48; }
                else if (c == 2) { kind = BK_EQ; *(lp + 0) = 61; }
                else { kind = BK_PLUS; *(lp + 0) = 43; }
            } else {
                if (c == 3) {
                    if (r == 0) { kind = BK_DIV; *(lp + 0) = 47; }
                    if (r == 1) { kind = BK_MUL; *(lp + 0) = 42; }
                    if (r == 2) { kind = BK_MINUS; *(lp + 0) = 45; }
                } else {
                    int d = (3 - r) * 3 + c + 1;
                    dig = d;
                    *(lp + 0) = 48 + d;
                }
            }

            bid[gi] = dsk_add_widget(win, WT_BUTTON, bx + c * 52, by + r * 46, bw, bh, cast<string>(lp), 0, 0, 0);
            bkind[gi] = kind;
            bdigit[gi] = dig;
            gi = gi + 1;
            c = c + 1;
        }
        r = r + 1;
    }

    int cur = 0;
    int acc = 0;
    int op = 0;
    int entering = 0;

    while (dsk_running() == 1) {
        dsk_widget_set_label(disp, dsk_itoa(cur));
        int clicked = dsk_update();

        if (clicked >= 0) {
            int i = 0;
            while (i < 16) {
                if (bid[i] == clicked) {
                    if (bkind[i] == BK_DIGIT) {
                        if (entering == 1) { cur = cur * 10 + bdigit[i]; }
                        else { cur = bdigit[i]; entering = 1; }
                    } else if (bkind[i] == BK_CLEAR) {
                        cur = 0; acc = 0; op = 0; entering = 0;
                    } else if (bkind[i] == BK_EQ) {
                        if (op == 1) { cur = acc + cur; }
                        if (op == 2) { cur = acc - cur; }
                        if (op == 3) { cur = acc * cur; }
                        if (op == 4) { if (cur != 0) { cur = acc / cur; } else { cur = 0; } }
                        op = 0; entering = 0;
                    } else {
                        if (op == 1) { cur = acc + cur; }
                        if (op == 2) { cur = acc - cur; }
                        if (op == 3) { cur = acc * cur; }
                        if (op == 4) { if (cur != 0) { cur = acc / cur; } else { cur = 0; } }
                        acc = cur;
                        if (bkind[i] == BK_PLUS) { op = 1; }
                        if (bkind[i] == BK_MINUS) { op = 2; }
                        if (bkind[i] == BK_MUL) { op = 3; }
                        if (bkind[i] == BK_DIV) { op = 4; }
                        entering = 0;
                    }
                }
                i = i + 1;
            }
        }
        gui_present();
        sleep_ms(16);
    }

    dsk_shutdown();
    return 0;
}
