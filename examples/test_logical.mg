// examples/test_logical.mg
// Verification suite for the newly added logical && and || operators in Falcon

extern fn print_str(string s) -> void;
extern fn print_int(int n) -> void;

fn main() -> void {
    print_str("--- Falcon Custom Feature: Logical Operators && and || ---\n");

    int a = 10;
    int b = 20;
    int c = 30;

    print_str("Testing logical AND (&&):\n");
    if (a < b && b < c) {
        print_str("  SUCCESS: (a < b && b < c) is true!\n");
    } else {
        print_str("  FAILURE: (a < b && b < c) evaluated as false!\n");
    }

    if (a < b && b > c) {
        print_str("  FAILURE: (a < b && b > c) evaluated as true!\n");
    } else {
        print_str("  SUCCESS: (a < b && b > c) is false!\n");
    }

    print_str("Testing logical OR (||):\n");
    if (a > b || b < c) {
        print_str("  SUCCESS: (a > b || b < c) is true!\n");
    } else {
        print_str("  FAILURE: (a > b || b < c) evaluated as false!\n");
    }

    if (a > b || b > c) {
        print_str("  FAILURE: (a > b || b > c) evaluated as true!\n");
    } else {
        print_str("  SUCCESS: (a > b || b > c) is false!\n");
    }
    print_str("SUCCESS: Logical operators && and || compile and evaluate perfectly!\n");
}
