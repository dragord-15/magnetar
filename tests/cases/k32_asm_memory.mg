fn main() {
    asm {
        mov rax, 42;
        push rax;
        mov rax, 0;
        mov rax, [rsp];
        add rax, 8;
        pop rcx;
        mov rdi, rax;
        mov rax, 60;
        syscall;
    }
}
