#include "codegen_x64.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// ══════════════════════════════════════
// دوال داخلية
// ══════════════════════════════════════

static uint8_t rex_prefix(bool w, bool r, bool x, bool b) {
    return 0x40 | (w ? 0x08 : 0) | (r ? 0x04 : 0) | (x ? 0x02 : 0) | (b ? 0x01 : 0);
}

static uint8_t modrm_byte(uint8_t mod, uint8_t reg, uint8_t rm) {
    return ((mod & 0x03) << 6) | ((reg & 0x07) << 3) | (rm & 0x07);
}

void ensure_space(CodeGen* cg, size_t extra) {
    if (cg->size + extra > cg->capacity) {
        while (cg->capacity < cg->size + extra) cg->capacity *= 2;
        cg->buffer = (uint8_t*)realloc(cg->buffer, cg->capacity);
    }
}

static void emit_byte(CodeGen* cg, uint8_t b) {
    ensure_space(cg, 1);
    cg->buffer[cg->size++] = b;
}

static int reg_index(X64Register reg) {
    if (reg >= REG_XMM0) return reg - REG_XMM0;
    if (reg >= REG_R8) return reg - REG_R8;
    return reg;
}

static bool is_extended(X64Register reg) {
    if (reg >= REG_XMM0) return false;
    return reg >= REG_R8;
}

// ══════════════════════════════════════
// إنشاء وتدمير
// ══════════════════════════════════════

CodeGen* cg_create(size_t initial_capacity) {
    CodeGen* cg = (CodeGen*)malloc(sizeof(CodeGen));
    cg->capacity = initial_capacity > 0 ? initial_capacity : 4096;
    cg->buffer = (uint8_t*)malloc(cg->capacity);
    cg->size = 0;
    return cg;
}

void cg_destroy(CodeGen* cg) {
    if (cg) { free(cg->buffer); free(cg); }
}

uint8_t* cg_get_buffer(CodeGen* cg) { return cg->buffer; }
size_t cg_get_size(CodeGen* cg) { return cg->size; }
size_t cg_get_position(CodeGen* cg) { return cg->size; }

// ══════════════════════════════════════
// MOV
// ══════════════════════════════════════

void cg_emit_mov_reg_imm64(CodeGen* cg, X64Register reg, uint64_t value) {
    if (value == 0) {
        cg_emit_xor_reg_reg(cg, reg, reg);
        return;
    }
    emit_byte(cg, rex_prefix(true, false, false, is_extended(reg)));
    emit_byte(cg, 0xB8 | (reg_index(reg) & 7));
    for (int i = 0; i < 8; i++) emit_byte(cg, (value >> (i * 8)) & 0xFF);
}

void cg_emit_mov_reg_imm32(CodeGen* cg, X64Register reg, uint32_t value) {
    if (value == 0) {
        cg_emit_xor_reg_reg(cg, reg, reg);
        return;
    }
    emit_byte(cg, rex_prefix(false, false, false, is_extended(reg)));
    emit_byte(cg, 0xB8 | (reg_index(reg) & 7));
    for (int i = 0; i < 4; i++) emit_byte(cg, (value >> (i * 8)) & 0xFF);
}

void cg_emit_mov_reg_reg(CodeGen* cg, X64Register dst, X64Register src) {
    if (dst == src) return;
    emit_byte(cg, rex_prefix(true, is_extended(src), false, is_extended(dst)));
    emit_byte(cg, 0x89);
    emit_byte(cg, modrm_byte(3, reg_index(src) & 7, reg_index(dst) & 7));
}

// ══════════════════════════════════════
// LEA
// ══════════════════════════════════════

void cg_emit_lea_reg_rip(CodeGen* cg, X64Register reg, int32_t disp32) {
    emit_byte(cg, rex_prefix(true, is_extended(reg), false, false));
    emit_byte(cg, 0x8D);
    emit_byte(cg, modrm_byte(0, reg_index(reg) & 7, 5));
    for (int i = 0; i < 4; i++) emit_byte(cg, (disp32 >> (i * 8)) & 0xFF);
}

