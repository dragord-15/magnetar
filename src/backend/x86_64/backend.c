#include "../backend.h"
#include "../elf_writer.h"
#include "../pe_writer.h"
#include "codegen.h"
#include "encoder.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    char* entry_name;
    char* format; /* elf, pe */
} X86_64State;

static const char* g_x86_64_format = "elf";
const char* x86_64_current_format(void) { return g_x86_64_format; }

static void* x86_64_create(void) {
    X86_64State* state = (X86_64State*)malloc(sizeof(X86_64State));
    if (state) {
        state->entry_name = strdup("main");
        state->format = strdup("elf");
    }
    g_x86_64_format = "elf";
    return state;
}

static void x86_64_destroy(void* state) {
    X86_64State* st = (X86_64State*)state;
    if (st) {
        free(st->entry_name);
        free(st->format);
    }
    free(state);
}

static void x86_64_set_entry(void* state, const char* name) {
    X86_64State* st = (X86_64State*)state;
    if (!st) return;
    free(st->entry_name);
    st->entry_name = strdup(name && *name ? name : "main");
}

static void x86_64_set_format(void* state, const char* format) {
    X86_64State* st = (X86_64State*)state;
    if (!st) return;
    free(st->format);
    st->format = strdup(format && *format ? format : "elf");
    g_x86_64_format = st->format;
}

static bool x86_64_generate(void* state, IRProgram* ir, BackendResult* result, bool object_mode) {
    (void)state;
    backend_result_init(result);

    AsmGen gen;
    AsmGen_init(&gen, ir);
    AsmGen_set_entry_name(((X86_64State*)state)->entry_name);
    gen.is_object_mode = object_mode;

    if (!AsmGen_generate(&gen)) {
        AsmGen_free(&gen);
        return false;
    }

    size_t code_size;
    result->code = AsmGen_get_native_code(&gen, &code_size);
    result->code_size = code_size;

    size_t rodata_size;
    result->rodata = AsmGen_get_data_section(&gen, &rodata_size);
    result->rodata_size = rodata_size;

    int exp_count = AsmGen_get_func_count();
    result->num_exports = 0;
    for (int i = 0; i < exp_count && i < MAX_EXPORTS; i++) {
        result->exports[i].name = strdup(AsmGen_get_func_name(i));
        result->exports[i].offset = (uint32_t)AsmGen_get_func_pos(i);
        result->num_exports++;
    }

    result->patches = NULL;
    result->num_patches = 0;
    if (object_mode && gen.pt) {
        for (size_t i = 0; i < gen.pt->count; i++) {
            PatchPoint* p = &gen.pt->patches[i];
            if (p->is_label) continue;

            bool has_local = false;
            for (size_t j = 0; j < gen.pt->count; j++) {
                if (gen.pt->patches[j].is_label &&
                    strcmp(gen.pt->patches[j].label_name, p->label_name) == 0) {
                    has_local = true;
                    break;
                }
            }
            if (!has_local) {
                result->num_patches++;
                result->patches = (ImportPatch*)realloc(result->patches,
                    sizeof(ImportPatch) * result->num_patches);
                result->patches[result->num_patches - 1].name = strdup(p->label_name);
                result->patches[result->num_patches - 1].position = p->position;
                result->patches[result->num_patches - 1].type = MAG_PATCH_X86_PC32;
            }
        }
    }

    AsmGen_free(&gen);
    return true;
}

static bool x86_64_write_executable(const char* path, BackendResult* result) {
    /* format selected via state stored in global-like pattern? backend API passes no state here.
       We detect by checking for PE magic request through env-like global set by wrapper below. */
    extern const char* x86_64_current_format(void);
    const char* fmt = x86_64_current_format();

    if (fmt && strcmp(fmt, "pe") == 0) {
        PEBuilder builder;
        builder.text_section = result->code;
        builder.text_size = result->code_size;
        builder.rodata_section = result->rodata;
        builder.rodata_size = result->rodata_size;
        builder.data_section = NULL;
        builder.data_size = 0;
        builder.image_base = 0x140000000ULL;
        builder.subsystem = 3; /* console */
        size_t pe_size;
        uint8_t* pe_data = pe_build(&builder, &pe_size);
        if (!pe_data) return false;
        int res = pe_write_file(path, pe_data, pe_size);
        pe_free(pe_data);
        if (res == 0) {
            printf("[Backend] Created '%s' (%zu bytes, PE64)\n", path, pe_size);
            return true;
        }
        return false;
    }

    ELFBuilder builder;
    builder.text_section = result->code;
    builder.text_size = result->code_size;
    builder.rodata_section = result->rodata;
    builder.rodata_size = result->rodata_size;
    builder.data_section = NULL;
    builder.data_size = 0;
    builder.entry_point = 0x400000 + 64 + 56;

    size_t elf_size;
    uint8_t* elf_data = elf_build(&builder, &elf_size);
    if (!elf_data) return false;

    int res = elf_write_file(path, elf_data, elf_size);
    elf_free(elf_data);
    if (res == 0) {
        printf("[Backend] Created '%s' (%zu bytes, ELF64)\n", path, elf_size);
        return true;
    }
    return false;
}

