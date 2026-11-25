fn add(any a, any b) -> any {
    return a + b;
}

fn main() {
    any a = 10;
    any b = 3;
    print(a + b); print("\n");
    print(a - b); print("\n");
    print(a * b); print("\n");
    print(a / b); print("\n");
    print(a % b); print("\n");

    any x = 2.5;
    any y = 4.0;
    print(x + y); print("\n");
    print(x * y); print("\n");
    print(a + x); print("\n");

    any s = "foo";
    any t = "bar";
    print(s + t); print("\n");
    print(s < t); print("\n");
    print(s == "foo"); print("\n");

    any c = a + b;
    print(c); print("\n");
    any d = x + y;
    print(d); print("\n");

    print((a + b) * 2); print("\n");
    print(add(a, b)); print("\n");
    print(add(x, y)); print("\n");

    print(cast<int>(x)); print("\n");
    print(cast<float>(a)); print("\n");
    any e = cast<any>(3.5);
    print(e); print("\n");
    print(cast<any>(2.5) + cast<any>(1.5)); print("\n");
}
