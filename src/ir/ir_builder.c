#include "ir.h"
#include "../parser/ast.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// ---------------------------------------------------------------------------
// ir_builder.c – Stage 1: Real AST → IR translation
// Walks the entire AST and emits typed IR instructions.
// The code-generator (asm_gen.c) will read these in Stage 1 as a fallback,
// while the IR_AST_NODE path remains available for complex nodes not yet
// lowered.
// ---------------------------------------------------------------------------

static int next_vreg = 0;  // virtual register counter

static int new_vreg(void) { return next_vreg++; }

// Forward declaration
static int ir_build_node(IR_Program *prog, ASTNode *node);

// ── Literals ──────────────────────────────────────────────────────────────

static int ir_build_number(IR_Program *prog, ASTNode *node) {
    int dst = new_vreg();
    ir_emit(prog, IR_CONST, dst, node->int_value, 0, NULL);
    return dst;
}

// ── Binary expressions ─────────────────────────────────────────────────────

static int ir_build_binary(IR_Program *prog, ASTNode *node) {
    if (node->child_count < 2) return -1;
    int lhs = ir_build_node(prog, node->children[0]);
    int rhs = ir_build_node(prog, node->children[1]);
    int dst = new_vreg();
    const char *op = node->token.text;
    if (!op) { ir_emit_ast(prog, node); return -1; }

    if      (strcmp(op, "+")  == 0) ir_emit(prog, IR_ADD,   dst, lhs, rhs, NULL);
    else if (strcmp(op, "-")  == 0) ir_emit(prog, IR_SUB,   dst, lhs, rhs, NULL);
    else if (strcmp(op, "*")  == 0) ir_emit(prog, IR_MUL,   dst, lhs, rhs, NULL);
    else if (strcmp(op, "/")  == 0) ir_emit(prog, IR_DIV,   dst, lhs, rhs, NULL);
    else if (strcmp(op, "%")  == 0) ir_emit(prog, IR_MOD,   dst, lhs, rhs, NULL);
    else if (strcmp(op, "&")  == 0) ir_emit(prog, IR_AND,   dst, lhs, rhs, NULL);
    else if (strcmp(op, "|")  == 0) ir_emit(prog, IR_OR,    dst, lhs, rhs, NULL);
    else if (strcmp(op, "^")  == 0) ir_emit(prog, IR_XOR,   dst, lhs, rhs, NULL);
    else if (strcmp(op, "<<") == 0) ir_emit(prog, IR_SHL,   dst, lhs, rhs, NULL);
    else if (strcmp(op, ">>") == 0) ir_emit(prog, IR_SHR,   dst, lhs, rhs, NULL);
    else if (strcmp(op, ">")  == 0) ir_emit(prog, IR_SETGT, dst, lhs, rhs, NULL);
    else if (strcmp(op, "<")  == 0) ir_emit(prog, IR_SETLT, dst, lhs, rhs, NULL);
    else if (strcmp(op, ">=") == 0) ir_emit(prog, IR_SETGE, dst, lhs, rhs, NULL);
    else if (strcmp(op, "<=") == 0) ir_emit(prog, IR_SETLE, dst, lhs, rhs, NULL);
    else if (strcmp(op, "==") == 0) ir_emit(prog, IR_SETEQ, dst, lhs, rhs, NULL);
    else if (strcmp(op, "!=") == 0) ir_emit(prog, IR_SETNE, dst, lhs, rhs, NULL);
    else {
        // Unrecognised binary op – fall back to AST wrapping
        ir_emit_ast(prog, node);
        return -1;
    }
    return dst;
}

// ── Return statement ───────────────────────────────────────────────────────

static void ir_build_return(IR_Program *prog, ASTNode *node) {
    if (node->child_count > 0) {
        int val = ir_build_node(prog, node->children[0]);
        if (val >= 0) ir_emit(prog, IR_MOV, 0 /*RAX*/, val, 0, NULL);
    }
    ir_emit(prog, IR_RET, 0, 0, 0, NULL);
}

// ── Function declaration ───────────────────────────────────────────────────

static void ir_build_func_decl(IR_Program *prog, ASTNode *node) {
    const char *name = node->token.text ? node->token.text : "unknown";
    ir_emit(prog, IR_LABEL, 0, 0, 0, name);
    // Body is the last child
    if (node->child_count > 0) {
        ir_build_node(prog, node->children[node->child_count - 1]);
    }
}

// ── Block ──────────────────────────────────────────────────────────────────

