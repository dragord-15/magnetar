#ifndef MAGNETAR_ELF_WRITER_H
#define MAGNETAR_ELF_WRITER_H

#include <stdint.h>
#include <stddef.h>

typedef struct {
    uint8_t* text_section;
    size_t text_size;
    uint8_t* data_section;
    size_t data_size;
    uint8_t* rodata_section;
    size_t rodata_size;
    uint64_t entry_point;
} ELFBuilder;

uint8_t* elf_build(ELFBuilder* builder, size_t* out_size);
int elf_write_file(const char* path, uint8_t* data, size_t size);
void elf_free(uint8_t* data);

#endif