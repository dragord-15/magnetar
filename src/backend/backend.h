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

/* Relocation kinds used by MAGO object files.  x86_64 objects use the legacy
   fixed PC-relative type 0; ARM64 objects use the typed MAG2 format. */
typedef enum {
    MAG_PATCH_X86_PC32          = 0,
    MAG_PATCH_AARCH64_ABS64     = 1,
    MAG_PATCH_AARCH64_ABS32     = 2,
    MAG_PATCH_AARCH64_PREL32    = 3,
    MAG_PATCH_AARCH64_PREL64    = 4,
    MAG_PATCH_AARCH64_CALL26    = 5,
    MAG_PATCH_AARCH64_JUMP26    = 6,
    MAG_PATCH_AARCH64_ADRP_ADD  = 7,
    MAG_PATCH_AARCH64_CONDBR19  = 8,
    MAG_PATCH_AARCH64_TSTBR14   = 9,
    MAG_PATCH_AARCH64_LDST8_ABS_LO12_NC  = 10,
    MAG_PATCH_AARCH64_LDST16_ABS_LO12_NC = 11,
    MAG_PATCH_AARCH64_LDST32_ABS_LO12_NC = 12,
    MAG_PATCH_AARCH64_LDST64_ABS_LO12_NC = 13,
    /* Like ABS64, but patches an eight-byte raw pointer in the data image
       instead of a four-instruction movz/movk sequence in code. */
    MAG_PATCH_AARCH64_ABS64_RAW = 14
} MagPatchType;

typedef struct {
    char* name;
    uint32_t position;
    uint32_t type;
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
