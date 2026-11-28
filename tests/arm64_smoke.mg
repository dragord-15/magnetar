// Standalone ARM64 smoke test for magc.
// Compile: ./magc tests/arm64_smoke.mg -o arm64_smoke
// Run:     ./arm64_smoke

fn main() {
    print("ARM64 smoke test\n");

    int a = 7;
    int b = 5;
    print(a + b);
    print("\n");

    fixed<int, 3> xs = {1, 2, 3};
    for (int i = 0; i < 3; i++) {
        print(xs[i]);
        print(" ");
    }
    print("\n");
}
