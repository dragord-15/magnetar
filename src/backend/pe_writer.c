#include "pe_writer.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <sys/stat.h>

typedef struct {
    uint8_t* buf;
    size_t size;
    size_t cap;
} Buf;

static void buf_init(Buf* b, size_t cap) {
    b->buf = (uint8_t*)malloc(cap ? cap : 4096);
    b->size = 0;
    b->cap = cap ? cap : 4096;
}

static void buf_ensure(Buf* b, size_t extra) {
    if (b->size + extra <= b->cap) return;
    while (b->cap < b->size + extra) b->cap *= 2;
    b->buf = (uint8_t*)realloc(b->buf, b->cap);
}

static void bw8(Buf* b, uint8_t v) { buf_ensure(b,1); b->buf[b->size++]=v; }
static void bw16(Buf* b, uint16_t v) { bw8(b, v&0xFF); bw8(b,(v>>8)&0xFF); }
static void bw32(Buf* b, uint32_t v) { for(int i=0;i<4;i++) bw8(b,(v>>(i*8))&0xFF); }
static void bw64(Buf* b, uint64_t v) { for(int i=0;i<8;i++) bw8(b,(uint8_t)((v>>(i*8))&0xFF)); }
static void bwbytes(Buf* b, const uint8_t* d, size_t n) { if(!n) return; buf_ensure(b,n); memcpy(b->buf+b->size,d,n); b->size+=n; }
static void bwzero(Buf* b, size_t n) { buf_ensure(b,n); memset(b->buf+b->size,0,n); b->size+=n; }
static void bwpad(Buf* b, size_t align) { size_t rem=b->size%align; if(rem) bwzero(b, align-rem); }

static size_t align_up(size_t v, size_t a) { return (v + a - 1) & ~(a - 1); }

