#include "semantic.h"
#include "../utils/diagnostics.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_NAMES 8192
#define MAX_VARS 8192

#define NAME_BUCKETS 8192

typedef struct {
    char** items;
    int* next;      /* index+1 of next item in the bucket, 0 = end */
    int heads[NAME_BUCKETS]; /* index+1 of bucket head, 0 = empty */
    int count;
} NameSet;

typedef struct {
    char* name;
    int type;
    int depth;
} Var;

static NameSet functions;
static NameSet globals;
static Var vars[MAX_VARS];
static int var_count = 0;
static int scope_depth = 0;
static int error_count = 0;

/* Names the frontend/backend implement without an `extern fn` declaration.
   The authoritative list is the AST plus this small set of intrinsics. */
static const char* const builtin_names[] = {
    "print", "len", "sizeof", "cast", "typeof", "move", "copy", "borrow",
    "clone", "assert", "exit", "printf", "print_str", "print_int",
    "print_float", "read_line", "nan", "inf", "this", "self", "super"
};

static unsigned name_hash(const char* name) {
    unsigned h = 2166136261u;
    for (const unsigned char* p = (const unsigned char*)name; *p; p++) {
        h ^= *p;
        h *= 16777619u;
    }
    return h & (NAME_BUCKETS - 1);
}

static void ns_init(NameSet* set) {
    set->items = NULL;
    set->next = NULL;
    set->count = 0;
    for (int i = 0; i < NAME_BUCKETS; i++) set->heads[i] = 0;
}

static void ns_add(NameSet* set, const char* name) {
    if (!name || !*name) return;
    unsigned bucket = name_hash(name);
    for (int link = set->heads[bucket]; link; link = set->next[link - 1])
        if (strcmp(set->items[link - 1], name) == 0) return;
    if (set->count >= MAX_NAMES) return;
    char** items = (char**)realloc(set->items, (size_t)(set->count + 1) * sizeof(char*));
    int* next = (int*)realloc(set->next, (size_t)(set->count + 1) * sizeof(int));
    if (!items || !next) return;
    set->items = items;
    set->next = next;
    set->items[set->count] = strdup(name);
    set->next[set->count] = set->heads[bucket];
    set->heads[bucket] = ++set->count;
}

static bool ns_has(const NameSet* set, const char* name) {
    if (!name || !*name) return false;
    unsigned bucket = name_hash(name);
    for (int link = set->heads[bucket]; link; link = set->next[link - 1])
        if (strcmp(set->items[link - 1], name) == 0) return true;
    return false;
}

static void ns_free(NameSet* set) {
    for (int i = 0; i < set->count; i++) free(set->items[i]);
    free(set->items);
    free(set->next);
    ns_init(set);
}

static bool is_builtin(const char* name) {
    if (!name) return false;
    for (size_t i = 0; i < sizeof(builtin_names) / sizeof(builtin_names[0]); i++)
        if (strcmp(name, builtin_names[i]) == 0) return true;
    return false;
}

static void enter_scope(void) { scope_depth++; }

static void leave_scope(void) {
    int write = 0;
    for (int i = 0; i < var_count; i++) {
        if (vars[i].depth == scope_depth) {
            free(vars[i].name);
            continue;
        }
        if (write != i) vars[write] = vars[i];
        write++;
    }
    var_count = write;
    if (scope_depth > 0) scope_depth--;
}

static void declare_var(const char* name, int type) {
    if (!name || !*name || var_count >= MAX_VARS) return;
    /* Redeclaration in the same scope keeps the first binding, matching the
       redefinition policy for globals. */
    for (int i = var_count - 1; i >= 0 && vars[i].depth == scope_depth; i--) {
        if (strcmp(vars[i].name, name) == 0) {
            vars[i].type = type;
            return;
        }
    }
    vars[var_count].name = strdup(name);
    vars[var_count].type = type;
    vars[var_count].depth = scope_depth;
    var_count++;
}

static int lookup_var(const char* name) {
    if (!name) return -1;
    for (int i = var_count - 1; i >= 0; i--)
        if (strcmp(vars[i].name, name) == 0) return vars[i].type;
    return -1;
}

static bool known_name(const char* name) {
    if (!name || !*name) return true; /* compiler-generated nodes */
    return ns_has(&functions, name) || ns_has(&globals, name) ||
           lookup_var(name) >= 0 || is_builtin(name);
}

static bool is_string_literal(ASTNode* n) {
    return n && ((n->type == NODE_STRING) ||
                 (n->type == AST_LITERAL_EXPR && n->token.type == TOK_STRING_LITERAL));
}

static void report(ASTNode* node, const char* message) {
    diag_report_error(node->token.line, node->token.column, message,
                      node->token.text ? node->token.text : "", NULL);
    error_count++;
}

static void check_assignment_type(ASTNode* lhs, ASTNode* rhs) {
    if (!lhs || !rhs || !is_string_literal(rhs)) return;
    if (lhs->type != AST_IDENTIFIER_EXPR && lhs->type != NODE_IDENT) return;
    int type = lookup_var(lhs->token.text);
    if (type == TOK_KW_INT || type == TOK_KW_FLOAT || type == TOK_KW_HALF ||
        type == TOK_KW_BOOL || type == TOK_KW_CHAR) {
        char msg[192];
        snprintf(msg, sizeof(msg),
                 "type mismatch: '%s' is numeric but is assigned a string literal",
                 lhs->token.text);
        report(lhs, msg);
    }
}

static void check_node(ASTNode* node);

