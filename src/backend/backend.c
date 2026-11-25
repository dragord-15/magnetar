#include "backend.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_BACKENDS 8

static Backend* backends[MAX_BACKENDS];
static int backend_count = 0;

extern Backend* backend_x86_64_get(void);
extern Backend* backend_arm64_get(void);
extern Backend* backend_riscv_get(void);

void backend_register(Backend* backend) {
    if (backend_count < MAX_BACKENDS) {
        backends[backend_count++] = backend;
    }
}

Backend* backend_get(const char* name) {
    for (int i = 0; i < backend_count; i++) {
        if (strcmp(backends[i]->name, name) == 0) {
            return backends[i];
        }
    }
    return NULL;
}

Backend* backend_get_default(void) {
    if (backend_count > 0) return backends[0];
    return NULL;
}

void backend_init_all(void) {
    Backend* x86 = backend_x86_64_get();
    if (x86) backend_register(x86);
    Backend* arm = backend_arm64_get();
    if (arm) backend_register(arm);
    Backend* rv = backend_riscv_get();
    if (rv) backend_register(rv);
}

void backend_list_all(void) {
    printf("Available backends:\n");
    for (int i = 0; i < backend_count; i++) {
        printf("  %s - %s\n", backends[i]->name, backends[i]->description);
    }
}

void backend_result_init(BackendResult* result) {
    result->code = NULL;
    result->code_size = 0;
    result->rodata = NULL;
    result->rodata_size = 0;
    result->num_exports = 0;
    result->patches = NULL;
    result->num_patches = 0;
}

void backend_result_free(BackendResult* result) {
    free(result->code);
    free(result->rodata);
    for (int i = 0; i < result->num_exports; i++) {
        free(result->exports[i].name);
    }
    if (result->patches) {
        for (int i = 0; i < result->num_patches; i++) {
            free(result->patches[i].name);
        }
        free(result->patches);
    }
}
