enum Color { RED, GREEN, BLUE }

fn main() {
    fixed<int, 3> a = {1, 2, 3};
    slice<int> s = a[1..3];
    ptr<int> p = alloc<int>(1);
    *p = 9;

    print(s[0]); print("|"); print(s[1]); print("|");
    print(Color.BLUE); print("|"); print(*p); print("\n");

    int i = 0;
    do { i++; print(i); } while (i < 2);
    print("\n");
}
