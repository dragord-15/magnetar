fn main() {
    int x = 33;
    int y = 0;
    asm {
        lea rax, [y];
        mov rcx, 50;
        mov [rax], rcx;
        mov rax, [y];
        add rax, [x];
        sub rax, 33;
        mov rdi, rax;
        mov rax, 60;
        syscall;
    }
}
