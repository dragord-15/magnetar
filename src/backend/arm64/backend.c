#include "../backend.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void* arm64_create(void) { return NULL; }
static void arm64_destroy(void* state) { (void)state; }

static bool arm64_generate(void* state, IRProgram* ir, BackendResult* result, bool object_mode) {
    (void)state; (void)ir; (void)result; (void)object_mode;
    fprintf(stderr, "ARM64 backend not yet implemented\n");
    return false;
}

static bool arm64_write_executable(const char* path, BackendResult* result) {
    (void)path; (void)result;
    fprintf(stderr, "ARM64 backend not yet implemented\n");
    return false;
}

static bool arm64_write_object(const char* path, BackendResult* result) {
    (void)path; (void)result;
    fprintf(stderr, "ARM64 backend not yet implemented\n");
    return false;
}

static bool arm64_generate_stub(void* state, uint8_t** buf, size_t* size, const char* name) {
    (void)state; (void)buf; (void)size; (void)name;
    return false;
}

static uint64_t arm64_get_entry_point(void* state) {
    (void)state;
    return 0;
}

Backend* backend_arm64_get(void) {
    static Backend backend = {
        .name = "arm64",
        .description = "ARM64 Linux (placeholder - not yet implemented)",
        .create = arm64_create,
        .destroy = arm64_destroy,
        .generate = arm64_generate,
        .write_executable = arm64_write_executable,
        .write_object = arm64_write_object,
        .generate_stub = arm64_generate_stub,
        .get_entry_point = arm64_get_entry_point
    };
    return &backend;
}
