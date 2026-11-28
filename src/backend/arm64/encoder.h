#ifndef MAGNETAR_ARM64_ENCODER_H
#define MAGNETAR_ARM64_ENCODER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Minimal AArch64 encoder.  No assembler is invoked: instructions are encoded
 * directly into a byte buffer. */
typedef struct {
    uint8_t* data;
    size_t len;
    size_t cap;
} A64Buf;

void a64_init(A64Buf* b, size_t cap);
void a64_free(A64Buf* b);
void a64_emit32(A64Buf* b, uint32_t word);
void a64_emit_byte(A64Buf* b, uint8_t byte);
size_t a64_size(A64Buf* b);

/* Core integer instructions. Registers are 0..30 (xzr/sp = 31). */
void a64_nop(A64Buf* b);
void a64_ret(A64Buf* b);
void a64_svc(A64Buf* b);
void a64_align_sp(A64Buf* b);      /* bic sp, sp, #15 */
void a64_mov_reg(A64Buf* b, int rd, int rm);
void a64_mov_imm(A64Buf* b, int rd, uint64_t imm);        /* 4-instr MOVZ/MOVK */
void a64_movz32(A64Buf* b, int rd, uint32_t imm);
void a64_add_imm(A64Buf* b, int rd, int rn, uint32_t imm);
void a64_sub_imm(A64Buf* b, int rd, int rn, uint32_t imm);
void a64_add_reg(A64Buf* b, int rd, int rn, int rm);
void a64_sub_reg(A64Buf* b, int rd, int rn, int rm);
void a64_mul(A64Buf* b, int rd, int rn, int rm);
void a64_sdiv(A64Buf* b, int rd, int rn, int rm);
void a64_udiv(A64Buf* b, int rd, int rn, int rm);
void a64_and_reg(A64Buf* b, int rd, int rn, int rm);
void a64_orr_reg(A64Buf* b, int rd, int rn, int rm);
void a64_eor_reg(A64Buf* b, int rd, int rn, int rm);
void a64_lsr_imm(A64Buf* b, int rd, int rn, uint32_t shift); /* LSR x, x, #n */

/* Memory. X offsets must be 8-byte aligned; byte offsets may be any value. */
void a64_ldr_x(A64Buf* b, int rt, int rn, uint32_t byte_offset);
void a64_str_x(A64Buf* b, int rt, int rn, uint32_t byte_offset);
void a64_ldr_w(A64Buf* b, int rt, int rn, uint32_t byte_offset);
void a64_str_w(A64Buf* b, int rt, int rn, uint32_t byte_offset);
void a64_ldrb(A64Buf* b, int rt, int rn, uint32_t byte_offset);
void a64_strb(A64Buf* b, int rt, int rn, uint32_t byte_offset);
void a64_prologue(A64Buf* b, uint32_t frame_size); /* stp x29,x30 / mov / sub */
void a64_epilogue(A64Buf* b, uint32_t frame_size); /* add / ldp / ret */

/* Conditions. Values follow the AArch64 ConditionHolds encoding. */
enum {
    A64_EQ = 0, A64_NE = 1, A64_CS = 2, A64_CC = 3,
    A64_MI = 4, A64_PL = 5, A64_VS = 6, A64_VC = 7,
    A64_HI = 8, A64_LS = 9, A64_GE = 10, A64_LT = 11,
    A64_GT = 12, A64_LE = 13
};

void a64_cmp_reg(A64Buf* b, int rn, int rm);
void a64_cmp_imm(A64Buf* b, int rn, uint32_t imm);
void a64_cset(A64Buf* b, int rd, int cond);
size_t a64_cbz(A64Buf* b, int rt);
size_t a64_cbnz(A64Buf* b, int rt);
size_t a64_b(A64Buf* b);
size_t a64_bl(A64Buf* b);
size_t a64_bcond(A64Buf* b, int cond);

/* Floating point (32-bit S registers, bit patterns carried in W registers). */
void a64_fmov_s_w(A64Buf* b, int sd, int wn);
void a64_fmov_w_s(A64Buf* b, int wd, int sn);
void a64_fadd(A64Buf* b, int sd, int sn, int sm);
void a64_fsub(A64Buf* b, int sd, int sn, int sm);
void a64_fmul(A64Buf* b, int sd, int sn, int sm);
void a64_fdiv(A64Buf* b, int sd, int sn, int sm);
void a64_fcmp(A64Buf* b, int sn, int sm);
void a64_fcsel(A64Buf* b, int sd, int sn, int sm, int cond);
void a64_fcvtzs(A64Buf* b, int wd, int sn);
void a64_scvtf(A64Buf* b, int sd, int wn);
void a64_fabs(A64Buf* b, int sd, int sn);
void a64_fsqrt(A64Buf* b, int sd, int sn);

/* Patch helpers. `pos` is the byte offset returned by the emitting call. */
void a64_patch_branch(uint8_t* code, size_t pos, size_t target);
void a64_patch_cond(uint8_t* code, size_t pos, size_t target);
void a64_patch_cb(uint8_t* code, size_t pos, size_t target);
void a64_patch_mov64(uint8_t* code, size_t pos, uint64_t value);
void a64_patch_adrp_add(uint8_t* code, size_t pos, uint64_t pc, uint64_t target);
void a64_patch_tstbr14(uint8_t* code, size_t pos, size_t target);
void a64_patch_lo12(uint8_t* code, size_t pos, uint64_t target);

#endif /* MAGNETAR_ARM64_ENCODER_H */