static bool x86_64_write_object(const char* path, BackendResult* result) {
    FILE* f = fopen(path, "wb");
    if (!f) {
        fprintf(stderr, "Error: Cannot open '%s' for writing\n", path);
        return false;
    }

    fwrite("MAGO", 1, 4, f);
    uint32_t code_size_32 = (uint32_t)result->code_size;
    fwrite(&code_size_32, sizeof(uint32_t), 1, f);
    fwrite(result->code, 1, result->code_size, f);

    uint32_t num_exports = (uint32_t)result->num_exports;
    fwrite(&num_exports, sizeof(uint32_t), 1, f);
    for (uint32_t i = 0; i < num_exports; i++) {
        uint32_t pos = result->exports[i].offset;
        uint32_t name_len = (uint32_t)strlen(result->exports[i].name);
        fwrite(&pos, sizeof(uint32_t), 1, f);
        fwrite(&name_len, sizeof(uint32_t), 1, f);
        fwrite(result->exports[i].name, 1, name_len, f);
    }

    uint32_t num_patches = (uint32_t)result->num_patches;
    fwrite(&num_patches, sizeof(uint32_t), 1, f);
    for (int i = 0; i < result->num_patches; i++) {
        uint32_t pos = (uint32_t)result->patches[i].position;
        uint32_t name_len = (uint32_t)strlen(result->patches[i].name);
        fwrite(&pos, sizeof(uint32_t), 1, f);
        fwrite(&name_len, sizeof(uint32_t), 1, f);
        fwrite(result->patches[i].name, 1, name_len, f);
    }

    fclose(f);
    printf("[Backend] Created object file '%s'\n", path);
    return true;
}

extern void emit_print_string_var_mag(CodeGen* cg);
extern void emit_print_int_mag(CodeGen* cg);
extern void emit_print_float_mag(CodeGen* cg);
extern void emit_dyn_push_mag(CodeGen* cg);

static void emit_print_string_self_contained(CodeGen* cg, const char* str, size_t len) {
    cg_emit_mov_reg_imm64(cg, REG_RAX, 1);
    cg_emit_mov_reg_imm64(cg, REG_RDI, 1);
    cg_emit_lea_reg_rip(cg, REG_RSI, 0);
    size_t patch_pos = cg_get_size(cg) - 4;
    cg_emit_mov_reg_imm64(cg, REG_RDX, len);
    cg_emit_syscall(cg);
    cg_emit_jmp_rel8(cg, (int8_t)len);
    size_t string_pos = cg_get_size(cg);
    for (size_t i = 0; i < len; i++) cg_emit_byte(cg, str[i]);
    int32_t disp = (int32_t)(string_pos - (patch_pos + 4));
    cg->buffer[patch_pos] = disp & 0xFF;
    cg->buffer[patch_pos + 1] = (disp >> 8) & 0xFF;
    cg->buffer[patch_pos + 2] = (disp >> 16) & 0xFF;
    cg->buffer[patch_pos + 3] = (disp >> 24) & 0xFF;
}

static void emit_print_string_var_mag_local(CodeGen* cg) {
    cg_emit_mov_reg_reg(cg, REG_RSI, REG_RAX);
    cg_emit_xor_reg_reg(cg, REG_RDX, REG_RDX);
    int loop_top = cg_get_size(cg);
    cg_emit_byte(cg, 0x48); cg_emit_byte(cg, 0x0F); cg_emit_byte(cg, 0xB6);
    cg_emit_byte(cg, 0x0C); cg_emit_byte(cg, 0x16);
    cg_emit_test_reg_reg(cg, REG_RCX, REG_RCX);
    cg_emit_je_rel8(cg, 0);
    int patch_exit = cg_get_size(cg) - 1;
    cg_emit_byte(cg, 0x48); cg_emit_byte(cg, 0xFF); cg_emit_byte(cg, 0xC2);
    int back_offset = loop_top - (cg_get_size(cg) + 2);
    cg_emit_jmp_rel8(cg, (int8_t)back_offset);
    cg->buffer[patch_exit] = (uint8_t)(cg_get_size(cg) - (patch_exit + 1));
    cg_emit_mov_reg_imm64(cg, REG_RAX, 1);
    cg_emit_mov_reg_imm64(cg, REG_RDI, 1);
    cg_emit_syscall(cg);
}

static void emit_print_int_mag_local(CodeGen* cg) {
    cg_emit_sub_reg_imm32(cg, REG_RSP, 32);
    cg_emit_mov_reg_reg(cg, REG_RCX, REG_RSP);
    cg_emit_add_reg_imm32(cg, REG_RCX, 30);
    cg_emit_mov_reg_imm64(cg, REG_R8, 10);
    cg_emit_mov_reg_reg(cg, REG_R9, REG_RCX);
    int loop_start = cg_get_size(cg);
    cg_emit_xor_reg_reg(cg, REG_RDX, REG_RDX);
    cg_emit_idiv_reg(cg, REG_R8);
    cg_emit_add_reg_imm32(cg, REG_RDX, 48);
    cg_emit_sub_reg_imm32(cg, REG_RCX, 1);
    cg_emit_byte(cg, 0x88); cg_emit_byte(cg, 0x11);
    cg_emit_test_reg_reg(cg, REG_RAX, REG_RAX);
    int offset = loop_start - (cg_get_size(cg) + 2);
    cg_emit_jne_rel8(cg, (int8_t)offset);
    cg_emit_mov_reg_imm64(cg, REG_RAX, 1);
    cg_emit_mov_reg_imm64(cg, REG_RDI, 1);
    cg_emit_mov_reg_reg(cg, REG_RSI, REG_RCX);
    cg_emit_mov_reg_reg(cg, REG_RDX, REG_R9);
    cg_emit_sub_reg_reg(cg, REG_RDX, REG_RCX);
    cg_emit_syscall(cg);
    cg_emit_add_reg_imm32(cg, REG_RSP, 32);
}

