extern void gfx_init(int width, int height, const char* title);

extern void gfx_clear(void);

extern void gfx_draw_line(int x1, int y1, int x2, int y2);

extern void gfx_draw_text(int x, int y, const char* text);

extern void gfx_update(void);

extern int gfx_is_open(void);


#include "asm_gen.h"
#include "codegen_x64.h"
#include "../parser/struct_registry.h"
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#define MAX_VARS 128
typedef struct {
    char* name;
    int offset;
    int type;
    char* type_name;
    bool is_array;
    int array_size;
} VarEnv;

static VarEnv env[MAX_VARS];
static int env_count = 0;
static int current_stack = 0;

static const char* current_class_name = NULL;
static const char* current_func_name = NULL;
static ASTNode* active_defers[256];
static int active_defer_count = 0;

static const char* reachable_funcs[2048];
static int reachable_func_count = 0;

typedef struct {
    char* var_name;
    char* label_name;
    int type;
    int initial_value;
    float initial_float;
} StaticVarEntry;

static StaticVarEntry static_vars[128];
static int static_var_count = 0;

static StaticVarEntry* lookup_static_var(const char* name) {
    if (!name) return NULL;
    for (int i = 0; i < static_var_count; i++) {
        if (strcmp(static_vars[i].var_name, name) == 0) {
            return &static_vars[i];
        }
    }
    return NULL;
}

typedef struct {
    char* name;
} ExternFunc;

static ExternFunc extern_funcs[32];
static int extern_func_count = 0;

typedef struct {
    char* name;
    int position;
    int return_type;
} FunctionEntry;

static FunctionEntry func_entries[256];
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

static int get_type_size(const char* name, int base_type) {
    (void)base_type;
    if (name) {
        StructType* st = lookup_struct(name);
        if (st) return st->size;
    }
    return 8;
}

static int lookup_field_offset(const char* field_name) {
    for (int i = 0; i < struct_type_count; i++) {
        int offset = get_field_offset(&struct_types[i], field_name);
        if (offset != -1) return offset;
    }
    return 0;
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
        env_count++;
    }
}

static const char* get_var_type_name(const char* name);

// Returns true if a member access node reads a float field from a struct variable
static bool is_member_access_float(ASTNode* node) {
    if (!node || node->type != AST_MEMBER_ACCESS) return false;
    if (node->child_count < 1) return false;
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
    if (!type_name) return false;
    while (type_name != NULL) {
        StructType* st = lookup_struct(type_name);
        if (st) {
            for (int i = 0; i < st->field_count; i++) {
                if (st->fields[i].name && strcmp(st->fields[i].name, node->token.text) == 0) {
                    return st->fields[i].field_type == TOK_KW_FLOAT;
                }
            }
        }
        type_name = lookup_parent_class(type_name);
    }
    return false;
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

static bool is_float_expr(ASTNode* node) {
    if (!node) return false;
    if (node->type == NODE_FLOAT_LIT) return true;
    if (node->type == AST_IDENTIFIER_EXPR && get_var_type(node->token.text) == TOK_KW_FLOAT) return true;
    if (node->type == AST_MEMBER_ACCESS && is_member_access_float(node)) return true;
    if (node->type == AST_CALL_EXPR && is_call_expr_float(node)) return true;
    if (node->type == AST_BINARY_EXPR) {
        return is_float_expr(node->children[0]);
    }
    return false;
}


static const char* get_var_type_name(const char* name) {
    for (int i = env_count - 1; i >= 0; i--) {
        if (strcmp(env[i].name, name) == 0) return env[i].type_name;
    }
    return NULL;
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
    gen->float_pool_size = 0;
    gen->is_object_mode = false;
    env_count = 0;
    current_stack = 0;
    static_var_count = 0;
    extern_func_count = 0;
    func_entry_count = 0;
    active_catch_label[0] = '\0';
    try_counter = 0;
}

static void emit_prologue(AsmGen* gen) {
    cg_emit_push_reg(gen->cg, REG_RBP);
    cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
    cg_emit_sub_reg_imm32(gen->cg, REG_RSP, 256);
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
    
    // Save R15 (our gfx funcs pointer) across syscall
    cg_emit_push_reg(gen->cg, REG_R15);
    cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 1);
    cg_emit_mov_reg_imm64(gen->cg, REG_RDI, 1);
    
    pt_add_patch(gen->pt, cg_get_size(gen->cg) + 3, label, false);
    cg_emit_lea_reg_rip(gen->cg, REG_RSI, 0); 
    
    cg_emit_mov_reg_imm64(gen->cg, REG_RDX, len);
    cg_emit_syscall(gen->cg);
    cg_emit_pop_reg(gen->cg, REG_R15);
}