void cg_emit_lea_reg_mem(CodeGen* cg, X64Register reg, X64Register base, int32_t offset) {
    emit_byte(cg, rex_prefix(true, is_extended(reg), false, is_extended(base)));
    emit_byte(cg, 0x8D);
    if (offset == 0 && base != REG_RSP && base != REG_RBP) {
        emit_byte(cg, modrm_byte(0, reg_index(reg) & 7, reg_index(base) & 7));
    } else if (offset >= -128 && offset <= 127) {
        emit_byte(cg, modrm_byte(1, reg_index(reg) & 7, reg_index(base) & 7));
        emit_byte(cg, offset & 0xFF);
    } else {
        emit_byte(cg, modrm_byte(2, reg_index(reg) & 7, reg_index(base) & 7));
        for (int i = 0; i < 4; i++) emit_byte(cg, (offset >> (i * 8)) & 0xFF);
    }
}

// ══════════════════════════════════════
// XOR
// ══════════════════════════════════════

void cg_emit_xor_reg_reg(CodeGen* cg, X64Register dst, X64Register src) {
    emit_byte(cg, rex_prefix(true, is_extended(src), false, is_extended(dst)));
    emit_byte(cg, 0x31);
    emit_byte(cg, modrm_byte(3, reg_index(src) & 7, reg_index(dst) & 7));
}

// ══════════════════════════════════════
// ADD
// ══════════════════════════════════════

void cg_emit_add_reg_reg(CodeGen* cg, X64Register dst, X64Register src) {
    emit_byte(cg, rex_prefix(true, is_extended(src), false, is_extended(dst)));
    emit_byte(cg, 0x01);
    emit_byte(cg, modrm_byte(3, reg_index(src) & 7, reg_index(dst) & 7));
}

void cg_emit_add_reg_imm32(CodeGen* cg, X64Register reg, int32_t value) {
    if (value == 0) return;
    if (value == 1) {
        emit_byte(cg, rex_prefix(true, false, false, is_extended(reg)));
        emit_byte(cg, 0xFF);
        emit_byte(cg, modrm_byte(3, 0, reg_index(reg) & 7));
        return;
    }
    if (value >= -128 && value <= 127) {
        emit_byte(cg, rex_prefix(true, false, false, is_extended(reg)));
        emit_byte(cg, 0x83);
        emit_byte(cg, modrm_byte(3, 0, reg_index(reg) & 7));
        emit_byte(cg, value & 0xFF);
    } else {
        emit_byte(cg, rex_prefix(true, false, false, is_extended(reg)));
        emit_byte(cg, 0x81);
        emit_byte(cg, modrm_byte(3, 0, reg_index(reg) & 7));
        for (int i = 0; i < 4; i++) emit_byte(cg, (value >> (i * 8)) & 0xFF);
    }
}

// ══════════════════════════════════════
// SUB
// ══════════════════════════════════════

void cg_emit_sub_reg_reg(CodeGen* cg, X64Register dst, X64Register src) {
    emit_byte(cg, rex_prefix(true, is_extended(src), false, is_extended(dst)));
    emit_byte(cg, 0x29);
    emit_byte(cg, modrm_byte(3, reg_index(src) & 7, reg_index(dst) & 7));
}

void cg_emit_sub_reg_imm32(CodeGen* cg, X64Register reg, int32_t value) {
    if (value == 0) return;
    if (value == 1) {
        emit_byte(cg, rex_prefix(true, false, false, is_extended(reg)));
        emit_byte(cg, 0xFF);
        emit_byte(cg, modrm_byte(3, 1, reg_index(reg) & 7));
        return;
    }
    if (value >= -128 && value <= 127) {
        emit_byte(cg, rex_prefix(true, false, false, is_extended(reg)));
        emit_byte(cg, 0x83);
        emit_byte(cg, modrm_byte(3, 5, reg_index(reg) & 7));
        emit_byte(cg, value & 0xFF);
    } else {
        emit_byte(cg, rex_prefix(true, false, false, is_extended(reg)));
        emit_byte(cg, 0x81);
        emit_byte(cg, modrm_byte(3, 5, reg_index(reg) & 7));
        for (int i = 0; i < 4; i++) emit_byte(cg, (value >> (i * 8)) & 0xFF);
    }
}

// ══════════════════════════════════════
// IMUL, IDIV
// ══════════════════════════════════════

