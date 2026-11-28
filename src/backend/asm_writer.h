#ifndef MAGNETAR_ASM_WRITER_H
#define MAGNETAR_ASM_WRITER_H

#include "backend.h"
#include <stdbool.h>

/* Writes an assembler-readable listing that reproduces result->code and
   result->rodata byte for byte. target_arch is typically "x86_64" or
   "arm64"/"aarch64". */
bool asm_write_file(const char* path, BackendResult* result, const char* target_arch);

#endif
