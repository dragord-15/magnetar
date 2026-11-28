fn main() {
    /* The ARM64 backend maps x86 syscall registers to AArch64 x0-x5 and
       translates the write syscall number. */
    string msg = "asm write\n";
    asm {
        mov rax, 1;
        mov rdi, 1;
        mov rsi, [msg];
        mov rdx, 10;
        syscall;
    }
}