void cg_emit_imul_reg_reg(CodeGen* cg, X64Register dst, X64Register src) {
    emit_byte(cg, rex_prefix(true, is_extended(dst), false, is_extended(src)));
    emit_byte(cg, 0x0F);
    emit_byte(cg, 0xAF);
    emit_byte(cg, modrm_byte(3, reg_index(dst) & 7, reg_index(src) & 7));
}

void cg_emit_idiv_reg(CodeGen* cg, X64Register reg) {
    emit_byte(cg, rex_prefix(true, false, false, is_extended(reg)));
    emit_byte(cg, 0xF7);
    emit_byte(cg, modrm_byte(3, 7, reg_index(reg) & 7));
}

// ══════════════════════════════════════
// CMP
// ══════════════════════════════════════

void cg_emit_cmp_reg_imm32(CodeGen* cg, X64Register reg, int32_t value) {
    if (value >= -128 && value <= 127) {
        emit_byte(cg, rex_prefix(true, false, false, is_extended(reg)));
        emit_byte(cg, 0x83);
        emit_byte(cg, modrm_byte(3, 7, reg_index(reg) & 7));
        emit_byte(cg, value & 0xFF);
    } else {
        emit_byte(cg, rex_prefix(true, false, false, is_extended(reg)));
        emit_byte(cg, 0x81);
        emit_byte(cg, modrm_byte(3, 7, reg_index(reg) & 7));
        for (int i = 0; i < 4; i++) emit_byte(cg, (value >> (i * 8)) & 0xFF);
    }
}

void cg_emit_cmp_reg_reg(CodeGen* cg, X64Register a, X64Register b) {
    emit_byte(cg, rex_prefix(true, is_extended(b), false, is_extended(a)));
    emit_byte(cg, 0x39);
    emit_byte(cg, modrm_byte(3, reg_index(b) & 7, reg_index(a) & 7));
}

void cg_emit_test_reg_reg(CodeGen* cg, X64Register a, X64Register b) {
    emit_byte(cg, rex_prefix(true, is_extended(b), false, is_extended(a)));
    emit_byte(cg, 0x85);
    emit_byte(cg, modrm_byte(3, reg_index(b) & 7, reg_index(a) & 7));
}

// ══════════════════════════════════════
// PUSH, POP
// ══════════════════════════════════════

void cg_emit_push_reg(CodeGen* cg, X64Register reg) {
    if (is_extended(reg)) emit_byte(cg, 0x41);
    emit_byte(cg, 0x50 | (reg_index(reg) & 7));
}

static bool decode_last_push(CodeGen* cg, X64Register* out_reg, size_t* out_size) {
    if (cg->size >= 2) {
        uint8_t b1 = cg->buffer[cg->size - 2];
        uint8_t b2 = cg->buffer[cg->size - 1];
        if (b1 == 0x41 && b2 >= 0x50 && b2 <= 0x57) {
            *out_reg = (X64Register)(REG_R8 + (b2 - 0x50));
            *out_size = 2;
            return true;
        }
    }
    if (cg->size >= 1) {
        uint8_t b = cg->buffer[cg->size - 1];
        if (b >= 0x50 && b <= 0x57) {
            *out_reg = (X64Register)(REG_RAX + (b - 0x50));
            *out_size = 1;
            return true;
        }
    }
    return false;
}

void cg_emit_pop_reg(CodeGen* cg, X64Register reg) {
    X64Register pushed_reg;
    size_t push_size;
    if (decode_last_push(cg, &pushed_reg, &push_size)) {
        cg->size -= push_size; // backtracking
        if (pushed_reg == reg) {
            // push X; pop X => optimized out entirely!
            return;
        } else {
            // push X; pop Y => mov Y, X
            cg_emit_mov_reg_reg(cg, reg, pushed_reg);
            return;
        }
    }

    if (is_extended(reg)) emit_byte(cg, 0x41);
    emit_byte(cg, 0x58 | (reg_index(reg) & 7));
}

// ══════════════════════════════════════
// CALL, RET, SYSCALL
// ══════════════════════════════════════

void cg_emit_call_reg(CodeGen* cg, X64Register reg) {
    if (is_extended(reg)) emit_byte(cg, 0x41);
    emit_byte(cg, 0xFF);
    emit_byte(cg, modrm_byte(3, 2, reg_index(reg) & 7));
}

void cg_emit_call_rel32(CodeGen* cg, int32_t offset) {
    emit_byte(cg, 0xE8);
    for (int i = 0; i < 4; i++) emit_byte(cg, (offset >> (i * 8)) & 0xFF);
}

