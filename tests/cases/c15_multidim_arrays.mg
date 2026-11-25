fn main() {
    int grid[2][3] = {{1,2,3},{4,5,6}};
    int[2][3] typed = {{10,20,30},{40,50,60}};
    fixed<fixed<int,3>,2> nested = {{7,8,9},{11,12,13}};
    int cube[2][2][2] = {{{1,2},{3,4}},{{5,6},{7,8}}};
    int i = 1;
    int j = 2;
    print(grid[i][j]); print(" ");
    print(typed[0][2]); print(" ");
    print(nested[1][0]); print(" ");
    print(cube[1][1][0]); print(" ");
    cube[0][1][1] = 99;
    print(cube[0][1][1]); print(" ");
    print(sizeof(grid)); print(" ");
    print(sizeof(cube)); print("\n");
}
