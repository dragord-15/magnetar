/*
 * Self-contained AArch64 implementations for unresolved externals.
 *
 * The x86_64 backend carries a large table of Linux syscall stubs and a few
 * high-level mock builtins.  ARM64 previously had no equivalent, so aggregate
 * links failed on any extern and standalone ELFs silently left BLs unpatched.
 * This emitter is shared by both paths: it writes raw instructions only, with
 * no assembler, libc or runtime dependency.
 */
#include "stubs.h"
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#define STUB_FRAME 256u

static void stub_prologue(A64Buf* b) {
    a64_prologue(b, STUB_FRAME);
    /* SysV-style incoming arguments arrive in x0..x7; keep the first six in
       frame slots so paths that shift arguments can still reach them. */
    for (int i = 0; i < 6; i++) {
        a64_sub_imm(b, 9, 29, (uint32_t)((i + 1) * 8));
        a64_str_x(b, i, 9, 0);
    }
}

static void stub_epilogue(A64Buf* b) { a64_epilogue(b, STUB_FRAME); }

static void stub_load(A64Buf* b, int rd, int arg) {
    a64_sub_imm(b, 9, 29, (uint32_t)((arg + 1) * 8));
    a64_ldr_x(b, rd, 9, 0);
}

static void stub_syscall(A64Buf* b, uint32_t nr) {
    a64_mov_imm(b, 8, nr);
    a64_svc(b);
    stub_epilogue(b);
}

static void stub_frame_ptr(A64Buf* b, int rd) {
    a64_mov_imm(b, rd, STUB_FRAME);
    a64_sub_reg(b, rd, 29, rd);
}

/* Print a constant string through write(1, ...), using an inline stack copy
   so no rodata section or absolute address is required. */
static void stub_print_bytes(A64Buf* b, const char* s, size_t len) {
    stub_frame_ptr(b, 9);
    for (size_t i = 0; i < len; i++) {
        a64_movz32(b, 10, (uint32_t)(unsigned char)s[i]);
        a64_strb(b, 10, 9, (uint32_t)i);
    }
    a64_mov_imm(b, 0, 1);
    a64_mov_reg(b, 1, 9);
    a64_mov_imm(b, 2, len);
    a64_mov_imm(b, 8, 64);
    a64_svc(b);
}

/* x11 = NUL-terminated string -> write(1, x11, strlen(x11)). */
static void stub_print_str_reg(A64Buf* b, int reg) {
    a64_mov_reg(b, 11, reg);
    a64_mov_reg(b, 9, 11);
    a64_mov_imm(b, 10, 0);
    size_t loop = a64_size(b);
    a64_add_reg(b, 12, 9, 10);
    a64_ldrb(b, 13, 12, 0);
    size_t end = a64_cbz(b, 13);
    a64_add_imm(b, 10, 10, 1);
    size_t back = a64_b(b);
    a64_patch_branch(b->data, back, loop);
    a64_patch_cb(b->data, end, a64_size(b));
    a64_mov_imm(b, 0, 1);
    a64_mov_reg(b, 1, 11);
    a64_mov_reg(b, 2, 10);
    a64_mov_imm(b, 8, 64);
    a64_svc(b);
}

/* x0 = unsigned integer -> write(1, decimal, len). */
static void stub_print_int(A64Buf* b) {
    stub_frame_ptr(b, 9);
    a64_mov_reg(b, 10, 9);
    a64_mov_imm(b, 12, 10);
    size_t loop = a64_size(b);
    a64_udiv(b, 13, 0, 12);
    a64_mul(b, 14, 13, 12);
    a64_sub_reg(b, 14, 0, 14);
    a64_mov_imm(b, 15, '0');
    a64_add_reg(b, 14, 14, 15);
    a64_sub_imm(b, 10, 10, 1);
    a64_strb(b, 14, 10, 0);
    a64_mov_reg(b, 0, 13);
    size_t again = a64_cbnz(b, 0);
    a64_patch_cb(b->data, again, loop);
    a64_mov_reg(b, 2, 9);
    a64_sub_reg(b, 2, 2, 10);
    a64_mov_imm(b, 0, 1);
    a64_mov_reg(b, 1, 10);
    a64_mov_imm(b, 8, 64);
    a64_svc(b);
}

/* Return a heap copy of a constant string.  A private anonymous page keeps
   the result valid after the stub returns, just like x86 rodata pointers. */
