fn main() {
    /* `any` array slots are 16 bytes on both backends; this catches the
       ARM64 frame-corruption bug that previously hid in dead stack space. */
    fixed<any, 2> a = {7, "ok"};
    print(a[0]); print("|"); print(a[1]); print("|");
    print(sizeof(a)); print("\n");
}