void cg_emit_ret(CodeGen* cg) { emit_byte(cg, 0xC3); }

void cg_emit_syscall(CodeGen* cg) {
    emit_byte(cg, 0x0F);
    emit_byte(cg, 0x05);
}

void cg_emit_byte(CodeGen* cg, uint8_t byte) {
    emit_byte(cg, byte);
}

void cg_emit_imul_reg_imm32(CodeGen* cg, X64Register dst, X64Register src, int32_t imm) {
    emit_byte(cg, rex_prefix(true, is_extended(dst), false, is_extended(src)));
    emit_byte(cg, 0x69);
    emit_byte(cg, modrm_byte(3, reg_index(dst) & 7, reg_index(src) & 7));
    for (int i = 0; i < 4; i++) emit_byte(cg, (imm >> (i * 8)) & 0xFF);
}

void cg_emit_shl_reg_imm8(CodeGen* cg, X64Register reg, uint8_t imm) {
    emit_byte(cg, rex_prefix(true, false, false, is_extended(reg)));
    if (imm == 1) {
        emit_byte(cg, 0xD1);
        emit_byte(cg, modrm_byte(3, 4, reg_index(reg) & 7));
    } else {
        emit_byte(cg, 0xC1);
        emit_byte(cg, modrm_byte(3, 4, reg_index(reg) & 7));
        emit_byte(cg, imm);
    }
}

void cg_emit_nop(CodeGen* cg) { emit_byte(cg, 0x90); }
void cg_emit_int3(CodeGen* cg) { emit_byte(cg, 0xCC); }

// ══════════════════════════════════════
// قفزات
// ══════════════════════════════════════

void cg_emit_jmp_rel8(CodeGen* cg, int8_t offset) { emit_byte(cg, 0xEB); emit_byte(cg, offset); }
void cg_emit_jmp_rel32(CodeGen* cg, int32_t offset) {
    emit_byte(cg, 0xE9);
    for (int i = 0; i < 4; i++) emit_byte(cg, (offset >> (i * 8)) & 0xFF);
}

void cg_emit_je_rel8(CodeGen* cg, int8_t offset) { emit_byte(cg, 0x74); emit_byte(cg, offset); }
void cg_emit_je_rel32(CodeGen* cg, int32_t offset) {
    emit_byte(cg, 0x0F);
    emit_byte(cg, 0x84);
    for (int i = 0; i < 4; i++) emit_byte(cg, (offset >> (i * 8)) & 0xFF);
}
void cg_emit_jne_rel8(CodeGen* cg, int8_t offset) { emit_byte(cg, 0x75); emit_byte(cg, offset); }
void cg_emit_jl_rel8(CodeGen* cg, int8_t offset) { emit_byte(cg, 0x7C); emit_byte(cg, offset); }
void cg_emit_jle_rel8(CodeGen* cg, int8_t offset) { emit_byte(cg, 0x7E); emit_byte(cg, offset); }
void cg_emit_jg_rel8(CodeGen* cg, int8_t offset) { emit_byte(cg, 0x7F); emit_byte(cg, offset); }
void cg_emit_jge_rel8(CodeGen* cg, int8_t offset) { emit_byte(cg, 0x7D); emit_byte(cg, offset); }

void cg_emit_jmp_label(CodeGen* cg, PatchTable* pt, const char* label) {
    pt_add_patch(pt, cg->size, label, false);
    cg_emit_jmp_rel32(cg, 0);
}

void cg_emit_label(CodeGen* cg, PatchTable* pt, const char* label) {
    pt_add_patch(pt, cg->size, label, true);
}

// ══════════════════════════════════════
// PatchTable
// ══════════════════════════════════════

PatchTable* pt_create(void) {
    PatchTable* pt = (PatchTable*)malloc(sizeof(PatchTable));
    pt->capacity = 64;
    pt->count = 0;
    pt->patches = (PatchPoint*)malloc(sizeof(PatchPoint) * pt->capacity);
    return pt;
}

void pt_destroy(PatchTable* pt) {
    if (pt) {
        for (size_t i = 0; i < pt->count; i++) free(pt->patches[i].label_name);
        free(pt->patches);
        free(pt);
    }
}

