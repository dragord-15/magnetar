fn main() {
    int pid = spawn { int x = 1; };
    print(pid > 0); print("\n");
    int st = await pid;
    print(st); print("\n");
    int none = await;
    print(none); print("\n");
}
