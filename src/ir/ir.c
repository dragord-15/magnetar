#include "ir.h"
#include <stdlib.h>
#include <string.h>

// ---------- IR Program management ----------

IR_Program *ir_program_new(void) {
    IR_Program *prog = (IR_Program *)malloc(sizeof(IR_Program));
    if (!prog) return NULL;
    prog->capacity     = 32;
    prog->count        = 0;
    prog->instructions = (IR_Inst *)malloc(prog->capacity * sizeof(IR_Inst));
    if (!prog->instructions) {
        free(prog);
        return NULL;
    }
    return prog;
}

void ir_program_free(IR_Program *prog) {
    if (!prog) return;
    for (size_t i = 0; i < prog->count; i++) {
        if (prog->instructions[i].label)
            free((char *)prog->instructions[i].label);
    }
    free(prog->instructions);
    free(prog);
}

// ---------- Emit a regular instruction ----------
void ir_emit(IR_Program *prog, IR_Opcode op, int dst, int src1, int src2,
             const char *label) {
    if (!prog) return;
    if (prog->count >= prog->capacity) {
        size_t new_cap = prog->capacity * 2;
        IR_Inst *buf   = (IR_Inst *)realloc(prog->instructions,
                                             new_cap * sizeof(IR_Inst));
        if (!buf) return;
        prog->instructions = buf;
        prog->capacity     = new_cap;
    }
    IR_Inst *inst   = &prog->instructions[prog->count++];
    inst->op        = op;
    inst->dst       = dst;
    inst->src1      = src1;
    inst->src2      = src2;
    inst->label     = label ? strdup(label) : NULL;
    inst->ast_node  = NULL;
}

// ---------- Emit an AST-node-wrapper instruction (used by asm_gen.c) ----------
void ir_emit_ast(IR_Program *prog, ASTNode *node) {
    if (!prog) return;
    if (prog->count >= prog->capacity) {
        size_t new_cap = prog->capacity * 2;
        IR_Inst *buf   = (IR_Inst *)realloc(prog->instructions,
                                             new_cap * sizeof(IR_Inst));
        if (!buf) return;
        prog->instructions = buf;
        prog->capacity     = new_cap;
    }
    IR_Inst *inst   = &prog->instructions[prog->count++];
    inst->op        = IR_AST_NODE;
    inst->dst       = 0;
    inst->src1      = 0;
    inst->src2      = 0;
    inst->label     = NULL;
    inst->ast_node  = node;
}

// ---------- Compatibility wrappers (used by main.c and asm_gen.c) ----------

IRProgram *IRProgram_build(void *ast) {
    IR_Program *prog = ir_program_new();
    if (!prog) return NULL;
    if (ast) {
        // STAGE 0 (active): wrap the entire AST in a single IR_AST_NODE.
        // asm_gen.c reads this and calls generate_from_ast() to produce x86-64.
        ir_emit_ast(prog, (ASTNode *)ast);

        // STAGE 1 (pending): real IR lowering via ir_build_from_ast().
        // Activate once asm_gen.c is updated to consume IR opcodes directly.
        // ir_build_from_ast(prog, (ASTNode *)ast);
    }
    if (prog->count == 0) {
        ir_emit(prog, IR_RET, 0, 0, 0, NULL);
    }
    return prog;
}

void IRProgram_optimize(IRProgram *prog) {
    ir_optimize(prog); // delegate to ir_optimizer.c
}

void IRProgram_free(IRProgram *prog) {
    ir_program_free(prog);
}
