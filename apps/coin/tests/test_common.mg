// Tiny assertion helpers for MGC unit tests.
// Every test returns 0 on success and a positive failure count otherwise.

extern fn print_str(string s) -> void;

fn check_int(string name, int got, int want, int* failures) -> void {
    if (got != want) {
        print_str("FAIL ");
        print_str(name);
        print_str(": got ");
        print(got);
        print_str(", want ");
        print(want);
        print_str("\n");
        *failures = *failures + 1;
    }
}

fn check_bool(string name, bool got, bool want, int* failures) -> void {
    if (got != want) {
        print_str("FAIL ");
        print_str(name);
        print_str("\n");
        *failures = *failures + 1;
    }
}

fn check_string(string name, string got, string want, int* failures) -> void {
    if (got != want) {
        print_str("FAIL ");
        print_str(name);
        print_str(": got '");
        print_str(got);
        print_str("', want '");
        print_str(want);
        print_str("'\n");
        *failures = *failures + 1;
    }
}

fn test_report(string name, int failures) -> int {
    if (failures == 0) {
        print_str("PASS ");
        print_str(name);
        print_str("\n");
        return 0;
    }
    print_str("FAILURES ");
    print_str(name);
    print_str(": ");
    print(failures);
    print_str("\n");
    return failures;
}
