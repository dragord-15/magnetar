struct S {
    any a;
    int b;
    any vals[2];
};

class C {
    any v;
    int n;
};

union U {
    any v;
    int n;
};

fn main() {
    print(sizeof(any)); print("\n");
    print(sizeof(any[3])); print("\n");

    any arr[3];
    arr[0] = "one";
    arr[1] = 2;
    arr[2] = 3.5;
    print(arr[0]); print(" ");
    print(arr[1]); print(" ");
    print(arr[2]); print("\n");

    any grid[2][2];
    grid[0][0] = "a"; grid[0][1] = 1;
    grid[1][0] = 2.5; grid[1][1] = "d";
    print(grid[0][0]); print(" ");
    print(grid[0][1]); print(" ");
    print(grid[1][0]); print(" ");
    print(grid[1][1]); print("\n");
    print(sizeof(grid)); print("\n");

    let s: S;
    s.a = "field";
    s.b = 7;
    s.vals[0] = 11;
    s.vals[1] = "tail";
    print(s.a); print(" ");
    print(s.b); print(" ");
    print(s.vals[0]); print(" ");
    print(s.vals[1]); print("\n");
    print(sizeof(S)); print("\n");

    let lit = S { "init", 9, { 4, 5.5 } };
    print(lit.a); print(" ");
    print(lit.b); print(" ");
    print(lit.vals[0]); print(" ");
    print(lit.vals[1]); print("\n");

    let c: C;
    c.v = "class";
    c.n = 3;
    print(c.v); print(" ");
    print(c.n); print("\n");
    print(sizeof(C)); print("\n");

    let u: U;
    u.v = 4.75;
    print(u.v); print("\n");
    print(sizeof(U)); print("\n");

    let p: any* = alloc<any>(3);
    p[0] = "zero"; p[1] = 8; p[2] = 1.25;
    print(p[0]); print(" ");
    print(p[1]); print(" ");
    print(p[2]); print("\n");
}
