#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include "backend/backend.h"
#include "backend/elf_writer.h"
#include "backend/x86_64/encoder.h"

void ensure_space(CodeGen* cg, size_t extra);

// Use ExportSymbol and ImportPatch from backend.h

typedef struct {
    uint8_t* code;
    uint32_t code_size;
    ExportSymbol* exports;
    uint32_t num_exports;
    ImportPatch* patches;
    uint32_t num_patches;
} ObjectFile;

typedef struct {
    char* name;
    uint32_t global_offset;
} GlobalSymbol;

static void free_object_file(ObjectFile* obj) {
    if (!obj) return;
    free(obj->code);
    for (uint32_t i = 0; i < obj->num_exports; i++) {
        free(obj->exports[i].name);
    }
    free(obj->exports);
    for (uint32_t i = 0; i < obj->num_patches; i++) {
        free(obj->patches[i].name);
    }
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
    if (fread(magic, 1, 4, f) != 4 || memcmp(magic, "MAGO", 4) != 0) {
        fprintf(stderr, "Linker Error: Invalid object file '%s' (bad magic)\n", path);
        fclose(f);
        return NULL;
    }
    
    ObjectFile* obj = (ObjectFile*)malloc(sizeof(ObjectFile));
    memset(obj, 0, sizeof(ObjectFile));
    
#define MAG_MAX_CODE_SIZE    (256u * 1024u * 1024u)
#define MAG_MAX_ENTRIES      (1u << 20)
#define MAG_MAX_NAME_LEN     65535u

    if (fread(&obj->code_size, sizeof(uint32_t), 1, f) != 1) goto fail;
    if (obj->code_size > MAG_MAX_CODE_SIZE) goto fail;
    obj->code = (uint8_t*)malloc(obj->code_size);
    if (fread(obj->code, 1, obj->code_size, f) != obj->code_size) goto fail;
    
    if (fread(&obj->num_exports, sizeof(uint32_t), 1, f) != 1) goto fail;
    if (obj->num_exports > MAG_MAX_ENTRIES) goto fail;
    obj->exports = (ExportSymbol*)malloc(sizeof(ExportSymbol) * obj->num_exports);
    for (uint32_t i = 0; i < obj->num_exports; i++) {
        if (fread(&obj->exports[i].offset, sizeof(uint32_t), 1, f) != 1) goto fail;
        uint32_t name_len;
        if (fread(&name_len, sizeof(uint32_t), 1, f) != 1) goto fail;
        if (name_len > MAG_MAX_NAME_LEN) goto fail;
        obj->exports[i].name = (char*)malloc(name_len + 1);
        if (fread(obj->exports[i].name, 1, name_len, f) != name_len) goto fail;
        obj->exports[i].name[name_len] = '\0';
    }
    
    if (fread(&obj->num_patches, sizeof(uint32_t), 1, f) != 1) goto fail;
    if (obj->num_patches > MAG_MAX_ENTRIES) goto fail;
    obj->patches = (ImportPatch*)malloc(sizeof(ImportPatch) * obj->num_patches);
    for (uint32_t i = 0; i < obj->num_patches; i++) {
        if (fread(&obj->patches[i].position, sizeof(uint32_t), 1, f) != 1) goto fail;
        uint32_t name_len;
        if (fread(&name_len, sizeof(uint32_t), 1, f) != 1) goto fail;
        if (name_len > MAG_MAX_NAME_LEN) goto fail;
        obj->patches[i].name = (char*)malloc(name_len + 1);
        if (fread(obj->patches[i].name, 1, name_len, f) != name_len) goto fail;
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

int main(int argc, char** argv) {
    if (argc < 2) {
        printf("Magnetar Linker v3.5 (mag)\n");
        printf("Usage: %s <obj1.o> <obj2.o> ... [-o output] [--target arch] [--kernel]\n", argv[0]);
        printf("Targets: x86_64 (default)\n");
        printf("Flags:   --kernel  OS kernel mode (no startup prefix, no main required)\n");
        return 1;
    }
    
    backend_init_all();
    const char* target_arch = "x86_64";
    const char* output_name = "a.out";
    bool kernel_mode = false;
    int max_files = argc;
    ObjectFile** files = (ObjectFile**)malloc(sizeof(ObjectFile*) * max_files);
    int num_files = 0;
    
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-o") == 0) {
            if (i + 1 < argc) {
                output_name = argv[i + 1];
                i++;
            }
        } else if (strcmp(argv[i], "--target") == 0 && i + 1 < argc) {
            target_arch = argv[i + 1];
            i++;
        } else if (strncmp(argv[i], "--target=", 9) == 0) {
            target_arch = argv[i] + 9;
        } else if (strcmp(argv[i], "--target") == 0 && i + 1 >= argc) {
            fprintf(stderr, "Linker Error: --target requires an argument (x86_64)\n");
            free(files);
            return 1;
        } else if (strcmp(argv[i], "--format") == 0 || strncmp(argv[i], "--format=", 9) == 0) {
            const char* fmt = (strcmp(argv[i], "--format") == 0) ? (i + 1 < argc ? argv[i + 1] : "") : (argv[i] + 9);
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
    
    Backend* backend = backend_get(target_arch);
    if (!backend) {
        fprintf(stderr, "Linker Error: Backend '%s' not found\n", target_arch);
        for (int i = 0; i < num_files; i++) free_object_file(files[i]);
        free(files);
        return 1;
    }
    
    void* bstate = backend->create();
    CodeGen* cg = cg_create(65536);
    
    size_t call_main_pos = 0;
    if (!kernel_mode) {
        // Prepend startup/entry code
        cg_emit_byte(cg, 0xE8);
        call_main_pos = cg_get_size(cg);
        cg_emit_byte(cg, 0); cg_emit_byte(cg, 0); cg_emit_byte(cg, 0); cg_emit_byte(cg, 0);
        cg_emit_mov_reg_imm64(cg, REG_RAX, 60);
        cg_emit_xor_reg_reg(cg, REG_RDI, REG_RDI);
        cg_emit_syscall(cg);
    }
    
    // Append code of each object file
    uint32_t* base_offsets = (uint32_t*)malloc(sizeof(uint32_t) * num_files);
    for (int i = 0; i < num_files; i++) {
        base_offsets[i] = (uint32_t)cg_get_size(cg);
        ensure_space(cg, files[i]->code_size);
        memcpy(cg->buffer + base_offsets[i], files[i]->code, files[i]->code_size);
        cg->size += files[i]->code_size;
    }
    
    // Build global symbol table
    int max_symbols = 65536;
    GlobalSymbol* syms = (GlobalSymbol*)malloc(sizeof(GlobalSymbol) * max_symbols);
    int num_syms = 0;
    
    for (int i = 0; i < num_files; i++) {
        ObjectFile* obj = files[i];
        uint32_t base = base_offsets[i];
        for (uint32_t j = 0; j < obj->num_exports; j++) {
            ExportSymbol* exp = &obj->exports[j];
            for (int k = 0; k < num_syms; k++) {
                if (strcmp(syms[k].name, exp->name) == 0) {
                    fprintf(stderr, "Linker Error: Duplicate symbol '%s'\n", exp->name);
                    for (int n = 0; n < num_files; n++) free_object_file(files[n]);
                    free(files); free(base_offsets);
                    for (int n = 0; n < num_syms; n++) free(syms[n].name);
                    free(syms); cg_destroy(cg); backend->destroy(bstate);
                    return 1;
                }
            }
            if (num_syms >= max_symbols) {
                fprintf(stderr, "Linker Error: Exceeded maximum symbols limit.\n");
                for (int n = 0; n < num_files; n++) free_object_file(files[n]);
                free(files); free(base_offsets);
                for (int n = 0; n < num_syms; n++) free(syms[n].name);
                free(syms); cg_destroy(cg); backend->destroy(bstate);
                return 1;
            }
            syms[num_syms].name = strdup(exp->name);
            syms[num_syms].global_offset = base + exp->offset;
            num_syms++;
        }
    }
    
    // Resolve patches using backend for stub generation
    for (int i = 0; i < num_files; i++) {
        ObjectFile* obj = files[i];
        uint32_t base = base_offsets[i];
        for (uint32_t j = 0; j < obj->num_patches; j++) {
            ImportPatch* patch = &obj->patches[j];
            uint32_t global_patch_pos = base + patch->position;
            
            int found_idx = -1;
            for (int k = 0; k < num_syms; k++) {
                if (strcmp(syms[k].name, patch->name) == 0) {
                    found_idx = k;
                    break;
                }
            }
            
            uint32_t target_offset = 0;
            if (found_idx != -1) {
                target_offset = syms[found_idx].global_offset;
            } else {
                uint32_t stub_offset = (uint32_t)cg_get_size(cg);
                uint8_t* stub_buf = NULL;
                size_t stub_size = 0;
                if (backend->generate_stub(bstate, &stub_buf, &stub_size, patch->name)) {
                    ensure_space(cg, stub_size);
                    memcpy(cg->buffer + stub_offset, stub_buf, stub_size);
                    cg->size += stub_size;
                    free(stub_buf);
                    
                    syms[num_syms].name = strdup(patch->name);
                    syms[num_syms].global_offset = stub_offset;
                    target_offset = stub_offset;
                    if (num_syms + 1 >= max_symbols) {
                        fprintf(stderr, "Linker Error: Exceeded maximum symbols limit during stub generation.\n");
                        for (int n = 0; n < num_files; n++) free_object_file(files[n]);
                        free(files); free(base_offsets);
                        for (int n = 0; n < num_syms + 1; n++) free(syms[n].name);
                        free(syms); cg_destroy(cg); backend->destroy(bstate);
                        return 1;
                    }
                    num_syms++;
                } else {
                    fprintf(stderr, "Linker Error: Unresolved external symbol '%s'\n", patch->name);
                    for (int n = 0; n < num_files; n++) free_object_file(files[n]);
                    free(files); free(base_offsets);
                    for (int n = 0; n < num_syms; n++) free(syms[n].name);
                    free(syms); cg_destroy(cg); backend->destroy(bstate);
                    return 1;
                }
            }
            
            // Resolve 32-bit PC-relative displacement
            int32_t displacement = (int32_t)(target_offset - (global_patch_pos + 4));
            cg->buffer[global_patch_pos] = displacement & 0xFF;
            cg->buffer[global_patch_pos + 1] = (displacement >> 8) & 0xFF;
            cg->buffer[global_patch_pos + 2] = (displacement >> 16) & 0xFF;
            cg->buffer[global_patch_pos + 3] = (displacement >> 24) & 0xFF;
        }
    }
    
    // Resolve entry point (main) — skipped in kernel mode
    int main_idx = -1;
    for (int k = 0; k < num_syms; k++) {
        if (strcmp(syms[k].name, "main") == 0) {
            main_idx = k;
            break;
        }
    }
    
    if (!kernel_mode) {
        if (main_idx == -1) {
            fprintf(stderr, "Linker Error: Entry point 'main' not defined.\n");
            for (int n = 0; n < num_files; n++) free_object_file(files[n]);
            free(files); free(base_offsets);
            for (int n = 0; n < num_syms; n++) free(syms[n].name);
            free(syms); cg_destroy(cg); backend->destroy(bstate);
            return 1;
        }
        
        uint32_t main_offset = syms[main_idx].global_offset;
        int32_t main_disp = (int32_t)(main_offset - (call_main_pos + 4));
        cg->buffer[call_main_pos] = main_disp & 0xFF;
        cg->buffer[call_main_pos + 1] = (main_disp >> 8) & 0xFF;
        cg->buffer[call_main_pos + 2] = (main_disp >> 16) & 0xFF;
        cg->buffer[call_main_pos + 3] = (main_disp >> 24) & 0xFF;
    }
    
    // Build and write executable using backend
    printf("[Linker] Creating ELF executable '%s' from %d object files...\n", output_name, num_files);
    
    BackendResult result;
    backend_result_init(&result);
    result.code = (uint8_t*)malloc(cg->size);
    memcpy(result.code, cg->buffer, cg->size);
    result.code_size = cg->size;
    
    bool ok = backend->write_executable(output_name, &result);
    if (ok) {
        printf("[Linker] Success! Created '%s' (%zu bytes)\n", output_name, result.code_size);
    } else {
        fprintf(stderr, "[Linker] Failed to write '%s'\n", output_name);
    }
    
    backend_result_free(&result);
    cg_destroy(cg);
    for (int i = 0; i < num_files; i++) free_object_file(files[i]);
    free(files);
    free(base_offsets);
    for (int i = 0; i < num_syms; i++) free(syms[i].name);
    free(syms);
    backend->destroy(bstate);
    
    return ok ? 0 : 1;
}

