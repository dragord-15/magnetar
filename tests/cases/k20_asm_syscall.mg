fn main() {
    asm("mov rax, 60");
    asm("mov rdi, 7");
    asm("syscall");
    print("unreachable\n");
}