void pt_add_patch(PatchTable* pt, size_t position, const char* label, bool is_label) {
    if (pt->count >= pt->capacity) {
        pt->capacity *= 2;
        pt->patches = (PatchPoint*)realloc(pt->patches, sizeof(PatchPoint) * pt->capacity);
    }
    pt->patches[pt->count].position = position;
    pt->patches[pt->count].label_name = strdup(label);
    pt->patches[pt->count].is_label = is_label;
    pt->count++;
}

void pt_resolve_patches(CodeGen* cg, PatchTable* pt) {
    for (size_t i = 0; i < pt->count; i++) {
        if (pt->patches[i].is_label) continue;
        for (size_t j = 0; j < pt->count; j++) {
            if (pt->patches[j].is_label && 
                strcmp(pt->patches[i].label_name, pt->patches[j].label_name) == 0) {
                int32_t offset = (int32_t)(pt->patches[j].position - pt->patches[i].position - 4);
                size_t pos = pt->patches[i].position;
                cg->buffer[pos] = offset & 0xFF;
                cg->buffer[pos + 1] = (offset >> 8) & 0xFF;
                cg->buffer[pos + 2] = (offset >> 16) & 0xFF;
                cg->buffer[pos + 3] = (offset >> 24) & 0xFF;
                break;
            }
        }
    }
}

// ══════════════════════════════════════
// دوال للتوافق مع الإصدارات القديمة (stubs)
// ══════════════════════════════════════

void cg_emit_mov_reg_mem(CodeGen* cg, X64Register reg, X64Register base, int32_t offset) {
    emit_byte(cg, rex_prefix(true, is_extended(reg), false, is_extended(base)));
    emit_byte(cg, 0x8B);
    if (offset >= -128 && offset <= 127) {
        emit_byte(cg, modrm_byte(1, reg_index(reg) & 7, reg_index(base) & 7));
        emit_byte(cg, offset & 0xFF);
    } else {
        emit_byte(cg, modrm_byte(2, reg_index(reg) & 7, reg_index(base) & 7));
        for (int i = 0; i < 4; i++) emit_byte(cg, (offset >> (i * 8)) & 0xFF);
    }
}

void cg_emit_mov_mem_reg(CodeGen* cg, X64Register base, int32_t offset, X64Register reg) {
    emit_byte(cg, rex_prefix(true, is_extended(reg), false, is_extended(base)));
    emit_byte(cg, 0x89);
    if (offset >= -128 && offset <= 127) {
        emit_byte(cg, modrm_byte(1, reg_index(reg) & 7, reg_index(base) & 7));
        emit_byte(cg, offset & 0xFF);
    } else {
        emit_byte(cg, modrm_byte(2, reg_index(reg) & 7, reg_index(base) & 7));
        for (int i = 0; i < 4; i++) emit_byte(cg, (offset >> (i * 8)) & 0xFF);
    }
}

void cg_emit_movss_mem_xmm(CodeGen* cg, X64Register base, int32_t offset, X64Register xmm) {
    emit_byte(cg, 0xF3);
    emit_byte(cg, 0x0F);
    emit_byte(cg, 0x11);
    int base_idx = reg_index(base) & 7;
    int xmm_idx  = reg_index(xmm)  & 7;
    if (base_idx == 4) { // RSP needs SIB
        if (offset >= -128 && offset <= 127) {
            emit_byte(cg, modrm_byte(1, xmm_idx, 4));
            emit_byte(cg, 0x24); // SIB: scale=0, index=none, base=RSP
            emit_byte(cg, (uint8_t)(offset & 0xFF));
        } else {
            emit_byte(cg, modrm_byte(2, xmm_idx, 4));
            emit_byte(cg, 0x24);
            for (int i = 0; i < 4; i++) emit_byte(cg, (offset >> (i * 8)) & 0xFF);
        }
    } else {
        if (offset >= -128 && offset <= 127) {
            emit_byte(cg, modrm_byte(1, xmm_idx, base_idx));
            emit_byte(cg, (uint8_t)(offset & 0xFF));
        } else {
            emit_byte(cg, modrm_byte(2, xmm_idx, base_idx));
            for (int i = 0; i < 4; i++) emit_byte(cg, (offset >> (i * 8)) & 0xFF);
        }
    }
}

