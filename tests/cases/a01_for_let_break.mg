fn main() {
    for (let i = 0; i < 10; i = i + 1) {
        if (i == 3) { break; }
        print(i);
    }
    print("|");
    for (let i = 0; i < 5; i = i + 1) {
        if (i == 2) { continue; }
        print(i);
    }
    print("|");
    for (int i = 0; i < 10; i = i + 1) {
        if (i == 3) { break; }
        print(i);
    }
    print("\n");
}
