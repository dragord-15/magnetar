fn main() {
    int pid = async { int x = 4; };
    print(pid > 0); print("\n");
    print(await pid); print("\n");
}
