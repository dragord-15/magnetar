// examples/test_string.mg
// Comprehensive Test Suite for Magnetar String Library (lib/string.mg)

use "lib/string.mg";

fn main() -> void {
    print("=== STARTING MAGNETAR STRING LIBRARY VERIFICATION ===\n\n");

    // 1. Character tests
    print("[1] Character tests:\n");
    print("  is_digit('5'): "); print(is_digit('5')); print("\n");
    print("  is_digit('a'): "); print(is_digit('a')); print("\n");
    print("  is_alpha('Z'): "); print(is_alpha('Z')); print("\n");
    print("  to_upper('m'): "); print(cast<int>(to_upper('m'))); print(" (expected 77 'M')\n");
    print("  to_lower('M'): "); print(cast<int>(to_lower('M'))); print(" (expected 109 'm')\n\n");

    // 2. Case conversions
    print("[2] Case conversions:\n");
    string original = "Hello, Magnetar Language!";
    string upper = str_to_upper(original);
    string lower = str_to_lower(original);
    print("  Original: "); print_str(original); print("\n");
    print("  Upper:    "); print_str(upper); print("\n");
    print("  Lower:    "); print_str(lower); print("\n\n");

    // 3. Search and substrings
    print("[3] Search and inspection:\n");
    print("  starts_with 'Hello': "); print(str_starts_with(original, "Hello")); print("\n");
    print("  ends_with 'Language!': "); print(str_ends_with(original, "Language!")); print("\n");
    print("  contains 'Magnetar': "); print(str_contains(original, "Magnetar")); print("\n");
    print("  index_of 'Magnetar': "); print(str_index_of(original, "Magnetar")); print("\n");
    print("  substr(7, 8): "); print_str(str_substr(original, 7, 8)); print(" (expected 'Magnetar')\n\n");

    // 4. Trim and Replace
    print("[4] Trim and Replace:\n");
    string dirty = "   \tMagnetar OS Core   \n";
    string clean_str = str_trim(dirty);
    print("  Trimmed: ["); print_str(clean_str); print("]\n");

    string fruit = "apple pie with apple cider";
    string replaced = str_replace(fruit, "apple", "berry");
    print("  Replaced: "); print_str(replaced); print("\n\n");

    // 5. Conversions
    print("[5] Conversions:\n");
    string s_num = int_to_str(-98765);
    int parsed_num = str_to_int(s_num);
    print("  int_to_str(-98765): "); print_str(s_num); print("\n");
    print("  str_to_int: "); print(parsed_num); print("\n");
    print("  float_to_str(3.14159, 4): "); print_str(float_to_str(3.14159, 4)); print("\n");
    print("  hex_to_str(255): "); print_str(hex_to_str(255)); print(" (expected 0xff)\n\n");

    // 6. StringBuilder
    print("[6] StringBuilder:\n");
    StringBuilder sb;
    sb.init(64);
    sb.append("Buffer: ");
    sb.append_int(100);
    sb.append(" items, ratio = ");
    sb.append(float_to_str(0.85, 2));
    string built = sb.to_string();
    print("  Built string: "); print_str(built); print("\n");
    sb.free_builder();

    print("\n=== ALL STRING LIBRARY TESTS PASSED! ===\n");
}
