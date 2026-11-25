#ifndef MAGNETAR_CODEGEN_H
#define MAGNETAR_CODEGEN_H

#include "../../parser/ast.h"
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

typedef enum {
    REG_RAX = 0, REG_RCX = 1, REG_RDX = 2, REG_RBX = 3,
    REG_RSP = 4, REG_RBP = 5, REG_RSI = 6, REG_RDI = 7,
    REG_R8 = 8,  REG_R9 = 9,  REG_R10 = 10, REG_R11 = 11,
    REG_R12 = 12, REG_R13 = 13, REG_R14 = 14, REG_R15 = 15,
    REG_XMM0 = 16, REG_XMM1 = 17, REG_XMM2 = 18, REG_XMM3 = 19,
    REG_XMM4 = 20, REG_XMM5 = 21, REG_XMM6 = 22, REG_XMM7 = 23
} X64Register;

typedef struct {
    uint8_t* buffer;
    size_t size;
    size_t capacity;
} CodeGen;

typedef struct {
    size_t position;
    char* label_name;
    bool is_label;
} PatchPoint;

typedef struct {
    PatchPoint* patches;
    size_t count;
    size_t capacity;
} PatchTable;

CodeGen* cg_create(size_t initial_capacity);
void cg_destroy(CodeGen* cg);
uint8_t* cg_get_buffer(CodeGen* cg);
size_t cg_get_size(CodeGen* cg);
size_t cg_get_position(CodeGen* cg);

void cg_emit_mov_reg_imm64(CodeGen* cg, X64Register reg, uint64_t value);
void cg_emit_mov_reg_imm32(CodeGen* cg, X64Register reg, uint32_t value);
void cg_emit_mov_reg_reg(CodeGen* cg, X64Register dst, X64Register src);

void cg_emit_lea_reg_rip(CodeGen* cg, X64Register reg, int32_t disp32);
void cg_emit_lea_reg_mem(CodeGen* cg, X64Register reg, X64Register base, int32_t offset);

void cg_emit_xor_reg_reg(CodeGen* cg, X64Register dst, X64Register src);
void cg_emit_add_reg_reg(CodeGen* cg, X64Register dst, X64Register src);
void cg_emit_add_reg_imm32(CodeGen* cg, X64Register reg, int32_t value);
void cg_emit_sub_reg_reg(CodeGen* cg, X64Register dst, X64Register src);
void cg_emit_sub_reg_imm32(CodeGen* cg, X64Register reg, int32_t value);
void cg_emit_imul_reg_reg(CodeGen* cg, X64Register dst, X64Register src);
void cg_emit_idiv_reg(CodeGen* cg, X64Register reg);

void cg_emit_cmp_reg_imm32(CodeGen* cg, X64Register reg, int32_t value);
void cg_emit_cmp_reg_reg(CodeGen* cg, X64Register a, X64Register b);
void cg_emit_test_reg_reg(CodeGen* cg, X64Register a, X64Register b);

void cg_emit_push_reg(CodeGen* cg, X64Register reg);
void cg_emit_pop_reg(CodeGen* cg, X64Register reg);

void cg_emit_call_reg(CodeGen* cg, X64Register reg);
void cg_emit_call_rel32(CodeGen* cg, int32_t offset);
void cg_emit_ret(CodeGen* cg);
void cg_emit_syscall(CodeGen* cg);

void cg_emit_byte(CodeGen* cg, uint8_t byte);
void cg_emit_imul_reg_imm32(CodeGen* cg, X64Register dst, X64Register src, int32_t imm);
void cg_emit_shl_reg_imm8(CodeGen* cg, X64Register reg, uint8_t imm);
void cg_emit_shr_reg_imm8(CodeGen* cg, X64Register reg, uint8_t imm);
void cg_emit_inc_reg(CodeGen* cg, X64Register reg);
void cg_emit_dec_reg(CodeGen* cg, X64Register reg);
void cg_emit_btc_reg_imm8(CodeGen* cg, X64Register reg, uint8_t imm);

void cg_emit_nop(CodeGen* cg);
void cg_emit_int3(CodeGen* cg);

void cg_emit_in_al_dx(CodeGen* cg);
void cg_emit_in_ax_dx(CodeGen* cg);
void cg_emit_in_eax_dx(CodeGen* cg);
void cg_emit_out_dx_al(CodeGen* cg);
void cg_emit_out_dx_ax(CodeGen* cg);
void cg_emit_out_dx_eax(CodeGen* cg);