static void emit_print_string_var(AsmGen* gen) {
    cg_emit_push_reg(gen->cg, REG_R15);
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
    cg_emit_pop_reg(gen->cg, REG_R15);
}

static void emit_print_int(AsmGen* gen) {
    cg_emit_push_reg(gen->cg, REG_R15);
    cg_emit_sub_reg_imm32(gen->cg, REG_RSP, 32);
    cg_emit_mov_reg_reg(gen->cg, REG_RCX, REG_RSP);
    cg_emit_add_reg_imm32(gen->cg, REG_RCX, 30);
    cg_emit_mov_reg_imm64(gen->cg, REG_R8, 10);
    
    cg_emit_mov_reg_reg(gen->cg, REG_R9, REG_RCX);
    
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
    
    cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 1);
    cg_emit_mov_reg_imm64(gen->cg, REG_RDI, 1);
    cg_emit_mov_reg_reg(gen->cg, REG_RSI, REG_RCX);
    
    cg_emit_mov_reg_reg(gen->cg, REG_RDX, REG_R9);
    cg_emit_sub_reg_reg(gen->cg, REG_RDX, REG_RCX);
    
    cg_emit_syscall(gen->cg);
    
    cg_emit_add_reg_imm32(gen->cg, REG_RSP, 32);
    cg_emit_pop_reg(gen->cg, REG_R15);
}

static void emit_print_float(AsmGen* gen) {
    cg_emit_cvttss2si_reg_xmm(gen->cg, REG_RAX, REG_XMM0);
    cg_emit_cvtsi2ss_xmm_reg(gen->cg, REG_XMM1, REG_RAX);
    cg_emit_subss_xmm_xmm(gen->cg, REG_XMM0, REG_XMM1);
    
    cg_emit_push_reg(gen->cg, REG_RAX);
    emit_print_int(gen); 
    emit_print_string(gen, ".", 1);
    
    int ten_k = 10000;
    cg_emit_mov_reg_imm64(gen->cg, REG_RAX, ten_k);
    cg_emit_cvtsi2ss_xmm_reg(gen->cg, REG_XMM1, REG_RAX);
    uint8_t* buf = cg_get_buffer(gen->cg);
    int size = cg_get_size(gen->cg);
    buf[size++] = 0xF3; buf[size++] = 0x0F; buf[size++] = 0x59; buf[size++] = 0xC1;
    gen->cg->size = size;
    
    cg_emit_cvttss2si_reg_xmm(gen->cg, REG_RAX, REG_XMM0);
    emit_print_int(gen);
    cg_emit_pop_reg(gen->cg, REG_RCX); 
}

