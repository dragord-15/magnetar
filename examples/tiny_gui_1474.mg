fn main() -> int {
    asm("
    // env path '/proc/self/environ'
    mov dword [rbp-96], 0x6f72702f;
    mov dword [rbp-92], 0x65732f63;
    mov dword [rbp-88], 0x652f666c;
    mov dword [rbp-84], 0x7269766e;
    mov dword [rbp-80], 0x00006e6f;
    // key 'XAUTHORITY='
    mov dword [rbp-128], 0x54554158;
    mov dword [rbp-124], 0x49524f48;
    mov dword [rbp-120], 0x003d5954;
    // unix socket path '/tmp/.X11-unix/X0'

    mov dword [rbp-96], 0x6e75722f;
    mov dword [rbp-92], 0x6573752f;
    mov dword [rbp-88], 0x30312f72;
    mov dword [rbp-84], 0x2e2f3130;
    mov dword [rbp-80], 0x7474756d;
    mov dword [rbp-76], 0x582d7265;
    mov dword [rbp-72], 0x6c796177;
    mov dword [rbp-68], 0x61646e61;
    mov dword [rbp-64], 0x2e687475;
    mov dword [rbp-60], 0x35324e46;
    mov dword [rbp-56], 0x3359;
    lea rsi, [rbp-96];
    HAVE_PATH:
    mov eax, 2;
    mov rdi, rsi;
    xor esi, esi;
    xor edx, edx;
    syscall;
    mov ebx, eax;
    test eax, eax;
    js NOAUTH;
    mov eax, 9;
    xor edi, edi;
    mov esi, 1024;
    mov edx, 3;
    mov r10d, 34;
    mov r8, -1;
    xor r9d, r9d;
    syscall;
    mov r14, rax;
    mov eax, 0;
    mov edi, ebx;
    mov rsi, r14;
    mov edx, 1024;
    syscall;
    mov eax, 3;
    mov edi, ebx;
    syscall;

    lea rax, [r14+17];
    mov [rbp-24], rax;
    lea rax, [r14+37];
    mov [rbp-32], rax;
    mov rax, 18;
    mov [rbp-8], rax;
    mov rax, 16;
    mov [rbp-16], rax;
    jmp AUTH_READY;

    NOAUTH:
    xor eax, eax;
    mov [rbp-8], rax;
    mov [rbp-16], rax;
    mov [rbp-24], rax;
    mov [rbp-32], rax;

    AUTH_READY:
    mov eax, 41;
    mov edi, 1;
    mov esi, 1;
    xor edx, edx;
    syscall;
    mov ebx, eax;

    mov dword [rbp-256], 0x742f0001;
    mov dword [rbp-252], 0x2e2f706d;
    mov dword [rbp-248], 0x2d313158;
    mov dword [rbp-244], 0x78696e75;
    mov dword [rbp-240], 0x0030582f;
    mov eax, 42;
    mov edi, ebx;
    lea rsi, [rbp-256];
    mov edx, 110;
    syscall;

    mov dword [rbp-384], 0x000b006c;
    mov dword [rbp-380], 0;
    mov eax, [rbp-8];
    mov edx, [rbp-16];
    shl edx, 16;
    or eax, edx;
    mov [rbp-378], eax;

    mov dword [rbp-512], 0;
    lea rax, [rbp-384];
    mov [rbp-480], rax;
    mov rax, 12;
    mov [rbp-472], rax;
    mov rax, [rbp-24];
    mov [rbp-464], rax;
    mov eax, [rbp-8];
    mov [rbp-456], rax;
    lea rax, [rbp-512];
    mov [rbp-448], rax;
    mov rax, 2;
    mov [rbp-440], rax;
    mov rax, [rbp-32];
    mov [rbp-432], rax;
    mov eax, [rbp-16];
    mov [rbp-424], rax;
    mov eax, 20;
    mov edi, ebx;
    lea rsi, [rbp-480];
    mov edx, 4;
    syscall;

    mov eax, 45;
    mov edi, ebx;
    lea rsi, [rbp-528];
    mov edx, 8;
    xor r10d, r10d;
    xor r8d, r8d;
    xor r9d, r9d;
    syscall;

    mov eax, [rbp-522];
    and eax, 255;
    mov edx, [rbp-521];
    and edx, 255;
    shl edx, 8;
    or eax, edx;
    shl eax, 2;
    mov r15d, eax;

    mov eax, 9;
    xor edi, edi;
    mov esi, 32768;
    mov edx, 3;
    mov r10d, 34;
    mov r8, -1;
    xor r9d, r9d;
    syscall;
    mov r14, rax;
    mov eax, 45;
    mov edi, ebx;
    mov rsi, r14;
    mov edx, r15d;
    xor r10d, r10d;
    xor r8d, r8d;
    xor r9d, r9d;
    syscall;

    mov r13d, [r14+4];
    mov eax, [r14+16];
    and eax, 255;
    mov edx, [r14+17];
    and edx, 255;
    shl edx, 8;
    or eax, edx;
    add eax, 3;
    and eax, -4;
    mov edx, [r14+21];
    and edx, 255;
    shl edx, 3;
    add eax, edx;
    add eax, 32;
    mov r15d, eax;
    mov r12d, [r14+rax];
    mov eax, r15d;
    add eax, 32;
    mov r11d, [r14+rax];
    mov eax, r15d;
    add eax, 38;
    mov eax, [r14+rax];
    and eax, 255;
    mov [rbp-72], eax;

    // create window
    mov dword [rbp-592], 0;
    mov dword [rbp-588], 0;
    mov dword [rbp-584], 0;
    mov dword [rbp-580], 0;
    mov dword [rbp-576], 0;
    mov dword [rbp-572], 0;
    mov dword [rbp-568], 0;
    mov dword [rbp-564], 0;
    mov dword [rbp-560], 0;
    mov dword [rbp-556], 0;
    mov dword [rbp-552], 0;
    lea rdi, [rbp-592];
    mov eax, 1;
    mov edx, [rbp-72];
    shl edx, 8;
    or eax, edx;
    mov edx, 11;
    shl edx, 16;
    or eax, edx;
    mov [rdi], eax;
    lea rax, [r13+1];
    mov [rdi+4], rax;
    mov [rdi+8], r12;
    mov dword [rdi+12], 0x00640064;
    mov dword [rdi+16], 0x00400040;
    mov dword [rdi+20], 0x00010001;
    mov [rdi+24], r11;
    mov dword [rdi+28], 2058;
    mov dword [rdi+32], 0x141824;
    mov dword [rdi+36], 0x36425a;
    mov dword [rdi+40], 199183;
    mov eax, 44;
    mov edi, ebx;
    lea rsi, [rbp-592];
    mov edx, 44;
    xor r10d, r10d;
    xor r8d, r8d;
    xor r9d, r9d;
    syscall;

    // create gc
    mov dword [rbp-624], 0;
    mov dword [rbp-620], 0;
    mov dword [rbp-616], 0;
    mov dword [rbp-612], 0;
    lea rdi, [rbp-624];
    mov eax, 55;
    mov edx, 4;
    shl edx, 16;
    or eax, edx;
    mov [rdi], eax;
    lea rax, [r13+2];
    mov [rdi+4], rax;
    lea rax, [r13+1];
    mov [rdi+8], rax;
    mov eax, 44;
    mov edi, ebx;
    lea rsi, [rbp-624];
    mov edx, 16;
    xor r10d, r10d;
    xor r8d, r8d;
    xor r9d, r9d;
    syscall;

    // map window
    mov dword [rbp-640], 0;
    mov dword [rbp-636], 0;
    lea rdi, [rbp-640];
    mov eax, 8;
    mov edx, 2;
    shl edx, 16;
    or eax, edx;
    mov [rdi], eax;
    lea rax, [r13+1];
    mov [rdi+4], rax;
    mov eax, 44;
    mov edi, ebx;
    lea rsi, [rbp-640];
    mov edx, 8;
    xor r10d, r10d;
    xor r8d, r8d;
    xor r9d, r9d;
    syscall;

    mov dword [rbp-656], 2;
    mov dword [rbp-652], 0;
    mov dword [rbp-648], 500000000;
    mov dword [rbp-644], 0;
    mov eax, 35;
    lea rdi, [rbp-656];
    xor esi, esi;
    syscall;
    ");
    return 0;
}
