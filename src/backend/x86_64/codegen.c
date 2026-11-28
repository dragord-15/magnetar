#include "codegen.h"
#include "encoder.h"
#include "../../parser/struct_registry.h"
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <errno.h>

#define MAX_VARS 4096
typedef struct {
    char* name;
    int offset;
    int type;
    char* type_name;
    bool is_array;
    int array_size;
    bool is_volatile;
} VarEnv;

static VarEnv env[MAX_VARS];
static int env_count = 0;
/* Byte offset (magnitude below %rbp) of the next local variable. Locals
   start below the temporary region so the two can never overlap. */
static int current_stack = LOCALS_BASE;

static const char* current_class_name = NULL;
static const char* current_func_name = NULL;
/* When the current function returns a struct/tuple, %rax holds a hidden
   pointer to the caller-provided destination at entry. We stash it in a
   dedicated local slot (offset magnitude below %rbp, 0 when unused) so the
   `return` statement can copy the aggregate into it. */
static int current_sret_offset = 0;
static StructType* current_ret_struct = NULL;
/* Non-zero while generating the body of a spawn/async/parallel child, where
   `yield` means "finish this child and report the yielded value as its exit
   status" instead of the plain sched_yield used in the main process. */
static int child_context_depth = 0;
static ASTNode* active_defers[256];
static int active_defer_count = 0;

static const char* reachable_funcs[2048];
static int reachable_func_count = 0;

/* Name of the function the runtime calls after `_start`. Defaults to `main`
   but can be changed from the command line with `--entry <name>`. */
static char entry_func_name[256] = "main";
static bool entry_func_missing = false;

void AsmGen_set_entry_name(const char* name) {
    if (!name || !*name) {
        strcpy(entry_func_name, "main");
        return;
    }
    strncpy(entry_func_name, name, sizeof(entry_func_name) - 1);
    entry_func_name[sizeof(entry_func_name) - 1] = '\0';
}

typedef struct {
    char* var_name;
    char* label_name;
    int type;
    int initial_value;
    float initial_float;
    int size;               /* bytes reserved in the pool (structs > 8) */
    bool is_struct;         /* yields its ADDRESS on read, like a local struct */
    bool is_array;          /* yields its ADDRESS on read, like a local array */
    bool has_runtime_init;  /* initializer must run in the .ginit region */
    bool is_volatile;       /* every access must reach memory */
} StaticVarEntry;

static StaticVarEntry static_vars[2048];
static int static_var_count = 0;

static void generate_from_ast(AsmGen* gen, ASTNode* node);
static void emit_division_by_zero_guard(AsmGen* gen);

/* True when the function body contains a `return <value>;`. Reaching the end
   of a function without one leaves the return register undefined, so the
   value has to be pinned down explicitly. */
static bool ast_has_value_return(ASTNode* node) {
    if (!node) return false;
    if (node->type == AST_FUNC_DECL) return false; /* nested function */
    if (node->type == AST_RETURN_STMT) return node->child_count > 0;
    for (int i = 0; i < node->child_count; i++) {
        if (ast_has_value_return(node->children[i])) return true;
    }
    return false;
}

/* Releases the expression temporaries of the statement that just finished.
   Temporaries live in a small region below %rbp; without this reset every
   aggregate literal would keep its slot alive until the end of the function
   and eventually overflow into the local variables. */
static void temp_reset(AsmGen* gen) {
    gen->temp_stack_offset = 8;
}

static StaticVarEntry* lookup_static_var(const char* name) {
    if (!name) return NULL;
    for (int i = 0; i < static_var_count; i++) {
        if (strcmp(static_vars[i].var_name, name) == 0) {
            return &static_vars[i];
        }
    }
    return NULL;
}

static void ensure_task_statics(void) {
    if (!lookup_static_var("__task_pipes") && static_var_count < 2048) {
        StaticVarEntry* sv = &static_vars[static_var_count++];
        memset(sv, 0, sizeof(*sv));
        sv->var_name = strdup("__task_pipes");
        sv->label_name = strdup(".static_var_task_pipes");
        sv->type = TOK_KW_INT;
        sv->size = 256 * 24;
    }
    if (!lookup_static_var("__task_wfd") && static_var_count < 2048) {
        StaticVarEntry* sv = &static_vars[static_var_count++];
        memset(sv, 0, sizeof(*sv));
        sv->var_name = strdup("__task_wfd");
        sv->label_name = strdup(".static_var_task_wfd");
        sv->type = TOK_KW_INT;
        sv->size = 8;
    }
}

/* Register a file-scope (or `static`/`const`) variable declaration in the
   static pool. Literal int/float/bool/char initializers are baked into the
   pool image; anything else (string literal, expression, struct literal)
   is flagged so the .ginit region emits a runtime store before main. */
static StaticVarEntry* register_static_var(ASTNode* decl) {
    if (!decl || decl->type != AST_VAR_DECL || !decl->token.text) return NULL;
    StaticVarEntry* existing = lookup_static_var(decl->token.text);
    if (existing) return existing;
    if (static_var_count >= 2048) return NULL;

    char label[64];
    snprintf(label, sizeof(label), ".static_var_%d", static_var_count);
    StaticVarEntry* sv = &static_vars[static_var_count++];
    sv->var_name = strdup(decl->token.text);
    sv->label_name = strdup(label);
    sv->type = decl->int_value;
    sv->initial_value = 0;
    sv->initial_float = 0.0f;
    sv->size = 8;
    sv->is_struct = false;
    sv->is_array = false;
    sv->has_runtime_init = false;
    sv->is_volatile = decl->is_volatile;

    if (decl->string_value) {
        StructType* st = lookup_struct(decl->string_value);
        if (st && st->field_count > 0) {
            sv->is_struct = true;
            if (st->size > 8) sv->size = st->size;
        }
    }
    if (decl->int_value == TOK_KW_FIXED) {
        sv->is_array = true;
        if (decl->child_count > 0 && decl->children[0]->type == NODE_NUMBER)
            sv->size = 8 * decl->children[0]->int_value;
        if (sv->size < 8) sv->size = 8;
    }

    int init_idx = (decl->int_value == TOK_KW_FIXED) ? 1 : 0;
    if (decl->child_count > init_idx) {
        ASTNode* init = decl->children[init_idx];
        if (init->type == AST_LITERAL_EXPR && init->token.type != TOK_STRING_LITERAL) {
            sv->initial_value = init->int_value;
        } else if (init->type == NODE_FLOAT_LIT) {
            sv->initial_float = init->float_value;
        } else if (init->type == NODE_BOOL_LIT) {
            sv->initial_value = init->bool_value ? 1 : 0;
        } else if (init->type == NODE_CHAR_LIT) {
            sv->initial_value = (int)init->char_value;
        } else {
            sv->has_runtime_init = true;
        }
    }
    return sv;
}

/* Emit the runtime store for one file-scope initializer into the current
   (.ginit) region. Value lands in RAX (or XMM0 for floats). */
static void emit_global_runtime_init(AsmGen* gen, ASTNode* decl) {
    StaticVarEntry* sv = lookup_static_var(decl->token.text);
    if (!sv || !sv->has_runtime_init) return;
    int init_idx = (decl->int_value == TOK_KW_FIXED) ? 1 : 0;
    if (decl->child_count <= init_idx) return;
    ASTNode* init = decl->children[init_idx];

    if (init->type == AST_STRUCT_LITERAL && sv->is_struct) {
        StructType* st = lookup_struct(decl->string_value);
        if (!st) return;
        for (int i = 0; i < init->child_count && i < st->field_count; i++) {
            generate_from_ast(gen, init->children[i]);
            cg_emit_lea_reg_rip(gen->cg, REG_RCX, 0);
            pt_add_patch(gen->pt, cg_get_size(gen->cg) - 4, sv->label_name, false);
            if (st->fields[i].field_type == TOK_KW_FLOAT ||
                st->fields[i].field_type == TOK_KW_HALF) {
                cg_emit_movss_mem_xmm(gen->cg, REG_RCX, st->fields[i].offset, REG_XMM0);
            } else {
                cg_emit_mov_mem_reg(gen->cg, REG_RCX, st->fields[i].offset, REG_RAX);
            }
        }
        return;
    }

    generate_from_ast(gen, init);
    cg_emit_lea_reg_rip(gen->cg, REG_RCX, 0);
    pt_add_patch(gen->pt, cg_get_size(gen->cg) - 4, sv->label_name, false);
    if (sv->type == TOK_KW_FLOAT || sv->type == TOK_KW_HALF) {
        cg_emit_movss_mem_xmm(gen->cg, REG_RCX, 0, REG_XMM0);
    } else {
        cg_emit_mov_mem_reg(gen->cg, REG_RCX, 0, REG_RAX);
    }
}

typedef struct {
    char* name;
} ExternFunc;

#define MAX_EXTERN_FUNCS 1024
#define MAX_FUNC_ENTRIES 8192

static ExternFunc extern_funcs[MAX_EXTERN_FUNCS];
static int extern_func_count = 0;

typedef struct {
    char* name;
    int position;
    int return_type;
} FunctionEntry;

static FunctionEntry func_entries[MAX_FUNC_ENTRIES];
static int func_entry_count = 0;

static int get_var_offset(const char* name) {
    for (int i = env_count - 1; i >= 0; i--) {
        if (strcmp(env[i].name, name) == 0) return env[i].offset;
    }
    return 0; // Not found
}

static VarEnv* lookup_var_env(const char* name) {
    for (int i = env_count - 1; i >= 0; i--) {
        if (strcmp(env[i].name, name) == 0) return &env[i];
    }
    return NULL;
}

#if 0
static void dbg_env_dump(const char* tag, const char* name) {
    printf("  [env:%s] looking '%s' env_count=%d\n", tag, name, env_count);
    for (int i = 0; i < env_count; i++) {
        if (env[i].name && strcmp(env[i].name, name) == 0)
            printf("    match[%d] name='%s' offset=%d type=%d array=%d\n",
                   i, env[i].name, env[i].offset, env[i].type, env[i].is_array);
    }
}
#define DBG_ENV(tag, name) dbg_env_dump(tag, name)
#else
#define DBG_ENV(tag, name) ((void)0)
#endif

static int get_type_size(const char* name, int base_type) {
    if (base_type == TOK_KW_ANY) return 16;
    if (name && strcmp(name, "any") == 0) return 16;
    if (name) {
        StructType* st = lookup_struct(name);
        if (st) return st->size;
    }
    return 8;
}

/* Element stride used by `alloc<T>(n)` / `new T`. It must agree with
   sizeof(T) and with the parser's pointer-index stride. Local-stack sizing
   keeps the separate get_type_size() rules (pointers stay 8 bytes). */
static int alloc_elem_size(const char* name, int base_type) {
    if (base_type == TOK_KW_ANY || (name && strcmp(name, "any") == 0)) return 16;
    if (name) {
        StructType* st = lookup_struct(name);
        if (st) return st->size;
        if (strcmp(name, "char") == 0 || strcmp(name, "byte") == 0 ||
            strcmp(name, "bool") == 0) return 1;
        if (strcmp(name, "word") == 0) return 2;
        if (strcmp(name, "half") == 0 || strcmp(name, "dword") == 0 ||
            strcmp(name, "float") == 0) return 4;
    }
    switch (base_type) {
        case TOK_KW_CHAR: case TOK_KW_BYTE: case TOK_KW_BOOL: return 1;
        case TOK_KW_WORD: return 2;
        case TOK_KW_HALF: case TOK_KW_DWORD: case TOK_KW_FLOAT: return 4;
        default: return 8;
    }
}

static int lookup_field_offset(const char* field_name) {
    for (int i = 0; i < struct_type_count; i++) {
        int offset = get_field_offset(&struct_types[i], field_name);
        if (offset != -1) return offset;
    }
    return 0;
}

/* Resolves the byte offset of a field using the *declared* type of the base
   expression. Searching every struct in the program (lookup_field_offset)
   picked the first type that happened to own a field with that name, so two
   structs sharing a field name resolved to the wrong offset. */
static int resolve_field_offset(ASTNode* base, const char* field_name) {
    if (base && field_name) {
        const char* type_name = NULL;
        if (base->type == AST_IDENTIFIER_EXPR) {
            VarEnv* v = lookup_var_env(base->token.text);
            if (v) type_name = v->type_name;
        } else if (base->type == NODE_THIS) {
            type_name = current_class_name;
        } else if (base->type == NODE_SUPER) {
            type_name = lookup_parent_class(current_class_name);
        }
        while (type_name != NULL) {
            StructType* st = lookup_struct(type_name);
            if (st) {
                int off = get_field_offset(st, field_name);
                if (off != -1) return off;
            }
            type_name = lookup_parent_class(type_name);
        }
    }
    return lookup_field_offset(field_name);
}

static int get_var_type(const char* name) {
    for (int i = env_count - 1; i >= 0; i--) {
        if (strcmp(env[i].name, name) == 0) return env[i].type;
    }
    return 0;
}

static void add_var(const char* name, int offset, int type, const char* type_name) {
    if (env_count < MAX_VARS) {
        env[env_count].name = strdup(name);
        env[env_count].offset = offset;
        env[env_count].type = type;
        env[env_count].type_name = type_name ? strdup(type_name) : NULL;
        env[env_count].is_array = false;
        env[env_count].array_size = 0;
        env[env_count].is_volatile = false;
        env_count++;
    } else {
        fprintf(stderr, "[codegen] variable table full (MAX_VARS=%d); dropping '%s'\n", MAX_VARS, name);
    }
}

static const char* get_var_type_name(const char* name);

/* Finds the declared field behind a member access, following the
   inheritance chain of the base expression's type. Returns NULL when the
   field or the base type is unknown. */
static StructField* resolve_member_field(ASTNode* node) {
    if (!node || node->type != AST_MEMBER_ACCESS) return NULL;
    if (node->child_count < 1) return NULL;
    ASTNode* base = node->children[0];
    const char* type_name = NULL;
    if (base->type == AST_IDENTIFIER_EXPR) {
        VarEnv* var_env = lookup_var_env(base->token.text);
        if (var_env) type_name = var_env->type_name;
    } else if (base->type == NODE_THIS) {
        type_name = current_class_name;
    } else if (base->type == NODE_SUPER) {
        type_name = lookup_parent_class(current_class_name);
    }
    while (type_name != NULL) {
        StructType* st = lookup_struct(type_name);
        if (st) {
            StructField* f = find_field(st, node->token.text);
            if (f) return f;
        }
        type_name = lookup_parent_class(type_name);
    }
    return NULL;
}

// Returns true if a member access node reads a float field from a struct variable
static bool is_member_access_float(ASTNode* node) {
    StructField* f = resolve_member_field(node);
    return f ? (f->field_type == TOK_KW_FLOAT || f->field_type == TOK_KW_HALF) : false;
}

/* Returns true if the member access targets an array field (`int data[4];`).
   Such a field has to be handed out as an address, not as a value. */
static bool is_member_access_array(ASTNode* node) {
    StructField* f = resolve_member_field(node);
    return f ? (f->array_size > 0) : false;
}

static bool is_member_access_any(ASTNode* node) {
    StructField* f = resolve_member_field(node);
    return f ? (f->field_type == TOK_KW_ANY) : false;
}

static bool is_call_expr_float(ASTNode* node) {
    if (!node || node->type != AST_CALL_EXPR) return false;
    if (node->child_count < 1) return false;
    ASTNode* func_name = node->children[0];
    char mangled[256] = "";
    if (func_name->type == AST_MEMBER_ACCESS) {
        ASTNode* receiver = func_name->children[0];
        const char* method_name = func_name->token.text;
        const char* class_name = NULL;
        if (receiver->type == NODE_THIS) {
            class_name = current_class_name;
        } else if (receiver->type == NODE_SUPER) {
            class_name = lookup_parent_class(current_class_name);
        } else if (receiver->type == AST_IDENTIFIER_EXPR) {
            class_name = get_var_type_name(receiver->token.text);
        }
        const char* resolve_class = class_name;
        bool found = false;
        while (resolve_class != NULL) {
            snprintf(mangled, sizeof(mangled), "%s_%s", resolve_class, method_name);
            for (int f = 0; f < func_entry_count; f++) {
                if (strcmp(func_entries[f].name, mangled) == 0) {
                    if (func_entries[f].return_type == TOK_KW_FLOAT || func_entries[f].return_type == TOK_KW_HALF) {
                        return true;
                    }
                    found = true;
                    break;
                }
            }
            if (found) break;
            resolve_class = lookup_parent_class(resolve_class);
        }
    } else {
        if (func_name->token.text) {
            strncpy(mangled, func_name->token.text, sizeof(mangled) - 1);
            mangled[sizeof(mangled) - 1] = '\0';
            for (int f = 0; f < func_entry_count; f++) {
                if (strcmp(func_entries[f].name, mangled) == 0) {
                    return (func_entries[f].return_type == TOK_KW_FLOAT || func_entries[f].return_type == TOK_KW_HALF);
                }
            }
        }
    }
    return false;
}

static bool deref_is_float(ASTNode* node);

static bool is_float_expr(ASTNode* node) {
    if (!node) return false;
    if (node->type == NODE_FLOAT_LIT || node->type == NODE_NAN_LIT ||
        node->type == NODE_INF_LIT) return true;
    if (node->type == AST_IDENTIFIER_EXPR &&
        (get_var_type(node->token.text) == TOK_KW_FLOAT ||
         get_var_type(node->token.text) == TOK_KW_HALF)) return true;
    if (node->type == AST_MEMBER_ACCESS && is_member_access_float(node)) return true;
    if (node->type == AST_UNARY_EXPR) {
        if (node->token.type == TOK_STAR)
            return deref_is_float(node);
        if ((node->token.type == TOK_MINUS || node->token.type == TOK_PLUS) &&
            node->child_count > 0)
            return is_float_expr(node->children[0]);
    }
    if (node->type == AST_CALL_EXPR) {
        if (is_call_expr_float(node)) return true;
        if (node->children[0] && node->children[0]->token.text) {
            const char* nm = node->children[0]->token.text;
            return strcmp(nm, "pow") == 0 || strcmp(nm, "sin") == 0 ||
                   strcmp(nm, "cos") == 0 || strcmp(nm, "tan") == 0 ||
                   strcmp(nm, "sqrt") == 0 || strcmp(nm, "exp") == 0 ||
                   strcmp(nm, "log") == 0 || strcmp(nm, "rand_float") == 0;
        }
        return false;
    }
    if (node->type == AST_BINARY_EXPR) {
        switch (node->token.type) {
        case TOK_LT: case TOK_LE: case TOK_GT: case TOK_GE:
        case TOK_EQ: case TOK_NEQ:
        case TOK_AND: case TOK_OR:
            /* Comparisons and logical connectives evaluate to 0/1, which are
               integers -- printing them as a float produced garbage like
               "1.5000" for `1.5 < 2.5`. */
            return false;
        case TOK_ASSIGN:
            /* The value of an assignment is the value assigned. */
            return is_float_expr(node->children[1]);
        default:
            break;
        }
        /* An arithmetic operation is a float operation as soon as one of its
           operands is a float -- `1 + 2.5` is 3.5, not 3. */
        return is_float_expr(node->children[0]) || is_float_expr(node->children[1]);
    }
    if (node->type == AST_TERNARY_EXPR) {
        return (node->child_count > 1 && is_float_expr(node->children[1])) ||
               (node->child_count > 2 && is_float_expr(node->children[2]));
    }
    if (node->type == AST_UNARY_EXPR) {
        /* `-x` keeps the type of its operand. */
        if (node->token.type == TOK_MINUS || node->token.type == TOK_PLUS) {
            return node->child_count > 0 && is_float_expr(node->children[0]);
        }
        return false;
    }
    return false;
}

/* True when every branch of the expression yields a string pointer -- lets
   `print(c ? "a" : "b")` pick the runtime string printer instead of printing
   the pointer as an integer. */
static bool is_string_expr(ASTNode* node) {
    if (!node) return false;
    if (node->type == AST_LITERAL_EXPR && node->token.type == TOK_STRING_LITERAL) return true;
    if (node->type == AST_IDENTIFIER_EXPR) return get_var_type(node->token.text) == TOK_KW_STRING;
    /* `arr[i]` is rewritten to `*(arr + i*8)`. The parser tags that deref
       with the element type so a `string[]` slot is treated as text. */
    if (node->type == AST_UNARY_EXPR && node->token.type == TOK_STAR &&
        node->int_value == TOK_KW_STRING)
        return true;
    if (node->type == AST_MEMBER_ACCESS) {
        StructField* f = resolve_member_field(node);
        /* An array field decays to an address, not a string value. */
        if (f && f->array_size == 0 && f->field_type == TOK_KW_STRING)
            return true;
    }
    if (node->type == AST_CAST_EXPR && node->int_value == TOK_KW_STRING)
        return true;
    if (node->type == AST_TERNARY_EXPR)
        return node->child_count > 2 && is_string_expr(node->children[1]) &&
               is_string_expr(node->children[2]);
    if (node->type == AST_BINARY_EXPR && node->token.type == TOK_PLUS &&
        node->child_count >= 2 && is_string_expr(node->children[0]) &&
        is_string_expr(node->children[1]))
        return true;
    return false;
}

/* `any` stores its payload in the first 8 bytes of the slot and a small type
   tag in the second 8 bytes. The payload keeps the existing scalar layout, so
   code that only reads the value still works; `print` uses the tag to pick
   the right formatter. */
#define ANY_TAG_INT    0
#define ANY_TAG_FLOAT  1
#define ANY_TAG_STRING 2
#define ANY_TAG_BOOL   3
#define ANY_TAG_CHAR   4
#define ANY_TAG_PTR    5

/* Mirror of is_string_expr for booleans: `print(c ? true : false)`. */
static bool is_bool_expr(ASTNode* node) {
    if (!node) return false;
    if (node->type == NODE_BOOL_LIT) return true;
    if (node->type == AST_IDENTIFIER_EXPR) return get_var_type(node->token.text) == TOK_KW_BOOL;
    if (node->type == AST_TERNARY_EXPR)
        return node->child_count > 2 && is_bool_expr(node->children[1]) &&
               is_bool_expr(node->children[2]);
    return false;
}

/* Structs, arrays and raw pointers are stored in an any box as their
   address; the PTR tag lets conversions and casts treat them as references
   instead of integers. */
static bool is_pointerish_expr(ASTNode* node) {
    if (!node) return false;
    if (node->type == AST_IDENTIFIER_EXPR) {
        VarEnv* v = lookup_var_env(node->token.text);
        if (v) {
            if (v->is_array) return true;
            if (v->type_name && lookup_struct(v->type_name)) return true;
            if (v->type == TOK_KW_PTR || v->type == TOK_KW_REF ||
                v->type == TOK_KW_OWN || v->type == TOK_KW_RAW)
                return true;
        }
        StaticVarEntry* sv = lookup_static_var(node->token.text);
        if (sv) {
            if (sv->is_array || sv->is_struct) return true;
            if (sv->type == TOK_KW_PTR || sv->type == TOK_KW_REF ||
                sv->type == TOK_KW_OWN || sv->type == TOK_KW_RAW)
                return true;
        }
    }
    if (node->type == AST_MEMBER_ACCESS) {
        StructField* f = resolve_member_field(node);
        if (f && (f->array_size > 0 || f->field_type == TOK_KW_STRUCT))
            return true;
    }
    return false;
}

static int any_tag_for_expr(ASTNode* node) {
    if (is_float_expr(node)) return ANY_TAG_FLOAT;
    if (is_string_expr(node)) return ANY_TAG_STRING;
    if (is_bool_expr(node) || node->type == NODE_BOOL_LIT) return ANY_TAG_BOOL;
    if (node->type == NODE_CHAR_LIT ||
        (node->type == AST_IDENTIFIER_EXPR &&
         get_var_type(node->token.text) == TOK_KW_CHAR))
        return ANY_TAG_CHAR;
    if (is_pointerish_expr(node)) return ANY_TAG_PTR;
    return ANY_TAG_INT;
}

/* Synthetic two-field aggregate used for the 16-byte `any` value: payload at
   offset 0 and tag at offset 8. This lets calls/returns reuse the existing
   struct sret path. */
static StructType* any_struct_type(void) {
    static StructType st;
    static int initialized = 0;
    if (!initialized) {
        initialized = 1;
        memset(&st, 0, sizeof(st));
        st.name = (char*)"any";
        st.field_count = 2;
        st.size = 16;
        st.fields[0].name = (char*)"value";
        st.fields[0].offset = 0;
        st.fields[0].field_type = TOK_KW_INT;
        st.fields[1].name = (char*)"tag";
        st.fields[1].offset = 8;
        st.fields[1].field_type = TOK_KW_INT;
    }
    return &st;
}

static StructType* ret_struct_for(const char* name) {
    if (name && strcmp(name, "any") == 0) return any_struct_type();
    return name ? lookup_struct(name) : NULL;
}

static bool expr_is_any(ASTNode* node) {
    if (!node) return false;
    if (node->type == AST_IDENTIFIER_EXPR)
        return get_var_type(node->token.text) == TOK_KW_ANY;
    if (node->type == AST_MEMBER_ACCESS) {
        StructField* f = resolve_member_field(node);
        /* An `any` array field decays to the address of its first slot. */
        return f && f->field_type == TOK_KW_ANY && f->array_size == 0;
    }
    if (node->type == AST_UNARY_EXPR && node->token.type == TOK_STAR &&
        node->int_value == TOK_KW_ANY)
        return true;
    if (node->type == AST_CALL_EXPR && node->string_value &&
        strcmp(node->string_value, "any") == 0)
        return true;
    return false;
}

/* Assignable any locations: variables, struct/class fields and array slots. */
static bool is_any_lvalue(ASTNode* node) {
    if (!node) return false;
    if (node->type == AST_IDENTIFIER_EXPR)
        return get_var_type(node->token.text) == TOK_KW_ANY;
    if (node->type == AST_MEMBER_ACCESS) {
        StructField* f = resolve_member_field(node);
        return f && f->field_type == TOK_KW_ANY && f->array_size == 0;
    }
    return node->type == AST_UNARY_EXPR && node->token.type == TOK_STAR &&
           node->int_value == TOK_KW_ANY;
}

/* Put the address of the 16-byte tagged value in RAX. */
static bool gen_any_address(AsmGen* gen, ASTNode* node) {
    if (!node) return false;
    if (node->type == AST_IDENTIFIER_EXPR) {
        VarEnv* v = lookup_var_env(node->token.text);
        if (v && v->type == TOK_KW_ANY) {
            cg_emit_lea_reg_mem(gen->cg, REG_RAX, REG_RBP, v->offset);
            return true;
        }
        return false;
    }
    if (node->type == AST_MEMBER_ACCESS && expr_is_any(node)) {
        generate_from_ast(gen, node);
        return true;
    }
    if (node->type == AST_UNARY_EXPR && node->token.type == TOK_STAR &&
        node->int_value == TOK_KW_ANY) {
        generate_from_ast(gen, node);
        return true;
    }
    if (node->type == AST_CALL_EXPR && node->string_value &&
        strcmp(node->string_value, "any") == 0) {
        generate_from_ast(gen, node);
        return true;
    }
    return false;
}

static bool is_any_expr(ASTNode* node);
static void gen_any_value(AsmGen* gen, ASTNode* node);
static void emit_any_binary(AsmGen* gen, ASTNode* node);

static bool is_any_compound_op(TokenType op) {
    return op == TOK_ASSIGN || op == TOK_PLUS_ASSIGN ||
           op == TOK_MINUS_ASSIGN || op == TOK_STAR_ASSIGN ||
           op == TOK_SLASH_ASSIGN || op == TOK_MOD_ASSIGN ||
           op == TOK_SHL_ASSIGN || op == TOK_SHR_ASSIGN ||
           op == TOK_AND_ASSIGN || op == TOK_OR_ASSIGN ||
           op == TOK_XOR_ASSIGN;
}

/* An expression whose value is known to be a tagged `any` box. Besides a
   plain any variable or an any-returning call, an operation with any
   operand also carries a runtime tag. */
static bool is_any_expr(ASTNode* node) {
    if (!node) return false;
    if (expr_is_any(node)) return true;
    if (node->type == AST_BINARY_EXPR && !is_any_compound_op(node->token.type))
        return is_any_expr(node->child_count > 0 ? node->children[0] : NULL) ||
               is_any_expr(node->child_count > 1 ? node->children[1] : NULL);
    if (node->type == AST_CAST_EXPR && node->int_value == TOK_KW_ANY)
        return true;
    return false;
}

/* Leave the payload in RAX and the runtime tag in RDX. Non-any operands use
   their static tag; float values are stored as 32-bit IEEE bits, matching the
   representation used when an any box is built. */
static void emit_any_operand(AsmGen* gen, ASTNode* node) {
    if (is_any_expr(node)) {
        gen_any_value(gen, node);
        cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RAX, 8);
        cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RAX, 0);
        return;
    }
    int tag = any_tag_for_expr(node);
    generate_from_ast(gen, node);
    if (tag == ANY_TAG_FLOAT)
        cg_emit_movd_xmm_to_gpr(gen->cg, REG_RAX, REG_XMM0);
    cg_emit_mov_reg_imm32(gen->cg, REG_RDX, (uint32_t)tag);
}

static void emit_any_to_float(AsmGen* gen, X64Register payload_reg,
                              X64Register tag_reg, X64Register xmm) {
    char conv[64], done[64];
    int id = gen->label_counter++;
    snprintf(conv, sizeof(conv), ".any_conv_%d", id);
    snprintf(done, sizeof(done), ".any_conv_done_%d", id);
    cg_emit_cmp_reg_imm32(gen->cg, tag_reg, ANY_TAG_FLOAT);
    cg_emit_jne_label(gen->cg, gen->pt, conv);
    cg_emit_movd_gpr_to_xmm(gen->cg, xmm, payload_reg);
    cg_emit_jmp_label(gen->cg, gen->pt, done);
    cg_emit_label(gen->cg, gen->pt, conv);
    cg_emit_cvtsi2ss_xmm_reg(gen->cg, xmm, payload_reg);
    cg_emit_label(gen->cg, gen->pt, done);
}

static uint8_t any_int_setcc(TokenType op) {
    if (op == TOK_LT) return 0x9C;
    if (op == TOK_LE) return 0x9E;
    if (op == TOK_GT) return 0x9F;
    if (op == TOK_GE) return 0x9D;
    if (op == TOK_EQ) return 0x94;
    return 0x95;
}

static uint8_t any_float_setcc(TokenType op) {
    if (op == TOK_LT) return 0x92;
    if (op == TOK_LE) return 0x96;
    if (op == TOK_GT) return 0x97;
    if (op == TOK_GE) return 0x93;
    if (op == TOK_EQ) return 0x94;
    return 0x95;
}

static void emit_setcc_al_movzx(AsmGen* gen, uint8_t cc) {
    uint8_t* buf = cg_get_buffer(gen->cg);
    int sz = cg_get_size(gen->cg);
    buf[sz++] = 0x0F; buf[sz++] = cc; buf[sz++] = 0xC0;
    buf[sz++] = 0x48; buf[sz++] = 0x0F; buf[sz++] = 0xB6; buf[sz++] = 0xC0;
    gen->cg->size = sz;
}

static void emit_any_compare_result(AsmGen* gen, TokenType op,
                                    X64Register src_a, X64Register src_b) {
    cg_emit_cmp_reg_reg(gen->cg, src_a, src_b);
    emit_setcc_al_movzx(gen, any_int_setcc(op));
}

static void emit_any_float_compare_result(AsmGen* gen, TokenType op) {
    uint8_t* buf = cg_get_buffer(gen->cg);
    int sz = cg_get_size(gen->cg);
    buf[sz++] = 0x0F; buf[sz++] = 0x2E; buf[sz++] = 0xC1; /* ucomiss xmm0,xmm1 */
    gen->cg->size = sz;
    emit_setcc_al_movzx(gen, any_float_setcc(op));
}

static void emit_any_string_compare_result(AsmGen* gen, TokenType op) {
    cg_emit_test_reg_reg(gen->cg, REG_RAX, REG_RAX);
    emit_setcc_al_movzx(gen, any_int_setcc(op));
}

/* Runtime-dispatch an arithmetic or comparison expression with at least one
   `any` operand. Result: payload in RAX, tag in RDX. */
