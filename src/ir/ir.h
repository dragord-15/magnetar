#ifndef MAGNETAR_IR_H
#define MAGNETAR_IR_H

#include <stddef.h>
#include <stdint.h>

// Forward-declare ASTNode so we can embed it without pulling the full header.
typedef struct ASTNode ASTNode;

// ---------- IR Opcodes (31 total – satisfies >= 20 requirement) ----------
typedef enum {
    IR_NOP = 0,   // no operation
    IR_CONST,     // dst = imm
    IR_LOAD,      // dst = mem[src1]
    IR_STORE,     // mem[dst] = src1
    IR_ADD,       // dst = src1 + src2
    IR_SUB,       // dst = src1 - src2
    IR_MUL,       // dst = src1 * src2
    IR_DIV,       // dst = src1 / src2
    IR_MOD,       // dst = src1 % src2
    IR_NEG,       // dst = -src1
    IR_AND,       // dst = src1 & src2
    IR_OR,        // dst = src1 | src2
    IR_XOR,       // dst = src1 ^ src2
    IR_SHL,       // dst = src1 << src2
    IR_SHR,       // dst = src1 >> src2
    IR_MOV,       // dst = src1
    IR_PUSH,      // push src1 onto stack
    IR_POP,       // pop into dst
    IR_CALL,      // call function identified by label
    IR_RET,       // return from function
    IR_JMP,       // unconditional jump to label
    IR_JZ,        // jump to label if src1 == 0
    IR_JNZ,       // jump to label if src1 != 0
    IR_LABEL,     // label definition
    IR_CMP,       // set flags: compare src1 and src2
    IR_SETGT,     // dst = (src1 >  src2)
    IR_SETLT,     // dst = (src1 <  src2)
    IR_SETGE,     // dst = (src1 >= src2)
    IR_SETLE,     // dst = (src1 <= src2)
    IR_SETEQ,     // dst = (src1 == src2)
    IR_SETNE,     // dst = (src1 != src2)
    IR_AST_NODE   // wraps a raw ASTNode* (used during stage 0 code-gen)
} IR_Opcode;

// ---------- Instruction ----------
typedef struct {
    IR_Opcode   op;
    int         dst;      // destination virtual register
    int         src1;     // first source operand
    int         src2;     // second source operand
    const char *label;    // target label (for jumps / calls / strings)
    ASTNode    *ast_node; // payload for IR_AST_NODE instructions
} IR_Inst;

// Compatibility alias – existing code (asm_gen.c) uses 'IRInstruction'
typedef IR_Inst IRInstruction;

// ---------- Program (dynamic list of instructions) ----------
typedef struct {
    IR_Inst *instructions; // ← field name matches asm_gen.c usage
    size_t   count;
    size_t   capacity;
} IR_Program;

// Compatibility alias – existing code uses 'IRProgram'
typedef IR_Program IRProgram;

// ---------- Core API ----------
IR_Program *ir_program_new(void);
void        ir_program_free(IR_Program *prog);
void        ir_emit(IR_Program *prog, IR_Opcode op, int dst, int src1, int src2,
                    const char *label);
void        ir_emit_ast(IR_Program *prog, ASTNode *node);

// ---------- Stage-0 wrappers (real AST traversal added in stage 1) ----------
IRProgram  *IRProgram_build(void *ast);
void        IRProgram_optimize(IRProgram *prog);
void        IRProgram_free(IR_Program *prog);

// ---------- Real AST-walking builder (ir_builder.c) ----------
void        ir_build_from_ast(IR_Program *prog, struct ASTNode *ast);
void        ir_build_example(IR_Program *prog);

// ---------- Optimiser (defined in ir_optimizer.c) ----------
void        ir_optimize(IR_Program *prog);

#endif // MAGNETAR_IR_H
