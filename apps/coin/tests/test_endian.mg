use "../lib/endian.mg";
use "test_common.mg";

fn main() -> int {
    int failures = 0;
    char* buf = alloc<char>(16);
    if (buf == null) {
        print_str("FAIL alloc\n");
        return 1;
    }

    endian_write_u8(buf, 0, 0xAB);
    check_int("u8", endian_read_u8(buf, 0), 0xAB, &failures);

    endian_write_u16_le(buf, 0, 0xBEEF);
    check_int("u16", endian_read_u16_le(buf, 0), 0xBEEF, &failures);

    endian_write_u32_le(buf, 0, 0x12345678);
    check_int("u32", endian_read_u32_le(buf, 0), 0x12345678, &failures);

    endian_write_u64_le(buf, 0, 0x0102030405060708);
    check_int("u64", endian_read_u64_le(buf, 0), 0x0102030405060708, &failures);

    endian_write_u32_le(buf, 4, 0xFFFFFFFF);
    check_int("u32max", endian_read_u32_le(buf, 4), 4294967295, &failures);

    endian_write_i64_le(buf, 0, 2100000000000000);
    check_int("i64money", endian_read_i64_le(buf, 0), 2100000000000000, &failures);

    // Little-endian layout check: 0x12345678 -> 78 56 34 12
    endian_write_u32_le(buf, 0, 0x12345678);
    check_int("byte0", endian_read_u8(buf, 0), 0x78, &failures);
    check_int("byte1", endian_read_u8(buf, 1), 0x56, &failures);
    check_int("byte2", endian_read_u8(buf, 2), 0x34, &failures);
    check_int("byte3", endian_read_u8(buf, 3), 0x12, &failures);

    // High bytes must not be sign-extended.
    endian_write_u16_le(buf, 0, 0x80FF);
    check_int("u16high", endian_read_u16_le(buf, 0), 0x80FF, &failures);

    free(buf);
    return test_report("test_endian", failures);
}
