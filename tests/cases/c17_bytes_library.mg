use "../../lib/bytes.mg";

fn main() {
    print_str(bytes_to_string(0)); print("|");
    print_str(bytes_to_string(500)); print("|");
    print_str(bytes_to_string(1023)); print("|");
    print_str(bytes_to_string(1024)); print("|");
    print_str(bytes_to_string(1536)); print("|");
    print_str(bytes_to_string(1048576)); print("|");
    print_str(bytes_to_string(5767168)); print("|");
    print_str(bytes_to_string(2147483648)); print("|");
    print_str(bytes_to_string(3298534883328)); print("|");
    print_str(bytes_to_string(4503599627370496)); print("|");
    print_str(bytes_to_string(5764607523034234880)); print("|");
    print_str(bytes_to_string_prec(1536, 0)); print("|");
    print_str(bytes_to_string_si(1500)); print("|");
    print_str(bytes_to_string_si(1000000)); print("|");
    print_str(bytes_unit_name(bytes_unit_index(1536))); print("|");
    print(unit_to_bytes(1.5, 1)); print("|");
    print(bytes_to_bits(2)); print("|");
    print(bits_to_bytes(16)); print("\n");
}