void cg_emit_movss_xmm_mem(CodeGen* cg, X64Register xmm, X64Register base, int32_t offset) {
    emit_byte(cg, 0xF3);
    emit_byte(cg, 0x0F);
    emit_byte(cg, 0x10);
    int base_idx = reg_index(base) & 7;
    int xmm_idx  = reg_index(xmm)  & 7;
    if (base_idx == 4) { // RSP needs SIB
        if (offset >= -128 && offset <= 127) {
            emit_byte(cg, modrm_byte(1, xmm_idx, 4));
            emit_byte(cg, 0x24);
            emit_byte(cg, (uint8_t)(offset & 0xFF));
        } else {
            emit_byte(cg, modrm_byte(2, xmm_idx, 4));
            emit_byte(cg, 0x24);
            for (int i = 0; i < 4; i++) emit_byte(cg, (offset >> (i * 8)) & 0xFF);
        }
    } else {
        if (offset >= -128 && offset <= 127) {
            emit_byte(cg, modrm_byte(1, xmm_idx, base_idx));
            emit_byte(cg, (uint8_t)(offset & 0xFF));
        } else {
            emit_byte(cg, modrm_byte(2, xmm_idx, base_idx));
            for (int i = 0; i < 4; i++) emit_byte(cg, (offset >> (i * 8)) & 0xFF);
        }
    }
}

void cg_emit_addss_xmm_xmm(CodeGen* cg, X64Register dst, X64Register src) {
    emit_byte(cg, 0xF3); emit_byte(cg, 0x0F); emit_byte(cg, 0x58);
    emit_byte(cg, modrm_byte(3, reg_index(dst) & 7, reg_index(src) & 7));
}
void cg_emit_subss_xmm_xmm(CodeGen* cg, X64Register dst, X64Register src) {
    emit_byte(cg, 0xF3); emit_byte(cg, 0x0F); emit_byte(cg, 0x5C);
    emit_byte(cg, modrm_byte(3, reg_index(dst) & 7, reg_index(src) & 7));
}
void cg_emit_mulss_xmm_xmm(CodeGen* cg, X64Register dst, X64Register src) {
    emit_byte(cg, 0xF3); emit_byte(cg, 0x0F); emit_byte(cg, 0x59);
    emit_byte(cg, modrm_byte(3, reg_index(dst) & 7, reg_index(src) & 7));
}
void cg_emit_divss_xmm_xmm(CodeGen* cg, X64Register dst, X64Register src) {
    emit_byte(cg, 0xF3); emit_byte(cg, 0x0F); emit_byte(cg, 0x5E);
    emit_byte(cg, modrm_byte(3, reg_index(dst) & 7, reg_index(src) & 7));
}

void cg_emit_cvttss2si_reg_xmm(CodeGen* cg, X64Register dst, X64Register src) {
    emit_byte(cg, 0xF3); emit_byte(cg, rex_prefix(true, is_extended(dst), false, false));
    emit_byte(cg, 0x0F); emit_byte(cg, 0x2C);
    emit_byte(cg, modrm_byte(3, reg_index(dst) & 7, reg_index(src) & 7));
}

void cg_emit_cvtsi2ss_xmm_reg(CodeGen* cg, X64Register dst, X64Register src) {
    emit_byte(cg, 0xF3); emit_byte(cg, rex_prefix(true, false, false, is_extended(src)));
    emit_byte(cg, 0x0F); emit_byte(cg, 0x2A);
    emit_byte(cg, modrm_byte(3, reg_index(dst) & 7, reg_index(src) & 7));
}

void cg_emit_movss_xmm_rip(CodeGen* cg, X64Register reg, int32_t disp32) {
    emit_byte(cg, 0xF3);
    emit_byte(cg, 0x0F); emit_byte(cg, 0x10);
    emit_byte(cg, modrm_byte(0, reg_index(reg) & 7, 5));
    for (int i = 0; i < 4; i++) emit_byte(cg, (disp32 >> (i * 8)) & 0xFF);
}

void cg_emit_vtable(CodeGen* cg, const char** method_labels, int count) {
    (void)method_labels;
    for (int i = 0; i < count; i++) {
        for (int b = 0; b < 8; b++) {
            emit_byte(cg, 0);
        }
    }
}

