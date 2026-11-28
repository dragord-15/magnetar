#include "encoder.h"
#include <stdlib.h>
#include <string.h>

void a64_init(A64Buf* b, size_t cap) {
    if (cap < 256) cap = 256;
    b->data = (uint8_t*)malloc(cap);
    b->len = 0;
    b->cap = b->data ? cap : 0;
}

void a64_free(A64Buf* b) {
    free(b->data);
    b->data = NULL;
    b->len = b->cap = 0;
}

void a64_emit32(A64Buf* b, uint32_t word) {
    if (!b->data) return;
    if (b->len + 4 > b->cap) {
        while (b->cap < b->len + 4) b->cap *= 2;
        uint8_t* p = (uint8_t*)realloc(b->data, b->cap);
        if (!p) return;
        b->data = p;
    }
    b->data[b->len++] = (uint8_t)(word & 0xFF);
    b->data[b->len++] = (uint8_t)((word >> 8) & 0xFF);
    b->data[b->len++] = (uint8_t)((word >> 16) & 0xFF);
    b->data[b->len++] = (uint8_t)((word >> 24) & 0xFF);
}

void a64_emit_byte(A64Buf* b, uint8_t byte) {
    if (!b->data) return;
    if (b->len + 1 > b->cap) {
        while (b->cap < b->len + 1) b->cap *= 2;
        uint8_t* p = (uint8_t*)realloc(b->data, b->cap);
        if (!p) return;
        b->data = p;
    }
    b->data[b->len++] = byte;
}

size_t a64_size(A64Buf* b) { return b->len; }

