fn main() {
    print(sizeof(int)); print(" ");
    print(sizeof(float)); print(" ");
    print(sizeof(char)); print("\n");

    int* block = alloc<int>(3);
    block[0] = 10;
    block[1] = 20;
    block[2] = 30;
    print(block[0]); print(" ");
    print(block[1]); print(" ");
    print(block[2]); print("\n");
    free(block);

    float* f = alloc<float>(3);
    f[0] = 1.5;
    f[1] = 2.5;
    f[2] = 3.5;
    print(f[0]); print(" ");
    print(f[1]); print(" ");
    print(f[2]); print("\n");
    free(f);

    char* c = alloc<char>(3);
    c[0] = cast<char>(65);
    c[1] = cast<char>(66);
    c[2] = cast<char>(67);
    print(c[0]); print(c[1]); print(c[2]); print("\n");
    free(c);
}
