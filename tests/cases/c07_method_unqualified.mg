extern fn sqrt(float x) -> float;
struct V { float x; fn mag() -> float { return sqrt(this.x * this.x); } fn twice() -> float { return mag() + mag(); } }
fn main() {
    V v;
    v.x = 3.0;
    print(v.twice());
    print("\n");
}
