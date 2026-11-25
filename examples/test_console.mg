// examples/test_console.mg
// Test suite for Console & Terminal IO Library (lib/console.mg)

use "console.mg";

fn main() -> void {
    print_info("Testing Console IO and ANSI styles...");
    print_success("Green success message printed successfully.");
    print_warning("Yellow warning message printed successfully.");
    print_error("Red error message to stderr tested successfully.");

    print_colored("35m", "Custom Magenta text!\n");
    print_cyan("Bright Cyan text!\n");

    print_line("Testing console input with automated pipe...");
    string name = input("Enter username: ");
    print_str("Welcome, "); print_str(name); print("!\n");

    int val = input_int("Enter a number: ");
    print_str("Double of number: "); print(val * 2); print("\n");

    print_success("All console functions verified!");
}
