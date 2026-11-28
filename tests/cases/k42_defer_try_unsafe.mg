fn f() -> int {
    defer print(9);
    print(1);
    return 5;
}

fn main() {
    print(f()); print("|");
    unsafe { print(8); }
    print("|");
    try {
        print(1);
        throw 7;
        print(2);
    } catch {
        print(3);
    } finally {
        print(4);
    }
    print("\n");
}
