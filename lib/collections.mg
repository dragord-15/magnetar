// ============================================================================
// Magnetar Standard Library: Collections (lib/collections.mg)
// Dynamic Arrays, Stacks, Queues, and Key-Value Maps
// ============================================================================

use "lib/string.mg";

// -------------------------------------------------------------
// 1. IntList: Dynamic Array of Integers (64-bit)
// -------------------------------------------------------------

struct IntList {
    int* data;
    int length;
    int capacity;

    fn init(int initial_cap) -> void {
        if (initial_cap < 4) {
            initial_cap = 8;
        }
        capacity = initial_cap;
        length = 0;
        data = alloc<int>(capacity);
    }

    fn ensure_capacity(int needed) -> void {
        if (needed > capacity) {
            int new_cap = capacity * 2;
            if (new_cap < needed) {
                new_cap = needed;
            }
            int* new_data = alloc<int>(new_cap);
            for (int i = 0; i < length; i = i + 1) {
                new_data[i] = data[i];
            }
            free(data);
            data = new_data;
            capacity = new_cap;
        }
    }

    fn push(int val) -> void {
        ensure_capacity(length + 1);
        data[length] = val;
        length = length + 1;
    }

    fn pop() -> int {
        if (length <= 0) {
            return 0;
        }
        length = length - 1;
        return data[length];
    }

    fn get(int index) -> int {
        if (index < 0 || index >= length) {
            return 0;
        }
        return data[index];
    }

    fn set_at(int index, int val) -> bool {
        if (index < 0 || index >= length) {
            return false;
        }
        data[index] = val;
        return true;
    }

    fn insert(int index, int val) -> bool {
        if (index < 0 || index > length) {
            return false;
        }
        ensure_capacity(length + 1);
        int i = length;
        while (i > index) {
            data[i] = data[i - 1];
            i = i - 1;
        }
        data[index] = val;
        length = length + 1;
        return true;
    }

    fn remove_at(int index) -> int {
        if (index < 0 || index >= length) {
            return 0;
        }
        int removed = data[index];
        int i = index;
        while (i < length - 1) {
            data[i] = data[i + 1];
            i = i + 1;
        }
        length = length - 1;
        return removed;
    }

    fn index_of(int val) -> int {
        for (int i = 0; i < length; i = i + 1) {
            if (data[i] == val) {
                return i;
            }
        }
        return -1;
    }

    fn contains(int val) -> bool {
        return index_of(val) >= 0;
    }

    fn clear() -> void {
        length = 0;
    }

    fn free_list() -> void {
        if (data != null) {
            free(data);
            data = null;
            length = 0;
            capacity = 0;
        }
    }
};

// -------------------------------------------------------------
// 2. StringList: Dynamic Array of Strings
// -------------------------------------------------------------

struct StringList {
    string* data;
    int length;
    int capacity;

    fn init(int initial_cap) -> void {
        if (initial_cap < 4) {
            initial_cap = 8;
        }
        capacity = initial_cap;
        length = 0;
        data = alloc<string>(capacity);
    }

    fn ensure_capacity(int needed) -> void {
        if (needed > capacity) {
            int new_cap = capacity * 2;
            if (new_cap < needed) {
                new_cap = needed;
            }
            string* new_data = alloc<string>(new_cap);
            for (int i = 0; i < length; i = i + 1) {
                new_data[i] = data[i];
            }
            free(data);
            data = new_data;
            capacity = new_cap;
        }
    }

    fn push(string str) -> void {
        ensure_capacity(length + 1);
        data[length] = str;
        length = length + 1;
    }

    fn pop() -> string {
        if (length <= 0) {
            return "";
        }
        length = length - 1;
        return data[length];
    }

    fn get(int index) -> string {
        if (index < 0 || index >= length) {
            return "";
        }
        return data[index];
    }

    fn set_at(int index, string str) -> bool {
        if (index < 0 || index >= length) {
            return false;
        }
        data[index] = str;
        return true;
    }

    fn remove_at(int index) -> string {
        if (index < 0 || index >= length) {
            return "";
        }
        string removed = data[index];
        int i = index;
        while (i < length - 1) {
            data[i] = data[i + 1];
            i = i + 1;
        }
        length = length - 1;
        return removed;
    }

    fn contains(string str) -> bool {
        for (int i = 0; i < length; i = i + 1) {
            if (str_equals(data[i], str)) {
                return true;
            }
        }
        return false;
    }

    fn join(string delimiter) -> string {
        if (length == 0) {
            return "";
        }
        if (length == 1) {
            return data[0];
        }
        StringBuilder sb;
        sb.init(length * 16);
        for (int i = 0; i < length; i = i + 1) {
            sb.append(data[i]);
            if (i < length - 1) {
                sb.append(delimiter);
            }
        }
        string res = sb.to_string();
        sb.free_builder();
        return res;
    }

    fn clear() -> void {
        length = 0;
    }

