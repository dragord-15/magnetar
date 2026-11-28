#ifndef MAGNETAR_BIN_WRITER_H
#define MAGNETAR_BIN_WRITER_H

#include "backend.h"
#include <stdbool.h>

/* Writes a flat binary: .text bytes followed by .rodata bytes, with no
   ELF/PE headers or relocation records. */
bool bin_write_file(const char* path, BackendResult* result);

#endif
