struct Basket { string items[3]; }

fn echo(string s) {
    print("<");
    print(s);
    print(">");
}

fn main() {
    let fixed_names: fixed<string, 3> = {"ali", "bob", "cat"};
    print(fixed_names[0]); print(" ");
    print(fixed_names[1]); print(" ");
    print(fixed_names[2]); print("\n");

    string names[3] = {"one", "two", "three"};
    names[1] = "TWO";
    print(names[1]); print(" ");
    print(names[0] + "+" + names[2]); print("\n");

    if (names[0] == "one") { print("equal"); } else { print("different"); }
    print("\n");

    string grid[2][2] = {{"a", "b"}, {"c", "d"}};
    print(grid[0][0]); print(grid[0][1]);
    print(grid[1][0]); print(grid[1][1]); print("\n");

    Basket b;
    b.items[0] = "red";
    b.items[1] = "green";
    print(b.items[0]); print(" "); print(b.items[1]); print("\n");

    dyn<string> d = {"dyn1", "dyn2"};
    print(d[0]); print("\n");

    string* heap = alloc<string>(2);
    heap[0] = "heap0";
    heap[1] = "heap1";
    print(heap[0]); print(" "); print(heap[1]); print("\n");

    echo(fixed_names[2]); print("\n");
}
