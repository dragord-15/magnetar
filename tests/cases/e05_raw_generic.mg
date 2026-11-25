fn main() {
    raw<int> p = alloc<int>(3);
    p[0] = 10; p[1] = 20; p[2] = 30;
    print(p[0] + p[1] + p[2]);
    print("|");
    raw<char> c = alloc<char>(2);
    c[0] = cast<char>(65);
    c[1] = cast<char>(66);
    print(c[0]); print(c[1]);
    print("\n");
    free(p);
    free(c);
}
