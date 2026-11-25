#include "../backend.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void* riscv_create(void) { return NULL; }
static void riscv_destroy(void* state) { (void)state; }

static bool riscv_generate(void* state, IRProgram* ir, BackendResult* result, bool object_mode) {
    (void)state; (void)ir; (void)result; (void)object_mode;
    fprintf(stderr, "RISC-V backend not yet implemented\n");
    return false;
}

static bool riscv_write_executable(const char* path, BackendResult* result) {
    (void)path; (void)result;
    fprintf(stderr, "RISC-V backend not yet implemented\n");
    return false;
}

static bool riscv_write_object(const char* path, BackendResult* result) {
    (void)path; (void)result;
    fprintf(stderr, "RISC-V backend not yet implemented\n");
    return false;
}

static bool riscv_generate_stub(void* state, uint8_t** buf, size_t* size, const char* name) {
    (void)state; (void)buf; (void)size; (void)name;
    return false;
}

static uint64_t riscv_get_entry_point(void* state) {
    (void)state;
    return 0;
}

Backend* backend_riscv_get(void) {
    static Backend backend = {
        .name = "riscv",
        .description = "RISC-V 64 Linux (placeholder - not yet implemented)",
        .create = riscv_create,
        .destroy = riscv_destroy,
        .generate = riscv_generate,
        .write_executable = riscv_write_executable,
        .write_object = riscv_write_object,
        .generate_stub = riscv_generate_stub,
        .get_entry_point = riscv_get_entry_point
    };
    return &backend;
}
