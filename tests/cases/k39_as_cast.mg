struct P { int x; }

fn main() {
    let ch = 65 as char;
    print(ch); print("\n");
    let i = 3.9 as int;
    print(i); print("\n");
    let f = 7 as float;
    print(f); print("\n");
    let a = 42 as any;
    print(a); print("\n");
    let b = ("hi") as string;
    print(b); print("\n");
    let n = (1 + 2) as int * 2;
    print(n); print("\n");
    let p = alloc<int>(1);
    p[0] = 9;
    let cp = p as int*;
    print(cp[0]); print("\n");
}