static void check_children(ASTNode* node) {
    if (!node) return;
    for (int i = 0; i < node->child_count; i++) check_node(node->children[i]);
}

static void check_node(ASTNode* node) {
    if (!node) return;
    switch (node->type) {
        case AST_VAR_DECL: {
            int type = (int)node->int_value;
            declare_var(node->token.text, type);
            if (node->child_count > 0) {
                ASTNode* init = node->children[0];
                if (is_string_literal(init) &&
                    (type == TOK_KW_INT || type == TOK_KW_FLOAT ||
                     type == TOK_KW_HALF || type == TOK_KW_BOOL ||
                     type == TOK_KW_CHAR)) {
                    char msg[192];
                    snprintf(msg, sizeof(msg),
                             "type mismatch: '%s' is numeric but is initialized with a string literal",
                             node->token.text ? node->token.text : "variable");
                    report(node, msg);
                }
                check_children(node);
            }
            break;
        }
        case AST_FUNC_DECL:
            /* The body is checked by check_function below (params need a
               dedicated scope); avoid walking it twice. */
            break;
        case NODE_IMPL:
            /* `impl Type { ... }` stores Type (and an optional trait) as
               identifier children; those are type names, not variables. */
            break;
        case AST_IDENTIFIER_EXPR:
        case NODE_IDENT:
            if (!known_name(node->token.text)) {
                char msg[192];
                snprintf(msg, sizeof(msg), "undefined variable '%s'", node->token.text);
                report(node, msg);
            }
            break;
        case AST_CALL_EXPR: {
            ASTNode* callee = node->child_count > 0 ? node->children[0] : NULL;
            if (callee && callee->type == AST_IDENTIFIER_EXPR &&
                !known_name(callee->token.text)) {
                char msg[192];
                snprintf(msg, sizeof(msg), "undefined function '%s'", callee->token.text);
                report(callee, msg);
            }
            for (int i = 0; i < node->child_count; i++) check_node(node->children[i]);
            break;
        }
        case AST_MEMBER_ACCESS:
            /* Only the receiver is an identifier; the member name belongs to
               the struct/enum namespace. */
            if (node->child_count > 0) check_node(node->children[0]);
            break;
        case AST_BINARY_EXPR:
            if (node->token.type == TOK_ASSIGN && node->child_count > 1)
                check_assignment_type(node->children[0], node->children[1]);
            check_children(node);
            break;
        case AST_BLOCK:
            enter_scope();
            check_children(node);
            leave_scope();
            break;
        case AST_ASM_STMT:
            /* Inline asm stores raw text in literal children. */
            break;
        default:
            check_children(node);
            break;
    }
}

static void check_function(ASTNode* fn) {
    if (!fn || fn->child_count < 1) return;
    enter_scope();
    ASTNode* body = fn->children[fn->child_count - 1];
    /* Every child except the body is a parameter AST_VAR_DECL. */
    for (int i = 0; i < fn->child_count - 1; i++) {
        ASTNode* param = fn->children[i];
        if (param && param->type == AST_VAR_DECL)
            declare_var(param->token.text, (int)param->int_value);
    }
    if (body && body->type == AST_BLOCK) {
        check_children(body);
    } else {
        check_node(body);
    }
    leave_scope();
}

int semantic_check(ASTNode* program, const char* entry) {
    ns_init(&functions);
    ns_init(&globals);
    var_count = 0;
    scope_depth = 0;
    error_count = 0;

    if (!program) return 0;

    /* Collect every top-level declaration first: calling a function defined
       later in the file must keep working. */
    for (int i = 0; i < program->child_count; i++) {
        ASTNode* node = program->children[i];
        if (!node) continue;
        if (node->type == AST_FUNC_DECL) ns_add(&functions, node->token.text);
        else if (node->type == NODE_IMPL) {
            /* Methods are emitted as `Type_method`; make both spellings
               visible so sibling methods can call each other. */
            for (int j = 0; j < node->child_count; j++) {
                ASTNode* child = node->children[j];
                if (!child || child->type != AST_FUNC_DECL) continue;
                ns_add(&functions, child->token.text);
                const char* mangled = child->token.text;
                const char* sep = mangled ? strrchr(mangled, '_') : NULL;
                if (sep && sep[1]) ns_add(&functions, sep + 1);
            }
        }
        else if (node->type == AST_VAR_DECL) ns_add(&globals, node->token.text);
        else if (node->type == AST_STRUCT_DECL || node->type == AST_CLASS_DECL ||
                 node->type == NODE_CLASS_DECL || node->type == NODE_ENUM_DECL ||
                 node->type == NODE_UNION_DECL)
            ns_add(&globals, node->token.text);
    }

    bool has_entry = false;
    const char* wanted = (entry && *entry) ? entry : "main";
    for (int i = 0; i < program->child_count; i++) {
        ASTNode* node = program->children[i];
        if (!node) continue;
        if (node->type == AST_FUNC_DECL) {
            if (strcmp(node->token.text ? node->token.text : "", wanted) == 0)
                has_entry = true;
            check_function(node);
        } else if (node->type == AST_BLOCK) {
            check_node(node);
        } else {
            check_node(node);
        }
    }

    if (!has_entry && (!entry || !*entry))
        fprintf(stderr, "Warning: entry function 'main' was not defined; use `entry fn name()` or --entry <name>.\n");

    ns_free(&functions);
    ns_free(&globals);
    for (int i = 0; i < var_count; i++) free(vars[i].name);
    var_count = 0;
    return error_count;
}
