#ifndef MAGNETAR_BACKEND_H
#define MAGNETAR_BACKEND_H

#include "../ir/ir.h"
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define MAX_EXPORTS 256
#define MAX_IMPORTS 4096

typedef struct {
    char* name;
    uint32_t offset;
} ExportSymbol;

typedef struct {
    char* name;
    uint32_t position;
} ImportPatch;

typedef struct {
    uint8_t* code;
    size_t code_size;
    uint8_t* rodata;
    size_t rodata_size;
    ExportSymbol exports[MAX_EXPORTS];
    int num_exports;
    ImportPatch* patches;
    int num_patches;
} BackendResult;

typedef struct Backend {
    const char* name;
    const char* description;

    void* (*create)(void);
    void (*destroy)(void* state);

    bool (*generate)(void* state, IRProgram* ir, BackendResult* result, bool object_mode);
    void (*set_entry)(void* state, const char* name);
    void (*set_format)(void* state, const char* format);

    bool (*write_executable)(const char* path, BackendResult* result);
    bool (*write_object)(const char* path, BackendResult* result);

    bool (*generate_stub)(void* state, uint8_t** buf, size_t* size, const char* name);

    uint64_t (*get_entry_point)(void* state);
} Backend;

void backend_register(Backend* backend);
Backend* backend_get(const char* name);
Backend* backend_get_default(void);
void backend_init_all(void);
void backend_list_all(void);

void backend_result_init(BackendResult* result);
void backend_result_free(BackendResult* result);

#endif
