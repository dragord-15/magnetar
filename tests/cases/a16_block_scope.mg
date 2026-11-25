fn main() {
    let x = 1;
    { let x = 2.5; print(x); print(" "); }
    print(sizeof(x));
    print("\n");
}
