#include "asm_writer.h"
#include <stdio.h>
#include <stdint.h>
#include <string.h>

#define ASM_BYTES_PER_LINE 16
#define ASM_MAX_LABELS (MAX_EXPORTS + 1)

typedef struct {
    const char* name;
    size_t offset;
} AsmLabel;

typedef struct {
    AsmLabel labels[ASM_MAX_LABELS];
    int count;
} AsmLabelList;

static bool asm_str_equal_ci(const char* a, const char* b) {
    while (*a && *b) {
        char ca = *a;
        char cb = *b;
        if (ca >= 'A' && ca <= 'Z') ca = (char)(ca + ('a' - 'A'));
        if (cb >= 'A' && cb <= 'Z') cb = (char)(cb + ('a' - 'A'));
        if (ca != cb) return false;
        a++;
        b++;
    }
    return *a == '\0' && *b == '\0';
}

static bool asm_is_arm64(const char* target_arch) {
    if (!target_arch) return false;
    return asm_str_equal_ci(target_arch, "arm64") ||
           asm_str_equal_ci(target_arch, "aarch64") ||
           asm_str_equal_ci(target_arch, "armv8") ||
           asm_str_equal_ci(target_arch, "armv8-a");
}

static bool asm_valid_symbol(const char* name) {
    if (!name || !*name) return false;
    unsigned char c = (unsigned char)name[0];
    if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_')) return false;
    for (const char* p = name + 1; *p; p++) {
        c = (unsigned char)*p;
        if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
              (c >= '0' && c <= '9') || c == '_')) return false;
    }
    return true;
}

static void asm_label_list_add(AsmLabelList* list, const char* name, size_t offset) {
    if (list->count >= ASM_MAX_LABELS) return;
    for (int i = 0; i < list->count; i++) {
        if (strcmp(list->labels[i].name, name) == 0) return;
    }
    list->labels[list->count].name = name;
    list->labels[list->count].offset = offset;
    list->count++;
}

static void asm_label_list_sort(AsmLabelList* list) {
    for (int i = 1; i < list->count; i++) {
        AsmLabel item = list->labels[i];
        int j = i - 1;
        while (j >= 0 && list->labels[j].offset > item.offset) {
            list->labels[j + 1] = list->labels[j];
            j--;
        }
        list->labels[j + 1] = item;
    }
}

static void asm_emit_labels_at(FILE* f, const AsmLabelList* list, size_t offset,
                               size_t* bytes_on_line) {
    for (int i = 0; i < list->count; i++) {
        if (list->labels[i].offset != offset) continue;
        if (*bytes_on_line) {
            fputc('\n', f);
            *bytes_on_line = 0;
        }
        fprintf(f, "%s:\n", list->labels[i].name);
    }
}

static bool asm_has_label_inside(const AsmLabelList* list, size_t start, size_t end) {
    for (int i = 0; i < list->count; i++) {
        size_t offset = list->labels[i].offset;
        if (offset > start && offset < end) return true;
    }
    return false;
}

static void asm_emit_code(FILE* f, const uint8_t* code, size_t code_size,
                          const AsmLabelList* labels, bool arm64) {
    size_t offset = 0;
    size_t bytes_on_line = 0;

    while (offset < code_size) {
        asm_emit_labels_at(f, labels, offset, &bytes_on_line);

        if (arm64 && (offset % 4) == 0 && offset + 4 <= code_size &&
            !asm_has_label_inside(labels, offset, offset + 4)) {
            if (bytes_on_line) {
                fputc('\n', f);
                bytes_on_line = 0;
            }
            uint32_t word = (uint32_t)code[offset] |
                            ((uint32_t)code[offset + 1] << 8) |
                            ((uint32_t)code[offset + 2] << 16) |
                            ((uint32_t)code[offset + 3] << 24);
            fprintf(f, "    .inst 0x%08x\n", word);
            offset += 4;
        } else {
            if (bytes_on_line == 0) fputs("    .byte ", f);
            else fputs(", ", f);
            fprintf(f, "0x%02x", code[offset]);
            offset++;
            bytes_on_line++;
            if (bytes_on_line == ASM_BYTES_PER_LINE) {
                fputc('\n', f);
                bytes_on_line = 0;
            }
        }
    }
    if (bytes_on_line) fputc('\n', f);
    asm_emit_labels_at(f, labels, code_size, &bytes_on_line);
}

static void asm_emit_rodata(FILE* f, const uint8_t* data, size_t size) {
    size_t bytes_on_line = 0;

    for (size_t i = 0; i < size; i++) {
        if (bytes_on_line == 0) fputs("    .byte ", f);
        else fputs(", ", f);
        fprintf(f, "0x%02x", data[i]);
        bytes_on_line++;
        if (bytes_on_line == ASM_BYTES_PER_LINE) {
            fputc('\n', f);
            bytes_on_line = 0;
        }
    }
    if (bytes_on_line) fputc('\n', f);
}

bool asm_write_file(const char* path, BackendResult* result, const char* target_arch) {
    if (!path || !result) return false;
    if (result->code_size && !result->code) return false;
    if (result->rodata_size && !result->rodata) return false;

    bool arm64 = asm_is_arm64(target_arch);
    const char* arch_name = arm64 ? "arm64/aarch64" : "x86_64";

    AsmLabelList labels;
    labels.count = 0;
    int export_count = result->num_exports;
    if (export_count > MAX_EXPORTS) export_count = MAX_EXPORTS;
    for (int i = 0; i < export_count; i++) {
        const char* name = result->exports[i].name;
        if (!asm_valid_symbol(name)) continue;
        size_t offset = result->exports[i].offset;
        if (offset > result->code_size) offset = result->code_size;
        asm_label_list_add(&labels, name, offset);
    }

    bool has_main = false;
    for (int i = 0; i < labels.count; i++) {
        if (strcmp(labels.labels[i].name, "main") == 0) {
            has_main = true;
            break;
        }
    }
    if (!has_main) asm_label_list_add(&labels, "main", 0);
    asm_label_list_sort(&labels);

    FILE* f = fopen(path, "w");
    if (!f) return false;

    bool ok = true;
    if (fprintf(f, "/* Magnetar assembly listing - target: %s */\n", arch_name) < 0) ok = false;
    if (ok && fprintf(f, "/* .text: %zu bytes, .rodata: %zu bytes */\n",
                      result->code_size, result->rodata_size) < 0) ok = false;
    if (ok) fputs("/* Byte directives reproduce the generated bytes exactly. */\n", f);
    if (ok && arm64) fputs("    .arch armv8-a\n", f);
    if (ok) fputs("    .section .text\n", f);
    if (ok && arm64) fputs("    .align 2\n", f);
    if (ok) {
        for (int i = 0; i < labels.count; i++) {
            fprintf(f, "    .globl %s\n", labels.labels[i].name);
        }
        asm_emit_code(f, result->code, result->code_size, &labels, arm64);
    }
    if (ok) {
        fputs("    .section .rodata\n", f);
        asm_emit_rodata(f, result->rodata, result->rodata_size);
    }

    if (ferror(f)) ok = false;
    if (fclose(f) != 0) ok = false;
    return ok;
}
