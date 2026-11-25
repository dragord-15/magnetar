// Magnetar Coin — Bitcoin-style CompactSize (varint).
// Values are non-negative; negative input is rejected by the checked writer.

use "endian.mg";

fn varint_size(int value) -> int {
    if (value < 0) { return 9; }
    if (value < 253) { return 1; }
    if (value <= 65535) { return 3; }
    if (value <= 4294967295) { return 5; }
    return 9;
}

fn varint_write(char* out, int offset, int value) -> int {
    if (out == null || offset < 0) { return offset; }

    if (value < 253) {
        endian_write_u8(out, offset, value);
        return offset + 1;
    }
    if (value <= 65535) {
        endian_write_u8(out, offset, 253);
        endian_write_u16_le(out, offset + 1, value);
        return offset + 3;
    }
    if (value <= 4294967295) {
        endian_write_u8(out, offset, 254);
        endian_write_u32_le(out, offset + 1, value);
        return offset + 5;
    }

    endian_write_u8(out, offset, 255);
    endian_write_u64_le(out, offset + 1, value);
    return offset + 9;
}

fn varint_write_checked(char* out, int offset, int value, bool* ok) -> int {
    if (ok == null) { return offset; }
    if (out == null || offset < 0 || value < 0) {
        *ok = false;
        return offset;
    }
    *ok = true;
    return varint_write(out, offset, value);
}

fn varint_read(char* data, int length, int* offset, bool* ok) -> int {
    if (ok == null) { return 0; }
    *ok = false;
    if (data == null || offset == null) { return 0; }

    int off = *offset;
    if (off < 0 || off >= length) { return 0; }

    int first = endian_read_u8(data, off);
    off = off + 1;

    if (first < 253) {
        *offset = off;
        *ok = true;
        return first;
    }

    int count = 2;
    if (first == 253) {
        count = 2;
    } else if (first == 254) {
        count = 4;
    } else {
        count = 8;
    }

    if (off + count > length) { return 0; }

    int value = 0;
    for (int i = 0; i < count; i = i + 1) {
        int b = endian_read_u8(data, off + i);
        value = value | (b << (i * 8));
    }

    *offset = off + count;
    *ok = true;

    if (count == 8 && value < 0) {
        *ok = false;
        return 0;
    }

    return value;
}
