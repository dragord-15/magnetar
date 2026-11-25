struct Point { int x; int y; }
fn main() {
    Point a = {111, 222};
    Point b;
    b = a;
    print(b.x);
    print("|");
    print(b.y);
    print("\n");
}
