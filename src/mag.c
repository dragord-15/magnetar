#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include "backend/backend.h"
#include "backend/elf_writer.h"
#include "backend/x86_64/encoder.h"
#include "backend/arm64/encoder.h"

void ensure_space(CodeGen* cg, size_t extra);

#define MAG_ELF_BASE 0x400000ULL
#define MAG_IMAGE_HEADERS 120ULL   /* ELF header (64) + one program header (56) */
#define MAG_HEAP_BASE 0x500000ULL

typedef struct {
    char* path;
    uint8_t* code;
    uint32_t code_size;
    ExportSymbol* exports;
    uint32_t num_exports;
    ImportPatch* patches;
    uint32_t num_patches;
    bool typed;              /* MAG2 (typed ARM64 patches) vs MAGO (x86_64) */
} ObjectFile;

typedef struct {
    char* name;
    uint32_t global_offset;
} GlobalSymbol;

static void free_object_file(ObjectFile* obj) {
    if (!obj) return;
    free(obj->path);
    free(obj->code);
    for (uint32_t i = 0; i < obj->num_exports; i++) free(obj->exports[i].name);
    free(obj->exports);
    for (uint32_t i = 0; i < obj->num_patches; i++) free(obj->patches[i].name);
    free(obj->patches);
    free(obj);
}

static ObjectFile* read_object_file(const char* path) {
    FILE* f = fopen(path, "rb");
    if (!f) {
        fprintf(stderr, "Linker Error: Cannot open object file '%s'\n", path);
        return NULL;
    }

    char magic[4];
    if (fread(magic, 1, 4, f) != 4) {
        fprintf(stderr, "Linker Error: Invalid object file '%s' (short magic)\n", path);
        fclose(f);
        return NULL;
    }

    /* MAGO: legacy x86_64 objects (untyped PC-relative patches).
       MAG2: typed patches, used by the ARM64 backend. */
    bool typed = false;
    if (memcmp(magic, "MAGO", 4) == 0) typed = false;
    else if (memcmp(magic, "MAG2", 4) == 0) typed = true;
    else {
        fprintf(stderr, "Linker Error: Invalid object file '%s' (bad magic)\n", path);
        fclose(f);
        return NULL;
    }

#define MAG_MAX_CODE_SIZE    (256u * 1024u * 1024u)
#define MAG_MAX_ENTRIES      (1u << 20)
#define MAG_MAX_NAME_LEN     65535u

    ObjectFile* obj = (ObjectFile*)calloc(1, sizeof(ObjectFile));
    if (!obj) { fclose(f); return NULL; }
    obj->path = strdup(path);
    obj->typed = typed;

    if (fread(&obj->code_size, sizeof(uint32_t), 1, f) != 1) goto fail;
    if (obj->code_size > MAG_MAX_CODE_SIZE) goto fail;
    obj->code = (uint8_t*)malloc(obj->code_size ? obj->code_size : 1);
    if (!obj->code) goto fail;
    if (obj->code_size && fread(obj->code, 1, obj->code_size, f) != obj->code_size) goto fail;

    if (fread(&obj->num_exports, sizeof(uint32_t), 1, f) != 1) goto fail;
    if (obj->num_exports > MAG_MAX_ENTRIES) goto fail;
    obj->exports = (ExportSymbol*)calloc(obj->num_exports ? obj->num_exports : 1,
                                         sizeof(ExportSymbol));
    if (!obj->exports) goto fail;
    for (uint32_t i = 0; i < obj->num_exports; i++) {
        if (fread(&obj->exports[i].offset, sizeof(uint32_t), 1, f) != 1) goto fail;
        uint32_t name_len;
        if (fread(&name_len, sizeof(uint32_t), 1, f) != 1) goto fail;
        if (name_len > MAG_MAX_NAME_LEN) goto fail;
        obj->exports[i].name = (char*)malloc(name_len + 1);
        if (!obj->exports[i].name) goto fail;
        if (name_len && fread(obj->exports[i].name, 1, name_len, f) != name_len) goto fail;
        obj->exports[i].name[name_len] = '\0';
    }

    if (fread(&obj->num_patches, sizeof(uint32_t), 1, f) != 1) goto fail;
    if (obj->num_patches > MAG_MAX_ENTRIES) goto fail;
    obj->patches = (ImportPatch*)calloc(obj->num_patches ? obj->num_patches : 1,
                                        sizeof(ImportPatch));
    if (!obj->patches) goto fail;
    for (uint32_t i = 0; i < obj->num_patches; i++) {
        if (fread(&obj->patches[i].position, sizeof(uint32_t), 1, f) != 1) goto fail;
        if (typed) {
            if (fread(&obj->patches[i].type, sizeof(uint32_t), 1, f) != 1) goto fail;
        } else {
            obj->patches[i].type = MAG_PATCH_X86_PC32;
        }
        uint32_t name_len;
        if (fread(&name_len, sizeof(uint32_t), 1, f) != 1) goto fail;
        if (name_len > MAG_MAX_NAME_LEN) goto fail;
        obj->patches[i].name = (char*)malloc(name_len + 1);
        if (!obj->patches[i].name) goto fail;
        if (name_len && fread(obj->patches[i].name, 1, name_len, f) != name_len) goto fail;
        obj->patches[i].name[name_len] = '\0';
    }

#undef MAG_MAX_CODE_SIZE
#undef MAG_MAX_ENTRIES
#undef MAG_MAX_NAME_LEN

    fclose(f);
    return obj;

fail:
    fprintf(stderr, "Linker Error: Corrupted object file '%s'\n", path);
    fclose(f);
    free_object_file(obj);
    return NULL;
}