void cg_emit_jmp_rel8(CodeGen* cg, int8_t offset);
void cg_emit_jmp_rel32(CodeGen* cg, int32_t offset);
void cg_emit_je_rel8(CodeGen* cg, int8_t offset);
void cg_emit_je_rel32(CodeGen* cg, int32_t offset);
void cg_emit_jne_rel8(CodeGen* cg, int8_t offset);
void cg_emit_jne_rel32(CodeGen* cg, int32_t offset);
void cg_emit_jl_rel8(CodeGen* cg, int8_t offset);
void cg_emit_jle_rel8(CodeGen* cg, int8_t offset);
void cg_emit_jg_rel8(CodeGen* cg, int8_t offset);
void cg_emit_jge_rel8(CodeGen* cg, int8_t offset);
void cg_emit_jl_rel32(CodeGen* cg, int32_t offset);
void cg_emit_jle_rel32(CodeGen* cg, int32_t offset);
void cg_emit_jg_rel32(CodeGen* cg, int32_t offset);
void cg_emit_jge_rel32(CodeGen* cg, int32_t offset);
void cg_emit_ja_rel32(CodeGen* cg, int32_t offset);

void cg_emit_jmp_label(CodeGen* cg, PatchTable* pt, const char* label);
void cg_emit_je_label(CodeGen* cg, PatchTable* pt, const char* label);
void cg_emit_jne_label(CodeGen* cg, PatchTable* pt, const char* label);
void cg_emit_jl_label(CodeGen* cg, PatchTable* pt, const char* label);
void cg_emit_jle_label(CodeGen* cg, PatchTable* pt, const char* label);
void cg_emit_jg_label(CodeGen* cg, PatchTable* pt, const char* label);
void cg_emit_jge_label(CodeGen* cg, PatchTable* pt, const char* label);
void cg_emit_ja_label(CodeGen* cg, PatchTable* pt, const char* label);
void cg_emit_label(CodeGen* cg, PatchTable* pt, const char* label);

PatchTable* pt_create(void);
void pt_destroy(PatchTable* pt);
void pt_add_patch(PatchTable* pt, size_t position, const char* label, bool is_label);
int pt_resolve_patches(CodeGen* cg, PatchTable* pt);

void cg_emit_mov_reg_mem(CodeGen* cg, X64Register reg, X64Register base, int32_t offset);
void cg_emit_mov_mem_reg(CodeGen* cg, X64Register base, int32_t offset, X64Register reg);
void cg_emit_movss_xmm_mem(CodeGen* cg, X64Register xmm, X64Register base, int32_t offset);
void cg_emit_movss_mem_xmm(CodeGen* cg, X64Register base, int32_t offset, X64Register xmm);
void cg_emit_addss_xmm_xmm(CodeGen* cg, X64Register dst, X64Register src);
void cg_emit_subss_xmm_xmm(CodeGen* cg, X64Register dst, X64Register src);
void cg_emit_mulss_xmm_xmm(CodeGen* cg, X64Register dst, X64Register src);
void cg_emit_divss_xmm_xmm(CodeGen* cg, X64Register dst, X64Register src);
void cg_emit_cvttss2si_reg_xmm(CodeGen* cg, X64Register dst, X64Register src);
void cg_emit_cvtsi2ss_xmm_reg(CodeGen* cg, X64Register dst, X64Register src);
void cg_emit_movss_xmm_rip(CodeGen* cg, X64Register reg, int32_t disp32);
void cg_emit_movd_xmm_to_gpr(CodeGen* cg, X64Register dst, X64Register src);
void cg_emit_movd_gpr_to_xmm(CodeGen* cg, X64Register dst, X64Register src);
void cg_emit_vtable(CodeGen* cg, const char** method_labels, int count);

void cg_emit_movzx_byte(CodeGen* cg, X64Register reg, X64Register base, int32_t offset);
void cg_emit_movzx_word(CodeGen* cg, X64Register reg, X64Register base, int32_t offset);
void cg_emit_mov_reg_mem32(CodeGen* cg, X64Register reg, X64Register base, int32_t offset);
void cg_emit_movsxd_reg_mem(CodeGen* cg, X64Register reg, X64Register base, int32_t offset);
void cg_emit_mov_mem_reg8(CodeGen* cg, X64Register base, int32_t offset, X64Register reg);
void cg_emit_mov_mem_reg16(CodeGen* cg, X64Register base, int32_t offset, X64Register reg);
void cg_emit_mov_mem_reg32(CodeGen* cg, X64Register base, int32_t offset, X64Register reg);

#endif