static void emit_print_float_mag_local(CodeGen* cg) {
    cg_emit_cvttss2si_reg_xmm(cg, REG_RAX, REG_XMM0);
    cg_emit_cvtsi2ss_xmm_reg(cg, REG_XMM1, REG_RAX);
    cg_emit_subss_xmm_xmm(cg, REG_XMM0, REG_XMM1);
    cg_emit_push_reg(cg, REG_RAX);
    emit_print_int_mag_local(cg);
    emit_print_string_self_contained(cg, ".", 1);
    int ten_k = 10000;
    cg_emit_mov_reg_imm64(cg, REG_RAX, ten_k);
    cg_emit_cvtsi2ss_xmm_reg(cg, REG_XMM1, REG_RAX);
    cg_emit_byte(cg, 0xF3); cg_emit_byte(cg, 0x0F);
    cg_emit_byte(cg, 0x59); cg_emit_byte(cg, 0xC1);
    cg_emit_cvttss2si_reg_xmm(cg, REG_RAX, REG_XMM0);
    emit_print_int_mag_local(cg);
    cg_emit_pop_reg(cg, REG_RCX);
}

static void emit_dyn_push_mag_local(CodeGen* cg) {
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RCX, REG_RBP, 16);
    cg_emit_mov_reg_mem(cg, REG_RAX, REG_RCX, 0);
    cg_emit_mov_reg_mem(cg, REG_RDX, REG_RCX, 8);
    cg_emit_mov_reg_mem(cg, REG_R8, REG_RCX, 16);
    cg_emit_cmp_reg_reg(cg, REG_RDX, REG_R8);
    cg_emit_byte(cg, 0x75); cg_emit_byte(cg, 0);
    int jne_skip_alloc = cg_get_size(cg) - 1;
    cg_emit_push_reg(cg, REG_RCX);
    cg_emit_push_reg(cg, REG_RDX);
    cg_emit_test_reg_reg(cg, REG_R8, REG_R8);
    cg_emit_byte(cg, 0x75); cg_emit_byte(cg, 0);
    int jnz_do_mremap = cg_get_size(cg) - 1;
    cg_emit_mov_reg_imm32(cg, REG_RAX, 9);
    cg_emit_mov_reg_imm32(cg, REG_RDI, 0);
    cg_emit_mov_reg_imm32(cg, REG_RSI, 32);
    cg_emit_mov_reg_imm32(cg, REG_RDX, 3);
    cg_emit_mov_reg_imm32(cg, REG_R10, 0x22);
    cg_emit_mov_reg_imm32(cg, REG_R8, -1);
    cg_emit_mov_reg_imm32(cg, REG_R9, 0);
    cg_emit_byte(cg, 0x0F); cg_emit_byte(cg, 0x05);
    cg_emit_mov_reg_imm32(cg, REG_R8, 4);
    cg_emit_byte(cg, 0xEB); cg_emit_byte(cg, 0);
    int jmp_alloc_done = cg_get_size(cg) - 1;
    cg->buffer[jnz_do_mremap] = cg_get_size(cg) - jnz_do_mremap - 1;
    cg_emit_mov_reg_reg(cg, REG_RDI, REG_RAX);
    cg_emit_mov_reg_reg(cg, REG_RSI, REG_R8);
    cg_emit_shl_reg_imm8(cg, REG_RSI, 3);
    cg_emit_mov_reg_reg(cg, REG_RDX, REG_RSI);
    cg_emit_shl_reg_imm8(cg, REG_RDX, 1);
    cg_emit_mov_reg_imm32(cg, REG_R10, 1);
    cg_emit_mov_reg_imm32(cg, REG_RAX, 25);
    cg_emit_byte(cg, 0x0F); cg_emit_byte(cg, 0x05);
    cg_emit_shl_reg_imm8(cg, REG_R8, 1);
    cg->buffer[jmp_alloc_done] = cg_get_size(cg) - jmp_alloc_done - 1;
    cg_emit_pop_reg(cg, REG_RDX);
    cg_emit_pop_reg(cg, REG_RCX);
    cg_emit_mov_mem_reg(cg, REG_RCX, 0, REG_RAX);
    cg_emit_mov_mem_reg(cg, REG_RCX, 16, REG_R8);
    cg->buffer[jne_skip_alloc] = cg_get_size(cg) - jne_skip_alloc - 1;
    cg_emit_mov_reg_mem(cg, REG_RAX, REG_RCX, 0);
    cg_emit_mov_reg_mem(cg, REG_R9, REG_RBP, 24);
    cg_emit_mov_reg_reg(cg, REG_R8, REG_RDX);
    cg_emit_shl_reg_imm8(cg, REG_R8, 3);
    cg_emit_add_reg_reg(cg, REG_RAX, REG_R8);
    cg_emit_mov_mem_reg(cg, REG_RAX, 0, REG_R9);
    cg_emit_add_reg_imm32(cg, REG_RDX, 1);
    cg_emit_mov_mem_reg(cg, REG_RCX, 8, REG_RDX);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
}

