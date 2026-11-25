// Magnetar Coin — little-endian integer codec.
//
// Magnetar's `int` is signed 64-bit. All consensus integers in MGC are
// little-endian. u64 values above 2^63-1 are read as the same bit pattern
// (negative in language terms); MGC never needs such values (timestamps and
// satoshi amounts are far below 2^63).

fn endian_read_u8(char* data, int offset) -> int {
    if (data == null || offset < 0) { return 0; }
    return cast<int>(*(data + offset)) & 255;
}

fn endian_write_u8(char* data, int offset, int value) -> void {
    if (data == null || offset < 0) { return; }
    *(data + offset) = cast<char>(value & 255);
}

fn endian_read_u16_le(char* data, int offset) -> int {
    if (data == null || offset < 0) { return 0; }
    return (cast<int>(*(data + offset)) & 255) |
           ((cast<int>(*(data + offset + 1)) & 255) << 8);
}

fn endian_write_u16_le(char* data, int offset, int value) -> void {
    if (data == null || offset < 0) { return; }
    *(data + offset) = cast<char>(value & 255);
    *(data + offset + 1) = cast<char>((value >> 8) & 255);
}

fn endian_read_u32_le(char* data, int offset) -> int {
    if (data == null || offset < 0) { return 0; }
    int b0 = cast<int>(*(data + offset)) & 255;
    int b1 = cast<int>(*(data + offset + 1)) & 255;
    int b2 = cast<int>(*(data + offset + 2)) & 255;
    int b3 = cast<int>(*(data + offset + 3)) & 255;
    return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
}

fn endian_write_u32_le(char* data, int offset, int value) -> void {
    if (data == null || offset < 0) { return; }
    *(data + offset) = cast<char>(value & 255);
    *(data + offset + 1) = cast<char>((value >> 8) & 255);
    *(data + offset + 2) = cast<char>((value >> 16) & 255);
    *(data + offset + 3) = cast<char>((value >> 24) & 255);
}

fn endian_read_u64_le(char* data, int offset) -> int {
    if (data == null || offset < 0) { return 0; }
    int value = 0;
    for (int i = 0; i < 8; i = i + 1) {
        int b = cast<int>(*(data + offset + i)) & 255;
        value = value | (b << (i * 8));
    }
    return value;
}

fn endian_write_u64_le(char* data, int offset, int value) -> void {
    if (data == null || offset < 0) { return; }
    for (int i = 0; i < 8; i = i + 1) {
        *(data + offset + i) = cast<char>((value >> (i * 8)) & 255);
    }
}

fn endian_read_i64_le(char* data, int offset) -> int {
    return endian_read_u64_le(data, offset);
}

fn endian_write_i64_le(char* data, int offset, int value) -> void {
    endian_write_u64_le(data, offset, value);
}
