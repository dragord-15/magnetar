struct P { int x; fn scaled(int k) -> int { return this.x * k; } }
fn main() {
    P p;
    p.x = 5;
    print(p.scaled(3));
    print("\n");
}
