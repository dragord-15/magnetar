use "../lib/ripemd160.mg";
use "../../lib/crypto.mg";
use "test_common.mg";

extern fn print_str(string s) -> void;

fn main() -> int {
    int failures = 0;
    char* out = alloc<char>(20);
    if (out == null) {
        print_str("FAIL alloc\n");
        return 1;
    }

    ripemd160_raw(null, 0, out);
    check_string("rmd160 empty", crypto_hex_encode(out, 20),
                 "9c1185a5c5e9fc54612808977ee8f548b2258d31", &failures);

    ripemd160_raw(cast<char*>("abc"), 3, out);
    check_string("rmd160 abc", crypto_hex_encode(out, 20),
                 "8eb208f7e05d987a9b044a8e98c6b087f15a0bfc", &failures);

    ripemd160_raw(cast<char*>("message digest"), 14, out);
    check_string("rmd160 message digest", crypto_hex_encode(out, 20),
                 "5d0689ef49d2fae572b881b123a85ffa21595f36", &failures);

    ripemd160_raw(cast<char*>("abcdefghijklmnopqrstuvwxyz"), 26, out);
    check_string("rmd160 alpha", crypto_hex_encode(out, 20),
                 "f71c27109c692c1b56bbdceb5b9d2865b3708dbc", &failures);

    ripemd160_raw(cast<char*>("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"), 56, out);
    check_string("rmd160 abcdbcde...", crypto_hex_encode(out, 20),
                 "12a053384a9c0c88e405a06c27dcf49ada62eb2b", &failures);

    ripemd160_raw(cast<char*>("12345678901234567890123456789012345678901234567890123456789012345678901234567890"), 80, out);
    check_string("rmd160 digits80", crypto_hex_encode(out, 20),
                 "9b752e45573d4b39f4dbd3323cab82bf63326bfb", &failures);

    free(out);
    return test_report("test_ripemd160", failures);
}
