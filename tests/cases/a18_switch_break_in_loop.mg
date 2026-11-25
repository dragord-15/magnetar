fn main() {
    let i = 0;
    while (i < 3) {
        i = i + 1;
        switch (i) {
            case 1: { print("one"); }
            default: { break; }
        }
        print(".");
    }
    print("\n");
}