    fn free_list() -> void {
        if (data != null) {
            free(data);
            data = null;
            length = 0;
            capacity = 0;
        }
    }
};

// -------------------------------------------------------------
// 3. Stack: LIFO (Last-In First-Out)
// -------------------------------------------------------------

struct Stack {
    int* data;
    int top;
    int capacity;

    fn init(int initial_cap) -> void {
        if (initial_cap < 4) {
            initial_cap = 8;
        }
        capacity = initial_cap;
        top = 0;
        data = alloc<int>(capacity);
    }

    fn push(int val) -> void {
        if (top >= capacity) {
            int new_cap = capacity * 2;
            int* new_data = alloc<int>(new_cap);
            for (int i = 0; i < top; i = i + 1) {
                new_data[i] = data[i];
            }
            free(data);
            data = new_data;
            capacity = new_cap;
        }
        data[top] = val;
        top = top + 1;
    }

    fn pop() -> int {
        if (top <= 0) {
            return 0;
        }
        top = top - 1;
        return data[top];
    }

    fn peek() -> int {
        if (top <= 0) {
            return 0;
        }
        return data[top - 1];
    }

    fn is_empty() -> bool {
        return top <= 0;
    }

    fn size() -> int {
        return top;
    }

    fn free_stack() -> void {
        if (data != null) {
            free(data);
            data = null;
            top = 0;
            capacity = 0;
        }
    }
};

// -------------------------------------------------------------
// 4. Queue: FIFO (First-In First-Out)
// -------------------------------------------------------------

struct Queue {
    int* data;
    int head;
    int tail;
    int count;
    int capacity;

    fn init(int initial_cap) -> void {
        if (initial_cap < 4) {
            initial_cap = 8;
        }
        capacity = initial_cap;
        head = 0;
        tail = 0;
        count = 0;
        data = alloc<int>(capacity);
    }

    fn enqueue(int val) -> void {
        if (count >= capacity) {
            int new_cap = capacity * 2;
            int* new_data = alloc<int>(new_cap);
            for (int i = 0; i < count; i = i + 1) {
                int idx = (head + i) % capacity;
                new_data[i] = data[idx];
            }
            free(data);
            data = new_data;
            head = 0;
            tail = count;
            capacity = new_cap;
        }
        data[tail] = val;
        tail = (tail + 1) % capacity;
        count = count + 1;
    }

    fn dequeue() -> int {
        if (count <= 0) {
            return 0;
        }
        int val = data[head];
        head = (head + 1) % capacity;
        count = count - 1;
        return val;
    }

    fn peek() -> int {
        if (count <= 0) {
            return 0;
        }
        return data[head];
    }

    fn is_empty() -> bool {
        return count <= 0;
    }

    fn size() -> int {
        return count;
    }

    fn free_queue() -> void {
        if (data != null) {
            free(data);
            data = null;
            count = 0;
            capacity = 0;
        }
    }
};

// -------------------------------------------------------------
// 5. Map: String Key-Value Dictionary
// -------------------------------------------------------------

struct Map {
    string* keys;
    string* values;
    int length;
    int capacity;

    fn init(int initial_cap) -> void {
        if (initial_cap < 4) {
            initial_cap = 8;
        }
        capacity = initial_cap;
        length = 0;
        keys = alloc<string>(capacity);
        values = alloc<string>(capacity);
    }

    fn put(string key, string val) -> void {
        for (int i = 0; i < length; i = i + 1) {
            if (str_equals(keys[i], key)) {
                values[i] = val;
                return;
            }
        }
        if (length >= capacity) {
            int new_cap = capacity * 2;
            string* new_k = alloc<string>(new_cap);
            string* new_v = alloc<string>(new_cap);
            for (int j = 0; j < length; j = j + 1) {
                new_k[j] = keys[j];
                new_v[j] = values[j];
            }
            free(keys);
            free(values);
            keys = new_k;
            values = new_v;
            capacity = new_cap;
        }
        keys[length] = key;
        values[length] = val;
        length = length + 1;
    }

    fn get(string key) -> string {
        for (int i = 0; i < length; i = i + 1) {
            if (str_equals(keys[i], key)) {
                return values[i];
            }
        }
        return "";
    }

    fn has(string key) -> bool {
        for (int i = 0; i < length; i = i + 1) {
            if (str_equals(keys[i], key)) {
                return true;
            }
        }
        return false;
    }

    fn remove(string key) -> bool {
        for (int i = 0; i < length; i = i + 1) {
            if (str_equals(keys[i], key)) {
                int j = i;
                while (j < length - 1) {
                    keys[j] = keys[j + 1];
                    values[j] = values[j + 1];
                    j = j + 1;
                }
                length = length - 1;
                return true;
            }
        }
        return false;
    }

    fn count() -> int {
        return length;
    }

    fn free_map() -> void {
        if (keys != null) {
            free(keys);
            free(values);
            keys = null;
            values = null;
            length = 0;
            capacity = 0;
        }
    }
};