static void emit_any_binary(AsmGen* gen, ASTNode* node) {
    ASTNode* lhs = node->children[0];
    ASTNode* rhs = node->children[1];
    TokenType op = node->token.type;
    bool is_cmp = (op == TOK_EQ || op == TOK_NEQ || op == TOK_LT ||
                   op == TOK_LE || op == TOK_GT || op == TOK_GE);
    bool is_arith = (op == TOK_PLUS || op == TOK_MINUS || op == TOK_STAR ||
                     op == TOK_SLASH || op == TOK_MOD);

    int id = gen->label_counter++;
    char l_float[64], l_string[64], l_int[64], l_done[64];
    snprintf(l_float, sizeof(l_float), ".any_float_%d", id);
    snprintf(l_string, sizeof(l_string), ".any_string_%d", id);
    snprintf(l_int, sizeof(l_int), ".any_int_%d", id);
    snprintf(l_done, sizeof(l_done), ".any_bin_done_%d", id);

    emit_any_operand(gen, lhs);          /* RAX = lhs payload, RDX = lhs tag */
    cg_emit_push_reg(gen->cg, REG_RDX);
    cg_emit_push_reg(gen->cg, REG_RAX);
    emit_any_operand(gen, rhs);          /* RAX = rhs payload, RDX = rhs tag */
    cg_emit_mov_reg_reg(gen->cg, REG_RCX, REG_RDX);
    cg_emit_pop_reg(gen->cg, REG_RDI);   /* lhs payload */
    cg_emit_pop_reg(gen->cg, REG_RSI);   /* lhs tag */

    if (is_arith || is_cmp) {
        cg_emit_cmp_reg_imm32(gen->cg, REG_RSI, ANY_TAG_FLOAT);
        cg_emit_je_label(gen->cg, gen->pt, l_float);
        cg_emit_cmp_reg_imm32(gen->cg, REG_RCX, ANY_TAG_FLOAT);
        cg_emit_je_label(gen->cg, gen->pt, l_float);
        if (op == TOK_PLUS || is_cmp) {
            cg_emit_cmp_reg_imm32(gen->cg, REG_RSI, ANY_TAG_STRING);
            cg_emit_jne_label(gen->cg, gen->pt, l_int);
            cg_emit_cmp_reg_imm32(gen->cg, REG_RCX, ANY_TAG_STRING);
            cg_emit_jne_label(gen->cg, gen->pt, l_int);
            cg_emit_jmp_label(gen->cg, gen->pt, l_string);
        } else {
            cg_emit_jmp_label(gen->cg, gen->pt, l_int);
        }
    } else {
        cg_emit_jmp_label(gen->cg, gen->pt, l_int);
    }

    /* Float path: convert each operand to XMM registers, then apply the op. */
    cg_emit_label(gen->cg, gen->pt, l_float);
    emit_any_to_float(gen, REG_RDI, REG_RSI, REG_XMM0);
    emit_any_to_float(gen, REG_RAX, REG_RCX, REG_XMM1);
    if (is_cmp) {
        emit_any_float_compare_result(gen, op);
        cg_emit_xor_reg_reg(gen->cg, REG_RDX, REG_RDX);
    } else if (op == TOK_PLUS) {
        cg_emit_addss_xmm_xmm(gen->cg, REG_XMM0, REG_XMM1);
        cg_emit_movd_xmm_to_gpr(gen->cg, REG_RAX, REG_XMM0);
        cg_emit_mov_reg_imm32(gen->cg, REG_RDX, ANY_TAG_FLOAT);
    } else if (op == TOK_MINUS) {
        cg_emit_subss_xmm_xmm(gen->cg, REG_XMM0, REG_XMM1);
        cg_emit_movd_xmm_to_gpr(gen->cg, REG_RAX, REG_XMM0);
        cg_emit_mov_reg_imm32(gen->cg, REG_RDX, ANY_TAG_FLOAT);
    } else if (op == TOK_STAR) {
        cg_emit_mulss_xmm_xmm(gen->cg, REG_XMM0, REG_XMM1);
        cg_emit_movd_xmm_to_gpr(gen->cg, REG_RAX, REG_XMM0);
        cg_emit_mov_reg_imm32(gen->cg, REG_RDX, ANY_TAG_FLOAT);
    } else if (op == TOK_SLASH) {
        cg_emit_divss_xmm_xmm(gen->cg, REG_XMM0, REG_XMM1);
        cg_emit_movd_xmm_to_gpr(gen->cg, REG_RAX, REG_XMM0);
        cg_emit_mov_reg_imm32(gen->cg, REG_RDX, ANY_TAG_FLOAT);
    } else {
        /* `%` on floats falls back to integer semantics on the raw payloads. */
        cg_emit_jmp_label(gen->cg, gen->pt, l_int);
    }
    if (is_cmp || (is_arith && op != TOK_MOD))
        cg_emit_jmp_label(gen->cg, gen->pt, l_done);

    /* String path: concatenation or lexicographic comparison. */
    cg_emit_label(gen->cg, gen->pt, l_string);
    cg_emit_push_reg(gen->cg, REG_RAX);   /* rhs */
    cg_emit_push_reg(gen->cg, REG_RDI);   /* lhs */
    cg_emit_call_rel32(gen->cg, 0);
    if (op == TOK_PLUS) {
        pt_add_patch(gen->pt, cg_get_size(gen->cg) - 4, "__str_concat", false);
        cg_emit_add_reg_imm32(gen->cg, REG_RSP, 16);
        cg_emit_mov_reg_imm32(gen->cg, REG_RDX, ANY_TAG_STRING);
    } else {
        pt_add_patch(gen->pt, cg_get_size(gen->cg) - 4, "__str_cmp", false);
        cg_emit_add_reg_imm32(gen->cg, REG_RSP, 16);
        emit_any_string_compare_result(gen, op);
        cg_emit_xor_reg_reg(gen->cg, REG_RDX, REG_RDX);
    }
    cg_emit_jmp_label(gen->cg, gen->pt, l_done);

    /* Integer path. */
    cg_emit_label(gen->cg, gen->pt, l_int);
    cg_emit_mov_reg_reg(gen->cg, REG_RCX, REG_RAX); /* rhs payload */
    cg_emit_mov_reg_reg(gen->cg, REG_RAX, REG_RDI); /* lhs payload */
    if (op == TOK_PLUS) cg_emit_add_reg_reg(gen->cg, REG_RAX, REG_RCX);
    else if (op == TOK_MINUS) cg_emit_sub_reg_reg(gen->cg, REG_RAX, REG_RCX);
    else if (op == TOK_STAR) cg_emit_imul_reg_reg(gen->cg, REG_RAX, REG_RCX);
    else if (op == TOK_SLASH || op == TOK_MOD) {
        emit_division_by_zero_guard(gen);
        uint8_t* qbuf = cg_get_buffer(gen->cg);
        int qsz = cg_get_size(gen->cg);
        qbuf[qsz++] = 0x48; qbuf[qsz++] = 0x99; /* cqo */
        gen->cg->size = qsz;
        cg_emit_idiv_reg(gen->cg, REG_RCX);
        if (op == TOK_MOD) cg_emit_mov_reg_reg(gen->cg, REG_RAX, REG_RDX);
    } else if (is_cmp) {
        emit_any_compare_result(gen, op, REG_RAX, REG_RCX);
    } else {
        cg_emit_mov_reg_reg(gen->cg, REG_RAX, REG_RDI);
    }
    cg_emit_xor_reg_reg(gen->cg, REG_RDX, REG_RDX);
    cg_emit_label(gen->cg, gen->pt, l_done);
}

/* Materialise a tagged any value and leave its address in RAX. */
static void gen_any_value(AsmGen* gen, ASTNode* node) {
    if (node && node->type == AST_CAST_EXPR &&
        node->int_value == TOK_KW_ANY && node->child_count > 0) {
        gen_any_value(gen, node->children[0]);
        return;
    }
    if (expr_is_any(node)) {
        gen_any_address(gen, node);
        return;
    }
    if (node && node->type == AST_BINARY_EXPR &&
        !is_any_compound_op(node->token.type) &&
        (is_any_expr(node->children[0]) ||
         (node->child_count > 1 && is_any_expr(node->children[1])))) {
        emit_any_binary(gen, node); /* RAX payload, RDX tag */
    } else {
        int tag = any_tag_for_expr(node);
        generate_from_ast(gen, node);
        if (tag == ANY_TAG_FLOAT)
            cg_emit_movd_xmm_to_gpr(gen->cg, REG_RAX, REG_XMM0);
        cg_emit_mov_reg_imm32(gen->cg, REG_RDX, (uint32_t)tag);
    }
    gen->temp_stack_offset = (gen->temp_stack_offset + 7) & ~7;
    gen->temp_stack_offset += 16;
    int off = -gen->temp_stack_offset;
    cg_emit_mov_mem_reg(gen->cg, REG_RBP, off, REG_RAX);
    cg_emit_mov_mem_reg(gen->cg, REG_RBP, off + 8, REG_RDX);
    cg_emit_lea_reg_mem(gen->cg, REG_RAX, REG_RBP, off);
}

/* Emit a pipe + fork pair used by spawn/async. The child keeps the write end
   in `__task_wfd` so `yield value` can hand a full 64-bit result back; the
   parent records pid -> read-end in `__task_pipes`. */
static void emit_task_fork(AsmGen* gen, ASTNode* block, const char* prefix) {
    ensure_task_statics();
    gen->temp_stack_offset = (gen->temp_stack_offset + 7) & ~7;
    int fds_off = -gen->temp_stack_offset;
    gen->temp_stack_offset += 8;

    char parent_lbl[64];
    snprintf(parent_lbl, sizeof(parent_lbl), ".%s_parent_%d", prefix,
             gen->label_counter++);

    cg_emit_lea_reg_mem(gen->cg, REG_RDI, REG_RBP, fds_off);
    cg_emit_mov_reg_imm32(gen->cg, REG_RAX, 22); /* pipe */
    cg_emit_syscall(gen->cg);

    cg_emit_mov_reg_imm32(gen->cg, REG_RAX, 57); /* fork */
    cg_emit_syscall(gen->cg);
    cg_emit_test_reg_reg(gen->cg, REG_RAX, REG_RAX);
    cg_emit_jne_label(gen->cg, gen->pt, parent_lbl);

    /* Child: close the read end, remember the write end, run the block. */
    cg_emit_mov_reg_mem32(gen->cg, REG_RDI, REG_RBP, fds_off);
    cg_emit_mov_reg_imm32(gen->cg, REG_RAX, 3); /* close */
    cg_emit_syscall(gen->cg);
    StaticVarEntry* wfd = lookup_static_var("__task_wfd");
    if (wfd) {
        cg_emit_lea_reg_rip(gen->cg, REG_R8, 0);
        pt_add_patch(gen->pt, cg_get_size(gen->cg) - 4, wfd->label_name, false);
        cg_emit_mov_reg_mem32(gen->cg, REG_R9, REG_RBP, fds_off + 4);
        cg_emit_mov_mem_reg(gen->cg, REG_R8, 0, REG_R9);
    }
    child_context_depth++;
    if (block) generate_from_ast(gen, block);
    child_context_depth--;
    cg_emit_mov_reg_imm32(gen->cg, REG_RDI, 0);
    cg_emit_mov_reg_imm32(gen->cg, REG_RAX, 60); /* exit */
    cg_emit_syscall(gen->cg);

    /* Parent: store pid/read-end, close the write end, leave pid in RAX. */
    cg_emit_label(gen->cg, gen->pt, parent_lbl);
    cg_emit_mov_reg_reg(gen->cg, REG_R10, REG_RAX);
    StaticVarEntry* pipes = lookup_static_var("__task_pipes");
    if (pipes) {
        cg_emit_mov_reg_reg(gen->cg, REG_R11, REG_R10);
        uint8_t* buf = cg_get_buffer(gen->cg);
        int sz = cg_get_size(gen->cg);
        buf[sz++] = 0x49; buf[sz++] = 0x81; buf[sz++] = 0xE3; /* and r11, imm32 */
        buf[sz++] = 0xFF; buf[sz++] = 0x00; buf[sz++] = 0x00; buf[sz++] = 0x00;
        gen->cg->size = sz;
        cg_emit_imul_reg_imm32(gen->cg, REG_R11, REG_R11, 24);
        cg_emit_lea_reg_rip(gen->cg, REG_R8, 0);
        pt_add_patch(gen->pt, cg_get_size(gen->cg) - 4, pipes->label_name, false);
        cg_emit_add_reg_reg(gen->cg, REG_R8, REG_R11);
        cg_emit_mov_mem_reg(gen->cg, REG_R8, 0, REG_R10);
        cg_emit_mov_reg_mem32(gen->cg, REG_R9, REG_RBP, fds_off);
        cg_emit_mov_mem_reg(gen->cg, REG_R8, 8, REG_R9);
    }
    cg_emit_mov_reg_mem32(gen->cg, REG_RDI, REG_RBP, fds_off + 4);
    cg_emit_mov_reg_imm32(gen->cg, REG_RAX, 3); /* close */
    cg_emit_syscall(gen->cg);
    cg_emit_mov_reg_reg(gen->cg, REG_RAX, REG_R10);
}

/* Wait for a task (pid in RAX, or any child when wait_any is true) and leave
   its yielded 64-bit value in RAX, falling back to the exit status. */
static void emit_task_join(AsmGen* gen, bool wait_any) {
    ensure_task_statics();
    if (wait_any)
        cg_emit_mov_reg_imm64(gen->cg, REG_RDI, (uint64_t)-1);
    else
        cg_emit_mov_reg_reg(gen->cg, REG_RDI, REG_RAX);

    gen->temp_stack_offset = (gen->temp_stack_offset + 7) & ~7;
    int status_off = -gen->temp_stack_offset;
    gen->temp_stack_offset += 8;
    gen->temp_stack_offset = (gen->temp_stack_offset + 7) & ~7;
    int buf_off = -gen->temp_stack_offset;
    gen->temp_stack_offset += 8;

    cg_emit_lea_reg_mem(gen->cg, REG_RSI, REG_RBP, status_off);
    cg_emit_mov_reg_imm32(gen->cg, REG_RDX, 0);
    cg_emit_mov_reg_imm32(gen->cg, REG_R10, 0);
    cg_emit_mov_reg_imm32(gen->cg, REG_RAX, 61); /* wait4 */
    cg_emit_syscall(gen->cg);

    char fail_lbl[64], done_lbl[64], nopipe_lbl[64];
    int id = gen->label_counter++;
    snprintf(fail_lbl, sizeof(fail_lbl), ".join_fail_%d", id);
    snprintf(done_lbl, sizeof(done_lbl), ".join_done_%d", id);
    snprintf(nopipe_lbl, sizeof(nopipe_lbl), ".join_nopipe_%d", id);
    cg_emit_test_reg_reg(gen->cg, REG_RAX, REG_RAX);
    cg_emit_jl_label(gen->cg, gen->pt, fail_lbl);

    StaticVarEntry* pipes = lookup_static_var("__task_pipes");
    if (pipes) {
        cg_emit_mov_reg_reg(gen->cg, REG_R10, REG_RAX);
        cg_emit_mov_reg_reg(gen->cg, REG_R11, REG_R10);
        uint8_t* pbuf = cg_get_buffer(gen->cg);
        int psz = cg_get_size(gen->cg);
        pbuf[psz++] = 0x49; pbuf[psz++] = 0x81; pbuf[psz++] = 0xE3;
        pbuf[psz++] = 0xFF; pbuf[psz++] = 0x00; pbuf[psz++] = 0x00; pbuf[psz++] = 0x00;
        gen->cg->size = psz;
        cg_emit_imul_reg_imm32(gen->cg, REG_R11, REG_R11, 24);
        cg_emit_lea_reg_rip(gen->cg, REG_R8, 0);
        pt_add_patch(gen->pt, cg_get_size(gen->cg) - 4, pipes->label_name, false);
        cg_emit_add_reg_reg(gen->cg, REG_R8, REG_R11);
        cg_emit_mov_reg_mem(gen->cg, REG_R9, REG_R8, 0);
        cg_emit_cmp_reg_reg(gen->cg, REG_R9, REG_R10);
        cg_emit_jne_label(gen->cg, gen->pt, nopipe_lbl);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_R8, 8);
        cg_emit_test_reg_reg(gen->cg, REG_RDI, REG_RDI);
        cg_emit_jl_label(gen->cg, gen->pt, nopipe_lbl);
        cg_emit_lea_reg_mem(gen->cg, REG_RSI, REG_RBP, buf_off);
        cg_emit_mov_reg_imm32(gen->cg, REG_RDX, 8);
        cg_emit_xor_reg_reg(gen->cg, REG_RAX, REG_RAX);
        cg_emit_syscall(gen->cg); /* read */
        cg_emit_cmp_reg_imm32(gen->cg, REG_RAX, 8);
        cg_emit_jne_label(gen->cg, gen->pt, nopipe_lbl);
        cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, buf_off);
        cg_emit_mov_reg_imm32(gen->cg, REG_R9, 0);
        cg_emit_mov_mem_reg(gen->cg, REG_R8, 0, REG_R9);
        cg_emit_jmp_label(gen->cg, gen->pt, done_lbl);
        cg_emit_label(gen->cg, gen->pt, nopipe_lbl);
    }
    cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, status_off);
    /* status >> 8 & 0xff is the normal exit code. */
    cg_emit_byte(gen->cg, 0x48); cg_emit_byte(gen->cg, 0xC1); cg_emit_byte(gen->cg, 0xE8); cg_emit_byte(gen->cg, 0x08);
    cg_emit_byte(gen->cg, 0x48); cg_emit_byte(gen->cg, 0x25);
    cg_emit_byte(gen->cg, 0xFF); cg_emit_byte(gen->cg, 0x00);
    cg_emit_byte(gen->cg, 0x00); cg_emit_byte(gen->cg, 0x00);
    cg_emit_jmp_label(gen->cg, gen->pt, done_lbl);
    cg_emit_label(gen->cg, gen->pt, fail_lbl);
    cg_emit_mov_reg_imm64(gen->cg, REG_RAX, (uint64_t)-1);
    cg_emit_label(gen->cg, gen->pt, done_lbl);
}

/* Parameter types are needed at call sites to know whether an `any` argument
   must be pushed as two words (payload + tag). */
#define MAX_SIG_PARAMS 32
typedef struct {
    char* name;
    int param_count;
    int param_types[MAX_SIG_PARAMS];
} FuncSig;

static FuncSig func_sigs[MAX_FUNC_ENTRIES];
static int func_sig_count = 0;

static FuncSig* lookup_func_sig(const char* name, int argc) {
    FuncSig* fallback = NULL;
    for (int i = 0; i < func_sig_count; i++) {
        if (strcmp(func_sigs[i].name, name) != 0) continue;
        if (func_sigs[i].param_count == argc) return &func_sigs[i];
        if (!fallback) fallback = &func_sigs[i];
    }
    return fallback;
}

static void register_func_sig(ASTNode* fn) {
    if (!fn || !fn->token.text) return;
    for (int i = 0; i < func_sig_count; i++) {
        if (strcmp(func_sigs[i].name, fn->token.text) == 0 &&
            func_sigs[i].param_count == (fn->child_count > 0 ? fn->child_count - 1 : 0)) {
            return;
        }
    }
    if (func_sig_count >= MAX_FUNC_ENTRIES) return;
    FuncSig* sig = &func_sigs[func_sig_count++];
    sig->name = strdup(fn->token.text);
    sig->param_count = fn->child_count > 0 ? fn->child_count - 1 : 0;
    if (sig->param_count > MAX_SIG_PARAMS) sig->param_count = MAX_SIG_PARAMS;
    for (int i = 0; i < sig->param_count; i++)
        sig->param_types[i] = fn->children[i]->int_value;
}

static void scan_func_sigs(ASTNode* node) {
    if (!node) return;
    if (node->type == AST_FUNC_DECL) register_func_sig(node);
    for (int i = 0; i < node->child_count; i++)
        scan_func_sigs(node->children[i]);
}


static const char* get_var_type_name(const char* name) {
    for (int i = env_count - 1; i >= 0; i--) {
        if (strcmp(env[i].name, name) == 0) return env[i].type_name;
    }
    return NULL;
}

/* Element width of a pointer expression, in bytes, for `*p` / `p[i]` access.
   Returns 0 when the pointee width is unknown (caller defaults to 8).
   `char*`, `byte*` and `bool*` must load/store ONE byte: the pointee type is
   carried in VarEnv.type_name because the parser collapses `T*` to TOK_KW_PTR. */
static int ptr_element_width(ASTNode* node) {
    if (!node) return 0;
    ASTNode* ptr_node = node;
    if (ptr_node->type == AST_BINARY_EXPR && ptr_node->children[0]) {
        ptr_node = ptr_node->children[0];
    }
    if (ptr_node->type == AST_IDENTIFIER_EXPR) {
        VarEnv* v = lookup_var_env(ptr_node->token.text);
        if (!v) return 0;
        if (v->type == TOK_KW_CHAR || v->type == TOK_KW_BYTE ||
            v->type == TOK_KW_BOOL) return 1;
        if (v->type == TOK_KW_DWORD || v->type == TOK_KW_FLOAT) return 4;
        if ((v->type == TOK_KW_PTR || v->type == TOK_KW_REF ||
             v->type == TOK_KW_OWN || v->type == TOK_KW_RAW) && v->type_name) {
            const char* tn = v->type_name;
            /* `char**` indexes over pointers: a trailing '*' means 8-byte
               elements, so fall through to the default width. */
            size_t tn_len = strlen(tn);
            if (tn_len > 0 && tn[tn_len - 1] == '*') return 0;
            if (strcmp(tn, "char") == 0 || strcmp(tn, "byte") == 0 ||
                strcmp(tn, "bool") == 0) return 1;
            if (strcmp(tn, "dword") == 0 || strcmp(tn, "float") == 0 ||
                strcmp(tn, "half") == 0) return 4;
        }
    } else if (ptr_node->type == AST_CAST_EXPR) {
        if (ptr_node->int_value == TOK_KW_CHAR || ptr_node->int_value == TOK_KW_BYTE ||
            ptr_node->int_value == TOK_KW_BOOL) return 1;
        if (ptr_node->int_value == TOK_KW_DWORD || ptr_node->int_value == TOK_KW_FLOAT) return 4;
    }
    return 0;
}

/* True when a dereference reads/writes a 32-bit float rather than an int.
   The pointee type may be hidden by the `*(p + i)` rewrite, so the parser's
   marker on the deref node is consulted as well. */
static bool deref_is_float(ASTNode* node) {
    if (!node || node->type != AST_UNARY_EXPR || node->token.type != TOK_STAR)
        return false;
    if (node->string_value) {
        if (strcmp(node->string_value, "float") == 0 ||
            strcmp(node->string_value, "half") == 0)
            return true;
        if (strcmp(node->string_value, "dword") == 0 ||
            strcmp(node->string_value, "int") == 0 ||
            strcmp(node->string_value, "char") == 0)
            return false;
    }
    ASTNode* operand = node->child_count > 0 ? node->children[0] : NULL;
    if (!operand) return false;
    if (operand->type == AST_BINARY_EXPR && operand->child_count > 0)
        operand = operand->children[0];
    if (operand->type == AST_IDENTIFIER_EXPR) {
        VarEnv* v = lookup_var_env(operand->token.text);
        if (!v) return false;
        if (v->type == TOK_KW_FLOAT || v->type == TOK_KW_HALF) return true;
        if ((v->type == TOK_KW_PTR || v->type == TOK_KW_REF ||
             v->type == TOK_KW_OWN || v->type == TOK_KW_RAW) && v->type_name)
            return strcmp(v->type_name, "float") == 0 ||
                   strcmp(v->type_name, "half") == 0;
    }
    if (operand->type == AST_CAST_EXPR)
        return operand->int_value == TOK_KW_FLOAT ||
               operand->int_value == TOK_KW_HALF;
    return false;
}

static char active_catch_label[128] = "";
static int try_counter = 0;

void AsmGen_init(AsmGen* gen, IRProgram* ir) {
    gen->cg = cg_create(16384);
    gen->pt = pt_create();
    gen->ir = ir;
    gen->string_table_cap = 4096;
    gen->string_table = (char*)malloc(gen->string_table_cap);
    gen->string_table_size = 0;
    gen->label_counter = 0;
    /* Temporaries start right below the return address (rbp-8) and grow
       downwards; locals start at rbp-256. */
    gen->temp_stack_offset = 8;
    gen->float_pool_size = 0;
    gen->is_object_mode = false;
    env_count = 0;
    current_stack = LOCALS_BASE;
    static_var_count = 0;
    extern_func_count = 0;
    func_entry_count = 0;
    active_catch_label[0] = '\0';
    try_counter = 0;
}

static void emit_prologue(AsmGen* gen) {
    (void)gen;
    cg_emit_push_reg(gen->cg, REG_RBP);
    cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
    cg_emit_sub_reg_imm32(gen->cg, REG_RSP, 2048);
}

static void emit_epilogue(AsmGen* gen) {
    cg_emit_mov_reg_reg(gen->cg, REG_RSP, REG_RBP);
    cg_emit_pop_reg(gen->cg, REG_RBP);
    cg_emit_ret(gen->cg);
}

static void emit_syscall_exit(AsmGen* gen, int code) {
    cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 60);
    cg_emit_mov_reg_imm64(gen->cg, REG_RDI, code);
    cg_emit_syscall(gen->cg);
}

static const char* add_string(AsmGen* gen, const char* str, size_t len) {
    size_t needed = gen->string_table_size + len + 2;
    if (needed > gen->string_table_cap) {
        while (gen->string_table_cap < needed) gen->string_table_cap *= 2;
        gen->string_table = (char*)realloc(gen->string_table, gen->string_table_cap);
    }
    size_t offset = gen->string_table_size;
    memcpy(gen->string_table + offset, str, len);
    gen->string_table[offset + len] = '\0';
    gen->string_table_size = offset + len + 1;
    return gen->string_table + offset;
}

static void emit_print_string(AsmGen* gen, const char* str, size_t len) {
    char label[32];
    snprintf(label, sizeof(label), ".str%zu", gen->string_table_size);
    add_string(gen, str, len);
    
    cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 1);
    cg_emit_mov_reg_imm64(gen->cg, REG_RDI, 1);
    
    pt_add_patch(gen->pt, cg_get_size(gen->cg) + 3, label, false);
    cg_emit_lea_reg_rip(gen->cg, REG_RSI, 0); 
    
    cg_emit_mov_reg_imm64(gen->cg, REG_RDX, len);
    cg_emit_syscall(gen->cg);
}

static void emit_division_by_zero_guard(AsmGen* gen) {
    cg_emit_test_reg_reg(gen->cg, REG_RCX, REG_RCX);
    cg_emit_jne_rel32(gen->cg, 0);
    int skip_error = cg_get_size(gen->cg) - 4;
    const char *message = "magnetar: division by zero\n";
    size_t message_len = strlen(message);
    char label[32];
    snprintf(label, sizeof(label), ".str%zu", gen->string_table_size);
    add_string(gen, message, message_len);
    cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 1); // write
    cg_emit_mov_reg_imm64(gen->cg, REG_RDI, 2); // stderr
    pt_add_patch(gen->pt, cg_get_size(gen->cg) + 3, label, false);
    cg_emit_lea_reg_rip(gen->cg, REG_RSI, 0);
    cg_emit_mov_reg_imm64(gen->cg, REG_RDX, message_len);
    cg_emit_syscall(gen->cg);
    cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 60); // exit
    cg_emit_mov_reg_imm64(gen->cg, REG_RDI, 1);
    cg_emit_syscall(gen->cg);
    int32_t skip_disp = (int32_t)(cg_get_size(gen->cg) - (skip_error + 4));
    for (int i = 0; i < 4; i++)
        gen->cg->buffer[skip_error + i] = (uint8_t)((skip_disp >> (i * 8)) & 0xFF);
}

static void emit_print_string_var(AsmGen* gen) {
    cg_emit_mov_reg_reg(gen->cg, REG_RSI, REG_RAX);
    cg_emit_xor_reg_reg(gen->cg, REG_RDX, REG_RDX);
    
    int loop_top = cg_get_size(gen->cg);
    
    uint8_t* buf = cg_get_buffer(gen->cg);
    int sz = cg_get_size(gen->cg);
    buf[sz++] = 0x48; buf[sz++] = 0x0F; buf[sz++] = 0xB6; buf[sz++] = 0x0C; buf[sz++] = 0x16;
    gen->cg->size = sz;
    
    cg_emit_test_reg_reg(gen->cg, REG_RCX, REG_RCX);
    
    cg_emit_je_rel8(gen->cg, 0);
    int patch_exit = cg_get_size(gen->cg) - 1;
    
    buf = cg_get_buffer(gen->cg);
    sz = cg_get_size(gen->cg);
    buf[sz++] = 0x48; buf[sz++] = 0xFF; buf[sz++] = 0xC2;
    gen->cg->size = sz;
    
    int back_offset = loop_top - (cg_get_size(gen->cg) + 2);
    cg_emit_jmp_rel8(gen->cg, (int8_t)back_offset);
    
    gen->cg->buffer[patch_exit] = (uint8_t)(cg_get_size(gen->cg) - (patch_exit + 1));
    
    cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 1);
    cg_emit_mov_reg_imm64(gen->cg, REG_RDI, 1);
    cg_emit_syscall(gen->cg);
}

static void emit_print_int(AsmGen* gen) {
    cg_emit_sub_reg_imm32(gen->cg, REG_RSP, 32);
    cg_emit_mov_reg_reg(gen->cg, REG_RCX, REG_RSP);
    cg_emit_add_reg_imm32(gen->cg, REG_RCX, 30);
    cg_emit_mov_reg_imm64(gen->cg, REG_R8, 10);
    
    cg_emit_mov_reg_reg(gen->cg, REG_R9, REG_RCX);

    /* Digit loop's `xor rdx, rdx` makes idiv read a negative rax as a huge
       128-bit positive, so -7 printed as 18446744073709551609. Store a sign
       flag at [rsp+31] (above the digits, which grow downward from rsp+29),
       negate rax, and re-attach '-' in front afterwards. */
    {
        uint8_t* buf = cg_get_buffer(gen->cg);
        int size = cg_get_size(gen->cg);
        buf[size++] = 0xC6; buf[size++] = 0x44; buf[size++] = 0x24; buf[size++] = 0x1F; buf[size++] = 0x00;
        gen->cg->size = size;
    }
    cg_emit_test_reg_reg(gen->cg, REG_RAX, REG_RAX);
    int jge_pos = cg_get_size(gen->cg);
    cg_emit_jge_rel8(gen->cg, 0);
    {
        uint8_t* buf = cg_get_buffer(gen->cg);
        int size = cg_get_size(gen->cg);
        buf[size++] = 0x48; buf[size++] = 0xF7; buf[size++] = 0xD8;
        buf[size++] = 0xC6; buf[size++] = 0x44; buf[size++] = 0x24; buf[size++] = 0x1F; buf[size++] = 0x01;
        gen->cg->size = size;
    }
    {
        int pos = cg_get_size(gen->cg);
        uint8_t* buf = cg_get_buffer(gen->cg);
        buf[jge_pos + 1] = (uint8_t)(int8_t)(pos - (jge_pos + 2));
    }

    int loop_start = cg_get_size(gen->cg);
    cg_emit_xor_reg_reg(gen->cg, REG_RDX, REG_RDX);
    cg_emit_idiv_reg(gen->cg, REG_R8);
    cg_emit_add_reg_imm32(gen->cg, REG_RDX, 48);
    cg_emit_sub_reg_imm32(gen->cg, REG_RCX, 1);
    
    uint8_t* buf = cg_get_buffer(gen->cg);
    int size = cg_get_size(gen->cg);
    buf[size++] = 0x88;
    buf[size++] = 0x11;
    gen->cg->size = size;
    
    cg_emit_test_reg_reg(gen->cg, REG_RAX, REG_RAX);
    
    int offset = loop_start - (cg_get_size(gen->cg) + 2);
    cg_emit_jne_rel8(gen->cg, (int8_t)offset);

    /* mov al, [rsp+31]; test al, al; je +6; dec rcx; mov byte [rcx], '-' */
    cg_emit_byte(gen->cg, 0x8A); cg_emit_byte(gen->cg, 0x44);
    cg_emit_byte(gen->cg, 0x24); cg_emit_byte(gen->cg, 0x1F);
    cg_emit_byte(gen->cg, 0x84); cg_emit_byte(gen->cg, 0xC0);
    cg_emit_byte(gen->cg, 0x74); cg_emit_byte(gen->cg, 0x06);
    cg_emit_byte(gen->cg, 0x48); cg_emit_byte(gen->cg, 0xFF); cg_emit_byte(gen->cg, 0xC9);
    cg_emit_byte(gen->cg, 0xC6); cg_emit_byte(gen->cg, 0x01); cg_emit_byte(gen->cg, 0x2D);

    cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 1);
    cg_emit_mov_reg_imm64(gen->cg, REG_RDI, 1);
    cg_emit_mov_reg_reg(gen->cg, REG_RSI, REG_RCX);
    
    cg_emit_mov_reg_reg(gen->cg, REG_RDX, REG_R9);
    cg_emit_sub_reg_reg(gen->cg, REG_RDX, REG_RCX);
    
    cg_emit_syscall(gen->cg);
    
    cg_emit_add_reg_imm32(gen->cg, REG_RSP, 32);
}

/* Writes `len` bytes of `str` to stdout; the length is taken from a register
   so that a sign which is only sometimes present can be printed. */
static void emit_print_string_reg(AsmGen* gen, const char* str, size_t len,
                                   X64Register len_reg) {
    char label[32];
    snprintf(label, sizeof(label), ".str%zu", gen->string_table_size);
    add_string(gen, str, len);

    cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 1);
    cg_emit_mov_reg_imm64(gen->cg, REG_RDI, 1);
    pt_add_patch(gen->pt, cg_get_size(gen->cg) + 3, label, false);
    cg_emit_lea_reg_rip(gen->cg, REG_RSI, 0);
    cg_emit_mov_reg_reg(gen->cg, REG_RDX, len_reg);
    cg_emit_syscall(gen->cg);
}

/* Prints the float held in %xmm0.
 *
 * The format is `%.4f` with the trailing zeros removed -- at least one digit
 * after the point is kept: 3.5, 6.0, 1.4142. The special values print as
 * `inf` and `nan`. The previous implementation always printed four fraction
 * digits, so 3.5 came out as "3.5000". */
