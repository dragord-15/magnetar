fn bump() { static let c = 0; c = c + 1; return c; }
fn main() {
    print(bump()); print(" ");
    print(bump()); print(" ");
    print(bump());
    print("\n");
}