static uint32_t load32(const uint8_t* p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static void store32(uint8_t* p, uint32_t w) {
    p[0] = (uint8_t)(w & 0xFF);
    p[1] = (uint8_t)((w >> 8) & 0xFF);
    p[2] = (uint8_t)((w >> 16) & 0xFF);
    p[3] = (uint8_t)((w >> 24) & 0xFF);
}

void a64_nop(A64Buf* b) { a64_emit32(b, 0xD503201F); }
void a64_ret(A64Buf* b) { a64_emit32(b, 0xD65F03C0); }
void a64_svc(A64Buf* b) { a64_emit32(b, 0xD4000001); }

/* AAPCS64 requires SP to be 16-byte aligned at public interfaces.  Linux
   already guarantees this at process entry, but enforcing it explicitly makes
   the contract clear for linked objects.  Go through x9 because logical
   immediates encode xzr, not sp, for register number 31. */
void a64_align_sp(A64Buf* b) {
    a64_add_imm(b, 9, 31, 0);    /* add  x9, sp, #0  */
    a64_emit32(b, 0x927CED29u);  /* and  x9, x9, #0xfffffffffffffff0 */
    a64_add_imm(b, 31, 9, 0);    /* add  sp, x9, #0  */
}

void a64_mov_reg(A64Buf* b, int rd, int rm) {
    a64_emit32(b, 0xAA0003E0u | ((uint32_t)(rm & 31) << 16) | (uint32_t)(rd & 31));
}

static void movz64(A64Buf* b, int rd, uint16_t imm, int hw) {
    a64_emit32(b, 0xD2800000u | ((uint32_t)hw << 21) |
                  ((uint32_t)imm << 5) | (uint32_t)(rd & 31));
}

static void movk64(A64Buf* b, int rd, uint16_t imm, int hw) {
    a64_emit32(b, 0xF2800000u | ((uint32_t)hw << 21) |
                  ((uint32_t)imm << 5) | (uint32_t)(rd & 31));
}

void a64_mov_imm(A64Buf* b, int rd, uint64_t imm) {
    movz64(b, rd, (uint16_t)(imm & 0xFFFF), 0);
    movk64(b, rd, (uint16_t)((imm >> 16) & 0xFFFF), 1);
    movk64(b, rd, (uint16_t)((imm >> 32) & 0xFFFF), 2);
    movk64(b, rd, (uint16_t)((imm >> 48) & 0xFFFF), 3);
}

void a64_movz32(A64Buf* b, int rd, uint32_t imm) {
    a64_emit32(b, 0x52800000u | ((imm & 0xFFFFu) << 5) | (uint32_t)(rd & 31));
}

void a64_add_imm(A64Buf* b, int rd, int rn, uint32_t imm) {
    a64_emit32(b, 0x91000000u | ((imm & 0xFFFu) << 10) |
                  (((uint32_t)rn & 31) << 5) | ((uint32_t)rd & 31));
}

void a64_sub_imm(A64Buf* b, int rd, int rn, uint32_t imm) {
    a64_emit32(b, 0xD1000000u | ((imm & 0xFFFu) << 10) |
                  (((uint32_t)rn & 31) << 5) | ((uint32_t)rd & 31));
}

void a64_add_reg(A64Buf* b, int rd, int rn, int rm) {
    a64_emit32(b, 0x8B000000u | (((uint32_t)rm & 31) << 16) |
                  (((uint32_t)rn & 31) << 5) | ((uint32_t)rd & 31));
}

void a64_sub_reg(A64Buf* b, int rd, int rn, int rm) {
    a64_emit32(b, 0xCB000000u | (((uint32_t)rm & 31) << 16) |
                  (((uint32_t)rn & 31) << 5) | ((uint32_t)rd & 31));
}

void a64_mul(A64Buf* b, int rd, int rn, int rm) {
    a64_emit32(b, 0x9B007C00u | (((uint32_t)rm & 31) << 16) |
                  (((uint32_t)rn & 31) << 5) | ((uint32_t)rd & 31));
}

void a64_sdiv(A64Buf* b, int rd, int rn, int rm) {
    a64_emit32(b, 0x9AC00C00u | (((uint32_t)rm & 31) << 16) |
                  (((uint32_t)rn & 31) << 5) | ((uint32_t)rd & 31));
}

void a64_udiv(A64Buf* b, int rd, int rn, int rm) {
    a64_emit32(b, 0x9AC00800u | (((uint32_t)rm & 31) << 16) |
                  (((uint32_t)rn & 31) << 5) | ((uint32_t)rd & 31));
}

void a64_and_reg(A64Buf* b, int rd, int rn, int rm) {
    a64_emit32(b, 0x8A000000u | (((uint32_t)rm & 31) << 16) |
                  (((uint32_t)rn & 31) << 5) | ((uint32_t)rd & 31));
}

void a64_orr_reg(A64Buf* b, int rd, int rn, int rm) {
    a64_emit32(b, 0xAA000000u | (((uint32_t)rm & 31) << 16) |
                  (((uint32_t)rn & 31) << 5) | ((uint32_t)rd & 31));
}

void a64_eor_reg(A64Buf* b, int rd, int rn, int rm) {
    a64_emit32(b, 0xCA000000u | (((uint32_t)rm & 31) << 16) |
                  (((uint32_t)rn & 31) << 5) | ((uint32_t)rd & 31));
}

void a64_lsr_imm(A64Buf* b, int rd, int rn, uint32_t shift) {
    uint32_t s = shift & 63;
    a64_emit32(b, 0xD3400000u | (s << 16) | (63u << 10) |
                  (((uint32_t)rn & 31) << 5) | ((uint32_t)rd & 31));
}

void a64_ldr_x(A64Buf* b, int rt, int rn, uint32_t byte_offset) {
    uint32_t imm12 = (byte_offset >> 3) & 0xFFFu;
    a64_emit32(b, 0xF9400000u | (imm12 << 10) |
                  (((uint32_t)rn & 31) << 5) | ((uint32_t)rt & 31));
}

void a64_str_x(A64Buf* b, int rt, int rn, uint32_t byte_offset) {
    uint32_t imm12 = (byte_offset >> 3) & 0xFFFu;
    a64_emit32(b, 0xF9000000u | (imm12 << 10) |
                  (((uint32_t)rn & 31) << 5) | ((uint32_t)rt & 31));
}

void a64_ldr_w(A64Buf* b, int rt, int rn, uint32_t byte_offset) {
    uint32_t imm12 = (byte_offset >> 2) & 0xFFFu;
    a64_emit32(b, 0xB9400000u | (imm12 << 10) |
                  (((uint32_t)rn & 31) << 5) | ((uint32_t)rt & 31));
}

void a64_str_w(A64Buf* b, int rt, int rn, uint32_t byte_offset) {
    uint32_t imm12 = (byte_offset >> 2) & 0xFFFu;
    a64_emit32(b, 0xB9000000u | (imm12 << 10) |
                  (((uint32_t)rn & 31) << 5) | ((uint32_t)rt & 31));
}

void a64_ldrb(A64Buf* b, int rt, int rn, uint32_t byte_offset) {
    a64_emit32(b, 0x39400000u | ((byte_offset & 0xFFFu) << 10) |
                  (((uint32_t)rn & 31) << 5) | ((uint32_t)rt & 31));
}

void a64_strb(A64Buf* b, int rt, int rn, uint32_t byte_offset) {
    a64_emit32(b, 0x39000000u | ((byte_offset & 0xFFFu) << 10) |
                  (((uint32_t)rn & 31) << 5) | ((uint32_t)rt & 31));
}

void a64_prologue(A64Buf* b, uint32_t frame_size) {
    a64_emit32(b, 0xA9BF7BFD); /* stp x29, x30, [sp, #-16]! */
    a64_add_imm(b, 29, 31, 0); /* mov x29, sp */
    a64_sub_imm(b, 31, 31, frame_size);
}

void a64_epilogue(A64Buf* b, uint32_t frame_size) {
    a64_add_imm(b, 31, 31, frame_size);
    a64_emit32(b, 0xA8C17BFD); /* ldp x29, x30, [sp], #16 */
    a64_ret(b);
}

void a64_cmp_reg(A64Buf* b, int rn, int rm) {
    a64_emit32(b, 0xEB000000u | (((uint32_t)rm & 31) << 16) |
                  (((uint32_t)rn & 31) << 5) | 31u);
}

void a64_cmp_imm(A64Buf* b, int rn, uint32_t imm) {
    a64_emit32(b, 0xF1000000u | ((imm & 0xFFFu) << 10) |
                  (((uint32_t)rn & 31) << 5) | 31u);
}

void a64_cset(A64Buf* b, int rd, int cond) {
    a64_emit32(b, 0x1A9F07E0u | (((uint32_t)(cond & 15) ^ 1u) << 12) |
                  ((uint32_t)rd & 31));
}

size_t a64_cbz(A64Buf* b, int rt) {
    size_t pos = a64_size(b);
    a64_emit32(b, 0xB4000000u | ((uint32_t)rt & 31));
    return pos;
}

size_t a64_cbnz(A64Buf* b, int rt) {
    size_t pos = a64_size(b);
    a64_emit32(b, 0xB5000000u | ((uint32_t)rt & 31));
    return pos;
}

size_t a64_b(A64Buf* b) {
    size_t pos = a64_size(b);
    a64_emit32(b, 0x14000000u);
    return pos;
}

size_t a64_bl(A64Buf* b) {
    size_t pos = a64_size(b);
    a64_emit32(b, 0x94000000u);
    return pos;
}

size_t a64_bcond(A64Buf* b, int cond) {
    size_t pos = a64_size(b);
    a64_emit32(b, 0x54000000u | ((uint32_t)cond & 15u));
    return pos;
}

void a64_fmov_s_w(A64Buf* b, int sd, int wn) {
    a64_emit32(b, 0x1E270000u | (((uint32_t)wn & 31) << 5) | ((uint32_t)sd & 31));
}

void a64_fmov_w_s(A64Buf* b, int wd, int sn) {
    a64_emit32(b, 0x1E260000u | (((uint32_t)sn & 31) << 5) | ((uint32_t)wd & 31));
}

static void fp3(A64Buf* b, uint32_t base, int sd, int sn, int sm) {
    a64_emit32(b, base | (((uint32_t)sm & 31) << 16) |
                  (((uint32_t)sn & 31) << 5) | ((uint32_t)sd & 31));
}

void a64_fadd(A64Buf* b, int sd, int sn, int sm) { fp3(b, 0x1E202800u, sd, sn, sm); }
void a64_fsub(A64Buf* b, int sd, int sn, int sm) { fp3(b, 0x1E203800u, sd, sn, sm); }
void a64_fmul(A64Buf* b, int sd, int sn, int sm) { fp3(b, 0x1E200800u, sd, sn, sm); }
void a64_fdiv(A64Buf* b, int sd, int sn, int sm) { fp3(b, 0x1E201800u, sd, sn, sm); }

void a64_fcmp(A64Buf* b, int sn, int sm) {
    a64_emit32(b, 0x1E202000u | (((uint32_t)sm & 31) << 16) |
                  (((uint32_t)sn & 31) << 5));
}

void a64_fcsel(A64Buf* b, int sd, int sn, int sm, int cond) {
    a64_emit32(b, 0x1E200C00u | (((uint32_t)sm & 31) << 16) |
                  (((uint32_t)(cond & 15)) << 12) |
                  (((uint32_t)sn & 31) << 5) | ((uint32_t)sd & 31));
}

void a64_fcvtzs(A64Buf* b, int wd, int sn) {
    /* 64-bit destination keeps negative values negative for cmp/neg. */
    a64_emit32(b, 0x9E380000u | (((uint32_t)sn & 31) << 5) | ((uint32_t)wd & 31));
}

void a64_scvtf(A64Buf* b, int sd, int wn) {
    /* Magnetar `int` is 64-bit, so convert from Xn (not Wn). */
    a64_emit32(b, 0x9E220000u | (((uint32_t)wn & 31) << 5) | ((uint32_t)sd & 31));
}

void a64_fabs(A64Buf* b, int sd, int sn) {
    a64_emit32(b, 0x1E20C000u | (((uint32_t)sn & 31) << 5) | ((uint32_t)sd & 31));
}

void a64_fsqrt(A64Buf* b, int sd, int sn) {
    a64_emit32(b, 0x1E21C000u | (((uint32_t)sn & 31) << 5) | ((uint32_t)sd & 31));
}

void a64_patch_branch(uint8_t* code, size_t pos, size_t target) {
    uint32_t word = load32(code + pos);
    uint32_t op = word & 0xFC000000u;
    int64_t delta = (int64_t)target - (int64_t)pos;
    uint32_t imm26 = (uint32_t)((delta >> 2) & 0x03FFFFFFu);
    store32(code + pos, op | imm26);
}

void a64_patch_cond(uint8_t* code, size_t pos, size_t target) {
    uint32_t word = load32(code + pos);
    uint32_t cond = word & 15u;
    int64_t delta = (int64_t)target - (int64_t)pos;
    uint32_t imm19 = (uint32_t)((delta >> 2) & 0x7FFFFu);
    store32(code + pos, 0x54000000u | cond | (imm19 << 5));
}

void a64_patch_cb(uint8_t* code, size_t pos, size_t target) {
    uint32_t word = load32(code + pos);
    uint32_t op = word & 0xFF000000u;
    uint32_t rt = word & 31u;
    int64_t delta = (int64_t)target - (int64_t)pos;
    uint32_t imm19 = (uint32_t)((delta >> 2) & 0x7FFFFu);
    store32(code + pos, op | (imm19 << 5) | rt);
}

void a64_patch_mov64(uint8_t* code, size_t pos, uint64_t value) {
    for (int i = 0; i < 4; i++) {
        uint16_t imm = (uint16_t)((value >> (i * 16)) & 0xFFFFu);
        uint32_t word = load32(code + pos + (size_t)i * 4);
        word = (word & ~0x001FFFE0u) | ((uint32_t)imm << 5);
        store32(code + pos + (size_t)i * 4, word);
    }
}

void a64_patch_adrp_add(uint8_t* code, size_t pos, uint64_t pc, uint64_t target) {
    /* Patch an ADRP xN, <page> / ADD xM, xN, #lo12 pair.  `pos` locates the
       pair in the output buffer; `pc` is its final virtual address. */
    int64_t page_delta =
        ((int64_t)(target & ~(uint64_t)0xFFF) -
         (int64_t)(pc & ~(uint64_t)0xFFF)) >> 12;
    uint32_t immlo = (uint32_t)page_delta & 3u;
    uint32_t immhi = (uint32_t)((page_delta >> 2) & 0x7FFFFu);
    uint32_t adrp = load32(code + pos);
    uint32_t rd = adrp & 31u;
    store32(code + pos,
            0x90000000u | (immlo << 29) | (immhi << 5) | rd);

    uint32_t add = load32(code + pos + 4);
    uint32_t rd2 = add & 31u;
    uint32_t rn = (add >> 5) & 31u;
    uint32_t imm12 = (uint32_t)(target & 0xFFFu);
    store32(code + pos + 4,
            0x91000000u | (imm12 << 10) | (rn << 5) | rd2);
}

void a64_patch_tstbr14(uint8_t* code, size_t pos, size_t target) {
    uint32_t word = load32(code + pos);
    uint32_t op = word & 0xFF000000u;   /* keeps TBZ/TBNZ and b5 */
    uint32_t rt = word & 31u;
    int64_t delta = (int64_t)target - (int64_t)pos;
    uint32_t imm14 = (uint32_t)((delta >> 2) & 0x3FFFu);
    store32(code + pos, op | (imm14 << 19) | rt);
}

/* ADD (immediate) and LDST unsigned-offset instructions both keep their
   12-bit offset in bits 21:10. */
void a64_patch_lo12(uint8_t* code, size_t pos, uint64_t target) {
    uint32_t word = load32(code + pos);
    uint32_t imm12 = (uint32_t)(target & 0xFFFu);
    store32(code + pos, (word & ~0x003FFC00u) | (imm12 << 10));
}