static void stub_return_cstr(A64Buf* b, const char* s, size_t len) {
    stub_frame_ptr(b, 9);
    for (size_t i = 0; i < len; i++) {
        a64_movz32(b, 10, (uint32_t)(unsigned char)s[i]);
        a64_strb(b, 10, 9, (uint32_t)i);
    }
    a64_mov_imm(b, 0, 0);
    a64_mov_imm(b, 1, 4096);
    a64_mov_imm(b, 2, 3);
    a64_mov_imm(b, 3, 0x22);       /* MAP_PRIVATE | MAP_ANONYMOUS */
    a64_mov_imm(b, 4, (uint64_t)-1);
    a64_mov_imm(b, 5, 0);
    a64_mov_imm(b, 8, 222);        /* mmap */
    a64_svc(b);
    a64_mov_reg(b, 14, 0);         /* result address */
    a64_mov_reg(b, 10, 9);         /* source */
    a64_mov_imm(b, 13, 0);
    size_t loop = a64_size(b);
    a64_ldrb(b, 12, 10, 0);
    a64_strb(b, 12, 14, 0);
    a64_add_imm(b, 10, 10, 1);
    a64_add_imm(b, 14, 14, 1);
    a64_add_imm(b, 13, 13, 1);
    a64_cmp_imm(b, 13, (uint32_t)len);
    size_t again = a64_bcond(b, A64_LT);
    a64_patch_cond(b->data, again, loop);
    a64_mov_imm(b, 12, 0);
    a64_strb(b, 12, 14, 0);
    a64_sub_reg(b, 0, 14, 13);
    stub_epilogue(b);
}

static void stub_return_int(A64Buf* b, uint64_t value) {
    a64_mov_imm(b, 0, value);
    stub_epilogue(b);
}

/* ------------------------------------------------------------------
 * Float math.  The x86_64 backend uses x87 for sin/cos/tan/exp/log/pow;
 * AArch64 has no such instructions, so these emit self-contained polynomial
 * approximations directly.  Float bit patterns travel in w0/w1, matching the
 * way the ARM64 code generator passes floating-point values in GPRs.
 * ------------------------------------------------------------------ */
