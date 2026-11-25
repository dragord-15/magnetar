#ifndef MAGNETAR_PE_WRITER_H
#define MAGNETAR_PE_WRITER_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

typedef struct {
    uint8_t* text_section;
    size_t text_size;
    uint8_t* data_section;
    size_t data_size;
    uint8_t* rodata_section;
    size_t rodata_size;
    uint64_t image_base;
    uint32_t subsystem; /* 2=GUI, 3=CUI */
} PEBuilder;

uint8_t* pe_build(PEBuilder* builder, size_t* out_size);
int pe_write_file(const char* path, uint8_t* data, size_t size);
void pe_free(uint8_t* data);

#endif