static bool x86_64_generate_stub(void* state, uint8_t** buf, size_t* size, const char* name) {
    (void)state;
    CodeGen* cg = cg_create(256);

    if (strcmp(name, "exit") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16);
        cg_emit_mov_reg_imm64(cg, REG_RAX, 60);
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "printf") == 0 || strcmp(name, "print_str") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RAX, REG_RBP, 16);
        emit_print_string_var_mag_local(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "print_int") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RAX, REG_RBP, 16);
        emit_print_int_mag_local(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "print_float") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_movss_xmm_mem(cg, REG_XMM0, REG_RBP, 16);
        emit_print_float_mag_local(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "get_timestamp") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_imm64(cg, REG_RDI, 0);
        cg_emit_mov_reg_imm64(cg, REG_RAX, 201);
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sleep_ms") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RAX, REG_RBP, 16);
        cg_emit_mov_reg_imm64(cg, REG_RCX, 1000);
        cg_emit_xor_reg_reg(cg, REG_RDX, REG_RDX);
        cg_emit_idiv_reg(cg, REG_RCX);
        cg_emit_mov_reg_reg(cg, REG_R9, REG_RAX);
        cg_emit_mov_reg_reg(cg, REG_RAX, REG_RDX);
        cg_emit_mov_reg_imm64(cg, REG_RCX, 1000000);
        cg_emit_imul_reg_reg(cg, REG_RAX, REG_RCX);
        cg_emit_push_reg(cg, REG_RAX);
        cg_emit_push_reg(cg, REG_R9);
        cg_emit_mov_reg_reg(cg, REG_RDI, REG_RSP);
        cg_emit_mov_reg_imm64(cg, REG_RSI, 0);
        cg_emit_mov_reg_imm64(cg, REG_RAX, 35);
        cg_emit_syscall(cg);
        cg_emit_add_reg_imm32(cg, REG_RSP, 16);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "rand_int") == 0) {
        cg_emit_byte(cg, 0x0F); cg_emit_byte(cg, 0x31);
        cg_emit_byte(cg, 0x48); cg_emit_byte(cg, 0xC1);
        cg_emit_byte(cg, 0xE2); cg_emit_byte(cg, 0x20);
        cg_emit_byte(cg, 0x48); cg_emit_byte(cg, 0x09); cg_emit_byte(cg, 0xD0);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sqrt") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_movss_xmm_mem(cg, REG_XMM0, REG_RBP, 16);
        cg_emit_byte(cg, 0xF3); cg_emit_byte(cg, 0x0F);
        cg_emit_byte(cg, 0x51); cg_emit_byte(cg, 0xC0);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sin") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_movss_xmm_mem(cg, REG_XMM0, REG_RBP, 16);
        cg_emit_sub_reg_imm32(cg, REG_RSP, 8);
        cg_emit_movss_mem_xmm(cg, REG_RSP, 0, REG_XMM0);
        cg_emit_byte(cg, 0xD9); cg_emit_byte(cg, 0x04); cg_emit_byte(cg, 0x24);
        cg_emit_byte(cg, 0xD9); cg_emit_byte(cg, 0xFE);
        cg_emit_byte(cg, 0xD9); cg_emit_byte(cg, 0x1C); cg_emit_byte(cg, 0x24);
        cg_emit_movss_xmm_mem(cg, REG_XMM0, REG_RSP, 0);
        cg_emit_add_reg_imm32(cg, REG_RSP, 8);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "cos") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_movss_xmm_mem(cg, REG_XMM0, REG_RBP, 16);
        cg_emit_sub_reg_imm32(cg, REG_RSP, 8);
        cg_emit_movss_mem_xmm(cg, REG_RSP, 0, REG_XMM0);
        cg_emit_byte(cg, 0xD9); cg_emit_byte(cg, 0x04); cg_emit_byte(cg, 0x24);
        cg_emit_byte(cg, 0xD9); cg_emit_byte(cg, 0xFF);
        cg_emit_byte(cg, 0xD9); cg_emit_byte(cg, 0x1C); cg_emit_byte(cg, 0x24);
        cg_emit_movss_xmm_mem(cg, REG_XMM0, REG_RSP, 0);
        cg_emit_add_reg_imm32(cg, REG_RSP, 8);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "__dyn_push") == 0) {
        emit_dyn_push_mag_local(cg);
    } else if (strcmp(name, "sys_mmap") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // addr
        cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // length
        cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // prot
        cg_emit_mov_reg_mem(cg, REG_R10, REG_RBP, 40); // flags
        cg_emit_mov_reg_mem(cg, REG_R8, REG_RBP, 48);  // fd
        cg_emit_mov_reg_mem(cg, REG_R9, REG_RBP, 56);  // offset
        cg_emit_mov_reg_imm64(cg, REG_RAX, 9); // sys_mmap
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sys_munmap") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // addr
        cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // length
        cg_emit_mov_reg_imm64(cg, REG_RAX, 11); // sys_munmap
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sys_ioctl") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // fd
        cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // request
        cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg
        cg_emit_mov_reg_imm64(cg, REG_RAX, 16); // sys_ioctl
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sys_open") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // path
        cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // flags
        cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // mode
        cg_emit_mov_reg_imm64(cg, REG_RAX, 2); // sys_open
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sys_close") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // fd
        cg_emit_mov_reg_imm64(cg, REG_RAX, 3); // sys_close
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sys_read") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // fd
        cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // buf
        cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // count
        cg_emit_mov_reg_imm64(cg, REG_RAX, 0); // sys_read
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sys_write") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // fd
        cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // buf
        cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // count
        cg_emit_mov_reg_imm64(cg, REG_RAX, 1); // sys_write
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sys_lseek") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // fd
        cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // offset
        cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // whence
        cg_emit_mov_reg_imm64(cg, REG_RAX, 8); // sys_lseek
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sys_unlink") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // path
        cg_emit_mov_reg_imm64(cg, REG_RAX, 87); // sys_unlink
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sys_rename") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // oldpath
        cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // newpath
        cg_emit_mov_reg_imm64(cg, REG_RAX, 82); // sys_rename
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sys_mkdir") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // path
        cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // mode
        cg_emit_mov_reg_imm64(cg, REG_RAX, 83); // sys_mkdir
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sys_rmdir") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // path
        cg_emit_mov_reg_imm64(cg, REG_RAX, 84); // sys_rmdir
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sys_chdir") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // path
        cg_emit_mov_reg_imm64(cg, REG_RAX, 80); // sys_chdir
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sys_getcwd") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // buf
        cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // size
        cg_emit_mov_reg_imm64(cg, REG_RAX, 79); // sys_getcwd
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sys_fork") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_imm64(cg, REG_RAX, 57); // sys_fork
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sys_getpid") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_imm64(cg, REG_RAX, 39); // sys_getpid
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sys_getuid") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_imm64(cg, REG_RAX, 102); // sys_getuid
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sys_stat") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_imm64(cg, REG_RAX, 4); // int stat(const char*, struct stat*)
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sys_lstat") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_imm64(cg, REG_RAX, 6); // int lstat(const char*, struct stat*)
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sys_fstat") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_imm64(cg, REG_RAX, 5); // int fstat(int, struct stat*)
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sys_statx") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3
        cg_emit_mov_reg_mem(cg, REG_R10, REG_RBP, 40); // arg4
        cg_emit_mov_reg_mem(cg, REG_R8, REG_RBP, 48); // arg5
        cg_emit_mov_reg_imm64(cg, REG_RAX, 332); // int statx(int, const char*, int, unsigned, void*)
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sys_newstat") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // path
        cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // statbuf
        cg_emit_mov_reg_imm64(cg, REG_RAX, 4); // sys_newstat
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sys_getdents64") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // fd
        cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // dirp
        cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // count
        cg_emit_mov_reg_imm64(cg, REG_RAX, 217); // sys_getdents64
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sys_wait4") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // pid
        cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // wstatus
        cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // options
        cg_emit_mov_reg_mem(cg, REG_R10, REG_RBP, 40); // rusage
        cg_emit_mov_reg_imm64(cg, REG_RAX, 61); // sys_wait4
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sys_mount") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16);
        cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24);
        cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32);
        cg_emit_mov_reg_mem(cg, REG_R10, REG_RBP, 40);
        cg_emit_mov_reg_mem(cg, REG_R8, REG_RBP, 48);
        cg_emit_mov_reg_imm64(cg, REG_RAX, 165);
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sys_umount2") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16);
        cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24);
        cg_emit_mov_reg_imm64(cg, REG_RAX, 166);
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sys_dup2") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16);
        cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24);
        cg_emit_mov_reg_imm64(cg, REG_RAX, 33);
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sys_execve") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16);
        cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24);
        cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32);
        cg_emit_mov_reg_imm64(cg, REG_RAX, 59);
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sys_setsid") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_imm64(cg, REG_RAX, 112);
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sys_sethostname") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16);
        cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24);
        cg_emit_mov_reg_imm64(cg, REG_RAX, 170);
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sys_sync") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_imm64(cg, REG_RAX, 162);
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sys_reboot") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16);
        cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24);
        cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32);
        cg_emit_mov_reg_mem(cg, REG_R10, REG_RBP, 40);
        cg_emit_mov_reg_imm64(cg, REG_RAX, 169);
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sys_kill") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16);
        cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24);
        cg_emit_mov_reg_imm64(cg, REG_RAX, 62);
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sys_getppid") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_imm64(cg, REG_RAX, 110);
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sys_readlink") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16);
        cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24);
        cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32);
        cg_emit_mov_reg_imm64(cg, REG_RAX, 89);
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sys_exit_group") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16);
        cg_emit_mov_reg_imm64(cg, REG_RAX, 231);
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    } else if (strcmp(name, "sys_rt_sigaction") == 0) {
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16);
        cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24);
        cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32);
        cg_emit_mov_reg_mem(cg, REG_R10, REG_RBP, 40);
        cg_emit_mov_reg_imm64(cg, REG_RAX, 13);
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_pipe") == 0) {
    // int pipe(int fds[2])
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_imm64(cg, REG_RAX, 22); // sys_pipe
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_dup") == 0) {
    // int dup(int oldfd)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_imm64(cg, REG_RAX, 32); // sys_dup
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_dup3") == 0) {
    // int dup3(int old, int new, int flags)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3
    cg_emit_mov_reg_imm64(cg, REG_RAX, 292); // sys_dup3
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_fcntl") == 0) {
    // int fcntl(int fd, int cmd, int arg)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3
    cg_emit_mov_reg_imm64(cg, REG_RAX, 72); // sys_fcntl
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_fsync") == 0) {
    // int fsync(int fd)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_imm64(cg, REG_RAX, 74); // sys_fsync
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_fdatasync") == 0) {
    // int fdatasync(int fd)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_imm64(cg, REG_RAX, 75); // sys_fdatasync
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_ftruncate") == 0) {
    // int ftruncate(int fd, int len)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_imm64(cg, REG_RAX, 77); // sys_ftruncate
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_truncate") == 0) {
    // int truncate(char* path, int len)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_imm64(cg, REG_RAX, 76); // sys_truncate
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_flock") == 0) {
    // int flock(int fd, int op)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_imm64(cg, REG_RAX, 73); // sys_flock
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_access") == 0) {
    // int access(char* path, int mode)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_imm64(cg, REG_RAX, 21); // sys_access
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_writev") == 0) {
    // ssize_t writev(int fd, void* iov, int cnt)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3
    cg_emit_mov_reg_imm64(cg, REG_RAX, 20); // sys_writev
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_readv") == 0) {
    // ssize_t readv(int fd, void* iov, int cnt)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3
    cg_emit_mov_reg_imm64(cg, REG_RAX, 19); // sys_readv
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_setuid") == 0) {
    // int setuid(int uid)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_imm64(cg, REG_RAX, 105); // sys_setuid
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_setgid") == 0) {
    // int setgid(int gid)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_imm64(cg, REG_RAX, 106); // sys_setgid
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_setgroups") == 0) {
    // int setgroups(int n, int* list)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_imm64(cg, REG_RAX, 116); // sys_setgroups
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_setresuid") == 0) {
    // int setresuid(int r, int e, int s)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3
    cg_emit_mov_reg_imm64(cg, REG_RAX, 117); // sys_setresuid
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_setresgid") == 0) {
    // int setresgid(int r, int e, int s)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3
    cg_emit_mov_reg_imm64(cg, REG_RAX, 119); // sys_setresgid
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_capset") == 0) {
    // int capset(int hdr, int data)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_imm64(cg, REG_RAX, 126); // sys_capset
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_setpriority") == 0) {
    // int setpriority(int which, int who, int prio)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3
    cg_emit_mov_reg_imm64(cg, REG_RAX, 141); // sys_setpriority
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_sched_setscheduler") == 0) {
    // int sched_setscheduler(int pid, int pol, int par)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3
    cg_emit_mov_reg_imm64(cg, REG_RAX, 156); // sys_sched_setscheduler
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_sched_yield") == 0) {
    // int sched_yield(void)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_imm64(cg, REG_RAX, 24); // sys_sched_yield
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_prctl") == 0) {
    // int prctl(int opt, int a2..a5)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3
    cg_emit_mov_reg_mem(cg, REG_R10, REG_RBP, 40); // arg4
    cg_emit_mov_reg_mem(cg, REG_R8, REG_RBP, 48); // arg5
    cg_emit_mov_reg_imm64(cg, REG_RAX, 157); // sys_prctl
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_chroot") == 0) {
    // int chroot(char* path)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_imm64(cg, REG_RAX, 161); // sys_chroot
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_pivot_root") == 0) {
    // int pivot_root(char* nr, char* po)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_imm64(cg, REG_RAX, 155); // sys_pivot_root
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_uname") == 0) {
    // int uname(void* buf)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_imm64(cg, REG_RAX, 63); // sys_uname
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_sysinfo") == 0) {
    // int sysinfo(void* info)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_imm64(cg, REG_RAX, 99); // sys_sysinfo
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_gettid") == 0) {
    // int gettid(void)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_imm64(cg, REG_RAX, 186); // sys_gettid
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_tgkill") == 0) {
    // int tgkill(int tgid, int tid, int sig)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3
    cg_emit_mov_reg_imm64(cg, REG_RAX, 234); // sys_tgkill
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_getrandom") == 0) {
    // long getrandom(void* buf, int len, int flags)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3
    cg_emit_mov_reg_imm64(cg, REG_RAX, 318); // sys_getrandom
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_setrlimit") == 0) {
    // int setrlimit(int res, void* lim)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_imm64(cg, REG_RAX, 160); // sys_setrlimit
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_getrlimit") == 0) {
    // int getrlimit(int res, void* lim)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_imm64(cg, REG_RAX, 97); // sys_getrlimit
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_nanosleep") == 0) {
    // int nanosleep(void* req, void* rem)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_imm64(cg, REG_RAX, 35); // sys_nanosleep
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_clock_gettime") == 0) {
    // int clock_gettime(int clk, void* tp)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_imm64(cg, REG_RAX, 228); // sys_clock_gettime
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_sigprocmask") == 0) {
    // int sigprocmask(int how, void* s, void* o, int sz)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3
    cg_emit_mov_reg_mem(cg, REG_R10, REG_RBP, 40); // arg4
    cg_emit_mov_reg_imm64(cg, REG_RAX, 14); // sys_sigprocmask
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_symlink") == 0) {
    // int symlink(char* t, char* l)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_imm64(cg, REG_RAX, 88); // sys_symlink
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_chmod") == 0) {
    // int chmod(char* p, int mode)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_imm64(cg, REG_RAX, 90); // sys_chmod
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_fchmod") == 0) {
    // int fchmod(int fd, int mode)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_imm64(cg, REG_RAX, 91); // sys_fchmod
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_chown") == 0) {
    // int chown(char* p, int o, int g)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3
    cg_emit_mov_reg_imm64(cg, REG_RAX, 92); // sys_chown
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_fchown") == 0) {
    // int fchown(int fd, int o, int g)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3
    cg_emit_mov_reg_imm64(cg, REG_RAX, 93); // sys_fchown
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_lchown") == 0) {
    // int lchown(char* p, int o, int g)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3
    cg_emit_mov_reg_imm64(cg, REG_RAX, 94); // sys_lchown
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_mknod") == 0) {
    // int mknod(char* p, int mode, int dev)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3
    cg_emit_mov_reg_imm64(cg, REG_RAX, 133); // sys_mknod
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_statvfs") == 0) {
    // int statvfs(char* p, void* buf)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_imm64(cg, REG_RAX, 137); // sys_statvfs
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_swapon") == 0) {
    // int swapon(char* p, int flags)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_imm64(cg, REG_RAX, 107); // sys_swapon
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_swapoff") == 0) {
    // int swapoff(char* p)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_imm64(cg, REG_RAX, 166); // sys_swapoff
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_socket") == 0) {
    // int socket(int dom, int type, int proto)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3
    cg_emit_mov_reg_imm64(cg, REG_RAX, 41); // sys_socket
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_connect") == 0) {
    // int connect(int fd, void* a, int len)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3
    cg_emit_mov_reg_imm64(cg, REG_RAX, 42); // sys_connect
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_bind") == 0) {
    // int bind(int fd, void* a, int len)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3
    cg_emit_mov_reg_imm64(cg, REG_RAX, 49); // sys_bind
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_listen") == 0) {
    // int listen(int fd, int backlog)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_imm64(cg, REG_RAX, 50); // sys_listen
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_accept") == 0) {
    // int accept(int fd, void* a, int len)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3
    cg_emit_mov_reg_imm64(cg, REG_RAX, 43); // sys_accept
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_shutdown") == 0) {
    // int shutdown(int fd, int how)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_imm64(cg, REG_RAX, 48); // sys_shutdown
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_send") == 0) {
    // ssize_t send(int fd, void* b, int l, int f)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3
    cg_emit_mov_reg_imm64(cg, REG_R10, 0); // flags = 0
    cg_emit_mov_reg_imm64(cg, REG_RCX, 0); // dest_addr = NULL
    cg_emit_mov_reg_imm64(cg, REG_R8, 0); // addrlen = NULL
    cg_emit_mov_reg_imm64(cg, REG_RAX, 44); // sys_send
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_recv") == 0) {
    // ssize_t recv(int fd, void* b, int l, int f)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3
    cg_emit_mov_reg_imm64(cg, REG_R10, 0); // flags = 0
    cg_emit_mov_reg_imm64(cg, REG_RCX, 0); // src_addr = NULL
    cg_emit_mov_reg_imm64(cg, REG_R8, 0); // addrlen = NULL
    cg_emit_mov_reg_imm64(cg, REG_RAX, 45); // sys_recv
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_setsockopt") == 0) {
    // int setsockopt(int fd,int lv,int n,void* v,int l)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3
    cg_emit_mov_reg_mem(cg, REG_R10, REG_RBP, 40); // arg4
    cg_emit_mov_reg_mem(cg, REG_R8, REG_RBP, 48); // arg5
    cg_emit_mov_reg_imm64(cg, REG_RAX, 54); // sys_setsockopt
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_poll") == 0) {
        // int poll(void* fds, int nfds, int timeout)
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3
        cg_emit_mov_reg_imm64(cg, REG_RAX, 7); // sys_poll
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_sendto") == 0) {
        // int sendto(int fd, char* buf, int len, int flags, void* dst, int dlen)
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3
        cg_emit_mov_reg_mem(cg, REG_R10, REG_RBP, 40); // arg4
        cg_emit_mov_reg_mem(cg, REG_R8, REG_RBP, 48); // arg5
        cg_emit_mov_reg_mem(cg, REG_R9, REG_RBP, 56); // arg6
        cg_emit_mov_reg_imm64(cg, REG_RAX, 44); // sys_sendto
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_recvfrom") == 0) {
        // int recvfrom(int fd, char* buf, int len, int flags, void* src, int slen)
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3
        cg_emit_mov_reg_mem(cg, REG_R10, REG_RBP, 40); // arg4
        cg_emit_mov_reg_mem(cg, REG_R8, REG_RBP, 48); // arg5
        cg_emit_mov_reg_mem(cg, REG_R9, REG_RBP, 56); // arg6
        cg_emit_mov_reg_imm64(cg, REG_RAX, 45); // sys_recvfrom
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_sendmsg") == 0) {
        // int sendmsg(int fd, void* msg, int flags)
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3
        cg_emit_mov_reg_imm64(cg, REG_RAX, 46); // sys_sendmsg
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_recvmsg") == 0) {
        // int recvmsg(int fd, void* msg, int flags)
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3
        cg_emit_mov_reg_imm64(cg, REG_RAX, 47); // sys_recvmsg
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_getsockname") == 0) {
        // int getsockname(int fd, void* addr, int len)
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3
        cg_emit_mov_reg_imm64(cg, REG_RAX, 51); // sys_getsockname
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_getpeername") == 0) {
        // int getpeername(int fd, void* addr, int len)
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3
        cg_emit_mov_reg_imm64(cg, REG_RAX, 52); // sys_getpeername
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_getsockopt") == 0) {
        // int getsockopt(int fd, int lvl, int name, void* val, int len)
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3
        cg_emit_mov_reg_mem(cg, REG_R10, REG_RBP, 40); // arg4
        cg_emit_mov_reg_mem(cg, REG_R8, REG_RBP, 48); // arg5
        cg_emit_mov_reg_imm64(cg, REG_RAX, 55); // sys_getsockopt
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_epoll_wait") == 0) {
        // int epoll_wait(int epfd, void* evs, int maxev, int timeout)
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3
        cg_emit_mov_reg_mem(cg, REG_R10, REG_RBP, 40); // arg4
        cg_emit_mov_reg_imm64(cg, REG_RAX, 232); // sys_epoll_wait
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_epoll_ctl") == 0) {
        // int epoll_ctl(int epfd, int op, int fd, void* ev)
        cg_emit_push_reg(cg, REG_RBP);
        cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3
        cg_emit_mov_reg_mem(cg, REG_R10, REG_RBP, 40); // arg4
        cg_emit_mov_reg_imm64(cg, REG_RAX, 233); // sys_epoll_ctl
        cg_emit_syscall(cg);
        cg_emit_pop_reg(cg, REG_RBP);
        cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_socketpair") == 0) {
    // int socketpair(int d,int t,int p,int* sv)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3
    cg_emit_mov_reg_mem(cg, REG_R10, REG_RBP, 40); // arg4
    cg_emit_mov_reg_imm64(cg, REG_RAX, 53); // sys_socketpair
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_epoll_create1") == 0) {
    // int epoll_create1(int flags)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_imm64(cg, REG_RAX, 291); // sys_epoll_create1
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_eventfd") == 0) {
    // int eventfd(int val, int flags)
    // NOTE: x86_64 eventfd is 284 (eventfd2 is 290). The kernel's sys_eventfd
    // reads only arg1, so flags is loaded but ignored; kept for source
    // compatibility with callers that pass two arguments.
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2 (ignored by kernel)
    cg_emit_mov_reg_imm64(cg, REG_RAX, 284); // sys_eventfd
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_eventfd2") == 0) {
    // int eventfd2(int val, int flags)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1 = count
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2 = flags
    cg_emit_mov_reg_imm64(cg, REG_RAX, 290); // sys_eventfd2
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_timerfd_settime") == 0) {
    // int timerfd_settime(int fd, int flags, void* new, void* old)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16);  // arg1 = fd
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24);  // arg2 = flags
    cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32);  // arg3 = new_value
    cg_emit_mov_reg_mem(cg, REG_R10, REG_RBP, 40);  // arg4 = old_value
    cg_emit_mov_reg_imm64(cg, REG_RAX, 286); // sys_timerfd_settime
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_accept4") == 0) {
    // int accept4(int fd, void* addr, int* addrlen, int flags)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3
    cg_emit_mov_reg_mem(cg, REG_R10, REG_RBP, 40); // arg4
    cg_emit_mov_reg_imm64(cg, REG_RAX, 288); // sys_accept4
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_select") == 0) {
    // int select(int nfds, void* r, void* w, void* e, void* timeout)
    // x86_64 selects in place and returns the byte counts, matching FD_SETSIZE
    // 1024 bitmaps; prefer sys_ppoll/sys_pselect6 where possible.
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16);  // arg1 = nfds
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24);  // arg2 = readfds
    cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32);  // arg3 = writefds
    cg_emit_mov_reg_mem(cg, REG_R10, REG_RBP, 40);  // arg4 = exceptfds
    cg_emit_mov_reg_mem(cg, REG_R8,  REG_RBP, 48);  // arg5 = timeout
    cg_emit_mov_reg_imm64(cg, REG_RAX, 23); // sys_select
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_pselect6") == 0) {
    // int pselect6(int nfds, void* r, void* w, void* e, void* ts, void* sigmask)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1 = nfds
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2 = readfds
    cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3 = writefds
    cg_emit_mov_reg_mem(cg, REG_R10, REG_RBP, 40); // arg4 = exceptfds
    cg_emit_mov_reg_mem(cg, REG_R8,  REG_RBP, 48); // arg5 = timespec
    cg_emit_mov_reg_mem(cg, REG_R9,  REG_RBP, 56); // arg6 = sigmask
    cg_emit_mov_reg_imm64(cg, REG_RAX, 270); // sys_pselect6
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_ppoll") == 0) {
    // int ppoll(void* fds, int nfds, void* tmo, void* sigmask, int sigsz)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1 = fds
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2 = nfds
    cg_emit_mov_reg_mem(cg, REG_RDX, REG_RBP, 32); // arg3 = timeout
    cg_emit_mov_reg_mem(cg, REG_R10, REG_RBP, 40); // arg4 = sigmask
    cg_emit_mov_reg_mem(cg, REG_R8,  REG_RBP, 48); // arg5 = sigsetsize
    cg_emit_mov_reg_imm64(cg, REG_RAX, 271); // sys_ppoll
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_timerfd_create") == 0) {
    // int timerfd_create(int clk, int flags)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_mem(cg, REG_RSI, REG_RBP, 24); // arg2
    cg_emit_mov_reg_imm64(cg, REG_RAX, 283); // sys_timerfd_create
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }
    else if (strcmp(name, "sys_inotify_init1") == 0) {
    // int inotify_init1(int flags)
    cg_emit_push_reg(cg, REG_RBP);
    cg_emit_mov_reg_reg(cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(cg, REG_RDI, REG_RBP, 16); // arg1
    cg_emit_mov_reg_imm64(cg, REG_RAX, 294); // sys_inotify_init1
    cg_emit_syscall(cg);
    cg_emit_pop_reg(cg, REG_RBP);
    cg_emit_ret(cg);
    }


    *buf = (uint8_t*)malloc(cg->size);
    memcpy(*buf, cg->buffer, cg->size);
    *size = cg->size;
    cg_destroy(cg);
    return true;
}

static uint64_t x86_64_get_entry_point(void* state) {
    (void)state;
    return 0x400000 + 64 + 56;
}

Backend* backend_x86_64_get(void) {
    static Backend backend = {
        .name = "x86_64",
        .description = "x86-64 Linux native code generation",
        .create = x86_64_create,
        .destroy = x86_64_destroy,
        .generate = x86_64_generate,
        .set_entry = x86_64_set_entry,
        .set_format = x86_64_set_format,
        .write_executable = x86_64_write_executable,
        .write_object = x86_64_write_object,
        .generate_stub = x86_64_generate_stub,
        .get_entry_point = x86_64_get_entry_point
    };
    return &backend;
}
