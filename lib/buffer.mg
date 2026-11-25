// ============================================================================
// Magnetar Standard Library: Growable Byte Buffer (lib/buffer.mg)
// Binary-safe buffer used by the HTTP/TLS stack.
// Unlike `string`, this buffer keeps an explicit length, so it can hold NUL
// bytes (images, compressed bodies, encrypted payloads, ...).
// ============================================================================

use "lib/string.mg";

struct ByteBuffer {
    char* data;
    int length;
    int capacity;

    fn init(int initial_capacity) -> void {
        if (initial_capacity < 32) {
            initial_capacity = 256;
        }
        capacity = initial_capacity;
        data = alloc<char>(capacity + 1);
        length = 0;
        *(data + 0) = 0;
    }

    fn ensure(int extra) -> void {
        if (length + extra + 1 <= capacity) {
            return;
        }
        int new_cap = capacity;
        while (new_cap < length + extra + 1) {
            new_cap = new_cap * 2;
        }
        char* next = alloc<char>(new_cap + 1);
        for (int i = 0; i < length; i = i + 1) {
            *(next + i) = *(data + i);
        }
        *(next + length) = 0;
        if (data != null) {
            free(data);
        }
        data = next;
        capacity = new_cap;
    }

    fn append(char* src, int count) -> void {
        if (src == null || count <= 0) {
            return;
        }
        ensure(count);
        for (int i = 0; i < count; i = i + 1) {
            *(data + length + i) = *(src + i);
        }
        length = length + count;
        *(data + length) = 0;
    }

    fn append_str(string text) -> void {
        if (text == null) {
            return;
        }
        append(cast<char*>(text), len(text));
    }

    fn append_char(char c) -> void {
        ensure(1);
        *(data + length) = c;
        length = length + 1;
        *(data + length) = 0;
    }

    fn append_int(int value) -> void {
        string s = int_to_str(value);
        append_str(s);
        free(cast<char*>(s));
    }

    fn clear() -> void {
        length = 0;
        if (data != null) {
            *(data + 0) = 0;
        }
    }

    fn to_string() -> string {
        if (data == null) {
            return "";
        }
        return cast<string>(data);
    }

    fn slice_string(int start, int count) -> string {
        if (start < 0) { start = 0; }
        if (start >= length || count <= 0) { return ""; }
        if (start + count > length) { count = length - start; }
        char* out = alloc<char>(count + 1);
        for (int i = 0; i < count; i = i + 1) {
            *(out + i) = *(data + start + i);
        }
        *(out + count) = 0;
        return cast<string>(out);
    }

    fn clone_bytes() -> char* {
        char* out = alloc<char>(length + 1);
        for (int i = 0; i < length; i = i + 1) {
            *(out + i) = *(data + i);
        }
        *(out + length) = 0;
        return out;
    }

    fn free_buffer() -> void {
        if (data != null) {
            free(data);
            data = null;
        }
        length = 0;
        capacity = 0;
    }
};

fn buffer_new() -> ByteBuffer {
    ByteBuffer b;
    b.init(256);
    return b;
}

fn buffer_from_string(string text) -> ByteBuffer {
    ByteBuffer b;
    b.init(len(text) + 32);
    b.append_str(text);
    return b;
}

fn buffer_index_of(ByteBuffer b, char* needle, int needle_len) -> int {
    if (b.data == null || needle == null || needle_len <= 0) {
        return -1;
    }
    int last = b.length - needle_len;
    int i = 0;
    while (i <= last) {
        bool matched = true;
        int j = 0;
        while (j < needle_len) {
            if (*(b.data + i + j) != *(needle + j)) {
                matched = false;
                j = needle_len;
            } else {
                j = j + 1;
            }
        }
        if (matched) {
            return i;
        }
        i = i + 1;
    }
    return -1;
}
