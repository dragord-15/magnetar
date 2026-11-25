fn main() {
    let s = 0;
    for (let i = 0; i < 5; i = i + 1) {
        if (i == 2) { continue; }
        s = s + i;
    }
    print(s);
    print("\n");
}