static void emit_print_float(AsmGen* gen) {
    CodeGen* cg = gen->cg;
    static int fp_label_counter = 0;
    int id = fp_label_counter++;
    char label_nan[32], label_inf[32], label_done[32];
    snprintf(label_nan, sizeof(label_nan), ".fpnan%d", id);
    snprintf(label_inf, sizeof(label_inf), ".fpinf%d", id);
    snprintf(label_done, sizeof(label_done), ".fpdone%d", id);

    /* --- the raw bits of the value --- */
    cg_emit_movd_xmm_to_gpr(cg, REG_R10, REG_XMM0);      /* r10d = the bits */
    cg_emit_mov_reg_reg(cg, REG_R11, REG_R10);           /* keep the sign */
    cg_emit_shr_reg_imm8(cg, REG_R11, 31);               /* r11d = sign */
    cg_emit_byte(cg, 0x41); cg_emit_byte(cg, 0x81); cg_emit_byte(cg, 0xE2);
    cg_emit_byte(cg, 0xFF); cg_emit_byte(cg, 0xFF); cg_emit_byte(cg, 0xFF);
    cg_emit_byte(cg, 0x7F);               /* and r10d, 0x7FFFFFFF (magnitude) */

    cg_emit_byte(cg, 0x41); cg_emit_byte(cg, 0x81); cg_emit_byte(cg, 0xFA);
    cg_emit_byte(cg, 0x00); cg_emit_byte(cg, 0x00); cg_emit_byte(cg, 0x80);
    cg_emit_byte(cg, 0x7F);                              /* cmp r10d, 0x7F800000 */
    cg_emit_ja_label(cg, gen->pt, label_nan);            /* not a number */
    cg_emit_je_label(cg, gen->pt, label_inf);            /* infinity */

    /* --- an ordinary value --- */
    cg_emit_movd_gpr_to_xmm(cg, REG_XMM0, REG_R10);      /* xmm0 = magnitude */

    /* The sign is a single '-' when it is set and nothing at all otherwise
       (a write of zero bytes prints nothing). */
    emit_print_string_reg(gen, "-", 1, REG_R11);

    cg_emit_cvttss2si_reg_xmm(cg, REG_RAX, REG_XMM0);    /* integer part */
    cg_emit_mov_reg_reg(cg, REG_R13, REG_RAX);           /* keep it */
    cg_emit_cvtsi2ss_xmm_reg(cg, REG_XMM1, REG_RAX);
    cg_emit_subss_xmm_xmm(cg, REG_XMM0, REG_XMM1);       /* xmm0 = fraction */

    /* scaled = round(fraction * 10000), computed as floor(f*20000 + 1) / 2 */
    cg_emit_mov_reg_imm32(cg, REG_R10, 20000);
    cg_emit_cvtsi2ss_xmm_reg(cg, REG_XMM1, REG_R10);
    cg_emit_mulss_xmm_xmm(cg, REG_XMM0, REG_XMM1);
    cg_emit_mov_reg_imm32(cg, REG_R10, 1);
    cg_emit_cvtsi2ss_xmm_reg(cg, REG_XMM2, REG_R10);
    cg_emit_addss_xmm_xmm(cg, REG_XMM0, REG_XMM2);
    cg_emit_cvttss2si_reg_xmm(cg, REG_RAX, REG_XMM0);
    cg_emit_shr_reg_imm8(cg, REG_RAX, 1);               /* scaled */

    /* Rounding may carry into the integer part (1.99999 -> 2.0). */
    cg_emit_cmp_reg_imm32(cg, REG_RAX, 10000);
    int carry_ok = cg_get_size(cg);
    cg_emit_byte(cg, 0x0F); cg_emit_byte(cg, 0x82); cg_emit_byte(cg, 0x00);
    cg_emit_byte(cg, 0x00); cg_emit_byte(cg, 0x00); cg_emit_byte(cg, 0x00);
                                                     /* jb .scaled_ok */
    cg_emit_inc_reg(cg, REG_R13);
    cg_emit_xor_reg_reg(cg, REG_RAX, REG_RAX);
    {
        int pos = cg_get_size(cg);
        int32_t off = (int32_t)(pos - (carry_ok + 6));
        uint8_t* buf = cg_get_buffer(cg);
        buf[carry_ok + 2] = (uint8_t)(off & 0xFF);
        buf[carry_ok + 3] = (uint8_t)((off >> 8) & 0xFF);
        buf[carry_ok + 4] = (uint8_t)((off >> 16) & 0xFF);
        buf[carry_ok + 5] = (uint8_t)((off >> 24) & 0xFF);
    }

    /* The scaled fraction has to survive the printing of the integer part,
       so it is parked in %r12 (which the integer printer leaves alone). */
    cg_emit_mov_reg_reg(cg, REG_R12, REG_RAX);

    cg_emit_mov_reg_reg(cg, REG_RAX, REG_R13);
    emit_print_int(gen);
    emit_print_string(gen, ".", 1);

    /* The four fraction digits, most significant first. */
    cg_emit_sub_reg_imm32(cg, REG_RSP, 32);
    cg_emit_mov_reg_reg(cg, REG_RAX, REG_R12);
    cg_emit_xor_reg_reg(cg, REG_RDX, REG_RDX);
    cg_emit_mov_reg_imm32(cg, REG_RCX, 1000);
    cg_emit_idiv_reg(cg, REG_RCX);
    cg_emit_add_reg_imm32(cg, REG_RAX, '0');
    cg_emit_byte(cg, 0x88); cg_emit_byte(cg, 0x04); cg_emit_byte(cg, 0x24);
                                                     /* mov [rsp], al */
    cg_emit_mov_reg_reg(cg, REG_RAX, REG_RDX);
    cg_emit_xor_reg_reg(cg, REG_RDX, REG_RDX);
    cg_emit_mov_reg_imm32(cg, REG_RCX, 100);
    cg_emit_idiv_reg(cg, REG_RCX);
    cg_emit_add_reg_imm32(cg, REG_RAX, '0');
    cg_emit_byte(cg, 0x88); cg_emit_byte(cg, 0x44); cg_emit_byte(cg, 0x24);
    cg_emit_byte(cg, 0x01);                             /* mov [rsp+1], al */
    cg_emit_mov_reg_reg(cg, REG_RAX, REG_RDX);
    cg_emit_xor_reg_reg(cg, REG_RDX, REG_RDX);
    cg_emit_mov_reg_imm32(cg, REG_RCX, 10);
    cg_emit_idiv_reg(cg, REG_RCX);
    cg_emit_add_reg_imm32(cg, REG_RAX, '0');
    cg_emit_byte(cg, 0x88); cg_emit_byte(cg, 0x44); cg_emit_byte(cg, 0x24);
    cg_emit_byte(cg, 0x02);                             /* mov [rsp+2], al */
    cg_emit_add_reg_imm32(cg, REG_RDX, '0');
    cg_emit_byte(cg, 0x88); cg_emit_byte(cg, 0x54); cg_emit_byte(cg, 0x24);
    cg_emit_byte(cg, 0x03);                             /* mov [rsp+3], dl */

    /* Drop the trailing zeros, but always keep one digit after the point. */
    cg_emit_mov_reg_imm32(cg, REG_RCX, 4);
    int len_loop = cg_get_size(cg);
    cg_emit_cmp_reg_imm32(cg, REG_RCX, 1);
    int len_done = cg_get_size(cg);
    cg_emit_byte(cg, 0x0F); cg_emit_byte(cg, 0x8E); cg_emit_byte(cg, 0x00);
    cg_emit_byte(cg, 0x00); cg_emit_byte(cg, 0x00); cg_emit_byte(cg, 0x00);
                                                     /* jle .len_done */
    cg_emit_byte(cg, 0x80); cg_emit_byte(cg, 0x7C); cg_emit_byte(cg, 0x0C);
    cg_emit_byte(cg, 0xFF); cg_emit_byte(cg, 0x30);   /* cmp byte [rsp+rcx-1], '0' */
    int len_nz = cg_get_size(cg);
    cg_emit_byte(cg, 0x0F); cg_emit_byte(cg, 0x85); cg_emit_byte(cg, 0x00);
    cg_emit_byte(cg, 0x00); cg_emit_byte(cg, 0x00); cg_emit_byte(cg, 0x00);
                                                     /* jne .len_done */
    cg_emit_dec_reg(cg, REG_RCX);
    int back_jmp = cg_get_size(cg);
    cg_emit_byte(cg, 0xE9); cg_emit_byte(cg, 0x00); cg_emit_byte(cg, 0x00);
    cg_emit_byte(cg, 0x00); cg_emit_byte(cg, 0x00);   /* jmp .len_loop */
    {
        int32_t off = (int32_t)(len_loop - (back_jmp + 4));
        uint8_t* buf = cg_get_buffer(cg);
        buf[back_jmp + 1] = (uint8_t)(off & 0xFF);
        buf[back_jmp + 2] = (uint8_t)((off >> 8) & 0xFF);
        buf[back_jmp + 3] = (uint8_t)((off >> 16) & 0xFF);
        buf[back_jmp + 4] = (uint8_t)((off >> 24) & 0xFF);
    }
    /* .len_done */
    {
        int pos = cg_get_size(cg);
        int32_t off = (int32_t)(pos - (len_done + 6));
        uint8_t* buf = cg_get_buffer(cg);
        buf[len_done + 2] = (uint8_t)(off & 0xFF);
        buf[len_done + 3] = (uint8_t)((off >> 8) & 0xFF);
        buf[len_done + 4] = (uint8_t)((off >> 16) & 0xFF);
        buf[len_done + 5] = (uint8_t)((off >> 24) & 0xFF);
    }
    {
        int pos = cg_get_size(cg);
        int32_t off = (int32_t)(pos - (len_nz + 6));
        uint8_t* buf = cg_get_buffer(cg);
        buf[len_nz + 2] = (uint8_t)(off & 0xFF);
        buf[len_nz + 3] = (uint8_t)((off >> 8) & 0xFF);
        buf[len_nz + 4] = (uint8_t)((off >> 16) & 0xFF);
        buf[len_nz + 5] = (uint8_t)((off >> 24) & 0xFF);
    }

    /* Write the digits that are left. */
    cg_emit_mov_reg_imm64(cg, REG_RAX, 1);
    cg_emit_mov_reg_imm64(cg, REG_RDI, 1);
    cg_emit_mov_reg_reg(cg, REG_RSI, REG_RSP);
    cg_emit_mov_reg_reg(cg, REG_RDX, REG_RCX);
    cg_emit_syscall(cg);
    cg_emit_add_reg_imm32(cg, REG_RSP, 32);
    cg_emit_jmp_label(cg, gen->pt, label_done);

    /* --- infinity --- */
    cg_emit_label(cg, gen->pt, label_inf);
    emit_print_string_reg(gen, "-", 1, REG_R11);
    emit_print_string(gen, "inf", 3);
    cg_emit_jmp_label(cg, gen->pt, label_done);

    /* --- not a number --- */
    cg_emit_label(cg, gen->pt, label_nan);
    emit_print_string(gen, "nan", 3);

    cg_emit_label(cg, gen->pt, label_done);
}

/* ---------------------------------------------------------- break/continue
   `break` and `continue` emit an unpatched `jmp rel32` and record the patch
   position in the innermost loop frame; the loop finishes and patches every
   recorded position to its exit (break) or its update point (continue). */

#define MAX_LOOP_BREAKS 128
#define MAX_LOOP_DEPTH  256

typedef struct {
    int breaks[MAX_LOOP_BREAKS];
    int break_count;
    int continues[MAX_LOOP_BREAKS];
    int continue_count;
} LoopFrame;

static LoopFrame loop_frames[MAX_LOOP_DEPTH];
static int loop_depth = 0;

static void cg_patch_rel32(CodeGen* cg, int pos, int target) {
    int32_t rel = (int32_t)(target - (pos + 4));
    for (int i = 0; i < 4; i++) {
        cg->buffer[pos + i] = (uint8_t)((rel >> (i * 8)) & 0xFF);
    }
}

static void loop_push(void) {
    if (loop_depth < MAX_LOOP_DEPTH) {
        loop_frames[loop_depth].break_count = 0;
        loop_frames[loop_depth].continue_count = 0;
        loop_depth++;
    }
}

/* Emits `jmp rel32` with a placeholder; the position is recorded in the
   innermost frame under `breaks` (true) or `continues` (false). */
static void loop_emit_jump(CodeGen* cg, bool is_break) {
    cg_emit_jmp_rel32(cg, 0);
    if (loop_depth <= 0) return;
    LoopFrame* f = &loop_frames[loop_depth - 1];
    int pos = cg_get_size(cg) - 4;
    if (is_break) {
        if (f->break_count < MAX_LOOP_BREAKS) f->breaks[f->break_count++] = pos;
    } else {
        if (f->continue_count < MAX_LOOP_BREAKS)
            f->continues[f->continue_count++] = pos;
    }
}

static void loop_pop_and_patch(CodeGen* cg, int continue_target, int exit_target) {
    if (loop_depth <= 0) return;
    LoopFrame* f = &loop_frames[loop_depth - 1];
    loop_depth--;
    for (int i = 0; i < f->break_count; i++)
        cg_patch_rel32(cg, f->breaks[i], exit_target);
    for (int i = 0; i < f->continue_count; i++)
        cg_patch_rel32(cg, f->continues[i], continue_target);
}

/* Loads a scalar value of type `t` from [base+off] into RAX (or XMM0 for
   floats) without disturbing `base`. Used by `move`, which needs the address
   to survive the load so the source slot can be cleared afterwards. */
static void emit_load_scalar_at(AsmGen* gen, X64Register base, int off, TokenType t) {
    if (t == TOK_KW_FLOAT || t == TOK_KW_HALF) {
        cg_emit_movss_xmm_mem(gen->cg, REG_XMM0, base, off);
    } else if (t == TOK_KW_BYTE || t == TOK_KW_CHAR || t == TOK_KW_BOOL) {
        cg_emit_movzx_byte(gen->cg, REG_RAX, base, off);
    } else if (t == TOK_KW_WORD) {
        cg_emit_movzx_word(gen->cg, REG_RAX, base, off);
    } else if (t == TOK_KW_DWORD) {
        cg_emit_movsxd_reg_mem(gen->cg, REG_RAX, base, off);
    } else {
        cg_emit_mov_reg_mem(gen->cg, REG_RAX, base, off);
    }
}

/* Zeroes the scalar slot at [base+off] using the width of `t`. */
static void emit_zero_scalar_at(AsmGen* gen, X64Register base, int off, TokenType t) {
    cg_emit_xor_reg_reg(gen->cg, REG_RCX, REG_RCX);
    if (t == TOK_KW_BYTE || t == TOK_KW_CHAR || t == TOK_KW_BOOL) {
        cg_emit_mov_mem_reg8(gen->cg, base, off, REG_RCX);
    } else if (t == TOK_KW_WORD) {
        cg_emit_mov_mem_reg16(gen->cg, base, off, REG_RCX);
    } else if (t == TOK_KW_DWORD || t == TOK_KW_FLOAT || t == TOK_KW_HALF) {
        cg_emit_mov_mem_reg32(gen->cg, base, off, REG_RCX);
    } else {
        cg_emit_mov_mem_reg(gen->cg, base, off, REG_RCX);
    }
}

/* ── Inline assembly mini-assembler ──────────────────────────────────────
   `asm("...")` and `asm { ... }` accept a small but useful subset of x86-64:
   mov/add/sub/and/or/xor/cmp/test/inc/dec/not/neg/shl/shr, push/pop, call,
   int, plus the zero-operand instructions handled below. Registers are the
   64-bit names rax..r15; immediates accept decimal, 0x…, 0b… and 0o… forms. */
static const char *asm_reg_names[16] = {
    "rax", "rcx", "rdx", "rbx", "rsp", "rbp", "rsi", "rdi",
    "r8",  "r9",  "r10", "r11", "r12", "r13", "r14", "r15"
};

/* 32-bit aliases register to the same physical register; the emitted move
   is 64-bit, which is harmless for the immediate/arithmetic forms accepted
   here and keeps `xor eax, eax` / `mov eax, 60` working as expected. */
static const char *asm_reg_names32[16] = {
    "eax", "ecx", "edx", "ebx", "esp", "ebp", "esi", "edi",
    "r8d", "r9d", "r10d", "r11d", "r12d", "r13d", "r14d", "r15d"
};

static void asm_trim(char *s) {
    char *p = s;
    while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') p++;
    if (p != s) memmove(s, p, strlen(p) + 1);
    size_t n = strlen(s);
    while (n > 0 && (s[n - 1] == ' ' || s[n - 1] == '\t' ||
                     s[n - 1] == '\r' || s[n - 1] == '\n'))
        s[--n] = '\0';
}

static void asm_lower(char *s) {
    for (; *s; s++)
        if (*s >= 'A' && *s <= 'Z') *s = (char)(*s - 'A' + 'a');
}

static int asm_reg_id(const char *s) {
    char low[16];
    size_t n = strlen(s);
    if (n >= sizeof(low)) return -1;
    for (size_t i = 0; i <= n; i++) {
        char c = s[i];
        low[i] = (c >= 'A' && c <= 'Z') ? (char)(c - 'A' + 'a') : c;
    }
    for (int i = 0; i < 16; i++)
        if (strcmp(low, asm_reg_names[i]) == 0) return i;
    for (int i = 0; i < 16; i++)
        if (strcmp(low, asm_reg_names32[i]) == 0) return i;
    return -1;
}

static bool asm_imm(const char *s, int64_t *out) {
    char *end = NULL;
    if (*s == '\0') return false;
    errno = 0;
    long long v = strtoll(s, &end, 0);
    if (end == s || *end != '\0' || errno != 0) return false;
    *out = v;
    return true;
}

static void asm_binop_rr(AsmGen *gen, uint8_t opcode, X64Register dst,
                         X64Register src) {
    uint8_t rex = 0x48;
    if (src >= REG_R8) rex |= 0x04;
    if (dst >= REG_R8) rex |= 0x01;
    cg_emit_byte(gen->cg, rex);
    cg_emit_byte(gen->cg, opcode);
    cg_emit_byte(gen->cg, (uint8_t)(0xC0 | ((src & 7) << 3) | (dst & 7)));
}

static void asm_binop_imm(AsmGen *gen, uint8_t digit, X64Register dst,
                          int32_t imm) {
    cg_emit_byte(gen->cg, (uint8_t)(0x48 | (dst >= REG_R8 ? 0x01 : 0)));
    if (imm >= -128 && imm <= 127) {
        cg_emit_byte(gen->cg, 0x83);
        cg_emit_byte(gen->cg, (uint8_t)(0xC0 | (digit << 3) | (dst & 7)));
        cg_emit_byte(gen->cg, (uint8_t)(imm & 0xFF));
        return;
    }
    cg_emit_byte(gen->cg, 0x81);
    cg_emit_byte(gen->cg, (uint8_t)(0xC0 | (digit << 3) | (dst & 7)));
    for (int i = 0; i < 4; i++)
        cg_emit_byte(gen->cg, (uint8_t)((imm >> (i * 8)) & 0xFF));
}

/* One inline-asm block owns a table that maps the source labels it defines to
   unique assembler symbols. Forward jumps are patched through the normal
   patch table, so both forward and backward label references work. */
typedef struct {
    int block_id;
    int count;
    char names[128][64];
    char mangled[128][128];
} AsmLabels;

static const char *asm_label_for(AsmLabels *labels, const char *raw) {
    if (!labels || !raw) return NULL;
    char name[64];
    snprintf(name, sizeof(name), "%s", raw);
    asm_trim(name);
    asm_lower(name);
    if (!name[0]) return NULL;
    for (int i = 0; i < labels->count; i++)
        if (strcmp(labels->names[i], name) == 0) return labels->mangled[i];
    if (labels->count >= 128) return NULL;
    int i = labels->count++;
    snprintf(labels->names[i], sizeof(labels->names[i]), "%s", name);
    snprintf(labels->mangled[i], sizeof(labels->mangled[i]), ".asm_%s_%d",
             name, labels->block_id);
    return labels->mangled[i];
}

/* Memory operand: `[base + index*scale + disp]`. Any part except a register
   base is optional. Size prefixes such as `qword ptr` are ignored. */
typedef struct {
    bool valid;
    int base;
    int index;
    int scale;
    int32_t disp;
} AsmMem;

static bool asm_parse_mem(AsmGen *gen, const char *s, AsmMem *m) {
    (void)gen;
    memset(m, 0, sizeof(*m));
    m->base = -1;
    m->index = -1;
    m->scale = 1;
    if (!s) return false;
    const char *lb = strchr(s, '[');
    if (!lb) return false;
    const char *rb = strrchr(s, ']');
    if (!rb || rb <= lb) return false;

    char inner[160];
    size_t w = 0;
    for (const char *q = lb + 1; q < rb && w + 1 < sizeof(inner); q++) {
        char c = *q;
        if (c == ' ' || c == '\t' || c == '%') continue;
        inner[w++] = c;
    }
    inner[w] = '\0';
    if (!inner[0]) return false;

    int pos = 0;
    int sign = 1;
    while (inner[pos]) {
        if (inner[pos] == '+') { sign = 1; pos++; continue; }
        if (inner[pos] == '-') { sign = -1; pos++; continue; }
        int start = pos;
        while (inner[pos] && inner[pos] != '+' && inner[pos] != '-') pos++;
        char tok[64];
        int tl = pos - start;
        if (tl <= 0 || tl >= (int)sizeof(tok)) return false;
        memcpy(tok, inner + start, (size_t)tl);
        tok[tl] = '\0';

        char *star = strchr(tok, '*');
        if (star) {
            *star = '\0';
            char *endp = NULL;
            long sc = strtol(star + 1, &endp, 0);
            if (!endp || *endp || (sc != 1 && sc != 2 && sc != 4 && sc != 8))
                return false;
            int ridd = asm_reg_id(tok);
            if (ridd < 0 || m->index >= 0) return false;
            m->index = ridd;
            m->scale = (int)sc;
        } else {
            int ridd = asm_reg_id(tok);
            if (ridd >= 0) {
                if (m->base < 0) m->base = ridd;
                else if (m->index < 0) m->index = ridd;
                else return false;
            } else {
                char *endp = NULL;
                errno = 0;
                long long v = strtoll(tok, &endp, 0);
                if (endp != tok && endp && *endp == '\0' && errno == 0) {
                    m->disp += (int32_t)(sign * v);
                    sign = 1;
                } else {
                    /* A local variable name inside `[...]` resolves to its
                       rbp-relative slot: `[x]` == `[rbp-<offset>]`. */
                    VarEnv *ve = lookup_var_env(tok);
                    if (!ve || m->base >= 0) return false;
                    m->base = (int)REG_RBP;
                    m->disp += (int32_t)(sign * ve->offset);
                    sign = 1;
                }
            }
        }
    }
    m->valid = true;
    return true;
}

/* Emit the ModRM/SIB/displacement tail for an instruction whose destination
   or source is a memory operand. `reg_field` is either a register number
   (rex_r set when it is >= 8) or an opcode extension digit. */
static void asm_emit_mem_form(AsmGen *gen, uint8_t opcode, int reg_field,
                              bool rex_r, AsmMem *m) {
    int base = m->base;
    int index = m->index;
    bool need_sib = (index >= 0) || base < 0 || (base >= 0 && (base & 7) == 4);
    int mod;
    if (base < 0) mod = 0;
    else if (m->disp == 0 && (base & 7) != 5) mod = 0;
    else if (m->disp >= -128 && m->disp <= 127) mod = 1;
    else mod = 2;

    uint8_t rex = 0x48;
    if (rex_r) rex |= 0x04;
    if (index >= 8) rex |= 0x02;
    if (base >= 8) rex |= 0x01;
    cg_emit_byte(gen->cg, rex);
    cg_emit_byte(gen->cg, opcode);
    uint8_t modrm = (uint8_t)((mod << 6) | ((reg_field & 7) << 3) |
                              (need_sib ? 4 : (base & 7)));
    cg_emit_byte(gen->cg, modrm);
    if (need_sib) {
        int idx = index >= 0 ? (index & 7) : 4;
        int bs = base >= 0 ? (base & 7) : 5;
        int scale_bits = m->scale == 8 ? 3 : m->scale == 4 ? 2 :
                         m->scale == 2 ? 1 : 0;
        cg_emit_byte(gen->cg,
                     (uint8_t)((scale_bits << 6) | (idx << 3) | bs));
    }
    if (base < 0) {
        for (int i = 0; i < 4; i++)
            cg_emit_byte(gen->cg, (uint8_t)((m->disp >> (i * 8)) & 0xFF));
    } else if (mod == 1) {
        cg_emit_byte(gen->cg, (uint8_t)(m->disp & 0xFF));
    } else if (mod == 2) {
        for (int i = 0; i < 4; i++)
            cg_emit_byte(gen->cg, (uint8_t)((m->disp >> (i * 8)) & 0xFF));
    }
}

static int asm_jcc_code(const char *mnemonic) {
    if (strcmp(mnemonic, "jo") == 0) return 0;
    if (strcmp(mnemonic, "jno") == 0) return 1;
    if (strcmp(mnemonic, "jb") == 0 || strcmp(mnemonic, "jc") == 0 ||
        strcmp(mnemonic, "jnae") == 0) return 2;
    if (strcmp(mnemonic, "jae") == 0 || strcmp(mnemonic, "jnb") == 0 ||
        strcmp(mnemonic, "jnc") == 0) return 3;
    if (strcmp(mnemonic, "je") == 0 || strcmp(mnemonic, "jz") == 0) return 4;
    if (strcmp(mnemonic, "jne") == 0 || strcmp(mnemonic, "jnz") == 0) return 5;
    if (strcmp(mnemonic, "jbe") == 0 || strcmp(mnemonic, "jna") == 0) return 6;
    if (strcmp(mnemonic, "ja") == 0 || strcmp(mnemonic, "jnbe") == 0) return 7;
    if (strcmp(mnemonic, "js") == 0) return 8;
    if (strcmp(mnemonic, "jns") == 0) return 9;
    if (strcmp(mnemonic, "jp") == 0 || strcmp(mnemonic, "jpe") == 0) return 10;
    if (strcmp(mnemonic, "jnp") == 0 || strcmp(mnemonic, "jpo") == 0) return 11;
    if (strcmp(mnemonic, "jl") == 0 || strcmp(mnemonic, "jnge") == 0) return 12;
    if (strcmp(mnemonic, "jge") == 0 || strcmp(mnemonic, "jnl") == 0) return 13;
    if (strcmp(mnemonic, "jle") == 0 || strcmp(mnemonic, "jng") == 0) return 14;
    if (strcmp(mnemonic, "jg") == 0 || strcmp(mnemonic, "jnle") == 0) return 15;
    return -1;
}

static bool asm_find_label_pos(AsmGen *gen, const char *label, size_t *pos) {
    for (size_t i = 0; i < gen->pt->count; i++) {
        PatchPoint *p = &gen->pt->patches[i];
        if (p->is_label && strcmp(p->label_name, label) == 0) {
            *pos = p->position;
            return true;
        }
    }
    return false;
}

static void asm_emit_jump(AsmGen *gen, AsmLabels *labels, const char *mnemonic,
                          const char *operand) {
    const char *target = asm_label_for(labels, operand);
    if (!target) {
        cg_emit_byte(gen->cg, 0x90);
        return;
    }
    int is_jmp = strcmp(mnemonic, "jmp") == 0;
    int cc = is_jmp ? -1 : asm_jcc_code(mnemonic);
    if (!is_jmp && cc < 0) {
        cg_emit_byte(gen->cg, 0x90);
        return;
    }
    size_t here = cg_get_size(gen->cg);
    size_t label_pos;
    if (asm_find_label_pos(gen, target, &label_pos) && label_pos <= here) {
        int64_t disp = (int64_t)label_pos - (int64_t)(here + 2);
        if (disp >= -128 && disp <= 127) {
            cg_emit_byte(gen->cg, is_jmp ? 0xEB : (uint8_t)(0x70 | cc));
            cg_emit_byte(gen->cg, (uint8_t)(disp & 0xFF));
            return;
        }
    }
    if (is_jmp) {
        cg_emit_byte(gen->cg, 0xE9);
    } else {
        cg_emit_byte(gen->cg, 0x0F);
        cg_emit_byte(gen->cg, (uint8_t)(0x80 | cc));
    }
    size_t patch_pos = cg_get_size(gen->cg);
    for (int i = 0; i < 4; i++) cg_emit_byte(gen->cg, 0);
    pt_add_patch(gen->pt, patch_pos, target, false);
}

static void asm_emit_one(AsmGen *gen, char *line, AsmLabels *labels) {
    asm_trim(line);
    if (!line[0] || line[0] == '#' ||
        (line[0] == '/' && line[1] == '/'))
        return;
    /* Strip trailing comments; a leading '#' is still an immediate marker. */
    for (char *q = line; *q; q++) {
        if (q[0] == '#' && (q == line || q[-1] == ' ' || q[-1] == '\t')) {
            *q = '\0';
            break;
        }
        if (q[0] == '/' && q[1] == '/') {
            *q = '\0';
            break;
        }
    }
    asm_trim(line);
    if (!line[0]) return;

    char *colon = strchr(line, ':');
    if (colon) {
        /* A label is turned into a unique local symbol, so a following
           `jmp`/`je`/... can reach it. */
        *colon = '\0';
        asm_trim(line);
        const char *label = asm_label_for(labels, line);
        if (label) cg_emit_label(gen->cg, gen->pt, label);
        asm_emit_one(gen, colon + 1, labels);
        return;
    }

    char *space = line;
    while (*space && *space != ' ' && *space != '\t') space++;
    char mnemonic[32];
    size_t mlen = (size_t)(space - line);
    if (mlen >= sizeof(mnemonic)) mlen = sizeof(mnemonic) - 1;
    memcpy(mnemonic, line, mlen);
    mnemonic[mlen] = '\0';
    asm_lower(mnemonic);

    char op1[80] = "", op2[80] = "", op3[80] = "";
    char *rest = space;
    while (*rest == ' ' || *rest == '\t') rest++;
    if (*rest && *rest != '#' && *rest != ';') {
        char *comma = strchr(rest, ',');
        if (comma) {
            *comma = '\0';
            strncpy(op1, rest, sizeof(op1) - 1);
            char *more = comma + 1;
            char *comma2 = strchr(more, ',');
            if (comma2) {
                *comma2 = '\0';
                strncpy(op2, more, sizeof(op2) - 1);
                strncpy(op3, comma2 + 1, sizeof(op3) - 1);
            } else {
                strncpy(op2, more, sizeof(op2) - 1);
            }
        } else {
            strncpy(op1, rest, sizeof(op1) - 1);
        }
    }
    asm_trim(op1); asm_trim(op2); asm_trim(op3);
    /* Operands keep their case so local variable names inside `[...]` can be
       looked up exactly; register matching is case-insensitive. */
    /* Accept AT&T-style `%rax` operands as well. */
    if (op1[0] == '%') memmove(op1, op1 + 1, strlen(op1));
    if (op2[0] == '%') memmove(op2, op2 + 1, strlen(op2));
    if (op3[0] == '%') memmove(op3, op3 + 1, strlen(op3));

    int r1 = asm_reg_id(op1);
    int r2 = asm_reg_id(op2);
    int64_t imm1 = 0, imm2 = 0;
    bool o1_imm = asm_imm(op1[0] == '#' || op1[0] == '$' ? op1 + 1 : op1, &imm1);
    bool o2_imm = asm_imm(op2[0] == '#' || op2[0] == '$' ? op2 + 1 : op2, &imm2);

    /* Zero-operand instructions. */
    if (strcmp(mnemonic, "nop") == 0) { cg_emit_byte(gen->cg, 0x90); return; }
    if (strcmp(mnemonic, "syscall") == 0) { cg_emit_byte(gen->cg, 0x0F); cg_emit_byte(gen->cg, 0x05); return; }
    if (strcmp(mnemonic, "ret") == 0) { cg_emit_byte(gen->cg, 0xC3); return; }
    if (strcmp(mnemonic, "int3") == 0) { cg_emit_byte(gen->cg, 0xCC); return; }
    if (strcmp(mnemonic, "pause") == 0) { cg_emit_byte(gen->cg, 0xF3); cg_emit_byte(gen->cg, 0x90); return; }
    if (strcmp(mnemonic, "cpuid") == 0) { cg_emit_byte(gen->cg, 0x0F); cg_emit_byte(gen->cg, 0xA2); return; }
    if (strcmp(mnemonic, "rdtsc") == 0) { cg_emit_byte(gen->cg, 0x0F); cg_emit_byte(gen->cg, 0x31); return; }
    if (strcmp(mnemonic, "ud2") == 0) { cg_emit_byte(gen->cg, 0x0F); cg_emit_byte(gen->cg, 0x0B); return; }
    if (strcmp(mnemonic, "hlt") == 0) { cg_emit_byte(gen->cg, 0xF4); return; }
    if (strcmp(mnemonic, "cli") == 0) { cg_emit_byte(gen->cg, 0xFA); return; }
    if (strcmp(mnemonic, "sti") == 0) { cg_emit_byte(gen->cg, 0xFB); return; }
    if (strcmp(mnemonic, "cld") == 0) { cg_emit_byte(gen->cg, 0xFC); return; }
    if (strcmp(mnemonic, "std") == 0) { cg_emit_byte(gen->cg, 0xFD); return; }
    if (strcmp(mnemonic, "leave") == 0) { cg_emit_byte(gen->cg, 0xC9); return; }
    if (strcmp(mnemonic, "int") == 0 && o1_imm) {
        cg_emit_byte(gen->cg, 0xCD);
        cg_emit_byte(gen->cg, (uint8_t)(imm1 & 0xFF));
        return;
    }

    AsmMem m1, m2;
    bool mem1 = asm_parse_mem(gen, op1, &m1);
    bool mem2 = asm_parse_mem(gen, op2, &m2);

    /* Jumps and conditional jumps to a label in this asm block. */
    if (mnemonic[0] == 'j' && op1[0]) {
        if (strcmp(mnemonic, "jmp") == 0 && r1 >= 0) {
            cg_emit_byte(gen->cg, (uint8_t)(0x48 | (r1 >= 8 ? 0x01 : 0)));
            cg_emit_byte(gen->cg, 0xFF);
            cg_emit_byte(gen->cg, (uint8_t)(0xE0 | (r1 & 7)));
            return;
        }
        if (r1 < 0 && (strcmp(mnemonic, "jmp") == 0 ||
                       asm_jcc_code(mnemonic) >= 0)) {
            asm_emit_jump(gen, labels, mnemonic, op1);
            return;
        }
    }

    if (strcmp(mnemonic, "lea") == 0) {
        if (r1 >= 0 && mem2) {
            asm_emit_mem_form(gen, 0x8D, r1, r1 >= 8, &m2);
            return;
        }
    }

    if (strcmp(mnemonic, "mov") == 0) {
        if (r1 >= 0 && mem2) {
            asm_emit_mem_form(gen, 0x8B, r1, r1 >= 8, &m2);
            return;
        }
        if (mem1 && r2 >= 0) {
            asm_emit_mem_form(gen, 0x89, r2, r2 >= 8, &m1);
            return;
        }
        if (mem1 && o2_imm) {
            asm_emit_mem_form(gen, 0xC7, 0, false, &m1);
            for (int i = 0; i < 4; i++)
                cg_emit_byte(gen->cg, (uint8_t)((imm2 >> (i * 8)) & 0xFF));
            return;
        }
    }

    if (mem1 && r1 < 0) {
        int digit = -1;
        uint8_t opcode = 0;
        if (strcmp(mnemonic, "inc") == 0) { opcode = 0xFF; digit = 0; }
        else if (strcmp(mnemonic, "dec") == 0) { opcode = 0xFF; digit = 1; }
        else if (strcmp(mnemonic, "not") == 0) { opcode = 0xF7; digit = 2; }
        else if (strcmp(mnemonic, "neg") == 0) { opcode = 0xF7; digit = 3; }
        if (digit >= 0) {
            asm_emit_mem_form(gen, opcode, digit, false, &m1);
            return;
        }
        if ((strcmp(mnemonic, "shl") == 0 || strcmp(mnemonic, "shr") == 0) &&
            o2_imm) {
            asm_emit_mem_form(gen, 0xC1,
                              strcmp(mnemonic, "shl") == 0 ? 4 : 5, false, &m1);
            cg_emit_byte(gen->cg, (uint8_t)(imm2 & 0xFF));
            return;
        }
    }

    if (r1 < 0) {
        cg_emit_byte(gen->cg, 0x90); /* unknown instruction: NOP */
        return;
    }
    X64Register dst = (X64Register)r1;

    if (strcmp(mnemonic, "push") == 0) { cg_emit_push_reg(gen->cg, dst); return; }
    if (strcmp(mnemonic, "pop") == 0) { cg_emit_pop_reg(gen->cg, dst); return; }
    if (strcmp(mnemonic, "inc") == 0) { cg_emit_inc_reg(gen->cg, dst); return; }
    if (strcmp(mnemonic, "dec") == 0) { cg_emit_dec_reg(gen->cg, dst); return; }
    if (strcmp(mnemonic, "call") == 0) { cg_emit_call_reg(gen->cg, dst); return; }

    if (strcmp(mnemonic, "mov") == 0) {
        if (r2 >= 0) { cg_emit_mov_reg_reg(gen->cg, dst, (X64Register)r2); return; }
        if (o2_imm) {
            if (imm2 != 0 && imm2 >= -128 && imm2 <= 127 && dst != REG_RSP) {
                cg_emit_byte(gen->cg, 0x6A);
                cg_emit_byte(gen->cg, (uint8_t)(imm2 & 0xFF));
                cg_emit_pop_reg(gen->cg, dst);
            } else if ((int64_t)imm2 == (int32_t)imm2) {
                cg_emit_mov_reg_imm32(gen->cg, dst, (uint32_t)imm2);
            } else {
                cg_emit_mov_reg_imm64(gen->cg, dst, (uint64_t)imm2);
            }
            return;
        }
    }
    if (strcmp(mnemonic, "not") == 0 || strcmp(mnemonic, "neg") == 0) {
        cg_emit_byte(gen->cg, (uint8_t)(0x48 | (dst >= REG_R8 ? 0x01 : 0)));
        cg_emit_byte(gen->cg, 0xF7);
        cg_emit_byte(gen->cg, (uint8_t)(0xC0 | ((strcmp(mnemonic, "not") == 0 ? 2 : 3) << 3) | (dst & 7)));
        return;
    }
    if (strcmp(mnemonic, "shl") == 0 || strcmp(mnemonic, "shr") == 0) {
        if (o2_imm) {
            if (strcmp(mnemonic, "shl") == 0)
                cg_emit_shl_reg_imm8(gen->cg, dst, (uint8_t)imm2);
            else
                cg_emit_shr_reg_imm8(gen->cg, dst, (uint8_t)imm2);
            return;
        }
    }

    /* add/or/and/sub/xor/cmp/test with optional memory operands. */
    struct {
        const char *name;
        uint8_t rm_reg;   /* [mem], reg  /  reg, reg */
        uint8_t reg_rm;   /* reg, [mem] */
        uint8_t digit;
        bool is_test;
    } ops[] = {
        {"add", 0x01, 0x03, 0, false}, {"or",  0x09, 0x0B, 1, false},
        {"and", 0x21, 0x23, 4, false}, {"sub", 0x29, 0x2B, 5, false},
        {"xor", 0x31, 0x33, 6, false}, {"cmp", 0x39, 0x3B, 7, false},
        {"test", 0x85, 0x85, 0, true}
    };
    for (size_t i = 0; i < sizeof(ops) / sizeof(ops[0]); i++) {
        if (strcmp(mnemonic, ops[i].name) != 0) continue;
        if (r1 >= 0 && mem2) {
            asm_emit_mem_form(gen, ops[i].reg_rm, r1, r1 >= 8, &m2);
            return;
        }
        if (mem1 && r2 >= 0) {
            asm_emit_mem_form(gen, ops[i].rm_reg, r2, r2 >= 8, &m1);
            return;
        }
        if (mem1 && o2_imm) {
            if (ops[i].is_test) {
                asm_emit_mem_form(gen, 0xF7, 0, false, &m1);
            } else {
                asm_emit_mem_form(gen, 0x81, ops[i].digit, false, &m1);
            }
            for (int b = 0; b < 4; b++)
                cg_emit_byte(gen->cg, (uint8_t)((imm2 >> (b * 8)) & 0xFF));
            return;
        }
        if (r2 >= 0) { asm_binop_rr(gen, ops[i].rm_reg, dst, (X64Register)r2); return; }
        if (o2_imm) { asm_binop_imm(gen, ops[i].digit, dst, (int32_t)imm2); return; }
    }

    cg_emit_byte(gen->cg, 0x90); /* fallback: NOP */
}

