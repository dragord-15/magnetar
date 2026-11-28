#include "bin_writer.h"
#include <stdio.h>
#include <sys/stat.h>

bool bin_write_file(const char* path, BackendResult* result) {
    if (!path || !result) return false;
    if (result->code_size && !result->code) return false;
    if (result->rodata_size && !result->rodata) return false;

    FILE* f = fopen(path, "wb");
    if (!f) return false;

    bool ok = true;
    if (result->code_size && fwrite(result->code, 1, result->code_size, f) != result->code_size) {
        ok = false;
    }
    if (ok && result->rodata_size &&
        fwrite(result->rodata, 1, result->rodata_size, f) != result->rodata_size) {
        ok = false;
    }
    if (ferror(f)) ok = false;
    if (fclose(f) != 0) ok = false;
    if (!ok) return false;

    chmod(path, 0755);
    return true;
}