void cg_emit_movzx_byte(CodeGen* cg, X64Register reg, X64Register base, int32_t offset) {
    emit_byte(cg, rex_prefix(true, is_extended(reg), false, is_extended(base)));
    emit_byte(cg, 0x0F);
    emit_byte(cg, 0xB6);
    if (offset >= -128 && offset <= 127) {
        emit_byte(cg, modrm_byte(1, reg_index(reg) & 7, reg_index(base) & 7));
        emit_byte(cg, offset & 0xFF);
    } else {
        emit_byte(cg, modrm_byte(2, reg_index(reg) & 7, reg_index(base) & 7));
        for (int i = 0; i < 4; i++) emit_byte(cg, (offset >> (i * 8)) & 0xFF);
    }
}

void cg_emit_movzx_word(CodeGen* cg, X64Register reg, X64Register base, int32_t offset) {
    emit_byte(cg, rex_prefix(true, is_extended(reg), false, is_extended(base)));
    emit_byte(cg, 0x0F);
    emit_byte(cg, 0xB7);
    if (offset >= -128 && offset <= 127) {
        emit_byte(cg, modrm_byte(1, reg_index(reg) & 7, reg_index(base) & 7));
        emit_byte(cg, offset & 0xFF);
    } else {
        emit_byte(cg, modrm_byte(2, reg_index(reg) & 7, reg_index(base) & 7));
        for (int i = 0; i < 4; i++) emit_byte(cg, (offset >> (i * 8)) & 0xFF);
    }
}

void cg_emit_mov_reg_mem32(CodeGen* cg, X64Register reg, X64Register base, int32_t offset) {
    emit_byte(cg, rex_prefix(false, is_extended(reg), false, is_extended(base)));
    emit_byte(cg, 0x8B);
    if (offset >= -128 && offset <= 127) {
        emit_byte(cg, modrm_byte(1, reg_index(reg) & 7, reg_index(base) & 7));
        emit_byte(cg, offset & 0xFF);
    } else {
        emit_byte(cg, modrm_byte(2, reg_index(reg) & 7, reg_index(base) & 7));
        for (int i = 0; i < 4; i++) emit_byte(cg, (offset >> (i * 8)) & 0xFF);
    }
}

void cg_emit_mov_mem_reg8(CodeGen* cg, X64Register base, int32_t offset, X64Register reg) {
    emit_byte(cg, rex_prefix(false, is_extended(reg), false, is_extended(base)));
    emit_byte(cg, 0x88);
    if (offset >= -128 && offset <= 127) {
        emit_byte(cg, modrm_byte(1, reg_index(reg) & 7, reg_index(base) & 7));
        emit_byte(cg, offset & 0xFF);
    } else {
        emit_byte(cg, modrm_byte(2, reg_index(reg) & 7, reg_index(base) & 7));
        for (int i = 0; i < 4; i++) emit_byte(cg, (offset >> (i * 8)) & 0xFF);
    }
}

void cg_emit_mov_mem_reg16(CodeGen* cg, X64Register base, int32_t offset, X64Register reg) {
    emit_byte(cg, 0x66); // 16-bit override
    emit_byte(cg, rex_prefix(false, is_extended(reg), false, is_extended(base)));
    emit_byte(cg, 0x89);
    if (offset >= -128 && offset <= 127) {
        emit_byte(cg, modrm_byte(1, reg_index(reg) & 7, reg_index(base) & 7));
        emit_byte(cg, offset & 0xFF);
    } else {
        emit_byte(cg, modrm_byte(2, reg_index(reg) & 7, reg_index(base) & 7));
        for (int i = 0; i < 4; i++) emit_byte(cg, (offset >> (i * 8)) & 0xFF);
    }
}

void cg_emit_mov_mem_reg32(CodeGen* cg, X64Register base, int32_t offset, X64Register reg) {
    emit_byte(cg, rex_prefix(false, is_extended(reg), false, is_extended(base)));
    emit_byte(cg, 0x89);
    if (offset >= -128 && offset <= 127) {
        emit_byte(cg, modrm_byte(1, reg_index(reg) & 7, reg_index(base) & 7));
        emit_byte(cg, offset & 0xFF);
    } else {
        emit_byte(cg, modrm_byte(2, reg_index(reg) & 7, reg_index(base) & 7));
        for (int i = 0; i < 4; i++) emit_byte(cg, (offset >> (i * 8)) & 0xFF);
    }
}
