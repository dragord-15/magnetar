#include "../backend/elf_writer.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <sys/stat.h>

typedef struct {
    uint8_t* buf;
    size_t size;
    size_t cap;
} Buf;

static void Buf_init(Buf* b, size_t cap) {
    b->buf = (uint8_t*)malloc(cap);
    b->size = 0;
    b->cap = cap;
}

static void Buf_ensure(Buf* b, size_t extra) {
    if (b->size + extra > b->cap) {
        while (b->cap < b->size + extra) b->cap *= 2;
        b->buf = (uint8_t*)realloc(b->buf, b->cap);
    }
}

static void Buf_write8(Buf* b, uint8_t v) {
    Buf_ensure(b, 1);
    b->buf[b->size++] = v;
}

static void Buf_write16(Buf* b, uint16_t v) {
    Buf_write8(b, v & 0xFF);
    Buf_write8(b, (v >> 8) & 0xFF);
}

static void Buf_write32(Buf* b, uint32_t v) {
    for (int i = 0; i < 4; i++) Buf_write8(b, (v >> (i * 8)) & 0xFF);
}

static void Buf_write64(Buf* b, uint64_t v) {
    for (int i = 0; i < 8; i++) Buf_write8(b, (v >> (i * 8)) & 0xFF);
}

static void Buf_write_bytes(Buf* b, const uint8_t* data, size_t len) {
    Buf_ensure(b, len);
    memcpy(b->buf + b->size, data, len);
    b->size += len;
}

uint8_t* elf_build(ELFBuilder* bld, size_t* out_size) {
    Buf elf;
    Buf_init(&elf, 4096);
    
    size_t total_code = bld->text_size + bld->rodata_size + bld->data_size;
    uint64_t base = 0x400000;
    uint64_t entry = base + 64 + 56;
    
    // ELF Header (64 bytes)
    Buf_write_bytes(&elf, (uint8_t[]){0x7F,'E','L','F', 2,1,1,0, 0,0,0,0,0,0,0,0}, 16);
    Buf_write16(&elf, 2);     // ET_EXEC
    Buf_write16(&elf, 0x3E);  // x86-64
    Buf_write32(&elf, 1);     // version
    Buf_write64(&elf, entry);
    Buf_write64(&elf, 64);    // phoff
    Buf_write64(&elf, 0);     // shoff
    Buf_write32(&elf, 0);     // flags
    Buf_write16(&elf, 64);    // ehsize
    Buf_write16(&elf, 56);    // phentsize
    Buf_write16(&elf, 1);     // phnum
    Buf_write16(&elf, 0);     // shentsize
    Buf_write16(&elf, 0);     // shnum
    Buf_write16(&elf, 0);     // shstrndx
    
    // Program Header (56 bytes)
    Buf_write32(&elf, 1);     // PT_LOAD
    Buf_write32(&elf, 7);     // PF_R|PF_W|PF_X
    Buf_write64(&elf, 64 + 56); // offset
    Buf_write64(&elf, entry);   // vaddr
    Buf_write64(&elf, entry);   // paddr
    Buf_write64(&elf, total_code); // filesz
    Buf_write64(&elf, total_code); // memsz
    Buf_write64(&elf, 0x10);  // align
    
    // .text section
    if (bld->text_section) Buf_write_bytes(&elf, bld->text_section, bld->text_size);
    
    // .rodata section
    if (bld->rodata_section) Buf_write_bytes(&elf, bld->rodata_section, bld->rodata_size);
    
    // .data section
    if (bld->data_section) Buf_write_bytes(&elf, bld->data_section, bld->data_size);
    
    *out_size = elf.size;
    return elf.buf;
}

int elf_write_file(const char* path, uint8_t* data, size_t size) {
    FILE* f = fopen(path, "wb");
    if (!f) return -1;
    fwrite(data, 1, size, f);
    fclose(f);
    chmod(path, 0755);
    return 0;
}

void elf_free(uint8_t* data) {
    free(data);
}