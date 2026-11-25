// ============================================================================
// Magnetar Standard Library: CLI Helpers (lib/cli.mg)
// Lightweight argument parsing and help formatting for CLI apps.
// ============================================================================

use "lib/string.mg";

fn cli_arg(char** argv, int index) -> string {
    if (argv == null || index < 0) { return ""; }
    string a = argv[index];
    if (a == null) { return ""; }
    return a;
}

fn cli_has_flag(int argc, char** argv, string flag) -> bool {
    for (int i = 1; i < argc; i = i + 1) {
        string a = cli_arg(argv, i);
        if (str_equals(a, flag)) { return true; }
    }
    return false;
}

fn cli_get_option(int argc, char** argv, string name, string fallback) -> string {
    int nlen = len(name);
    for (int i = 1; i < argc; i = i + 1) {
        string a = cli_arg(argv, i);
        int alen = len(a);
        if (alen <= nlen) { continue; }
        string prefix = str_substr(a, 0, nlen);
        if (str_equals(prefix, name)) {
            free(cast<char*>(prefix));
            return str_substr(a, nlen, alen - nlen);
        }
        free(cast<char*>(prefix));
    }
    return fallback;
}

fn cli_get_option_int(int argc, char** argv, string name, int fallback) -> int {
    string v = cli_get_option(argc, argv, name, "");
    if (v == "" || v == null) { return fallback; }
    return str_to_int(v);
}

fn cli_is_number(string text) -> bool {
    if (text == null) { return false; }
    int n = len(text);
    if (n <= 0) { return false; }
    int i = 0;
    if (*(cast<char*>(text)) == 45) { i = 1; }
    if (i >= n) { return false; }
    while (i < n) {
        if (!is_digit(*(cast<char*>(text) + i))) { return false; }
        i = i + 1;
    }
    return true;
}

fn cli_print_kv(string key, string value) -> void {
    print_str(key);
    print_str(": ");
    print_str(value);
    print_str("\n");
}