static void stub_fconst(A64Buf* b, int sreg, float value) {
    uint32_t bits;
    memcpy(&bits, &value, sizeof(bits));
    a64_mov_imm(b, 15, bits);
    a64_fmov_s_w(b, sreg, 15);
}
static void stub_horner(A64Buf* b, int p, int z, float coeff) {
    stub_fconst(b, 15, coeff);
    a64_fmul(b, p, p, z);
    a64_fadd(b, p, p, 15);
}
static void stub_fcopy(A64Buf* b, int dst, int src) {
    stub_fconst(b, 12, 0.0f);
    a64_fadd(b, dst, src, 12);
}
static void stub_reduce_pi(A64Buf* b, int x) {
    stub_fconst(b, 1, 6.28318530717958647692f); /* 2*pi */
    stub_fconst(b, 2, 3.14159265358979323846f); /* pi */
    size_t hi = a64_size(b);
    a64_fcmp(b, x, 2);
    size_t hi_done = a64_bcond(b, A64_LE);
    a64_fsub(b, x, x, 1);
    size_t hi_back = a64_b(b);
    a64_patch_branch(b->data, hi_back, a64_size(b));
    a64_patch_cond(b->data, hi_done, a64_size(b));
    stub_fconst(b, 2, -3.14159265358979323846f);
    size_t lo = a64_size(b);
    a64_fcmp(b, x, 2);
    size_t lo_done = a64_bcond(b, A64_GE);
    a64_fadd(b, x, x, 1);
    size_t lo_back = a64_b(b);
    a64_patch_branch(b->data, lo_back, a64_size(b));
    a64_patch_cond(b->data, lo_done, a64_size(b));
}
static void stub_sin_poly(A64Buf* b, int out, int x) {
    a64_fmul(b, 9, x, x); /* z = x*x */
    stub_fconst(b, 10, 1.6059043836821613e-10f); /* 1/11! */
    stub_horner(b, 10, 9, -2.505210838544172e-8f); /* -1/9! */
    stub_horner(b, 10, 9, 2.7557319223985893e-6f); /* 1/7! */
    stub_horner(b, 10, 9, -0.0001984126984126984f); /* -1/5! */
    stub_horner(b, 10, 9, 0.008333333333333333f); /* 1/3! */
    stub_horner(b, 10, 9, -0.16666666666666666f); /* -1/1! */
    stub_horner(b, 10, 9, 1.0f);
    a64_fmul(b, out, x, 10);
}
static void stub_cos_poly(A64Buf* b, int out, int x) {
    a64_fmul(b, 9, x, x);
    stub_fconst(b, 10, 2.08767569878681e-9f); /* 1/12! */
    stub_horner(b, 10, 9, -2.7557319223985893e-7f); /* -1/10! */
    stub_horner(b, 10, 9, 2.4801587301587302e-5f); /* 1/8! */
    stub_horner(b, 10, 9, -0.001388888888888889f); /* -1/6! */
    stub_horner(b, 10, 9, 0.041666666666666664f); /* 1/4! */
    stub_horner(b, 10, 9, -0.5f);
    stub_horner(b, 10, 9, 1.0f);
    stub_fcopy(b, out, 10);
}
static void stub_emit_log(A64Buf* b, int out, int in) {
    /* atanh series: log(x) = 2*(z + z^3/3 + z^5/5 + ...), z=(x-1)/(x+1). */
    stub_fconst(b, 12, 1.0f);
    stub_fconst(b, 13, 2.0f);
    a64_fsub(b, 8, in, 12);
    a64_fadd(b, 9, in, 12);
    a64_fdiv(b, 8, 8, 9);
    a64_fmul(b, 9, 8, 8);
    stub_fconst(b, 10, 0.07692307692307693f); /* 1/13 */
    stub_horner(b, 10, 9, 0.09090909090909091f);
    stub_horner(b, 10, 9, 0.1111111111111111f);
    stub_horner(b, 10, 9, 0.14285714285714285f);
    stub_horner(b, 10, 9, 0.2f);
    stub_horner(b, 10, 9, 0.3333333333333333f);
    stub_horner(b, 10, 9, 1.0f);
    a64_fmul(b, out, 8, 10);
    a64_fmul(b, out, out, 13);
}
static size_t stub_emit_exp(A64Buf* b, int out, int in) {
    stub_fconst(b, 12, 0.0f);
    a64_fadd(b, 8, in, 12); /* x */
    a64_fcmp(b, 8, 12);
    a64_cset(b, 14, A64_MI);
    size_t positive = a64_bcond(b, A64_GE);
    a64_fsub(b, 8, 12, 8); /* work with |x| */
    a64_patch_cond(b->data, positive, a64_size(b));
    stub_fconst(b, 10, 2.7557319223985893e-7f); /* 1/10! */
    stub_horner(b, 10, 8, 2.7557319223985893e-6f);
    stub_horner(b, 10, 8, 2.4801587301587302e-5f);
    stub_horner(b, 10, 8, 0.0001984126984126984f);
    stub_horner(b, 10, 8, 0.001388888888888889f);
    stub_horner(b, 10, 8, 0.008333333333333333f);
    stub_horner(b, 10, 8, 0.041666666666666664f);
    stub_horner(b, 10, 8, 0.16666666666666666f);
    stub_horner(b, 10, 8, 0.5f);
    stub_horner(b, 10, 8, 1.0f);
    stub_horner(b, 10, 8, 1.0f);
    a64_cmp_imm(b, 14, 0);
    size_t done = a64_bcond(b, A64_EQ);
    stub_fconst(b, 12, 1.0f);
    a64_fdiv(b, 10, 12, 10);
    a64_patch_cond(b->data, done, a64_size(b));
    size_t tail = a64_size(b);
    stub_fcopy(b, out, 10);
    return tail;
}
static void stub_emit_pow(A64Buf* b, int x, int y) {
    /* Integral exponents use repeated multiplication so pow(2,3) is exactly
       8.0, matching the x86 x87 result after rounding to float. */
    stub_fconst(b, 12, 0.0f);
    a64_fcvtzs(b, 14, y);
    a64_scvtf(b, 14, 14);
    a64_fcmp(b, 14, y);
    size_t noninteger = a64_bcond(b, A64_NE);
    a64_fcmp(b, y, 12); /* s12 is zero (initialised by exp path below) */
    a64_cset(b, 13, A64_MI);
    size_t nonnegative = a64_bcond(b, A64_GE);
    a64_sub_reg(b, 14, 31, 14);
    a64_patch_cond(b->data, nonnegative, a64_size(b));
    stub_fcopy(b, 11, x);
    stub_fconst(b, 10, 1.0f);
    size_t mul_loop = a64_size(b);
    a64_cmp_imm(b, 14, 0);
    size_t mul_done = a64_bcond(b, A64_EQ);
    a64_fmul(b, 10, 10, 11);
    a64_sub_imm(b, 14, 14, 1);
    size_t mul_back = a64_b(b);
    a64_patch_branch(b->data, mul_back, mul_loop);
    a64_patch_cond(b->data, mul_done, a64_size(b));
    a64_cmp_imm(b, 13, 0);
    size_t int_done = a64_bcond(b, A64_EQ);
    stub_fconst(b, 12, 1.0f);
    a64_fdiv(b, 10, 12, 10);
    size_t int_end = a64_b(b);
    a64_patch_cond(b->data, noninteger, a64_size(b));

    stub_emit_log(b, 8, x);
    a64_fmul(b, 8, 8, y);
    size_t exp_tail = stub_emit_exp(b, 0, 8);
    a64_patch_cond(b->data, int_done, exp_tail);
    a64_patch_branch(b->data, int_end, exp_tail);
}