static void emit_inline_asm(AsmGen *gen, const char *src) {
    if (!src) return;
    char *copy = strdup(src);
    if (!copy) return;
    AsmLabels labels;
    memset(&labels, 0, sizeof(labels));
    labels.block_id = gen->label_counter++;
    char *p = copy;
    while (*p) {
        char *end = p;
        while (*end && *end != ';' && *end != '\n') end++;
        char saved = *end;
        *end = '\0';
        asm_emit_one(gen, p, &labels);
        if (!saved) break;
        p = end + 1;
    }
    free(copy);
}

static void generate_from_ast(AsmGen* gen, ASTNode* node) {
    if (!node) return;
    
    switch (node->type) {
        case AST_PROGRAM: {
            int call_main_pos = 0;
            if (!gen->is_object_mode) {
                /* _start: the kernel enters with [rsp]=argc, [rsp+8]=argv and
                   envp right after it. Magnetar passes function arguments on the
                   stack (the callee reads them at rbp+16, rbp+24, ...), so the
                   entry must push them in reverse order before calling main. */
                uint8_t* b = cg_get_buffer(gen->cg);
                int sz = cg_get_size(gen->cg);
                b[sz++] = 0x48; b[sz++] = 0x8B; b[sz++] = 0x3C; b[sz++] = 0x24;       // mov rdi, [rsp]
                b[sz++] = 0x48; b[sz++] = 0x8D; b[sz++] = 0x74; b[sz++] = 0x24; b[sz++] = 0x08; // lea rsi, [rsp+8]
                b[sz++] = 0x48; b[sz++] = 0x89; b[sz++] = 0xE2;                     // mov rdx, rsp
                b[sz++] = 0x48; b[sz++] = 0x83; b[sz++] = 0xC2; b[sz++] = 0x10;     // add rdx, 16
                b[sz++] = 0x48; b[sz++] = 0x8B; b[sz++] = 0x04; b[sz++] = 0x24;     // mov rax, [rsp]
                b[sz++] = 0x48; b[sz++] = 0xC1; b[sz++] = 0xE0; b[sz++] = 0x03;     // shl rax, 3
                b[sz++] = 0x48; b[sz++] = 0x01; b[sz++] = 0xC2;                     // add rdx, rax  (envp)
                b[sz++] = 0x48; b[sz++] = 0x83; b[sz++] = 0xE4; b[sz++] = 0xF0;     // and rsp, -16
                b[sz++] = 0x31; b[sz++] = 0xED;                                     // xor ebp, ebp
                b[sz++] = 0x52;                                                     // push rdx (envp)
                b[sz++] = 0x56;                                                     // push rsi (argv)
                b[sz++] = 0x57;                                                     // push rdi (argc)
                b[sz++] = 0xE8;                                                     // call main
                b[sz++] = 0; b[sz++] = 0; b[sz++] = 0; b[sz++] = 0;
                call_main_pos = sz - 4;
                b[sz++] = 0x48; b[sz++] = 0x83; b[sz++] = 0xC4; b[sz++] = 0x18;     // add rsp, 24
                b[sz++] = 0x89; b[sz++] = 0xC7;                                     // mov edi, eax
                b[sz++] = 0xB8; b[sz++] = 0xE7; b[sz++] = 0x00; b[sz++] = 0x00; b[sz++] = 0x00; // mov eax, 231
                b[sz++] = 0x0F; b[sz++] = 0x05;                                     // syscall
                gen->cg->size = sz;
            }
            
            for (int i = 0; i < node->child_count; i++) {
                generate_from_ast(gen, node->children[i]);
            }
            
            if (!gen->is_object_mode) {
                int main_pos = 0;
                for (int i = 0; i < func_entry_count; i++) {
                    if (strcmp(func_entries[i].name, entry_func_name) == 0) {
                        main_pos = func_entries[i].position;
                        break;
                    }
                }
                if (main_pos > 0) {
                    int32_t offset = main_pos - (call_main_pos + 4);
                    uint8_t* buf = cg_get_buffer(gen->cg);
                    buf[call_main_pos] = offset & 0xFF;
                    buf[call_main_pos + 1] = (offset >> 8) & 0xFF;
                    buf[call_main_pos + 2] = (offset >> 16) & 0xFF;
                    buf[call_main_pos + 3] = (offset >> 24) & 0xFF;
                } else {
                    fprintf(stderr,
                            "Error: entry function '%s' was not defined. "
                            "Use --entry <name> to select a different start function.\n",
                            entry_func_name);
                    entry_func_missing = true;
                }
            }
            break;
        }
        
        case AST_FUNC_DECL: {
            if ((node->int_value & 0xFF) == 1) {
                if (extern_func_count < MAX_EXTERN_FUNCS) {
                    extern_funcs[extern_func_count].name = strdup(node->token.text);
                    extern_func_count++;
                }
                break;
            }
            // Emit every regular function so call patches always resolve.
            // Dead Function Elimination via scan_calls misses class methods
            // (member-access calls), leaving unresolved jumps that corrupt the
            // stack at runtime. Emitting all functions is safe and robust.
            int func_pos = cg_get_size(gen->cg);
            if (node->token.text) {
                cg_emit_label(gen->cg, gen->pt, node->token.text);
                if (func_entry_count < MAX_FUNC_ENTRIES) {
                    func_entries[func_entry_count].name = strdup(node->token.text);
                    func_entries[func_entry_count].position = func_pos;
                    func_entries[func_entry_count].return_type = (node->int_value >> 8);
                    func_entry_count++;
                }
            }
            
            const char* saved_func = current_func_name;
            current_func_name = node->token.text;
            int saved_defer_count = active_defer_count;
            active_defer_count = 0;
            
            const char* saved_class = current_class_name;
            if (node->token.text && strchr(node->token.text, '_')) {
                char* underscore = strchr(node->token.text, '_');
                int len = underscore - node->token.text;
                char* class_name_copy = (char*)malloc(len + 1);
                strncpy(class_name_copy, node->token.text, len);
                class_name_copy[len] = '\0';
                current_class_name = class_name_copy;
            }
            
            emit_prologue(gen);
            
            int saved_env_count = env_count;
            int saved_stack = current_stack;
            current_stack = LOCALS_BASE;
            gen->temp_stack_offset = 8;
            
            int saved_sret_offset = current_sret_offset;
            StructType* saved_ret_struct = current_ret_struct;
            current_sret_offset = 0;
            current_ret_struct = ret_struct_for(node->string_value);
            if (current_ret_struct) {
                current_stack += 8;
                current_sret_offset = -current_stack;
                cg_emit_mov_mem_reg(gen->cg, REG_RBP, current_sret_offset, REG_RAX);
            }
            
            int param_offset = 16;
            for (int i = 0; i < node->child_count - 1; i++) {
                ASTNode* param = node->children[i];
                add_var(param->token.text, param_offset, param->int_value, param->string_value);
                if (env_count > 0)
                    env[env_count - 1].is_volatile = param->is_volatile;
                param_offset += (param->int_value == TOK_KW_ANY) ? 16 : 8;
            }
            
            if (node->child_count > 0) {
                generate_from_ast(gen, node->children[node->child_count - 1]);
            }
            
            for (int i = active_defer_count - 1; i >= 0; i--) {
                generate_from_ast(gen, active_defers[i]);
            }
            
            /* A function that never returns a value leaves %rax undefined.
               `main` in particular must exit with status 0, otherwise the
               process ends up with whatever happened to be in %rax. */
            if (!ast_has_value_return(node->children[node->child_count - 1])) {
                cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 0);
            }
            
            emit_epilogue(gen);
            
            active_defer_count = saved_defer_count;
            current_func_name = saved_func;
            current_sret_offset = saved_sret_offset;
            current_ret_struct = saved_ret_struct;
            
            env_count = saved_env_count;
            current_stack = saved_stack;
            
            if (current_class_name && current_class_name != saved_class) {
                free((void*)current_class_name);
            }
            current_class_name = saved_class;
            break;
        }
        
        case NODE_CLASS_DECL: {
            for (int i = 0; i < node->child_count; i++) {
                generate_from_ast(gen, node->children[i]);
            }
            break;
        }
        
        case NODE_ENUM_DECL:
        case NODE_UNION_DECL:
            break;
        
        case AST_BLOCK: {
            int saved_env_count = env_count;
            int saved_stack = current_stack;
            for (int i = 0; i < node->child_count; i++) {
                /* Every statement starts with a fresh temporary region. */
                temp_reset(gen);
                generate_from_ast(gen, node->children[i]);
            }
            env_count = saved_env_count;
            current_stack = saved_stack;
            break;
        }
        
        case AST_RETURN_STMT: {
            temp_reset(gen);
            bool ret_is_any_value = current_ret_struct == any_struct_type() &&
                                    current_sret_offset != 0 &&
                                    node->child_count > 0 &&
                                    is_any_expr(node->children[0]);
            if (node->child_count > 0 && !ret_is_any_value) {
                generate_from_ast(gen, node->children[0]);
            }
            if (current_ret_struct == any_struct_type() && current_sret_offset != 0) {
                /* `any` needs both words. A returned `any` expression already
                   points at a tagged value, otherwise compute the tag from the
                   expression's static type. */
                if (node->child_count > 0 && node->children[0]) {
                    ASTNode* e = node->children[0];
                    if (is_any_expr(e)) {
                        gen_any_value(gen, e);
                        cg_emit_mov_reg_reg(gen->cg, REG_RDX, REG_RAX);
                        cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, current_sret_offset);
                        for (int off = 0; off < 16; off += 8) {
                            cg_emit_mov_reg_mem(gen->cg, REG_RCX, REG_RDX, off);
                            cg_emit_mov_mem_reg(gen->cg, REG_RAX, off, REG_RCX);
                        }
                    } else {
                        int tag = any_tag_for_expr(e);
                        generate_from_ast(gen, e);
                        if (tag == ANY_TAG_FLOAT)
                            cg_emit_movd_xmm_to_gpr(gen->cg, REG_RAX, REG_XMM0);
                        cg_emit_mov_reg_reg(gen->cg, REG_RDX, REG_RAX);
                        cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, current_sret_offset);
                        cg_emit_mov_mem_reg(gen->cg, REG_RAX, 0, REG_RDX);
                        cg_emit_mov_reg_imm32(gen->cg, REG_RCX, (uint32_t)tag);
                        cg_emit_mov_mem_reg(gen->cg, REG_RAX, 8, REG_RCX);
                    }
                } else {
                    cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, current_sret_offset);
                    cg_emit_xor_reg_reg(gen->cg, REG_RCX, REG_RCX);
                    cg_emit_mov_mem_reg(gen->cg, REG_RAX, 0, REG_RCX);
                    cg_emit_mov_mem_reg(gen->cg, REG_RAX, 8, REG_RCX);
                }
            } else if (current_ret_struct && current_sret_offset != 0) {
                /* %rax points at the aggregate being returned. Copy every
                   field into the caller's destination and leave that pointer
                   in %rax as well. */
                cg_emit_mov_reg_reg(gen->cg, REG_RDX, REG_RAX);
                cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, current_sret_offset);
                for (int i = 0; i < current_ret_struct->field_count; i++) {
                    int off = current_ret_struct->fields[i].offset;
                    cg_emit_mov_reg_mem(gen->cg, REG_RCX, REG_RDX, off);
                    cg_emit_mov_mem_reg(gen->cg, REG_RAX, off, REG_RCX);
                }
            }
            for (int i = active_defer_count - 1; i >= 0; i--) {
                generate_from_ast(gen, active_defers[i]);
            }
            emit_epilogue(gen);
            break;
        }
        
        case AST_VAR_DECL: {
            temp_reset(gen);
            if (node->bool_value) {
                char label[64];
                snprintf(label, sizeof(label), ".static_var_%d", static_var_count);
                if (static_var_count < 2048) {
                    StaticVarEntry* sv = &static_vars[static_var_count++];
                    sv->var_name = strdup(node->token.text);
                    sv->label_name = strdup(label);
                    sv->type = node->int_value;
                    sv->initial_value = 0;
                    sv->initial_float = 0.0f;
                    sv->is_volatile = node->is_volatile;
                    
                    if (node->child_count > 0) {
                        ASTNode* init = node->children[0];
                        if (init->type == AST_LITERAL_EXPR) {
                            sv->initial_value = init->int_value;
                        } else if (init->type == NODE_FLOAT_LIT) {
                            sv->initial_float = init->float_value;
                        }
                    }
                }
                add_var(node->token.text, 0, node->int_value, node->string_value);
                if (env_count > 0)
                    env[env_count - 1].is_volatile = node->is_volatile;
            } else {
                int alloc_size = 8;
                bool is_array = false;
                int array_size = 0;
                
                if (node->string_value != NULL) alloc_size = get_type_size(node->string_value, 0);
                else if (node->int_value == TOK_KW_BYTE || node->int_value == TOK_KW_CHAR || node->int_value == TOK_KW_BOOL) alloc_size = 1;
                else if (node->int_value == TOK_KW_WORD) alloc_size = 2;
                else if (node->int_value == TOK_KW_DWORD || node->int_value == TOK_KW_FLOAT ||
                         node->int_value == TOK_KW_HALF) alloc_size = 4;
                else if (node->int_value == TOK_KW_FIXED) {
                    is_array = true;
                    if (node->child_count > 0 && node->children[0]->type == NODE_NUMBER) {
                        array_size = node->children[0]->int_value;
                    }
                    TokenType elem_t = (TokenType)node->char_value;
                    alloc_size = (elem_t == TOK_KW_ANY ? 16 : 8) * array_size;
                } else if (node->int_value == TOK_KW_ANY) {
                    alloc_size = 16;
                } else if (node->int_value == TOK_KW_DYN) {
                    alloc_size = 24;
                } else if (node->int_value == TOK_KW_SLICE) {
                    alloc_size = 16;
                } else if (node->int_value == TOK_KW_RAW) {
                    alloc_size = get_type_size(node->string_value, 0);
                } else {
                    alloc_size = get_type_size(node->string_value, node->int_value);
                }
                
                // Align stack allocation
                if (alloc_size >= 8) current_stack = (current_stack + 7) & ~7;
                else if (alloc_size >= 4) current_stack = (current_stack + 3) & ~3;
                else if (alloc_size >= 2) current_stack = (current_stack + 1) & ~1;
                
                current_stack += alloc_size;
                int var_offset = -current_stack;
                add_var(node->token.text, var_offset, node->int_value, node->string_value);
                if (env_count > 0)
                    env[env_count - 1].is_volatile = node->is_volatile;
                
                if (is_array) {
                    env[env_count - 1].is_array = true;
                    env[env_count - 1].array_size = array_size;
                } else if (node->int_value == TOK_KW_DYN) {
                    // Initialize dyn to {0, 0, 0}
                    cg_emit_byte(gen->cg, 0x48); cg_emit_byte(gen->cg, 0x31); cg_emit_byte(gen->cg, 0xC0); // xor rax, rax
                    cg_emit_mov_mem_reg(gen->cg, REG_RBP, var_offset, REG_RAX);
                    cg_emit_mov_mem_reg(gen->cg, REG_RBP, var_offset + 8, REG_RAX);
                    cg_emit_mov_mem_reg(gen->cg, REG_RBP, var_offset + 16, REG_RAX);
                } else if (node->int_value == TOK_KW_SLICE) {
                    // Initialize slice to {0, 0}
                    cg_emit_byte(gen->cg, 0x48); cg_emit_byte(gen->cg, 0x31); cg_emit_byte(gen->cg, 0xC0); // xor rax, rax
                    cg_emit_mov_mem_reg(gen->cg, REG_RBP, var_offset, REG_RAX);
                    cg_emit_mov_mem_reg(gen->cg, REG_RBP, var_offset + 8, REG_RAX);
                }
                
                int init_child_idx = (node->int_value == TOK_KW_FIXED) ? 1 : 0;
                if (node->int_value == TOK_KW_ANY) {
                    /* Tagged payload: clear both words, then store the value
                       and the static tag of the initializer. */
                    cg_emit_xor_reg_reg(gen->cg, REG_RAX, REG_RAX);
                    cg_emit_mov_mem_reg(gen->cg, REG_RBP, var_offset, REG_RAX);
                    cg_emit_mov_mem_reg(gen->cg, REG_RBP, var_offset + 8, REG_RAX);
                    if (node->child_count > 0) {
                        ASTNode* init = node->children[0];
                        if (is_any_expr(init)) {
                            gen_any_value(gen, init);
                            cg_emit_mov_reg_reg(gen->cg, REG_RDX, REG_RAX);
                            cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RDX, 0);
                            cg_emit_mov_mem_reg(gen->cg, REG_RBP, var_offset, REG_RAX);
                            cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RDX, 8);
                            cg_emit_mov_mem_reg(gen->cg, REG_RBP, var_offset + 8, REG_RAX);
                        } else {
                            int tag = any_tag_for_expr(init);
                            generate_from_ast(gen, init);
                            if (tag == ANY_TAG_FLOAT)
                                cg_emit_movd_xmm_to_gpr(gen->cg, REG_RAX, REG_XMM0);
                            cg_emit_mov_mem_reg(gen->cg, REG_RBP, var_offset, REG_RAX);
                            cg_emit_mov_reg_imm32(gen->cg, REG_RAX, (uint32_t)tag);
                            cg_emit_mov_mem_reg(gen->cg, REG_RBP, var_offset + 8, REG_RAX);
                        }
                    }
                } else if (node->child_count > init_child_idx) {
                    ASTNode* init = node->children[init_child_idx];
                    if (init->type == AST_STRUCT_LITERAL && node->string_value != NULL && !is_array) {
                        StructType* st = lookup_struct(node->string_value);
                        if (st != NULL) {
                            for (int i = 0; i < init->child_count && i < st->field_count; i++) {
                                ASTNode* elem = init->children[i];
                                int fld_off = var_offset + st->fields[i].offset;
                                if (st->fields[i].field_type == TOK_KW_ANY &&
                                    st->fields[i].array_size > 0 &&
                                    elem->type == AST_STRUCT_LITERAL) {
                                    int n = elem->child_count;
                                    if (n > st->fields[i].array_size)
                                        n = st->fields[i].array_size;
                                    for (int j = 0; j < n; j++) {
                                        ASTNode* item = elem->children[j];
                                        int slot = fld_off + j * 16;
                                        if (is_any_expr(item)) {
                                            gen_any_value(gen, item);
                                            cg_emit_mov_reg_reg(gen->cg, REG_RDX, REG_RAX);
                                            cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RDX, 0);
                                            cg_emit_mov_reg_mem(gen->cg, REG_RCX, REG_RDX, 8);
                                        } else {
                                            int tag = any_tag_for_expr(item);
                                            generate_from_ast(gen, item);
                                            if (tag == ANY_TAG_FLOAT)
                                                cg_emit_movd_xmm_to_gpr(gen->cg, REG_RAX, REG_XMM0);
                                            cg_emit_mov_reg_imm32(gen->cg, REG_RCX, (uint32_t)tag);
                                        }
                                        cg_emit_mov_mem_reg(gen->cg, REG_RBP, slot, REG_RAX);
                                        cg_emit_mov_mem_reg(gen->cg, REG_RBP, slot + 8, REG_RCX);
                                    }
                                } else if (st->fields[i].field_type == TOK_KW_ANY) {
                                    if (is_any_expr(elem)) {
                                        gen_any_value(gen, elem);
                                        cg_emit_mov_reg_reg(gen->cg, REG_RDX, REG_RAX);
                                        cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RDX, 0);
                                        cg_emit_mov_reg_mem(gen->cg, REG_RCX, REG_RDX, 8);
                                    } else {
                                        int tag = any_tag_for_expr(elem);
                                        generate_from_ast(gen, elem);
                                        if (tag == ANY_TAG_FLOAT)
                                            cg_emit_movd_xmm_to_gpr(gen->cg, REG_RAX, REG_XMM0);
                                        cg_emit_mov_reg_imm32(gen->cg, REG_RCX, (uint32_t)tag);
                                    }
                                    cg_emit_mov_mem_reg(gen->cg, REG_RBP, fld_off, REG_RAX);
                                    cg_emit_mov_mem_reg(gen->cg, REG_RBP, fld_off + 8, REG_RCX);
                                } else {
                                    generate_from_ast(gen, elem);
                                    if (st->fields[i].field_type == TOK_KW_FLOAT ||
                                        st->fields[i].field_type == TOK_KW_HALF) {
                                        cg_emit_movss_mem_xmm(gen->cg, REG_RBP, fld_off, REG_XMM0);
                                    } else {
                                        cg_emit_mov_mem_reg(gen->cg, REG_RBP, fld_off, REG_RAX);
                                    }
                                }
                            }
                        }
                    } else if (init->type == AST_STRUCT_LITERAL && is_array) {
                        /* {1,2,3,4} must land in the array's own slots. Falling
                           through to the generic path stored the literal's temp
                           *address* there, so a[i] read a pointer. */
                        TokenType elem_t = (TokenType)node->char_value;
                        bool elem_is_float = (elem_t == TOK_KW_FLOAT || elem_t == TOK_KW_HALF);
                        bool elem_is_any = (elem_t == TOK_KW_ANY);
                        int elem_stride = elem_is_any ? 16 : 8;
                        for (int i = 0; i < init->child_count && i < array_size; i++) {
                            ASTNode* elem = init->children[i];
                            if (elem_is_any) {
                                if (is_any_expr(elem)) {
                                    gen_any_value(gen, elem);
                                    cg_emit_mov_reg_reg(gen->cg, REG_RDX, REG_RAX);
                                    cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RDX, 0);
                                    cg_emit_mov_reg_mem(gen->cg, REG_RCX, REG_RDX, 8);
                                } else {
                                    int tag = any_tag_for_expr(elem);
                                    generate_from_ast(gen, elem);
                                    if (tag == ANY_TAG_FLOAT)
                                        cg_emit_movd_xmm_to_gpr(gen->cg, REG_RAX, REG_XMM0);
                                    cg_emit_mov_reg_imm32(gen->cg, REG_RCX, (uint32_t)tag);
                                }
                                cg_emit_mov_mem_reg(gen->cg, REG_RBP,
                                                    var_offset + i * elem_stride, REG_RAX);
                                cg_emit_mov_mem_reg(gen->cg, REG_RBP,
                                                    var_offset + i * elem_stride + 8, REG_RCX);
                            } else {
                                generate_from_ast(gen, elem);
                                if (elem_is_float)
                                    cg_emit_movss_mem_xmm(gen->cg, REG_RBP, var_offset + i * elem_stride, REG_XMM0);
                                else
                                    cg_emit_mov_mem_reg(gen->cg, REG_RBP, var_offset + i * elem_stride, REG_RAX);
                            }
                        }
                    } else if (init->type == AST_STRUCT_LITERAL && node->int_value == TOK_KW_DYN) {
                        int count = init->child_count;
                        int cap = count < 4 ? 4 : count;
                        // sys_mmap(0, cap * 8, 3, 0x22, -1, 0)
                        cg_emit_mov_reg_imm32(gen->cg, REG_RAX, 9);
                        cg_emit_mov_reg_imm32(gen->cg, REG_RDI, 0);
                        cg_emit_mov_reg_imm32(gen->cg, REG_RSI, cap * 8);
                        cg_emit_mov_reg_imm32(gen->cg, REG_RDX, 3);
                        cg_emit_mov_reg_imm32(gen->cg, REG_R10, 0x22);
                        cg_emit_mov_reg_imm32(gen->cg, REG_R8, -1);
                        cg_emit_mov_reg_imm32(gen->cg, REG_R9, 0);
                        cg_emit_syscall(gen->cg);
                        // Save buffer pointer to local dyn struct
                        cg_emit_mov_mem_reg(gen->cg, REG_RBP, var_offset, REG_RAX);
                        cg_emit_mov_reg_imm64(gen->cg, REG_RDX, count);
                        cg_emit_mov_mem_reg(gen->cg, REG_RBP, var_offset + 8, REG_RDX);
                        cg_emit_mov_reg_imm64(gen->cg, REG_RDX, cap);
                        cg_emit_mov_mem_reg(gen->cg, REG_RBP, var_offset + 16, REG_RDX);
                        // Populate elements
                        for (int i = 0; i < count; i++) {
                            generate_from_ast(gen, init->children[i]);
                            cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, var_offset);
                            cg_emit_mov_mem_reg(gen->cg, REG_RDX, i * 8, REG_RAX);
                        }
                    } else if (init->type == AST_CALL_EXPR && init->string_value &&
                               lookup_struct(init->string_value) != NULL &&
                               node->string_value != NULL &&
                               lookup_struct(node->string_value) != NULL) {
                        /* `P r = make_p();` returns a pointer to the callee's
                           result buffer; copy the fields into `r`. */
                        StructType* dst_st = lookup_struct(node->string_value);
                        StructType* src_st = lookup_struct(init->string_value);
                        generate_from_ast(gen, init);
                        cg_emit_mov_reg_reg(gen->cg, REG_RDX, REG_RAX);
                        int n = dst_st->field_count < src_st->field_count
                                    ? dst_st->field_count
                                    : src_st->field_count;
                        for (int i = 0; i < n; i++) {
                            cg_emit_mov_reg_mem(gen->cg, REG_RCX, REG_RDX,
                                                src_st->fields[i].offset);
                            cg_emit_mov_mem_reg(gen->cg, REG_RBP,
                                                var_offset + dst_st->fields[i].offset,
                                                REG_RCX);
                        }
                    } else if (init->type == AST_UNARY_EXPR &&
                               init->token.type == TOK_KW_MOVE &&
                               init->child_count > 0 &&
                               init->children[0]->type == AST_IDENTIFIER_EXPR &&
                               node->string_value &&
                               lookup_struct(node->string_value) != NULL) {
                        /* `P q = move p;` transfers every field and clears the
                           source, instead of only moving the first 8 bytes. */
                        StructType* dst_st = lookup_struct(node->string_value);
                        VarEnv* src_env = lookup_var_env(init->children[0]->token.text);
                        if (dst_st && src_env) {
                            for (int i = 0; i < dst_st->field_count; i++) {
                                cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP,
                                                    src_env->offset + dst_st->fields[i].offset);
                                cg_emit_mov_mem_reg(gen->cg, REG_RBP,
                                                    var_offset + dst_st->fields[i].offset,
                                                    REG_RAX);
                                cg_emit_xor_reg_reg(gen->cg, REG_RCX, REG_RCX);
                                cg_emit_mov_mem_reg(gen->cg, REG_RBP,
                                                    src_env->offset + dst_st->fields[i].offset,
                                                    REG_RCX);
                            }
                        }
                    } else {
                        StructType* dst_st = node->string_value
                                                 ? lookup_struct(node->string_value)
                                                 : NULL;
                        VarEnv* src_env = (init->type == AST_IDENTIFIER_EXPR)
                                              ? lookup_var_env(init->token.text)
                                              : NULL;
                        StructType* src_st = (src_env && src_env->type_name)
                                                 ? lookup_struct(src_env->type_name)
                                                 : NULL;
                        if (dst_st != NULL && src_st != NULL) {
                            int n = dst_st->field_count < src_st->field_count
                                        ? dst_st->field_count
                                        : src_st->field_count;
                            for (int i = 0; i < n; i++) {
                                cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP,
                                                    src_env->offset + src_st->fields[i].offset);
                                cg_emit_mov_mem_reg(gen->cg, REG_RBP,
                                                    var_offset + dst_st->fields[i].offset,
                                                    REG_RAX);
                            }
                        } else {
                            generate_from_ast(gen, init);
                            if (node->int_value == TOK_KW_FLOAT || node->int_value == TOK_KW_HALF) {
                                cg_emit_movss_mem_xmm(gen->cg, REG_RBP, var_offset, REG_XMM0);
                            } else if (node->int_value == TOK_KW_SLICE || node->int_value == TOK_KW_DYN) {
                                cg_emit_mov_mem_reg(gen->cg, REG_RBP, var_offset, REG_RAX);
                                cg_emit_mov_mem_reg(gen->cg, REG_RBP, var_offset + 8, REG_RDX);
                            } else {
                                if (alloc_size == 1) cg_emit_mov_mem_reg8(gen->cg, REG_RBP, var_offset, REG_RAX);
                                else if (alloc_size == 2) cg_emit_mov_mem_reg16(gen->cg, REG_RBP, var_offset, REG_RAX);
                                else if (alloc_size == 4) cg_emit_mov_mem_reg32(gen->cg, REG_RBP, var_offset, REG_RAX);
                                else cg_emit_mov_mem_reg(gen->cg, REG_RBP, var_offset, REG_RAX);
                            }
                        }
                    }
                }
            }
            break;
        }
        
        case AST_LITERAL_EXPR: {
            if (node->token.type == TOK_STRING_LITERAL) {
                char label[32];
                snprintf(label, sizeof(label), ".str%zu", gen->string_table_size);
                const char* str = node->string_value ? node->string_value : node->token.text;
                size_t len = strlen(str);
                add_string(gen, str, len);
                pt_add_patch(gen->pt, cg_get_size(gen->cg) + 3, label, false);
                cg_emit_lea_reg_rip(gen->cg, REG_RAX, 0);
            } else {
                cg_emit_mov_reg_imm64(gen->cg, REG_RAX, node->int_value);
            }
            break;
        }
        case AST_STRUCT_LITERAL: {
            int size = node->child_count * 8;
            int start = gen->temp_stack_offset;
            gen->temp_stack_offset += size;
            /* Fields grow upward from the returned pointer. The old downward
               layout put `_1` at pointer-8, so `return (7, 9)` copied garbage
               even though the fields were present in memory. */
            int base = -(start + size);
            StructType* lit_st = node->string_value ? lookup_struct(node->string_value) : NULL;
            for (int i = 0; i < node->child_count; i++) {
                generate_from_ast(gen, node->children[i]);
                bool fld_is_float = lit_st && i < lit_st->field_count &&
                                    (lit_st->fields[i].field_type == TOK_KW_FLOAT ||
                                     lit_st->fields[i].field_type == TOK_KW_HALF);
                if (fld_is_float)
                    cg_emit_movss_mem_xmm(gen->cg, REG_RBP, base + i * 8, REG_XMM0);
                else
                    cg_emit_mov_mem_reg(gen->cg, REG_RBP, base + i * 8, REG_RAX);
            }
            cg_emit_lea_reg_mem(gen->cg, REG_RAX, REG_RBP, base);
            break;
        }
        
        case NODE_FLOAT_LIT: {
            /* The literal lives in the read-only float pool; loading it
               directly from there avoids staging it through a fixed scratch
               slot on the stack, which used to overwrite a local variable. */
            size_t idx = gen->float_pool_size;
            if (idx < MAX_FLOAT_POOL) {
                gen->float_pool[idx] = node->float_value;
                gen->float_pool_size++;
            }
            char label[32];
            snprintf(label, sizeof(label), ".flt%zu", idx);
            pt_add_patch(gen->pt, cg_get_size(gen->cg) + 4, label, false);
            cg_emit_movss_xmm_rip(gen->cg, REG_XMM0, 0);
            break;
        }
        
        case NODE_NAN_LIT: {
            size_t idx = gen->float_pool_size;
            if (idx < MAX_FLOAT_POOL) {
                uint32_t nan_bits = 0x7FC00000;
                float nan_val;
                memcpy(&nan_val, &nan_bits, 4);
                gen->float_pool[idx] = nan_val;
                gen->float_pool_size++;
            }
            char label[32];
            snprintf(label, sizeof(label), ".flt%zu", idx);
            pt_add_patch(gen->pt, cg_get_size(gen->cg) + 4, label, false);
            cg_emit_movss_xmm_rip(gen->cg, REG_XMM0, 0);
            break;
        }
        
        case NODE_INF_LIT: {
            size_t idx = gen->float_pool_size;
            if (idx < MAX_FLOAT_POOL) {
                uint32_t inf_bits = 0x7F800000;
                float inf_val;
                memcpy(&inf_val, &inf_bits, 4);
                gen->float_pool[idx] = inf_val;
                gen->float_pool_size++;
            }
            char label[32];
            snprintf(label, sizeof(label), ".flt%zu", idx);
            pt_add_patch(gen->pt, cg_get_size(gen->cg) + 4, label, false);
            cg_emit_movss_xmm_rip(gen->cg, REG_XMM0, 0);
            break;
        }
        
        case AST_UNSAFE_BLOCK: {
            for (int i = 0; i < node->child_count; i++) {
                generate_from_ast(gen, node->children[i]);
            }
            break;
        }
        
        case AST_CAST_EXPR: {
            ASTNode* src_expr = node->children[0];
            int dest_type = node->int_value;
            if (is_any_expr(src_expr)) {
                emit_any_operand(gen, src_expr); /* RAX payload, RDX tag */
                if (dest_type == TOK_KW_FLOAT || dest_type == TOK_KW_HALF) {
                    char conv[64], done[64];
                    int id = gen->label_counter++;
                    snprintf(conv, sizeof(conv), ".any_cast_f_%d", id);
                    snprintf(done, sizeof(done), ".any_cast_fd_%d", id);
                    cg_emit_cmp_reg_imm32(gen->cg, REG_RDX, ANY_TAG_FLOAT);
                    cg_emit_jne_label(gen->cg, gen->pt, conv);
                    cg_emit_movd_gpr_to_xmm(gen->cg, REG_XMM0, REG_RAX);
                    cg_emit_jmp_label(gen->cg, gen->pt, done);
                    cg_emit_label(gen->cg, gen->pt, conv);
                    cg_emit_cvtsi2ss_xmm_reg(gen->cg, REG_XMM0, REG_RAX);
                    cg_emit_label(gen->cg, gen->pt, done);
                } else if (dest_type != TOK_KW_STRING) {
                    char done[64];
                    int id = gen->label_counter++;
                    snprintf(done, sizeof(done), ".any_cast_i_%d", id);
                    cg_emit_cmp_reg_imm32(gen->cg, REG_RDX, ANY_TAG_FLOAT);
                    cg_emit_jne_label(gen->cg, gen->pt, done);
                    cg_emit_movd_gpr_to_xmm(gen->cg, REG_XMM1, REG_RAX);
                    cg_emit_cvttss2si_reg_xmm(gen->cg, REG_RAX, REG_XMM1);
                    cg_emit_label(gen->cg, gen->pt, done);
                }
                break;
            }
            generate_from_ast(gen, src_expr);
            bool src_is_float = is_float_expr(src_expr);
            if (src_is_float) {
                if (dest_type == TOK_KW_INT || dest_type == TOK_KW_BOOL || dest_type == TOK_KW_CHAR || dest_type == TOK_KW_PTR) {
                    cg_emit_cvttss2si_reg_xmm(gen->cg, REG_RAX, REG_XMM0);
                }
            } else {
                if (dest_type == TOK_KW_FLOAT) {
                    cg_emit_cvtsi2ss_xmm_reg(gen->cg, REG_XMM0, REG_RAX);
                }
            }
            break;
        }
        
        case NODE_BOOL_LIT: {
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, node->bool_value ? 1 : 0);
            break;
        }
        
        case NODE_THIS:
        case NODE_SUPER: {
            cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, 16);
            break;
        }
        
        case NODE_CHAR_LIT: {
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, (int)node->char_value);
            break;
        }
        
        case AST_IDENTIFIER_EXPR: {
                StaticVarEntry* sv = lookup_static_var(node->token.text);
            if (sv) {
                cg_emit_lea_reg_rip(gen->cg, REG_RAX, 0);
                pt_add_patch(gen->pt, cg_get_size(gen->cg) - 4, sv->label_name, false);
                if (sv->type == TOK_KW_FLOAT) {
                    cg_emit_movss_xmm_mem(gen->cg, REG_XMM0, REG_RAX, 0);
                } else {
                    cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RAX, 0);
                }
            } else {
                VarEnv* var_env = lookup_var_env(node->token.text);
                if (var_env) {
                    if (var_env->is_array || (var_env->type_name != NULL && var_env->type != TOK_KW_PTR && var_env->type != TOK_KW_REF && var_env->type != TOK_KW_OWN && var_env->type != TOK_KW_RAW && var_env->offset < 16)) {
                        cg_emit_lea_reg_mem(gen->cg, REG_RAX, REG_RBP, var_env->offset);
                    } else if (var_env->type_name != NULL && var_env->type != TOK_KW_PTR && var_env->type != TOK_KW_REF && var_env->type != TOK_KW_OWN && var_env->type != TOK_KW_RAW && var_env->offset >= 16) {
                        cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, var_env->offset);
                    } else if (var_env->type == TOK_KW_FLOAT || var_env->type == TOK_KW_HALF) {
                        cg_emit_movss_xmm_mem(gen->cg, REG_XMM0, REG_RBP, var_env->offset);
                    } else if (var_env->type == TOK_KW_BYTE || var_env->type == TOK_KW_CHAR || var_env->type == TOK_KW_BOOL) {
                        cg_emit_movzx_byte(gen->cg, REG_RAX, REG_RBP, var_env->offset);
                    } else if (var_env->type == TOK_KW_WORD) {
                        cg_emit_movzx_word(gen->cg, REG_RAX, REG_RBP, var_env->offset);
                    } else if (var_env->type == TOK_KW_DWORD) {
                        cg_emit_movsxd_reg_mem(gen->cg, REG_RAX, REG_RBP, var_env->offset);
                    } else {
                        cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, var_env->offset);
                    }
                } else if (current_class_name) {
                    StructType* st = lookup_struct(current_class_name);
                    int field_offset = get_field_offset(st, node->token.text);
                    if (field_offset != -1) {
                        cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, 16); // load 'this' (first parameter)
                        cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RAX, field_offset);
                    } else {
                        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 0);
                    }
                } else {
                    cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 0);
                }
            }
            break;
        }

        case AST_BINARY_EXPR: {
            if (node->token.type == TOK_ASSIGN) {
                ASTNode* left = node->children[0];
                if (is_any_lvalue(left)) {
                    ASTNode* rhs = node->children[1];
                    gen_any_address(gen, left);
                    cg_emit_push_reg(gen->cg, REG_RAX);
                    if (is_any_expr(rhs)) {
                        gen_any_value(gen, rhs);
                        cg_emit_mov_reg_reg(gen->cg, REG_RDX, REG_RAX);
                        cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RDX, 0);
                        cg_emit_mov_reg_mem(gen->cg, REG_RCX, REG_RDX, 8);
                    } else {
                        int tag = any_tag_for_expr(rhs);
                        generate_from_ast(gen, rhs);
                        if (tag == ANY_TAG_FLOAT)
                            cg_emit_movd_xmm_to_gpr(gen->cg, REG_RAX, REG_XMM0);
                        cg_emit_mov_reg_imm32(gen->cg, REG_RCX, (uint32_t)tag);
                    }
                    cg_emit_pop_reg(gen->cg, REG_R10);
                    cg_emit_mov_mem_reg(gen->cg, REG_R10, 0, REG_RAX);
                    cg_emit_mov_mem_reg(gen->cg, REG_R10, 8, REG_RCX);
                    break;
                }
                if (left->type == AST_IDENTIFIER_EXPR) {
                    VarEnv* dst_env = lookup_var_env(left->token.text);
                    /* Assigning one struct to another copies the whole
                       layout; storing the address of the source instead left
                       the destination holding a pointer. */
                    if (dst_env && dst_env->type_name &&
                        lookup_struct(dst_env->type_name)) {
                        StructType* dst_st = lookup_struct(dst_env->type_name);
                        ASTNode* rhs = node->children[1];
                        bool rhs_is_move = (rhs->type == AST_UNARY_EXPR &&
                                            rhs->token.type == TOK_KW_MOVE &&
                                            rhs->child_count > 0 &&
                                            rhs->children[0]->type == AST_IDENTIFIER_EXPR);
                        ASTNode* src_node = rhs_is_move ? rhs->children[0] : rhs;
                        VarEnv* src_env = (src_node->type == AST_IDENTIFIER_EXPR)
                                              ? lookup_var_env(src_node->token.text)
                                              : NULL;
                        if (!src_env && src_node->type == AST_CALL_EXPR &&
                            src_node->string_value &&
                            lookup_struct(src_node->string_value) != NULL) {
                            StructType* src_st = lookup_struct(src_node->string_value);
                            generate_from_ast(gen, src_node);
                            cg_emit_mov_reg_reg(gen->cg, REG_RDX, REG_RAX);
                            int n = dst_st->field_count < src_st->field_count
                                        ? dst_st->field_count
                                        : src_st->field_count;
                            for (int i = 0; i < n; i++) {
                                cg_emit_mov_reg_mem(gen->cg, REG_RCX, REG_RDX,
                                                    src_st->fields[i].offset);
                                cg_emit_mov_mem_reg(gen->cg, REG_RBP,
                                                    dst_env->offset + dst_st->fields[i].offset,
                                                    REG_RCX);
                            }
                            break;
                        }
                        if (src_env && src_env->type_name &&
                            lookup_struct(src_env->type_name)) {
                            for (int i = 0; i < dst_st->field_count; i++) {
                                cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP,
                                                     src_env->offset + dst_st->fields[i].offset);
                                cg_emit_mov_mem_reg(gen->cg, REG_RBP,
                                                     dst_env->offset + dst_st->fields[i].offset, REG_RAX);
                                if (rhs_is_move) {
                                    cg_emit_xor_reg_reg(gen->cg, REG_RCX, REG_RCX);
                                    cg_emit_mov_mem_reg(gen->cg, REG_RBP,
                                                         src_env->offset + dst_st->fields[i].offset,
                                                         REG_RCX);
                                }
                            }
                            break;
                        }
                    }
                    generate_from_ast(gen, node->children[1]);
                    StaticVarEntry* sv = lookup_static_var(left->token.text);
                    if (sv) {
                        cg_emit_lea_reg_rip(gen->cg, REG_RCX, 0);
                        pt_add_patch(gen->pt, cg_get_size(gen->cg) - 4, sv->label_name, false);
                        if (sv->type == TOK_KW_FLOAT) {
                            cg_emit_movss_mem_xmm(gen->cg, REG_RCX, 0, REG_XMM0);
                        } else {
                            cg_emit_mov_mem_reg(gen->cg, REG_RCX, 0, REG_RAX);
                        }
                    } else {
                        VarEnv* var_env = lookup_var_env(left->token.text);
                        if (var_env) {
                            if (var_env->type == TOK_KW_FLOAT || var_env->type == TOK_KW_HALF) {
                                cg_emit_movss_mem_xmm(gen->cg, REG_RBP, var_env->offset, REG_XMM0);
                            } else if (var_env->type == TOK_KW_BYTE || var_env->type == TOK_KW_CHAR || var_env->type == TOK_KW_BOOL) {
                                cg_emit_mov_mem_reg8(gen->cg, REG_RBP, var_env->offset, REG_RAX);
                            } else if (var_env->type == TOK_KW_WORD) {
                                cg_emit_mov_mem_reg16(gen->cg, REG_RBP, var_env->offset, REG_RAX);
                            } else if (var_env->type == TOK_KW_DWORD) {
                                cg_emit_mov_mem_reg32(gen->cg, REG_RBP, var_env->offset, REG_RAX);
                            } else if (var_env->type == TOK_KW_SLICE || var_env->type == TOK_KW_DYN) {
                                cg_emit_mov_mem_reg(gen->cg, REG_RBP, var_env->offset, REG_RAX);
                                cg_emit_mov_mem_reg(gen->cg, REG_RBP, var_env->offset + 8, REG_RDX);
                            } else {
                                cg_emit_mov_mem_reg(gen->cg, REG_RBP, var_env->offset, REG_RAX);
                            }
                        } else if (current_class_name) {
                            StructType* st = lookup_struct(current_class_name);
                            int field_offset = get_field_offset(st, left->token.text);
                            if (field_offset != -1) {
                                cg_emit_mov_reg_mem(gen->cg, REG_RCX, REG_RBP, 16); // load 'this' pointer
                                cg_emit_mov_mem_reg(gen->cg, REG_RCX, field_offset, REG_RAX); // store value into field
                            }
                        }
                    }
                } else if (left->type == AST_UNARY_EXPR && left->token.type == TOK_STAR) {
                    if (deref_is_float(left)) {
                        generate_from_ast(gen, left->children[0]); // address -> RAX
                        cg_emit_push_reg(gen->cg, REG_RAX);
                        generate_from_ast(gen, node->children[1]); // value -> XMM0
                        cg_emit_pop_reg(gen->cg, REG_RAX);
                        cg_emit_movss_mem_xmm(gen->cg, REG_RAX, 0, REG_XMM0);
                        break;
                    }
                    generate_from_ast(gen, node->children[1]); // Evaluate RHS -> RAX
                    cg_emit_push_reg(gen->cg, REG_RAX);        // Push RHS
                    generate_from_ast(gen, left->children[0]); // Evaluate pointer expression -> RAX
                    cg_emit_pop_reg(gen->cg, REG_RCX);         // Pop RHS -> RCX
                    
                    bool is_32bit_ptr = false;
                    bool is_8bit_ptr = false;
                    int elem_w = ptr_element_width(left->children[0]);
                    if (elem_w == 1) is_8bit_ptr = true;
                    else if (elem_w == 4) is_32bit_ptr = true;
                    
                    ASTNode* rhs = node->children[1];
                    if (!is_8bit_ptr && !is_32bit_ptr && rhs) {
                        /* The width of the *pointee* decides how many bytes
                           are written. It is only guessed from the right hand
                           side when the pointer type is unknown — and `int` is
                           64 bit wide in Magnetar, so an integer must never
                           be narrowed to four bytes. */
                        if (rhs->type == AST_IDENTIFIER_EXPR) {
                            VarEnv* rv = lookup_var_env(rhs->token.text);
                            if (rv) {
                                if (rv->type == TOK_KW_CHAR || rv->type == TOK_KW_BYTE || rv->type == TOK_KW_BOOL) is_8bit_ptr = true;
                                else if (rv->type == TOK_KW_DWORD) is_32bit_ptr = true;
                            }
                        }
                    }
                    
                    if (is_8bit_ptr) {
                        cg_emit_mov_mem_reg8(gen->cg, REG_RAX, 0, REG_RCX);
                    } else if (is_32bit_ptr) {
                        cg_emit_mov_mem_reg32(gen->cg, REG_RAX, 0, REG_RCX);
                    } else {
                        cg_emit_mov_mem_reg(gen->cg, REG_RAX, 0, REG_RCX);
                    }
                } else if (left->type == AST_MEMBER_ACCESS) {
                    // Evaluate RHS -> RAX or XMM0
                    generate_from_ast(gen, node->children[1]); // Evaluate RHS
                    // Determine if RHS is float (based on whether the LHS field is a float)
                    bool rhs_is_float = is_member_access_float(left);
                    
                    if (rhs_is_float) {
                        cg_emit_sub_reg_imm32(gen->cg, REG_RSP, 16);
                        cg_emit_movss_mem_xmm(gen->cg, REG_RSP, 0, REG_XMM0);
                    } else {
                        cg_emit_push_reg(gen->cg, REG_RAX);
                    }
                    ASTNode* base = left->children[0];
                    if (base->type == AST_IDENTIFIER_EXPR) {
                        VarEnv* var_env = lookup_var_env(base->token.text);
                        if (var_env && var_env->type_name != NULL && var_env->type != TOK_KW_PTR && var_env->type != TOK_KW_REF && var_env->type != TOK_KW_OWN && var_env->type != TOK_KW_RAW) {
                            if (var_env->offset < 16) {
                                cg_emit_lea_reg_mem(gen->cg, REG_RAX, REG_RBP, var_env->offset);
                            } else {
                                cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, var_env->offset);
                            }
                        } else {
                            generate_from_ast(gen, base);
                        }
                    } else {
                        generate_from_ast(gen, base);
                    }
                    int offset = resolve_field_offset(left->children[0], left->token.text);
                    if (rhs_is_float) {
                        cg_emit_movss_xmm_mem(gen->cg, REG_XMM0, REG_RSP, 0);
                        cg_emit_add_reg_imm32(gen->cg, REG_RSP, 16);
                        // movss [rax + offset], xmm0
                        uint8_t* buf = cg_get_buffer(gen->cg);
                        int sz = cg_get_size(gen->cg);
                        buf[sz++] = 0xF3; buf[sz++] = 0x0F; buf[sz++] = 0x11; // movss [mem], xmm0
                        if (offset == 0) { buf[sz++] = 0x00; } // [rax]
                        else if (offset >= -128 && offset <= 127) { buf[sz++] = 0x40; buf[sz++] = (uint8_t)offset; }
                        else { buf[sz++] = 0x80; buf[sz++] = (uint8_t)(offset); buf[sz++] = (uint8_t)(offset>>8); buf[sz++] = (uint8_t)(offset>>16); buf[sz++] = (uint8_t)(offset>>24); }
                        gen->cg->size = sz;
                    } else {
                        cg_emit_pop_reg(gen->cg, REG_RCX);         // Pop RHS -> RCX
                        cg_emit_mov_mem_reg(gen->cg, REG_RAX, offset, REG_RCX); // mov [rax + offset], rcx
                    }
                }
                break;
            }

            /* Operations on `any` values pick their meaning from the runtime
               tag (int, float or string) instead of treating the payload as an
               integer unconditionally. */
            if (node->token.type == TOK_PLUS || node->token.type == TOK_MINUS ||
                node->token.type == TOK_STAR || node->token.type == TOK_SLASH ||
                node->token.type == TOK_MOD || node->token.type == TOK_EQ ||
                node->token.type == TOK_NEQ || node->token.type == TOK_LT ||
                node->token.type == TOK_LE || node->token.type == TOK_GT ||
                node->token.type == TOK_GE) {
                if (is_any_expr(node->children[0]) ||
                    (node->child_count > 1 && is_any_expr(node->children[1]))) {
                    emit_any_binary(gen, node);
                    break;
                }
            }

            bool lhs_float = is_float_expr(node->children[0]);
            bool rhs_float = is_float_expr(node->children[1]);
            /* `1 + 2.5` is a float operation: the integer operand has to be
               converted, not reinterpreted as raw float bits. */
            bool is_float = lhs_float || rhs_float;
            bool is_str_op = !is_float && node->token.type != TOK_ASSIGN &&
                             node->token.type != TOK_PLUS_ASSIGN &&
                             node->token.type != TOK_MINUS_ASSIGN &&
                             node->token.type != TOK_STAR_ASSIGN &&
                             node->token.type != TOK_SLASH_ASSIGN &&
                             node->token.type != TOK_SHL_ASSIGN &&
                             node->token.type != TOK_SHR_ASSIGN &&
                             node->token.type != TOK_AND_ASSIGN &&
                             node->token.type != TOK_OR_ASSIGN &&
                             node->token.type != TOK_XOR_ASSIGN &&
                             is_string_expr(node->children[0]) &&
                             is_string_expr(node->children[1]);

            if (is_str_op) {
                /* String + String => __str_concat; string comparisons => __str_cmp */
                generate_from_ast(gen, node->children[0]); // LHS -> RAX
                cg_emit_push_reg(gen->cg, REG_RAX);
                generate_from_ast(gen, node->children[1]); // RHS -> RAX
                cg_emit_mov_reg_reg(gen->cg, REG_RCX, REG_RAX); // RCX = RHS
                cg_emit_pop_reg(gen->cg, REG_RAX);              // RAX = LHS

                bool is_cmp = (node->token.type == TOK_EQ || node->token.type == TOK_NEQ ||
                               node->token.type == TOK_LT || node->token.type == TOK_LE ||
                               node->token.type == TOK_GT || node->token.type == TOK_GE);

                if (node->token.type == TOK_PLUS && !is_cmp) {
                    /* __str_concat(lhs, rhs) — both args on stack */
                    cg_emit_push_reg(gen->cg, REG_RCX); // push RHS
                    cg_emit_push_reg(gen->cg, REG_RAX); // push LHS
                    cg_emit_call_rel32(gen->cg, 0);
                    pt_add_patch(gen->pt, cg_get_size(gen->cg) - 4, "__str_concat", false);
                    cg_emit_add_reg_imm32(gen->cg, REG_RSP, 16);
                } else if (is_cmp) {
                    /* __str_cmp(lhs, rhs) -> RAX = <0, 0, >0 */
                    cg_emit_push_reg(gen->cg, REG_RCX);
                    cg_emit_push_reg(gen->cg, REG_RAX);
                    cg_emit_call_rel32(gen->cg, 0);
                    pt_add_patch(gen->pt, cg_get_size(gen->cg) - 4, "__str_cmp", false);
                    cg_emit_add_reg_imm32(gen->cg, REG_RSP, 16);
                    /* map strcmp result to boolean 0/1 */
                    cg_emit_test_reg_reg(gen->cg, REG_RAX, REG_RAX);
                    uint8_t* buf = cg_get_buffer(gen->cg);
                    int sz = cg_get_size(gen->cg);
                    buf[sz++] = 0x0F;
                    if      (node->token.type == TOK_EQ)  buf[sz++] = 0x94; // sete
                    else if (node->token.type == TOK_NEQ) buf[sz++] = 0x95; // setne
                    else if (node->token.type == TOK_LT)  buf[sz++] = 0x9C; // setl
                    else if (node->token.type == TOK_LE)  buf[sz++] = 0x9E; // setle
                    else if (node->token.type == TOK_GT)  buf[sz++] = 0x9F; // setg
                    else                                  buf[sz++] = 0x9D; // setge
                    buf[sz++] = 0xC0; // AL
                    gen->cg->size = sz;
                    buf = cg_get_buffer(gen->cg); sz = cg_get_size(gen->cg);
                    buf[sz++] = 0x48; buf[sz++] = 0x0F; buf[sz++] = 0xB6; buf[sz++] = 0xC0; // movzx rax, al
                    gen->cg->size = sz;
                }
                break;
            }

            if (node->token.type == TOK_AND || node->token.type == TOK_OR) {
                bool is_and = (node->token.type == TOK_AND);
                generate_from_ast(gen, node->children[0]);
                cg_emit_test_reg_reg(gen->cg, REG_RAX, REG_RAX);
                if (is_and) {
                    cg_emit_byte(gen->cg, 0x0F); cg_emit_byte(gen->cg, 0x84); // je rel32
                    cg_emit_byte(gen->cg, 0); cg_emit_byte(gen->cg, 0);
                    cg_emit_byte(gen->cg, 0); cg_emit_byte(gen->cg, 0);
                    int patch_false = cg_get_size(gen->cg) - 4;
                    generate_from_ast(gen, node->children[1]);
                    cg_emit_test_reg_reg(gen->cg, REG_RAX, REG_RAX);
                    cg_emit_byte(gen->cg, 0x0F); cg_emit_byte(gen->cg, 0x95); cg_emit_byte(gen->cg, 0xC0); // setne al
                    cg_emit_byte(gen->cg, 0x48); cg_emit_byte(gen->cg, 0x0F); cg_emit_byte(gen->cg, 0xB6); cg_emit_byte(gen->cg, 0xC0); // movzx rax,al
                    cg_emit_byte(gen->cg, 0xE9); // jmp rel32
                    cg_emit_byte(gen->cg, 0); cg_emit_byte(gen->cg, 0);
                    cg_emit_byte(gen->cg, 0); cg_emit_byte(gen->cg, 0);
                    int patch_end = cg_get_size(gen->cg) - 4;
                    int rel_false = cg_get_size(gen->cg) - patch_false - 4;
                    gen->cg->buffer[patch_false]     = (uint8_t)(rel_false);
                    gen->cg->buffer[patch_false + 1] = (uint8_t)(rel_false >> 8);
                    gen->cg->buffer[patch_false + 2] = (uint8_t)(rel_false >> 16);
                    gen->cg->buffer[patch_false + 3] = (uint8_t)(rel_false >> 24);
                    cg_emit_xor_reg_reg(gen->cg, REG_RAX, REG_RAX);
                    int rel_end = cg_get_size(gen->cg) - patch_end - 4;
                    gen->cg->buffer[patch_end]     = (uint8_t)(rel_end);
                    gen->cg->buffer[patch_end + 1] = (uint8_t)(rel_end >> 8);
                    gen->cg->buffer[patch_end + 2] = (uint8_t)(rel_end >> 16);
                    gen->cg->buffer[patch_end + 3] = (uint8_t)(rel_end >> 24);
                } else {
                    cg_emit_byte(gen->cg, 0x0F); cg_emit_byte(gen->cg, 0x85); // jne rel32
                    cg_emit_byte(gen->cg, 0); cg_emit_byte(gen->cg, 0);
                    cg_emit_byte(gen->cg, 0); cg_emit_byte(gen->cg, 0);
                    int patch_true = cg_get_size(gen->cg) - 4;
                    generate_from_ast(gen, node->children[1]);
                    cg_emit_test_reg_reg(gen->cg, REG_RAX, REG_RAX);
                    cg_emit_byte(gen->cg, 0x0F); cg_emit_byte(gen->cg, 0x95); cg_emit_byte(gen->cg, 0xC0); // setne al
                    cg_emit_byte(gen->cg, 0x48); cg_emit_byte(gen->cg, 0x0F); cg_emit_byte(gen->cg, 0xB6); cg_emit_byte(gen->cg, 0xC0); // movzx rax,al
                    cg_emit_byte(gen->cg, 0xE9); // jmp rel32
                    cg_emit_byte(gen->cg, 0); cg_emit_byte(gen->cg, 0);
                    cg_emit_byte(gen->cg, 0); cg_emit_byte(gen->cg, 0);
                    int patch_end = cg_get_size(gen->cg) - 4;
                    int rel_true = cg_get_size(gen->cg) - patch_true - 4;
                    gen->cg->buffer[patch_true]     = (uint8_t)(rel_true);
                    gen->cg->buffer[patch_true + 1] = (uint8_t)(rel_true >> 8);
                    gen->cg->buffer[patch_true + 2] = (uint8_t)(rel_true >> 16);
                    gen->cg->buffer[patch_true + 3] = (uint8_t)(rel_true >> 24);
                    cg_emit_mov_reg_imm32(gen->cg, REG_RAX, 1);
                    int rel_end = cg_get_size(gen->cg) - patch_end - 4;
                    gen->cg->buffer[patch_end]     = (uint8_t)(rel_end);
                    gen->cg->buffer[patch_end + 1] = (uint8_t)(rel_end >> 8);
                    gen->cg->buffer[patch_end + 2] = (uint8_t)(rel_end >> 16);
                    gen->cg->buffer[patch_end + 3] = (uint8_t)(rel_end >> 24);
                }
                break;
            }

            /* A literal right operand needs no expression evaluation and
               cannot clobber RAX, so keep the left operand in its register
               instead of spilling it through push/pop. This is the first
               register-friendly step toward the full allocator/SysV ABI. */
            ASTNode* rhs_node = node->child_count > 1 ? node->children[1] : NULL;
            bool rhs_const_int = !is_float && rhs_node &&
                rhs_node->type == AST_LITERAL_EXPR &&
                rhs_node->token.type == TOK_INT_LITERAL &&
                rhs_node->token.text;
            int64_t rhs_const_value = 0;
            if (rhs_const_int) {
                char* end = NULL;
                rhs_const_value = strtoll(rhs_node->token.text, &end, 10);
                if (end == rhs_node->token.text || *end != '\0')
                    rhs_const_int = false;
            }

            generate_from_ast(gen, node->children[0]);
            if (is_float) {
                if (!lhs_float) cg_emit_cvtsi2ss_xmm_reg(gen->cg, REG_XMM0, REG_RAX);
                cg_emit_sub_reg_imm32(gen->cg, REG_RSP, 16);
                cg_emit_movss_mem_xmm(gen->cg, REG_RSP, 0, REG_XMM0);
            } else if (!rhs_const_int) {
                cg_emit_push_reg(gen->cg, REG_RAX);
            }
            
            if (rhs_const_int) {
                cg_emit_mov_reg_imm64(gen->cg, REG_RCX, (uint64_t)rhs_const_value);
            } else {
                generate_from_ast(gen, node->children[1]);
            }
            
            if (is_float) {
                if (!rhs_float) cg_emit_cvtsi2ss_xmm_reg(gen->cg, REG_XMM0, REG_RAX);
                // XMM0 = RHS, load LHS from stack into XMM1
                uint8_t* buf = cg_get_buffer(gen->cg);
                int size = cg_get_size(gen->cg);
                // movss xmm1, xmm0  (save rhs into xmm1)
                buf[size++] = 0xF3; buf[size++] = 0x0F; buf[size++] = 0x10; buf[size++] = 0xC8;
                gen->cg->size = size;
                // load lhs into xmm0
                cg_emit_movss_xmm_mem(gen->cg, REG_XMM0, REG_RSP, 0);
                cg_emit_add_reg_imm32(gen->cg, REG_RSP, 16);
                
                if (node->token.type == TOK_PLUS) cg_emit_addss_xmm_xmm(gen->cg, REG_XMM0, REG_XMM1);
                else if (node->token.type == TOK_MINUS) cg_emit_subss_xmm_xmm(gen->cg, REG_XMM0, REG_XMM1);
                else if (node->token.type == TOK_STAR) cg_emit_mulss_xmm_xmm(gen->cg, REG_XMM0, REG_XMM1);
                else if (node->token.type == TOK_SLASH) cg_emit_divss_xmm_xmm(gen->cg, REG_XMM0, REG_XMM1);
                else if (node->token.type == TOK_LT || node->token.type == TOK_LE ||
                         node->token.type == TOK_GT || node->token.type == TOK_GE ||
                         node->token.type == TOK_EQ || node->token.type == TOK_NEQ) {
                    uint8_t* buf = cg_get_buffer(gen->cg);
                    int sz = cg_get_size(gen->cg);
                    // ucomiss xmm0, xmm1
                    buf[sz++] = 0x0F; buf[sz++] = 0x2E; buf[sz++] = 0xC1;
                    // setcc al
                    buf[sz++] = 0x0F;
                    if      (node->token.type == TOK_LT)  buf[sz++] = 0x92; // setb
                    else if (node->token.type == TOK_LE)  buf[sz++] = 0x96; // setbe
                    else if (node->token.type == TOK_GT)  buf[sz++] = 0x97; // seta
                    else if (node->token.type == TOK_GE)  buf[sz++] = 0x93; // setae
                    else if (node->token.type == TOK_EQ)  buf[sz++] = 0x94; // sete
                    else                                  buf[sz++] = 0x95; // setne
                    buf[sz++] = 0xC0; // AL
                    // movzx rax, al
                    buf[sz++] = 0x48; buf[sz++] = 0x0F; buf[sz++] = 0xB6; buf[sz++] = 0xC0;
                    gen->cg->size = sz;
                }
            } else {
                if (!rhs_const_int) {
                    cg_emit_mov_reg_reg(gen->cg, REG_RCX, REG_RAX);
                    cg_emit_pop_reg(gen->cg, REG_RAX);
                }
                if (node->token.type == TOK_PLUS) cg_emit_add_reg_reg(gen->cg, REG_RAX, REG_RCX);
                else if (node->token.type == TOK_MINUS) cg_emit_sub_reg_reg(gen->cg, REG_RAX, REG_RCX);
                else if (node->token.type == TOK_STAR) cg_emit_imul_reg_reg(gen->cg, REG_RAX, REG_RCX);
                else if (node->token.type == TOK_SLASH) {
                    /* idiv treats RDX:RAX as a signed 128-bit dividend, so RAX must be
                       sign-extended into RDX (cqo). Zeroing RDX only works for
                       non-negative values and raises #DE on e.g. -1 / 1. */
                    emit_division_by_zero_guard(gen);
                    uint8_t* qbuf = cg_get_buffer(gen->cg);
                    int qsz = cg_get_size(gen->cg);
                    qbuf[qsz++] = 0x48; qbuf[qsz++] = 0x99; // cqo
                    gen->cg->size = qsz;
                    cg_emit_idiv_reg(gen->cg, REG_RCX);
                }
                else if (node->token.type == TOK_MOD) {
                    emit_division_by_zero_guard(gen);
                    uint8_t* qbuf = cg_get_buffer(gen->cg);
                    int qsz = cg_get_size(gen->cg);
                    qbuf[qsz++] = 0x48; qbuf[qsz++] = 0x99; // cqo
                    gen->cg->size = qsz;
                    cg_emit_idiv_reg(gen->cg, REG_RCX);
                    cg_emit_mov_reg_reg(gen->cg, REG_RAX, REG_RDX);
                }
                else if (node->token.type == TOK_BIT_AND) {
                    uint8_t* buf = cg_get_buffer(gen->cg);
                    int sz = cg_get_size(gen->cg);
                    buf[sz++] = 0x48; buf[sz++] = 0x21; buf[sz++] = 0xC8; // and rax, rcx
                    gen->cg->size = sz;
                }
                else if (node->token.type == TOK_BIT_OR) {
                    uint8_t* buf = cg_get_buffer(gen->cg);
                    int sz = cg_get_size(gen->cg);
                    buf[sz++] = 0x48; buf[sz++] = 0x09; buf[sz++] = 0xC8; // or rax, rcx
                    gen->cg->size = sz;
                }
                else if (node->token.type == TOK_BIT_XOR) {
                    uint8_t* buf = cg_get_buffer(gen->cg);
                    int sz = cg_get_size(gen->cg);
                    buf[sz++] = 0x48; buf[sz++] = 0x31; buf[sz++] = 0xC8; // xor rax, rcx
                    gen->cg->size = sz;
                }
                else if (node->token.type == TOK_SHL) {
                    uint8_t* buf = cg_get_buffer(gen->cg);
                    int sz = cg_get_size(gen->cg);
                    buf[sz++] = 0x48; buf[sz++] = 0xD3; buf[sz++] = 0xE0; // shl rax, cl
                    gen->cg->size = sz;
                }
                else if (node->token.type == TOK_SHR) {
                    uint8_t* buf = cg_get_buffer(gen->cg);
                    int sz = cg_get_size(gen->cg);
                    buf[sz++] = 0x48; buf[sz++] = 0xD3; buf[sz++] = 0xE8; // shr rax, cl
                    gen->cg->size = sz;
                }
                // Comparison operators -> result in RAX (0 or 1)
                else if (node->token.type == TOK_LT || node->token.type == TOK_LE ||
                         node->token.type == TOK_GT || node->token.type == TOK_GE ||
                         node->token.type == TOK_EQ || node->token.type == TOK_NEQ) {
                    cg_emit_cmp_reg_reg(gen->cg, REG_RAX, REG_RCX);
                    uint8_t* buf = cg_get_buffer(gen->cg);
                    int sz = cg_get_size(gen->cg);
                    buf[sz++] = 0x0F;
                    if      (node->token.type == TOK_LT)  buf[sz++] = 0x9C;
                    else if (node->token.type == TOK_LE)  buf[sz++] = 0x9E;
                    else if (node->token.type == TOK_GT)  buf[sz++] = 0x9F;
                    else if (node->token.type == TOK_GE)  buf[sz++] = 0x9D;
                    else if (node->token.type == TOK_EQ)  buf[sz++] = 0x94;
                    else                                  buf[sz++] = 0x95;
                    buf[sz++] = 0xC0; // AL
                    gen->cg->size = sz;
                    // movzx rax, al
                    buf = cg_get_buffer(gen->cg); sz = cg_get_size(gen->cg);
                    buf[sz++] = 0x48; buf[sz++] = 0x0F; buf[sz++] = 0xB6; buf[sz++] = 0xC0;
                    gen->cg->size = sz;
                }
            }
            break;
        }
        
        // cond ? then : else  -- both branches leave the value in RAX/XMM0
        case AST_TERNARY_EXPR: {
            if (node->child_count < 3) break;
            generate_from_ast(gen, node->children[0]); // cond -> RAX
            cg_emit_test_reg_reg(gen->cg, REG_RAX, REG_RAX);
            cg_emit_je_rel32(gen->cg, 0);
            int patch_else = cg_get_size(gen->cg) - 4;
            generate_from_ast(gen, node->children[1]); // then branch
            cg_emit_jmp_rel32(gen->cg, 0);
            int patch_end = cg_get_size(gen->cg) - 4;
            int32_t else_offset = cg_get_size(gen->cg) - (patch_else + 4);
            for (int i = 0; i < 4; i++) {
                gen->cg->buffer[patch_else + i] = (uint8_t)((else_offset >> (i * 8)) & 0xFF);
            }
            generate_from_ast(gen, node->children[2]); // else branch
            int32_t end_offset = cg_get_size(gen->cg) - (patch_end + 4);
            for (int i = 0; i < 4; i++) {
                gen->cg->buffer[patch_end + i] = (uint8_t)((end_offset >> (i * 8)) & 0xFF);
            }
            break;
        }
        
        case AST_SLICE_EXPR: {
            generate_from_ast(gen, node->children[1]); // start -> RAX
            cg_emit_push_reg(gen->cg, REG_RAX);
            
            generate_from_ast(gen, node->children[2]); // end -> RAX
            cg_emit_push_reg(gen->cg, REG_RAX);
            
            generate_from_ast(gen, node->children[0]); // receiver -> RAX
            
            cg_emit_pop_reg(gen->cg, REG_R8); // end
            cg_emit_pop_reg(gen->cg, REG_R9); // start
            
            cg_emit_mov_reg_reg(gen->cg, REG_RDX, REG_R8);
            cg_emit_sub_reg_reg(gen->cg, REG_RDX, REG_R9); // RDX = len = end - start
            
            cg_emit_imul_reg_imm32(gen->cg, REG_R9, REG_R9, 8);
            cg_emit_add_reg_reg(gen->cg, REG_RAX, REG_R9); // RAX = ptr = base + start * 8
            break;
        }
        
        case AST_CALL_EXPR: {
            ASTNode* func_name = node->children[0];
            if (func_name->type == AST_IDENTIFIER_EXPR && strcmp(func_name->token.text, "fn_addr") == 0) {
                if (node->child_count >= 2) {
                    ASTNode* name_arg = node->children[1];
                    const char* sym = NULL;
                    if (name_arg->type == AST_LITERAL_EXPR && name_arg->token.type == TOK_STRING_LITERAL) {
                        sym = name_arg->string_value ? name_arg->string_value : name_arg->token.text;
                    }
                    if (sym) {
                        cg_emit_lea_reg_rip(gen->cg, REG_RAX, 0);
                        pt_add_patch(gen->pt, cg_get_size(gen->cg) - 4, sym, false);
                    } else {
                        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 0);
                    }
                } else {
                    cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 0);
                }
                break;
            }
            if (func_name->type == AST_IDENTIFIER_EXPR && strcmp(func_name->token.text, "len") == 0) {
                if (node->child_count >= 2) {
                    ASTNode* arg = node->children[1];
                    generate_from_ast(gen, arg); // RAX = pointer to string
                    /* strlen inline: rdi = str, rcx = count */
                    cg_emit_mov_reg_reg(gen->cg, REG_RDI, REG_RAX);
                    cg_emit_xor_reg_reg(gen->cg, REG_RCX, REG_RCX);
                    int loop = cg_get_size(gen->cg);
                    /* cmp byte [rdi + rcx], 0 */
                    uint8_t* buf = cg_get_buffer(gen->cg);
                    int sz = cg_get_size(gen->cg);
                    buf[sz++] = 0x80; buf[sz++] = 0x3C; buf[sz++] = 0x0F; buf[sz++] = 0x00;
                    gen->cg->size = sz;
                    /* je done */
                    cg_emit_byte(gen->cg, 0x74); cg_emit_byte(gen->cg, 0);
                    int je_done = cg_get_size(gen->cg) - 1;
                    /* inc rcx */
                    cg_emit_byte(gen->cg, 0x48); cg_emit_byte(gen->cg, 0xFF); cg_emit_byte(gen->cg, 0xC1);
                    /* jmp loop */
                    int jmp_back = loop - (cg_get_size(gen->cg) + 2);
                    cg_emit_byte(gen->cg, 0xEB); cg_emit_byte(gen->cg, (uint8_t)jmp_back);
                    /* done: mov rax, rcx */
                    gen->cg->buffer[je_done] = cg_get_size(gen->cg) - je_done - 1;
                    cg_emit_mov_reg_reg(gen->cg, REG_RAX, REG_RCX);
                } else {
                    cg_emit_mov_reg_imm32(gen->cg, REG_RAX, 0);
                }
                break;
            }
            if (func_name->type == AST_IDENTIFIER_EXPR && strcmp(func_name->token.text, "print") == 0) {
                for (int arg_idx = 1; arg_idx < node->child_count; arg_idx++) {
                    ASTNode* arg = node->children[arg_idx];
                    if (is_any_expr(arg)) {
                        char l_f[64], l_s[64], l_b[64], l_false[64], l_done[64];
                        int id = gen->label_counter++;
                        snprintf(l_f, sizeof(l_f), ".any_flt_%d", id);
                        snprintf(l_s, sizeof(l_s), ".any_str_%d", id);
                        snprintf(l_b, sizeof(l_b), ".any_bool_%d", id);
                        snprintf(l_false, sizeof(l_false), ".any_false_%d", id);
                        snprintf(l_done, sizeof(l_done), ".any_done_%d", id);
                        gen_any_value(gen, arg);
                        cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RAX, 8);
                        cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RAX, 0);
                        cg_emit_cmp_reg_imm32(gen->cg, REG_RDX, ANY_TAG_FLOAT);
                        cg_emit_je_label(gen->cg, gen->pt, l_f);
                        cg_emit_cmp_reg_imm32(gen->cg, REG_RDX, ANY_TAG_STRING);
                        cg_emit_je_label(gen->cg, gen->pt, l_s);
                        cg_emit_cmp_reg_imm32(gen->cg, REG_RDX, ANY_TAG_BOOL);
                        cg_emit_je_label(gen->cg, gen->pt, l_b);
                        emit_print_int(gen); /* int, char or unset */
                        cg_emit_jmp_label(gen->cg, gen->pt, l_done);
                        cg_emit_label(gen->cg, gen->pt, l_f);
                        cg_emit_movd_gpr_to_xmm(gen->cg, REG_XMM0, REG_RAX);
                        emit_print_float(gen);
                        cg_emit_jmp_label(gen->cg, gen->pt, l_done);
                        cg_emit_label(gen->cg, gen->pt, l_s);
                        emit_print_string_var(gen);
                        cg_emit_jmp_label(gen->cg, gen->pt, l_done);
                        cg_emit_label(gen->cg, gen->pt, l_b);
                        cg_emit_test_reg_reg(gen->cg, REG_RAX, REG_RAX);
                        cg_emit_je_label(gen->cg, gen->pt, l_false);
                        emit_print_string(gen, "true", 4);
                        cg_emit_jmp_label(gen->cg, gen->pt, l_done);
                        cg_emit_label(gen->cg, gen->pt, l_false);
                        emit_print_string(gen, "false", 5);
                        cg_emit_label(gen->cg, gen->pt, l_done);
                    } else if (arg->type == AST_LITERAL_EXPR && arg->token.type == TOK_STRING_LITERAL) {
                        const char* str = arg->string_value ? arg->string_value : arg->token.text;
                        size_t len = strlen(str);
                        emit_print_string(gen, str, len);
                    } else if (is_string_expr(arg)) {
                        generate_from_ast(gen, arg);
                        emit_print_string_var(gen);
                    } else if (is_float_expr(arg)) {
                        generate_from_ast(gen, arg);
                        emit_print_float(gen);
                    } else if (is_bool_expr(arg) || arg->type == NODE_BOOL_LIT || (arg->type == AST_IDENTIFIER_EXPR && get_var_type(arg->token.text) == TOK_KW_BOOL)) {
                        generate_from_ast(gen, arg);
                        cg_emit_test_reg_reg(gen->cg, REG_RAX, REG_RAX);
                        cg_emit_je_rel8(gen->cg, 0);
                        int je_offset = cg_get_size(gen->cg) - 1;
                        emit_print_string(gen, "true", 4);
                        cg_emit_jmp_rel8(gen->cg, 0);
                        int jmp2_offset = cg_get_size(gen->cg) - 1;
                        gen->cg->buffer[je_offset] = cg_get_size(gen->cg) - (je_offset + 1);
                        emit_print_string(gen, "false", 5);
                        gen->cg->buffer[jmp2_offset] = cg_get_size(gen->cg) - (jmp2_offset + 1);
                    } else if (arg->type == NODE_CHAR_LIT || (arg->type == AST_IDENTIFIER_EXPR && get_var_type(arg->token.text) == TOK_KW_CHAR)) {
                        generate_from_ast(gen, arg);
                        emit_print_int(gen);
                    } else if (arg->type == AST_IDENTIFIER_EXPR && get_var_type(arg->token.text) == TOK_KW_STRING) {
                        generate_from_ast(gen, arg);
                        emit_print_string_var(gen);
                    } else {
                        generate_from_ast(gen, arg);
                        emit_print_int(gen);
                    }
                }
            } else {
                FuncSig* call_sig =
                    func_name->type == AST_IDENTIFIER_EXPR
                        ? lookup_func_sig(func_name->token.text,
                                          node->child_count - 1)
                        : NULL;
                int any_arg_extra = 0;
                for (int i = node->child_count - 1; i >= 1; i--) {
                    ASTNode* arg = node->children[i];
                    bool param_is_any =
                        call_sig && (i - 1) < call_sig->param_count &&
                        call_sig->param_types[i - 1] == TOK_KW_ANY;
                    if (param_is_any) {
                        any_arg_extra++;
                        if (is_any_expr(arg)) {
                            gen_any_value(gen, arg);
                            cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RAX, 0);
                            cg_emit_mov_reg_mem(gen->cg, REG_RCX, REG_RAX, 8);
                            cg_emit_push_reg(gen->cg, REG_RCX); /* tag */
                            cg_emit_push_reg(gen->cg, REG_RDX); /* payload */
                        } else {
                            int tag = any_tag_for_expr(arg);
                            generate_from_ast(gen, arg);
                            if (tag == ANY_TAG_FLOAT)
                                cg_emit_movd_xmm_to_gpr(gen->cg, REG_RAX, REG_XMM0);
                            cg_emit_mov_reg_imm32(gen->cg, REG_RCX, (uint32_t)tag);
                            cg_emit_push_reg(gen->cg, REG_RCX); /* tag */
                            cg_emit_push_reg(gen->cg, REG_RAX); /* payload */
                        }
                        continue;
                    }
                    generate_from_ast(gen, arg);
                    if (is_float_expr(arg)) {
                        // movq rax, xmm0
                        uint8_t* buf = cg_get_buffer(gen->cg);
                        int sz = cg_get_size(gen->cg);
                        buf[sz++] = 0x66; buf[sz++] = 0x48; buf[sz++] = 0x0F; buf[sz++] = 0x7E; buf[sz++] = 0xC0;
                        gen->cg->size = sz;
                    }
                    cg_emit_push_reg(gen->cg, REG_RAX);
                }
                
                char mangled[256] = "";
                if (func_name->type == AST_MEMBER_ACCESS) {
                    ASTNode* receiver = func_name->children[0];
                    const char* method_name = func_name->token.text;
                    const char* class_name = NULL;
                    
                    if (receiver->type == AST_IDENTIFIER_EXPR) {
                        VarEnv* v = lookup_var_env(receiver->token.text);
                        if (v && v->type == TOK_KW_DYN) {
                            if (strcmp(method_name, "push") == 0) {
                                cg_emit_lea_reg_mem(gen->cg, REG_RAX, REG_RBP, v->offset);
                                cg_emit_push_reg(gen->cg, REG_RAX);
                                cg_emit_call_rel32(gen->cg, 0);
                                pt_add_patch(gen->pt, cg_get_size(gen->cg) - 4, "__dyn_push", false);
                                cg_emit_add_reg_imm32(gen->cg, REG_RSP, node->child_count * 8);
                                break;
                            } else if (strcmp(method_name, "pop") == 0) {
                                cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, v->offset + 8);
                                cg_emit_test_reg_reg(gen->cg, REG_RDX, REG_RDX);
                                cg_emit_byte(gen->cg, 0x74); cg_emit_byte(gen->cg, 0x18);
                                cg_emit_sub_reg_imm32(gen->cg, REG_RDX, 1);
                                cg_emit_mov_mem_reg(gen->cg, REG_RBP, v->offset + 8, REG_RDX);
                                cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, v->offset);
                                cg_emit_shl_reg_imm8(gen->cg, REG_RDX, 3);
                                cg_emit_add_reg_reg(gen->cg, REG_RAX, REG_RDX);
                                cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RAX, 0);
                                cg_emit_add_reg_imm32(gen->cg, REG_RSP, (node->child_count - 1) * 8);
                                break;
                            } else if (strcmp(method_name, "clear") == 0) {
                                cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 0);
                                cg_emit_mov_mem_reg(gen->cg, REG_RBP, v->offset + 8, REG_RAX);
                                cg_emit_add_reg_imm32(gen->cg, REG_RSP, (node->child_count - 1) * 8);
                                break;
                            } else if (strcmp(method_name, "len") == 0 || strcmp(method_name, "size") == 0) {
                                cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, v->offset + 8);
                                cg_emit_add_reg_imm32(gen->cg, REG_RSP, (node->child_count - 1) * 8);
                                break;
                            } else if (strcmp(method_name, "cap") == 0 || strcmp(method_name, "capacity") == 0) {
                                cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, v->offset + 16);
                                cg_emit_add_reg_imm32(gen->cg, REG_RSP, (node->child_count - 1) * 8);
                                break;
                            }
                        }
                    }
                    
                    if (receiver->type == NODE_THIS) {
                        class_name = current_class_name;
                    } else if (receiver->type == NODE_SUPER) {
                        class_name = lookup_parent_class(current_class_name);
                    } else if (receiver->type == AST_IDENTIFIER_EXPR) {
                        class_name = get_var_type_name(receiver->token.text);
                    }
                    
                    generate_from_ast(gen, receiver);
                    cg_emit_push_reg(gen->cg, REG_RAX);
                    
                    const char* resolve_class = class_name;
                    bool found = false;
                    while (resolve_class != NULL) {
                        snprintf(mangled, sizeof(mangled), "%s_%s", resolve_class, method_name);
                        for (int f = 0; f < func_entry_count; f++) {
                            if (strcmp(func_entries[f].name, mangled) == 0) {
                                found = true;
                                break;
                            }
                        }
                        if (found) break;
                        resolve_class = lookup_parent_class(resolve_class);
                    }
                    if (!found) {
                        snprintf(mangled, sizeof(mangled), "%s_%s", class_name ? class_name : "", method_name);
                    }
                } else {
                    if (func_name->token.text) {
                        strncpy(mangled, func_name->token.text, sizeof(mangled) - 1);
                        mangled[sizeof(mangled) - 1] = '\0';
                    }
                }
                
                StructType* ret_st = ret_struct_for(node->string_value);
                int sret_off = 0;
                if (ret_st) {
                    /* The aggregate result buffer belongs to the expression
                       temporary region, not to the function's locals. Bumping
                       current_stack here used to shift every later `-current_stack`
                       reference in the enclosing initializer, so `P r = make();`
                       copied the fields into the wrong slot. */
                    int ret_size = (ret_st->size + 7) & ~7;
                    gen->temp_stack_offset = (gen->temp_stack_offset + 7) & ~7;
                    /* The buffer occupies [-off, -off + ret_size), so the
                       offset must include the size. Using -offset and then
                       growing upward wrote fields past %rbp and clobbered the
                       saved frame for three-field structs/tuples. */
                    gen->temp_stack_offset += ret_size;
                    sret_off = -gen->temp_stack_offset;
                    cg_emit_lea_reg_mem(gen->cg, REG_RAX, REG_RBP, sret_off);
                }
                pt_add_patch(gen->pt, cg_get_size(gen->cg) + 1, mangled, false);
                cg_emit_call_rel32(gen->cg, 0);
                if (ret_st) {
                    cg_emit_lea_reg_mem(gen->cg, REG_RAX, REG_RBP, sret_off);
                }
                
                int push_count = node->child_count - 1;
                if (func_name->type == AST_MEMBER_ACCESS) {
                    push_count++;
                }
                if (push_count > 0 || any_arg_extra > 0) {
                    cg_emit_add_reg_imm32(gen->cg, REG_RSP,
                                          push_count * 8 + any_arg_extra * 8);
                }
            }
            break;
        }
        
        case AST_STRUCT_DECL:
            for (int i = 0; i < node->child_count; i++) {
                generate_from_ast(gen, node->children[i]);
            }
            break;
            
        case AST_ALLOC_EXPR: {
            generate_from_ast(gen, node->children[0]); // Evaluate count -> RAX
            int type_size = alloc_elem_size(node->string_value, node->int_value);
            cg_emit_mov_reg_imm64(gen->cg, REG_RCX, type_size);
            cg_emit_imul_reg_reg(gen->cg, REG_RAX, REG_RCX);
            cg_emit_add_reg_imm32(gen->cg, REG_RAX, 8); // total size including 8 bytes metadata
            
            cg_emit_push_reg(gen->cg, REG_RAX); // Save total size
            cg_emit_pop_reg(gen->cg, REG_RSI);  // Pop total size into RSI
            cg_emit_push_reg(gen->cg, REG_RSI); // Push it back to keep it on stack
            
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 9); // sys_mmap
            cg_emit_mov_reg_imm64(gen->cg, REG_RDI, 0);
            // RSI is already populated!
            cg_emit_mov_reg_imm64(gen->cg, REG_RDX, 3);
            cg_emit_mov_reg_imm64(gen->cg, REG_R10, 34);
            cg_emit_mov_reg_imm64(gen->cg, REG_R8, -1);
            cg_emit_mov_reg_imm64(gen->cg, REG_R9, 0);
            cg_emit_syscall(gen->cg);
            
            cg_emit_pop_reg(gen->cg, REG_RCX);
            cg_emit_mov_mem_reg(gen->cg, REG_RAX, 0, REG_RCX);
            cg_emit_add_reg_imm32(gen->cg, REG_RAX, 8);
            break;
        }
        
        case AST_NEW_EXPR: {
            int type_size = alloc_elem_size(node->string_value, node->int_value);
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, type_size + 8);
            
            cg_emit_push_reg(gen->cg, REG_RAX);
            cg_emit_pop_reg(gen->cg, REG_RSI);
            cg_emit_push_reg(gen->cg, REG_RSI);
            
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 9); // sys_mmap
            cg_emit_mov_reg_imm64(gen->cg, REG_RDI, 0);
            // RSI is already populated!
            cg_emit_mov_reg_imm64(gen->cg, REG_RDX, 3);
            cg_emit_mov_reg_imm64(gen->cg, REG_R10, 34);
            cg_emit_mov_reg_imm64(gen->cg, REG_R8, -1);
            cg_emit_mov_reg_imm64(gen->cg, REG_R9, 0);
            cg_emit_syscall(gen->cg);
            
            cg_emit_pop_reg(gen->cg, REG_RCX);
            cg_emit_mov_mem_reg(gen->cg, REG_RAX, 0, REG_RCX);
            cg_emit_add_reg_imm32(gen->cg, REG_RAX, 8);
            break;
        }
        
        case AST_FREE_STMT: {
            generate_from_ast(gen, node->children[0]); // Evaluate ptr -> RAX
            cg_emit_sub_reg_imm32(gen->cg, REG_RAX, 8);
            cg_emit_mov_reg_reg(gen->cg, REG_RDI, REG_RAX);
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RDI, 0);
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 11); // sys_munmap
            cg_emit_syscall(gen->cg);
            break;
        }
        
        case AST_MEMBER_ACCESS: {
            ASTNode* left = node->children[0];
            if (left->type == AST_IDENTIFIER_EXPR && is_enum_type(left->token.text)) {
                int val = lookup_enum_value(left->token.text, node->token.text);
                cg_emit_mov_reg_imm64(gen->cg, REG_RAX, val);
            } else if (left->type == AST_IDENTIFIER_EXPR && lookup_var_env(left->token.text) && lookup_var_env(left->token.text)->type == TOK_KW_DYN) {
                VarEnv* v = lookup_var_env(left->token.text);
                if (strcmp(node->token.text, "len") == 0 || strcmp(node->token.text, "length") == 0) {
                    cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, v->offset + 8);
                } else if (strcmp(node->token.text, "cap") == 0 || strcmp(node->token.text, "capacity") == 0) {
                    cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, v->offset + 16);
                } else {
                    cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 0);
                }
            } else {
                if (left->type == AST_IDENTIFIER_EXPR) {
                    VarEnv* var_env = lookup_var_env(left->token.text);
                    if (var_env && var_env->type_name != NULL && var_env->type != TOK_KW_PTR && var_env->type != TOK_KW_REF && var_env->type != TOK_KW_OWN && var_env->type != TOK_KW_RAW) {
                        if (var_env->offset < 16) {
                            cg_emit_lea_reg_mem(gen->cg, REG_RAX, REG_RBP, var_env->offset);
                        } else {
                            cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, var_env->offset);
                        }
                    } else {
                        generate_from_ast(gen, left); // Evaluate base pointer -> RAX
                    }
                } else {
                    generate_from_ast(gen, left); // Evaluate base pointer -> RAX
                }
                int offset = resolve_field_offset(left, node->token.text);
                bool field_is_float = is_member_access_float(node);
                if (is_member_access_array(node) || is_member_access_any(node)) {
                    /* An array or `any` field is addressed, not loaded:
                       callers read array slots and the 16-byte tagged box
                       through this address. */
                    cg_emit_lea_reg_mem(gen->cg, REG_RAX, REG_RAX, offset);
                } else if (field_is_float) {
                    // movss xmm0, [rax + offset]
                    uint8_t* buf = cg_get_buffer(gen->cg);
                    int sz = cg_get_size(gen->cg);
                    buf[sz++] = 0xF3; buf[sz++] = 0x0F; buf[sz++] = 0x10; // movss xmm0, [mem]
                    if (offset == 0) { buf[sz++] = 0x00; }
                    else if (offset >= -128 && offset <= 127) { buf[sz++] = 0x40; buf[sz++] = (uint8_t)offset; }
                    else { buf[sz++] = 0x80; buf[sz++] = (uint8_t)(offset); buf[sz++] = (uint8_t)(offset>>8); buf[sz++] = (uint8_t)(offset>>16); buf[sz++] = (uint8_t)(offset>>24); }
                    gen->cg->size = sz;
                } else {
                    cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RAX, offset);
                }
            }
            break;
        }
        
        case AST_UNARY_EXPR: {
            ASTNode* operand = node->children[0];
            if (node->token.type == TOK_BIT_AND || node->token.type == TOK_KW_BORROW) { // &x or borrow x
                if (operand->type == AST_IDENTIFIER_EXPR) {
                    int offset = get_var_offset(operand->token.text);
                    cg_emit_lea_reg_mem(gen->cg, REG_RAX, REG_RBP, offset);
                }
            } else if (node->token.type == TOK_BIT_NOT) { // ~x -> not rax
                generate_from_ast(gen, operand);
                uint8_t* nbuf = cg_get_buffer(gen->cg);
                int nsz = cg_get_size(gen->cg);
                nbuf[nsz++] = 0x48; nbuf[nsz++] = 0xF7; nbuf[nsz++] = 0xD0; // not rax
                gen->cg->size = nsz;
            } else if (node->token.type == TOK_MINUS) { // -x -> neg rax
                generate_from_ast(gen, operand);
                if (is_float_expr(operand)) {
                    /* A float lives in %xmm0, so the sign bit of the value
                       has to be flipped there. `neg rax` would touch an
                       unrelated register and leave the float untouched. */
                    cg_emit_movd_xmm_to_gpr(gen->cg, REG_R10, REG_XMM0);
                    cg_emit_btc_reg_imm8(gen->cg, REG_R10, 31); /* flip the sign */
                    cg_emit_movd_gpr_to_xmm(gen->cg, REG_XMM0, REG_R10);
                } else {
                    uint8_t* nbuf = cg_get_buffer(gen->cg);
                    int nsz = cg_get_size(gen->cg);
                    nbuf[nsz++] = 0x48; nbuf[nsz++] = 0xF7; nbuf[nsz++] = 0xD8; // neg rax
                    gen->cg->size = nsz;
                }
            } else if (node->token.type == TOK_STAR) { // *p
                generate_from_ast(gen, operand); // Evaluate pointer expr -> RAX
                /* An `any` array slot is a 16-byte tagged box; hand out its
                   address so the any helpers can read both words. */
                if (node->int_value == TOK_KW_ANY)
                    break;
                bool is_byte = false;
                bool is_32bit = false;
                int elem_w = ptr_element_width(operand);
                /* For `cast<char*>(p)[i]` the index rewrite hides the pointee
                   type behind an add expression, so fall back to what the
                   parser recorded on the deref node itself. */
                if ((elem_w == 0 || elem_w == 8) && node->string_value) {
                    const char* tn = node->string_value;
                    if (strcmp(tn, "char") == 0 || strcmp(tn, "byte") == 0 ||
                        strcmp(tn, "bool") == 0)
                        elem_w = 1;
                    else if (strcmp(tn, "dword") == 0 || strcmp(tn, "float") == 0 ||
                             strcmp(tn, "half") == 0)
                        elem_w = 4;
                }
                if (elem_w == 1) is_byte = true;
                else if (elem_w == 4) is_32bit = true;
                
                if (is_byte) {
                    cg_emit_movzx_byte(gen->cg, REG_RAX, REG_RAX, 0); // movzx rax, byte ptr [rax]
                } else if (is_32bit) {
                    if (deref_is_float(node))
                        cg_emit_movss_xmm_mem(gen->cg, REG_XMM0, REG_RAX, 0);
                    else
                        cg_emit_movsxd_reg_mem(gen->cg, REG_RAX, REG_RAX, 0); // movsxd rax, dword ptr [rax]
                } else {
                    cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RAX, 0); // mov rax, [rax]
                }
            } else if (node->token.type == TOK_KW_MOVE) {
                if (operand->type == AST_IDENTIFIER_EXPR) {
                    VarEnv* mv = lookup_var_env(operand->token.text);
                    TokenType mt = mv ? (TokenType)mv->type : get_var_type(operand->token.text);
                    int offset = get_var_offset(operand->token.text);
                    emit_load_scalar_at(gen, REG_RBP, offset, mt);
                    emit_zero_scalar_at(gen, REG_RBP, offset, mt);
                } else if (operand->type == AST_MEMBER_ACCESS) {
                    ASTNode* left = operand->children[0];
                    /* RSI is used as the address scratch because `movss` in the
                       encoder does not emit a REX.B prefix for extended base
                       registers, so R10/R11 would address the wrong register. */
                    if (left->type == AST_IDENTIFIER_EXPR) {
                        VarEnv* be = lookup_var_env(left->token.text);
                        if (be && be->type_name && be->type != TOK_KW_PTR &&
                            be->type != TOK_KW_REF && be->type != TOK_KW_OWN &&
                            be->type != TOK_KW_RAW) {
                            if (be->offset < 16)
                                cg_emit_lea_reg_mem(gen->cg, REG_RSI, REG_RBP, be->offset);
                            else
                                cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, be->offset);
                        } else {
                            generate_from_ast(gen, left);
                            cg_emit_mov_reg_reg(gen->cg, REG_RSI, REG_RAX);
                        }
                    } else {
                        generate_from_ast(gen, left);
                        cg_emit_mov_reg_reg(gen->cg, REG_RSI, REG_RAX);
                    }
                    int foff = resolve_field_offset(left, operand->token.text);
                    StructField* fld = resolve_member_field(operand);
                    TokenType ft = fld ? (TokenType)fld->field_type : TOK_KW_INT;
                    emit_load_scalar_at(gen, REG_RSI, foff, ft);
                    emit_zero_scalar_at(gen, REG_RSI, foff, ft);
                } else if (operand->type == AST_UNARY_EXPR && operand->token.type == TOK_STAR) {
                    generate_from_ast(gen, operand->children[0]);
                    cg_emit_mov_reg_reg(gen->cg, REG_RSI, REG_RAX);
                    int elem_w = ptr_element_width(operand->children[0]);
                    if ((elem_w == 0 || elem_w == 8) && operand->string_value) {
                        const char* tn = operand->string_value;
                        if (strcmp(tn, "char") == 0 || strcmp(tn, "byte") == 0 ||
                            strcmp(tn, "bool") == 0)
                            elem_w = 1;
                        else if (strcmp(tn, "dword") == 0 || strcmp(tn, "float") == 0 ||
                                 strcmp(tn, "half") == 0)
                            elem_w = 4;
                    }
                    TokenType et = TOK_KW_INT;
                    if (elem_w == 1) et = TOK_KW_BYTE;
                    else if (elem_w == 4) et = deref_is_float(operand) ? TOK_KW_FLOAT : TOK_KW_DWORD;
                    emit_load_scalar_at(gen, REG_RSI, 0, et);
                    emit_zero_scalar_at(gen, REG_RSI, 0, et);
                } else {
                    generate_from_ast(gen, operand);
                }
            } else if (node->token.type == TOK_KW_COPY || node->token.type == TOK_KW_CLONE) {
                generate_from_ast(gen, operand); // Evaluate source pointer -> RAX
                cg_emit_test_reg_reg(gen->cg, REG_RAX, REG_RAX);
                cg_emit_je_rel8(gen->cg, 0);
                int patch_null = cg_get_size(gen->cg) - 1;
                
                cg_emit_sub_reg_imm32(gen->cg, REG_RAX, 8);
                cg_emit_mov_reg_mem(gen->cg, REG_R8, REG_RAX, 0);
                
                cg_emit_push_reg(gen->cg, REG_RAX);
                cg_emit_push_reg(gen->cg, REG_R8);
                
                cg_emit_pop_reg(gen->cg, REG_RSI);
                cg_emit_push_reg(gen->cg, REG_RSI);
                
                cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 9);
                cg_emit_mov_reg_imm64(gen->cg, REG_RDI, 0);
                // RSI is already populated!
                cg_emit_mov_reg_imm64(gen->cg, REG_RDX, 3);
                cg_emit_mov_reg_imm64(gen->cg, REG_R10, 34);
                cg_emit_mov_reg_imm64(gen->cg, REG_R8, -1);
                cg_emit_mov_reg_imm64(gen->cg, REG_R9, 0);
                cg_emit_syscall(gen->cg);
                
                cg_emit_pop_reg(gen->cg, REG_RCX);
                cg_emit_pop_reg(gen->cg, REG_RSI);
                
                cg_emit_mov_mem_reg(gen->cg, REG_RAX, 0, REG_RCX);
                cg_emit_mov_reg_reg(gen->cg, REG_RDI, REG_RAX);
                
                // Emit rep movsb (F3 A4)
                uint8_t* buf = cg_get_buffer(gen->cg);
                int sz = cg_get_size(gen->cg);
                buf[sz++] = 0xF3; buf[sz++] = 0xA4;
                gen->cg->size = sz;
                
                cg_emit_add_reg_imm32(gen->cg, REG_RAX, 8);
                
                int offset_null = cg_get_size(gen->cg) - (patch_null + 1);
                buf[patch_null] = offset_null;
            } else if (node->token.type == TOK_NOT) {
                generate_from_ast(gen, operand);
                cg_emit_test_reg_reg(gen->cg, REG_RAX, REG_RAX);
                uint8_t* buf = cg_get_buffer(gen->cg);
                int sz = cg_get_size(gen->cg);
                buf[sz++] = 0x0F; buf[sz++] = 0x94; buf[sz++] = 0xC0; // setz al
                buf[sz++] = 0x48; buf[sz++] = 0x0F; buf[sz++] = 0xB6; buf[sz++] = 0xC0; // movzx rax, al
                gen->cg->size = sz;
            }
            break;
        }
        
        case AST_EXPR_STMT: {
            temp_reset(gen);
            if (node->child_count > 0) {
                generate_from_ast(gen, node->children[0]);
            }
            break;
        }
        
        // if (cond) { then } [else { else }]
        case AST_IF_STMT: {
            if (node->child_count >= 2) {
                generate_from_ast(gen, node->children[0]); // cond -> RAX
                cg_emit_test_reg_reg(gen->cg, REG_RAX, REG_RAX);
                cg_emit_je_rel32(gen->cg, 0);
                int patch_else = cg_get_size(gen->cg) - 4;
                generate_from_ast(gen, node->children[1]); // then block
                if (node->child_count >= 3) {
                    cg_emit_jmp_rel32(gen->cg, 0);
                    int patch_end = cg_get_size(gen->cg) - 4;
                    int32_t else_offset = cg_get_size(gen->cg) - (patch_else + 4);
                    for (int i = 0; i < 4; i++) {
                        gen->cg->buffer[patch_else + i] = (uint8_t)((else_offset >> (i * 8)) & 0xFF);
                    }
                    generate_from_ast(gen, node->children[2]); // else block
                    int32_t end_offset = cg_get_size(gen->cg) - (patch_end + 4);
                    for (int i = 0; i < 4; i++) {
                        gen->cg->buffer[patch_end + i] = (uint8_t)((end_offset >> (i * 8)) & 0xFF);
                    }
                } else {
                    int32_t else_offset = cg_get_size(gen->cg) - (patch_else + 4);
                    for (int i = 0; i < 4; i++) {
                        gen->cg->buffer[patch_else + i] = (uint8_t)((else_offset >> (i * 8)) & 0xFF);
                    }
                }
            }
            break;
        }
        
        // while (cond) { body }  |  do { body } while (cond);
        case AST_WHILE_STMT: {
            if (node->child_count >= 2) {
                if (node->bool_value) {
                    /* do-while: body runs at least once, then condition is tested */
                    int body_start = cg_get_size(gen->cg);
                    loop_push();
                    generate_from_ast(gen, node->children[1]); // body
                    int continue_target = cg_get_size(gen->cg);
                    generate_from_ast(gen, node->children[0]); // condition -> RAX
                    cg_emit_test_reg_reg(gen->cg, REG_RAX, REG_RAX);
                    cg_emit_jne_rel32(gen->cg, 0);
                    int jne_patch = cg_get_size(gen->cg) - 4;
                    cg_patch_rel32(gen->cg, jne_patch, body_start);
                    loop_pop_and_patch(gen->cg, continue_target, cg_get_size(gen->cg));
                } else {
                    int loop_top = cg_get_size(gen->cg);
                    loop_push();
                    generate_from_ast(gen, node->children[0]); // condition -> RAX
                    cg_emit_test_reg_reg(gen->cg, REG_RAX, REG_RAX);
                    cg_emit_je_rel32(gen->cg, 0); // placeholder
                    int patch_exit = cg_get_size(gen->cg) - 4;
                    generate_from_ast(gen, node->children[1]); // body
                    // jump back to top
                    int back_offset = loop_top - (cg_get_size(gen->cg) + 5);
                    cg_emit_jmp_rel32(gen->cg, (int32_t)back_offset);

                    int32_t exit_offset = cg_get_size(gen->cg) - (patch_exit + 4);
                    for (int i = 0; i < 4; i++) {
                        gen->cg->buffer[patch_exit + i] = (uint8_t)((exit_offset >> (i * 8)) & 0xFF);
                    }
                    // `continue` re-tests the condition, `break` leaves after the back-jump
                    loop_pop_and_patch(gen->cg, loop_top, cg_get_size(gen->cg));
                }
            }
            break;
        }

        case AST_BREAK_STMT:
            loop_emit_jump(gen->cg, true);
            break;

        case AST_CONTINUE_STMT:
            loop_emit_jump(gen->cg, false);
            break;
        
        // for (init; cond; post) { body }
        case AST_FOR_STMT: {
            if (node->child_count >= 4) {
                generate_from_ast(gen, node->children[0]); // init
                int loop_top = cg_get_size(gen->cg);
                generate_from_ast(gen, node->children[1]); // cond -> RAX
                cg_emit_test_reg_reg(gen->cg, REG_RAX, REG_RAX);
                cg_emit_je_rel32(gen->cg, 0);
                int patch_exit = cg_get_size(gen->cg) - 4;
                loop_push();
                generate_from_ast(gen, node->children[3]); // body
                // `continue` in a for loop must still run the post statement
                int continue_target = cg_get_size(gen->cg);
                generate_from_ast(gen, node->children[2]); // post
                int back_offset = loop_top - (cg_get_size(gen->cg) + 5);
                cg_emit_jmp_rel32(gen->cg, (int32_t)back_offset);
                
                int32_t exit_offset = cg_get_size(gen->cg) - (patch_exit + 4);
                for (int i = 0; i < 4; i++) {
                    gen->cg->buffer[patch_exit + i] = (uint8_t)((exit_offset >> (i * 8)) & 0xFF);
                }
                loop_pop_and_patch(gen->cg, continue_target, cg_get_size(gen->cg));
            }
            break;
        }
        
        case AST_DEFER_STMT: {
            if (node->child_count > 0 && active_defer_count < 256) {
                active_defers[active_defer_count++] = node->children[0];
            }
            break;
        }
        
        case AST_LABEL_DECL: {
            if (node->token.text) {
                char label_mangled[128];
                snprintf(label_mangled, sizeof(label_mangled), ".user_label_%s_%s", 
                         current_func_name ? current_func_name : "global", node->token.text);
                cg_emit_label(gen->cg, gen->pt, label_mangled);
            }
            break;
        }
        
        case AST_GOTO_STMT: {
            if (node->token.text) {
                char label_mangled[128];
                snprintf(label_mangled, sizeof(label_mangled), ".user_label_%s_%s", 
                         current_func_name ? current_func_name : "global", node->token.text);
                int start_pos = cg_get_size(gen->cg);
                cg_emit_byte(gen->cg, 0xE9);
                cg_emit_byte(gen->cg, 0);
                cg_emit_byte(gen->cg, 0);
                cg_emit_byte(gen->cg, 0);
                cg_emit_byte(gen->cg, 0);
                pt_add_patch(gen->pt, start_pos + 1, label_mangled, false);
            }
            break;
        }
        
        case AST_USE_DECL: {
            /* compile noise silenced */
            break;
        }
        
        case AST_EXPORT_DECL: {
            /* compile noise silenced */;
            if (node->child_count > 0) {
                generate_from_ast(gen, node->children[0]);
            }
            break;
        }
        
        case AST_ASSERT_STMT: {
            if (node->child_count > 0) {
                // Evaluate expression -> RAX
                generate_from_ast(gen, node->children[0]);
                
                // test rax, rax
                cg_emit_test_reg_reg(gen->cg, REG_RAX, REG_RAX);
                
                // jnz over failure
                int jnz_pos = cg_get_size(gen->cg);
                cg_emit_byte(gen->cg, 0x75);
                cg_emit_byte(gen->cg, 0); // placeholder
                
                // Failure block:
                emit_print_string(gen, "Assertion failed!\n", 18);
                // Exit system call: sys_exit (60), code 1
                cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 60);
                cg_emit_mov_reg_imm64(gen->cg, REG_RDI, 1);
                cg_emit_syscall(gen->cg);
                
                // Patch the jnz offset to skip the failure block
                int current_pos = cg_get_size(gen->cg);
                uint8_t* buf = cg_get_buffer(gen->cg);
                buf[jnz_pos + 1] = (uint8_t)(current_pos - (jnz_pos + 2));
            }
            break;
        }
        
        case AST_TRY_STMT: {
            int try_idx = try_counter++;
            char catch_lbl[64];
            char finally_lbl[64];
            char end_lbl[64];
            snprintf(catch_lbl, sizeof(catch_lbl), ".catch_%d", try_idx);
            snprintf(finally_lbl, sizeof(finally_lbl), ".finally_%d", try_idx);
            snprintf(end_lbl, sizeof(end_lbl), ".end_try_%d", try_idx);
            
            // Save previous catch label
            char prev_catch[128];
            strncpy(prev_catch, active_catch_label, sizeof(prev_catch));
            
            // Set new active catch label
            strncpy(active_catch_label, catch_lbl, sizeof(active_catch_label));
            
            // 1. Emit Try Block
            if (node->child_count > 0 && node->children[0]) {
                generate_from_ast(gen, node->children[0]);
            }
            
            // At the end of normal try execution, jump to finally
            int jmp_finally_pos = cg_get_size(gen->cg);
            cg_emit_byte(gen->cg, 0xE9);
            cg_emit_byte(gen->cg, 0); cg_emit_byte(gen->cg, 0);
            cg_emit_byte(gen->cg, 0); cg_emit_byte(gen->cg, 0);
            pt_add_patch(gen->pt, jmp_finally_pos + 1, finally_lbl, false);
            
            // 2. Emit Catch Label & Block
            cg_emit_label(gen->cg, gen->pt, catch_lbl);
            // Restore enclosing catch label during catch block so that throws in catch propagate outwards!
            strncpy(active_catch_label, prev_catch, sizeof(active_catch_label));
            
            if (node->child_count > 1 && node->children[1]) {
                generate_from_ast(gen, node->children[1]);
            }
            
            // At the end of catch block execution, jump to finally
            int jmp_finally_catch_pos = cg_get_size(gen->cg);
            cg_emit_byte(gen->cg, 0xE9);
            cg_emit_byte(gen->cg, 0); cg_emit_byte(gen->cg, 0);
            cg_emit_byte(gen->cg, 0); cg_emit_byte(gen->cg, 0);
            pt_add_patch(gen->pt, jmp_finally_catch_pos + 1, finally_lbl, false);
            
            // 3. Emit Finally Label & Block
            cg_emit_label(gen->cg, gen->pt, finally_lbl);
            if (node->child_count > 2 && node->children[2]) {
                generate_from_ast(gen, node->children[2]);
            }
            
            // Emit End Try Label
            cg_emit_label(gen->cg, gen->pt, end_lbl);
            break;
        }
        
        case AST_THROW_STMT: {
            if (node->child_count > 0 && node->children[0]) {
                // Evaluate throw expression -> RAX
                generate_from_ast(gen, node->children[0]);
            } else {
                cg_emit_xor_reg_reg(gen->cg, REG_RAX, REG_RAX);
            }
            
            if (strlen(active_catch_label) > 0) {
                // Jump to active catch block
                int jmp_catch_pos = cg_get_size(gen->cg);
                cg_emit_byte(gen->cg, 0xE9);
                cg_emit_byte(gen->cg, 0); cg_emit_byte(gen->cg, 0);
                cg_emit_byte(gen->cg, 0); cg_emit_byte(gen->cg, 0);
                pt_add_patch(gen->pt, jmp_catch_pos + 1, active_catch_label, false);
            } else {
                // Unhandled exception: print error and exit!
                emit_print_string(gen, "Unhandled Exception!\n", 21);
                cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 60); // sys_exit
                cg_emit_mov_reg_imm64(gen->cg, REG_RDI, 1);
                cg_emit_syscall(gen->cg);
            }
            break;
        }
        
        case NODE_IMPL: {
            if (node->child_count > 0 && node->children[0]->token.text) {
                /* compile noise silenced */;
            }
            for (int i = 1; i < node->child_count; i++) {
                generate_from_ast(gen, node->children[i]);
            }
            break;
        }
        
        case AST_ASM_STMT: {
            const char* asm_str = NULL;
            char* stripped = NULL;
            if (node->string_value) {
                asm_str = node->string_value;
            } else if (node->child_count > 0 && node->children[0]->token.text) {
                asm_str = node->children[0]->token.text;
            }
            if (asm_str) {
                size_t n = strlen(asm_str);
                if (n >= 2 && asm_str[0] == '"' && asm_str[n - 1] == '"') {
                    stripped = strndup(asm_str + 1, n - 2);
                    asm_str = stripped;
                }
                emit_inline_asm(gen, asm_str);
                free(stripped);
            }
            break;
        }
        
        case AST_ASYNC_STMT: {
            /* `async { ... }` runs the block in a child process while the
               parent keeps going. The pid is not exposed; use `spawn` when it
               is needed. Results still reach `await` through the task pipe. */
            emit_task_fork(gen, node->child_count > 0 ? node->children[0] : NULL,
                           "async");
            break;
        }
        
        case AST_PARALLEL_STMT: {
            /* `parallel { ... }` forks the block with a result pipe and joins
               it before continuing. Used as an expression it evaluates to the
               value the block yielded. */
            emit_task_fork(gen, node->child_count > 0 ? node->children[0] : NULL,
                           "parallel");
            emit_task_join(gen, false);
            break;
        }
        
        case AST_AWAIT_STMT: {
            bool wait_any = node->child_count == 0;
            if (!wait_any)
                generate_from_ast(gen, node->children[0]);
            emit_task_join(gen, wait_any);
            break;
        }
        
        case AST_SPAWN_STMT: {
            /* fork() -> syscall 57. The parent keeps the child pid in RAX;
               the child runs the block/expression and exits. `yield v` sends
               v through the task pipe for a later `await`. */
            emit_task_fork(gen, node->child_count > 0 ? node->children[0] : NULL,
                           "spawn");
            break;
        }
        
        default: {
            for (int i = 0; i < node->child_count; i++) {
                generate_from_ast(gen, node->children[i]);
            }
            break;
        }
    }
}

