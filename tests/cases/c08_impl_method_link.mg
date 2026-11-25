struct P { int x; }
impl P { fn get() -> int { return 7; } }
fn main() {
    P p;
    print(p.get());
    print("\n");
}
