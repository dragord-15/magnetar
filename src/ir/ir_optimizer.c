#include "ir.h"
#include <stdlib.h>

// ---------------------------------------------------------------------------
// ir_optimizer.c  –  Stage 0 IR optimisation passes
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

void ir_optimize(IR_Program *prog) {
    if (!prog) return;
    fold_mov_self(prog);
    fold_xor_zero(prog);
    remove_nop(prog);
}
