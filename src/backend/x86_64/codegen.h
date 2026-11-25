#ifndef MAGNETAR_X86_64_CODEGEN_H
#define MAGNETAR_X86_64_CODEGEN_H

#include "../../parser/ast.h"
#include "../../ir/ir.h"
#include "encoder.h"
#include <stdbool.h>
#include <stdint.h>

/* The read-only pool of float literals. Every distinct float literal in the
   program needs one slot; 256 was too small for real programs and the
   overflow produced references to labels that were never emitted. */
#define MAX_FLOAT_POOL 4096

/* Stack frame layout, relative to %rbp:
 *
 *      rbp+16+  incoming arguments (pushed by the caller)
 *      rbp+8    return address
 *      rbp      saved %rbp
 *      rbp-8    first free slot  -- expression temporaries grow downwards
 *      ...      up to rbp-(TEMP_REGION-1)
 *      rbp-256  first local variable -- locals grow downwards
 *      ...
 *      rbp-2048 bottom of the frame
 *
 * Temporaries and locals used to share one growing region, so a struct
 * literal silently overwrote the sixteenth local. */
#define TEMP_REGION_SIZE 256
#define LOCALS_BASE      TEMP_REGION_SIZE
#define STACK_FRAME_SIZE 2048

typedef struct {
    CodeGen* cg;
    PatchTable* pt;
    IRProgram* ir;
    char* string_table;
    size_t string_table_size;
    size_t string_table_cap;
    float float_pool[MAX_FLOAT_POOL];
    size_t float_pool_size;
    int label_counter;
    int temp_stack_offset;
    bool is_object_mode;
} AsmGen;

void AsmGen_init(AsmGen* gen, IRProgram* ir);
void AsmGen_set_entry_name(const char* name);
bool AsmGen_generate(AsmGen* gen);
uint8_t* AsmGen_get_native_code(AsmGen* gen, size_t* out_size);
uint8_t* AsmGen_get_data_section(AsmGen* gen, size_t* out_size);
void AsmGen_free(AsmGen* gen);

int AsmGen_get_func_count(void);
const char* AsmGen_get_func_name(int index);
int AsmGen_get_func_pos(int index);

#endif // MAGNETAR_ASM_GEN_H
