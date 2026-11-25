fn main() {
    float a[3];
    a[0] = 1.5; a[1] = 2.5; a[2] = 3.5;
    print(a[0] + a[1] + a[2]);
    print("|");
    float* p = alloc<float>(2);
    p[0] = 4.5;
    p[1] = 5.5;
    print(p[0] + p[1]);
    print("|");
    a[1] = 8.5;
    print(a[1]);
    print("\n");
    free(p);
}