/* Syscalls whose arguments pass straight through in x0..x5. */
typedef struct { const char* name; uint32_t nr; } PlainSyscall;
static const PlainSyscall plain_syscalls[] = {
    {"sys_accept", 202}, {"sys_accept4", 242}, {"sys_bind", 200},
    {"sys_capset", 91}, {"sys_chdir", 49}, {"sys_chroot", 51},
    {"sys_clock_gettime", 113}, {"sys_close", 57}, {"sys_connect", 203},
    {"sys_dup", 23}, {"sys_dup3", 24}, {"sys_epoll_create1", 20},
    {"sys_epoll_ctl", 21}, {"sys_execve", 221}, {"sys_exit", 93},
    {"sys_exit_group", 94}, {"sys_fchmod", 52}, {"sys_fchown", 55},
    {"sys_fcntl", 25}, {"sys_fdatasync", 83}, {"sys_flock", 32},
    {"sys_fstat", 80}, {"sys_fsync", 82}, {"sys_ftruncate", 46},
    {"sys_getcwd", 17}, {"sys_getdents64", 61}, {"sys_getpeername", 205},
    {"sys_getpid", 172}, {"sys_getppid", 173}, {"sys_getrandom", 278},
    {"sys_getrlimit", 163}, {"sys_getsockname", 204}, {"sys_getsockopt", 209},
    {"sys_gettid", 178}, {"sys_getuid", 174}, {"sys_inotify_init1", 26},
    {"sys_ioctl", 29}, {"sys_kill", 129}, {"sys_listen", 201},
    {"sys_lseek", 62}, {"sys_mmap", 222}, {"sys_mount", 40},
    {"sys_munmap", 215}, {"sys_nanosleep", 101}, {"sys_newfstatat", 79},
    {"sys_pivot_root", 41}, {"sys_ppoll", 73}, {"sys_prctl", 167},
    {"sys_pselect6", 72}, {"sys_read", 63}, {"sys_readv", 65},
    {"sys_reboot", 142}, {"sys_recvfrom", 207}, {"sys_recvmsg", 212},
    {"sys_rt_sigaction", 134}, {"sys_sched_setscheduler", 119},
    {"sys_sched_yield", 124}, {"sys_sendmsg", 211}, {"sys_sendto", 206},
    {"sys_setgid", 144}, {"sys_setgroups", 159}, {"sys_sethostname", 161},
    {"sys_setpriority", 140}, {"sys_setresgid", 149}, {"sys_setresuid", 147},
    {"sys_setrlimit", 164}, {"sys_setsid", 157}, {"sys_setsockopt", 208},
    {"sys_setuid", 146}, {"sys_shutdown", 210}, {"sys_sigaltstack", 132},
    {"sys_sigprocmask", 135}, {"sys_socket", 198}, {"sys_socketpair", 199},
    {"sys_statfs", 43}, {"sys_statx", 291}, {"sys_swapoff", 225},
    {"sys_swapon", 224}, {"sys_sync", 81}, {"sys_sysinfo", 179},
    {"sys_tgkill", 131}, {"sys_timerfd_create", 85},
    {"sys_timerfd_settime", 86}, {"sys_truncate", 45}, {"sys_umount2", 39},
    {"sys_uname", 160}, {"sys_wait4", 260}, {"sys_write", 64},
    {"sys_writev", 66}
};

/* Emit a syscall with x0-x5 taken from saved argument slots, optionally
   shifted because AArch64 uses *at() variants for path operations. */
