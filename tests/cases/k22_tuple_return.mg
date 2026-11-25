fn make3() -> tuple<int, int, int> {
    tuple<int, int, int> t;
    t._0 = 1;
    t._1 = 2;
    t._2 = 3;
    return t;
}
struct P { int x; int y; }
fn makep() -> P {
    P p = {7, 9};
    return p;
}
fn make2() -> tuple<int, int> {
    return (7, 9);
}
fn main() {
    tuple<int, int, int> t = make3();
    print(t._0); print("|"); print(t._1); print("|"); print(t._2); print("\n");
    P p = makep();
    print(p.x); print("|"); print(p.y); print("\n");
    tuple<int, int> u = make2();
    print(u._0); print("|"); print(u._1); print("\n");
    tuple<int, float, string> v = (1, 2.5, "x");
    print(v._0); print("|"); print(v._1); print("|"); print(v._2); print("\n");
    print((5, 6)._0); print("\n");
}