static void put_le32(uint8_t* p, uint32_t v) {
    p[0] = (uint8_t)(v & 0xFF);
    p[1] = (uint8_t)((v >> 8) & 0xFF);
    p[2] = (uint8_t)((v >> 16) & 0xFF);
    p[3] = (uint8_t)((v >> 24) & 0xFF);
}

static bool patch_arm(uint8_t* code, uint32_t type, size_t pos, uint32_t target_off) {
    switch (type) {
    case MAG_PATCH_AARCH64_CALL26:
    case MAG_PATCH_AARCH64_JUMP26:
        a64_patch_branch(code, pos, target_off);
        return true;
    case MAG_PATCH_AARCH64_ABS64:
        a64_patch_mov64(code, pos, MAG_ELF_BASE + MAG_IMAGE_HEADERS + target_off);
        return true;
    case MAG_PATCH_AARCH64_ABS64_RAW: {
        uint64_t v = (uint64_t)(MAG_ELF_BASE + MAG_IMAGE_HEADERS + target_off);
        for (int i = 0; i < 8; i++) code[pos + (size_t)i] = (uint8_t)(v >> (i * 8));
        return true;
    }
    case MAG_PATCH_AARCH64_ADRP_ADD:
        a64_patch_adrp_add(code, pos,
                           MAG_ELF_BASE + MAG_IMAGE_HEADERS + pos,
                           MAG_ELF_BASE + MAG_IMAGE_HEADERS + target_off);
        return true;
    case MAG_PATCH_AARCH64_CONDBR19:
        a64_patch_cond(code, pos, target_off);
        return true;
    case MAG_PATCH_AARCH64_TSTBR14:
        a64_patch_tstbr14(code, pos, target_off);
        return true;
    case MAG_PATCH_AARCH64_ABS32:
        put_le32(code + pos, (uint32_t)(MAG_ELF_BASE + MAG_IMAGE_HEADERS + target_off));
        return true;
    case MAG_PATCH_AARCH64_PREL32:
        put_le32(code + pos, (uint32_t)((int64_t)target_off - (int64_t)pos));
        return true;
    case MAG_PATCH_AARCH64_PREL64: {
        uint64_t v = (uint64_t)((int64_t)target_off - (int64_t)pos);
        for (int i = 0; i < 8; i++) code[pos + (size_t)i] = (uint8_t)(v >> (i * 8));
        return true;
    }
    case MAG_PATCH_AARCH64_LDST8_ABS_LO12_NC:
    case MAG_PATCH_AARCH64_LDST16_ABS_LO12_NC:
    case MAG_PATCH_AARCH64_LDST32_ABS_LO12_NC:
    case MAG_PATCH_AARCH64_LDST64_ABS_LO12_NC:
        a64_patch_lo12(code, pos, MAG_ELF_BASE + MAG_IMAGE_HEADERS + target_off);
        return true;
    default:
        fprintf(stderr, "Linker Error: unsupported ARM64 relocation type %u\n", type);
        return false;
    }
}

