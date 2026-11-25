struct Buf { int data[4]; }
fn main() {
    Buf b;
    b.data[0] = 7;
    print(b.data[0]);
    print("\n");
}
