// ============================================================================
// Magnetar Standard Library: Console & Terminal IO (lib/console.mg)
// Standard Input (stdin), Terminal Output (stdout/stderr) & ANSI Styling
// ============================================================================

use "string.mg";

extern fn sys_read(int fd, char* buf, int count) -> int;
extern fn sys_write(int fd, char* buf, int count) -> int;
extern fn print_str(string s) -> void;

// Standard File Descriptors
const int STDIN_FILENO  = 0;
const int STDOUT_FILENO = 1;
const int STDERR_FILENO = 2;

// -------------------------------------------------------------
// 1. Terminal Output Functions
// -------------------------------------------------------------

fn print_line(string s) -> void {
    print_str(s);
    print("\n");
}

fn print_int_line(int n) -> void {
    print(n);
    print("\n");
}

fn eprint(string s) -> void {
    sys_write(STDERR_FILENO, cast<char*>(s), len(s));
}

fn eprint_line(string s) -> void {
    sys_write(STDERR_FILENO, cast<char*>(s), len(s));
    sys_write(STDERR_FILENO, "\n", 1);
}

// -------------------------------------------------------------
// 2. ANSI Styling and Color Output
// -------------------------------------------------------------

// Internal helper to emit ANSI escape code \033[<seq>
fn _ansi_emit(string seq) -> void {
    int seq_len = len(seq);
    char* buf = alloc<char>(seq_len + 3);
    *(buf + 0) = 27; // ESC (0x1B)
    *(buf + 1) = '[';
    char* ps = cast<char*>(seq);
    for (int i = 0; i < seq_len; i = i + 1) {
        int off = 2 + i;
        *(buf + off) = *(ps + i);
    }
    int total = 2 + seq_len;
    *(buf + total) = 0;
    sys_write(STDOUT_FILENO, buf, total);
    free(buf);
}

fn console_reset() -> void {
    _ansi_emit("0m");
}

fn console_bold() -> void {
    _ansi_emit("1m");
}

fn print_colored(string code, string text) -> void {
    _ansi_emit(code);
    print_str(text);
    _ansi_emit("0m");
}

fn print_red(string text) -> void {
    _ansi_emit("31m");
    print_str(text);
    _ansi_emit("0m");
}

fn print_green(string text) -> void {
    _ansi_emit("32m");
    print_str(text);
    _ansi_emit("0m");
}

fn print_yellow(string text) -> void {
    _ansi_emit("33m");
    print_str(text);
    _ansi_emit("0m");
}

fn print_blue(string text) -> void {
    _ansi_emit("34m");
    print_str(text);
    _ansi_emit("0m");
}

fn print_cyan(string text) -> void {
    _ansi_emit("36m");
    print_str(text);
    _ansi_emit("0m");
}

fn print_success(string msg) -> void {
    _ansi_emit("1;32m");
    print_str("[SUCCESS] ");
    _ansi_emit("0m");
    print_line(msg);
}

fn print_error(string msg) -> void {
    _ansi_emit("1;31m");
    sys_write(STDERR_FILENO, "[ERROR] ", 8);
    _ansi_emit("0m");
    sys_write(STDERR_FILENO, cast<char*>(msg), len(msg));
    sys_write(STDERR_FILENO, "\n", 1);
}

fn print_warning(string msg) -> void {
    _ansi_emit("1;33m");
    print_str("[WARNING] ");
    _ansi_emit("0m");
    print_line(msg);
}

fn print_info(string msg) -> void {
    _ansi_emit("1;36m");
    print_str("[INFO] ");
    _ansi_emit("0m");
    print_line(msg);
}


fn print_bold(string msg)->void{
    _ansi_emit("1m");
    print_str(msg);
    _ansi_emit("0m");
}

fn print_dim(string msg)->void{
    _ansi_emit("2m");
    print_str(msg);
    _ansi_emit("0m");
}



fn print_upper_case(string msg)->void{
    _ansi_emit("11m");
    print_str(msg);
    _ansi_emit("0m");
}
// -------------------------------------------------------------
// 3. User Input (Stdin)
// -------------------------------------------------------------

// Reads a line from stdin up to \n or EOF
fn console_read_line() -> string {
    int max_len = 2048;
    char* buf = alloc<char>(max_len + 1);
    int count = 0;
    char* ch = alloc<char>(2);
    int r = 0;

    while (count < max_len) {
        r = sys_read(STDIN_FILENO, ch, 1);
        if (r <= 0) {
            break;
        }
        if (*ch == 10) { // '\n'
            break;
        }
        if (*ch != 13) { // ignore '\r'
            *(buf + count) = *ch;
            count = count + 1;
        }
    }
    free(ch);

    if (count == 0 && r <= 0) {
        free(buf);
        return "";
    }
    *(buf + count) = 0;
    return cast<string>(buf);
}

// Prints a prompt message, then reads a line of input
fn input(string prompt) -> string {
    if (len(prompt) > 0) {
        print_str(prompt);
    }
    return console_read_line();
}

// Reads an integer from stdin
fn input_int(string prompt) -> int {
    string line = input(prompt);
    return str_to_int(str_trim(line));
}

// Clear screen and reset cursor position to top-left
fn console_clear() -> void {
    _ansi_emit("2J");
    _ansi_emit("H");
}