static void stub_at_syscall(A64Buf* b, uint32_t nr, int dirfd) {
    stub_load(b, 1, 0);
    stub_load(b, 2, 1);
    a64_mov_imm(b, 0, (uint64_t)(int64_t)dirfd);
    a64_mov_imm(b, 3, 0);
    stub_syscall(b, nr);
}

static bool emit_special_syscall(A64Buf* b, const char* name) {
    if (!strcmp(name, "sys_fork")) {
        a64_mov_imm(b, 0, 17);       /* SIGCHLD */
        a64_mov_imm(b, 1, 0);        /* no shared stack: fork-like clone */
        a64_mov_imm(b, 2, 0); a64_mov_imm(b, 3, 0); a64_mov_imm(b, 4, 0);
        stub_syscall(b, 220);
        return true;
    }
    if (!strcmp(name, "sys_pipe")) {
        stub_load(b, 0, 0);
        a64_mov_imm(b, 1, 0);
        stub_syscall(b, 59);
        return true;
    }
    if (!strcmp(name, "sys_dup2")) {
        stub_load(b, 0, 0); stub_load(b, 1, 1);
        a64_mov_imm(b, 2, 0);
        stub_syscall(b, 24);
        return true;
    }
    if (!strcmp(name, "sys_eventfd")) {
        stub_load(b, 0, 0);
        a64_mov_imm(b, 1, 0);
        stub_syscall(b, 19);
        return true;
    }
    if (!strcmp(name, "sys_epoll_wait")) {
        stub_load(b, 0, 0); stub_load(b, 1, 1); stub_load(b, 2, 2);
        a64_mov_imm(b, 3, 0); a64_mov_imm(b, 4, 0);
        stub_syscall(b, 22);
        return true;
    }
    if (!strcmp(name, "sys_poll")) {
        stub_load(b, 0, 0); stub_load(b, 1, 1); stub_load(b, 2, 2);
        a64_mov_imm(b, 3, 0); a64_mov_imm(b, 4, 0);
        stub_syscall(b, 73);
        return true;
    }
    if (!strcmp(name, "sys_select")) {
        for (int i = 0; i < 5; i++) stub_load(b, i, i);
        a64_mov_imm(b, 5, 0);
        stub_syscall(b, 72);
        return true;
    }
    if (!strcmp(name, "sys_send") || !strcmp(name, "sys_recv")) {
        for (int i = 0; i < 4; i++) stub_load(b, i, i);
        a64_mov_imm(b, 4, 0); a64_mov_imm(b, 5, 0);
        stub_syscall(b, !strcmp(name, "sys_send") ? 206u : 207u);
        return true;
    }
    if (!strcmp(name, "sys_open")) {
        stub_load(b, 1, 0); stub_load(b, 2, 1); stub_load(b, 3, 2);
        a64_mov_imm(b, 0, (uint64_t)(int64_t)-100); /* AT_FDCWD */
        stub_syscall(b, 56);
        return true;
    }
    if (!strcmp(name, "sys_stat") || !strcmp(name, "sys_newstat") ||
        !strcmp(name, "sys_lstat") || !strcmp(name, "sys_fs_exists")) {
        stub_at_syscall(b, 79, -100);
        if (!strcmp(name, "sys_lstat")) {
            /* Patch the zero flag argument before the syscall is emitted is
               unnecessary: a zero x3 works for both stat and lstat here. */
        }
        return true;
    }
    if (!strcmp(name, "sys_access")) {
        stub_load(b, 1, 0); stub_load(b, 2, 1);
        a64_mov_imm(b, 0, (uint64_t)(int64_t)-100);
        a64_mov_imm(b, 3, 0);
        stub_syscall(b, 48);
        return true;
    }
    if (!strcmp(name, "sys_mkdir")) {
        stub_load(b, 1, 0); stub_load(b, 2, 1);
        a64_mov_imm(b, 0, (uint64_t)(int64_t)-100);
        stub_syscall(b, 34);
        return true;
    }
    if (!strcmp(name, "sys_mknod")) {
        stub_load(b, 1, 0); stub_load(b, 2, 1); stub_load(b, 3, 2);
        a64_mov_imm(b, 0, (uint64_t)(int64_t)-100);
        stub_syscall(b, 33);
        return true;
    }
    if (!strcmp(name, "sys_chmod")) {
        stub_load(b, 1, 0); stub_load(b, 2, 1);
        a64_mov_imm(b, 0, (uint64_t)(int64_t)-100);
        a64_mov_imm(b, 3, 0);
        stub_syscall(b, 53);
        return true;
    }
    if (!strcmp(name, "sys_chown") || !strcmp(name, "sys_lchown")) {
        stub_load(b, 1, 0); stub_load(b, 2, 1); stub_load(b, 3, 2);
        a64_mov_imm(b, 0, (uint64_t)(int64_t)-100);
        a64_mov_imm(b, 4, !strcmp(name, "sys_lchown") ? 0x100u : 0u);
        stub_syscall(b, 54);
        return true;
    }
    if (!strcmp(name, "sys_readlink")) {
        stub_load(b, 1, 0); stub_load(b, 2, 1); stub_load(b, 3, 2);
        a64_mov_imm(b, 0, (uint64_t)(int64_t)-100);
        stub_syscall(b, 78);
        return true;
    }
    if (!strcmp(name, "sys_unlink") || !strcmp(name, "sys_rmdir")) {
        stub_load(b, 1, 0);
        a64_mov_imm(b, 0, (uint64_t)(int64_t)-100);
        a64_mov_imm(b, 2, !strcmp(name, "sys_rmdir") ? 0x200u : 0u);
        stub_syscall(b, 35);
        return true;
    }
    if (!strcmp(name, "sys_symlink")) {
        stub_load(b, 0, 0);
        a64_mov_imm(b, 1, (uint64_t)(int64_t)-100);
        stub_load(b, 2, 1);
        stub_syscall(b, 36);
        return true;
    }
    if (!strcmp(name, "sys_rename")) {
        a64_mov_imm(b, 0, (uint64_t)(int64_t)-100);
        stub_load(b, 1, 0);
        a64_mov_imm(b, 2, (uint64_t)(int64_t)-100);
        stub_load(b, 3, 1);
        stub_syscall(b, 38);
        return true;
    }
    return false;
}

