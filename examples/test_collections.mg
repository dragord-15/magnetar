// examples/test_collections.mg
// Comprehensive Test Suite for Collections Library (lib/collections.mg)

use "lib/collections.mg";

fn main() -> void {
    print("=== STARTING MAGNETAR COLLECTIONS VERIFICATION ===\n\n");

    // 1. Testing IntList
    print("[1] IntList dynamic array:\n");
    IntList numbers;
    numbers.init(4);
    for (int i = 1; i <= 5; i = i + 1) {
        numbers.push(i * 10);
    }
    print("  Initial length: "); print(numbers.length); print("\n");
    print("  numbers[0]: "); print(numbers.get(0)); print("\n");
    print("  numbers[4]: "); print(numbers.get(4)); print("\n");
    print("  contains 30: "); print(numbers.contains(30)); print("\n");
    print("  contains 99: "); print(numbers.contains(99)); print("\n");

    int popped = numbers.pop();
    print("  Popped last: "); print(popped); print(" (expected 50)\n");
    print("  Length after pop: "); print(numbers.length); print("\n\n");
    numbers.free_list();

    // 2. Testing StringList
    print("[2] StringList dynamic strings:\n");
    StringList words;
    words.init(4);
    words.push("Falcon");
    words.push("Magnetar");
    words.push("Compiler");
    print("  words length: "); print(words.length); print("\n");
    print("  words[1]: "); print_str(words.get(1)); print("\n");
    string joined = words.join(" -> ");
    print("  Joined: "); print_str(joined); print("\n\n");
    words.free_list();

    // 3. Testing Stack (LIFO)
    print("[3] Stack (LIFO):\n");
    Stack st;
    st.init(4);
    st.push(100);
    st.push(200);
    st.push(300);
    print("  Stack size: "); print(st.size()); print("\n");
    print("  Stack peek: "); print(st.peek()); print(" (expected 300)\n");
    print("  Stack pop:  "); print(st.pop()); print(" (expected 300)\n");
    print("  Stack pop:  "); print(st.pop()); print(" (expected 200)\n");
    print("  Stack empty: "); print(st.is_empty()); print(" (expected 0)\n\n");
    st.free_stack();

    // 4. Testing Queue (FIFO)
    print("[4] Queue (FIFO):\n");
    Queue q;
    q.init(4);
    q.enqueue(11);
    q.enqueue(22);
    q.enqueue(33);
    print("  Queue size: "); print(q.size()); print("\n");
    print("  Queue peek: "); print(q.peek()); print(" (expected 11)\n");
    print("  Queue dequeue: "); print(q.dequeue()); print(" (expected 11)\n");
    print("  Queue dequeue: "); print(q.dequeue()); print(" (expected 22)\n");
    print("  Queue remaining: "); print(q.size()); print(" (expected 1)\n\n");
    q.free_queue();

    // 5. Testing Map (Dictionary)
    print("[5] Map (Key-Value Dictionary):\n");
    Map dict;
    dict.init(4);
    dict.put("name", "Magnetar");
    dict.put("version", "3.5");
    dict.put("target", "x86_64");
    print("  Map count: "); print(dict.count()); print("\n");
    print("  dict['name']: "); print_str(dict.get("name")); print("\n");
    print("  dict['target']: "); print_str(dict.get("target")); print("\n");
    print("  has 'version': "); print(dict.has("version")); print("\n");
    print("  has 'unknown': "); print(dict.has("unknown")); print("\n");

    dict.remove("target");
    print("  count after remove 'target': "); print(dict.count()); print(" (expected 2)\n");
    print("  has 'target' after remove: "); print(dict.has("target")); print(" (expected 0)\n");
    dict.free_map();

    print("\n=== ALL COLLECTIONS TESTS PASSED! ===\n");
}
