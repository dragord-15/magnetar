fn main() {
    int* ip = alloc<int>(3);
    ip[0] = 10; ip[1] = 20; ip[2] = 30;

    float* fp = alloc<float>(3);
    fp[0] = 1.5; fp[1] = 2.5; fp[2] = 3.5;

    char* cp = alloc<char>(3);
    cp[0] = 65; cp[1] = 66; cp[2] = 67;

    print(ip[0]); print(" "); print(ip[1]); print(" "); print(ip[2]); print("|");
    print(fp[0]); print(" "); print(fp[1]); print(" "); print(fp[2]); print("|");
    print(cp[0]); print(cp[1]); print(cp[2]); print("\n");
}
