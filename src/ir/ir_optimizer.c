#include "ir.h"
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

// ---------------------------------------------------------------------------
// ir_optimizer.c  –  IR optimisation passes
// ---------------------------------------------------------------------------

static void fold_mov_self(IR_Program *prog) {
    for (size_t i = 0; i < prog->count; i++) {
        IR_Inst *ins = &prog->instructions[i];
        if (ins->op == IR_MOV && ins->dst == ins->src1) {
            ins->op = IR_NOP;
        }
    }
}

static void fold_xor_zero(IR_Program *prog) {
    if (prog->count < 2) return;
    for (size_t i = 0; i + 1 < prog->count; i++) {
        IR_Inst *a = &prog->instructions[i];
        IR_Inst *b = &prog->instructions[i + 1];
        if (a->op == IR_MOV && a->src1 == 0 &&
            b->op == IR_XOR && b->dst == a->dst &&
            b->src1 == a->dst && b->src2 == a->dst) {
            a->op = IR_NOP;
        }
    }
}

static void remove_nop(IR_Program *prog) {
    size_t write = 0;
    for (size_t i = 0; i < prog->count; i++) {
        if (prog->instructions[i].op != IR_NOP) {
            if (write != i)
                prog->instructions[write] = prog->instructions[i];
            write++;
        } else {
            /* تحرير التسمية إن وُجدت قبل حذف تعليمة NOP */
            if (prog->instructions[i].label)
                free((char *)prog->instructions[i].label);
        }
    }
    prog->count = write;
}

// Maximum virtual register index tracked by the folder. The stage-0 builder
// uses small dense indices; anything beyond this limit is treated as unknown
// rather than allocating an unbounded table from untrusted input.
#define FOLD_MAX_VREG 65536

typedef struct {
    int64_t value[FOLD_MAX_VREG];
    bool    known[FOLD_MAX_VREG];
} FoldEnv;

// Control flow makes a value's reaching definition ambiguous. Reset the whole
// environment at labels and after calls/jumps/returns instead of doing dataflow.
static bool control_flow_barrier(IR_Opcode op) {
    return op == IR_LABEL || op == IR_JMP || op == IR_JZ || op == IR_JNZ ||
           op == IR_CALL || op == IR_RET || op == IR_PUSH || op == IR_POP ||
           op == IR_AST_NODE;
}

static bool fold_binary(IR_Opcode op, int64_t a, int64_t b, int64_t *out) {
    switch (op) {
        case IR_ADD: *out = (int64_t)((uint64_t)a + (uint64_t)b); return true;
        case IR_SUB: *out = (int64_t)((uint64_t)a - (uint64_t)b); return true;
        case IR_MUL: *out = (int64_t)((uint64_t)a * (uint64_t)b); return true;
        case IR_AND: *out = a & b; return true;
        case IR_OR:  *out = a | b; return true;
        case IR_XOR: *out = a ^ b; return true;
        case IR_SETGT: *out = a >  b; return true;
        case IR_SETLT: *out = a <  b; return true;
        case IR_SETGE: *out = a >= b; return true;
        case IR_SETLE: *out = a <= b; return true;
        case IR_SETEQ: *out = a == b; return true;
        case IR_SETNE: *out = a != b; return true;
        case IR_DIV:
            if (b == 0 || (a == INT64_MIN && b == -1)) return false;
            *out = a / b;
            return true;
        case IR_MOD:
            if (b == 0 || (a == INT64_MIN && b == -1)) return false;
            *out = a % b;
            return true;
        case IR_SHL:
            if (b < 0 || b >= 64) return false;
            *out = (int64_t)((uint64_t)a << b);
            return true;
        case IR_SHR:
            if (b < 0 || b >= 64) return false;
            *out = a >> b;
            return true;
        default: return false;
    }
}

static bool fold_instruction(IR_Inst *ins, FoldEnv *env) {
    if (ins->dst < 0 || ins->dst >= FOLD_MAX_VREG) return false;

    if (ins->op == IR_CONST) {
        env->known[ins->dst] = true;
        env->value[ins->dst] = ins->src1;
        return false;
    }

    int64_t result = 0;
    bool can_fold = false;
    bool lhs_known = ins->src1 >= 0 && ins->src1 < FOLD_MAX_VREG &&
                     env->known[ins->src1];
    bool rhs_known = ins->src2 >= 0 && ins->src2 < FOLD_MAX_VREG &&
                     env->known[ins->src2];
    if (ins->op == IR_MOV && lhs_known) {
        result = env->value[ins->src1];
        can_fold = true;
    } else if (ins->op == IR_NEG && lhs_known &&
               env->value[ins->src1] != INT64_MIN) {
        result = -env->value[ins->src1];
        can_fold = true;
    } else if (lhs_known && rhs_known) {
        can_fold = fold_binary(ins->op, env->value[ins->src1],
                               env->value[ins->src2], &result);
    }

    if (can_fold) {
        ins->op = IR_CONST;
        ins->src1 = (int)result;
        ins->src2 = 0;
        env->known[ins->dst] = true;
        env->value[ins->dst] = result;
        return true;
    }

    env->known[ins->dst] = false;
    return false;
}

static size_t fold_constants(IR_Program *prog) {
    if (!prog || prog->count == 0) return 0;

    FoldEnv *env = (FoldEnv *)calloc(1, sizeof(*env));
    if (!env) return 0;

    size_t folded = 0;
    bool changed;
    do {
        changed = false;
        for (size_t i = 0; i < FOLD_MAX_VREG; i++) env->known[i] = false;
        for (size_t i = 0; i < prog->count; i++) {
            IR_Inst *ins = &prog->instructions[i];
            if (control_flow_barrier(ins->op)) {
                for (size_t r = 0; r < FOLD_MAX_VREG; r++) env->known[r] = false;
                continue;
            }
            if (fold_instruction(ins, env)) changed = true;
        }
        if (changed) folded++;
    } while (changed);

    free(env);
    return folded;
}

void ir_optimize(IR_Program *prog) {
    if (!prog) return;
    fold_mov_self(prog);
    fold_xor_zero(prog);
    fold_constants(prog);
    remove_nop(prog);
}
