use "../lib/serialization.mg";
use "test_common.mg";

fn main() -> int {
    int failures = 0;

    ByteWriter w;
    bw_init(&w, 8);
    check_bool("writer init", w.ok, true, &failures);

    bw_write_u8(&w, 0xAA);
    bw_write_u16(&w, 0xBEEF);
    bw_write_u32(&w, 0x12345678);
    bw_write_u64(&w, 2100000000000000);
    bw_write_varint(&w, 300);

    char* payload = alloc<char>(4);
    if (payload == null) {
        print_str("FAIL alloc payload\n");
        return 1;
    }
    *(payload + 0) = cast<char>(1);
    *(payload + 1) = cast<char>(2);
    *(payload + 2) = cast<char>(3);
    *(payload + 3) = cast<char>(4);
    bw_write_bytes_with_length(&w, payload, 4);

    check_bool("writer ok", w.ok, true, &failures);
    check_int("writer length", w.length, 1 + 2 + 4 + 8 + 3 + 1 + 4, &failures);

    ByteReader r;
    br_init(&r, w.data, w.length);

    check_int("read u8", br_read_u8(&r), 0xAA, &failures);
    check_int("read u16", br_read_u16(&r), 0xBEEF, &failures);
    check_int("read u32", br_read_u32(&r), 0x12345678, &failures);
    check_int("read u64", br_read_u64(&r), 2100000000000000, &failures);
    check_int("read varint", br_read_varint(&r), 300, &failures);

    check_int("read len", br_read_varint(&r), 4, &failures);
    char* out = alloc<char>(4);
    if (out == null) {
        print_str("FAIL alloc out\n");
        free(payload);
        bw_free(&w);
        return 1;
    }
    check_bool("read bytes", br_read_bytes(&r, out, 4), true, &failures);
    check_int("byte0", endian_read_u8(out, 0), 1, &failures);
    check_int("byte3", endian_read_u8(out, 3), 4, &failures);
    check_bool("reader ok", r.ok, true, &failures);
    check_int("remaining", br_remaining(&r), 0, &failures);

    // Reading past the end must fail without crashing.
    int before = r.offset;
    int bad = br_read_u8(&r);
    check_int("past end value", bad, 0, &failures);
    check_int("past end offset", r.offset, before, &failures);
    check_bool("past end ok", r.ok, false, &failures);

    // Truncated length-prefixed bytes: says 4 bytes, only 1 follows.
    char* trunc_data = alloc<char>(2);
    if (trunc_data == null) {
        print_str("FAIL alloc trunc\n");
        free(out);
        free(payload);
        bw_free(&w);
        return 1;
    }
    *(trunc_data + 0) = cast<char>(4);
    *(trunc_data + 1) = cast<char>(9);
    ByteReader trunc;
    br_init(&trunc, trunc_data, 2);
    check_int("trunc len", br_read_varint(&trunc), 4, &failures);
    check_bool("trunc bytes", br_read_bytes(&trunc, out, 4), false, &failures);
    check_bool("trunc ok", trunc.ok, false, &failures);

    free(trunc_data);
    free(out);
    free(payload);
    bw_free(&w);
    return test_report("test_serialization", failures);
}
