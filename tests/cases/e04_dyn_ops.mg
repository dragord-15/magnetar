fn main() {
    dyn<int> d = {4, 5, 6};
    d.push(7);
    print(d.len()); print("|");
    print(d[0]); print("|");
    print(d[3]); print("|");
    print(d.pop()); print("|");
    print(d.len()); print("\n");
    d.clear();
    print(d.len()); print("\n");
}