static void add_reachable(const char* name) {
    if (!name) return;
    for (int i = 0; i < reachable_func_count; i++) {
        if (strcmp(reachable_funcs[i], name) == 0) return;
    }
    if (reachable_func_count < 2048) {
        reachable_funcs[reachable_func_count++] = name;
    }
}

static void scan_calls(ASTNode* node) {
    if (!node) return;
    if (node->type == AST_CALL_EXPR) {
        ASTNode* func_name_node = node->children[0];
        if (func_name_node && func_name_node->type == AST_IDENTIFIER_EXPR) {
            const char* name = func_name_node->token.text;
            add_reachable(name);
        }
    }
    for (int i = 0; i < node->child_count; i++) {
        scan_calls(node->children[i]);
    }
}

static void compute_reachability(IRProgram* ir) {
    reachable_func_count = 0;
    add_reachable(entry_func_name);

    int last_count = 0;
    while (reachable_func_count > last_count) {
        int start_idx = last_count;
        last_count = reachable_func_count;

        for (int f = start_idx; f < last_count; f++) {
            const char* name = reachable_funcs[f];
            for (size_t i = 0; i < ir->count; i++) {
                IRInstruction* inst = &ir->instructions[i];
                if (inst->op == IR_AST_NODE && inst->ast_node) {
                    ASTNode* root = inst->ast_node;
                    if (root->type == AST_PROGRAM) {
                        for (int c = 0; c < root->child_count; c++) {
                            ASTNode* child = root->children[c];
                            if (child->type == AST_FUNC_DECL && child->token.text &&
                                strcmp(child->token.text, name) == 0) {
                                scan_calls(child);
                            }
                        }
                    } else if (root->type == AST_FUNC_DECL && root->token.text &&
                               strcmp(root->token.text, name) == 0) {
                        scan_calls(root);
                    }
                }
            }
        }
    }
}

