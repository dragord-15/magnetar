// Magnetar Coin — bounded readers and growable writers.
// Every read is checked; deserializers must never trust input lengths.

use "endian.mg";
use "varint.mg";
use "util.mg";

struct ByteReader {
    char* data;
    int length;
    int offset;
    bool ok;
}

fn br_init(ByteReader* r, char* data, int length) -> void {
    if (r == null) { return; }
    r.data = data;
    r.length = length;
    r.offset = 0;
    if (data == null && length > 0) {
        r.ok = false;
    } else {
        r.ok = true;
    }
}

fn br_remaining(ByteReader* r) -> int {
    if (r == null || !r.ok) { return 0; }
    int left = r.length - r.offset;
    if (left < 0) { return 0; }
    return left;
}

fn br_read_u8(ByteReader* r) -> int {
    if (r == null || !r.ok || r.offset + 1 > r.length) {
        if (r != null) { r.ok = false; }
        return 0;
    }
    int v = endian_read_u8(r.data, r.offset);
    r.offset = r.offset + 1;
    return v;
}

fn br_read_u16(ByteReader* r) -> int {
    if (r == null || !r.ok || r.offset + 2 > r.length) {
        if (r != null) { r.ok = false; }
        return 0;
    }
    int v = endian_read_u16_le(r.data, r.offset);
    r.offset = r.offset + 2;
    return v;
}

fn br_read_u32(ByteReader* r) -> int {
    if (r == null || !r.ok || r.offset + 4 > r.length) {
        if (r != null) { r.ok = false; }
        return 0;
    }
    int v = endian_read_u32_le(r.data, r.offset);
    r.offset = r.offset + 4;
    return v;
}

fn br_read_u64(ByteReader* r) -> int {
    if (r == null || !r.ok || r.offset + 8 > r.length) {
        if (r != null) { r.ok = false; }
        return 0;
    }
    int v = endian_read_u64_le(r.data, r.offset);
    r.offset = r.offset + 8;
    return v;
}

fn br_read_varint(ByteReader* r) -> int {
    if (r == null || !r.ok) { return 0; }

    // Do not pass &r.offset directly: the current backend loses the field
    // address in nested calls. Use a local and copy it back.
    int offset = r.offset;
    bool ok = false;
    int v = varint_read(r.data, r.length, &offset, &ok);
    if (!ok) {
        r.ok = false;
        return 0;
    }
    r.offset = offset;
    return v;
}

fn br_read_bytes(ByteReader* r, char* out, int count) -> bool {
    if (r == null || !r.ok || out == null || count < 0) {
        if (r != null) { r.ok = false; }
        return false;
    }
    if (r.offset + count > r.length) {
        r.ok = false;
        return false;
    }
    mgc_copy(out, r.data + r.offset, count);
    r.offset = r.offset + count;
    return true;
}

struct ByteWriter {
    char* data;
    int length;
    int capacity;
    bool ok;
}

fn bw_init(ByteWriter* w, int initial_capacity) -> void {
    if (w == null) { return; }
    if (initial_capacity < 16) { initial_capacity = 16; }
    w.data = alloc<char>(initial_capacity);
    w.length = 0;
    w.capacity = initial_capacity;
    w.ok = (w.data != null);
}

fn bw_ensure(ByteWriter* w, int extra) -> bool {
    if (w == null || !w.ok || extra < 0) {
        if (w != null) { w.ok = false; }
        return false;
    }
    int needed = w.length + extra;
    if (needed <= w.capacity) { return true; }

    int new_capacity = w.capacity;
    while (new_capacity < needed) {
        new_capacity = new_capacity * 2;
    }
    char* fresh = alloc<char>(new_capacity);
    if (fresh == null) {
        w.ok = false;
        return false;
    }
    mgc_copy(fresh, w.data, w.length);
    free(w.data);
    w.data = fresh;
    w.capacity = new_capacity;
    return true;
}

fn bw_write_u8(ByteWriter* w, int value) -> bool {
    if (!bw_ensure(w, 1)) { return false; }
    endian_write_u8(w.data, w.length, value);
    w.length = w.length + 1;
    return true;
}

fn bw_write_u16(ByteWriter* w, int value) -> bool {
    if (!bw_ensure(w, 2)) { return false; }
    endian_write_u16_le(w.data, w.length, value);
    w.length = w.length + 2;
    return true;
}

fn bw_write_u32(ByteWriter* w, int value) -> bool {
    if (!bw_ensure(w, 4)) { return false; }
    endian_write_u32_le(w.data, w.length, value);
    w.length = w.length + 4;
    return true;
}

fn bw_write_u64(ByteWriter* w, int value) -> bool {
    if (!bw_ensure(w, 8)) { return false; }
    endian_write_u64_le(w.data, w.length, value);
    w.length = w.length + 8;
    return true;
}

fn bw_write_varint(ByteWriter* w, int value) -> bool {
    if (w == null || !w.ok || value < 0) {
        if (w != null) { w.ok = false; }
        return false;
    }
    if (!bw_ensure(w, 9)) { return false; }
    bool ok = false;
    int next = varint_write_checked(w.data, w.length, value, &ok);
    if (!ok) {
        w.ok = false;
        return false;
    }
    w.length = next;
    return true;
}

fn bw_write_bytes(ByteWriter* w, char* data, int count) -> bool {
    if (w == null || !w.ok || count < 0) {
        if (w != null) { w.ok = false; }
        return false;
    }
    if (count == 0) { return true; }
    if (data == null) {
        w.ok = false;
        return false;
    }
    if (!bw_ensure(w, count)) { return false; }
    mgc_copy(w.data + w.length, data, count);
    w.length = w.length + count;
    return true;
}

fn bw_write_bytes_with_length(ByteWriter* w, char* data, int count) -> bool {
    if (!bw_write_varint(w, count)) { return false; }
    return bw_write_bytes(w, data, count);
}

fn bw_reset(ByteWriter* w) -> void {
    if (w == null) { return; }
    w.length = 0;
    w.ok = (w.data != null);
}

fn bw_free(ByteWriter* w) -> void {
    if (w == null) { return; }
    if (w.data != null) {
        free(w.data);
        w.data = null;
    }
    w.length = 0;
    w.capacity = 0;
    w.ok = false;
}
