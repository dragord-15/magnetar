fn main() {
    asm {
        mov rax, 1;
        shl rax, 3;
        add rax, 2;
        mov rdi, rax;
        mov rax, 60;
        syscall;
    }
}