int main(int argc, char** argv) {
    if (argc < 2) {
        printf("Magnetar Linker v3.5 (mag)\n");
        printf("Usage: %s <obj1.o> <obj2.o> ... [-o output] [--target arch] [--kernel]\n", argv[0]);
        printf("Targets: x86_64 (default), arm64/aarch64\n");
        printf("Flags:   --kernel  OS kernel mode (no startup prefix, no main required)\n");
        return 1;
    }

    backend_init_all();
    const char* target_arch = "x86_64";
    const char* output_name = "a.out";
    bool kernel_mode = false;
    int max_files = argc;
    ObjectFile** files = (ObjectFile**)malloc(sizeof(ObjectFile*) * (size_t)max_files);
    int num_files = 0;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-o") == 0) {
            if (i + 1 < argc) { output_name = argv[i + 1]; i++; }
        } else if (strcmp(argv[i], "--target") == 0 && i + 1 < argc) {
            target_arch = argv[i + 1];
            i++;
        } else if (strncmp(argv[i], "--target=", 9) == 0) {
            target_arch = argv[i] + 9;
        } else if (strcmp(argv[i], "--target") == 0 && i + 1 >= argc) {
            fprintf(stderr, "Linker Error: --target requires an argument (x86_64, arm64)\n");
            free(files);
            return 1;
        } else if (strcmp(argv[i], "--format") == 0 || strncmp(argv[i], "--format=", 9) == 0) {
            const char* fmt = (strcmp(argv[i], "--format") == 0)
                ? (i + 1 < argc ? argv[i + 1] : "") : (argv[i] + 9);
            fprintf(stderr, "Linker Error: --format has no effect. Only ELF output is supported (got '%s').\n", fmt);
            free(files);
            return 1;
        } else if (strcmp(argv[i], "--kernel") == 0) {
            kernel_mode = true;
        } else if (strncmp(argv[i], "--", 2) == 0) {
            fprintf(stderr, "Linker Error: Unknown option '%s'\n", argv[i]);
            free(files);
            return 1;
        } else {
            ObjectFile* obj = read_object_file(argv[i]);
            if (!obj) {
                for (int j = 0; j < num_files; j++) free_object_file(files[j]);
                free(files);
                return 1;
            }
            files[num_files++] = obj;
        }
    }

    if (num_files == 0) {
        fprintf(stderr, "Linker Error: No input object files specified.\n");
        free(files);
        return 1;
    }

    if (strcmp(target_arch, "aarch64") == 0) target_arch = "arm64";

    Backend* backend = backend_get(target_arch);
    if (!backend) {
        fprintf(stderr, "Linker Error: Backend '%s' not found\n", target_arch);
        for (int i = 0; i < num_files; i++) free_object_file(files[i]);
        free(files);
        return 1;
    }
    if (strcmp(target_arch, "x86_64") != 0 && strcmp(target_arch, "arm64") != 0) {
        fprintf(stderr, "Linker Error: object linking is only implemented for x86_64 and arm64 (got '%s').\n",
                target_arch);
        for (int i = 0; i < num_files; i++) free_object_file(files[i]);
        free(files);
        return 1;
    }
    bool arm = strcmp(target_arch, "arm64") == 0;
    for (int i = 0; i < num_files; i++) {
        if (files[i]->typed != arm) {
            fprintf(stderr,
                    "Linker Error: object '%s' was built for %s but --target %s was selected.\n",
                    files[i]->path, files[i]->typed ? "arm64" : "x86_64", target_arch);
            for (int j = 0; j < num_files; j++) free_object_file(files[j]);
            free(files);
            return 1;
        }
    }

    void* bstate = backend->create();
    CodeGen* xcg = NULL;
    A64Buf abuf;
    bool ok = false;
    if (arm) a64_init(&abuf, 65536);
    else xcg = cg_create(65536);

    size_t call_main_pos = 0;
    if (!kernel_mode) {
        if (arm) {
            /* AAPCS64/Linux process entry: x0=argc, x1=argv, x2=envp.
               Align SP explicitly and preserve those registers for main. */
            a64_align_sp(&abuf);
            a64_mov_imm(&abuf, 28, MAG_HEAP_BASE);
            a64_mov_imm(&abuf, 27, 12345);
            call_main_pos = a64_bl(&abuf);
            a64_mov_imm(&abuf, 8, 94);          /* __NR_exit */
            a64_svc(&abuf);
        } else {
            cg_emit_byte(xcg, 0xE8);
            call_main_pos = cg_get_size(xcg);
            cg_emit_byte(xcg, 0); cg_emit_byte(xcg, 0);
            cg_emit_byte(xcg, 0); cg_emit_byte(xcg, 0);
            cg_emit_mov_reg_imm64(xcg, REG_RAX, 60);
            cg_emit_xor_reg_reg(xcg, REG_RDI, REG_RDI);
            cg_emit_syscall(xcg);
        }
    }

    uint32_t* base_offsets = (uint32_t*)malloc(sizeof(uint32_t) * (size_t)num_files);
    for (int i = 0; i < num_files; i++) {
        /* AArch64 instructions are 4-byte aligned, but MAG2 object payloads
           end with packed string data and are not necessarily a multiple of
           four bytes.  Pad before each object so its code labels stay aligned. */
        if (arm)
            while (a64_size(&abuf) % 4u) a64_emit_byte(&abuf, 0);
        size_t cur = arm ? a64_size(&abuf) : cg_get_size(xcg);
        base_offsets[i] = (uint32_t)cur;
        if (arm) {
            for (size_t j = 0; j < files[i]->code_size; j++)
                a64_emit_byte(&abuf, files[i]->code[j]);
        } else {
            ensure_space(xcg, files[i]->code_size);
            memcpy(xcg->buffer + cur, files[i]->code, files[i]->code_size);
            xcg->size += files[i]->code_size;
        }
    }

    int max_symbols = 65536;
    GlobalSymbol* syms = (GlobalSymbol*)malloc(sizeof(GlobalSymbol) * (size_t)max_symbols);
    int num_syms = 0;

    for (int i = 0; i < num_files; i++) {
        ObjectFile* obj = files[i];
        uint32_t base = base_offsets[i];
        for (uint32_t j = 0; j < obj->num_exports; j++) {
            ExportSymbol* exp = &obj->exports[j];
            for (int k = 0; k < num_syms; k++) {
                if (strcmp(syms[k].name, exp->name) == 0) {
                    fprintf(stderr, "Linker Error: Duplicate symbol '%s'\n", exp->name);
                    goto cleanup;
                }
            }
            if (num_syms >= max_symbols) {
                fprintf(stderr, "Linker Error: Exceeded maximum symbols limit.\n");
                goto cleanup;
            }
            syms[num_syms].name = strdup(exp->name);
            syms[num_syms].global_offset = base + exp->offset;
            num_syms++;
        }
    }

    for (int i = 0; i < num_files; i++) {
        ObjectFile* obj = files[i];
        uint32_t base = base_offsets[i];
        for (uint32_t j = 0; j < obj->num_patches; j++) {
            ImportPatch* patch = &obj->patches[j];
            size_t global_patch_pos = base + patch->position;

            int found_idx = -1;
            for (int k = 0; k < num_syms; k++) {
                if (strcmp(syms[k].name, patch->name) == 0) { found_idx = k; break; }
            }

            uint32_t target_offset = 0;
            if (found_idx != -1) {
                target_offset = syms[found_idx].global_offset;
            } else {
                uint32_t stub_offset = arm
                    ? 0 /* assigned after alignment below */
                    : (uint32_t)cg_get_size(xcg);
                uint8_t* stub_buf = NULL;
                size_t stub_size = 0;
                if (!backend->generate_stub ||
                    !backend->generate_stub(bstate, &stub_buf, &stub_size, patch->name)) {
                    fprintf(stderr, "Linker Error: Unresolved external symbol '%s'\n", patch->name);
                    goto cleanup;
                }
                if (arm) {
                    while (a64_size(&abuf) % 4u) a64_emit_byte(&abuf, 0);
                    /* Branches target the first instruction, so record the
                       aligned address rather than the pre-padding position. */
                    stub_offset = (uint32_t)a64_size(&abuf);
                    for (size_t b = 0; b < stub_size; b++) a64_emit_byte(&abuf, stub_buf[b]);
                    while (a64_size(&abuf) % 4u) a64_emit_byte(&abuf, 0);
                } else {
                    ensure_space(xcg, stub_size);
                    memcpy(xcg->buffer + stub_offset, stub_buf, stub_size);
                    xcg->size += stub_size;
                }
                free(stub_buf);
                if (num_syms >= max_symbols) {
                    fprintf(stderr, "Linker Error: Exceeded maximum symbols limit during stub generation.\n");
                    goto cleanup;
                }
                syms[num_syms].name = strdup(patch->name);
                syms[num_syms].global_offset = stub_offset;
                target_offset = stub_offset;
                num_syms++;
            }

            if (arm) {
                uint8_t* code = abuf.data;
                if (!patch_arm(code, patch->type, global_patch_pos, target_offset)) goto cleanup;
            } else {
                int32_t displacement = (int32_t)((int64_t)target_offset - ((int64_t)global_patch_pos + 4));
                put_le32(xcg->buffer + global_patch_pos, (uint32_t)displacement);
            }
        }
    }

    if (!kernel_mode) {
        int main_idx = -1;
        for (int k = 0; k < num_syms; k++) {
            if (strcmp(syms[k].name, "main") == 0) { main_idx = k; break; }
        }
        if (main_idx == -1) {
            fprintf(stderr, "Linker Error: Entry point 'main' not defined.\n");
            goto cleanup;
        }
        uint32_t main_offset = syms[main_idx].global_offset;
        if (arm) {
            a64_patch_branch(abuf.data, call_main_pos, main_offset);
        } else {
            int32_t main_disp = (int32_t)((int64_t)main_offset - ((int64_t)call_main_pos + 4));
            put_le32(xcg->buffer + call_main_pos, (uint32_t)main_disp);
        }
    }

    printf("[Linker] Creating ELF executable '%s' from %d object files...\n", output_name, num_files);
    size_t total = arm ? a64_size(&abuf) : cg_get_size(xcg);
    BackendResult result;
    backend_result_init(&result);
    result.code = (uint8_t*)malloc(total ? total : 1);
    if (arm) memcpy(result.code, abuf.data, total);
    else memcpy(result.code, xcg->buffer, total);
    result.code_size = total;

    ok = backend->write_executable(output_name, &result);
    if (ok) printf("[Linker] Success! Created '%s' (%zu bytes)\n", output_name, result.code_size);
    else fprintf(stderr, "[Linker] Failed to write '%s'\n", output_name);

    backend_result_free(&result);

cleanup:
    if (xcg) cg_destroy(xcg);
    if (arm) a64_free(&abuf);
    for (int i = 0; i < num_files; i++) free_object_file(files[i]);
    free(files);
    free(base_offsets);
    for (int i = 0; i < num_syms; i++) free(syms[i].name);
    free(syms);
    backend->destroy(bstate);

    return ok ? 0 : 1;
}