static bool patch_refers_to(AsmGen* gen, const char* name) {
    if (!name) return false;
    for (size_t i = 0; i < gen->pt->count; i++) {
        PatchPoint* p = &gen->pt->patches[i];
        if (!p->is_label && p->label_name && strcmp(p->label_name, name) == 0)
            return true;
    }
    return false;
}

static bool patch_defines(AsmGen* gen, const char* name) {
    if (!name) return false;
    for (size_t i = 0; i < gen->pt->count; i++) {
        PatchPoint* p = &gen->pt->patches[i];
        if (p->is_label && p->label_name && strcmp(p->label_name, name) == 0)
            return true;
    }
    return false;
}

bool AsmGen_generate(AsmGen* gen) {
    if (!gen->ir) return false;
    entry_func_missing = false;

    // Compute reachability for Dead Function Elimination
    compute_reachability(gen->ir);

    /* Collect parameter types before emitting code so calls can push `any`
       arguments as two words even when the callee is defined later. */
    func_sig_count = 0;
    for (size_t i = 0; i < gen->ir->count; i++) {
        IRInstruction* inst = &gen->ir->instructions[i];
        if (inst->op == IR_AST_NODE && inst->ast_node)
            scan_func_sigs(inst->ast_node);
    }
    
    for (size_t i = 0; i < gen->ir->count; i++) {
        IRInstruction* inst = &gen->ir->instructions[i];
        if (inst->op == IR_AST_NODE && inst->ast_node) {
            generate_from_ast(gen, inst->ast_node);
        }
    }
    

    
    // Dump only extern function stubs that are actually called.
    if (!gen->is_object_mode) {
        for (int i = 0; i < extern_func_count; i++) {
            const char* name = extern_funcs[i].name;
            if (!patch_refers_to(gen, name) || patch_defines(gen, name))
                continue;
            cg_emit_label(gen->cg, gen->pt, name);
        if (strcmp(name, "exit") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16);
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 60);
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "printf") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, 16);
            emit_print_string_var(gen);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "print_str") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, 16);
            emit_print_string_var(gen);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "print_int") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, 16);
            emit_print_int(gen);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "print_float") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_movss_xmm_mem(gen->cg, REG_XMM0, REG_RBP, 16);
            emit_print_float(gen);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "get_timestamp") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_imm64(gen->cg, REG_RDI, 0);
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 201); // sys_time
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sleep_ms") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, 16); // ms
            cg_emit_mov_reg_imm64(gen->cg, REG_RCX, 1000);
            cg_emit_xor_reg_reg(gen->cg, REG_RDX, REG_RDX);
            cg_emit_idiv_reg(gen->cg, REG_RCX); // RAX = sec, RDX = ms % 1000
            cg_emit_mov_reg_reg(gen->cg, REG_R9, REG_RAX);
            cg_emit_mov_reg_reg(gen->cg, REG_RAX, REG_RDX);
            cg_emit_mov_reg_imm64(gen->cg, REG_RCX, 1000000);
            cg_emit_imul_reg_reg(gen->cg, REG_RAX, REG_RCX); // RAX = tv_nsec
            cg_emit_push_reg(gen->cg, REG_RAX); // push tv_nsec
            cg_emit_push_reg(gen->cg, REG_R9);  // push tv_sec
            cg_emit_mov_reg_reg(gen->cg, REG_RDI, REG_RSP);
            cg_emit_mov_reg_imm64(gen->cg, REG_RSI, 0);
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 35); // sys_nanosleep
            cg_emit_syscall(gen->cg);
            cg_emit_add_reg_imm32(gen->cg, REG_RSP, 16);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "rand_int") == 0) {
            // Native rdtsc entropy
            uint8_t* buf = cg_get_buffer(gen->cg);
            int sz = cg_get_size(gen->cg);
            buf[sz++] = 0x0F; buf[sz++] = 0x31; // rdtsc
            buf[sz++] = 0x48; buf[sz++] = 0xC1; buf[sz++] = 0xE2; buf[sz++] = 0x20; // shl rdx, 32
            buf[sz++] = 0x48; buf[sz++] = 0x09; buf[sz++] = 0xD0; // or rax, rdx
            gen->cg->size = sz;
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "rand_float") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 0x3F000000);
            cg_emit_push_reg(gen->cg, REG_RAX);
            cg_emit_movss_xmm_mem(gen->cg, REG_XMM0, REG_RSP, 0);
            cg_emit_add_reg_imm32(gen->cg, REG_RSP, 8);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sqrt") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_movss_xmm_mem(gen->cg, REG_XMM0, REG_RBP, 16);
            uint8_t* buf = cg_get_buffer(gen->cg);
            int sz = cg_get_size(gen->cg);
            buf[sz++] = 0xF3; buf[sz++] = 0x0F; buf[sz++] = 0x51; buf[sz++] = 0xC0; // sqrtss xmm0, xmm0
            gen->cg->size = sz;
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sin") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_movss_xmm_mem(gen->cg, REG_XMM0, REG_RBP, 16);
            cg_emit_sub_reg_imm32(gen->cg, REG_RSP, 8);
            cg_emit_movss_mem_xmm(gen->cg, REG_RSP, 0, REG_XMM0);
            uint8_t* buf = cg_get_buffer(gen->cg);
            int sz = cg_get_size(gen->cg);
            buf[sz++] = 0xD9; buf[sz++] = 0x04; buf[sz++] = 0x24; // fld dword ptr [rsp]
            buf[sz++] = 0xD9; buf[sz++] = 0xFE;                  // fsin
            buf[sz++] = 0xD9; buf[sz++] = 0x1C; buf[sz++] = 0x24; // fstp dword ptr [rsp]
            gen->cg->size = sz;
            cg_emit_movss_xmm_mem(gen->cg, REG_XMM0, REG_RSP, 0);
            cg_emit_add_reg_imm32(gen->cg, REG_RSP, 8);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "cos") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_movss_xmm_mem(gen->cg, REG_XMM0, REG_RBP, 16);
            cg_emit_sub_reg_imm32(gen->cg, REG_RSP, 8);
            cg_emit_movss_mem_xmm(gen->cg, REG_RSP, 0, REG_XMM0);
            uint8_t* buf = cg_get_buffer(gen->cg);
            int sz = cg_get_size(gen->cg);
            buf[sz++] = 0xD9; buf[sz++] = 0x04; buf[sz++] = 0x24; // fld dword ptr [rsp]
            buf[sz++] = 0xD9; buf[sz++] = 0xFF;                  // fcos
            buf[sz++] = 0xD9; buf[sz++] = 0x1C; buf[sz++] = 0x24; // fstp dword ptr [rsp]
            gen->cg->size = sz;
            cg_emit_movss_xmm_mem(gen->cg, REG_XMM0, REG_RSP, 0);
            cg_emit_add_reg_imm32(gen->cg, REG_RSP, 8);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "tan") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_movss_xmm_mem(gen->cg, REG_XMM0, REG_RBP, 16);
            cg_emit_sub_reg_imm32(gen->cg, REG_RSP, 16);
            cg_emit_movss_mem_xmm(gen->cg, REG_RSP, 0, REG_XMM0);
            uint8_t* buf = cg_get_buffer(gen->cg);
            int sz = cg_get_size(gen->cg);
            buf[sz++] = 0xD9; buf[sz++] = 0x04; buf[sz++] = 0x24; // fld dword ptr [rsp]
            buf[sz++] = 0xD9; buf[sz++] = 0xFE;                  // fsin
            buf[sz++] = 0xD9; buf[sz++] = 0x1C; buf[sz++] = 0x24; // fstp dword ptr [rsp]
            buf[sz++] = 0xD9; buf[sz++] = 0x04; buf[sz++] = 0x24; // fld dword ptr [rsp]
            buf[sz++] = 0xD9; buf[sz++] = 0xFF;                  // fcos
            buf[sz++] = 0xD9; buf[sz++] = 0x54; buf[sz++] = 0x24; buf[sz++] = 0x04; // fstp dword ptr [rsp + 4]
            gen->cg->size = sz;
            cg_emit_movss_xmm_mem(gen->cg, REG_XMM0, REG_RSP, 0); // xmm0 = sin
            cg_emit_movss_xmm_mem(gen->cg, REG_XMM1, REG_RSP, 4); // xmm1 = cos
            cg_emit_divss_xmm_xmm(gen->cg, REG_XMM0, REG_XMM1);
            cg_emit_add_reg_imm32(gen->cg, REG_RSP, 16);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "exp") == 0) {
            // exp(x) = e^x = 2^(x * log2(e)). arg at [rbp+16].
            // Uses same z -> 2^z path as pow.
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_sub_reg_imm32(gen->cg, REG_RSP, 16);
            uint8_t* buf = cg_get_buffer(gen->cg);
            int sz = cg_get_size(gen->cg);
            // mov eax, 0x3FB8AA3B (log2e); mov [rbp-16], eax; fld [rbp-16]
            buf[sz++] = 0xB8; buf[sz++] = 0x3B; buf[sz++] = 0xAA; buf[sz++] = 0xB8; buf[sz++] = 0x3F;
            buf[sz++] = 0x89; buf[sz++] = 0x45; buf[sz++] = 0xF0;
            buf[sz++] = 0xD9; buf[sz++] = 0x45; buf[sz++] = 0xF0; // fld dword [rbp-16] -> st0=log2e
            buf[sz++] = 0xD9; buf[sz++] = 0x45; buf[sz++] = 16;  // fld dword [rbp+16] (x) -> st0=x, st1=log2e
            buf[sz++] = 0xDE; buf[sz++] = 0xC9;                 // fmulp st1, st0 -> st0 = log2e*x = z
            buf[sz++] = 0xD9; buf[sz++] = 0xC0;                 // fld st0   -> st0=z, st1=z
            buf[sz++] = 0xD9; buf[sz++] = 0xC0;                 // fld st0   -> st0=z, st1=z, st2=z
            buf[sz++] = 0xD9; buf[sz++] = 0xE8;                 // fld1      -> st0=1, st1=z, st2=z, st3=z
            buf[sz++] = 0xD9; buf[sz++] = 0xC9;                 // fxch st1  -> st0=z, st1=1
            buf[sz++] = 0xD9; buf[sz++] = 0xF8;                 // fprem     -> st0 = frac = z mod 1
            buf[sz++] = 0xD9; buf[sz++] = 0xC0;                 // fld st0   -> st0=frac, st1=frac
            buf[sz++] = 0xD9; buf[sz++] = 0xF0;                 // f2xm1     -> st0 = 2^frac - 1
            buf[sz++] = 0xD9; buf[sz++] = 0xE8;                 // fld1
            buf[sz++] = 0xDE; buf[sz++] = 0xC1;                 // faddp st1,st0 -> st0 = 2^frac
            buf[sz++] = 0xDD; buf[sz++] = 0xD9;                 // fstp st1  -> pop frac, keep st0 = 2^frac, st1=1
            buf[sz++] = 0xDD; buf[sz++] = 0xD9;                 // fstp st1  -> pop 1, st0 = 2^frac, st1=z
            buf[sz++] = 0xD9; buf[sz++] = 0xFD;                 // fscale    -> st0 = 2^frac * 2^trunc(z) = 2^z
            buf[sz++] = 0xDD; buf[sz++] = 0xD9;                 // fstp st1  -> st0 = 2^z, st1=z
            buf[sz++] = 0xDD; buf[sz++] = 0xD9;                 // fstp st1  -> st0 = 2^z
            buf[sz++] = 0xD9; buf[sz++] = 0x5D; buf[sz++] = 0xF8; // fstp dword [rbp-8]
            gen->cg->size = sz;
            cg_emit_movss_xmm_mem(gen->cg, REG_XMM0, REG_RBP, -8);
            cg_emit_add_reg_imm32(gen->cg, REG_RSP, 16);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "log") == 0) {
            // log(x) = ln(x) = log2(x) * ln(2). arg at [rbp+16].
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_sub_reg_imm32(gen->cg, REG_RSP, 16);
            uint8_t* buf = cg_get_buffer(gen->cg);
            int sz = cg_get_size(gen->cg);
            // mov eax, ln(2); mov [rbp-16], eax; fld [rbp-16]
            buf[sz++] = 0xB8; buf[sz++] = 0x18; buf[sz++] = 0x72; buf[sz++] = 0x31; buf[sz++] = 0x3F;
            buf[sz++] = 0x89; buf[sz++] = 0x45; buf[sz++] = 0xF0;
            buf[sz++] = 0xD9; buf[sz++] = 0x45; buf[sz++] = 0xF0; // fld dword [rbp-16] -> st0=ln2
            buf[sz++] = 0xD9; buf[sz++] = 0x45; buf[sz++] = 16;  // fld dword [rbp+16] (x) -> st0=x, st1=ln2
            buf[sz++] = 0xD9; buf[sz++] = 0xF1;                 // fyl2x -> st0 = ln2 * log2(x) = ln(x)
            buf[sz++] = 0xD9; buf[sz++] = 0x5D; buf[sz++] = 0xF8; // fstp dword [rbp-8]
            gen->cg->size = sz;
            cg_emit_movss_xmm_mem(gen->cg, REG_XMM0, REG_RBP, -8);
            cg_emit_add_reg_imm32(gen->cg, REG_RSP, 16);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "pow") == 0) {
            // pow(x, y) = 2^(y * log2(x)) computed with x87 instructions.
            // args: x at [rbp+16], y at [rbp+24]; result returned in XMM0.
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_sub_reg_imm32(gen->cg, REG_RSP, 16);
            uint8_t* buf = cg_get_buffer(gen->cg);
            int sz = cg_get_size(gen->cg);
            buf[sz++] = 0xD9; buf[sz++] = 0x45; buf[sz++] = 24; // fld dword [rbp+24] (y)
            buf[sz++] = 0xD9; buf[sz++] = 0x45; buf[sz++] = 16; // fld dword [rbp+16] (x)
            buf[sz++] = 0xD9; buf[sz++] = 0xF1;                 // fyl2x  -> st0 = z = y*log2(x)
            buf[sz++] = 0xD9; buf[sz++] = 0xC0;                 // fld st0   -> st0=z, st1=z
            buf[sz++] = 0xD9; buf[sz++] = 0xC0;                 // fld st0   -> st0=z, st1=z, st2=z
            buf[sz++] = 0xD9; buf[sz++] = 0xE8;                 // fld1      -> st0=1, st1=z, st2=z, st3=z
            buf[sz++] = 0xD9; buf[sz++] = 0xC9;                 // fxch st1  -> st0=z, st1=1
            buf[sz++] = 0xD9; buf[sz++] = 0xF8;                 // fprem     -> st0 = frac = z mod 1, st1=1
            buf[sz++] = 0xD9; buf[sz++] = 0xC0;                 // fld st0   -> st0=frac, st1=frac
            buf[sz++] = 0xD9; buf[sz++] = 0xF0;                 // f2xm1     -> st0 = 2^frac - 1
            buf[sz++] = 0xD9; buf[sz++] = 0xE8;                 // fld1
            buf[sz++] = 0xDE; buf[sz++] = 0xC1;                 // faddp st1,st0 -> st0 = 2^frac, st1=frac
            buf[sz++] = 0xDD; buf[sz++] = 0xD9;                 // fstp st1  -> pop frac, keep st0 = 2^frac, st1=1
            buf[sz++] = 0xDD; buf[sz++] = 0xD9;                 // fstp st1  -> pop 1, st0 = 2^frac, st1=z
            buf[sz++] = 0xD9; buf[sz++] = 0xFD;                 // fscale    -> st0 = 2^frac * 2^trunc(z) = 2^z
            buf[sz++] = 0xDD; buf[sz++] = 0xD9;                 // fstp st1  -> st0 = 2^z, st1=z
            buf[sz++] = 0xDD; buf[sz++] = 0xD9;                 // fstp st1  -> st0 = 2^z
            buf[sz++] = 0xD9; buf[sz++] = 0x5D; buf[sz++] = 0xF8; // fstp dword [rbp-8]
            gen->cg->size = sz;
            cg_emit_movss_xmm_mem(gen->cg, REG_XMM0, REG_RBP, -8);
            cg_emit_add_reg_imm32(gen->cg, REG_RSP, 16);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "read_line") == 0) {
            // Reads one line from stdin (fd 0) into a 256-byte mmap'd buffer.
            // Loops byte-by-byte until newline, NUL, EOF, or buffer is full.
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_push_reg(gen->cg, REG_RBX);
            cg_emit_push_reg(gen->cg, REG_R12);
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 9);
            cg_emit_xor_reg_reg(gen->cg, REG_RDI, REG_RDI);
            cg_emit_mov_reg_imm64(gen->cg, REG_RSI, 256);
            cg_emit_mov_reg_imm64(gen->cg, REG_RDX, 3);
            cg_emit_mov_reg_imm64(gen->cg, REG_R10, 0x22);
            cg_emit_mov_reg_imm64(gen->cg, REG_R8, (uint64_t)-1);
            cg_emit_xor_reg_reg(gen->cg, REG_R9, REG_R9);
            cg_emit_syscall(gen->cg);
            cg_emit_mov_reg_reg(gen->cg, REG_RBX, REG_RAX);
            cg_emit_xor_reg_reg(gen->cg, REG_R12, REG_R12);
            cg_emit_label(gen->cg, gen->pt, ".rl_loop");
            cg_emit_mov_reg_reg(gen->cg, REG_RSI, REG_RBX);
            cg_emit_add_reg_reg(gen->cg, REG_RSI, REG_R12);
            cg_emit_xor_reg_reg(gen->cg, REG_RDI, REG_RDI);
            cg_emit_mov_reg_imm64(gen->cg, REG_RDX, 1);
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 0);
            cg_emit_syscall(gen->cg);
            cg_emit_test_reg_reg(gen->cg, REG_RAX, REG_RAX);
            cg_emit_jle_label(gen->cg, gen->pt, ".rl_done");
            cg_emit_movzx_byte(gen->cg, REG_RAX, REG_RSI, 0);
            cg_emit_cmp_reg_imm32(gen->cg, REG_RAX, 10);
            cg_emit_je_label(gen->cg, gen->pt, ".rl_done");
            cg_emit_cmp_reg_imm32(gen->cg, REG_RAX, 0);
            cg_emit_je_label(gen->cg, gen->pt, ".rl_done");
            cg_emit_add_reg_imm32(gen->cg, REG_R12, 1);
            cg_emit_cmp_reg_imm32(gen->cg, REG_R12, 255);
            cg_emit_jl_label(gen->cg, gen->pt, ".rl_loop");
            cg_emit_label(gen->cg, gen->pt, ".rl_done");
            cg_emit_mov_reg_reg(gen->cg, REG_RSI, REG_RBX);
            cg_emit_add_reg_reg(gen->cg, REG_RSI, REG_R12);
            cg_emit_xor_reg_reg(gen->cg, REG_RAX, REG_RAX);
            cg_emit_mov_mem_reg8(gen->cg, REG_RSI, 0, REG_RAX);
            cg_emit_mov_reg_reg(gen->cg, REG_RAX, REG_RBX);
            cg_emit_pop_reg(gen->cg, REG_R12);
            cg_emit_pop_reg(gen->cg, REG_RBX);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "audio_play") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            emit_print_string(gen, "[Audio] Playing track: '", 24);
            cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, 16);
            emit_print_string_var(gen);
            emit_print_string(gen, "'\n", 2);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sql_connect") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            emit_print_string(gen, "[SQL] Connecting to database: '", 31);
            cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, 16);
            emit_print_string_var(gen);
            emit_print_string(gen, "'\n", 2);
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 42);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sql_query") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            emit_print_string(gen, "[SQL] Executing query on DB handle: ", 36);
            cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, 16);
            emit_print_int(gen);
            emit_print_string(gen, ", query: '", 10);
            cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, 24);
            emit_print_string_var(gen);
            emit_print_string(gen, "'\n", 2);
            char label[32];
            snprintf(label, sizeof(label), ".str%zu", gen->string_table_size);
            add_string(gen, "SQL Result Set Mock", 19);
            pt_add_patch(gen->pt, cg_get_size(gen->cg) + 3, label, false);
            cg_emit_lea_reg_rip(gen->cg, REG_RAX, 0);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "process_exec") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            emit_print_string(gen, "[Process] Executing system command: '", 37);
            cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, 16);
            emit_print_string_var(gen);
            emit_print_string(gen, "'\n", 2);
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 0);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "os_get_env") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            emit_print_string(gen, "[OS] Reading environment variable: '", 36);
            cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, 16);
            emit_print_string_var(gen);
            emit_print_string(gen, "'\n", 2);
            char label[32];
            snprintf(label, sizeof(label), ".str%zu", gen->string_table_size);
            add_string(gen, "MagnetarEnvValue", 14);
            pt_add_patch(gen->pt, cg_get_size(gen->cg) + 3, label, false);
            cg_emit_lea_reg_rip(gen->cg, REG_RAX, 0);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "os_get_platform") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            char label[32];
            snprintf(label, sizeof(label), ".str%zu", gen->string_table_size);
            add_string(gen, "MagnetarOS-x86_64-Linux", 21);
            pt_add_patch(gen->pt, cg_get_size(gen->cg) + 3, label, false);
            cg_emit_lea_reg_rip(gen->cg, REG_RAX, 0);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "thread_spawn") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            emit_print_string(gen, "[Thread] Spawning new concurrent thread execution block...\n", 59);
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 1001);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "thread_join") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            emit_print_string(gen, "[Thread] Waiting for thread ID: ", 32);
            cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, 16);
            emit_print_int(gen);
            emit_print_string(gen, " to join...\n", 12);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "lock") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            emit_print_string(gen, "[Thread] Mutex locked successfully.\n", 36);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "unlock") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            emit_print_string(gen, "[Thread] Mutex unlocked successfully.\n", 38);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "regex_match") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            emit_print_string(gen, "[Regex] Matching pattern: '", 27);
            cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, 16);
            emit_print_string_var(gen);
            emit_print_string(gen, "' against text: '", 17);
            cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, 24);
            emit_print_string_var(gen);
            emit_print_string(gen, "'\n", 2);
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 1);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "crypto_hash_sha256") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            emit_print_string(gen, "[Crypto] Computing SHA-256 hash for: '", 38);
            cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, 16);
            emit_print_string_var(gen);
            emit_print_string(gen, "'\n", 2);
            char label[32];
            snprintf(label, sizeof(label), ".str%zu", gen->string_table_size);
            add_string(gen, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", 64);
            pt_add_patch(gen->pt, cg_get_size(gen->cg) + 3, label, false);
            cg_emit_lea_reg_rip(gen->cg, REG_RAX, 0);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "crypto_aes_encrypt") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            emit_print_string(gen, "[Crypto] Encrypting data: '", 27);
            cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, 16);
            emit_print_string_var(gen);
            emit_print_string(gen, "' using key: '", 14);
            cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, 24);
            emit_print_string_var(gen);
            emit_print_string(gen, "'\n", 2);
            char label[32];
            snprintf(label, sizeof(label), ".str%zu", gen->string_table_size);
            add_string(gen, "EncryptedMockDataBlob", 21);
            pt_add_patch(gen->pt, cg_get_size(gen->cg) + 3, label, false);
            cg_emit_lea_reg_rip(gen->cg, REG_RAX, 0);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "net_listen") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            emit_print_string(gen, "[Net] Listening on port: ", 25);
            cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, 16);
            emit_print_int(gen);
            emit_print_string(gen, "\n", 1);
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 12);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "net_accept") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            emit_print_string(gen, "[Net] Connection accepted on server socket FD: ", 47);
            cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, 16);
            emit_print_int(gen);
            emit_print_string(gen, "\n", 1);
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 13);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "net_send") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            emit_print_string(gen, "[Net] Sending data through socket FD: ", 38);
            cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, 16);
            emit_print_int(gen);
            emit_print_string(gen, ", data: '", 9);
            cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, 24);
            emit_print_string_var(gen);
            emit_print_string(gen, "'\n", 2);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "net_close") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            emit_print_string(gen, "[Net] Closed socket connection FD: ", 35);
            cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, 16);
            emit_print_int(gen);
            emit_print_string(gen, "\n", 1);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_open") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // path
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // flags
            cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // mode
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 2); // sys_open
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_close") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // fd
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 3); // sys_close
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_read") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // fd
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // buf
            cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // count
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 0); // sys_read
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_write") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // fd
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // buf
            cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // count
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 1); // sys_write
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_lseek") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // fd
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // offset
            cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // whence
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 8); // sys_lseek
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_unlink") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // path
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 87); // sys_unlink
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_rename") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // oldpath
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // newpath
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 82); // sys_rename
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_mkdir") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // path
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // mode
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 83); // sys_mkdir
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_rmdir") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // path
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 84); // sys_rmdir
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_chdir") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // path
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 80); // sys_chdir
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_getcwd") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // buf
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // size
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 79); // sys_getcwd
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_fork") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 57); // sys_fork
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_getpid") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 39); // sys_getpid
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_getuid") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 102); // sys_getuid
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_stat") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 4); // int stat(const char*, struct stat*)
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_lstat") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 6); // int lstat(const char*, struct stat*)
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_fstat") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 5); // int fstat(int, struct stat*)
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_statx") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
            cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3
            cg_emit_mov_reg_mem(gen->cg, REG_R10, REG_RBP, 40); // arg4
            cg_emit_mov_reg_mem(gen->cg, REG_R8, REG_RBP, 48); // arg5
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 332); // int statx(int, const char*, int, unsigned, void*)
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_newstat") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // path
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // statbuf
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 4); // sys_newstat
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_getdents64") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // fd
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // dirp
            cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // count
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 217); // sys_getdents64
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_wait4") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // pid
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // wstatus
            cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // options
            cg_emit_mov_reg_mem(gen->cg, REG_R10, REG_RBP, 40); // rusage
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 61); // sys_wait4
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_mmap") == 0) {
            // sys_mmap: x86-64 syscall 9 —
            //   void* mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset);
            // Register mapping: addr->RDI, length->RSI, prot->RDX, flags->R10, fd->R8, offset->R9.
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // addr
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // length
            cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // prot
            cg_emit_mov_reg_mem(gen->cg, REG_R10, REG_RBP, 40); // flags
            cg_emit_mov_reg_mem(gen->cg, REG_R8, REG_RBP, 48);  // fd
            cg_emit_mov_reg_mem(gen->cg, REG_R9, REG_RBP, 56);  // offset
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 9); // sys_mmap
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_munmap") == 0) {
            // sys_munmap: x86-64 syscall 11 —
            //   int munmap(void *addr, size_t length);
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // addr
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // length
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 11); // sys_munmap
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_ioctl") == 0) {
            // sys_ioctl: x86-64 syscall 16 —
            //   int ioctl(int fd, unsigned long request, ...);
            // Third pointer/vararg argument lands in RDX.
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // fd
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // request
            cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 16); // sys_ioctl
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_mount") == 0) {
            // sys_mount: x86-64 syscall 165 —
            //   int mount(const char *source, const char *target, const char *fstype,
            //             unsigned long flags, const void *data);
            // Register mapping: source->RDI, target->RSI, fstype->RDX, flags->R10, data->R8.
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16);
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24);
            cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32);
            cg_emit_mov_reg_mem(gen->cg, REG_R10, REG_RBP, 40);
            cg_emit_mov_reg_mem(gen->cg, REG_R8, REG_RBP, 48);
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 165);
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_umount2") == 0) {
            // sys_umount2: x86-64 syscall 166 —
            //   int umount2(const char *target, int flags);
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16);
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24);
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 166);
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_dup2") == 0) {
            // sys_dup2: x86-64 syscall 33 — int dup2(int oldfd, int newfd);
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16);
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24);
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 33);
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_execve") == 0) {
            // sys_execve: x86-64 syscall 59 —
            //   int execve(const char *filename, char *const argv[], char *const envp[]);
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16);
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24);
            cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32);
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 59);
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_setsid") == 0) {
            // sys_setsid: x86-64 syscall 112 — pid_t setsid(void);
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 112);
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_sethostname") == 0) {
            // sys_sethostname: x86-64 syscall 170 —
            //   int sethostname(const char *name, size_t len);
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16);
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24);
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 170);
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_sync") == 0) {
            // sys_sync: x86-64 syscall 162 — void sync(void);
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 162);
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_reboot") == 0) {
            // sys_reboot: x86-64 syscall 169 —
            //   int reboot(int magic1, int magic2, unsigned int cmd, void *arg);
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16);
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24);
            cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32);
            cg_emit_mov_reg_mem(gen->cg, REG_R10, REG_RBP, 40);
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 169);
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_kill") == 0) {
            // sys_kill: x86-64 syscall 62 — int kill(pid_t pid, int sig);
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16);
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24);
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 62);
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_getppid") == 0) {
            // sys_getppid: x86-64 syscall 110 — pid_t getppid(void);
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 110);
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_readlink") == 0) {
            // sys_readlink: x86-64 syscall 89 —
            //   ssize_t readlink(const char *path, char *buf, size_t bufsiz);
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16);
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24);
            cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32);
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 89);
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_exit_group") == 0) {
            // sys_exit_group: x86-64 syscall 231 — void exit_group(int status);
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16);
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 231);
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "sys_rt_sigaction") == 0) {
            // sys_rt_sigaction: x86-64 syscall 13 —
            //   int rt_sigaction(int sig, const struct sigaction *act,
            //                    struct sigaction *oldact, size_t sigsetsize);
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16);
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24);
            cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32);
            cg_emit_mov_reg_mem(gen->cg, REG_R10, REG_RBP, 40);
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 13);
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_pipe") == 0) {
        // int pipe(int fds[2])
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 22); // sys_pipe
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_dup") == 0) {
        // int dup(int oldfd)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 32); // sys_dup
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_dup3") == 0) {
        // int dup3(int old, int new, int flags)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 292); // sys_dup3
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_fcntl") == 0) {
        // int fcntl(int fd, int cmd, int arg)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 72); // sys_fcntl
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_fsync") == 0) {
        // int fsync(int fd)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 74); // sys_fsync
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_fdatasync") == 0) {
        // int fdatasync(int fd)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 75); // sys_fdatasync
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_ftruncate") == 0) {
        // int ftruncate(int fd, int len)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 77); // sys_ftruncate
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_truncate") == 0) {
        // int truncate(char* path, int len)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 76); // sys_truncate
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_flock") == 0) {
        // int flock(int fd, int op)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 73); // sys_flock
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_access") == 0) {
        // int access(char* path, int mode)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 21); // sys_access
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_writev") == 0) {
        // ssize_t writev(int fd, void* iov, int cnt)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 20); // sys_writev
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_readv") == 0) {
        // ssize_t readv(int fd, void* iov, int cnt)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 19); // sys_readv
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_setuid") == 0) {
        // int setuid(int uid)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 105); // sys_setuid
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_setgid") == 0) {
        // int setgid(int gid)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 106); // sys_setgid
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_setgroups") == 0) {
        // int setgroups(int n, int* list)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 116); // sys_setgroups
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_setresuid") == 0) {
        // int setresuid(int r, int e, int s)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 117); // sys_setresuid
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_setresgid") == 0) {
        // int setresgid(int r, int e, int s)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 119); // sys_setresgid
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_capset") == 0) {
        // int capset(int hdr, int data)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 126); // sys_capset
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_setpriority") == 0) {
        // int setpriority(int which, int who, int prio)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 141); // sys_setpriority
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_sched_setscheduler") == 0) {
        // int sched_setscheduler(int pid, int pol, int par)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 156); // sys_sched_setscheduler
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_sched_yield") == 0) {
        // int sched_yield(void)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 24); // sys_sched_yield
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_prctl") == 0) {
        // int prctl(int opt, int a2..a5)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3
        cg_emit_mov_reg_mem(gen->cg, REG_R10, REG_RBP, 40); // arg4
        cg_emit_mov_reg_mem(gen->cg, REG_R8, REG_RBP, 48); // arg5
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 157); // sys_prctl
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_chroot") == 0) {
        // int chroot(char* path)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 161); // sys_chroot
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_pivot_root") == 0) {
        // int pivot_root(char* nr, char* po)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 155); // sys_pivot_root
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_uname") == 0) {
        // int uname(void* buf)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 63); // sys_uname
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_sysinfo") == 0) {
        // int sysinfo(void* info)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 99); // sys_sysinfo
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_gettid") == 0) {
        // int gettid(void)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 186); // sys_gettid
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_tgkill") == 0) {
        // int tgkill(int tgid, int tid, int sig)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 234); // sys_tgkill
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_getrandom") == 0) {
        // long getrandom(void* buf, int len, int flags)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 318); // sys_getrandom
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_setrlimit") == 0) {
        // int setrlimit(int res, void* lim)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 160); // sys_setrlimit
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_getrlimit") == 0) {
        // int getrlimit(int res, void* lim)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 97); // sys_getrlimit
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_nanosleep") == 0) {
        // int nanosleep(void* req, void* rem)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 35); // sys_nanosleep
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_clock_gettime") == 0) {
        // int clock_gettime(int clk, void* tp)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 228); // sys_clock_gettime
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_sigprocmask") == 0) {
        // int sigprocmask(int how, void* s, void* o, int sz)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3
        cg_emit_mov_reg_mem(gen->cg, REG_R10, REG_RBP, 40); // arg4
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 14); // sys_sigprocmask
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_symlink") == 0) {
        // int symlink(char* t, char* l)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 88); // sys_symlink
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_chmod") == 0) {
        // int chmod(char* p, int mode)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 90); // sys_chmod
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_fchmod") == 0) {
        // int fchmod(int fd, int mode)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 91); // sys_fchmod
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_chown") == 0) {
        // int chown(char* p, int o, int g)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 92); // sys_chown
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_fchown") == 0) {
        // int fchown(int fd, int o, int g)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 93); // sys_fchown
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_lchown") == 0) {
        // int lchown(char* p, int o, int g)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 94); // sys_lchown
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_mknod") == 0) {
        // int mknod(char* p, int mode, int dev)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 133); // sys_mknod
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_statvfs") == 0) {
        // int statvfs(char* p, void* buf)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 137); // sys_statvfs
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_swapon") == 0) {
        // int swapon(char* p, int flags)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 107); // sys_swapon
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_swapoff") == 0) {
        // int swapoff(char* p)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 166); // sys_swapoff
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_socket") == 0) {
        // int socket(int dom, int type, int proto)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 41); // sys_socket
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_connect") == 0) {
        // int connect(int fd, void* a, int len)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 42); // sys_connect
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_bind") == 0) {
        // int bind(int fd, void* a, int len)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 49); // sys_bind
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_listen") == 0) {
        // int listen(int fd, int backlog)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 50); // sys_listen
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_accept") == 0) {
        // int accept(int fd, void* a, int len)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 43); // sys_accept
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_shutdown") == 0) {
        // int shutdown(int fd, int how)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 48); // sys_shutdown
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_send") == 0) {
        // ssize_t send(int fd, void* b, int l, int f)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3
        cg_emit_mov_reg_imm64(gen->cg, REG_R10, 0); // flags = 0
        cg_emit_mov_reg_imm64(gen->cg, REG_RCX, 0); // dest_addr = NULL
        cg_emit_mov_reg_imm64(gen->cg, REG_R8, 0); // addrlen = NULL
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 44); // sys_send
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_recv") == 0) {
        // ssize_t recv(int fd, void* b, int l, int f)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3
        cg_emit_mov_reg_imm64(gen->cg, REG_R10, 0); // flags = 0
        cg_emit_mov_reg_imm64(gen->cg, REG_RCX, 0); // src_addr = NULL
        cg_emit_mov_reg_imm64(gen->cg, REG_R8, 0); // addrlen = NULL
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 45); // sys_recv
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_setsockopt") == 0) {
        // int setsockopt(int fd,int lv,int n,void* v,int l)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3
        cg_emit_mov_reg_mem(gen->cg, REG_R10, REG_RBP, 40); // arg4
        cg_emit_mov_reg_mem(gen->cg, REG_R8, REG_RBP, 48); // arg5
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 54); // sys_setsockopt
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_poll") == 0) {
            // int poll(void* fds, int nfds, int timeout)
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
            cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 7); // sys_poll
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_sendto") == 0) {
            // int sendto(int fd, char* buf, int len, int flags, void* dst, int dlen)
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
            cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3
            cg_emit_mov_reg_mem(gen->cg, REG_R10, REG_RBP, 40); // arg4
            cg_emit_mov_reg_mem(gen->cg, REG_R8, REG_RBP, 48); // arg5
            cg_emit_mov_reg_mem(gen->cg, REG_R9, REG_RBP, 56); // arg6
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 44); // sys_sendto
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_recvfrom") == 0) {
            // int recvfrom(int fd, char* buf, int len, int flags, void* src, int slen)
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
            cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3
            cg_emit_mov_reg_mem(gen->cg, REG_R10, REG_RBP, 40); // arg4
            cg_emit_mov_reg_mem(gen->cg, REG_R8, REG_RBP, 48); // arg5
            cg_emit_mov_reg_mem(gen->cg, REG_R9, REG_RBP, 56); // arg6
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 45); // sys_recvfrom
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_sendmsg") == 0) {
            // int sendmsg(int fd, void* msg, int flags)
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
            cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 46); // sys_sendmsg
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_recvmsg") == 0) {
            // int recvmsg(int fd, void* msg, int flags)
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
            cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 47); // sys_recvmsg
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_getsockname") == 0) {
            // int getsockname(int fd, void* addr, int len)
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
            cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 51); // sys_getsockname
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_getpeername") == 0) {
            // int getpeername(int fd, void* addr, int len)
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
            cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 52); // sys_getpeername
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_getsockopt") == 0) {
            // int getsockopt(int fd, int lvl, int name, void* val, int len)
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
            cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3
            cg_emit_mov_reg_mem(gen->cg, REG_R10, REG_RBP, 40); // arg4
            cg_emit_mov_reg_mem(gen->cg, REG_R8, REG_RBP, 48); // arg5
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 55); // sys_getsockopt
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_epoll_wait") == 0) {
            // int epoll_wait(int epfd, void* evs, int maxev, int timeout)
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
            cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3
            cg_emit_mov_reg_mem(gen->cg, REG_R10, REG_RBP, 40); // arg4
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 232); // sys_epoll_wait
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_epoll_ctl") == 0) {
            // int epoll_ctl(int epfd, int op, int fd, void* ev)
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
            cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3
            cg_emit_mov_reg_mem(gen->cg, REG_R10, REG_RBP, 40); // arg4
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 233); // sys_epoll_ctl
            cg_emit_syscall(gen->cg);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_socketpair") == 0) {
        // int socketpair(int d,int t,int p,int* sv)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3
        cg_emit_mov_reg_mem(gen->cg, REG_R10, REG_RBP, 40); // arg4
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 53); // sys_socketpair
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_epoll_create1") == 0) {
        // int epoll_create1(int flags)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 291); // sys_epoll_create1
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_eventfd") == 0) {
        // int eventfd(int val, int flags)
        // NOTE: x86_64 eventfd is 284 (eventfd2 is 290). The kernel's
        // sys_eventfd reads only arg1, so flags is loaded but ignored; kept
        // for source compatibility with callers passing two arguments.
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2 (ignored)
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 284); // sys_eventfd
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_eventfd2") == 0) {
        // int eventfd2(int val, int flags)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1 = count
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2 = flags
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 290); // sys_eventfd2
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_timerfd_settime") == 0) {
        // int timerfd_settime(int fd, int flags, void* new, void* old)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16);  // arg1 = fd
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24);  // arg2 = flags
        cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32);  // arg3 = new
        cg_emit_mov_reg_mem(gen->cg, REG_R10, REG_RBP, 40);  // arg4 = old
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 286); // sys_timerfd_settime
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_accept4") == 0) {
        // int accept4(int fd, void* addr, int* addrlen, int flags)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3
        cg_emit_mov_reg_mem(gen->cg, REG_R10, REG_RBP, 40); // arg4
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 288); // sys_accept4
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_select") == 0) {
        // int select(int nfds, void* r, void* w, void* e, void* timeout)
        // x86_64 selects in place and returns byte counts over FD_SETSIZE
        // 1024 bitmaps; prefer sys_ppoll / sys_pselect6 where possible.
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16);  // arg1 = nfds
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24);  // arg2 = readfds
        cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32);  // arg3 = writefds
        cg_emit_mov_reg_mem(gen->cg, REG_R10, REG_RBP, 40);  // arg4 = exceptfds
        cg_emit_mov_reg_mem(gen->cg, REG_R8,  REG_RBP, 48);  // arg5 = timeout
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 23); // sys_select
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_pselect6") == 0) {
        // int pselect6(int nfds, void* r, void* w, void* e, void* ts, void* sm)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1 = nfds
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2 = readfds
        cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3 = writefds
        cg_emit_mov_reg_mem(gen->cg, REG_R10, REG_RBP, 40); // arg4 = exceptfds
        cg_emit_mov_reg_mem(gen->cg, REG_R8,  REG_RBP, 48); // arg5 = timespec
        cg_emit_mov_reg_mem(gen->cg, REG_R9,  REG_RBP, 56); // arg6 = sigmask
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 270); // sys_pselect6
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_ppoll") == 0) {
        // int ppoll(void* fds, int nfds, void* tmo, void* sigmask, int sigsz)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1 = fds
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2 = nfds
        cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32); // arg3 = timeout
        cg_emit_mov_reg_mem(gen->cg, REG_R10, REG_RBP, 40); // arg4 = sigmask
        cg_emit_mov_reg_mem(gen->cg, REG_R8,  REG_RBP, 48); // arg5 = sigsetsize
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 271); // sys_ppoll
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_timerfd_create") == 0) {
        // int timerfd_create(int clk, int flags)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // arg2
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 283); // sys_timerfd_create
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "sys_inotify_init1") == 0) {
        // int inotify_init1(int flags)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // arg1
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 294); // sys_inotify_init1
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }

        else if (strcmp(name, "sys_fs_exists") == 0) {
        // raw stat(2): int sys_fs_exists(char* path, void* statbuf)
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // path
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // statbuf
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 4); // sys_newstat
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "fs_exists") == 0) {
        // debug helper: prints the path, runs stat(2), prints the result
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        emit_print_string(gen, "[FS] Checking if path exists: '", 31);
        cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, 16);
        emit_print_string_var(gen);
        emit_print_string(gen, "' -> ", 5);
        cg_emit_push_reg(gen->cg, REG_RAX);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // path
        cg_emit_xor_reg_reg(gen->cg, REG_RSI, REG_RSI);     // statbuf = NULL
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 4);          // stat
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RAX);
        emit_print_int(gen);
        emit_print_string(gen, "\n", 1);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "fs_mkdir") == 0) {
        // debug helper: mkdir(2) with a log line
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        emit_print_string(gen, "[FS] Creating directory: '", 26);
        cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, 16);
        emit_print_string_var(gen);
        emit_print_string(gen, "' -> ", 5);
        cg_emit_push_reg(gen->cg, REG_RAX);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // path
        cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // mode
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 83);         // mkdir
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RAX);
        emit_print_int(gen);
        emit_print_string(gen, "\n", 1);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
        else if (strcmp(name, "fs_rm") == 0) {
        // debug helper: unlink(2) with a log line
        cg_emit_push_reg(gen->cg, REG_RBP);
        cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
        emit_print_string(gen, "[FS] Deleting file/directory: '", 33);
        cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, 16);
        emit_print_string_var(gen);
        emit_print_string(gen, "' -> ", 5);
        cg_emit_push_reg(gen->cg, REG_RAX);
        cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // path
        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 87);         // unlink
        cg_emit_syscall(gen->cg);
        cg_emit_pop_reg(gen->cg, REG_RAX);
        emit_print_int(gen);
        emit_print_string(gen, "\n", 1);
        cg_emit_pop_reg(gen->cg, REG_RBP);
        cg_emit_ret(gen->cg);
        }
    }

    if (patch_refers_to(gen, "__dyn_push")) {
    // __dyn_push
    pt_add_patch(gen->pt, cg_get_size(gen->cg), "__dyn_push", true);
    cg_emit_push_reg(gen->cg, REG_RBP);
    cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
    
    cg_emit_mov_reg_mem(gen->cg, REG_RCX, REG_RBP, 16); // RCX = &dyn
    cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RCX, 0); // old_ptr
    cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RCX, 8); // len
    cg_emit_mov_reg_mem(gen->cg, REG_R8, REG_RCX, 16); // cap
    
    cg_emit_cmp_reg_reg(gen->cg, REG_RDX, REG_R8);
    cg_emit_byte(gen->cg, 0x75); cg_emit_byte(gen->cg, 0); // jne skip_alloc
    int jne_skip_alloc = cg_get_size(gen->cg) - 1;
    
    cg_emit_push_reg(gen->cg, REG_RCX); // Save &dyn
    cg_emit_push_reg(gen->cg, REG_RDX); // Save len
    
    cg_emit_test_reg_reg(gen->cg, REG_R8, REG_R8);
    cg_emit_byte(gen->cg, 0x75); cg_emit_byte(gen->cg, 0); // jnz do_mremap
    int jnz_do_mremap = cg_get_size(gen->cg) - 1;
    
    // do_mmap
    cg_emit_mov_reg_imm32(gen->cg, REG_RAX, 9); // sys_mmap
    cg_emit_mov_reg_imm32(gen->cg, REG_RDI, 0);
    cg_emit_mov_reg_imm32(gen->cg, REG_RSI, 32); // 4 * 8
    cg_emit_mov_reg_imm32(gen->cg, REG_RDX, 3); // RW
    cg_emit_mov_reg_imm32(gen->cg, REG_R10, 0x22); // PRIV|ANON
    cg_emit_mov_reg_imm32(gen->cg, REG_R8, -1);
    cg_emit_mov_reg_imm32(gen->cg, REG_R9, 0);
    cg_emit_byte(gen->cg, 0x0F); cg_emit_byte(gen->cg, 0x05); // syscall
    cg_emit_mov_reg_imm32(gen->cg, REG_R8, 4); // new cap
    cg_emit_byte(gen->cg, 0xEB); cg_emit_byte(gen->cg, 0); // jmp alloc_done
    int jmp_alloc_done = cg_get_size(gen->cg) - 1;
    
    // do_mremap
    gen->cg->buffer[jnz_do_mremap] = cg_get_size(gen->cg) - jnz_do_mremap - 1;
    cg_emit_mov_reg_reg(gen->cg, REG_RDI, REG_RAX); // old_ptr
    cg_emit_mov_reg_reg(gen->cg, REG_RSI, REG_R8);
    cg_emit_shl_reg_imm8(gen->cg, REG_RSI, 3); // old_size
    cg_emit_mov_reg_reg(gen->cg, REG_RDX, REG_RSI);
    cg_emit_shl_reg_imm8(gen->cg, REG_RDX, 1); // new_size
    cg_emit_mov_reg_imm32(gen->cg, REG_R10, 1); // MREMAP_MAYMOVE
    cg_emit_mov_reg_imm32(gen->cg, REG_RAX, 25); // sys_mremap
    cg_emit_byte(gen->cg, 0x0F); cg_emit_byte(gen->cg, 0x05); // syscall
    cg_emit_shl_reg_imm8(gen->cg, REG_R8, 1); // cap *= 2
    
    // alloc_done
    gen->cg->buffer[jmp_alloc_done] = cg_get_size(gen->cg) - jmp_alloc_done - 1;
    cg_emit_pop_reg(gen->cg, REG_RDX); // Restore len
    cg_emit_pop_reg(gen->cg, REG_RCX); // Restore &dyn
    
    cg_emit_mov_mem_reg(gen->cg, REG_RCX, 0, REG_RAX); // dyn.ptr = rax
    cg_emit_mov_mem_reg(gen->cg, REG_RCX, 16, REG_R8); // dyn.cap = new_cap
    
    // skip_alloc
    gen->cg->buffer[jne_skip_alloc] = cg_get_size(gen->cg) - jne_skip_alloc - 1;
    cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RCX, 0); // Reload ptr
    cg_emit_mov_reg_mem(gen->cg, REG_R9, REG_RBP, 24); // Value
    
    cg_emit_mov_reg_reg(gen->cg, REG_R8, REG_RDX);
    cg_emit_shl_reg_imm8(gen->cg, REG_R8, 3); // len * 8
    cg_emit_add_reg_reg(gen->cg, REG_RAX, REG_R8); // ptr + len * 8
    cg_emit_mov_mem_reg(gen->cg, REG_RAX, 0, REG_R9); // [ptr+len*8] = val
    
    cg_emit_add_reg_imm32(gen->cg, REG_RDX, 1); // len++
    cg_emit_mov_mem_reg(gen->cg, REG_RCX, 8, REG_RDX); // dyn.len = len
    
    cg_emit_pop_reg(gen->cg, REG_RBP);
    cg_emit_ret(gen->cg);
    }
    }

    if (patch_refers_to(gen, "__str_concat")) {
    // __str_concat(str1, str2) -> RAX = newly allocated concatenated string
    // Calling convention: args pushed on stack, read at [rbp+16], [rbp+24].
    pt_add_patch(gen->pt, cg_get_size(gen->cg), "__str_concat", true);
    cg_emit_push_reg(gen->cg, REG_RBP);
    cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
    cg_emit_push_reg(gen->cg, REG_RBX);          // callee-saved: buffer ptr
    cg_emit_push_reg(gen->cg, REG_R12);          // callee-saved: len1
    cg_emit_push_reg(gen->cg, REG_R13);          // callee-saved: len2

    // strlen(str1) -> r12
    cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16);
    cg_emit_xor_reg_reg(gen->cg, REG_RCX, REG_RCX);
    {
        int loop1 = cg_get_size(gen->cg);
        // cmp byte [rdi+rcx], 0
        cg_emit_byte(gen->cg, 0x80); cg_emit_byte(gen->cg, 0x3C);
        cg_emit_byte(gen->cg, 0x0F); cg_emit_byte(gen->cg, 0x00);
        // je done1 (skip inc rcx [3 bytes] + jmp loop1 [2 bytes] = 5)
        cg_emit_byte(gen->cg, 0x74); cg_emit_byte(gen->cg, 0x05);
        // inc rcx
        cg_emit_byte(gen->cg, 0x48); cg_emit_byte(gen->cg, 0xFF); cg_emit_byte(gen->cg, 0xC1);
        // jmp loop1
        int jmp_back = loop1 - (cg_get_size(gen->cg) + 2);
        cg_emit_byte(gen->cg, 0xEB); cg_emit_byte(gen->cg, (uint8_t)jmp_back);
    }
    cg_emit_mov_reg_reg(gen->cg, REG_R12, REG_RCX);

    // strlen(str2) -> r13
    cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 24);
    cg_emit_xor_reg_reg(gen->cg, REG_RCX, REG_RCX);
    {
        int loop2 = cg_get_size(gen->cg);
        cg_emit_byte(gen->cg, 0x80); cg_emit_byte(gen->cg, 0x3C);
        cg_emit_byte(gen->cg, 0x0F); cg_emit_byte(gen->cg, 0x00);
        cg_emit_byte(gen->cg, 0x74); cg_emit_byte(gen->cg, 0x05);
        cg_emit_byte(gen->cg, 0x48); cg_emit_byte(gen->cg, 0xFF); cg_emit_byte(gen->cg, 0xC1);
        int jmp_back = loop2 - (cg_get_size(gen->cg) + 2);
        cg_emit_byte(gen->cg, 0xEB); cg_emit_byte(gen->cg, (uint8_t)jmp_back);
    }
    cg_emit_mov_reg_reg(gen->cg, REG_R13, REG_RCX);

    // mmap(0, len1+len2+1, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0)
    cg_emit_mov_reg_reg(gen->cg, REG_RSI, REG_R12);
    cg_emit_add_reg_reg(gen->cg, REG_RSI, REG_R13);
    cg_emit_add_reg_imm32(gen->cg, REG_RSI, 1);
    cg_emit_mov_reg_imm32(gen->cg, REG_RAX, 9);    // sys_mmap
    cg_emit_xor_reg_reg(gen->cg, REG_RDI, REG_RDI);
    cg_emit_mov_reg_imm32(gen->cg, REG_RDX, 3);    // PROT_READ|PROT_WRITE
    cg_emit_mov_reg_imm32(gen->cg, REG_R10, 0x22); // MAP_PRIVATE|MAP_ANONYMOUS
    cg_emit_mov_reg_imm32(gen->cg, REG_R8, -1);
    cg_emit_xor_reg_reg(gen->cg, REG_R9, REG_R9);
    cg_emit_byte(gen->cg, 0x0F); cg_emit_byte(gen->cg, 0x05); // syscall
    cg_emit_mov_reg_reg(gen->cg, REG_RBX, REG_RAX); // RBX = buffer

    // memcpy str1: rep movsb (rdi=dest, rsi=src, rcx=count)
    cg_emit_mov_reg_reg(gen->cg, REG_RDI, REG_RBX);
    cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 16);
    cg_emit_mov_reg_reg(gen->cg, REG_RCX, REG_R12);
    cg_emit_byte(gen->cg, 0xF3); cg_emit_byte(gen->cg, 0xA4); // rep movsb

    // memcpy str2 (rdi already advanced past str1)
    cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24);
    cg_emit_mov_reg_reg(gen->cg, REG_RCX, REG_R13);
    cg_emit_byte(gen->cg, 0xF3); cg_emit_byte(gen->cg, 0xA4); // rep movsb

    // null-terminate: mov byte [rdi], 0
    cg_emit_byte(gen->cg, 0xC6); cg_emit_byte(gen->cg, 0x07); cg_emit_byte(gen->cg, 0x00);

    // return buffer in RAX
    cg_emit_mov_reg_reg(gen->cg, REG_RAX, REG_RBX);
    cg_emit_pop_reg(gen->cg, REG_R13);
    cg_emit_pop_reg(gen->cg, REG_R12);
    cg_emit_pop_reg(gen->cg, REG_RBX);
    cg_emit_pop_reg(gen->cg, REG_RBP);
    cg_emit_ret(gen->cg);
    }

    if (patch_refers_to(gen, "__str_cmp")) {
    // __str_cmp(str1, str2) -> RAX = strcmp-like (<0, 0, >0)
    pt_add_patch(gen->pt, cg_get_size(gen->cg), "__str_cmp", true);
    cg_emit_push_reg(gen->cg, REG_RBP);
    cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
    cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16); // str1
    cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24); // str2
    {
        int loop = cg_get_size(gen->cg);
        // mov al, [rdi]
        cg_emit_byte(gen->cg, 0x8A); cg_emit_byte(gen->cg, 0x07);
        // mov bl, [rsi]
        cg_emit_byte(gen->cg, 0x8A); cg_emit_byte(gen->cg, 0x1E);
        // cmp al, bl
        cg_emit_byte(gen->cg, 0x38); cg_emit_byte(gen->cg, 0xD8);
        // jne diff (offset patched below)
        cg_emit_byte(gen->cg, 0x75); cg_emit_byte(gen->cg, 0);
        int jne_diff = cg_get_size(gen->cg) - 1;
        // test al, al
        cg_emit_byte(gen->cg, 0x84); cg_emit_byte(gen->cg, 0xC0);
        // je equal (offset patched below)
        cg_emit_byte(gen->cg, 0x74); cg_emit_byte(gen->cg, 0);
        int je_equal = cg_get_size(gen->cg) - 1;
        // inc rdi
        cg_emit_byte(gen->cg, 0x48); cg_emit_byte(gen->cg, 0xFF); cg_emit_byte(gen->cg, 0xC7);
        // inc rsi
        cg_emit_byte(gen->cg, 0x48); cg_emit_byte(gen->cg, 0xFF); cg_emit_byte(gen->cg, 0xC6);
        // jmp loop
        int jmp_back = loop - (cg_get_size(gen->cg) + 2);
        cg_emit_byte(gen->cg, 0xEB); cg_emit_byte(gen->cg, (uint8_t)jmp_back);

        // diff: movzx eax, al; movzx ebx, bl; sub eax, ebx; jmp done
        gen->cg->buffer[jne_diff] = cg_get_size(gen->cg) - jne_diff - 1;
        cg_emit_byte(gen->cg, 0x0F); cg_emit_byte(gen->cg, 0xB6); cg_emit_byte(gen->cg, 0xC0); // movzx eax, al
        cg_emit_byte(gen->cg, 0x0F); cg_emit_byte(gen->cg, 0xB6); cg_emit_byte(gen->cg, 0xDB); // movzx ebx, bl
        cg_emit_byte(gen->cg, 0x29); cg_emit_byte(gen->cg, 0xD8); // sub eax, ebx
        cg_emit_byte(gen->cg, 0x48); cg_emit_byte(gen->cg, 0x63); cg_emit_byte(gen->cg, 0xC0); // movsxd rax, eax
        cg_emit_byte(gen->cg, 0xEB); cg_emit_byte(gen->cg, 0);    // jmp done
        int jmp_done = cg_get_size(gen->cg) - 1;

        // equal: xor eax, eax
        gen->cg->buffer[je_equal] = cg_get_size(gen->cg) - je_equal - 1;
        cg_emit_xor_reg_reg(gen->cg, REG_RAX, REG_RAX);

        // done:
        gen->cg->buffer[jmp_done] = cg_get_size(gen->cg) - jmp_done - 1;
    }
    cg_emit_pop_reg(gen->cg, REG_RBP);
    cg_emit_ret(gen->cg);
    }

    // Dump string table into code section with labels
    size_t offset = 0;
    while (offset < gen->string_table_size) {
        char label[32];
        snprintf(label, sizeof(label), ".str%zu", offset);
        cg_emit_label(gen->cg, gen->pt, label);
        
        const char* str = gen->string_table + offset;
        size_t len = strlen(str) + 1; // include null
        for (size_t i = 0; i < len; i++) {
            cg_emit_byte(gen->cg, (uint8_t)str[i]);
        }
        offset += len;
    }
    
    // Dump float pool into code section with labels
    for (size_t i = 0; i < gen->float_pool_size; i++) {
        char label[32];
        snprintf(label, sizeof(label), ".flt%zu", i);
        cg_emit_label(gen->cg, gen->pt, label);
        uint8_t fbytes[4];
        memcpy(fbytes, &gen->float_pool[i], 4);
        for (int b = 0; b < 4; b++) {
            cg_emit_byte(gen->cg, fbytes[b]);
        }
    }

    // Dump static variables pool into code section with labels
    for (int i = 0; i < static_var_count; i++) {
        StaticVarEntry* sv = &static_vars[i];
        cg_emit_label(gen->cg, gen->pt, sv->label_name);
        uint64_t val = 0;
        if (sv->type == TOK_KW_FLOAT) {
            float fval = sv->initial_float;
            memcpy(&val, &fval, 4);
        } else {
            val = (uint64_t)sv->initial_value;
        }
        int bytes = sv->size > 0 ? sv->size : 8;
        for (int b = 0; b < 8 && b < bytes; b++) {
            cg_emit_byte(gen->cg, (uint8_t)((val >> (b * 8)) & 0xFF));
        }
        for (int b = 8; b < bytes; b++)
            cg_emit_byte(gen->cg, 0);
    }

    // Resolve all patches AFTER labels are defined
    if (pt_resolve_patches(gen->cg, gen->pt) > 0) {
        return false;
    }

    return !entry_func_missing;
}

uint8_t* AsmGen_get_native_code(AsmGen* gen, size_t* out_size) {
    *out_size = cg_get_size(gen->cg);
    uint8_t* copy = (uint8_t*)malloc(*out_size);
    memcpy(copy, cg_get_buffer(gen->cg), *out_size);
    return copy;
}

uint8_t* AsmGen_get_data_section(AsmGen* gen, size_t* out_size) {
    (void)gen;
    *out_size = 0;
    return NULL;
}

void AsmGen_free(AsmGen* gen) {
    for (int i=0; i<env_count; i++) free(env[i].name);
    cg_destroy(gen->cg);
    pt_destroy(gen->pt);
    free(gen->string_table);
}

int AsmGen_get_func_count(void) {
    return func_entry_count;
}

const char* AsmGen_get_func_name(int index) {
    if (index >= 0 && index < func_entry_count) {
        return func_entries[index].name;
    }
    return NULL;
}

int AsmGen_get_func_pos(int index) {
    if (index >= 0 && index < func_entry_count) {
        return func_entries[index].position;
    }
    return 0;
}
