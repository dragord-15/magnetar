fn main() {
    let i = 0;
    while (i < 3) {
        i = i + 1;
        match (i) {
            1 => { print("one"); }
            _ => { break; }
        }
        print(".");
    }
    print("\n");
}
