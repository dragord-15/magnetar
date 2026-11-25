struct Grid { int cells[2][3]; }
class Base { int cube[2][2][2]; }
class Derived extends Base { int extra; }
fn main() {
    Grid g;
    g.cells[0][0] = 11;
    g.cells[1][2] = 22;
    print(g.cells[0][0]); print(" ");
    print(g.cells[1][2]); print(" ");
    print(sizeof(g.cells)); print(" ");
    Derived d;
    d.cube[1][0][1] = 77;
    print(d.cube[1][0][1]); print(" ");
    print(sizeof(d.cube)); print("\n");
}
