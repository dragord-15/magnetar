extern fn sin(float x) -> float;
extern fn cos(float x) -> float;
extern fn tan(float x) -> float;
extern fn exp(float x) -> float;
extern fn log(float x) -> float;
extern fn pow(float x, float y) -> float;

fn main() {
    print(sin(0.5)); print("|");
    print(cos(0.5)); print("|");
    print(tan(0.5)); print("|");
    print(exp(1.0)); print("|");
    print(log(2.0)); print("|");
    print(pow(2.0, 3.0)); print("|");
    print(pow(2.0, -2.0)); print("\n");
}