uint8_t* pe_build(PEBuilder* bld, size_t* out_size) {
    const uint32_t file_align = 0x200;
    const uint32_t sect_align = 0x1000;
    const uint64_t image_base = bld->image_base ? bld->image_base : 0x140000000ULL;
    const uint32_t subsystem = bld->subsystem ? bld->subsystem : 3; /* CUI */

    size_t text_raw = align_up(bld->text_size, file_align);
    size_t rdata_raw = align_up(bld->rodata_size, file_align);
    size_t data_raw = align_up(bld->data_size, file_align);

    uint32_t headers_raw = (uint32_t)align_up(0x200, file_align); /* DOS+NT+sections fit in 512 */
    uint32_t text_rva = sect_align;
    uint32_t rdata_rva = text_rva + (uint32_t)align_up(bld->text_size ? bld->text_size : 1, sect_align);
    uint32_t data_rva  = rdata_rva + (uint32_t)align_up(bld->rodata_size ? bld->rodata_size : 1, sect_align);
    uint32_t image_size = data_rva + (uint32_t)align_up(bld->data_size ? bld->data_size : 1, sect_align);

    uint32_t text_off = headers_raw;
    uint32_t rdata_off = text_off + (uint32_t)text_raw;
    uint32_t data_off = rdata_off + (uint32_t)rdata_raw;

    Buf b; buf_init(&b, headers_raw + text_raw + rdata_raw + data_raw + 0x200);

    /* DOS Header */
    bw16(&b, 0x5A4D); /* e_magic */
    for(int i=0;i<29;i++) bw16(&b,0); /* e_cblp..e_res2 */
    bw32(&b, 0x80); /* e_lfanew */

    /* DOS stub */
    while(b.size < 0x80) bw8(&b,0);

    /* NT Headers signature */
    bw32(&b, 0x00004550); /* PE\0\0 */

    /* COFF File Header (20 bytes) */
    bw16(&b, 0x8664); /* Machine: AMD64 */
    bw16(&b, 3);      /* NumberOfSections: .text, .rdata, .data */
    bw32(&b, 0);      /* TimeDateStamp */
    bw32(&b, 0);      /* PointerToSymbolTable */
    bw32(&b, 0);      /* NumberOfSymbols */
    bw16(&b, 240);    /* SizeOfOptionalHeader (PE32+) */
    bw16(&b, 0x0022); /* Characteristics: EXECUTABLE_IMAGE | LARGE_ADDRESS_AWARE */

    /* Optional Header PE32+ (240 bytes) */
    bw16(&b, 0x20B);  /* Magic PE32+ */
    bw8(&b, 1); bw8(&b, 0); /* LinkerVersion */
    bw32(&b, (uint32_t)bld->text_size); /* SizeOfCode */
    bw32(&b, (uint32_t)(bld->rodata_size + bld->data_size)); /* SizeOfInitializedData */
    bw32(&b, 0); /* SizeOfUninitializedData */
    bw32(&b, text_rva); /* AddressOfEntryPoint - _start at beginning of .text */
    bw32(&b, text_rva); /* BaseOfCode */

    bw64(&b, image_base); /* ImageBase */
    bw32(&b, sect_align); /* SectionAlignment */
    bw32(&b, file_align); /* FileAlignment */
    bw16(&b, 6); bw16(&b, 0); /* Major/Minor OS Version */
    bw16(&b, 0); bw16(&b, 0); /* Major/Minor Image Version */
    bw16(&b, 6); bw16(&b, 0); /* Major/Minor Subsystem Version */
    bw32(&b, 0); /* Win32VersionValue */
    bw32(&b, image_size); /* SizeOfImage */
    bw32(&b, headers_raw); /* SizeOfHeaders */
    bw32(&b, 0); /* CheckSum */
    bw16(&b, (uint16_t)subsystem); /* Subsystem */
    bw16(&b, 0); /* DllCharacteristics */
    bw64(&b, 0x100000); /* SizeOfStackReserve */
    bw64(&b, 0x1000);   /* SizeOfStackCommit */
    bw64(&b, 0x100000); /* SizeOfHeapReserve */
    bw64(&b, 0x1000);   /* SizeOfHeapCommit */
    bw32(&b, 0); /* LoaderFlags */
    bw32(&b, 16); /* NumberOfRvaAndSizes */

    /* Data Directories (16) */
    for(int i=0;i<16;i++){ bw32(&b,0); bw32(&b,0); }

    /* Section Header: .text */
    bwbytes(&b, (const uint8_t*)".text\0\0\0", 8);
    bw32(&b, (uint32_t)bld->text_size); /* VirtualSize */
    bw32(&b, text_rva);
    bw32(&b, (uint32_t)text_raw); /* SizeOfRawData */
    bw32(&b, text_off);
    bw32(&b,0); bw32(&b,0); /* reloc/linenumbers */
    bw16(&b,0); bw16(&b,0);
    bw32(&b, 0x60000020); /* CODE | EXECUTE_READ */

    /* Section Header: .rdata */
    bwbytes(&b, (const uint8_t*)".rdata\0\0", 8);
    bw32(&b, (uint32_t)bld->rodata_size);
    bw32(&b, rdata_rva);
    bw32(&b, (uint32_t)rdata_raw);
    bw32(&b, rdata_off);
    bw32(&b,0); bw32(&b,0);
    bw16(&b,0); bw16(&b,0);
    bw32(&b, 0x40000040); /* INITIALIZED_DATA | READ */

    /* Section Header: .data */
    bwbytes(&b, (const uint8_t*)".data\0\0\0", 8);
    bw32(&b, (uint32_t)bld->data_size);
    bw32(&b, data_rva);
    bw32(&b, (uint32_t)data_raw);
    bw32(&b, data_off);
    bw32(&b,0); bw32(&b,0);
    bw16(&b,0); bw16(&b,0);
    bw32(&b, 0xC0000040); /* INITIALIZED_DATA | READ | WRITE */

    /* Pad headers */
    bwpad(&b, file_align);

    /* .text */
    if (bld->text_section && bld->text_size) bwbytes(&b, bld->text_section, bld->text_size);
    bwpad(&b, file_align);

    /* .rdata */
    if (bld->rodata_section && bld->rodata_size) bwbytes(&b, bld->rodata_section, bld->rodata_size);
    bwpad(&b, file_align);

    /* .data */
    if (bld->data_section && bld->data_size) bwbytes(&b, bld->data_section, bld->data_size);
    bwpad(&b, file_align);

    *out_size = b.size;
    return b.buf;
}

int pe_write_file(const char* path, uint8_t* data, size_t size) {
    FILE* f = fopen(path, "wb");
    if (!f) return -1;
    fwrite(data, 1, size, f);
    fclose(f);
    chmod(path, 0755);
    return 0;
}

void pe_free(uint8_t* data) { free(data); }
