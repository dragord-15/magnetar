struct P { int x; int y; }
fn main() {
    P p = P { 7, 9 };
    any a = p;
    let q: int* = cast<int*>(a);
    print(q[0]); print(" "); print(q[1]); print("\n");

    let arr: fixed<int, 3> = {10, 20, 30};
    any b = arr;
    let r: int* = cast<int*>(b);
    print(r[1]); print("\n");
}
