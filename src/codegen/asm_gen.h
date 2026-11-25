#ifndef FALCON_ASM_GEN_H
#define FALCON_ASM_GEN_H

#include "../parser/ast.h"
#include "../ir/ir.h"
#include "codegen_x64.h"
#include <stdbool.h>
#include <stdint.h>

typedef struct {
    CodeGen* cg;
    PatchTable* pt;
    IRProgram* ir;
    char* string_table;
    size_t string_table_size;
    size_t string_table_cap;
    float float_pool[256];
    size_t float_pool_size;
    int label_counter;
    bool is_object_mode;
} AsmGen;

void AsmGen_init(AsmGen* gen, IRProgram* ir);
bool AsmGen_generate(AsmGen* gen);
uint8_t* AsmGen_get_native_code(AsmGen* gen, size_t* out_size);
uint8_t* AsmGen_get_data_section(AsmGen* gen, size_t* out_size);
void AsmGen_free(AsmGen* gen);

int AsmGen_get_func_count(void);
const char* AsmGen_get_func_name(int index);
int AsmGen_get_func_pos(int index);

#endif // FALCON_ASM_GEN_H