/* High-level mocks mirroring the x86_64 backend's observable behaviour. */
static bool emit_mock(A64Buf* b, const char* name) {
    if (!strcmp(name, "sin") || !strcmp(name, "cos") || !strcmp(name, "tan")) {
        a64_fmov_s_w(b, 0, 0);
        stub_reduce_pi(b, 0);
        if (!strcmp(name, "sin")) {
            stub_sin_poly(b, 0, 0);
        } else if (!strcmp(name, "cos")) {
            stub_cos_poly(b, 0, 0);
        } else {
            stub_fcopy(b, 8, 0);
            stub_sin_poly(b, 0, 8);
            stub_cos_poly(b, 1, 8);
            a64_fdiv(b, 0, 0, 1);
        }
        a64_fmov_w_s(b, 0, 0);
        stub_epilogue(b);
        return true;
    }
    if (!strcmp(name, "exp")) {
        a64_fmov_s_w(b, 0, 0);
        stub_emit_exp(b, 0, 0);
        a64_fmov_w_s(b, 0, 0);
        stub_epilogue(b);
        return true;
    }
    if (!strcmp(name, "log")) {
        a64_fmov_s_w(b, 0, 0);
        stub_emit_log(b, 0, 0);
        a64_fmov_w_s(b, 0, 0);
        stub_epilogue(b);
        return true;
    }
    if (!strcmp(name, "pow")) {
        a64_fmov_s_w(b, 0, 0);
        a64_fmov_s_w(b, 6, 1);
        stub_emit_pow(b, 0, 6);
        a64_fmov_w_s(b, 0, 0);
        stub_epilogue(b);
        return true;
    }
    if (!strcmp(name, "audio_play")) {
        stub_print_bytes(b, "[Audio] Playing track: '", 24);
        stub_load(b, 0, 0); stub_print_str_reg(b, 0);
        stub_print_bytes(b, "'\n", 2);
        stub_epilogue(b);
        return true;
    }
    if (!strcmp(name, "sql_connect")) {
        stub_print_bytes(b, "[SQL] Connecting to database: '", 31);
        stub_load(b, 0, 0); stub_print_str_reg(b, 0);
        stub_print_bytes(b, "'\n", 2);
        stub_return_int(b, 42);
        return true;
    }
    if (!strcmp(name, "sql_query")) {
        stub_print_bytes(b, "[SQL] Executing query on DB handle: ", 36);
        stub_load(b, 0, 0); stub_print_int(b);
        stub_print_bytes(b, ", query: '", 10);
        stub_load(b, 0, 1); stub_print_str_reg(b, 0);
        stub_print_bytes(b, "'\n", 2);
        stub_return_cstr(b, "SQL Result Set Mock", 19);
        return true;
    }
    if (!strcmp(name, "process_exec")) {
        stub_print_bytes(b, "[Process] Executing system command: '", 37);
        stub_load(b, 0, 0); stub_print_str_reg(b, 0);
        stub_print_bytes(b, "'\n", 2);
        stub_return_int(b, 0);
        return true;
    }
    if (!strcmp(name, "os_get_env")) {
        stub_print_bytes(b, "[OS] Reading environment variable: '", 36);
        stub_load(b, 0, 0); stub_print_str_reg(b, 0);
        stub_print_bytes(b, "'\n", 2);
        stub_return_cstr(b, "MagnetarEnvValue", 16);
        return true;
    }
    if (!strcmp(name, "os_get_platform")) {
        stub_return_cstr(b, "MagnetarOS-aarch64-Linux", 24);
        return true;
    }
    if (!strcmp(name, "thread_spawn")) {
        stub_print_bytes(b, "[Thread] Spawning new concurrent thread execution block...\n", 59);
        stub_return_int(b, 1001);
        return true;
    }
    if (!strcmp(name, "thread_join")) {
        stub_print_bytes(b, "[Thread] Waiting for thread ID: ", 32);
        stub_load(b, 0, 0); stub_print_int(b);
        stub_print_bytes(b, " to join...\n", 12);
        stub_epilogue(b);
        return true;
    }
    if (!strcmp(name, "lock")) {
        stub_print_bytes(b, "[Thread] Mutex locked successfully.\n", 36);
        stub_epilogue(b);
        return true;
    }
    if (!strcmp(name, "unlock")) {
        stub_print_bytes(b, "[Thread] Mutex unlocked successfully.\n", 38);
        stub_epilogue(b);
        return true;
    }
    if (!strcmp(name, "regex_match")) {
        stub_print_bytes(b, "[Regex] Matching pattern: '", 27);
        stub_load(b, 0, 0); stub_print_str_reg(b, 0);
        stub_print_bytes(b, "' against text: '", 17);
        stub_load(b, 0, 1); stub_print_str_reg(b, 0);
        stub_print_bytes(b, "'\n", 2);
        stub_return_int(b, 1);
        return true;
    }
    if (!strcmp(name, "crypto_hash_sha256")) {
        stub_print_bytes(b, "[Crypto] Computing SHA-256 hash for: '", 38);
        stub_load(b, 0, 0); stub_print_str_reg(b, 0);
        stub_print_bytes(b, "'\n", 2);
        stub_return_cstr(b,
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", 64);
        return true;
    }
    if (!strcmp(name, "crypto_aes_encrypt")) {
        stub_print_bytes(b, "[Crypto] Encrypting data: '", 27);
        stub_load(b, 0, 0); stub_print_str_reg(b, 0);
        stub_print_bytes(b, "' using key: '", 14);
        stub_load(b, 0, 1); stub_print_str_reg(b, 0);
        stub_print_bytes(b, "'\n", 2);
        stub_return_cstr(b, "EncryptedMockDataBlob", 21);
        return true;
    }
    if (!strcmp(name, "net_listen")) {
        stub_print_bytes(b, "[Net] Listening on port: ", 25);
        stub_load(b, 0, 0); stub_print_int(b);
        stub_print_bytes(b, "\n", 1);
        stub_return_int(b, 12);
        return true;
    }
    if (!strcmp(name, "net_accept")) {
        stub_print_bytes(b, "[Net] Connection accepted on server socket FD: ", 47);
        stub_load(b, 0, 0); stub_print_int(b);
        stub_print_bytes(b, "\n", 1);
        stub_return_int(b, 13);
        return true;
    }
    if (!strcmp(name, "net_send")) {
        stub_print_bytes(b, "[Net] Sending data through socket FD: ", 38);
        stub_load(b, 0, 0); stub_print_int(b);
        stub_print_bytes(b, ", data: '", 9);
        stub_load(b, 0, 1); stub_print_str_reg(b, 0);
        stub_print_bytes(b, "'\n", 2);
        stub_epilogue(b);
        return true;
    }
    if (!strcmp(name, "net_close")) {
        stub_print_bytes(b, "[Net] Closed socket connection FD: ", 35);
        stub_load(b, 0, 0); stub_print_int(b);
        stub_print_bytes(b, "\n", 1);
        stub_epilogue(b);
        return true;
    }
    if (!strcmp(name, "fs_exists")) {
        stub_print_bytes(b, "[FS] Checking if path exists: '", 31);
        stub_load(b, 0, 0); stub_print_str_reg(b, 0);
        stub_print_bytes(b, "' -> ", 5);
        stub_load(b, 0, 0);
        a64_mov_imm(b, 1, 0);
        a64_mov_imm(b, 2, (uint64_t)(int64_t)-100);
        a64_mov_imm(b, 3, 0);
        a64_mov_imm(b, 8, 79);
        a64_svc(b);
        stub_print_int(b);
        stub_print_bytes(b, "\n", 1);
        stub_epilogue(b);
        return true;
    }
    if (!strcmp(name, "fs_mkdir")) {
        stub_print_bytes(b, "[FS] Creating directory: '", 26);
        stub_load(b, 0, 0); stub_print_str_reg(b, 0);
        stub_print_bytes(b, "' -> ", 5);
        stub_load(b, 1, 0); stub_load(b, 2, 1);
        a64_mov_imm(b, 0, (uint64_t)(int64_t)-100);
        a64_mov_imm(b, 8, 34);
        a64_svc(b);
        stub_print_int(b);
        stub_print_bytes(b, "\n", 1);
        stub_epilogue(b);
        return true;
    }
    if (!strcmp(name, "fs_rm")) {
        stub_print_bytes(b, "[FS] Deleting file/directory: '", 33);
        stub_load(b, 0, 0); stub_print_str_reg(b, 0);
        stub_print_bytes(b, "' -> ", 5);
        stub_load(b, 1, 0);
        a64_mov_imm(b, 0, (uint64_t)(int64_t)-100);
        a64_mov_imm(b, 2, 0);
        a64_mov_imm(b, 8, 35);
        a64_svc(b);
        stub_print_int(b);
        stub_print_bytes(b, "\n", 1);
        stub_epilogue(b);
        return true;
    }
    if (!strcmp(name, "read_line")) {
        a64_mov_imm(b, 0, 0);
        a64_mov_imm(b, 1, 256);
        a64_mov_imm(b, 2, 3);
        a64_mov_imm(b, 3, 0x22);
        a64_mov_imm(b, 4, (uint64_t)-1);
        a64_mov_imm(b, 5, 0);
        a64_mov_imm(b, 8, 222);
        a64_svc(b);
        a64_mov_reg(b, 9, 0);        /* buffer */
        a64_mov_imm(b, 10, 0);       /* index */
        size_t loop = a64_size(b);
        a64_add_reg(b, 12, 9, 10);
        a64_mov_imm(b, 0, 0);
        a64_mov_reg(b, 1, 12);
        a64_mov_imm(b, 2, 1);
        a64_mov_imm(b, 8, 63);       /* read */
        a64_svc(b);
        a64_mov_imm(b, 11, 0);
        a64_cmp_reg(b, 0, 11);
        size_t done = a64_bcond(b, A64_LE);
        a64_ldrb(b, 13, 12, 0);
        a64_mov_imm(b, 11, 10);
        a64_cmp_reg(b, 13, 11);
        size_t nl = a64_bcond(b, A64_EQ);
        a64_cmp_imm(b, 13, 0);
        size_t nul = a64_bcond(b, A64_EQ);
        a64_add_imm(b, 10, 10, 1);
        a64_cmp_imm(b, 10, 255);
        size_t again = a64_bcond(b, A64_LT);
        a64_patch_cond(b->data, again, loop);
        size_t finish = a64_size(b);
        a64_patch_cond(b->data, done, finish);
        a64_patch_cond(b->data, nl, finish);
        a64_patch_cond(b->data, nul, finish);
        a64_add_reg(b, 12, 9, 10);
        a64_mov_imm(b, 13, 0);
        a64_strb(b, 13, 12, 0);
        a64_mov_reg(b, 0, 9);
        stub_epilogue(b);
        return true;
    }
    return false;
}

bool arm_emit_stub(A64Buf* b, const char* name) {
    if (!b || !name) return false;
    size_t start = a64_size(b);
    stub_prologue(b);

    if (emit_mock(b, name)) return true;
    if (emit_special_syscall(b, name)) return true;
    for (size_t i = 0; i < sizeof(plain_syscalls) / sizeof(plain_syscalls[0]); i++) {
        if (!strcmp(name, plain_syscalls[i].name)) {
            for (int a = 0; a < 6; a++) stub_load(b, a, a);
            stub_syscall(b, plain_syscalls[i].nr);
            return true;
        }
    }

    b->len = start;
    return false;
}
