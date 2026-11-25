// Magnetar Coin — SHA-256d throughput benchmark over an 80-byte block header.

use "../lib/hash.mg";

extern fn print_str(string s) -> void;
extern fn get_timestamp() -> int;

fn main() -> int {
    int iterations = 1000000;
    char* data = alloc<char>(80);
    char* digest = alloc<char>(32);
    if (data == null || digest == null) {
        print_str("error: out of memory\n");
        if (data != null) { free(data); }
        if (digest != null) { free(digest); }
        return 1;
    }
    for (int i = 0; i < 80; i = i + 1) { *(data + i) = cast<char>(i & 255); }

    int start = get_timestamp();
    for (int i = 0; i < iterations; i = i + 1) {
        mgc_sha256d_raw(data, 80, digest);
    }
    int end = get_timestamp();
    int seconds = end - start;
    if (seconds < 1) { seconds = 1; }

    print_str("iterations: ");
    print(iterations);
    print_str("\n");
    print_str("seconds: ");
    print(seconds);
    print_str("\n");
    print_str("H/s: ");
    print(iterations / seconds);
    print_str("\n");
    print_str("digest: ");
    print_str(crypto_hex_encode(digest, 32));
    print_str("\n");

    free(digest);
    free(data);
    return 0;
}
