use "../lib/varint.mg";
use "test_common.mg";

fn main() -> int {
    int failures = 0;
    char* buf = alloc<char>(32);
    if (buf == null) {
        print_str("FAIL alloc\n");
        return 1;
    }

    int values[8] = {0, 1, 252, 253, 65535, 65536, 4294967295, 4294967296};

    for (int i = 0; i < 8; i = i + 1) {
        int value = values[i];
        int written = varint_write(buf, 0, value);
        check_int("size", written, varint_size(value), &failures);

        int offset = 0;
        bool ok = false;
        int decoded = varint_read(buf, written, &offset, &ok);
        check_bool("read ok", ok, true, &failures);
        check_int("roundtrip", decoded, value, &failures);
        check_int("consumed", offset, written, &failures);
    }

    // Truncated 0xFD marker.
    buf[0] = cast<char>(253);
    int offset = 0;
    bool ok = true;
    int decoded = varint_read(buf, 1, &offset, &ok);
    check_bool("truncated", ok, false, &failures);
    check_int("truncated value", decoded, 0, &failures);

    // Empty input.
    offset = 0;
    ok = true;
    decoded = varint_read(buf, 0, &offset, &ok);
    check_bool("empty", ok, false, &failures);

    // Negative writer must be rejected.
    ok = true;
    int next = varint_write_checked(buf, 0, -1, &ok);
    check_bool("negative", ok, false, &failures);
    check_int("negative offset", next, 0, &failures);

    free(buf);
    return test_report("test_varint", failures);
}
