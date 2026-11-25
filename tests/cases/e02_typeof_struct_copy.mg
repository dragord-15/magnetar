struct Point { int x; int y; }
fn main() {
    Point p = {3, 4};
    typeof(p) q = p;
    q.x = 30;
    print(p.x); print("|");
    print(q.x); print("|");
    print(q.y); print("|");
    typeof(p.x) n = p.x + p.y;
    print(n); print("\n");
}
