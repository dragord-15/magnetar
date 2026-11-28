struct A {
    int v;
    fn init() -> int { return 11; }
    fn via_this() -> int { return this.init(); }
}
struct B {
    int v;
    fn init() -> int { return 22; }
}

fn sum9(int a, int b, int c, int d, int e, int f, int g, int h, int i) -> int {
    return a + b + c + d + e + f + g + h + i;
}

fn main() {
    A a;
    print(sum9(1,2,3,4,5,6,7,8,9)); print("\n");
    print(a.via_this()); print("\n");
}