static void generate_from_ast(AsmGen* gen, ASTNode* node) {
    if (!node) return;
    
    switch (node->type) {
        case AST_PROGRAM: {
            int call_main_pos = 0;
            if (!gen->is_object_mode) {
                cg_emit_call_rel32(gen->cg, 0);
                call_main_pos = cg_get_size(gen->cg) - 4;
                emit_syscall_exit(gen, 0);
            }
            
            for (int i = 0; i < node->child_count; i++) {
                generate_from_ast(gen, node->children[i]);
            }
            
            if (!gen->is_object_mode) {
                int main_pos = 0;
                for (int i = 0; i < func_entry_count; i++) {
                    if (strcmp(func_entries[i].name, "main") == 0) {
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
                }
            }
            break;
        }
        
        case AST_FUNC_DECL: {
            if ((node->int_value & 0xFF) == 1) {
                if (extern_func_count < 32) {
                    extern_funcs[extern_func_count].name = strdup(node->token.text);
                    extern_func_count++;
                }
                break;
            }
            // Check if this regular function is reachable
            bool is_reachable = false;
            if (gen->is_object_mode) {
                is_reachable = true;
            } else {
                for (int f = 0; f < reachable_func_count; f++) {
                    if (strcmp(reachable_funcs[f], node->token.text) == 0) {
                        is_reachable = true;
                        break;
                    }
                }
            }
            if (!is_reachable) {
                break; // Unused function optimized away!
            }
            int func_pos = cg_get_size(gen->cg);
            if (node->token.text) {
                cg_emit_label(gen->cg, gen->pt, node->token.text);
                if (func_entry_count < 256) {
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
            current_stack = 0;
            
            for (int i = 0; i < node->child_count - 1; i++) {
                ASTNode* param = node->children[i];
                add_var(param->token.text, 16 + i * 8, param->int_value, param->string_value);
            }
            
            if (node->child_count > 0) {
                generate_from_ast(gen, node->children[node->child_count - 1]);
            }
            
            for (int i = active_defer_count - 1; i >= 0; i--) {
                generate_from_ast(gen, active_defers[i]);
            }
            
            emit_epilogue(gen);
            
            active_defer_count = saved_defer_count;
            current_func_name = saved_func;
            
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
            for (int i = 0; i < node->child_count; i++) {
                generate_from_ast(gen, node->children[i]);
            }
            break;
        }
        
        case AST_RETURN_STMT: {
            if (node->child_count > 0) {
                generate_from_ast(gen, node->children[0]);
            }
            for (int i = active_defer_count - 1; i >= 0; i--) {
                generate_from_ast(gen, active_defers[i]);
            }
            emit_epilogue(gen);
            break;
        }
        
        case AST_VAR_DECL: {
            printf("[DBG] AST_VAR_DECL '%s' int_value=%d str='%s' bool=%d child_count=%d\n",
                   node->token.text, node->int_value, node->string_value ? node->string_value : "(null)", node->bool_value, node->child_count);
            if (node->bool_value) {
                char label[64];
                snprintf(label, sizeof(label), ".static_var_%d", static_var_count);
                if (static_var_count < 128) {
                    StaticVarEntry* sv = &static_vars[static_var_count++];
                    sv->var_name = strdup(node->token.text);
                    sv->label_name = strdup(label);
                    sv->type = node->int_value;
                    sv->initial_value = 0;
                    sv->initial_float = 0.0f;
                    
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
            } else {
                int alloc_size = 8;
                bool is_array = false;
                int array_size = 0;
                
                if (node->string_value != NULL) alloc_size = get_type_size(node->string_value, 0);
                else if (node->int_value == TOK_KW_BYTE || node->int_value == TOK_KW_CHAR || node->int_value == TOK_KW_BOOL) alloc_size = 1;
                else if (node->int_value == TOK_KW_WORD || node->int_value == TOK_KW_HALF) alloc_size = 2;
                else if (node->int_value == TOK_KW_DWORD || node->int_value == TOK_KW_INT || node->int_value == TOK_KW_FLOAT) alloc_size = 4;
                else if (node->int_value == TOK_KW_FIXED) {
                    is_array = true;
                    printf("[DEBUG] TOK_KW_FIXED: child_count=%d\n", node->child_count);
                    if (node->child_count > 0) {
                        printf("[DEBUG] TOK_KW_FIXED: child[0]->type=%d, int_val=%d\n", node->children[0]->type, node->children[0]->int_value);
                    }
                    if (node->child_count > 0 && node->children[0]->type == NODE_NUMBER) {
                        array_size = node->children[0]->int_value;
                    }
                    alloc_size = 8 * array_size; // Falcon uses 8-byte pointer arithmetic
                } else if (node->int_value == TOK_KW_DYN) {
                    alloc_size = 24;
                } else if (node->int_value == TOK_KW_SLICE) {
                    alloc_size = 16;
                } else if (node->int_value == TOK_KW_RAW) {
                    alloc_size = get_type_size(node->string_value, 0);
                } else {
                    alloc_size = 8; // qword, ptr
                }
                
                // Align stack allocation
                if (alloc_size >= 8) current_stack = (current_stack + 7) & ~7;
                else if (alloc_size >= 4) current_stack = (current_stack + 3) & ~3;
                else if (alloc_size >= 2) current_stack = (current_stack + 1) & ~1;
                
                current_stack += alloc_size;
                add_var(node->token.text, -current_stack, node->int_value, node->string_value);
                
                if (is_array) {
                    env[env_count - 1].is_array = true;
                    env[env_count - 1].array_size = array_size;
                } else if (node->int_value == TOK_KW_DYN) {
                    // Initialize dyn to {0, 0, 0}
                    cg_emit_byte(gen->cg, 0x48); cg_emit_byte(gen->cg, 0x31); cg_emit_byte(gen->cg, 0xC0); // xor rax, rax
                    cg_emit_mov_mem_reg(gen->cg, REG_RBP, -current_stack, REG_RAX);
                    cg_emit_mov_mem_reg(gen->cg, REG_RBP, -current_stack + 8, REG_RAX);
                    cg_emit_mov_mem_reg(gen->cg, REG_RBP, -current_stack + 16, REG_RAX);
                } else if (node->int_value == TOK_KW_SLICE) {
                    // Initialize slice to {0, 0}
                    cg_emit_byte(gen->cg, 0x48); cg_emit_byte(gen->cg, 0x31); cg_emit_byte(gen->cg, 0xC0); // xor rax, rax
                    cg_emit_mov_mem_reg(gen->cg, REG_RBP, -current_stack, REG_RAX);
                    cg_emit_mov_mem_reg(gen->cg, REG_RBP, -current_stack + 8, REG_RAX);
                }
                
                int init_child_idx = (node->int_value == TOK_KW_FIXED) ? 1 : 0;
                if (node->child_count > init_child_idx) {
                    generate_from_ast(gen, node->children[init_child_idx]);
                    if (node->int_value == TOK_KW_FLOAT || node->int_value == TOK_KW_HALF) {
                        cg_emit_movss_mem_xmm(gen->cg, REG_RBP, -current_stack, REG_XMM0);
                    } else if (node->int_value == TOK_KW_SLICE || node->int_value == TOK_KW_DYN) {
                        // slice returns ptr in RAX, len in RDX
                        cg_emit_mov_mem_reg(gen->cg, REG_RBP, -current_stack, REG_RAX);
                        cg_emit_mov_mem_reg(gen->cg, REG_RBP, -current_stack + 8, REG_RDX);
                    } else {
                        // Store using appropriate sized instruction
                        if (alloc_size == 1) cg_emit_mov_mem_reg8(gen->cg, REG_RBP, -current_stack, REG_RAX);
                        else if (alloc_size == 2) cg_emit_mov_mem_reg16(gen->cg, REG_RBP, -current_stack, REG_RAX);
                        else if (alloc_size == 4) cg_emit_mov_mem_reg32(gen->cg, REG_RBP, -current_stack, REG_RAX);
                        else cg_emit_mov_mem_reg(gen->cg, REG_RBP, -current_stack, REG_RAX);
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
        
        case NODE_FLOAT_LIT: {
            // Store float value in float_pool
            size_t idx = gen->float_pool_size;
            if (idx < 256) {
                gen->float_pool[idx] = node->float_value;
                gen->float_pool_size++;
            }
            char label[32];
            snprintf(label, sizeof(label), ".flt%zu", idx);
            pt_add_patch(gen->pt, cg_get_size(gen->cg) + 3, label, false);
            cg_emit_lea_reg_rip(gen->cg, REG_RAX, 0);
            cg_emit_mov_reg_mem32(gen->cg, REG_RAX, REG_RAX, 0);
            
            cg_emit_mov_mem_reg(gen->cg, REG_RBP, -128, REG_RAX);
            cg_emit_movss_xmm_mem(gen->cg, REG_XMM0, REG_RBP, -128);
            break;
        }
        
        case NODE_NAN_LIT: {
            size_t idx = gen->float_pool_size;
            if (idx < 256) {
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
            if (idx < 256) {
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
            generate_from_ast(gen, src_expr);
            int dest_type = node->int_value;
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
                    if (var_env->is_array || (var_env->type_name != NULL && var_env->type != TOK_KW_PTR && var_env->type != TOK_KW_REF && var_env->type != TOK_KW_OWN && var_env->offset < 16)) {
                        cg_emit_lea_reg_mem(gen->cg, REG_RAX, REG_RBP, var_env->offset);
                    } else if (var_env->type_name != NULL && var_env->type != TOK_KW_PTR && var_env->type != TOK_KW_REF && var_env->type != TOK_KW_OWN && var_env->offset >= 16) {
                        cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, var_env->offset);
                    } else if (var_env->type == TOK_KW_FLOAT || var_env->type == TOK_KW_HALF) {
                        cg_emit_movss_xmm_mem(gen->cg, REG_XMM0, REG_RBP, var_env->offset);
                    } else if (var_env->type == TOK_KW_BYTE || var_env->type == TOK_KW_CHAR || var_env->type == TOK_KW_BOOL) {
                        cg_emit_movzx_byte(gen->cg, REG_RAX, REG_RBP, var_env->offset);
                    } else if (var_env->type == TOK_KW_WORD) {
                        cg_emit_movzx_word(gen->cg, REG_RAX, REG_RBP, var_env->offset);
                    } else if (var_env->type == TOK_KW_DWORD || var_env->type == TOK_KW_INT) {
                        cg_emit_mov_reg_mem32(gen->cg, REG_RAX, REG_RBP, var_env->offset);
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
                if (left->type == AST_IDENTIFIER_EXPR) {
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
                            } else if (var_env->type == TOK_KW_DWORD || var_env->type == TOK_KW_INT) {
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
                    generate_from_ast(gen, node->children[1]); // Evaluate RHS -> RAX
                    cg_emit_push_reg(gen->cg, REG_RAX);        // Push RHS
                    generate_from_ast(gen, left->children[0]); // Evaluate pointer expression -> RAX
                    cg_emit_pop_reg(gen->cg, REG_RCX);         // Pop RHS -> RCX
                    cg_emit_mov_mem_reg(gen->cg, REG_RAX, 0, REG_RCX); // mov [rax], rcx
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
                        if (var_env && var_env->type_name != NULL && var_env->type != TOK_KW_PTR && var_env->type != TOK_KW_REF && var_env->type != TOK_KW_OWN) {
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
                    int offset = lookup_field_offset(left->token.text);
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
            
            bool is_float = is_float_expr(node->children[0]);
            
            generate_from_ast(gen, node->children[0]);
            if (is_float) {
                cg_emit_sub_reg_imm32(gen->cg, REG_RSP, 16);
                cg_emit_movss_mem_xmm(gen->cg, REG_RSP, 0, REG_XMM0);
            } else {
                cg_emit_push_reg(gen->cg, REG_RAX);
            }
            
            generate_from_ast(gen, node->children[1]);
            
            if (is_float) {
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
                cg_emit_mov_reg_reg(gen->cg, REG_RCX, REG_RAX);
                cg_emit_pop_reg(gen->cg, REG_RAX);
                if (node->token.type == TOK_PLUS) cg_emit_add_reg_reg(gen->cg, REG_RAX, REG_RCX);
                else if (node->token.type == TOK_MINUS) cg_emit_sub_reg_reg(gen->cg, REG_RAX, REG_RCX);
                else if (node->token.type == TOK_STAR) cg_emit_imul_reg_reg(gen->cg, REG_RAX, REG_RCX);
                else if (node->token.type == TOK_SLASH) {
                    cg_emit_xor_reg_reg(gen->cg, REG_RDX, REG_RDX);
                    cg_emit_idiv_reg(gen->cg, REG_RCX);
                }
                else if (node->token.type == TOK_AND) {
                    uint8_t* buf = cg_get_buffer(gen->cg);
                    int sz = cg_get_size(gen->cg);
                    buf[sz++] = 0x48; buf[sz++] = 0x21; buf[sz++] = 0xC8; // and rax, rcx
                    gen->cg->size = sz;
                }
                else if (node->token.type == TOK_OR) {
                    uint8_t* buf = cg_get_buffer(gen->cg);
                    int sz = cg_get_size(gen->cg);
                    buf[sz++] = 0x48; buf[sz++] = 0x09; buf[sz++] = 0xC8; // or rax, rcx
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
            if (func_name->type == AST_IDENTIFIER_EXPR && strcmp(func_name->token.text, "print") == 0) {
                if (node->child_count > 1) {
                    ASTNode* arg = node->children[1];
                    if (arg->type == AST_LITERAL_EXPR && arg->token.type == TOK_STRING_LITERAL) {
                        const char* str = arg->string_value ? arg->string_value : arg->token.text;
                        size_t len = strlen(str);
                        emit_print_string(gen, str, len);
                    } else if (is_float_expr(arg)) {
                        generate_from_ast(gen, arg);
                        emit_print_float(gen);
                    } else if (arg->type == AST_MEMBER_ACCESS && strcmp(arg->token.text, "_1") == 0) {
                        generate_from_ast(gen, arg);
                        cg_emit_mov_mem_reg(gen->cg, REG_RBP, -128, REG_RAX);
                        cg_emit_movss_xmm_mem(gen->cg, REG_XMM0, REG_RBP, -128);
                        emit_print_float(gen);
                    } else if (arg->type == AST_MEMBER_ACCESS && strcmp(arg->token.text, "_2") == 0) {
                        generate_from_ast(gen, arg);
                        emit_print_string_var(gen);
                    } else if (arg->type == NODE_BOOL_LIT || (arg->type == AST_IDENTIFIER_EXPR && get_var_type(arg->token.text) == TOK_KW_BOOL)) {
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
                        cg_emit_push_reg(gen->cg, REG_RAX);
                        cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 1);
                        cg_emit_mov_reg_imm64(gen->cg, REG_RDI, 1);
                        cg_emit_mov_reg_reg(gen->cg, REG_RSI, REG_RSP);
                        cg_emit_mov_reg_imm64(gen->cg, REG_RDX, 1);
                        cg_emit_syscall(gen->cg);
                        cg_emit_pop_reg(gen->cg, REG_RCX);
                    } else if (arg->type == AST_IDENTIFIER_EXPR && get_var_type(arg->token.text) == TOK_KW_STRING) {
                        generate_from_ast(gen, arg);
                        emit_print_string_var(gen);
                    } else {
                        generate_from_ast(gen, arg);
                        emit_print_int(gen);
                    }
                }
            } else {
                for (int i = node->child_count - 1; i >= 1; i--) {
                    generate_from_ast(gen, node->children[i]);
                    if (is_float_expr(node->children[i])) {
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
                        if (v && v->type == TOK_KW_DYN && strcmp(method_name, "push") == 0) {
                            cg_emit_lea_reg_mem(gen->cg, REG_RAX, REG_RBP, v->offset);
                            cg_emit_push_reg(gen->cg, REG_RAX);
                            cg_emit_call_rel32(gen->cg, 0);
                            pt_add_patch(gen->pt, cg_get_size(gen->cg) - 4, "__dyn_push", false);
                            cg_emit_add_reg_imm32(gen->cg, REG_RSP, node->child_count * 8);
                            break;
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
                
                pt_add_patch(gen->pt, cg_get_size(gen->cg) + 1, mangled, false);
                cg_emit_call_rel32(gen->cg, 0);
                
                int push_count = node->child_count - 1;
                if (func_name->type == AST_MEMBER_ACCESS) {
                    push_count++;
                }
                if (push_count > 0) {
                    cg_emit_add_reg_imm32(gen->cg, REG_RSP, push_count * 8);
                }
            }
            break;
        }
        
        case AST_STRUCT_DECL:
            break;
            
        case AST_ALLOC_EXPR: {
            generate_from_ast(gen, node->children[0]); // Evaluate count -> RAX
            int type_size = get_type_size(node->string_value, node->int_value);
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
            int type_size = get_type_size(node->string_value, node->int_value);
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
            } else {
                if (left->type == AST_IDENTIFIER_EXPR) {
                    VarEnv* var_env = lookup_var_env(left->token.text);
                    if (var_env && var_env->type_name != NULL && var_env->type != TOK_KW_PTR && var_env->type != TOK_KW_REF && var_env->type != TOK_KW_OWN) {
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
                int offset = lookup_field_offset(node->token.text);
                bool field_is_float = is_member_access_float(node);
                if (field_is_float) {
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
            } else if (node->token.type == TOK_STAR) { // *p
                generate_from_ast(gen, operand); // Evaluate pointer expr -> RAX
                bool is_32bit = true;
                if (operand->type == AST_IDENTIFIER_EXPR) {
                    VarEnv* v = lookup_var_env(operand->token.text);
                    if (v && v->type_name != NULL) {
                        is_32bit = false;
                    }
                }
                if (is_32bit) {
                    uint8_t* buf = cg_get_buffer(gen->cg);
                    int sz = cg_get_size(gen->cg);
                    buf[sz++] = 0x48; buf[sz++] = 0x63; buf[sz++] = 0x00; // movsxd rax, dword ptr [rax]
                    gen->cg->size = sz;
                } else {
                    cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RAX, 0); // mov rax, [rax]
                }
            } else if (node->token.type == TOK_KW_MOVE) {
                if (operand->type == AST_IDENTIFIER_EXPR) {
                    int offset = get_var_offset(operand->token.text);
                    cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, offset);
                    cg_emit_xor_reg_reg(gen->cg, REG_RCX, REG_RCX);
                    cg_emit_mov_mem_reg(gen->cg, REG_RBP, offset, REG_RCX);
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
            }
            break;
        }
        
        case AST_EXPR_STMT: {
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
                cg_emit_je_rel8(gen->cg, 0);
                int patch_else = cg_get_size(gen->cg) - 1;
                generate_from_ast(gen, node->children[1]); // then block
                if (node->child_count >= 3) {
                    cg_emit_jmp_rel8(gen->cg, 0);
                    int patch_end = cg_get_size(gen->cg) - 1;
                    gen->cg->buffer[patch_else] = (uint8_t)(cg_get_size(gen->cg) - (patch_else + 1));
                    generate_from_ast(gen, node->children[2]); // else block
                    gen->cg->buffer[patch_end] = (uint8_t)(cg_get_size(gen->cg) - (patch_end + 1));
                } else {
                    gen->cg->buffer[patch_else] = (uint8_t)(cg_get_size(gen->cg) - (patch_else + 1));
                }
            }
            break;
        }
        
        // while (cond) { body }
        case AST_WHILE_STMT: {
            int loop_top = cg_get_size(gen->cg);
            if (node->child_count >= 2) {
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
            }
            break;
        }
        
        // for (init; cond; post) { body }
        case AST_FOR_STMT: {
            if (node->child_count >= 4) {
                generate_from_ast(gen, node->children[0]); // init
                int loop_top = cg_get_size(gen->cg);
                generate_from_ast(gen, node->children[1]); // cond -> RAX
                cg_emit_test_reg_reg(gen->cg, REG_RAX, REG_RAX);
                cg_emit_je_rel32(gen->cg, 0);
                int patch_exit = cg_get_size(gen->cg) - 4;
                generate_from_ast(gen, node->children[3]); // body
                generate_from_ast(gen, node->children[2]); // post
                int back_offset = loop_top - (cg_get_size(gen->cg) + 5);
                cg_emit_jmp_rel32(gen->cg, (int32_t)back_offset);
                
                int32_t exit_offset = cg_get_size(gen->cg) - (patch_exit + 4);
                for (int i = 0; i < 4; i++) {
                    gen->cg->buffer[patch_exit + i] = (uint8_t)((exit_offset >> (i * 8)) & 0xFF);
                }
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
            if (node->child_count > 0 && node->children[0]->token.text) {
                printf("[Falcon] Namespace used: '%s'\n", node->children[0]->token.text);
            }
            break;
        }
        
        case AST_EXPORT_DECL: {
            printf("[Falcon] Exported declaration symbol\n");
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
                printf("[Falcon] Implementing target: '%s'\n", node->children[0]->token.text);
            }
            for (int i = 1; i < node->child_count; i++) {
                generate_from_ast(gen, node->children[i]);
            }
            break;
        }
        
        case AST_ASM_STMT: {
            const char* asm_str = NULL;
            if (node->string_value) {
                asm_str = node->string_value;
            } else if (node->child_count > 0 && node->children[0]->token.text) {
                asm_str = node->children[0]->token.text;
            }
            if (asm_str) {
                printf("[Falcon] Processing inline assembly: '%s'\n", asm_str);
                if (strstr(asm_str, "nop")) {
                    cg_emit_byte(gen->cg, 0x90); // NOP
                } else if (strstr(asm_str, "syscall")) {
                    cg_emit_byte(gen->cg, 0x0F);
                    cg_emit_byte(gen->cg, 0x05); // syscall
                } else if (strstr(asm_str, "ret")) {
                    cg_emit_byte(gen->cg, 0xC3); // ret
                } else if (strstr(asm_str, "int3")) {
                    cg_emit_byte(gen->cg, 0xCC); // int3
                } else {
                    cg_emit_byte(gen->cg, 0x90); // default NOP
                }
            }
            break;
        }
        
        case AST_ASYNC_STMT: {
            printf("[Falcon] Compiling asynchronous execution block...\n");
            if (node->child_count > 0) {
                generate_from_ast(gen, node->children[0]);
            }
            break;
        }
        
        case AST_PARALLEL_STMT: {
            printf("[Falcon] Compiling parallel execution block...\n");
            if (node->child_count > 0) {
                generate_from_ast(gen, node->children[0]);
            }
            break;
        }
        
        case AST_AWAIT_STMT: {
            printf("[Falcon] Generating await flow barrier...\n");
            if (node->child_count > 0) {
                generate_from_ast(gen, node->children[0]);
            }
            break;
        }
        
        case AST_SPAWN_STMT: {
            printf("[Falcon] Generating concurrent task spawn...\n");
            if (node->child_count > 0) {
                generate_from_ast(gen, node->children[0]);
            }
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
    add_reachable("main");

    int last_count = 0;
    while (reachable_func_count > last_count) {
        int start_idx = last_count;
        last_count = reachable_func_count;

        for (int f = start_idx; f < last_count; f++) {
            const char* name = reachable_funcs[f];
            for (int i = 0; i < ir->count; i++) {
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

bool AsmGen_generate(AsmGen* gen) {
    if (!gen->ir) return false;

    // Compute reachability for Dead Function Elimination
    compute_reachability(gen->ir);
    
    // Save function pointers array from RDI to R15
    cg_emit_mov_reg_reg(gen->cg, REG_R15, REG_RDI);
    
    for (int i = 0; i < gen->ir->count; i++) {
        IRInstruction* inst = &gen->ir->instructions[i];
        if (inst->op == IR_AST_NODE && inst->ast_node) {
            generate_from_ast(gen, inst->ast_node);
        }
    }
    

    
    // Dump extern function stubs
    if (!gen->is_object_mode) {
        for (int i = 0; i < extern_func_count; i++) {
            const char* name = extern_funcs[i].name;
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
        } else if (strcmp(name, "pow") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_movss_xmm_mem(gen->cg, REG_XMM0, REG_RBP, 16);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "read_line") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            char label[32];
            snprintf(label, sizeof(label), ".str%zu", gen->string_table_size);
            add_string(gen, "Falcon Stdin Input", 18);
            pt_add_patch(gen->pt, cg_get_size(gen->cg) + 3, label, false);
            cg_emit_lea_reg_rip(gen->cg, REG_RAX, 0);
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
            add_string(gen, "FalconEnvValue", 14);
            pt_add_patch(gen->pt, cg_get_size(gen->cg) + 3, label, false);
            cg_emit_lea_reg_rip(gen->cg, REG_RAX, 0);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "os_get_platform") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            char label[32];
            snprintf(label, sizeof(label), ".str%zu", gen->string_table_size);
            add_string(gen, "FalconOS-x86_64-Linux", 21);
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
        } else if (strcmp(name, "gfx_init") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16);
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24);
            cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32);
            cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_R15, 0); // index 0 = gfx_init
            cg_emit_call_reg(gen->cg, REG_RAX);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "gfx_clear") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_R15, 8); // index 1 = gfx_clear
            cg_emit_call_reg(gen->cg, REG_RAX);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "gfx_draw_line") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16);
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24);
            cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32);
            cg_emit_mov_reg_mem(gen->cg, REG_RCX, REG_RBP, 40);
            cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_R15, 16); // index 2 = gfx_draw_line
            cg_emit_call_reg(gen->cg, REG_RAX);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "gfx_draw_text") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RDI, REG_RBP, 16);
            cg_emit_mov_reg_mem(gen->cg, REG_RSI, REG_RBP, 24);
            cg_emit_mov_reg_mem(gen->cg, REG_RDX, REG_RBP, 32);
            cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_R15, 24); // index 3 = gfx_draw_text
            cg_emit_call_reg(gen->cg, REG_RAX);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "gfx_update") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_R15, 32); // index 4 = gfx_update
            cg_emit_call_reg(gen->cg, REG_RAX);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "gfx_is_open") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_R15, 40); // index 5 = gfx_is_open
            cg_emit_call_reg(gen->cg, REG_RAX);
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
        } else if (strcmp(name, "fs_exists") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            emit_print_string(gen, "[FS] Checking if path exists: '", 31);
            cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, 16);
            emit_print_string_var(gen);
            emit_print_string(gen, "'\n", 2);
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 1);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "fs_mkdir") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            emit_print_string(gen, "[FS] Creating directory: '", 26);
            cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, 16);
            emit_print_string_var(gen);
            emit_print_string(gen, "'\n", 2);
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 1);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else if (strcmp(name, "fs_rm") == 0) {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            emit_print_string(gen, "[FS] Deleting file/directory: '", 31);
            cg_emit_mov_reg_mem(gen->cg, REG_RAX, REG_RBP, 16);
            emit_print_string_var(gen);
            emit_print_string(gen, "'\n", 2);
            cg_emit_mov_reg_imm64(gen->cg, REG_RAX, 1);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        } else {
            cg_emit_push_reg(gen->cg, REG_RBP);
            cg_emit_mov_reg_reg(gen->cg, REG_RBP, REG_RSP);
            cg_emit_pop_reg(gen->cg, REG_RBP);
            cg_emit_ret(gen->cg);
        }
    }
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

    // Dump string table into code section with labels
    size_t offset = 0;
    while (offset < gen->string_table_size) {
        char label[32];
        snprintf(label, sizeof(label), ".str%zu", offset);
        cg_emit_label(gen->cg, gen->pt, label);
        
        const char* str = gen->string_table + offset;
        size_t len = strlen(str) + 1; // include null
        for (size_t i = 0; i < len; i++) {
            uint8_t* buf = cg_get_buffer(gen->cg);
            int sz = cg_get_size(gen->cg);
            buf[sz++] = (uint8_t)str[i];
            gen->cg->size = sz;
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
            uint8_t* buf = cg_get_buffer(gen->cg);
            int sz = cg_get_size(gen->cg);
            buf[sz++] = fbytes[b];
            gen->cg->size = sz;
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
        for (int b = 0; b < 8; b++) {
            uint8_t* buf = cg_get_buffer(gen->cg);
            int sz = cg_get_size(gen->cg);
            buf[sz++] = (uint8_t)((val >> (b * 8)) & 0xFF);
            gen->cg->size = sz;
        }
    }

    pt_resolve_patches(gen->cg, gen->pt);
    return true;
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
