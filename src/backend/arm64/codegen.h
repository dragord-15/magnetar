#ifndef MAGNETAR_ARM64_CODEGEN_H
#define MAGNETAR_ARM64_CODEGEN_H

/* ARM64 AST -> machine-code generation.  The encoder lives in encoder.h and
 * the generic Backend API lives in backend.h.  ArmGen is opaque to callers:
 * only the functions below are part of the backend boundary. */

#include "../../backend/backend.h"
#include "../../ir/ir.h"
#include "encoder.h"
#include <stdbool.h>
#include <stdint.h>

typedef struct ArmGen ArmGen;

/* Prepare a generator for one compilation.  `entry_name` is copied. */
ArmGen* ArmGen_create(IRProgram* ir, const char* entry_name, bool object_mode);

/* Emit all functions, data and relocations into `result`.  Returns false when
 * the requested entry function was not found. */
bool ArmGen_generate(ArmGen* gen, BackendResult* result);

/* Release a generator.  Safe to call after a failed generation. */
void ArmGen_destroy(ArmGen* gen);

/* Standalone ELF64/AArch64 writer (ET_EXEC, EM_AARCH64). */
bool ArmGen_write_elf(const char* path, BackendResult* result);

/* Runtime virtual address of _start (ELF header + one program header). */
uint64_t ArmGen_entry_point(void);

#endif /* MAGNETAR_ARM64_CODEGEN_H */
