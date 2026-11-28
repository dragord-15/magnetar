#!/usr/bin/env bash
# The IR optimiser must fold integer constants safely and stop at undefined
# operations such as division by zero.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/check.c" <<'EOF'
#include "ir.h"
#include <stdio.h>

#define CHECK(expr) do { \
    if (!(expr)) { printf("FAIL  %s\n", #expr); return 1; } \
} while (0)

int main(void) {
    IR_Program *p = ir_program_new();
    CHECK(p != NULL);

    /* v10=7, v11=3; chained arithmetic, comparison, copy, and an unsafe div. */
    ir_emit(p, IR_CONST, 10, 7, 0, NULL);
    ir_emit(p, IR_CONST, 11, 3, 0, NULL);
    ir_emit(p, IR_ADD,   12, 10, 11, NULL);
    ir_emit(p, IR_MUL,   13, 12, 11, NULL);
    ir_emit(p, IR_DIV,   14, 13, 11, NULL);
    ir_emit(p, IR_SETGT, 15, 14, 10, NULL);
    ir_emit(p, IR_MOV,   16, 15, 0, NULL);
    ir_emit(p, IR_CONST, 17, 0, 0, NULL);
    ir_emit(p, IR_DIV,   18, 13, 17, NULL);
    ir_emit(p, IR_RET,    0,  0,  0, NULL);

    size_t before = p->count;
    IRProgram_optimize(p);

    CHECK(before == 10);
    CHECK(p->count == 10);
    CHECK(p->instructions[0].op == IR_CONST && p->instructions[0].src1 == 7);
    CHECK(p->instructions[1].op == IR_CONST && p->instructions[1].src1 == 3);
    CHECK(p->instructions[2].op == IR_CONST && p->instructions[2].src1 == 10);
    CHECK(p->instructions[3].op == IR_CONST && p->instructions[3].src1 == 30);
    CHECK(p->instructions[4].op == IR_CONST && p->instructions[4].src1 == 10);
    CHECK(p->instructions[5].op == IR_CONST && p->instructions[5].src1 == 1);
    CHECK(p->instructions[6].op == IR_CONST && p->instructions[6].src1 == 1);
    CHECK(p->instructions[7].op == IR_CONST && p->instructions[7].src1 == 0);
    CHECK(p->instructions[8].op == IR_DIV);
    CHECK(p->instructions[9].op == IR_RET);

    IRProgram_free(p);
    puts("ir folding: pass=10 fail=0");
    return 0;
}
EOF

gcc -std=gnu11 -Wall -Wextra -I"$ROOT/src/ir" \
    "$WORK/check.c" "$ROOT/src/ir/ir.c" "$ROOT/src/ir/ir_optimizer.c" \
    -o "$WORK/check" || { echo "FAIL  harness did not compile"; exit 1; }
"$WORK/check"
