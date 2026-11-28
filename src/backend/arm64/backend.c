/*
 * ARM64 (AArch64) backend adapter.
 *
 * The AST-to-machine-code generator lives in codegen.c and the raw AArch64
 * encoder in encoder.c.  This file only implements the generic Backend API
 * used by magc and mag.
 */
#include "backend.h"
#include "codegen.h"
#include "stubs.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { char* entry_name; } ArmState;

static void* arm_create(void) {
    ArmState* s = (ArmState*)malloc(sizeof(ArmState));
    if (s) s->entry_name = strdup("main");
    return s;
}

static void arm_destroy(void* state) {
    ArmState* s = (ArmState*)state;
    if (s) {
        free(s->entry_name);
        free(s);
    }
}

static void arm_set_entry(void* state, const char* name) {
    ArmState* s = (ArmState*)state;
    if (!s) return;
    free(s->entry_name);
    s->entry_name = strdup(name && *name ? name : "main");
}

static void arm_set_format(void* state, const char* format) {
    (void)state;
    (void)format;
}

static bool arm_generate(void* state, IRProgram* ir, BackendResult* result, bool object_mode) {
    (void)object_mode;
    ArmState* st = (ArmState*)state;
    const char* entry = st && st->entry_name ? st->entry_name : "main";

    ArmGen* gen = ArmGen_create(ir, entry, object_mode);
    bool ok = gen ? ArmGen_generate(gen, result) : false;
    ArmGen_destroy(gen);
    return ok;
}

static bool arm_write_executable(const char* path, BackendResult* result) {
    return ArmGen_write_elf(path, result);
}

static bool arm_write_object(const char* path, BackendResult* result) {
    FILE* f = fopen(path, "wb");
    if (!f) return false;

    /* MAG2 = MAGO with an explicit relocation type stored per patch.  x86_64
       keeps the legacy MAGO layout, so neither backend's object format is
       changed by this addition. */
    fwrite("MAG2", 1, 4, f);
    uint32_t n = (uint32_t)result->code_size;
    fwrite(&n, sizeof(n), 1, f);
    fwrite(result->code, 1, result->code_size, f);

    uint32_t ne = (uint32_t)result->num_exports;
    fwrite(&ne, sizeof(ne), 1, f);
    for (uint32_t i = 0; i < ne; i++) {
        uint32_t pos = result->exports[i].offset;
        uint32_t len = (uint32_t)strlen(result->exports[i].name);
        fwrite(&pos, sizeof(pos), 1, f);
        fwrite(&len, sizeof(len), 1, f);
        fwrite(result->exports[i].name, 1, len, f);
    }

    uint32_t np = (uint32_t)result->num_patches;
    fwrite(&np, sizeof(np), 1, f);
    for (uint32_t i = 0; i < np; i++) {
        uint32_t pos = result->patches[i].position;
        uint32_t type = result->patches[i].type;
        uint32_t len = (uint32_t)strlen(result->patches[i].name);
        fwrite(&pos, sizeof(pos), 1, f);
        fwrite(&type, sizeof(type), 1, f);
        fwrite(&len, sizeof(len), 1, f);
        fwrite(result->patches[i].name, 1, len, f);
    }

    fclose(f);
    return true;
}

static uint64_t arm_get_entry_point(void* state) {
    (void)state;
    return ArmGen_entry_point();
}

/* The linker calls this for every symbol that no object defines.  ARM64 now
   supports the same syscall/mock family as x86_64, using the same emitter as
   standalone compilation. */
static bool arm_generate_stub(void* state, uint8_t** buf, size_t* size,
                              const char* name) {
    (void)state;
    if (!buf || !size || !name) return false;
    A64Buf code;
    a64_init(&code, 256);
    if (!arm_emit_stub(&code, name)) {
        a64_free(&code);
        return false;
    }
    *buf = code.data;
    *size = code.len;
    return true;
}

Backend* backend_arm64_get(void) {
    static Backend backend = {
        .name = "arm64",
        .description = "AArch64 native machine-code generation (no external tools)",
        .create = arm_create,
        .destroy = arm_destroy,
        .generate = arm_generate,
        .set_entry = arm_set_entry,
        .set_format = arm_set_format,
        .write_executable = arm_write_executable,
        .write_object = arm_write_object,
        .generate_stub = arm_generate_stub,
        .get_entry_point = arm_get_entry_point
    };
    return &backend;
}
