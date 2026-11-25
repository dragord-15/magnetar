fn main() {
    range r = range(1, 7, 2);
    range q = r;
    print(q.start); print("|");
    print(q.end); print("|");
    print(q.step); print("|");
    for (int i in range(0, 4)) { print(i); }
    print("\n");
}
