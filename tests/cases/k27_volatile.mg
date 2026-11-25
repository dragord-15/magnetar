volatile int g = 5;
fn main() {
    volatile int x = 10;
    x = x + 1;
    g = g + 1;
    print(x); print("|"); print(g); print("\n");
}

