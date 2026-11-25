struct A { int w; int v; }
struct B { int v; int w; }
fn main() {
    B b = {33, 44};
    b.v = 99;
    print(b.v);
    print("|");
    print(b.w);
    print("\n");
}
