#ifndef MAGNETAR_AST_H
#define MAGNETAR_AST_H

#include "../lexer/token.h"
#include <stdbool.h>
#include <stdint.h>

typedef enum {
    AST_PROGRAM,
    NODE_NUMBER,
    NODE_BINARY,
    NODE_STRING,
    NODE_IDENT,
    AST_VAR_DECL,
    AST_FUNC_DECL,
    AST_STRUCT_DECL,
    AST_CLASS_DECL,
    AST_BLOCK,
    AST_IF_STMT,
    AST_WHILE_STMT,
    AST_FOR_STMT,
    AST_RETURN_STMT,
    AST_EXPR_STMT,
    AST_BINARY_EXPR,
    AST_UNARY_EXPR,
    AST_LITERAL_EXPR,
    AST_IDENTIFIER_EXPR,
    AST_CALL_EXPR,
    AST_MEMBER_ACCESS,
    NODE_FLOAT_LIT,
    NODE_BOOL_LIT,
    NODE_CHAR_LIT,
    AST_FREE_STMT,
    AST_ALLOC_EXPR,
    AST_NEW_EXPR,
    NODE_CLASS_DECL,
    NODE_ENUM_DECL,
    NODE_UNION_DECL,
    NODE_EXTENDS,
    NODE_THIS,
    NODE_SUPER,
    NODE_IMPL,
    NODE_NAN_LIT,
    NODE_INF_LIT,
    AST_CAST_EXPR,
    AST_UNSAFE_BLOCK,
    AST_SLICE_EXPR,
    AST_DEFER_STMT,
    AST_GOTO_STMT,
    AST_LABEL_DECL,
    AST_EXPORT_DECL,
    AST_USE_DECL,
    AST_TRY_STMT,
    AST_THROW_STMT,
    AST_ASSERT_STMT,
    AST_ASM_STMT,
    AST_ASYNC_STMT,
    AST_PARALLEL_STMT,
    AST_AWAIT_STMT,
    AST_SPAWN_STMT,
    AST_STRUCT_LITERAL,
    AST_BREAK_STMT,
    AST_CONTINUE_STMT,
    AST_TERNARY_EXPR
} ASTNodeType;

typedef struct ASTNode {
    ASTNodeType type;
    Token token; // Representative token
    struct ASTNode** children;
    int child_count;
    int child_capacity;
    // For specific nodes
    char* string_value;
    int64_t int_value; /* 64-bit: integer literals and offsets (int is 64-bit) */
    float float_value;
    bool bool_value;
    bool is_volatile;
    char char_value;
} ASTNode;

ASTNode* ASTNode_create(ASTNodeType type, Token token);
void ASTNode_add_child(ASTNode* parent, ASTNode* child);
void ASTNode_free(ASTNode* node);
ASTNode* ASTNode_clone(ASTNode* node);

#endif // MAGNETAR_AST_H