static void ir_build_block(IR_Program *prog, ASTNode *node) {
    for (int i = 0; i < node->child_count; i++) {
        ir_build_node(prog, node->children[i]);
    }
}

// ── Variable declaration ───────────────────────────────────────────────────

static int ir_build_var_decl(IR_Program *prog, ASTNode *node) {
    if (node->child_count > 0) {
        // child[0] is the initialiser expression
        int src = ir_build_node(prog, node->children[0]);
        int dst = new_vreg();
        if (src >= 0) ir_emit(prog, IR_MOV, dst, src, 0, NULL);
        return dst;
    }
    return new_vreg(); // uninitialised variable
}

// ── If statement ───────────────────────────────────────────────────────────

static void ir_build_if(IR_Program *prog, ASTNode *node) {
    // Fall back to AST wrapping for now; will be lowered properly in stage 2
    ir_emit_ast(prog, node);
}

// ── While statement ────────────────────────────────────────────────────────

static void ir_build_while(IR_Program *prog, ASTNode *node) {
    ir_emit_ast(prog, node); // lowered in stage 2
}

// ── For statement ──────────────────────────────────────────────────────────

static void ir_build_for(IR_Program *prog, ASTNode *node) {
    ir_emit_ast(prog, node); // lowered in stage 2
}

// ── Expression statement ───────────────────────────────────────────────────

static void ir_build_expr_stmt(IR_Program *prog, ASTNode *node) {
    if (node->child_count > 0) {
        ir_build_node(prog, node->children[0]);
    }
}

// ── Call expression ────────────────────────────────────────────────────────

static int ir_build_call(IR_Program *prog, ASTNode *node) {
    // Push arguments first, then emit IR_CALL
    for (int i = 0; i < node->child_count; i++) {
        int arg = ir_build_node(prog, node->children[i]);
        if (arg >= 0) ir_emit(prog, IR_PUSH, 0, arg, 0, NULL);
    }
    const char *name = node->token.text ? node->token.text : "unknown";
    int dst = new_vreg();
    ir_emit(prog, IR_CALL, dst, 0, 0, name);
    return dst;
}

// ── Dispatch ──────────────────────────────────────────────────────────────

static int ir_build_node(IR_Program *prog, ASTNode *node) {
    if (!node) return -1;
    switch (node->type) {
        case AST_PROGRAM:
            ir_build_block(prog, node);
            return -1;
        case NODE_NUMBER:
        case AST_LITERAL_EXPR:
            return ir_build_number(prog, node);
        case AST_BINARY_EXPR:
        case NODE_BINARY:
            return ir_build_binary(prog, node);
        case AST_RETURN_STMT:
            ir_build_return(prog, node);
            return -1;
        case AST_FUNC_DECL:
            ir_build_func_decl(prog, node);
            return -1;
        case AST_BLOCK:
            ir_build_block(prog, node);
            return -1;
        case AST_VAR_DECL:
            return ir_build_var_decl(prog, node);
        case AST_IF_STMT:
            ir_build_if(prog, node);
            return -1;
        case AST_WHILE_STMT:
            ir_build_while(prog, node);
            return -1;
        case AST_FOR_STMT:
            ir_build_for(prog, node);
            return -1;
        case AST_EXPR_STMT:
            ir_build_expr_stmt(prog, node);
            return -1;
        case AST_CALL_EXPR:
            return ir_build_call(prog, node);
        case AST_IDENTIFIER_EXPR:
        case NODE_IDENT: {
            // Load variable from stack slot (simplified: use a const placeholder)
            int dst = new_vreg();
            ir_emit(prog, IR_LOAD, dst, 0, 0, node->token.text);
            return dst;
        }
        default:
            // Unknown/complex node: fall back to AST wrapping so asm_gen handles it
            ir_emit_ast(prog, node);
            return -1;
    }
}

// ── Public API ──────────────────────────────────────────────────────────────

void ir_build_example(IR_Program *prog) {
    if (!prog) return;
    ir_emit(prog, IR_CONST, 0, 5, 0, NULL);
    ir_emit(prog, IR_CONST, 1, 3, 0, NULL);
    ir_emit(prog, IR_ADD,   2, 0, 1, NULL);
    ir_emit(prog, IR_RET,   0, 0, 0, NULL);
}

// Called by ir.c IRProgram_build → build IR from a real AST
void ir_build_from_ast(IR_Program *prog, ASTNode *ast) {
    if (!prog || !ast) return;
    next_vreg = 100; // virtual registers start at 100 to avoid clashing with real regs
    ir_build_node(prog, ast);
}
