struct C {
    int v;
    fn m(int a, int b, int c, int d, int e, int f, int g, int h) -> int {
        return a + b + c + d + e + f + g + h;
    }
}

fn sum12(int a, int b, int c, int d, int e, int f, int g, int h,
         int i, int j, int k, int l) -> int {
    return a + b + c + d + e + f + g + h + i + j + k + l;
}

fn main() {
    C c;
    print(sum12(1,2,3,4,5,6,7,8,9,10,11,12)); print("\n");
    print(c.m(1,2,3,4,5,6,7,8)); print("\n");
}
