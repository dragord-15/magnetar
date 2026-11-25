struct P { int x; int y; }
fn main() {
    P a = {1, 2};
    P b = move a;
    print(b.x); print(","); print(b.y); print("|");
    print(a.x); print(","); print(a.y); print("\n");
    int arr[3] = {10, 20, 30};
    int* p = arr;
    int c = move p[1];
    print(c); print("|"); print(p[1]); print("\n");
    int d = move *p;
    print(d); print("|"); print(*p); print("\n");
}
