// examples/test_bytes.mg
// Demo for the data-size library (lib/bytes.mg)

use "lib/bytes.mg";

fn main() -> void {
    print("=== MAGNETAR BYTES LIBRARY ===\n\n");

    print("Binary units (1 KB = 1024 B):\n");
    print("  0 B        -> "); print_str(bytes_to_string(0)); print("\n");
    print("  500 B      -> "); print_str(bytes_to_string(500)); print("\n");
    print("  1024 B     -> "); print_str(bytes_to_string(1024)); print("\n");
    print("  1536 B     -> "); print_str(bytes_to_string(1536)); print("\n");
    print("  1 MiB      -> "); print_str(bytes_to_string(1048576)); print("\n");
    print("  5.5 MiB    -> "); print_str(bytes_to_string(5767168)); print("\n");
    print("  2 GiB      -> "); print_str(bytes_to_string(2147483648)); print("\n");
    print("  3 TiB      -> "); print_str(bytes_to_string(3298534883328)); print("\n");
    print("  4 PiB      -> "); print_str(bytes_to_string(4503599627370496)); print("\n");
    print("  5 EiB      -> "); print_str(bytes_to_string(5764607523034234880)); print("\n\n");

    print("SI decimal units (1 KB = 1000 B):\n");
    print("  1500 B     -> "); print_str(bytes_to_string_si(1500)); print("\n");
    print("  1000000 B  -> "); print_str(bytes_to_string_si(1000000)); print("\n\n");

    print("Custom precision:\n");
    print("  1536 B, 0 decimals -> "); print_str(bytes_to_string_prec(1536, 0)); print("\n");
    print("  1536 B, 4 decimals -> "); print_str(bytes_to_string_prec(1536, 4)); print("\n\n");

    print("Manual unit / reverse conversion:\n");
    print("  unit index of 1536 B: "); print(bytes_unit_index(1536)); print("\n");
    print("  unit name:            "); print_str(bytes_unit_name(bytes_unit_index(1536))); print("\n");
    print("  1.5 KB in bytes:      "); print(unit_to_bytes(1.5, 1)); print("\n");
    print("  2 bytes in bits:      "); print(bytes_to_bits(2)); print("\n");

    print("\n=== DONE ===\n");
}
