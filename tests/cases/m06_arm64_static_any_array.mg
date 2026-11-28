static fixed<any, 3> g = {1, 2.5, "ok"};

fn main() {
    print(g[0]); print("|");
    print(g[1]); print("|");
    print(g[2]); print("|");
    print(sizeof(g)); print("\n");
}
