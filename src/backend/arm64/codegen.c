/*
 * ARM64 (AArch64) backend for Magnetar.
 *
 * Emits AArch64 machine code directly.  No assembler, compiler or external
 * tool is invoked.  Generated programs are standalone ELF64 ET_EXEC files.
 *
 * The supported subset covers the core language used by the test-suite:
 * scalar locals, arithmetic/comparisons, if/while/for, functions, printing,
 * fixed arrays, casts, simple allocation, and raw syscalls.
 */
#include "../../backend/backend.h"
#include "../../backend/elf_writer.h"
#include "../../parser/ast.h"
#include "../../parser/struct_registry.h"
#include "codegen.h"
#include "stubs.h"
#include <math.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define ARM_MAX_SYMS       512
#define ARM_MAX_GLOBALS    256
#define ARM_MAX_FUNCS      512
#define ARM_MAX_RELOCS     4096
#define ARM_MAX_STRINGS    1024
#define ARM_MAX_LABELS     512
#define ARM_MAX_LOOPS      128
#define ARM_MAX_EPILOGUES  512
#define ARM_SCRATCH_SLOTS  16
#define ARM_LOCAL_BASE     136
#define ELF_BASE           0x400000ULL

/* ------------------------------------------------------------------ */
/* Utilities                                                          */
/* ------------------------------------------------------------------ */

typedef struct { uint8_t* data; size_t len, cap; } ByteBuf;

static void bb_init(ByteBuf* b, size_t cap) {
    b->cap = cap ? cap : 256;
    b->data = (uint8_t*)malloc(b->cap);
    b->len = 0;
}
static void bb_put(ByteBuf* b, const uint8_t* p, size_t n) {
    if (!b->data) return;
    while (b->len + n > b->cap) {
        b->cap *= 2;
        uint8_t* q = (uint8_t*)realloc(b->data, b->cap);
        if (!q) return;
        b->data = q;
    }
    memcpy(b->data + b->len, p, n);
    b->len += n;
}
static void bb_free(ByteBuf* b) { free(b->data); b->data = NULL; b->len = b->cap = 0; }
static void put64(uint8_t* p, uint64_t v);

static uint32_t ld32(const uint8_t* p) {
    return (uint32_t)p[0] | ((uint32_t)p[1]<<8) | ((uint32_t)p[2]<<16) | ((uint32_t)p[3]<<24);
}
static void st32(uint8_t* p, uint32_t w) {
    p[0]=(uint8_t)w; p[1]=(uint8_t)(w>>8); p[2]=(uint8_t)(w>>16); p[3]=(uint8_t)(w>>24);
}
static uint32_t align16u(uint32_t n) { return (n+15u)&~15u; }

/* Token values from token.h. */
enum {
    T_INT=7, T_FLOAT=8, T_BOOL=9, T_CHAR=10, T_STRING=11, T_VOID=12, T_AUTO=13,
    T_ANY=14, T_BYTE=15, T_WORD=16, T_DWORD=17, T_QWORD=18, T_HALF=19,
    T_ARRAY=20, T_DYN=21, T_SLICE=22, T_TUPLE=23, T_RANGE=24, T_PTR=26,
    T_REF=27, T_OWN=28, T_RAW=29, T_FIXED=30,
    T_EQ=98, T_NEQ=99, T_LT=100, T_LE=101, T_GT=102, T_GE=103,
    T_AND=104, T_OR=105
};

typedef enum {
    VK_INT=0, VK_FLOAT, VK_STRING, VK_BOOL, VK_CHAR, VK_ARRAY, VK_PTR, VK_STRUCT, VK_VOID,
    VK_ANY
} ValueKind;

typedef struct {
    char* name; char* type_name; ValueKind kind;
    int offset, size, elem_size, array_len;
    bool is_dyn; int dyn_cap;
    bool is_global_const; bool is_global_mutable; int64_t const_value;
} Sym;

typedef struct {
    char* name; size_t offset; ValueKind ret_kind; bool is_extern;
    char* ret_type_name; int ret_size;
} Func;

typedef enum { RELOC_BRANCH=0, RELOC_ADDR=1, RELOC_DATA_ADDR=2 } RelocType;
typedef struct { size_t pos; char* name; RelocType type; } Reloc;
/* A pointer stored inside the mutable-global data image. Resolved after all
   string labels are known; in object mode it becomes an ABS64 MAG2 patch. */
typedef struct { size_t offset; char* name; } DataReloc;
typedef struct { char* name; uint8_t* bytes; size_t len, offset; uint64_t addr; } Str;
typedef struct { char* name; size_t pos; } Label;
typedef struct {
    size_t breaks[64], continues[64]; int nb, nc;
} LoopFrame;

struct ArmGen {
    A64Buf code;
    ByteBuf rodata, data;
    Sym locals[ARM_MAX_SYMS]; int local_count;
    Sym globals[ARM_MAX_GLOBALS]; int global_count;
    Func funcs[ARM_MAX_FUNCS]; int func_count;
    Label labels[ARM_MAX_LABELS]; int label_count;
    Reloc relocs[ARM_MAX_RELOCS]; int reloc_count;
    DataReloc data_relocs[ARM_MAX_RELOCS]; int data_reloc_count;
    Str strings[ARM_MAX_STRINGS]; int string_count;
    LoopFrame loops[ARM_MAX_LOOPS]; int loop_depth;
    size_t epilogues[ARM_MAX_EPILOGUES]; int epilogue_count;
    int local_bytes, scratch_depth;
    int scope_stack[ARM_MAX_SYMS]; int scope_depth;
    char* entry_name;
    bool object_mode;
    char obj_prefix[64];
    ASTNode* program;
    Func* current_func;
    int current_sret_offset;
    int ret_save_offset;
    ASTNode* defers[256]; int defer_count;
    char active_catch[128];
    char current_type[128];   /* enclosing type for `this.method()` resolution */
    bool abi_error;           /* unsupported call shape; generation must fail */
    int try_counter;
    bool task_statics;        /* pipe/pid table for spawn/async/parallel/await */
};

static ValueKind kind_from_token(int tok) {
    switch (tok) {
        case T_FLOAT: case T_HALF: return VK_FLOAT;
        case T_BOOL: return VK_BOOL;
        case T_CHAR: return VK_CHAR;
        case T_STRING: return VK_STRING;
        case T_ANY: return VK_ANY;
        case T_VOID: return VK_VOID;
        case T_SLICE: case T_PTR: case T_REF: case T_OWN: case T_RAW: return VK_PTR;
        default: return VK_INT;
    }
}
static int elem_size_from_token(int tok) {
    switch (tok) {
        case T_CHAR: case T_BYTE: return 1;
        case T_HALF: case T_FLOAT: case T_DWORD: return 4;
        case T_ANY: return 16;
        default: return 8;
    }
}
/* The parser strides array elements by 16 bytes only for `any`; all other
   element types keep the 8-byte language slot even when their scalar width
   is 1 or 4 bytes.  Mirror parser_elem_slot_size() exactly. */
static int arm_array_slot_size(int elem_tok) {
    return elem_tok == T_ANY ? 16 : 8;
}
static int arm_type_size_name(const char* name) {
    if (!name) return 8;
    if (!strcmp(name,"char")||!strcmp(name,"byte")) return 1;
    if (!strcmp(name,"float")||!strcmp(name,"half")||!strcmp(name,"dword")) return 4;
    return 8;
}
static void free_sym(Sym* s) { free(s->name); free(s->type_name); s->name=s->type_name=NULL; }

static void arm_push_local(ArmGen* g, const char* name, const char* type_name,
                           ValueKind kind, int offset, int size, int elem_size, int array_len) {
    if (!name || g->local_count >= ARM_MAX_SYMS) return;
    Sym* s = &g->locals[g->local_count++];
    memset(s, 0, sizeof(*s));
    s->name = strdup(name);
    s->type_name = type_name ? strdup(type_name) : NULL;
    s->kind = kind; s->offset = offset; s->size = size;
    s->elem_size = elem_size ? elem_size : 8;
    s->array_len = array_len;
}
static Sym* arm_find_sym(ArmGen* g, const char* name) {
    if (!name) return NULL;
    for (int i=g->local_count-1; i>=0; i--)
        if (g->locals[i].name && !strcmp(g->locals[i].name,name)) return &g->locals[i];
    for (int i=g->global_count-1; i>=0; i--)
        if (g->globals[i].name && !strcmp(g->globals[i].name,name)) return &g->globals[i];
    return NULL;
}
static StructField* arm_var_field(ArmGen* g, ASTNode* base, const char* field_name) {
    if (!field_name) return NULL;
    const char* type_name = NULL;
    if (base && (base->type==AST_IDENTIFIER_EXPR||base->type==NODE_IDENT)) {
        Sym* s = arm_find_sym(g, base->token.text);
        if (s) type_name = s->type_name;
    } else if (base && base->type==NODE_THIS) {
        Sym* s = arm_find_sym(g, "this");
        if (s) type_name = s->type_name;
    }
    StructField* f = find_field(type_name ? lookup_struct(type_name) : NULL, field_name);
    if (f) return f;
    for (int i=0;i<struct_type_count;i++) {
        f = find_field(&struct_types[i], field_name);
        if (f) return f;
    }
    return NULL;
}
static int arm_field_offset(ArmGen* g, ASTNode* base, const char* field_name) {
    StructField* f = arm_var_field(g, base, field_name);
    return f ? f->offset : 0;
}
/* Resolve an unqualified identifier inside a method to a field of `this`. */
static StructField* arm_this_field(ArmGen* g, const char* name) {
    Sym* th = arm_find_sym(g, "this");
    if (!th || !name) return NULL;
    StructField* f = find_field(lookup_struct(th->type_name ? th->type_name : ""), name);
    if (f) return f;
    /* Some method receivers lose their type name; fall back to a unique field. */
    for (int i=0;i<struct_type_count;i++) {
        f = find_field(&struct_types[i], name);
        if (f) return f;
    }
    return NULL;
}
static void arm_emit_addr(ArmGen* g, int rd, int rn, int offset);
/* Load the address of an unqualified `this` field into rd. */
static void arm_emit_this_field_addr(ArmGen* g, int rd, StructField* f) {
    Sym* th = arm_find_sym(g, "this");
    if (!th || !f) { a64_mov_imm(&g->code,rd,0); return; }
    arm_emit_addr(g,9,29,th->offset);
    a64_ldr_x(&g->code,9,9,0);
    arm_emit_addr(g,rd,9,f->offset);
}
static bool arm_call_is_method(ASTNode* n) {
    if (!n || n->child_count<1) return false;
    /* Only a member-access callee denotes a method call. A member access in
       the first argument position (e.g. f(obj.x, n)) is just an argument. */
    ASTNode* f=n->children[0];
    return f && f->type==AST_MEMBER_ACCESS;
}
/* Resolve Type_method, walking parent classes the same way the x86_64
   backend does.  Returns a stable function name owned by g->funcs. */
static const char* arm_find_method_symbol(ArmGen* g, const char* type_name,
                                          const char* method) {
    if (!type_name || !*type_name || !method) return NULL;
    char mangled[320];
    const char* resolve=type_name;
    for (int depth=0; resolve && *resolve && depth<16; depth++) {
        snprintf(mangled,sizeof(mangled),"%s_%s",resolve,method);
        for (int i=0;i<g->func_count;i++)
            if (g->funcs[i].name && !strcmp(g->funcs[i].name,mangled))
                return g->funcs[i].name;
        resolve=lookup_parent_class(resolve);
    }
    return NULL;
}
static const char* arm_call_target(ArmGen* g, ASTNode* n, char* buf, size_t cap,
                                   bool diagnose) {
    if (arm_call_is_method(n)) {
        ASTNode* member=n->children[0]->type==AST_MEMBER_ACCESS?n->children[0]:n->children[1];
        const char* method=member->token.text;
        ASTNode* recv=member->child_count?member->children[0]:NULL;
        /* Inside a method, bare method calls and `this.method()` resolve
           against the enclosing type recorded from the implicit receiver. */
        const char* type_name=g->current_type[0]?g->current_type:NULL;
        if (recv&&(recv->type==AST_IDENTIFIER_EXPR||recv->type==NODE_IDENT)) {
            Sym* s=arm_find_sym(g,recv->token.text);
            if (s&&s->type_name&&*s->type_name) type_name=s->type_name;
        }
        const char* found=arm_find_method_symbol(g,type_name,method);
        if (found) {
            snprintf(buf,cap,"%s",found);
            return buf;
        }
        /* Explicit `P p;` declarations can lose their type name in the AST;
           fall back to a unique Type_method symbol. */
        char suffix[256];
        snprintf(suffix,sizeof(suffix),"_%s",method?method:"");
        const char* fallback=NULL; int matches=0;
        for (int i=0;i<g->func_count;i++) {
            const char* fn=g->funcs[i].name;
            if (!fn) continue;
            size_t fl=strlen(fn), sl=strlen(suffix);
            if (fl>sl && !strcmp(fn+fl-sl,suffix)) { fallback=fn; matches++; }
        }
        if (matches==1) return fallback;
        if (diagnose) {
            fprintf(stderr,
                    "[arm64] ambiguous method '%s': receiver type %s; %d candidates; "
                    "use an explicitly typed receiver, `this`, or rename the method\n",
                    method?method:"?", type_name?type_name:"(unknown)", matches);
            g->abi_error=true;
        }
        return method?method:"";
    }
    if (n&&n->child_count>0&&n->children[0]->token.text) return n->children[0]->token.text;
    return "";
}
static Func* arm_find_func(ArmGen* g, const char* name) {
    if (!name) return NULL;
    for (int i=0;i<g->func_count;i++)
        if (g->funcs[i].name && !strcmp(g->funcs[i].name,name)) return &g->funcs[i];
    return NULL;
}
static int arm_call_ret_size(ArmGen* g, const char* name) {
    Func* f=arm_find_func(g,name);
    return f?f->ret_size:0;
}
static int arm_enter_scope(ArmGen* g) {
    if (g->scope_depth >= ARM_MAX_SYMS) return g->local_count;
    g->scope_stack[g->scope_depth++] = g->local_count;
    return g->local_count;
}
static void arm_leave_scope(ArmGen* g, int base) {
    while (g->local_count > base) free_sym(&g->locals[--g->local_count]);
    if (g->scope_depth > 0) g->scope_depth--;
}
static int arm_alloc_local(ArmGen* g, int size) {
    if (size<=0) size=8;
    int aligned = (size+7)&~7;
    /* Grow downwards: the new block's high edge meets the previous low edge. */
    int off = -(ARM_LOCAL_BASE + g->local_bytes + aligned - 8);
    g->local_bytes += aligned;
    return off;
}
static void arm_emit_addr(ArmGen* g, int rd, int rn, int offset) {
    if (offset>=0) a64_add_imm(&g->code,rd,rn,(uint32_t)offset);
    else a64_sub_imm(&g->code,rd,rn,(uint32_t)(-offset));
}

/* ------------------------------------------------------------------ */
/* Labels / relocations / strings                                     */
/* ------------------------------------------------------------------ */
static void arm_add_label(ArmGen* g, const char* name, size_t pos) {
    if (!name || g->label_count>=ARM_MAX_LABELS) return;
    for (int i=0;i<g->label_count;i++)
        if (!strcmp(g->labels[i].name,name)) { g->labels[i].pos=pos; return; }
    Label* l=&g->labels[g->label_count++];
    l->name=strdup(name); l->pos=pos;
}
static size_t arm_find_label(ArmGen* g, const char* name, bool* found) {
    for (int i=0;i<g->label_count;i++)
        if (!strcmp(g->labels[i].name,name)) { if(found)*found=true; return g->labels[i].pos; }
    for (int i=0;i<g->func_count;i++)
        if (!strcmp(g->funcs[i].name,name)) { if(found)*found=true; return g->funcs[i].offset; }
    if(found)*found=false; return 0;
}

static bool arm_is_func_name(ArmGen* g, const char* name) {
    for (int i = 0; i < g->func_count; i++)
        if (!strcmp(g->funcs[i].name, name)) return true;
    return false;
}

/* Labels appended after code emission (mutable globals and string literals)
   are not yet in the label table when standalone stubs are generated. */
static bool arm_is_late_label(ArmGen* g, const char* name) {
    if (!name) return false;
    if (!strncmp(name, "__mg_data_", 10) ||
        !strncmp(name, "__mg_str_", 9)) return true;
    for (int i = 0; i < g->string_count; i++)
        if (g->strings[i].name && !strcmp(g->strings[i].name, name)) return true;
    return false;
}

static bool arm_has_label(ArmGen* g, const char* name) {
    if (!name) return false;
    for (int i = 0; i < g->label_count; i++)
        if (!strcmp(g->labels[i].name, name)) return true;
    return false;
}

/* Local labels (string literals, runtime helpers, compiler temporaries) must
   be unique across MAGO objects.  Public function names stay global so the
   linker can resolve calls between objects. */
static char* arm_export_name(ArmGen* g, const char* name) {
    if (!name || !*name) return strdup("");
    if (!g->obj_prefix[0] || arm_is_func_name(g, name)) return strdup(name);
    size_t n = strlen(g->obj_prefix) + strlen(name) + 1;
    char* out = (char*)malloc(n);
    if (out) snprintf(out, n, "%s%s", g->obj_prefix, name);
    return out;
}
static void arm_add_reloc(ArmGen* g, const char* name, size_t pos, RelocType type) {
    if (!name||g->reloc_count>=ARM_MAX_RELOCS) return;
    Reloc* r=&g->relocs[g->reloc_count++];
    r->name=strdup(name); r->pos=pos; r->type=type;
}
static int arm_add_string(ArmGen* g, const uint8_t* bytes, size_t len) {
    for (int i=0;i<g->string_count;i++)
        if (g->strings[i].len==len && !memcmp(g->strings[i].bytes,bytes,len)) return i;
    if (g->string_count>=ARM_MAX_STRINGS) return 0;
    Str* s=&g->strings[g->string_count];
    s->name=(char*)malloc(24);
    snprintf(s->name,24,".Lstr%d",g->string_count);
    s->bytes=(uint8_t*)malloc(len+1);
    if(len) memcpy(s->bytes,bytes,len);
    s->bytes[len]=0; s->len=len; s->offset=0; s->addr=0;
    arm_add_label(g,s->name,0);
    return g->string_count++;
}
static size_t arm_emit_string_addr(ArmGen* g, const char* text) {
    int idx = arm_add_string(g,(const uint8_t*)text,strlen(text));
    size_t pos = a64_size(&g->code);
    a64_mov_imm(&g->code,0,0);
    arm_add_reloc(g,g->strings[idx].name,pos,RELOC_ADDR);
    return pos;
}
static void arm_print_literal(ArmGen* g, const char* text, int fd) {
    arm_emit_string_addr(g,text);
    a64_mov_imm(&g->code,1,(uint64_t)fd);
    a64_mov_imm(&g->code,8,64);
    a64_svc(&g->code);
}

static void arm_add_data_reloc(ArmGen* g, size_t offset, const char* name) {
    if(!name||g->data_reloc_count>=ARM_MAX_RELOCS) return;
    DataReloc* r=&g->data_relocs[g->data_reloc_count++];
    r->offset=offset; r->name=strdup(name);
}

/* Static initializer encoding, mirroring the runtime `any` box layout:
   [payload:64][tag:64].  String payloads are absolute pointers and need a
   relocation once the string table has been laid out. */
#define ANY_TAG_INT    0
#define ANY_TAG_FLOAT  1
#define ANY_TAG_STRING 2
#define ANY_TAG_BOOL   3
#define ANY_TAG_CHAR   4
#define ANY_TAG_PTR    5
static int arm_data_tag(ASTNode* n) {
    if(!n) return ANY_TAG_INT;
    if(n->type==AST_CAST_EXPR && (int)n->int_value==T_ANY && n->child_count>0)
        return arm_data_tag(n->children[0]);
    switch(n->type) {
        case NODE_FLOAT_LIT: case NODE_NAN_LIT: case NODE_INF_LIT: return ANY_TAG_FLOAT;
        case NODE_BOOL_LIT: return ANY_TAG_BOOL;
        case NODE_CHAR_LIT: return ANY_TAG_CHAR;
        case NODE_STRING: return ANY_TAG_STRING;
        case AST_LITERAL_EXPR:
            if(n->token.type==TOK_STRING_LITERAL) return ANY_TAG_STRING;
            if(n->token.type==TOK_FLOAT_LITERAL) return ANY_TAG_FLOAT;
            if(n->token.type==TOK_CHAR_LITERAL) return ANY_TAG_CHAR;
            if(n->token.type==TOK_KW_TRUE||n->token.type==TOK_KW_FALSE) return ANY_TAG_BOOL;
            return ANY_TAG_INT;
        default: return ANY_TAG_INT;
    }
}

static void arm_put_data_slot(ArmGen* g, int elem_tok, ASTNode* init) {
    size_t off=g->data.len;
    const char* str=NULL;
    bool is_string=(elem_tok==T_STRING);
    if(init) {
        if(init->type==AST_LITERAL_EXPR && init->token.type==TOK_STRING_LITERAL)
            str=init->string_value?init->string_value:"";
        else if(init->type==NODE_STRING) str=init->string_value?init->string_value:"";
    }
    uint64_t payload=0;
    if(str&&(is_string||elem_tok==T_ANY)) {
        int idx=arm_add_string(g,(const uint8_t*)str,strlen(str));
        arm_add_data_reloc(g,off,g->strings[idx].name);
    } else if(init) {
        switch(init->type) {
            case NODE_FLOAT_LIT: case NODE_NAN_LIT: case NODE_INF_LIT: {
                float v=(float)init->float_value; uint32_t bits;
                memcpy(&bits,&v,4); payload=bits; break;
            }
            case AST_LITERAL_EXPR:
                if(init->token.type==TOK_FLOAT_LITERAL) {
                    float v=(float)init->float_value; uint32_t bits;
                    memcpy(&bits,&v,4); payload=bits;
                } else if(init->token.type==TOK_CHAR_LITERAL)
                    payload=(uint64_t)(unsigned char)init->int_value;
                else if(init->token.type==TOK_KW_TRUE||init->token.type==TOK_KW_FALSE)
                    payload=init->token.type==TOK_KW_TRUE?1:0;
                else payload=(uint64_t)init->int_value;
                break;
            case NODE_BOOL_LIT: payload=init->bool_value?1:0; break;
            case NODE_CHAR_LIT: payload=(uint64_t)(unsigned char)init->char_value; break;
            default: payload=(uint64_t)init->int_value; break;
        }
    }
    if(elem_tok==T_ANY) {
        uint64_t be64; put64((uint8_t*)&be64,payload);
        bb_put(&g->data,(const uint8_t*)&be64,8);
        uint64_t tag=(uint64_t)arm_data_tag(init);
        put64((uint8_t*)&be64,tag);
        bb_put(&g->data,(const uint8_t*)&be64,8);
        return;
    }
    int width=elem_tok==T_CHAR||elem_tok==T_BYTE||elem_tok==T_BOOL ? 1
             : (elem_tok==T_WORD ? 2
             : ((elem_tok==T_FLOAT||elem_tok==T_HALF||elem_tok==T_DWORD) ? 4 : 8));
    uint8_t tmp[8]; memset(tmp,0,sizeof(tmp));
    for(int i=0;i<width;i++) tmp[i]=(uint8_t)(payload>>(i*8));
    bb_put(&g->data,tmp,(size_t)width);
}

/* ------------------------------------------------------------------ */
/* Function collection                                                */
/* ------------------------------------------------------------------ */
static ValueKind func_ret_kind(ASTNode* n) { return kind_from_token((n->int_value>>8)&0xFF); }

static void arm_scan_struct_size(ASTNode* n, const char* var, int* max_size) {
    if (!n) return;
    if (n->type==AST_MEMBER_ACCESS && n->child_count>0) {
        ASTNode* base=n->children[0];
        if (base && (base->type==AST_IDENTIFIER_EXPR||base->type==NODE_IDENT) &&
            base->token.text && !strcmp(base->token.text,var) && n->token.text) {
            for (int i=0;i<struct_type_count;i++) {
                StructField* f=find_field(&struct_types[i],n->token.text);
                if (f) {
                    int end=f->offset+elem_size_from_token(f->field_type);
                    if (end>*max_size) *max_size=end;
                }
            }
        }
    }
    for (int i=0;i<n->child_count;i++) arm_scan_struct_size(n->children[i],var,max_size);
}
static int arm_infer_struct_size(ArmGen* g, const char* var) {
    int max=0;
    arm_scan_struct_size(g->program,var,&max);
    return max;
}
static ASTNode* arm_find_func_node(ASTNode* n, const char* name) {
    if (!n||!name) return NULL;
    if (n->type==AST_FUNC_DECL && n->token.text && !strcmp(n->token.text,name)) return n;
    for (int i=0;i<n->child_count;i++) {
        ASTNode* r=arm_find_func_node(n->children[i],name);
        if (r) return r;
    }
    return NULL;
}
static void arm_collect_funcs(ArmGen* g, ASTNode* n) {
    if (!n) return;
    if (n->type==AST_FUNC_DECL) {
        for (int i=0;i<g->func_count;i++)
            if (n->token.text && !strcmp(g->funcs[i].name,n->token.text)) return;
        if (g->func_count<ARM_MAX_FUNCS) {
            Func* f=&g->funcs[g->func_count++];
            memset(f,0,sizeof(*f));
            f->name = n->token.text ? strdup(n->token.text) : strdup("unknown");
            f->ret_kind = func_ret_kind(n);
            f->is_extern = (n->int_value&0xFF)==1;
            if (f->ret_kind==VK_ANY) f->ret_size=16;
            if (n->string_value) {
                StructType* rst=lookup_struct(n->string_value);
                if (rst) {
                    f->ret_kind=VK_STRUCT;
                    f->ret_type_name=strdup(n->string_value);
                    f->ret_size=(rst->size+7)&~7;
                }
            }
        }
        return;
    }
    for (int i=0;i<n->child_count;i++) arm_collect_funcs(g,n->children[i]);
}
static void arm_register_global_data(ArmGen* g, ASTNode* n) {
    if (!n) return;
    if (n->type==AST_VAR_DECL && (n->bool_value||n->is_volatile) && n->token.text) {
        bool exists=false;
        for (int i=0;i<g->global_count;i++)
            if (g->globals[i].name && !strcmp(g->globals[i].name,n->token.text)) exists=true;
        if (!exists && g->global_count<ARM_MAX_GLOBALS) {
            int tok=(int)n->int_value;
            /* The parser emits TOK_KW_FIXED for fixed<T,N>; in this backend's
               local token enum that value is named T_ARRAY. */
            bool is_fixed=(tok==T_ARRAY);
            int elem_tok=is_fixed?(int)(unsigned char)n->char_value:tok;
            int slot=is_fixed?arm_array_slot_size(elem_tok)
                             :(tok==T_ANY?16:elem_size_from_token(tok));
            if(slot<=0) slot=8;
            int len=is_fixed&&n->child_count>0?n->children[0]->int_value:1;
            if(len<=0) len=1;
            ASTNode* init=NULL;
            ASTNode* values=NULL;
            if(is_fixed) {
                if(n->child_count>1) { init=n->children[0]; values=n->children[1]; }
            } else if(n->child_count>0) init=n->children[0];

            while(g->data.len%8) { uint8_t zero=0; bb_put(&g->data,&zero,1); }
            Sym* s=&g->globals[g->global_count++];
            memset(s,0,sizeof(*s));
            s->name=strdup(n->token.text);
            s->type_name=n->string_value?strdup(n->string_value):NULL;
            s->kind=is_fixed?VK_ARRAY:kind_from_token(tok);
            s->elem_size=slot; s->array_len=len; s->size=slot*len;
            s->is_global_mutable=true;
            s->offset=(int)g->data.len;

            if(is_fixed&&values&&values->type==AST_STRUCT_LITERAL) {
                for(int i=0;i<len;i++)
                    arm_put_data_slot(g,elem_tok,
                                      i<values->child_count?values->children[i]:NULL);
            } else {
                for(int i=0;i<len;i++) arm_put_data_slot(g,elem_tok,i==0?init:NULL);
            }
        }
    }
    for (int i=0;i<n->child_count;i++) arm_register_global_data(g,n->children[i]);
}
static void arm_register_globals(ArmGen* g, ASTNode* n) {
    if (!n) return;
    if (n->type==AST_VAR_DECL && n->token.text && !n->bool_value && !n->is_volatile && g->global_count<ARM_MAX_GLOBALS) {
        Sym* s=&g->globals[g->global_count++];
        memset(s,0,sizeof(*s));
        s->name=strdup(n->token.text);
        s->type_name=n->string_value?strdup(n->string_value):NULL;
        s->kind=kind_from_token((int)n->int_value);
        s->size=8; s->elem_size=8;
        s->is_global_const=true;
        if (n->child_count>0) {
            ASTNode* init=n->children[0];
            if (init->type==AST_LITERAL_EXPR||init->type==NODE_NUMBER) s->const_value=init->int_value;
            else if (init->type==NODE_BOOL_LIT) s->const_value=init->bool_value?1:0;
            else if (init->type==NODE_CHAR_LIT) s->const_value=(unsigned char)init->char_value;
        }
    }
    for (int i=0;i<n->child_count;i++) {
        if (n->children[i]->type==AST_FUNC_DECL||n->children[i]->type==AST_STRUCT_DECL||
            n->children[i]->type==AST_CLASS_DECL||n->children[i]->type==NODE_CLASS_DECL) continue;
        arm_register_globals(g,n->children[i]);
    }
    arm_register_global_data(g,n);
}

/* ------------------------------------------------------------------ */
/* Type inference                                                     */
/* ------------------------------------------------------------------ */
static ValueKind arm_expr_kind(ArmGen* g, ASTNode* n);
static bool arm_is_any_expr(ArmGen* g, ASTNode* n);
static int arm_any_tag(ArmGen* g, ASTNode* n);
static int arm_expr_elem_size(ArmGen* g, ASTNode* n) {
    if (!n) return 8;
    if (n->type==AST_UNARY_EXPR && n->token.text && !strcmp(n->token.text,"*")) {
        if (n->int_value) return elem_size_from_token((int)n->int_value);
        for (int i=0;i<n->child_count;i++) {
            ASTNode* c=n->children[i];
            while (c && c->type==AST_BINARY_EXPR && c->child_count>0) c=c->children[0];
            if (c && (c->type==AST_IDENTIFIER_EXPR||c->type==NODE_IDENT)) {
                Sym* s=arm_find_sym(g,c->token.text);
                if (s && s->kind==VK_PTR && s->elem_size>0) return s->elem_size;
            }
        }
    }
    if (n->type==AST_IDENTIFIER_EXPR||n->type==NODE_IDENT) {
        Sym* s=arm_find_sym(g,n->token.text); return s?s->elem_size:8;
    }
    if (n->type==AST_CAST_EXPR) return elem_size_from_token((int)n->int_value);
    for (int i=0;i<n->child_count;i++)
        if (n->children[i]->type==AST_IDENTIFIER_EXPR||n->children[i]->type==NODE_IDENT)
            return arm_expr_elem_size(g,n->children[i]);
    return 8;
}
static bool arm_is_any_expr(ArmGen* g, ASTNode* n);
static bool arm_is_string_expr(ArmGen* g, ASTNode* n);

static int arm_any_tag(ArmGen* g, ASTNode* n) {
    if (!n) return ANY_TAG_INT;
    if (n->type==AST_CAST_EXPR && (int)n->int_value==T_ANY && n->child_count>0)
        return arm_any_tag(g,n->children[0]);
    if (arm_is_any_expr(g,n) && n->type==AST_BINARY_EXPR &&
        (n->token.type==T_EQ||n->token.type==T_NEQ||n->token.type==T_LT||
         n->token.type==T_LE||n->token.type==T_GT||n->token.type==T_GE))
        return ANY_TAG_INT;
    switch (arm_expr_kind(g,n)) {
        case VK_FLOAT:  return ANY_TAG_FLOAT;
        case VK_STRING: return ANY_TAG_STRING;
        case VK_BOOL:   return ANY_TAG_BOOL;
        case VK_CHAR:   return ANY_TAG_CHAR;
        case VK_PTR:    return ANY_TAG_PTR;
        default:        return ANY_TAG_INT;
    }
}

static ValueKind arm_expr_kind(ArmGen* g, ASTNode* n) {
    if (!n) return VK_INT;
    switch (n->type) {
        case NODE_FLOAT_LIT: case NODE_NAN_LIT: case NODE_INF_LIT: return VK_FLOAT;
        case NODE_BOOL_LIT: return VK_BOOL;
        case NODE_CHAR_LIT: return VK_CHAR;
        case NODE_NUMBER: return VK_INT;
        case AST_LITERAL_EXPR:
            if (n->token.type==TOK_STRING_LITERAL) return VK_STRING;
            if (n->token.type==TOK_CHAR_LITERAL) return VK_CHAR;
            if (n->token.type==TOK_FLOAT_LITERAL) return VK_FLOAT;
            if (n->token.type==TOK_KW_TRUE||n->token.type==TOK_KW_FALSE) return VK_BOOL;
            return VK_INT;
        case AST_IDENTIFIER_EXPR: case NODE_IDENT: {
            const char* nm=n->token.text?n->token.text:"";
            if (!strcmp(nm,"nan")||!strcmp(nm,"inf")) return VK_FLOAT;
            if (!strcmp(nm,"true")||!strcmp(nm,"false")) return VK_BOOL;
            Sym* s=arm_find_sym(g,nm); if(s) return s->kind;
            StructField* f=arm_this_field(g,nm);
            if(f) return f->array_size>0?VK_ARRAY:kind_from_token(f->field_type);
            return VK_INT;
        }
        case AST_BINARY_EXPR:
            if (n->token.type==TOK_ASSIGN)
                return n->child_count?arm_expr_kind(g,n->children[0]):VK_INT;
            if (n->token.type==TOK_PLUS && arm_is_string_expr(g,n)) return VK_STRING;
            if (n->token.type>=T_EQ && n->token.type<=T_OR) {
                if (arm_is_any_expr(g,n->child_count>0?n->children[0]:NULL) ||
                    arm_is_any_expr(g,n->child_count>1?n->children[1]:NULL)) return VK_ANY;
                return VK_INT;
            }
            if (arm_is_any_expr(g,n->child_count>0?n->children[0]:NULL) ||
                arm_is_any_expr(g,n->child_count>1?n->children[1]:NULL)) return VK_ANY;
            if (n->child_count>=1 && arm_expr_kind(g,n->children[0])==VK_FLOAT) return VK_FLOAT;
            if (n->child_count>=2 && arm_expr_kind(g,n->children[1])==VK_FLOAT) return VK_FLOAT;
            return VK_INT;
        case AST_UNARY_EXPR: {
            const char* op=n->token.text?n->token.text:"";
            if (!strcmp(op,"&")) return VK_PTR;
            if (!strcmp(op,"*")) {
                /* Pointer dereference nodes carry the pointee type in int_value. */
                if (n->int_value) return kind_from_token((int)n->int_value);
                if (n->child_count>0) {
                    ASTNode* c=n->children[0];
                    while (c && c->type==AST_BINARY_EXPR && c->child_count>0) c=c->children[0];
                    if (c && (c->type==AST_IDENTIFIER_EXPR||c->type==NODE_IDENT)) {
                        Sym* s=arm_find_sym(g,c->token.text);
                        if (s && s->kind==VK_PTR) {
                            if (s->elem_size==1) return VK_CHAR;
                            if (s->elem_size==4) return VK_FLOAT;
                            return VK_INT;
                        }
                    }
                    ValueKind inner=arm_expr_kind(g,n->children[0]);
                    if (inner==VK_ARRAY||inner==VK_PTR) {
                        int es=arm_expr_elem_size(g,n->children[0]);
                        if (es==16) return VK_ANY;
                        if (es==4) return VK_FLOAT;
                        return es==1?VK_CHAR:VK_INT;
                    }
                }
                return VK_INT;
            }
            if (n->child_count>0) return arm_expr_kind(g,n->children[0]);
            return VK_INT;
        }
        case AST_CAST_EXPR: return kind_from_token((int)n->int_value);
        case AST_MEMBER_ACCESS: {
            StructField* f = n->child_count ? arm_var_field(g,n->children[0],n->token.text) : NULL;
            if (!f) return VK_INT;
            if (f->array_size>0) return VK_ARRAY;
            return kind_from_token(f->field_type);
        }
        case AST_ALLOC_EXPR: case AST_NEW_EXPR: return VK_PTR;
        case AST_TERNARY_EXPR:
            return n->child_count>1?arm_expr_kind(g,n->children[1]):VK_INT;
        case AST_CALL_EXPR: {
            if (n->child_count<1) return VK_INT;
            char tbuf[256];
            const char* nm=arm_call_target(g,n,tbuf,sizeof(tbuf),false);
            if (!strcmp(nm,"sqrt")||!strcmp(nm,"sin")||!strcmp(nm,"cos")) return VK_FLOAT;
            if (!strcmp(nm,"len")||!strcmp(nm,"str_compare")) return VK_INT;
            for (int i=0;i<g->func_count;i++)
                if (!strcmp(g->funcs[i].name,nm)) {
                    ValueKind rk=g->funcs[i].ret_kind;
                    /* A call result is always an integer value at print time,
                       even when the function is declared -> bool. */
                    return rk==VK_BOOL?VK_INT:rk;
                }
            return VK_INT;
        }
        default: return VK_INT;
    }
}
#define arm_is_float(g,n) (arm_expr_kind((g),(n))==VK_FLOAT)

/* True when an expression carries a runtime tag alongside its payload. */
static bool arm_is_any_expr(ArmGen* g, ASTNode* n) {
    if (!n) return false;
    if (arm_expr_kind(g,n)==VK_ANY) return true;
    if (n->type==AST_CAST_EXPR && (int)n->int_value==T_ANY) return true;
    if (n->type==AST_BINARY_EXPR && n->token.type!=TOK_ASSIGN &&
        !(n->token.type>=TOK_PLUS_ASSIGN&&n->token.type<=TOK_XOR_ASSIGN))
        return arm_is_any_expr(g,n->child_count>0?n->children[0]:NULL) ||
               arm_is_any_expr(g,n->child_count>1?n->children[1]:NULL);
    return false;
}

static bool arm_is_string_expr(ArmGen* g, ASTNode* n) {
    if (!n) return false;
    if (n->type==AST_LITERAL_EXPR && n->token.type==TOK_STRING_LITERAL) return true;
    if (n->type==AST_IDENTIFIER_EXPR||n->type==NODE_IDENT) {
        Sym* s=arm_find_sym(g,n->token.text);
        if (s&&s->kind==VK_STRING) return true;
    }
    if (n->type==AST_UNARY_EXPR && n->token.type==TOK_STAR &&
        (int)n->int_value==T_STRING) return true;
    if (n->type==AST_MEMBER_ACCESS) {
        StructField* f=n->child_count?arm_var_field(g,n->children[0],n->token.text):NULL;
        if (f && f->array_size==0 && f->field_type==T_STRING) return true;
    }
    if (n->type==AST_CAST_EXPR && (int)n->int_value==T_STRING) return true;
    if (n->type==AST_TERNARY_EXPR)
        return n->child_count>2 && arm_is_string_expr(g,n->children[1]) &&
               arm_is_string_expr(g,n->children[2]);
    if (n->type==AST_BINARY_EXPR && n->token.type==TOK_PLUS &&
        n->child_count>=2 && arm_is_string_expr(g,n->children[0]) &&
        arm_is_string_expr(g,n->children[1])) return true;
    return false;
}

/* ------------------------------------------------------------------ */
/* Load/store helpers                                                 */
/* ------------------------------------------------------------------ */
static void arm_emit_global_addr(ArmGen* g, int rd, Sym* s) {
    char name[128];
    snprintf(name,sizeof(name),"__mg_data_%s",s->name?s->name:"anon");
    size_t pos=a64_size(&g->code);
    a64_mov_imm(&g->code,rd,0);
    arm_add_reloc(g,name,pos,RELOC_ADDR);
}
static void arm_load_sym(ArmGen* g, int rd, Sym* s) {
    if (!s) { a64_mov_imm(&g->code,rd,0); return; }
    if (s->is_global_const) { a64_mov_imm(&g->code,rd,(uint64_t)s->const_value); return; }
    if (s->is_global_mutable) {
        arm_emit_global_addr(g,9,s);
        a64_ldr_x(&g->code,rd,9,0);
        return;
    }
    arm_emit_addr(g,9,29,s->offset);
    a64_ldr_x(&g->code,rd,9,0);
}
static void arm_store_sym(ArmGen* g, Sym* s, int rs) {
    if (!s||s->is_global_const) return;
    if (s->is_global_mutable) {
        arm_emit_global_addr(g,9,s);
        a64_str_x(&g->code,rs,9,0);
        return;
    }
    arm_emit_addr(g,9,29,s->offset);
    a64_str_x(&g->code,rs,9,0);
}
static int arm_save_scratch(ArmGen* g, int reg) {
    int idx=g->scratch_depth++;
    if(idx>=ARM_SCRATCH_SLOTS) {
        fprintf(stderr,"[arm64] scratch spill limit exceeded (>%d nested temporaries)\n",
                ARM_SCRATCH_SLOTS);
        g->abi_error=true;
        idx=ARM_SCRATCH_SLOTS-1;
    }
    arm_emit_addr(g,9,29,-(8+idx*8));
    a64_str_x(&g->code,reg,9,0);
    return idx;
}
static void arm_load_scratch(ArmGen* g,int reg,int idx) {
    arm_emit_addr(g,9,29,-(8+idx*8));
    a64_ldr_x(&g->code,reg,9,0);
}
static void arm_release_scratch(ArmGen* g,int idx) {
    /* Scratch slots are released LIFO: slot idx is the new high-water mark. */
    if(idx<g->scratch_depth) g->scratch_depth=idx;
}
static void arm_load_value(ArmGen* g,int base,int rd,int size) {
    if(size<=1) a64_ldrb(&g->code,rd,base,0);
    else if(size==4) a64_ldr_w(&g->code,rd,base,0);
    else a64_ldr_x(&g->code,rd,base,0);
}
static void arm_store_value(ArmGen* g,int base,int rs,int size) {
    if(size<=1) a64_strb(&g->code,rs,base,0);
    else if(size==4) a64_str_w(&g->code,rs,base,0);
    else a64_str_x(&g->code,rs,base,0);
}

/* ------------------------------------------------------------------ */
/* Expressions                                                        */
/* ------------------------------------------------------------------ */
static void arm_expr(ArmGen* g, ASTNode* n);
static void arm_stmt(ArmGen* g, ASTNode* n);
static void arm_run_block(ArmGen* g, ASTNode* n) {
    if (!n) return;
    int base=arm_enter_scope(g);
    for(int i=0;i<n->child_count;i++) arm_stmt(g,n->children[i]);
    arm_leave_scope(g,base);
}

/* ------------------------------------------------------------------ */
/* Real process-based tasks (spawn / async / parallel / await)        */
/* ------------------------------------------------------------------ */
static Sym* arm_find_global(ArmGen* g, const char* name) {
    for (int i=0;i<g->global_count;i++)
        if (g->globals[i].name && !strcmp(g->globals[i].name,name))
            return &g->globals[i];
    return NULL;
}
static Sym* arm_add_task_global(ArmGen* g, const char* name, int size) {
    Sym* s=arm_find_global(g,name);
    if (s) return s;
    if (g->global_count>=ARM_MAX_GLOBALS) return NULL;
    s=&g->globals[g->global_count++];
    memset(s,0,sizeof(*s));
    s->name=strdup(name);
    s->kind=VK_INT; s->elem_size=8; s->size=size;
    s->is_global_mutable=true;
    s->offset=(int)g->data.len;
    uint8_t* zeros=(uint8_t*)calloc((size_t)size,1);
    bb_put(&g->data,zeros,(size_t)size);
    free(zeros);
    return s;
}
static void arm_ensure_task_statics(ArmGen* g) {
    if (g->task_statics) return;
    g->task_statics=true;
    arm_add_task_global(g,"task_pipes",256*24);
    arm_add_task_global(g,"task_wfd",8);
}
/* pipe2 + clone(SIGCHLD): the child runs the block and exits; the parent
   records pid -> read-fd in task_pipes and leaves the pid in x0. */
static void arm_task_fork(ArmGen* g, ASTNode* block) {
    arm_ensure_task_statics(g);
    Sym* pipes=arm_find_global(g,"task_pipes");
    Sym* wfd=arm_find_global(g,"task_wfd");
    int fds_off=arm_alloc_local(g,8);
    int save_off=arm_alloc_local(g,8);

    arm_emit_addr(g,0,29,fds_off);
    a64_mov_imm(&g->code,1,0);
    a64_mov_imm(&g->code,8,59);   /* pipe2 */
    a64_svc(&g->code);

    a64_mov_imm(&g->code,0,17);   /* SIGCHLD -> fork-like clone on AArch64 */
    a64_mov_imm(&g->code,1,0);
    a64_mov_imm(&g->code,2,0);
    a64_mov_imm(&g->code,3,0);
    a64_mov_imm(&g->code,4,0);
    a64_mov_imm(&g->code,8,220);  /* clone */
    a64_svc(&g->code);
    arm_emit_addr(g,9,29,save_off);
    a64_str_x(&g->code,0,9,0);
    a64_cmp_imm(&g->code,0,0);
    size_t parent=a64_bcond(&g->code,A64_NE);

    /* Child: close read end, publish write end, run the block, exit(0). */
    arm_emit_addr(g,9,29,fds_off);
    a64_ldr_x(&g->code,0,9,0);
    a64_mov_imm(&g->code,8,57);   /* close */
    a64_svc(&g->code);
    if (wfd) {
        arm_emit_global_addr(g,9,wfd);
        arm_emit_addr(g,10,29,fds_off);
        a64_ldr_x(&g->code,11,10,8);
        a64_str_x(&g->code,11,9,0);
    }
    if (block) arm_run_block(g,block);
    a64_mov_imm(&g->code,0,0);
    a64_mov_imm(&g->code,8,93);   /* exit */
    a64_svc(&g->code);

    size_t parent_here=a64_size(&g->code);
    a64_patch_cond(g->code.data,parent,parent_here);

    /* Parent: save pid/read-fd, close write end, leave pid in x0. */
    arm_emit_addr(g,9,29,save_off);
    a64_ldr_x(&g->code,10,9,0);
    if (pipes) {
        arm_emit_global_addr(g,9,pipes);
        a64_mov_imm(&g->code,11,255);
        a64_and_reg(&g->code,11,10,11);
        a64_mov_imm(&g->code,12,24);
        a64_mul(&g->code,11,11,12);
        a64_add_reg(&g->code,9,9,11);
        a64_str_x(&g->code,10,9,0);
        arm_emit_addr(g,11,29,fds_off);
        a64_ldr_x(&g->code,12,11,0);
        a64_str_x(&g->code,12,9,8);
    }
    arm_emit_addr(g,11,29,fds_off);
    a64_ldr_x(&g->code,0,11,8);
    a64_mov_imm(&g->code,8,57);   /* close */
    a64_svc(&g->code);
    arm_emit_addr(g,9,29,save_off);
    a64_ldr_x(&g->code,0,9,0);
}
/* wait4 + pipe read: returns the child's yielded 64-bit value, the exit
   status, or -1 when no child could be waited for. */
static void arm_task_join(ArmGen* g, bool wait_any) {
    arm_ensure_task_statics(g);
    Sym* pipes=arm_find_global(g,"task_pipes");
    int status_off=arm_alloc_local(g,8);
    int buf_off=arm_alloc_local(g,8);
    int pid_off=arm_alloc_local(g,8);

    if (wait_any) a64_mov_imm(&g->code,0,(uint64_t)-1);
    arm_emit_addr(g,9,29,pid_off);
    a64_str_x(&g->code,0,9,0);

    arm_emit_addr(g,1,29,status_off);
    a64_mov_imm(&g->code,2,0);
    a64_mov_imm(&g->code,3,0);
    a64_mov_imm(&g->code,8,260);  /* wait4 */
    a64_svc(&g->code);
    arm_emit_addr(g,9,29,pid_off);
    a64_str_x(&g->code,0,9,0);
    a64_mov_imm(&g->code,10,0);
    a64_cmp_reg(&g->code,0,10);
    size_t fail=a64_bcond(&g->code,A64_LT);   /* -ECHILD, not just -1 */

    size_t nopipe1=0,nopipe2=0,nopipe3=0;
    if (pipes) {
        arm_emit_global_addr(g,9,pipes);
        arm_emit_addr(g,10,29,pid_off);
        a64_ldr_x(&g->code,10,10,0);
        a64_mov_imm(&g->code,11,255);
        a64_and_reg(&g->code,11,10,11);
        a64_mov_imm(&g->code,12,24);
        a64_mul(&g->code,11,11,12);
        a64_add_reg(&g->code,9,9,11);
        a64_ldr_x(&g->code,13,9,0);
        a64_cmp_reg(&g->code,13,10);
        nopipe1=a64_bcond(&g->code,A64_NE);
        a64_ldr_x(&g->code,14,9,8);
        a64_cmp_imm(&g->code,14,0);
        nopipe2=a64_bcond(&g->code,A64_LT);
        arm_emit_addr(g,0,29,buf_off);
        a64_mov_reg(&g->code,1,14);
        a64_mov_imm(&g->code,2,8);
        a64_mov_imm(&g->code,8,63);   /* read */
        a64_svc(&g->code);
        a64_cmp_imm(&g->code,0,8);
        nopipe3=a64_bcond(&g->code,A64_NE);
        arm_emit_addr(g,9,29,buf_off);
        a64_ldr_x(&g->code,0,9,0);
    }
    size_t done=a64_b(&g->code);

    if (pipes) {
        a64_patch_cond(g->code.data,nopipe1,a64_size(&g->code));
        a64_patch_cond(g->code.data,nopipe2,a64_size(&g->code));
        a64_patch_cond(g->code.data,nopipe3,a64_size(&g->code));
    }
    arm_emit_addr(g,9,29,status_off);
    a64_ldr_x(&g->code,0,9,0);
    a64_lsr_imm(&g->code,0,0,8);
    a64_mov_imm(&g->code,10,255);
    a64_and_reg(&g->code,0,0,10);
    a64_patch_branch(g->code.data,done,a64_size(&g->code));
    size_t skip_fail=a64_b(&g->code);

    a64_patch_cond(g->code.data,fail,a64_size(&g->code));
    a64_mov_imm(&g->code,0,(uint64_t)-1);
    a64_patch_branch(g->code.data,skip_fail,a64_size(&g->code));
}
/* Emit a divide-by-zero trap around an integer division whose divisor is in
   x10. The helper prints to stderr and exits with status 1. */
static size_t arm_div_check(ArmGen* g) { return a64_cbz(&g->code,10); }
static void arm_div_check_end(ArmGen* g, size_t zero) {
    size_t skip=a64_b(&g->code);
    a64_patch_cb(g->code.data,zero,a64_size(&g->code));
    arm_add_reloc(g,"mag_divzero",a64_bl(&g->code),RELOC_BRANCH);
    a64_patch_branch(g->code.data,skip,a64_size(&g->code));
}

static void arm_addr(ArmGen* g, ASTNode* n) {
    if (!n) { a64_mov_imm(&g->code,0,0); return; }
    if (n->type==AST_IDENTIFIER_EXPR||n->type==NODE_IDENT||n->type==NODE_THIS||n->type==NODE_SUPER) {
        const char* name=(n->type==NODE_THIS||n->type==NODE_SUPER)?"this":n->token.text;
        Sym* s=arm_find_sym(g,name);
        if(s&&s->is_global_mutable) arm_emit_global_addr(g,0,s);
        else if(s&&!s->is_global_const&&s->kind!=VK_PTR) arm_emit_addr(g,0,29,s->offset);
        else {
            StructField* f=arm_this_field(g,name);
            if(f) arm_emit_this_field_addr(g,0,f);
            else arm_expr(g,n);
        }
        return;
    }
    if (n->type==AST_MEMBER_ACCESS && n->child_count>0) {
        arm_addr(g,n->children[0]);
        arm_emit_addr(g,0,0,arm_field_offset(g,n->children[0],n->token.text));
        return;
    }
    if (n->type==AST_UNARY_EXPR&&n->token.type==TOK_STAR&&n->child_count>0) {
        arm_expr(g,n->children[0]); return;
    }
    arm_expr(g,n);
}
static void arm_float_bits(ArmGen* g, ASTNode* n) {
    uint32_t bits=0;
    if(n->type==NODE_NAN_LIT) bits=0x7FC00000u;
    else if(n->type==NODE_INF_LIT) bits=0x7F800000u;
    else { float v=(float)n->float_value; memcpy(&bits,&v,4); }
    a64_mov_imm(&g->code,0,bits);
}
static void arm_emit_args(ArmGen* g, ASTNode* n, int from, int max_args) {
    int arg=0;
    int slots[8];
    /* Evaluate arguments left-to-right, stashing each result in a scratch
       slot so later evaluations cannot clobber earlier argument registers. */
    for (int i=from;i<n->child_count&&arg<max_args;i++,arg++) {
        arm_expr(g,n->children[i]);
        slots[arg]=arm_save_scratch(g,0);
    }
    for(int i=arg;i<max_args;i++) a64_mov_imm(&g->code,i,0);
    /* Load into x0..x(arg-1) in reverse so releasing a slot cannot disturb
       the remaining saved values. */
    for(int i=arg-1;i>=0;i--) {
        arm_load_scratch(g,i,slots[i]);
        arm_release_scratch(g,slots[i]);
    }
}
/* Emit a direct or method call. x8 carries the hidden aggregate-result
   pointer when the caller has set one up.  The first eight GPR slots use
   x0-x7; extra slots go through a 16-byte-aligned outgoing stack area as
   required by AAPCS64. */
static void arm_emit_call(ArmGen* g, ASTNode* n, const char* target) {
    bool method=arm_call_is_method(n);
    ASTNode* recv=method && n->children[0]->child_count
                 ? n->children[0]->children[0] : NULL;
    int nslots=method ? n->child_count
                      : (n->child_count>0 ? n->child_count-1 : 0);

    if (nslots>511) {
        fprintf(stderr,"[arm64] unsupported call to '%s': %d argument slots "
                       "(AAPCS64 stack area exceeds the 12-bit frame offset limit)\n",
                target?target:"?",nslots);
        g->abi_error=true;
        nslots=511;
    }

    if (nslots<=8) {
        int slots[8];
        int arg=0;
        if (method) {
            /* Evaluate the receiver first, then every explicit argument,
               saving each into a scratch slot before evaluating the next. */
            arm_addr(g,recv);
            slots[arg++]=arm_save_scratch(g,0);
            for (int i=1;i<n->child_count&&arg<8;i++,arg++) {
                arm_expr(g,n->children[i]);
                slots[arg]=arm_save_scratch(g,0);
            }
        } else {
            for (int i=1;i<n->child_count&&arg<8;i++,arg++) {
                arm_expr(g,n->children[i]);
                slots[arg]=arm_save_scratch(g,0);
            }
        }
        for(int i=arg;i<8;i++) a64_mov_imm(&g->code,i,0);
        /* Reverse order keeps still-live scratch slots intact while loading. */
        for(int i=arg-1;i>=0;i--) {
            arm_load_scratch(g,i,slots[i]);
            arm_release_scratch(g,slots[i]);
        }
        arm_add_reloc(g,target,a64_bl(&g->code),RELOC_BRANCH);
        return;
    }

    /* AAPCS64: only slots 8..n-1 live in the caller's outgoing area, at
       [sp, #8*(i-8)] with SP 16-byte aligned at the call. */
    uint32_t stack_slots=(uint32_t)(nslots-8);
    uint32_t out=align16u(8*stack_slots);
    a64_sub_imm(&g->code,31,31,out);
    int slots[8];
    int total=0;
    if (method) {
        arm_addr(g,recv);
        slots[total++]=arm_save_scratch(g,0);
    }
    for (int i=1;i<n->child_count&&total<nslots;i++,total++) {
        arm_expr(g,n->children[i]);
        if (total<8) slots[total]=arm_save_scratch(g,0);
        else a64_str_x(&g->code,0,31,(uint32_t)(8*(total-8)));
    }
    int arg=total<8?total:8;
    for(int i=arg;i<8;i++) a64_mov_imm(&g->code,i,0);
    for(int i=arg-1;i>=0;i--) {
        arm_load_scratch(g,i,slots[i]);
        arm_release_scratch(g,slots[i]);
    }
    arm_add_reloc(g,target,a64_bl(&g->code),RELOC_BRANCH);
    a64_add_imm(&g->code,31,31,out);
}
/* Leave the address of a 16-byte tagged-any box in x0. */
static void arm_materialize_any(ArmGen* g, ASTNode* n) {
    if (!n) { a64_mov_imm(&g->code,0,0); return; }
    if (arm_expr_kind(g,n)==VK_ANY &&
        (n->type==AST_IDENTIFIER_EXPR||n->type==NODE_IDENT)) {
        arm_expr(g,n);
        return;
    }
    if (n->type==AST_CAST_EXPR && (int)n->int_value==T_ANY && n->child_count>0) {
        arm_materialize_any(g,n->children[0]);
        return;
    }
    /* Any-valued lvalues (dereferences and struct fields) already are boxes. */
    if (arm_expr_kind(g,n)==VK_ANY &&
        ((n->type==AST_UNARY_EXPR && n->token.type==TOK_STAR) ||
         n->type==AST_MEMBER_ACCESS)) {
        arm_addr(g,n);
        return;
    }
    /* Aggregates box their address, not their contents. */
    if (n->type==AST_IDENTIFIER_EXPR||n->type==NODE_IDENT) {
        Sym* s=arm_find_sym(g,n->token.text);
        if (s && (s->kind==VK_STRUCT||s->kind==VK_ARRAY)) {
            int off=arm_alloc_local(g,16);
            arm_emit_addr(g,0,29,off);
            int idx=arm_save_scratch(g,0);
            arm_emit_addr(g,0,29,s->offset);
            arm_load_scratch(g,9,idx);
            a64_str_x(&g->code,0,9,0);
            a64_mov_imm(&g->code,10,(uint64_t)ANY_TAG_PTR);
            a64_str_x(&g->code,10,9,8);
            arm_release_scratch(g,idx);
            arm_emit_addr(g,0,29,off);
            return;
        }
    }
    if (n->type==AST_BINARY_EXPR && arm_is_any_expr(g,n)) {
        arm_expr(g,n);              /* already returns a box address */
        return;
    }
    if (n->type==AST_CALL_EXPR && arm_expr_kind(g,n)==VK_ANY) {
        arm_expr(g,n);              /* sret path already returns a box address */
        return;
    }
    int off=arm_alloc_local(g,16);
    arm_emit_addr(g,0,29,off);
    int idx=arm_save_scratch(g,0);
    arm_expr(g,n);
    arm_load_scratch(g,9,idx);
    a64_str_x(&g->code,0,9,0);
    a64_mov_imm(&g->code,10,(uint64_t)arm_any_tag(g,n));
    a64_str_x(&g->code,10,9,8);
    arm_release_scratch(g,idx);
    arm_emit_addr(g,0,29,off);
}

static void arm_print_arg(ArmGen* g, ASTNode* arg) {
    ValueKind k=arm_expr_kind(g,arg);
    /* x86 reference: is_float_expr() does not recognise cast expressions,
       so cast<float> results are printed with the integer formatter using
       the original payload (conversion result stays in XMM0 there). */
    if(arg&&arg->type==AST_CAST_EXPR&&k==VK_FLOAT&&arg->child_count>0&&
       arm_is_any_expr(g,arg->children[0])) {
        arm_expr(g,arg->children[0]);   /* box address */
        a64_ldr_x(&g->code,0,0,0);      /* raw payload */
        arm_add_reloc(g,"mag_print_int",a64_bl(&g->code),RELOC_BRANCH);
        return;
    }
    if(arg&&arg->type==AST_CAST_EXPR&&k==VK_FLOAT) k=VK_INT;
    if(k==VK_ANY) {
        arm_materialize_any(g,arg);
        arm_add_reloc(g,"mag_print_any",a64_bl(&g->code),RELOC_BRANCH);
        return;
    }
    arm_expr(g,arg);
    switch(k) {
        case VK_STRING:
            arm_add_reloc(g,"mag_print_str",a64_bl(&g->code),RELOC_BRANCH); break;
        case VK_BOOL: {
            size_t p=a64_cbz(&g->code,0);
            arm_emit_string_addr(g,"true");
            size_t e=a64_b(&g->code);
            a64_patch_cb(g->code.data,p,a64_size(&g->code));
            arm_emit_string_addr(g,"false");
            a64_patch_branch(g->code.data,e,a64_size(&g->code));
            arm_add_reloc(g,"mag_print_str",a64_bl(&g->code),RELOC_BRANCH);
            break;
        }
        case VK_FLOAT:
            arm_add_reloc(g,"mag_print_float",a64_bl(&g->code),RELOC_BRANCH); break;
        default:
            arm_add_reloc(g,"mag_print_int",a64_bl(&g->code),RELOC_BRANCH); break;
    }
}
static void arm_builtin(ArmGen* g, ASTNode* n, const char* name) {
    if (!strcmp(name,"print")||!strcmp(name,"println")) {
        for(int i=1;i<n->child_count;i++) arm_print_arg(g,n->children[i]);
        if(!strcmp(name,"println")) arm_print_literal(g,"\n",1);
        return;
    }
    if (!strcmp(name,"print_info")||!strcmp(name,"print_str")) {
        for(int i=1;i<n->child_count;i++) {
            arm_expr(g,n->children[i]);
            arm_add_reloc(g,"mag_print_str",a64_bl(&g->code),RELOC_BRANCH);
        }
        return;
    }
    if (!strcmp(name,"print_error")||!strcmp(name,"eprint")) {
        for(int i=1;i<n->child_count;i++) {
            arm_expr(g,n->children[i]);
            a64_mov_imm(&g->code,1,2);
            arm_add_reloc(g,"mag_print_fd",a64_bl(&g->code),RELOC_BRANCH);
        }
        return;
    }
    if (!strcmp(name,"print_int")) {
        for(int i=1;i<n->child_count;i++) {
            arm_expr(g,n->children[i]);
            arm_add_reloc(g,"mag_print_int",a64_bl(&g->code),RELOC_BRANCH);
        }
        return;
    }
    if (!strcmp(name,"print_float")) {
        for(int i=1;i<n->child_count;i++) {
            arm_expr(g,n->children[i]);
            arm_add_reloc(g,"mag_print_float",a64_bl(&g->code),RELOC_BRANCH);
        }
        return;
    }
    if (!strcmp(name,"len")) {
        if(n->child_count>1) arm_expr(g,n->children[1]); else a64_mov_imm(&g->code,0,0);
        arm_add_reloc(g,"mag_strlen",a64_bl(&g->code),RELOC_BRANCH); return;
    }
    if (!strcmp(name,"str_equals")) {
        arm_emit_args(g,n,1,2);
        arm_add_reloc(g,"mag_strcmp",a64_bl(&g->code),RELOC_BRANCH);
        a64_cmp_imm(&g->code,0,0); a64_cset(&g->code,0,A64_EQ); return;
    }
    if (!strcmp(name,"str_compare")||!strcmp(name,"strcmp")) {
        arm_emit_args(g,n,1,2);
        arm_add_reloc(g,"mag_strcmp",a64_bl(&g->code),RELOC_BRANCH); return;
    }
    if (!strcmp(name,"exit")||!strcmp(name,"sys_exit")||!strcmp(name,"sys_exit_group")) {
        if(n->child_count>1) arm_expr(g,n->children[1]); else a64_mov_imm(&g->code,0,0);
        a64_mov_imm(&g->code,8,94); a64_svc(&g->code); return;
    }
    if (!strcmp(name,"get_timestamp")) {
        arm_add_reloc(g,"mag_get_timestamp",a64_bl(&g->code),RELOC_BRANCH); return;
    }
    if (!strcmp(name,"sleep_ms")) {
        if(n->child_count>1) arm_expr(g,n->children[1]); else a64_mov_imm(&g->code,0,0);
        arm_add_reloc(g,"mag_sleep_ms",a64_bl(&g->code),RELOC_BRANCH); return;
    }
    if (!strcmp(name,"rand_int")) {
        arm_add_reloc(g,"mag_rand",a64_bl(&g->code),RELOC_BRANCH); return;
    }
    if (!strcmp(name,"sqrt")) {
        if(n->child_count>1) arm_expr(g,n->children[1]);
        a64_fmov_s_w(&g->code,0,0); a64_fsqrt(&g->code,0,0); a64_fmov_w_s(&g->code,0,0); return;
    }
    if (!strcmp(name,"abs")) {
        if(n->child_count>1) arm_expr(g,n->children[1]);
        a64_cmp_imm(&g->code,0,0);
        size_t p=a64_bcond(&g->code,A64_GE);
        a64_sub_reg(&g->code,0,31,0);
        a64_patch_cond(g->code.data,p,a64_size(&g->code)); return;
    }
}
static void arm_expr(ArmGen* g, ASTNode* n) {
    if(!n) { a64_mov_imm(&g->code,0,0); return; }
    switch(n->type) {
        case NODE_NUMBER:
            a64_mov_imm(&g->code,0,(uint64_t)n->int_value); break;
        case NODE_FLOAT_LIT: case NODE_NAN_LIT: case NODE_INF_LIT:
            arm_float_bits(g,n); break;
        case NODE_BOOL_LIT:
            a64_mov_imm(&g->code,0,n->bool_value?1:0); break;
        case NODE_CHAR_LIT:
            a64_mov_imm(&g->code,0,(uint64_t)(unsigned char)n->char_value); break;
        case NODE_STRING:
            arm_emit_string_addr(g,n->string_value?n->string_value:""); break;
        case AST_LITERAL_EXPR:
            if(n->token.type==TOK_STRING_LITERAL)
                arm_emit_string_addr(g,n->string_value?n->string_value:"");
            else if(n->token.type==TOK_FLOAT_LITERAL) {
                float v=(float)n->float_value; uint32_t bits;
                memcpy(&bits,&v,4); a64_mov_imm(&g->code,0,bits);
            } else if(n->token.type==TOK_KW_TRUE||n->token.type==TOK_KW_FALSE)
                a64_mov_imm(&g->code,0,n->token.type==TOK_KW_TRUE?1:0);
            else if(n->token.type==TOK_CHAR_LITERAL)
                a64_mov_imm(&g->code,0,(uint64_t)(unsigned char)n->int_value);
            else a64_mov_imm(&g->code,0,(uint64_t)n->int_value);
            break;
        case AST_IDENTIFIER_EXPR: case NODE_IDENT: {
            const char* nm=n->token.text?n->token.text:"";
            if(!strcmp(nm,"nan")) { a64_mov_imm(&g->code,0,0x7FC00000ULL); break; }
            if(!strcmp(nm,"inf")) { a64_mov_imm(&g->code,0,0x7F800000ULL); break; }
            if(!strcmp(nm,"true")) { a64_mov_imm(&g->code,0,1); break; }
            if(!strcmp(nm,"false")) { a64_mov_imm(&g->code,0,0); break; }
            if(!strcmp(nm,"null")) { a64_mov_imm(&g->code,0,0); break; }
            Sym* s=arm_find_sym(g,nm);
            if(!s) {
                StructField* f=arm_this_field(g,nm);
                if(f) {
                    arm_emit_this_field_addr(g,9,f);
                    if(f->array_size>0) a64_mov_reg(&g->code,0,9);
                    else arm_load_value(g,9,0,elem_size_from_token(f->field_type));
                    break;
                }
            }
            if(s&&s->kind==VK_ARRAY) {
                if(s->is_global_mutable) arm_emit_global_addr(g,0,s);
                else if(s->is_global_const) a64_mov_imm(&g->code,0,(uint64_t)s->const_value);
                else arm_emit_addr(g,0,29,s->offset);
            }
            else if(s&&s->kind==VK_ANY) {
                if(s->is_global_const) a64_mov_imm(&g->code,0,(uint64_t)s->const_value);
                else if(s->is_global_mutable) arm_emit_global_addr(g,0,s);
                else arm_emit_addr(g,0,29,s->offset);
            }
            else arm_load_sym(g,0,s);
            break;
        }
        case NODE_THIS: case NODE_SUPER: {
            Sym* s=arm_find_sym(g,"this");
            if(s) { arm_emit_addr(g,9,29,s->offset); a64_ldr_x(&g->code,0,9,0); }
            else a64_mov_imm(&g->code,0,0);
            break;
        }
        case AST_CAST_EXPR: {
            ASTNode* ch=n->child_count?n->children[0]:NULL;
            int target=(int)n->int_value;
            if(target==T_ANY) { arm_materialize_any(g,ch); break; }
            bool from_any=arm_is_any_expr(g,ch);
            if(ch) arm_expr(g,ch); else a64_mov_imm(&g->code,0,0);
            bool to_float=(target==T_FLOAT||target==T_HALF);
            if(from_any) {
                /* Runtime tag decides conversion: tagged floats hold raw
                   IEEE bits, everything else holds an integer payload. */
                a64_ldr_x(&g->code,9,0,8);
                a64_cmp_imm(&g->code,9,ANY_TAG_FLOAT);
                size_t not_float=a64_bcond(&g->code,A64_NE);
                a64_ldr_x(&g->code,0,0,0);
                if(!to_float) {
                    a64_fmov_s_w(&g->code,0,0);
                    a64_fcvtzs(&g->code,0,0);
                }
                size_t cast_done=a64_b(&g->code);
                a64_patch_cond(g->code.data,not_float,a64_size(&g->code));
                a64_ldr_x(&g->code,0,0,0);
                if(to_float) {
                    a64_fmov_s_w(&g->code,0,0);
                    a64_scvtf(&g->code,0,0);
                    a64_fmov_w_s(&g->code,0,0);
                }
                a64_patch_branch(g->code.data,cast_done,a64_size(&g->code));
            } else {
                bool from_float=ch&&arm_is_float(g,ch);
                if(to_float) {
                    if(!from_float) {
                        a64_fmov_s_w(&g->code,0,0);
                        a64_scvtf(&g->code,0,0);
                        a64_fmov_w_s(&g->code,0,0);
                    }
                } else if(from_float) {
                    a64_fmov_s_w(&g->code,0,0);
                    a64_fcvtzs(&g->code,0,0);
                }
            }
            break;
        }
        case AST_ALLOC_EXPR: case AST_NEW_EXPR: {
            int elem=elem_size_from_token((int)n->int_value);
            if(n->string_value) elem=arm_type_size_name(n->string_value);
            if(n->child_count>0) arm_expr(g,n->children[0]); else a64_mov_imm(&g->code,0,0);
            if(elem!=1) { a64_mov_imm(&g->code,9,(uint64_t)elem); a64_mul(&g->code,0,0,9); }
            arm_add_reloc(g,"mag_alloc",a64_bl(&g->code),RELOC_BRANCH); break;
        }
        case AST_UNARY_EXPR: {
            const char* op=n->token.text?n->token.text:"";
            if(!strcmp(op,"move")) {
                ASTNode* ch=n->child_count?n->children[0]:NULL;
                arm_addr(g,ch);
                int idx=arm_save_scratch(g,0);
                int size=arm_expr_elem_size(g,ch);
                arm_load_scratch(g,9,idx);
                arm_load_value(g,9,0,size);
                arm_load_scratch(g,9,idx);
                a64_mov_imm(&g->code,10,0);
                arm_store_value(g,9,10,size);
                arm_release_scratch(g,idx);
            }
            else if(!strcmp(op,"&")) arm_addr(g,n->child_count?n->children[0]:NULL);
            else if(!strcmp(op,"*")) {
                ASTNode* ch=n->child_count?n->children[0]:NULL;
                if (arm_expr_kind(g,n)==VK_ANY) {
                    /* Any lvalues carry a 16-byte tagged box; leave its
                       address in x0, like an any variable. */
                    arm_addr(g,n);
                } else {
                    arm_expr(g,ch);
                    arm_load_value(g,0,0,arm_expr_elem_size(g,ch));
                }
            }
            else if(!strcmp(op,"!")) {
                arm_expr(g,n->child_count?n->children[0]:NULL);
                a64_cmp_imm(&g->code,0,0); a64_cset(&g->code,0,A64_EQ);
            }
            else if(!strcmp(op,"~")) {
                arm_expr(g,n->child_count?n->children[0]:NULL);
                a64_eor_reg(&g->code,0,0,31);
            }
            else if(!strcmp(op,"-")) {
                ASTNode* ch=n->child_count?n->children[0]:NULL;
                if(arm_is_float(g,ch)) {
                    arm_expr(g,ch);
                    a64_fmov_s_w(&g->code,0,0);
                    a64_mov_imm(&g->code,9,0xBF800000ULL); /* -1.0f */
                    a64_fmov_s_w(&g->code,9,9);
                    a64_fmul(&g->code,0,0,9);
                    a64_fmov_w_s(&g->code,0,0);
                } else {
                    arm_expr(g,ch); a64_sub_reg(&g->code,0,31,0);
                }
            }
            else if(!strcmp(op,"++")||!strcmp(op,"--")) {
                ASTNode* target=n->child_count?n->children[0]:NULL;
                arm_addr(g,target);
                int idx=arm_save_scratch(g,0);
                int size=arm_expr_elem_size(g,target);
                arm_load_scratch(g,9,idx);
                arm_load_value(g,9,9,size);
                a64_mov_imm(&g->code,10,1);
                if(!strcmp(op,"--")) a64_sub_reg(&g->code,9,9,10);
                else a64_add_reg(&g->code,9,9,10);
                arm_load_scratch(g,0,idx);
                arm_store_value(g,0,9,size);
                arm_release_scratch(g,idx);
                a64_mov_reg(&g->code,0,9);
            }
            else { if(n->child_count>0) arm_expr(g,n->children[0]); else a64_mov_imm(&g->code,0,0); }
            break;
        }
        case AST_BINARY_EXPR: {
            int tok=(int)n->token.type;
            if(tok==TOK_ASSIGN) {
                ASTNode* lhs=n->child_count>0?n->children[0]:NULL;
                ASTNode* rhs=n->child_count>1?n->children[1]:NULL;
                Sym* ls=lhs&&(lhs->type==AST_IDENTIFIER_EXPR||lhs->type==NODE_IDENT)?arm_find_sym(g,lhs->token.text):NULL;
                Sym* rs=rhs&&(rhs->type==AST_IDENTIFIER_EXPR||rhs->type==NODE_IDENT)?arm_find_sym(g,rhs->token.text):NULL;
                if(arm_expr_kind(g,lhs)==VK_ANY) {
                    arm_addr(g,lhs);
                    int didx=arm_save_scratch(g,0);
                    arm_materialize_any(g,rhs);
                    arm_load_scratch(g,9,didx);
                    a64_ldr_x(&g->code,10,0,0);
                    a64_str_x(&g->code,10,9,0);
                    a64_ldr_x(&g->code,10,0,8);
                    a64_str_x(&g->code,10,9,8);
                    arm_release_scratch(g,didx);
                    a64_mov_reg(&g->code,0,9);
                    break;
                }
                if(ls&&ls->kind==VK_STRUCT&&rs&&rs->kind==VK_STRUCT) {
                    arm_addr(g,lhs);
                    int didx=arm_save_scratch(g,0);
                    arm_addr(g,rhs);
                    int words=(ls->size+7)/8;
                    if(words<1) words=1;
                    if(words>(rs->size+7)/8) words=(rs->size+7)/8;
                    for(int w=0;w<words;w++) {
                        a64_ldr_x(&g->code,10,0,(uint32_t)(w*8));
                        arm_load_scratch(g,9,didx);
                        a64_str_x(&g->code,10,9,(uint32_t)(w*8));
                    }
                    arm_release_scratch(g,didx);
                    a64_mov_reg(&g->code,0,10);
                    break;
                }
                arm_expr(g,rhs);
                int idx=arm_save_scratch(g,0);
                arm_addr(g,lhs);
                int size=arm_expr_elem_size(g,lhs);
                if(lhs&&(lhs->type==AST_IDENTIFIER_EXPR||lhs->type==NODE_IDENT)) {
                    Sym* s=arm_find_sym(g,lhs->token.text);
                    if(s&&s->kind!=VK_ARRAY&&s->kind!=VK_PTR) size=8;
                }
                arm_load_scratch(g,9,idx);
                arm_store_value(g,0,9,size);
                arm_release_scratch(g,idx);
                a64_mov_reg(&g->code,0,9);
                break;
            }
            if(tok>=TOK_PLUS_ASSIGN&&tok<=TOK_XOR_ASSIGN) {
                ASTNode* lhs=n->child_count>0?n->children[0]:NULL;
                ASTNode* rhs=n->child_count>1?n->children[1]:NULL;
                arm_addr(g,lhs);
                int aidx=arm_save_scratch(g,0);
                int size=arm_expr_elem_size(g,lhs);
                arm_load_scratch(g,9,aidx);
                arm_load_value(g,9,9,size);
                arm_expr(g,rhs);
                a64_mov_reg(&g->code,10,0);
                switch(tok) {
                    case TOK_PLUS_ASSIGN: a64_add_reg(&g->code,9,9,10); break;
                    case TOK_MINUS_ASSIGN: a64_sub_reg(&g->code,9,9,10); break;
                    case TOK_STAR_ASSIGN: a64_mul(&g->code,9,9,10); break;
                    case TOK_SLASH_ASSIGN: {
                        size_t z=arm_div_check(g);
                        a64_sdiv(&g->code,9,9,10);
                        arm_div_check_end(g,z); break;
                    }
                    case TOK_MOD_ASSIGN: {
                        size_t z=arm_div_check(g);
                        a64_mov_imm(&g->code,11,0);
                        a64_udiv(&g->code,11,9,10);
                        a64_mul(&g->code,12,11,10);
                        a64_sub_reg(&g->code,9,9,12);
                        arm_div_check_end(g,z); break;
                    }
                    case TOK_AND_ASSIGN: a64_and_reg(&g->code,9,9,10); break;
                    case TOK_OR_ASSIGN: a64_orr_reg(&g->code,9,9,10); break;
                    case TOK_XOR_ASSIGN: a64_eor_reg(&g->code,9,9,10); break;
                    default: break;
                }
                arm_load_scratch(g,0,aidx);
                arm_store_value(g,0,9,size);
                arm_release_scratch(g,aidx);
                a64_mov_reg(&g->code,0,9);
                break;
            }
            if(n->child_count<2) { a64_mov_imm(&g->code,0,0); break; }
            /* Logical operators must short-circuit: the right operand is not
               evaluated when the left operand already decides the result. */
            if(tok==TOK_AND || tok==TOK_OR) {
                arm_expr(g,n->children[0]);
                size_t p=(tok==TOK_AND)?a64_cbz(&g->code,0):a64_cbnz(&g->code,0);
                arm_expr(g,n->children[1]);
                a64_cmp_imm(&g->code,0,0);
                a64_cset(&g->code,0,A64_NE);
                size_t e=a64_b(&g->code);
                a64_patch_cb(g->code.data,p,a64_size(&g->code));
                a64_mov_imm(&g->code,0,tok==TOK_AND?0:1);
                a64_patch_branch(g->code.data,e,a64_size(&g->code));
                break;
            }
            if(arm_is_string_expr(g,n->children[0]) &&
               arm_is_string_expr(g,n->children[1])) {
                arm_expr(g,n->children[0]);
                int slot=arm_save_scratch(g,0);
                arm_expr(g,n->children[1]);
                a64_mov_reg(&g->code,1,0);
                arm_load_scratch(g,0,slot);
                arm_release_scratch(g,slot);
                if(tok==TOK_PLUS) {
                    arm_add_reloc(g,"mag_strcat2",a64_bl(&g->code),RELOC_BRANCH);
                } else {
                    arm_add_reloc(g,"mag_strcmp",a64_bl(&g->code),RELOC_BRANCH);
                    int cond=A64_EQ;
                    if(tok==TOK_NEQ) cond=A64_NE;
                    else if(tok==TOK_LT) cond=A64_LT;
                    else if(tok==TOK_LE) cond=A64_LE;
                    else if(tok==TOK_GT) cond=A64_GT;
                    else if(tok==TOK_GE) cond=A64_GE;
                    a64_cmp_imm(&g->code,0,0);
                    a64_cset(&g->code,0,cond);
                }
                break;
            }
            if(arm_is_any_expr(g,n)) {
                int aoff=arm_alloc_local(g,16);
                arm_emit_addr(g,8,29,aoff);
                int dest_slot=arm_save_scratch(g,8);
                arm_materialize_any(g,n->children[0]);
                int aslot=arm_save_scratch(g,0);
                arm_materialize_any(g,n->children[1]);
                a64_mov_reg(&g->code,2,0);
                arm_load_scratch(g,1,aslot);
                arm_release_scratch(g,aslot);
                arm_load_scratch(g,8,dest_slot);
                arm_release_scratch(g,dest_slot);
                a64_mov_imm(&g->code,3,(uint64_t)tok);
                arm_add_reloc(g,"mag_any_bin",a64_bl(&g->code),RELOC_BRANCH);
                arm_emit_addr(g,0,29,aoff);
                break;
            }
            bool fl=arm_is_float(g,n);
            /* Evaluate left first, then right; keep left in x9. */
            arm_expr(g,n->children[0]);
            int sidx=arm_save_scratch(g,0);
            arm_expr(g,n->children[1]);
            a64_mov_reg(&g->code,10,0);
            arm_load_scratch(g,9,sidx);
            arm_release_scratch(g,sidx);
            if(fl) {
                if(arm_is_float(g,n->children[0])) a64_fmov_s_w(&g->code,0,9);
                else a64_scvtf(&g->code,0,9);
                if(arm_is_float(g,n->children[1])) a64_fmov_s_w(&g->code,1,10);
                else a64_scvtf(&g->code,1,10);
                bool cmp=false;
                int cond=A64_EQ;
                switch(tok) {
                    case TOK_PLUS: a64_fadd(&g->code,0,0,1); break;
                    case TOK_MINUS: a64_fsub(&g->code,0,0,1); break;
                    case TOK_STAR: a64_fmul(&g->code,0,0,1); break;
                    case TOK_SLASH: a64_fdiv(&g->code,0,0,1); break;
                    case TOK_EQ: case TOK_NEQ: case TOK_LT: case TOK_LE:
                    case TOK_GT: case TOK_GE: {
                        cmp=true;
                        if(tok==TOK_EQ) cond=A64_EQ;
                        else if(tok==TOK_NEQ) cond=A64_NE;
                        else if(tok==TOK_LT) cond=A64_LT;
                        else if(tok==TOK_LE) cond=A64_LE;
                        else if(tok==TOK_GT) cond=A64_GT;
                        else cond=A64_GE;
                        a64_fcmp(&g->code,0,1);
                        a64_cset(&g->code,0,cond);
                        break;
                    }
                    default: a64_mov_imm(&g->code,0,0); break;
                }
                if(!cmp) a64_fmov_w_s(&g->code,0,0);
            } else {
                switch(tok) {
                    case TOK_PLUS: a64_add_reg(&g->code,0,9,10); break;
                    case TOK_MINUS: a64_sub_reg(&g->code,0,9,10); break;
                    case TOK_STAR: a64_mul(&g->code,0,9,10); break;
                    case TOK_SLASH: {
                        size_t z=arm_div_check(g);
                        a64_sdiv(&g->code,0,9,10);
                        arm_div_check_end(g,z); break;
                    }
                    case TOK_MOD: {
                        size_t z=arm_div_check(g);
                        a64_mov_imm(&g->code,11,0);
                        a64_udiv(&g->code,11,9,10);
                        a64_mul(&g->code,12,11,10);
                        a64_sub_reg(&g->code,0,9,12);
                        arm_div_check_end(g,z); break;
                    }
                    case TOK_BIT_AND: a64_and_reg(&g->code,0,9,10); break;
                    case TOK_BIT_OR: a64_orr_reg(&g->code,0,9,10); break;
                    case TOK_BIT_XOR: a64_eor_reg(&g->code,0,9,10); break;
                    case TOK_SHL: case TOK_SHR: {
                        a64_mov_imm(&g->code,12,63);
                        a64_and_reg(&g->code,10,10,12);
                        a64_emit32(&g->code,
                            (tok==TOK_SHL?0x9AC32000u:0x9AC42800u) |
                            ((uint32_t)10<<16)|((uint32_t)9<<5)|0u);
                        break;
                    }
                    case TOK_EQ: case TOK_NEQ: case TOK_LT: case TOK_LE:
                    case TOK_GT: case TOK_GE: {
                        int cond=A64_EQ;
                        if(tok==TOK_EQ) cond=A64_EQ;
                        else if(tok==TOK_NEQ) cond=A64_NE;
                        else if(tok==TOK_LT) cond=A64_LT;
                        else if(tok==TOK_LE) cond=A64_LE;
                        else if(tok==TOK_GT) cond=A64_GT;
                        else cond=A64_GE;
                        a64_cmp_reg(&g->code,9,10);
                        a64_cset(&g->code,0,cond);
                        break;
                    }
                    case TOK_AND: case TOK_OR: {
                        if(tok==TOK_AND) {
                            size_t p=a64_cbz(&g->code,9);
                            a64_mov_imm(&g->code,0,0);
                            a64_cmp_imm(&g->code,10,0);
                            a64_cset(&g->code,0,A64_NE);
                            a64_patch_cb(g->code.data,p,a64_size(&g->code));
                        } else {
                            size_t p=a64_cbnz(&g->code,9);
                            a64_mov_imm(&g->code,0,1);
                            size_t e=a64_b(&g->code);
                            a64_patch_cb(g->code.data,p,a64_size(&g->code));
                            a64_cmp_imm(&g->code,10,0);
                            a64_cset(&g->code,0,A64_NE);
                            a64_patch_branch(g->code.data,e,a64_size(&g->code));
                        }
                        break;
                    }
                    default: a64_mov_imm(&g->code,0,0); break;
                }
            }
            break;
        }
        case AST_TERNARY_EXPR:
            if(n->child_count>=3) {
                arm_expr(g,n->children[0]);
                a64_cmp_imm(&g->code,0,0);
                size_t p=a64_bcond(&g->code,A64_EQ);
                arm_expr(g,n->children[1]);
                size_t e=a64_b(&g->code);
                a64_patch_cond(g->code.data,p,a64_size(&g->code));
                arm_expr(g,n->children[2]);
                a64_patch_branch(g->code.data,e,a64_size(&g->code));
            } else a64_mov_imm(&g->code,0,0);
            break;
        case AST_MEMBER_ACCESS: {
            /* Enum members are compile-time constants: `E.B` must not be
               treated as a struct field access. */
            ASTNode* base=n->child_count?n->children[0]:NULL;
            if(base && (base->type==AST_IDENTIFIER_EXPR||base->type==NODE_IDENT) &&
               base->token.text && is_enum_type(base->token.text)) {
                a64_mov_imm(&g->code,0,
                    (uint64_t)lookup_enum_value(base->token.text,n->token.text));
                break;
            }
            StructField* f = base ? arm_var_field(g,base,n->token.text) : NULL;
            arm_addr(g,n);
            if (f && f->array_size>0) break; /* array fields evaluate to their address */
            arm_load_value(g,0,0,f?elem_size_from_token(f->field_type):8);
            break;
        }
        case AST_STRUCT_LITERAL: {
            /* Materialise a tuple/aggregate literal in a temporary frame slot
               and return its address. */
            int words=n->child_count?n->child_count:1;
            int off=arm_alloc_local(g,words*8);
            arm_emit_addr(g,0,29,off);
            int idx=arm_save_scratch(g,0);
            for(int i=0;i<n->child_count;i++) {
                arm_expr(g,n->children[i]);
                arm_load_scratch(g,9,idx);
                a64_str_x(&g->code,0,9,(uint32_t)(i*8));
            }
            arm_release_scratch(g,idx);
            arm_emit_addr(g,0,29,off);
            break;
        }
        case AST_SLICE_EXPR: {
            if(n->child_count<3) {
                if(n->child_count>0) arm_expr(g,n->children[0]);
                else a64_mov_imm(&g->code,0,0);
                break;
            }
            /* Evaluate start/end for side effects, then return base + start*8
               so subsequent `s[i]` indexes the sliced view. */
            arm_expr(g,n->children[1]);
            int sidx=arm_save_scratch(g,0);
            arm_expr(g,n->children[2]);
            int eidx=arm_save_scratch(g,0);
            arm_expr(g,n->children[0]);
            arm_load_scratch(g,10,sidx);
            a64_mov_imm(&g->code,11,8);
            a64_mul(&g->code,10,10,11);
            a64_add_reg(&g->code,0,0,10);
            arm_release_scratch(g,eidx);
            arm_release_scratch(g,sidx);
            break;
        }
        case AST_CALL_EXPR: {
            if(n->child_count<1) { a64_mov_imm(&g->code,0,0); break; }
            /* dyn<T> methods operate on the local [len][cap] metadata slot. */
            if(arm_call_is_method(n)&&n->children[0]->type==AST_MEMBER_ACCESS) {
                ASTNode* member=n->children[0];
                ASTNode* recv=member->child_count?member->children[0]:NULL;
                Sym* ds=(recv&&(recv->type==AST_IDENTIFIER_EXPR||recv->type==NODE_IDENT))
                    ?arm_find_sym(g,recv->token.text):NULL;
                if(ds&&ds->is_dyn) {
                    const char* meth=member->token.text?member->token.text:"";
                    int meta=ds->offset+ds->dyn_cap*ds->elem_size;
                    if(!strcmp(meth,"len")||!strcmp(meth,"size")) {
                        arm_emit_addr(g,0,29,meta); a64_ldr_x(&g->code,0,0,0); break;
                    }
                    if(!strcmp(meth,"cap")||!strcmp(meth,"capacity")) {
                        arm_emit_addr(g,0,29,meta+8); a64_ldr_x(&g->code,0,0,0); break;
                    }
                    if(!strcmp(meth,"clear")) {
                        arm_emit_addr(g,9,29,meta);
                        a64_mov_imm(&g->code,10,0); a64_str_x(&g->code,10,9,0);
                        a64_mov_imm(&g->code,0,0); break;
                    }
                    if(!strcmp(meth,"push")) {
                        arm_expr(g,n->child_count>1?n->children[1]:NULL);
                        int vslot=arm_save_scratch(g,0);
                        arm_emit_addr(g,11,29,meta);
                        a64_ldr_x(&g->code,10,11,0);
                        int lslot=arm_save_scratch(g,10);
                        arm_emit_addr(g,11,29,ds->offset);
                        a64_mov_imm(&g->code,12,(uint64_t)ds->elem_size);
                        a64_mul(&g->code,10,10,12);
                        a64_add_reg(&g->code,11,11,10);
                        arm_load_scratch(g,0,vslot); arm_release_scratch(g,vslot);
                        arm_store_value(g,11,0,ds->elem_size);
                        arm_load_scratch(g,10,lslot); arm_release_scratch(g,lslot);
                        a64_mov_imm(&g->code,11,1);
                        a64_add_reg(&g->code,10,10,11);
                        arm_emit_addr(g,9,29,meta);
                        a64_str_x(&g->code,10,9,0);
                        a64_mov_reg(&g->code,0,10); break;
                    }
                    if(!strcmp(meth,"pop")) {
                        arm_emit_addr(g,9,29,meta);
                        a64_ldr_x(&g->code,10,9,0);
                        a64_mov_imm(&g->code,11,1);
                        a64_sub_reg(&g->code,10,10,11);
                        a64_str_x(&g->code,10,9,0);
                        arm_emit_addr(g,9,29,ds->offset);
                        a64_mov_imm(&g->code,11,(uint64_t)ds->elem_size);
                        a64_mul(&g->code,10,10,11);
                        a64_add_reg(&g->code,9,9,10);
                        arm_load_value(g,9,0,ds->elem_size); break;
                    }
                }
            }
            const char* nm=n->children[0]->token.text?n->children[0]->token.text:"";
            if(!strcmp(nm,"sizeof")) {
                int64_t sz=8;
                if(n->child_count>1) {
                    Sym* s=arm_find_sym(g,n->children[1]->token.text);
                    if(s) sz=s->size;
                    else if(n->children[1]->token.text && !strcmp(n->children[1]->token.text,"any")) sz=16;
                }
                a64_mov_imm(&g->code,0,(uint64_t)sz); break;
            }
            char tbuf[256];
            const char* target=arm_call_target(g,n,tbuf,sizeof(tbuf),true);
            int ret_size=arm_call_ret_size(g,target);
            int ret_off=0;
            if(ret_size>0) {
                ret_off=arm_alloc_local(g,ret_size);
                arm_emit_addr(g,0,29,ret_off);
                a64_mov_reg(&g->code,8,0);
            }
            static const char* builtins[]={
                "print","println","print_info","print_error","eprint","print_str",
                "print_int","print_float","len","str_equals","str_compare","strcmp",
                "exit","sys_exit","sys_exit_group","get_timestamp","sleep_ms",
                "rand_int","sqrt","abs",NULL
            };
            bool bi=false;
            if(!arm_call_is_method(n))
                for(int i=0;builtins[i];i++) if(!strcmp(nm,builtins[i])) { bi=true; break; }
            if(bi) arm_builtin(g,n,nm);
            else arm_emit_call(g,n,target);
            if(ret_size>0) arm_emit_addr(g,0,29,ret_off);
            break;
        }
        case AST_SPAWN_STMT: case AST_ASYNC_STMT:
            arm_task_fork(g,n->child_count>0?n->children[0]:NULL); break;
        case AST_AWAIT_STMT:
            if(n->child_count>0) arm_expr(g,n->children[0]);
            arm_task_join(g,n->child_count==0); break;
        default: a64_mov_imm(&g->code,0,0); break;
    }
}

/* ------------------------------------------------------------------ */
/* Statements                                                         */
/* ------------------------------------------------------------------ */
static void arm_stmt(ArmGen* g, ASTNode* n);

/* Run deferred statements in reverse registration order (LIFO). */
static void arm_flush_defers(ArmGen* g) {
    for (int i = g->defer_count - 1; i >= 0; i--) arm_stmt(g, g->defers[i]);
    g->defer_count = 0;
}

/* Unhandled throw: write a diagnostic and exit with status 1. */
static void arm_unhandled_throw(ArmGen* g) {
    static const char msg[] = "Unhandled Exception!\n";
    arm_emit_string_addr(g, msg);       /* x0 = message address */
    a64_mov_reg(&g->code, 1, 0);        /* x1 = buffer */
    a64_mov_imm(&g->code, 0, 2);        /* x0 = stderr */
    a64_mov_imm(&g->code, 2, sizeof(msg) - 1);
    a64_mov_imm(&g->code, 8, 64);
    a64_svc(&g->code);
    a64_mov_imm(&g->code, 0, 1);
    a64_mov_imm(&g->code, 8, 94);
    a64_svc(&g->code);
}

static size_t arm_prologue(ArmGen* g) {
    a64_prologue(&g->code,0);
    return a64_size(&g->code)-4;
}
static size_t arm_epilogue(ArmGen* g) {
    size_t pos=a64_size(&g->code);
    a64_add_imm(&g->code,31,31,0);
    a64_emit32(&g->code,0xA8C17BFD);
    a64_ret(&g->code);
    if(g->epilogue_count<ARM_MAX_EPILOGUES) g->epilogues[g->epilogue_count++]=pos;
    return pos;
}
static void arm_patch_frame(ArmGen* g,size_t sub_pos,uint32_t frame) {
    if(!frame) return;
    uint32_t w=ld32(g->code.data+sub_pos);
    w=(w&~0x003FFC00u)|((frame&0xFFFu)<<10);
    st32(g->code.data+sub_pos,w);
    for(int i=0;i<g->epilogue_count;i++) {
        uint8_t* p=g->code.data+g->epilogues[i];
        uint32_t e=ld32(p);
        e=(e&~0x003FFC00u)|((frame&0xFFFu)<<10);
        st32(p,e);
    }
}
/* Copy a 16-byte tagged-any box into a struct field at the given offset
   from a base address held in a scratch slot. */
static void arm_store_any_field(ArmGen* g, int base_slot, int offset, ASTNode* init) {
    arm_load_scratch(g,0,base_slot);
    a64_mov_imm(&g->code,10,(uint64_t)offset);
    a64_add_reg(&g->code,0,0,10);
    int idx=arm_save_scratch(g,0);
    arm_materialize_any(g,init);
    arm_load_scratch(g,9,idx);
    a64_ldr_x(&g->code,10,0,0);
    a64_str_x(&g->code,10,9,0);
    a64_ldr_x(&g->code,10,0,8);
    a64_str_x(&g->code,10,9,8);
    arm_release_scratch(g,idx);
}

/* ------------------------------------------------------------------ */
/* Minimal inline-asm emulation                                        */
/* ------------------------------------------------------------------ */
static char* arm_trim(char* s) {
    while(*s==' '||*s=='\t'||*s=='\r'||*s=='\n') s++;
    char* e=s+strlen(s);
    while(e>s&&(e[-1]==' '||e[-1]=='\t'||e[-1]=='\r'||e[-1]=='\n')) *--e=0;
    return s;
}
static int arm_asm_reg(const char* s) {
    s=arm_trim((char*)s);
    if(!strncmp(s,"rax",3)||!strncmp(s,"eax",3)) return 19;
    if(!strncmp(s,"rdi",3)||!strncmp(s,"edi",3)) return 20;
    if(!strncmp(s,"rcx",3)||!strncmp(s,"ecx",3)) return 21;
    if(!strncmp(s,"rdx",3)||!strncmp(s,"edx",3)) return 22;
    if(!strncmp(s,"rsi",3)||!strncmp(s,"esi",3)) return 23;
    if(!strncmp(s,"r8",2)||!strncmp(s,"r8d",3)) return 24;
    if(!strncmp(s,"r9",2)||!strncmp(s,"r9d",3)) return 25;
    if(!strncmp(s,"r10",3)||!strncmp(s,"r10d",5)) return 26;
    return -1;
}
static int arm_asm_memreg(const char* s) {
    if(!s||s[0]!='[') return -1;
    char name[64];
    snprintf(name,sizeof(name),"%s",s+1);
    char* close=strchr(name,']');
    if(close) *close=0;
    return arm_asm_reg(name);
}
/* Translate an x86-64 syscall number held in the emulated RAX (x19) to its
 * AArch64 number in x8, then marshal x86 argument registers into x0-x5. */
static void arm_emit_asm_syscall(ArmGen* g) {
    A64Buf* c=&g->code;
    size_t done_branches[128];
    int ndone=0;
#define ASM_SYSCALL_CASE(x86, arm64) do { \
        a64_cmp_imm(c,19,(uint32_t)(x86)); \
        size_t skip=a64_bcond(c,A64_NE); \
        a64_mov_imm(c,8,(uint64_t)(arm64)); \
        size_t done=a64_b(c); \
        a64_patch_cond(c->data,skip,a64_size(c)); \
        done_branches[ndone++]=done; \
    } while(0)
    ASM_SYSCALL_CASE(0,63);   ASM_SYSCALL_CASE(1,64);
    ASM_SYSCALL_CASE(2,56);   ASM_SYSCALL_CASE(3,57);
    ASM_SYSCALL_CASE(4,79);   ASM_SYSCALL_CASE(5,80);
    ASM_SYSCALL_CASE(6,79);   ASM_SYSCALL_CASE(7,73);
    ASM_SYSCALL_CASE(8,62);   ASM_SYSCALL_CASE(9,222);
    ASM_SYSCALL_CASE(11,215); ASM_SYSCALL_CASE(13,134);
    ASM_SYSCALL_CASE(14,135); ASM_SYSCALL_CASE(16,29);
    ASM_SYSCALL_CASE(19,65);  ASM_SYSCALL_CASE(20,66);
    ASM_SYSCALL_CASE(21,48);  ASM_SYSCALL_CASE(22,59);
    ASM_SYSCALL_CASE(23,72);  ASM_SYSCALL_CASE(24,124);
    ASM_SYSCALL_CASE(32,23);  ASM_SYSCALL_CASE(33,24);
    ASM_SYSCALL_CASE(35,101); ASM_SYSCALL_CASE(39,172);
    ASM_SYSCALL_CASE(41,198); ASM_SYSCALL_CASE(42,203);
    ASM_SYSCALL_CASE(43,202); ASM_SYSCALL_CASE(44,206);
    ASM_SYSCALL_CASE(45,207); ASM_SYSCALL_CASE(48,210);
    ASM_SYSCALL_CASE(49,200); ASM_SYSCALL_CASE(50,201);
    ASM_SYSCALL_CASE(51,204); ASM_SYSCALL_CASE(52,205);
    ASM_SYSCALL_CASE(53,199); ASM_SYSCALL_CASE(54,208);
    ASM_SYSCALL_CASE(55,209); ASM_SYSCALL_CASE(56,220);
    ASM_SYSCALL_CASE(57,220); ASM_SYSCALL_CASE(59,221);
    ASM_SYSCALL_CASE(60,93);  ASM_SYSCALL_CASE(61,260);
    ASM_SYSCALL_CASE(62,129); ASM_SYSCALL_CASE(63,160);
    ASM_SYSCALL_CASE(79,17);  ASM_SYSCALL_CASE(80,49);
    ASM_SYSCALL_CASE(83,34);  ASM_SYSCALL_CASE(84,35);
    ASM_SYSCALL_CASE(85,56);  ASM_SYSCALL_CASE(87,35);
    ASM_SYSCALL_CASE(88,36);  ASM_SYSCALL_CASE(89,38);
    ASM_SYSCALL_CASE(90,53);  ASM_SYSCALL_CASE(91,52);
    ASM_SYSCALL_CASE(92,54);  ASM_SYSCALL_CASE(228,113);
    ASM_SYSCALL_CASE(231,94); ASM_SYSCALL_CASE(318,278);
#undef ASM_SYSCALL_CASE
    /* Unsupported x86 numbers become exit_group with the emulated RDI code. */
    a64_mov_imm(c,8,94);
    for(int i=0;i<ndone;i++)
        a64_patch_cond(c->data,done_branches[i],a64_size(c));

    a64_mov_reg(c,0,20);      /* rdi */
    a64_mov_reg(c,1,23);      /* rsi */
    a64_mov_reg(c,2,22);      /* rdx */
    a64_mov_reg(c,3,26);      /* r10 */
    a64_mov_reg(c,4,24);      /* r8 */
    a64_mov_reg(c,5,25);      /* r9 */

    /* AArch64 uses *at() variants for path operations. */
    size_t special_done[32];
    int nspecial=0;
#define ASM_AT_CASE(x86, extra) do { \
        a64_cmp_imm(c,19,(uint32_t)(x86)); \
        size_t skip=a64_bcond(c,A64_NE); \
        a64_mov_imm(c,0,(uint64_t)(int64_t)-100); \
        a64_mov_reg(c,1,20); a64_mov_reg(c,2,21); \
        a64_mov_imm(c,3,(uint64_t)(extra)); \
        size_t done=a64_b(c); \
        a64_patch_cond(c->data,skip,a64_size(c)); \
        special_done[nspecial++]=done; \
    } while(0)
    ASM_AT_CASE(2,22);  /* open(path, flags, mode) -> openat(fd, path, flags, mode) */
    ASM_AT_CASE(4,0);   /* stat */
    ASM_AT_CASE(6,0x100); /* lstat uses AT_SYMLINK_NOFOLLOW */
    ASM_AT_CASE(21,0);  /* faccessat */
    ASM_AT_CASE(83,0);  /* mkdirat */
    ASM_AT_CASE(84,0x200); /* unlinkat with AT_REMOVEDIR */
    ASM_AT_CASE(85,22); /* creat -> openat */
    ASM_AT_CASE(87,0);  /* unlinkat */
    ASM_AT_CASE(90,0);  /* fchmodat */
    ASM_AT_CASE(92,0);  /* fchownat */
#undef ASM_AT_CASE
    for(int i=0;i<nspecial;i++)
        a64_patch_cond(c->data,special_done[i],a64_size(c));
    a64_svc(c);
}
static void arm_emit_asm(ArmGen* g, const char* text) {
    if(!text) return;
    char* buf=strdup(text);
    if(buf[0]=='"') memmove(buf,buf+1,strlen(buf));
    char* q=strchr(buf,'"'); if(q) *q=0;
    int slots[8], nslots=0;
    char* stmt=strtok(buf,";\n");
    while(stmt) {
        char* s=arm_trim(stmt);
        if(*s) {
            char* sp=strchr(s,' ');
            if(!sp||!strncmp(s,"syscall",7)) {
                arm_emit_asm_syscall(g);
            } else {
                *sp=0;
                char* mnem=arm_trim(s);
                char* ops=arm_trim(sp+1);
                char* comma=strchr(ops,',');
                char* a=ops,*b=NULL;
                if(comma) { *comma=0; b=arm_trim(comma+1); a=arm_trim(a); }
                int ra=arm_asm_reg(a);
                int64_t imm=b?strtoll(b,NULL,0):0;
                int rb=b?arm_asm_reg(b):-1;
                if(!strcmp(mnem,"mov")) {
                    if(a[0]=='[') {
                        /* mov [reg], reg */
                        int base=arm_asm_memreg(a);
                        int src=arm_asm_reg(b);
                        if(base>=0&&src>=0) a64_str_x(&g->code,src,base,0);
                    } else if(ra>=0) {
                        if(b&&!strcmp(b,"[rsp]")) {
                            if(nslots>0) arm_load_scratch(g,ra,slots[nslots-1]);
                        } else if(b&&b[0]=='[') {
                            int base=arm_asm_memreg(b);
                            if(base>=0) {
                                a64_ldr_x(&g->code,ra,base,0);
                            } else {
                                char name[64]; strncpy(name,b+1,sizeof(name)-1);
                                name[sizeof(name)-1]=0;
                                char* close=strchr(name,']'); if(close)*close=0;
                                Sym* sy=arm_find_sym(g,arm_trim(name));
                                if(sy) {
                                    arm_emit_addr(g,9,29,sy->offset);
                                    a64_ldr_x(&g->code,ra,9,0);
                                }
                            }
                        } else if(rb>=0) a64_mov_reg(&g->code,ra,rb);
                        else a64_mov_imm(&g->code,ra,(uint64_t)imm);
                    }
                } else if(!strcmp(mnem,"lea")&&ra>=0&&b&&b[0]=='[') {
                    char name[64]; strncpy(name,b+1,sizeof(name)-1);
                    name[sizeof(name)-1]=0;
                    char* close=strchr(name,']'); if(close)*close=0;
                    Sym* sy=arm_find_sym(g,arm_trim(name));
                    if(sy) arm_emit_addr(g,ra,29,sy->offset);
                } else if(!strcmp(mnem,"add")&&ra>=0) {
                    if(b&&b[0]=='['&&b[1]!='r') {
                        char name[64]; strncpy(name,b+1,sizeof(name)-1);
                        name[sizeof(name)-1]=0;
                        char* close=strchr(name,']'); if(close)*close=0;
                        Sym* sy=arm_find_sym(g,arm_trim(name));
                        if(sy) {
                            arm_emit_addr(g,9,29,sy->offset);
                            a64_ldr_x(&g->code,10,9,0);
                            a64_add_reg(&g->code,ra,ra,10);
                        }
                    } else if(rb>=0) a64_add_reg(&g->code,ra,ra,rb);
                    else a64_add_imm(&g->code,ra,ra,(uint32_t)imm);
                } else if(!strcmp(mnem,"sub")&&ra>=0) {
                    if(rb>=0) a64_sub_reg(&g->code,ra,ra,rb);
                    else a64_sub_imm(&g->code,ra,ra,(uint32_t)imm);
                } else if(!strcmp(mnem,"shl")&&ra>=0) {
                    a64_mov_imm(&g->code,10,(uint64_t)imm);
                    a64_emit32(&g->code,(0x9AC32000u&~0x001F0000u)|((uint32_t)10<<16)|((uint32_t)ra<<5)|(uint32_t)ra);
                } else if(!strcmp(mnem,"push")&&ra>=0&&nslots<8) {
                    slots[nslots]=arm_save_scratch(g,ra); nslots++;
                } else if(!strcmp(mnem,"pop")&&ra>=0&&nslots>0) {
                    nslots--; arm_load_scratch(g,ra,slots[nslots]); arm_release_scratch(g,slots[nslots]);
                } else if(!strcmp(mnem,"mov")&&ra>=0&&b&&!strcmp(b,"[rsp]")&&nslots>0) {
                    arm_load_scratch(g,ra,slots[nslots-1]);
                }
            }
        }
        stmt=strtok(NULL,";\n");
    }
    free(buf);
}

static void arm_var_decl(ArmGen* g, ASTNode* n) {
    if(!n||!n->token.text) return;
    Sym* existing=arm_find_sym(g,n->token.text);
    if(n->bool_value&&existing&&existing->is_global_mutable) return;
    int tok=(int)n->int_value;
    ValueKind kind=kind_from_token(tok);
    /* A slice is a pointer-like descriptor, not inline array storage: its
       initializer holds the adjusted base address produced by `a[i..j]`. */
    bool is_array=(tok==T_ARRAY||tok==T_DYN||tok==T_FIXED||tok==T_TUPLE);
    int elem_size=8,array_len=1;
    ASTNode* init=n->child_count>0?n->children[0]:NULL;
    ASTNode* values=NULL;
    StructType* st=n->string_value?lookup_struct(n->string_value):NULL;
    if(kind==VK_CHAR) elem_size=1;
    if(is_array) {
        if(n->child_count>0&&(n->children[0]->type==NODE_NUMBER||
           n->children[0]->type==AST_LITERAL_EXPR))
            array_len=(int)n->children[0]->int_value;
        if(n->child_count>1) { init=n->children[0]; values=n->children[1]; }
        else if(n->child_count==1&&n->children[0]->type==AST_STRUCT_LITERAL) {
            /* dyn<T> d = {a, b} has no explicit length operand. */
            values=n->children[0]; init=NULL;
            array_len=values->child_count?values->child_count:1;
        }
        else init=NULL;
        if(array_len<=0) array_len=1;
        if(values&&values->type==AST_STRUCT_LITERAL&&array_len<=1)
            array_len=values->child_count?values->child_count:1;
        /* Parser stores the element token in decl->char_value and the flat
           element count in children[0]->int_value.  Use the parser's slot
           width so `any` arrays do not silently overrun their frame slot. */
        if(tok==T_ARRAY||tok==T_FIXED)
            elem_size=arm_array_slot_size((int)(unsigned char)n->char_value);
        kind=VK_ARRAY;
    } else {
        elem_size=elem_size_from_token(tok);
        if(kind==VK_PTR&&n->string_value) elem_size=arm_type_size_name(n->string_value);
        if(st) { kind=VK_STRUCT; elem_size=8; array_len=(st->size+7)/8; }
        else {
            int inferred=arm_infer_struct_size(g,n->token.text);
            if(inferred>8) { kind=VK_STRUCT; elem_size=8; array_len=(inferred+7)/8; }
        }
    }
    bool is_dyn=(tok==T_DYN);
    int dyn_cap=is_dyn?(array_len<8?8:array_len):array_len;
    int alloc_bytes=(is_dyn?dyn_cap:array_len)*elem_size+(is_dyn?16:0);
    int off=arm_alloc_local(g,alloc_bytes);
    arm_push_local(g,n->token.text,n->string_value,kind,off,alloc_bytes,elem_size,array_len);
    Sym* newsym=arm_find_sym(g,n->token.text);
    if(newsym) { newsym->is_dyn=is_dyn; newsym->dyn_cap=dyn_cap; }
    if(is_dyn) {
        /* Metadata: [len][cap] just past the element storage. */
        arm_emit_addr(g,9,29,off+dyn_cap*elem_size);
        a64_mov_imm(&g->code,10,(uint64_t)array_len);
        a64_str_x(&g->code,10,9,0);
        a64_mov_imm(&g->code,10,(uint64_t)dyn_cap);
        a64_str_x(&g->code,10,9,8);
    }
    if(is_array&&values&&values->type==AST_STRUCT_LITERAL) {
        bool any_array=(tok==T_ARRAY||tok==T_FIXED) &&
                       (int)(unsigned char)n->char_value==T_ANY;
        arm_emit_addr(g,0,29,off);
        int aidx=arm_save_scratch(g,0);
        for(int i=0;i<values->child_count&&i<array_len;i++) {
            if(any_array) {
                /* Store both the payload and the tag of each boxed element. */
                arm_store_any_field(g,aidx,i*elem_size,values->children[i]);
                continue;
            }
            arm_expr(g,values->children[i]);
            arm_load_scratch(g,9,aidx);
            a64_mov_imm(&g->code,10,(uint64_t)(i*elem_size));
            a64_add_reg(&g->code,10,9,10);
            arm_store_value(g,10,0,elem_size);
        }
        arm_release_scratch(g,aidx);
        return;
    }
    if(!is_array&&init&&init->type==AST_STRUCT_LITERAL&&st) {
        arm_emit_addr(g,0,29,off);
        int aidx=arm_save_scratch(g,0);
        for(int i=0;i<init->child_count&&i<st->field_count;i++) {
            StructField* f=&st->fields[i];
            ASTNode* val=init->children[i];
            if(f->array_size>0&&f->field_type==T_ANY&&val&&
               val->type==AST_STRUCT_LITERAL) {
                for(int j=0;j<f->array_size&&j<val->child_count;j++)
                    arm_store_any_field(g,aidx,f->offset+j*16,val->children[j]);
                continue;
            }
            if(f->field_type==T_ANY) {
                arm_store_any_field(g,aidx,f->offset,val);
                continue;
            }
            arm_expr(g,val);
            a64_mov_reg(&g->code,10,0);
            arm_load_scratch(g,9,aidx);
            a64_mov_imm(&g->code,11,(uint64_t)f->offset);
            a64_add_reg(&g->code,10,9,11);
            arm_store_value(g,10,0,elem_size_from_token(f->field_type));
        }
        arm_release_scratch(g,aidx);
        return;
    }
    /* Struct copy, with `move` clearing the source. */
    {
        ASTNode* srcnode=init;
        bool moving=false;
        if(init&&init->type==AST_UNARY_EXPR&&init->token.text&&!strcmp(init->token.text,"move")) {
            srcnode=init->child_count?init->children[0]:NULL;
            moving=true;
        }
        if(!is_array&&kind!=VK_ANY&&srcnode&&(srcnode->type==AST_IDENTIFIER_EXPR||srcnode->type==NODE_IDENT)) {
            Sym* src=arm_find_sym(g,srcnode->token.text);
            if(src&&src->kind==VK_STRUCT) {
                arm_emit_addr(g,0,29,off);
                int didx=arm_save_scratch(g,0);
                arm_emit_addr(g,0,29,src->offset);
                int bytes=st?st->size:src->size;
                int words=(bytes+7)/8;
                if(words>(src->size+7)/8) words=(src->size+7)/8;
                for(int w=0;w<words;w++) {
                    a64_ldr_x(&g->code,10,0,(uint32_t)(w*8));
                    arm_load_scratch(g,9,didx);
                    a64_str_x(&g->code,10,9,(uint32_t)(w*8));
                }
                if(moving) {
                    a64_mov_imm(&g->code,10,0);
                    for(int w=0;w<words;w++)
                        a64_str_x(&g->code,10,0,(uint32_t)(w*8));
                }
                arm_release_scratch(g,didx);
                return;
            }
        }
    }
    if(!is_array&&init&&init->type==AST_CALL_EXPR&&(kind==VK_STRUCT||kind==VK_ANY)) {
        /* Let an aggregate-returning callee write straight into this local. */
        char tbuf[256];
        const char* target=arm_call_target(g,init,tbuf,sizeof(tbuf),true);
        arm_emit_addr(g,0,29,off);
        a64_mov_reg(&g->code,8,0);
        arm_emit_call(g,init,target);
        return;
    }
    if(!is_array&&init&&kind==VK_ANY) {
        arm_emit_addr(g,0,29,off);
        int didx=arm_save_scratch(g,0);
        arm_materialize_any(g,init);
        arm_load_scratch(g,9,didx);
        a64_ldr_x(&g->code,10,0,0);
        a64_str_x(&g->code,10,9,0);
        a64_ldr_x(&g->code,10,0,8);
        a64_str_x(&g->code,10,9,8);
        arm_release_scratch(g,didx);
        return;
    }
    if(!is_array&&init) {
        arm_expr(g,init);
        arm_store_sym(g,arm_find_sym(g,n->token.text),0);
    }
}
static void arm_stmt(ArmGen* g, ASTNode* n) {
    if(!n) return;
    switch(n->type) {
        case AST_BLOCK: {
            int base=arm_enter_scope(g);
            for(int i=0;i<n->child_count;i++) arm_stmt(g,n->children[i]);
            arm_leave_scope(g,base); break;
        }
        case AST_VAR_DECL: arm_var_decl(g,n); break;
        case AST_EXPR_STMT: if(n->child_count>0) arm_expr(g,n->children[0]); break;
        case AST_ASM_STMT: {
            const char* txt=n->string_value;
            if(n->child_count>0) {
                ASTNode* c=n->children[0];
                if(c->string_value&&*c->string_value) txt=c->string_value;
                else if(c->token.text) txt=c->token.text;
            }
            arm_emit_asm(g,txt); break;
        }
        case AST_ASYNC_STMT: case AST_SPAWN_STMT:
            arm_task_fork(g,n->child_count>0?n->children[0]:NULL); break;
        case AST_PARALLEL_STMT:
            arm_task_fork(g,n->child_count>0?n->children[0]:NULL);
            arm_task_join(g,false); break;
        case AST_AWAIT_STMT:
            if(n->child_count>0) arm_expr(g,n->children[0]);
            arm_task_join(g,n->child_count==0); break;
        case AST_RETURN_STMT: {
            ASTNode* e=n->child_count?n->children[0]:NULL;
            if(g->current_sret_offset && g->current_func) {
                int bytes=g->current_func->ret_size;
                arm_emit_addr(g,9,29,g->current_sret_offset);
                a64_ldr_x(&g->code,9,9,0);
                if(g->current_func->ret_kind==VK_ANY) {
                    a64_mov_reg(&g->code,11,9);
                    int didx=arm_save_scratch(g,11);
                    arm_materialize_any(g,e);
                    arm_load_scratch(g,9,didx);
                    a64_ldr_x(&g->code,10,0,0);
                    a64_str_x(&g->code,10,9,0);
                    a64_ldr_x(&g->code,10,0,8);
                    a64_str_x(&g->code,10,9,8);
                    arm_release_scratch(g,didx);
                    arm_flush_defers(g);
                    arm_emit_addr(g,9,29,g->current_sret_offset);
                    a64_ldr_x(&g->code,9,9,0);
                    a64_mov_reg(&g->code,0,9);
                    arm_epilogue(g); break;
                }
                if(e&&e->type==AST_STRUCT_LITERAL) {
                    a64_mov_reg(&g->code,11,9); /* arm_save_scratch uses x9 as its base */
                    int didx=arm_save_scratch(g,11);
                    for(int i=0;i<e->child_count;i++) {
                        arm_expr(g,e->children[i]);
                        arm_load_scratch(g,9,didx);
                        a64_str_x(&g->code,0,9,(uint32_t)(i*8));
                    }
                    arm_release_scratch(g,didx);
                } else if(e&&(e->type==AST_IDENTIFIER_EXPR||e->type==NODE_IDENT)) {
                    Sym* s=arm_find_sym(g,e->token.text);
                    if(s&&s->kind==VK_STRUCT) {
                        arm_emit_addr(g,10,29,s->offset);
                        for(int w=0;w<bytes/8;w++) {
                            a64_ldr_x(&g->code,11,10,(uint32_t)(w*8));
                            a64_str_x(&g->code,11,9,(uint32_t)(w*8));
                        }
                    } else {
                        if(e) arm_expr(g,e);
                        else a64_mov_imm(&g->code,0,0);
                        a64_str_x(&g->code,0,9,0);
                    }
                } else if(e&&e->type==AST_CALL_EXPR) {
                    /* Let a nested aggregate-returning call use our result slot. */
                    char tbuf[256];
                    const char* target=arm_call_target(g,e,tbuf,sizeof(tbuf),true);
                    a64_mov_reg(&g->code,8,9);
                    arm_emit_call(g,e,target);
                } else {
                    if(e) arm_expr(g,e); else a64_mov_imm(&g->code,0,0);
                    a64_str_x(&g->code,0,9,0);
                }
                arm_flush_defers(g);
                arm_emit_addr(g,9,29,g->current_sret_offset);
                a64_ldr_x(&g->code,9,9,0);
                a64_mov_reg(&g->code,0,9);
            } else {
                if(n->child_count>0) arm_expr(g,n->children[0]); else a64_mov_imm(&g->code,0,0);
                if(g->ret_save_offset) {
                    arm_emit_addr(g,9,29,g->ret_save_offset);
                    a64_str_x(&g->code,0,9,0);
                }
                arm_flush_defers(g);
                if(g->ret_save_offset) {
                    arm_emit_addr(g,9,29,g->ret_save_offset);
                    a64_ldr_x(&g->code,0,9,0);
                }
            }
            arm_epilogue(g); break;
        }
        case AST_IF_STMT: {
            if(n->child_count>0) arm_expr(g,n->children[0]);
            size_t to_else=0,to_end=0;
            if(n->child_count>1) {
                a64_cmp_imm(&g->code,0,0);
                to_else=a64_bcond(&g->code,A64_EQ);
                arm_stmt(g,n->children[1]);
                if(n->child_count>2) to_end=a64_b(&g->code);
                a64_patch_cond(g->code.data,to_else,a64_size(&g->code));
            } else {
                a64_cmp_imm(&g->code,0,0);
                to_else=a64_bcond(&g->code,A64_EQ);
                a64_patch_cond(g->code.data,to_else,a64_size(&g->code));
            }
            if(n->child_count>2) {
                arm_stmt(g,n->children[2]);
                a64_patch_branch(g->code.data,to_end,a64_size(&g->code));
            }
            break;
        }
        case AST_WHILE_STMT: {
            int li=g->loop_depth<ARM_MAX_LOOPS?g->loop_depth:-1;
            if(li>=0) memset(&g->loops[li],0,sizeof(LoopFrame));
            g->loop_depth++;
            if(n->bool_value) {
                /* do { body } while (cond): the body always runs once and
                   `continue` jumps to the trailing condition check. */
                size_t top=a64_size(&g->code);
                if(n->child_count>1) arm_stmt(g,n->children[1]);
                size_t cond=a64_size(&g->code);
                if(n->child_count>0) arm_expr(g,n->children[0]); else a64_mov_imm(&g->code,0,1);
                a64_cmp_imm(&g->code,0,0);
                size_t again=a64_bcond(&g->code,A64_NE);
                size_t end=a64_size(&g->code);
                a64_patch_cond(g->code.data,again,top);
                if(li>=0) {
                    for(int i=0;i<g->loops[li].nb;i++) a64_patch_branch(g->code.data,g->loops[li].breaks[i],end);
                    for(int i=0;i<g->loops[li].nc;i++) a64_patch_branch(g->code.data,g->loops[li].continues[i],cond);
                }
            } else {
                size_t top=a64_size(&g->code);
                if(n->child_count>0) arm_expr(g,n->children[0]); else a64_mov_imm(&g->code,0,1);
                a64_cmp_imm(&g->code,0,0);
                size_t to_end=a64_bcond(&g->code,A64_EQ);
                if(n->child_count>1) arm_stmt(g,n->children[1]);
                size_t back=a64_b(&g->code);
                size_t end=a64_size(&g->code);
                a64_patch_cond(g->code.data,to_end,end);
                a64_patch_branch(g->code.data,back,top);
                if(li>=0) {
                    for(int i=0;i<g->loops[li].nb;i++) a64_patch_branch(g->code.data,g->loops[li].breaks[i],end);
                    for(int i=0;i<g->loops[li].nc;i++) a64_patch_branch(g->code.data,g->loops[li].continues[i],top);
                }
            }
            g->loop_depth--;
            break;
        }
        case AST_FOR_STMT: {
            int base=arm_enter_scope(g);
            if(n->child_count>0) {
                if(n->children[0]->type==AST_VAR_DECL) arm_var_decl(g,n->children[0]);
                else arm_expr(g,n->children[0]);
            }
            int li=g->loop_depth<ARM_MAX_LOOPS?g->loop_depth:-1;
            if(li>=0) memset(&g->loops[li],0,sizeof(LoopFrame));
            g->loop_depth++;
            size_t cond=a64_size(&g->code);
            if(n->child_count>1) arm_expr(g,n->children[1]); else a64_mov_imm(&g->code,0,1);
            a64_cmp_imm(&g->code,0,0);
            size_t to_end=a64_bcond(&g->code,A64_EQ);
            if(n->child_count>3) arm_stmt(g,n->children[3]);
            size_t cont=a64_size(&g->code);
            if(n->child_count>2) arm_expr(g,n->children[2]);
            size_t back=a64_b(&g->code);
            size_t end=a64_size(&g->code);
            a64_patch_cond(g->code.data,to_end,end);
            a64_patch_branch(g->code.data,back,cond);
            if(li>=0) {
                for(int i=0;i<g->loops[li].nb;i++) a64_patch_branch(g->code.data,g->loops[li].breaks[i],end);
                for(int i=0;i<g->loops[li].nc;i++) a64_patch_branch(g->code.data,g->loops[li].continues[i],cont);
            }
            g->loop_depth--;
            arm_leave_scope(g,base); break;
        }
        case AST_BREAK_STMT:
            if(g->loop_depth>0&&g->loops[g->loop_depth-1].nb<64) {
                size_t p=a64_b(&g->code);
                g->loops[g->loop_depth-1].breaks[g->loops[g->loop_depth-1].nb++]=p;
            }
            break;
        case AST_CONTINUE_STMT:
            if(g->loop_depth>0&&g->loops[g->loop_depth-1].nc<64) {
                size_t p=a64_b(&g->code);
                g->loops[g->loop_depth-1].continues[g->loops[g->loop_depth-1].nc++]=p;
            }
            break;
        case AST_GOTO_STMT:
            arm_add_reloc(g,n->token.text?n->token.text:"",a64_b(&g->code),RELOC_BRANCH); break;
        case AST_LABEL_DECL:
            arm_add_label(g,n->token.text?n->token.text:"",a64_size(&g->code)); break;
        case AST_FREE_STMT:
            if(n->child_count>0) arm_expr(g,n->children[0]); else a64_mov_imm(&g->code,0,0);
            arm_add_reloc(g,"mag_free",a64_bl(&g->code),RELOC_BRANCH); break;
        case AST_ASSERT_STMT:
            if(n->child_count>0) arm_expr(g,n->children[0]); else a64_mov_imm(&g->code,0,1);
            a64_cmp_imm(&g->code,0,0);
            {
                size_t p=a64_bcond(&g->code,A64_NE);
                arm_add_reloc(g,"mag_abort",a64_bl(&g->code),RELOC_BRANCH);
                a64_patch_cond(g->code.data,p,a64_size(&g->code));
            }
            break;
        case AST_UNSAFE_BLOCK:
            for(int i=0;i<n->child_count;i++) arm_stmt(g,n->children[i]);
            break;
        case AST_DEFER_STMT:
            if(n->child_count>0 && g->defer_count<256)
                g->defers[g->defer_count++]=n->children[0];
            break;
        case AST_TRY_STMT: {
            int id=g->try_counter++;
            char catch_lbl[64], finally_lbl[64], end_lbl[64];
            snprintf(catch_lbl,sizeof(catch_lbl),".Larm_try_catch_%d",id);
            snprintf(finally_lbl,sizeof(finally_lbl),".Larm_try_finally_%d",id);
            snprintf(end_lbl,sizeof(end_lbl),".Larm_try_end_%d",id);
            char prev[128];
            snprintf(prev,sizeof(prev),"%s",g->active_catch);
            snprintf(g->active_catch,sizeof(g->active_catch),"%s",catch_lbl);
            if(n->child_count>0 && n->children[0]) arm_stmt(g,n->children[0]);
            arm_add_reloc(g,finally_lbl,a64_b(&g->code),RELOC_BRANCH);
            arm_add_label(g,catch_lbl,a64_size(&g->code));
            /* Throws inside catch propagate to the enclosing try. */
            snprintf(g->active_catch,sizeof(g->active_catch),"%s",prev);
            if(n->child_count>1 && n->children[1]) arm_stmt(g,n->children[1]);
            arm_add_reloc(g,finally_lbl,a64_b(&g->code),RELOC_BRANCH);
            arm_add_label(g,finally_lbl,a64_size(&g->code));
            if(n->child_count>2 && n->children[2]) arm_stmt(g,n->children[2]);
            arm_add_label(g,end_lbl,a64_size(&g->code));
            break;
        }
        case AST_THROW_STMT:
            if(n->child_count>0 && n->children[0]) arm_expr(g,n->children[0]);
            else a64_mov_imm(&g->code,0,0);
            if(g->active_catch[0])
                arm_add_reloc(g,g->active_catch,a64_b(&g->code),RELOC_BRANCH);
            else arm_unhandled_throw(g);
            break;
        case AST_FUNC_DECL: case AST_STRUCT_DECL: case AST_CLASS_DECL:
        case NODE_CLASS_DECL: case AST_USE_DECL: case AST_EXPORT_DECL:
            break;
        default: arm_expr(g,n); break;
    }
}
static void arm_emit_function(ArmGen* g, ASTNode* n) {
    if(!n||n->child_count<1) return;
    Func* fn=n->token.text?arm_find_func(g,n->token.text):NULL;
    Func* saved_func=g->current_func;
    int saved_sret=g->current_sret_offset;
    int saved_ret_save=g->ret_save_offset;
    char saved_type[128];
    snprintf(saved_type,sizeof(saved_type),"%s",g->current_type);
    ASTNode* saved_defers[256];
    int saved_defer_count=g->defer_count;
    if(saved_defer_count>0)
        memcpy(saved_defers,g->defers,(size_t)saved_defer_count*sizeof(ASTNode*));
    char saved_catch[128];
    snprintf(saved_catch,sizeof(saved_catch),"%s",g->active_catch);
    g->current_func=fn;
    g->current_sret_offset=0;
    g->defer_count=0;
    g->active_catch[0]=0;
    g->current_type[0]=0;
    int base=arm_enter_scope(g);
    size_t sub=arm_prologue(g);
    g->local_bytes=0; g->scratch_depth=0; g->epilogue_count=0;
    g->ret_save_offset=arm_alloc_local(g,8);
    if(fn&&fn->ret_size>0) {
        int off=arm_alloc_local(g,8);
        g->current_sret_offset=off;
        arm_emit_addr(g,9,29,off);
        a64_str_x(&g->code,8,9,0);
    }
    int last=n->child_count-1;
    int nparams=last;
    if(nparams>511) {
        fprintf(stderr,"[arm64] function '%s' has %d parameters (limit 511)\n",
                fn&&fn->name?fn->name:"?",nparams);
        g->abi_error=true;
        nparams=511;
    }
    for(int i=0;i<nparams;i++) {
        ASTNode* p=n->children[i];
        if(p->token.text &&
           (!strcmp(p->token.text,"this")||!strcmp(p->token.text,"self")) &&
           p->string_value)
            snprintf(g->current_type,sizeof(g->current_type),"%s",p->string_value);
        ValueKind kind=kind_from_token((int)p->int_value);
        int elem=(kind==VK_CHAR)?1:8;
        if(kind==VK_PTR&&p->string_value&&!strcmp(p->string_value,"char")) elem=1;
        int is_any=(kind==VK_ANY);
        int off=arm_alloc_local(g,is_any?16:8);
        arm_push_local(g,p->token.text,p->string_value,kind,off,is_any?16:8,elem,1);
        Sym* sym=arm_find_sym(g,p->token.text);
        /* Entry SP is x29+16 after the standard prologue; stack arguments
           start there (AAPCS64). */
        int src_reg=i<8?i:10;
        if(i>=8) {
            arm_emit_addr(g,10,29,16+8*(i-8));
            a64_ldr_x(&g->code,10,10,0);
        }
        if(is_any) {
            /* Caller passes a pointer to a 16-byte box; copy it into our slot. */
            arm_emit_addr(g,9,29,off);
            if(i<8) {
                a64_ldr_x(&g->code,10,i,0);
                a64_str_x(&g->code,10,9,0);
                a64_ldr_x(&g->code,11,i,8);
                a64_str_x(&g->code,11,9,8);
            } else {
                a64_ldr_x(&g->code,11,10,8);
                a64_str_x(&g->code,10,9,0);
                a64_str_x(&g->code,11,9,8);
            }
        } else arm_store_sym(g,sym,src_reg);
    }
    arm_stmt(g,n->children[last]);
    arm_flush_defers(g);
    /* Falling off the end of a function mirrors an explicit `return 0` for
       scalar functions and returns the hidden destination pointer for
       aggregate-returning functions. */
    if(g->current_func && g->current_func->ret_size>0) {
        arm_emit_addr(g,9,29,g->current_sret_offset);
        a64_ldr_x(&g->code,0,9,0);
    } else {
        a64_mov_imm(&g->code,0,0);
    }
    arm_epilogue(g);
    arm_patch_frame(g,sub,align16u(ARM_LOCAL_BASE+g->local_bytes));
    arm_leave_scope(g,base);
    g->current_func=saved_func;
    g->current_sret_offset=saved_sret;
    g->ret_save_offset=saved_ret_save;
    g->defer_count=saved_defer_count;
    if(saved_defer_count>0)
        memcpy(g->defers,saved_defers,(size_t)saved_defer_count*sizeof(ASTNode*));
    snprintf(g->active_catch,sizeof(g->active_catch),"%s",saved_catch);
    snprintf(g->current_type,sizeof(g->current_type),"%s",saved_type);
}

/* ------------------------------------------------------------------ */
/* Runtime helpers, emitted as machine code                           */
/* ------------------------------------------------------------------ */

#define HEAP_BASE  0x500000ULL
#define HEAP_SIZE  0x100000ULL

static size_t rt_bl(ArmGen* g, const char* name) {
    size_t pos = a64_bl(&g->code);
    arm_add_reloc(g, name, pos, RELOC_BRANCH);
    return pos;
}

/* x0 = NUL-terminated string -> x0 = length */
static void rt_strlen(A64Buf* c) {
    a64_mov_reg(c, 9, 0);
    a64_mov_imm(c, 10, 0);
    size_t loop = a64_size(c);
    a64_add_reg(c, 12, 9, 10);
    a64_ldrb(c, 11, 12, 0);
    size_t p = a64_cbz(c, 11);
    a64_add_imm(c, 10, 10, 1);
    size_t back = a64_b(c);
    a64_patch_branch(c->data, back, loop);
    a64_patch_cb(c->data, p, a64_size(c));
    a64_mov_reg(c, 0, 10);
    a64_ret(c);
}

/* write(1, x0, 1) */
static void rt_print_char(A64Buf* c) {
    a64_prologue(c, 16);
    a64_sub_imm(c, 9, 29, 1);
    a64_strb(c, 0, 9, 0);
    a64_mov_imm(c, 0, 1);
    a64_mov_reg(c, 1, 9);
    a64_mov_imm(c, 2, 1);
    a64_mov_imm(c, 8, 64);
    a64_svc(c);
    a64_epilogue(c, 16);
}

/* x0 = unsigned integer -> decimal digits */
static void rt_print_uint(A64Buf* c) {
    a64_prologue(c, 40);
    a64_mov_reg(c, 9, 29);
    a64_sub_imm(c, 9, 9, 32);     /* buffer start */
    a64_mov_reg(c, 10, 9);        /* current write position */
    a64_mov_imm(c, 12, 10);
    size_t loop = a64_size(c);
    a64_udiv(c, 13, 0, 12);
    a64_mul(c, 14, 13, 12);
    a64_sub_reg(c, 14, 0, 14);    /* remainder */
    a64_mov_imm(c, 15, 48);       /* '0' */
    a64_add_reg(c, 14, 14, 15);
    a64_sub_imm(c, 10, 10, 1);
    a64_strb(c, 14, 10, 0);
    a64_mov_reg(c, 0, 13);
    size_t again = a64_cbnz(c, 0);
    a64_patch_cb(c->data, again, loop);
    a64_mov_reg(c, 2, 9);
    a64_sub_reg(c, 2, 2, 10);     /* length */
    a64_mov_imm(c, 0, 1);
    a64_mov_reg(c, 1, 10);
    a64_mov_imm(c, 8, 64);
    a64_svc(c);
    a64_epilogue(c, 40);
}

/* x0 = pointer to NUL-terminated string */
static void rt_print_string(A64Buf* c) {
    a64_prologue(c, 16);
    a64_mov_reg(c, 9, 0);
    a64_mov_reg(c, 13, 0);        /* original pointer */
    size_t loop = a64_size(c);
    a64_ldrb(c, 11, 9, 0);
    size_t p = a64_cbz(c, 11);
    a64_add_imm(c, 9, 9, 1);
    size_t back = a64_b(c);
    a64_patch_branch(c->data, back, loop);
    a64_patch_cb(c->data, p, a64_size(c));
    a64_mov_reg(c, 2, 9);
    a64_sub_reg(c, 2, 2, 13);     /* length */
    a64_mov_imm(c, 0, 1);
    a64_mov_reg(c, 1, 13);
    a64_mov_imm(c, 8, 64);
    a64_svc(c);
    a64_epilogue(c, 16);
}

static void arm_emit_runtime(ArmGen* g) {
    A64Buf* c = &g->code;

    arm_add_label(g, "mag_strlen", a64_size(c));
    rt_strlen(c);

    arm_add_label(g, "mag_print_char", a64_size(c));
    rt_print_char(c);

    arm_add_label(g, "mag_print_uint", a64_size(c));
    rt_print_uint(c);

    arm_add_label(g, "mag_print_str", a64_size(c));
    rt_print_string(c);

    /* mag_print_fd: x0 = string, x1 = fd */
    arm_add_label(g, "mag_print_fd", a64_size(c));
    a64_prologue(c, 24);
    a64_mov_reg(c, 9, 0);         /* current pointer */
    a64_mov_reg(c, 12, 0);        /* original pointer */
    a64_mov_reg(c, 10, 1);        /* fd */
    size_t pfd = a64_size(c);
    a64_ldrb(c, 11, 9, 0);
    size_t pfdz = a64_cbz(c, 11);
    a64_add_imm(c, 9, 9, 1);
    size_t pfdback = a64_b(c);
    a64_patch_branch(c->data, pfdback, pfd);
    a64_patch_cb(c->data, pfdz, a64_size(c));
    a64_mov_reg(c, 2, 9);
    a64_sub_reg(c, 2, 2, 12);     /* length */
    a64_mov_reg(c, 1, 10);
    a64_mov_imm(c, 0, 1);
    a64_mov_imm(c, 8, 64);
    a64_svc(c);
    a64_epilogue(c, 24);

    /* mag_print_int: x0 = signed integer */
    arm_add_label(g, "mag_print_int", a64_size(c));
    a64_prologue(c, 16);
    a64_sub_imm(c, 10, 29, 8);
    a64_str_x(c, 0, 10, 0);       /* save value across print_char */
    a64_cmp_imm(c, 0, 0);
    size_t nonneg = a64_bcond(c, A64_GE);
    a64_mov_imm(c, 0, 45);        /* '-' */
    rt_bl(g, "mag_print_char");
    a64_sub_imm(c, 10, 29, 8);
    a64_ldr_x(c, 9, 10, 0);
    a64_sub_reg(c, 0, 31, 9);
    a64_sub_imm(c, 10, 29, 8);
    a64_str_x(c, 0, 10, 0);       /* store the magnitude */
    a64_patch_cond(c->data, nonneg, a64_size(c));
    a64_sub_imm(c, 10, 29, 8);
    a64_ldr_x(c, 0, 10, 0);
    rt_bl(g, "mag_print_uint");
    a64_epilogue(c, 16);

    /* mag_print_float: x0 = IEEE-754 single bit pattern.  Matches x86_64:
       four rounded fraction digits with trailing zeros removed. */
    arm_add_label(g, "mag_print_float", a64_size(c));
    a64_prologue(c, 64);
    a64_mov_reg(c, 9, 0);         /* bits */
    a64_mov_imm(c, 10, 0x7F800000ULL);
    a64_and_reg(c, 11, 9, 10);
    a64_cmp_reg(c, 11, 10);
    size_t finite = a64_bcond(c, A64_NE);
    /* exponent is all ones: nan or inf */
    a64_mov_imm(c, 12, 0x7FFFFFULL);
    a64_and_reg(c, 12, 9, 12);
    a64_cmp_imm(c, 12, 0);
    size_t inf_case = a64_bcond(c, A64_EQ);
    arm_emit_string_addr(g, "nan");
    rt_bl(g, "mag_print_str");
    size_t nan_end = a64_b(&g->code);
    a64_patch_cond(c->data, inf_case, a64_size(c));
    a64_mov_imm(c, 10, 0x80000000ULL);
    a64_and_reg(c, 11, 9, 10);
    size_t inf_positive = a64_cbz(c, 11);
    a64_mov_imm(c, 0, 45);
    rt_bl(g, "mag_print_char");
    a64_patch_cb(c->data, inf_positive, a64_size(c));
    arm_emit_string_addr(g, "inf");
    rt_bl(g, "mag_print_str");
    size_t inf_end = a64_b(&g->code);

    a64_patch_cond(c->data, finite, a64_size(c));
    a64_mov_imm(c, 10, 0x80000000ULL);
    a64_and_reg(c, 13, 9, 10);    /* sign flag */
    a64_sub_imm(c, 10, 29, 56);
    a64_str_x(c, 13, 10, 0);
    a64_mov_imm(c, 10, 0x7FFFFFFFULL);
    a64_and_reg(c, 11, 9, 10);    /* magnitude bits */
    a64_fmov_s_w(c, 0, 11);

    /* whole = trunc(magnitude); fraction = magnitude - whole. */
    a64_fcvtzs(c, 11, 0);
    a64_scvtf(c, 1, 11);
    a64_fsub(c, 0, 0, 1);
    /* scaled = floor(fraction * 20000 + 1) / 2, i.e. round to 4 digits. */
    a64_mov_imm(c, 10, 0x469C4000ULL); /* 20000.0f */
    a64_fmov_s_w(c, 1, 10);
    a64_fmul(c, 0, 0, 1);
    a64_mov_imm(c, 10, 0x3F800000ULL); /* 1.0f */
    a64_fmov_s_w(c, 1, 10);
    a64_fadd(c, 0, 0, 1);
    a64_fcvtzs(c, 9, 0);
    a64_lsr_imm(c, 9, 9, 1);
    a64_mov_imm(c, 10, 10000);
    a64_cmp_reg(c, 9, 10);
    size_t no_carry = a64_bcond(c, A64_LT);
    a64_add_imm(c, 11, 11, 1);
    a64_mov_imm(c, 9, 0);
    a64_patch_cond(c->data, no_carry, a64_size(c));

    a64_sub_imm(c, 10, 29, 8);
    a64_str_x(c, 9, 10, 0);       /* rounded fraction 0..9999 */
    a64_sub_imm(c, 10, 29, 16);
    a64_str_x(c, 11, 10, 0);      /* whole part */

    /* Precompute the four decimal digits before any helper call. */
    a64_mov_reg(c, 12, 9);
    a64_mov_imm(c, 15, 1000);
    a64_udiv(c, 13, 12, 15);
    a64_sub_imm(c, 10, 29, 24); a64_str_x(c, 13, 10, 0);
    a64_mul(c, 14, 13, 15);
    a64_sub_reg(c, 12, 12, 14);
    a64_mov_imm(c, 15, 100);
    a64_udiv(c, 13, 12, 15);
    a64_sub_imm(c, 10, 29, 32); a64_str_x(c, 13, 10, 0);
    a64_mul(c, 14, 13, 15);
    a64_sub_reg(c, 12, 12, 14);
    a64_mov_imm(c, 15, 10);
    a64_udiv(c, 13, 12, 15);
    a64_sub_imm(c, 10, 29, 40); a64_str_x(c, 13, 10, 0);
    a64_mul(c, 14, 13, 15);
    a64_sub_reg(c, 13, 12, 14);
    a64_sub_imm(c, 10, 29, 48); a64_str_x(c, 13, 10, 0);

    /* Optional leading minus. */
    a64_sub_imm(c, 10, 29, 56);
    a64_ldr_x(c, 13, 10, 0);
    size_t finite_positive = a64_cbz(c, 13);
    a64_mov_imm(c, 0, 45);
    rt_bl(g, "mag_print_char");
    a64_patch_cb(c->data, finite_positive, a64_size(c));

    a64_sub_imm(c, 10, 29, 16);
    a64_ldr_x(c, 0, 10, 0);
    rt_bl(g, "mag_print_uint");
    a64_mov_imm(c, 0, 46);        /* '.' */
    rt_bl(g, "mag_print_char");

    a64_sub_imm(c, 10, 29, 24);
    a64_ldr_x(c, 12, 10, 0);
    a64_mov_imm(c, 10, 48);
    a64_add_reg(c, 0, 12, 10);
    rt_bl(g, "mag_print_char");

    /* Print digit 1 only when digits 2 or 3 are nonzero. */
    a64_sub_imm(c, 10, 29, 32); a64_ldr_x(c, 12, 10, 0);
    a64_sub_imm(c, 10, 29, 40); a64_ldr_x(c, 13, 10, 0);
    a64_sub_imm(c, 10, 29, 48); a64_ldr_x(c, 14, 10, 0);
    a64_orr_reg(c, 15, 13, 14); a64_orr_reg(c, 15, 12, 15);
    a64_cmp_imm(c, 15, 0);
    size_t skip_d1 = a64_bcond(c, A64_EQ);
    a64_mov_imm(c, 10, 48);
    a64_add_reg(c, 0, 12, 10);
    rt_bl(g, "mag_print_char");
    a64_patch_cond(c->data, skip_d1, a64_size(c));

    /* Print digit 2 only when digit 3 is nonzero. */
    a64_sub_imm(c, 10, 29, 40); a64_ldr_x(c, 12, 10, 0);
    a64_sub_imm(c, 10, 29, 48); a64_ldr_x(c, 13, 10, 0);
    a64_orr_reg(c, 15, 12, 13);
    a64_cmp_imm(c, 15, 0);
    size_t skip_d2 = a64_bcond(c, A64_EQ);
    a64_mov_imm(c, 10, 48);
    a64_add_reg(c, 0, 12, 10);
    rt_bl(g, "mag_print_char");
    a64_patch_cond(c->data, skip_d2, a64_size(c));

    a64_sub_imm(c, 10, 29, 48);
    a64_ldr_x(c, 12, 10, 0);
    size_t skip_d3 = a64_cbz(c, 12);
    a64_mov_imm(c, 10, 48);
    a64_add_reg(c, 0, 12, 10);
    rt_bl(g, "mag_print_char");
    a64_patch_cb(c->data, skip_d3, a64_size(c));

    a64_patch_branch(c->data, nan_end, a64_size(c));
    a64_patch_branch(c->data, inf_end, a64_size(c));
    a64_epilogue(c, 64);

    /* mag_print_any: x0 = pointer to a { payload, tag } box */
    arm_add_label(g, "mag_print_any", a64_size(c));
    a64_prologue(c, 16);
    a64_sub_imm(c, 10, 29, 8);
    a64_str_x(c, 0, 10, 0);
    a64_ldr_x(c, 1, 0, 8);        /* tag before x0 is overwritten */
    a64_ldr_x(c, 0, 0, 0);
    a64_cmp_imm(c, 1, ANY_TAG_FLOAT);
    size_t any_float = a64_bcond(c, A64_EQ);
    a64_cmp_imm(c, 1, ANY_TAG_STRING);
    size_t any_string = a64_bcond(c, A64_EQ);
    a64_cmp_imm(c, 1, ANY_TAG_BOOL);
    size_t any_bool = a64_bcond(c, A64_EQ);
    rt_bl(g, "mag_print_int");
    size_t any_done_int = a64_b(c);
    a64_patch_cond(c->data, any_float, a64_size(c));
    rt_bl(g, "mag_print_float");
    size_t any_done_float = a64_b(c);
    a64_patch_cond(c->data, any_string, a64_size(c));
    rt_bl(g, "mag_print_str");
    size_t any_done_string = a64_b(c);
    a64_patch_cond(c->data, any_bool, a64_size(c));
    size_t any_false = a64_cbz(c, 0);
    arm_emit_string_addr(g, "true");
    rt_bl(g, "mag_print_str");
    size_t any_done_true = a64_b(c);
    a64_patch_cb(c->data, any_false, a64_size(c));
    arm_emit_string_addr(g, "false");
    rt_bl(g, "mag_print_str");
    size_t any_end = a64_size(c);
    a64_patch_branch(c->data, any_done_int, any_end);
    a64_patch_branch(c->data, any_done_float, any_end);
    a64_patch_branch(c->data, any_done_string, any_end);
    a64_patch_branch(c->data, any_done_true, any_end);
    a64_epilogue(c, 16);

    /* mag_strcat2: x0, x1 -> newly allocated concatenation */
    arm_add_label(g, "mag_strcat2", a64_size(c));
    a64_prologue(c, 32);
    a64_sub_imm(c, 10, 29, 8);
    a64_str_x(c, 0, 10, 0);
    a64_sub_imm(c, 10, 29, 16);
    a64_str_x(c, 1, 10, 0);
    rt_bl(g, "mag_strlen");             /* length of a */
    a64_sub_imm(c, 10, 29, 24);
    a64_str_x(c, 0, 10, 0);
    a64_sub_imm(c, 10, 29, 8);
    a64_ldr_x(c, 0, 10, 0);
    rt_bl(g, "mag_strlen");             /* length of b */
    a64_sub_imm(c, 10, 29, 24);
    a64_ldr_x(c, 9, 10, 0);             /* len a */
    a64_add_reg(c, 9, 9, 0);
    a64_add_imm(c, 9, 9, 1);
    a64_mov_reg(c, 0, 9);
    rt_bl(g, "mag_alloc");
    a64_mov_reg(c, 13, 0);              /* destination */
    a64_mov_reg(c, 14, 0);
    a64_sub_imm(c, 10, 29, 8);
    a64_ldr_x(c, 9, 10, 0);             /* source a */
    size_t cp1 = a64_size(c);
    a64_ldrb(c, 15, 9, 0);
    a64_strb(c, 15, 14, 0);
    a64_add_imm(c, 9, 9, 1);
    a64_add_imm(c, 14, 14, 1);
    size_t cp1z = a64_cbnz(c, 15);
    a64_patch_cb(c->data, cp1z, cp1);
    a64_sub_imm(c, 14, 14, 1);          /* overwrite the NUL from string a */
    a64_sub_imm(c, 10, 29, 16);
    a64_ldr_x(c, 9, 10, 0);             /* source b */
    size_t cp2 = a64_size(c);
    a64_ldrb(c, 15, 9, 0);
    a64_strb(c, 15, 14, 0);
    a64_add_imm(c, 9, 9, 1);
    a64_add_imm(c, 14, 14, 1);
    size_t cp2z = a64_cbnz(c, 15);
    a64_patch_cb(c->data, cp2z, cp2);
    a64_mov_reg(c, 0, 13);
    a64_epilogue(c, 32);

    /* mag_any_bin: x3=op, x1=lhs box*, x2=rhs box*, x8=result box* */
    arm_add_label(g, "mag_any_bin", a64_size(c));
    a64_prologue(c, 112);
    a64_sub_imm(c, 10, 29, 8);   a64_str_x(c, 8, 10, 0);
    a64_sub_imm(c, 10, 29, 16);  a64_str_x(c, 3, 10, 0);
    a64_sub_imm(c, 10, 29, 24);  a64_str_x(c, 1, 10, 0);
    a64_sub_imm(c, 10, 29, 32);  a64_str_x(c, 2, 10, 0);
    a64_ldr_x(c, 9, 1, 0);  a64_ldr_x(c, 11, 1, 8);
    a64_ldr_x(c, 12, 2, 0); a64_ldr_x(c, 13, 2, 8);
    a64_sub_imm(c, 10, 29, 40);  a64_str_x(c, 9, 10, 0);
    a64_sub_imm(c, 10, 29, 48);  a64_str_x(c, 11, 10, 0);
    a64_sub_imm(c, 10, 29, 56);  a64_str_x(c, 12, 10, 0);
    a64_sub_imm(c, 10, 29, 64);  a64_str_x(c, 13, 10, 0);

    /* Float path when either operand is a tagged float. */
    a64_cmp_imm(c, 11, ANY_TAG_FLOAT);
    size_t go_float1 = a64_bcond(c, A64_EQ);
    a64_cmp_imm(c, 13, ANY_TAG_FLOAT);
    size_t go_float2 = a64_bcond(c, A64_EQ);

    /* String path only for + and comparisons, when both tags are strings. */
    a64_sub_imm(c, 10, 29, 16); a64_ldr_x(c, 0, 10, 0);
    a64_cmp_imm(c, 0, 92);
    size_t str_plus = a64_bcond(c, A64_EQ);
    a64_cmp_imm(c, 0, 98);
    size_t str_cmp_op = a64_bcond(c, A64_CS);
    a64_b(c); size_t skip_str = a64_size(c) - 4;
    a64_patch_cond(c->data, str_plus, a64_size(c));
    a64_patch_cond(c->data, str_cmp_op, a64_size(c));
    a64_sub_imm(c, 10, 29, 48); a64_ldr_x(c, 9, 10, 0);
    a64_cmp_imm(c, 9, ANY_TAG_STRING);
    size_t not_str1 = a64_bcond(c, A64_NE);
    a64_sub_imm(c, 10, 29, 64); a64_ldr_x(c, 9, 10, 0);
    a64_cmp_imm(c, 9, ANY_TAG_STRING);
    size_t not_str2 = a64_bcond(c, A64_NE);

    /* Split string ops: + -> concat, comparisons -> strcmp. */
    a64_sub_imm(c, 10, 29, 16); a64_ldr_x(c, 0, 10, 0);
    a64_cmp_imm(c, 0, 92);
    size_t str_do_concat = a64_bcond(c, A64_EQ);
    size_t str_do_cmp = a64_b(c);
    a64_patch_cond(c->data, str_do_concat, a64_size(c));

    /* + on strings: concatenate into fresh heap string. */
    a64_sub_imm(c, 10, 29, 40); a64_ldr_x(c, 0, 10, 0);
    a64_sub_imm(c, 10, 29, 56); a64_ldr_x(c, 1, 10, 0);
    rt_bl(g, "mag_strcat2");
    a64_mov_reg(c, 9, 0);
    a64_mov_imm(c, 13, ANY_TAG_STRING);
    size_t str_join_end = a64_b(c);

    /* Comparisons on strings. */
    a64_patch_branch(c->data, str_do_cmp, a64_size(c));
    a64_sub_imm(c, 10, 29, 40); a64_ldr_x(c, 0, 10, 0);
    a64_sub_imm(c, 10, 29, 56); a64_ldr_x(c, 1, 10, 0);
    rt_bl(g, "mag_strcmp");
    a64_sub_imm(c, 10, 29, 16); a64_ldr_x(c, 10, 10, 0);
    a64_cmp_imm(c, 0, 0);
    size_t sc[6];
    int scc[6] = {A64_EQ,A64_NE,A64_LT,A64_LE,A64_GT,A64_GE};
    for (int i=0;i<6;i++) {
        a64_cmp_imm(c, 10, 98+i);
        sc[i] = a64_bcond(c, A64_EQ);
    }
    size_t sj[6];
    for (int i=0;i<6;i++) {
        a64_patch_cond(c->data, sc[i], a64_size(c));
        a64_cmp_imm(c, 0, 0);
        a64_cset(c, 9, scc[i]);
        a64_mov_imm(c, 13, ANY_TAG_INT);
        sj[i] = a64_b(c);
    }
    size_t str_cmp_end = a64_size(c);
    a64_patch_cond(c->data, not_str1, str_cmp_end);
    a64_patch_cond(c->data, not_str2, str_cmp_end);
    a64_patch_branch(c->data, skip_str, str_cmp_end);

    /* Integer path. */
    a64_sub_imm(c, 10, 29, 40); a64_ldr_x(c, 9, 10, 0);
    a64_sub_imm(c, 10, 29, 56); a64_ldr_x(c, 12, 10, 0);
    a64_sub_imm(c, 10, 29, 16); a64_ldr_x(c, 10, 10, 0);
    a64_cmp_imm(c, 10, 92); size_t iadd = a64_bcond(c, A64_EQ);
    a64_cmp_imm(c, 10, 93); size_t isub = a64_bcond(c, A64_EQ);
    a64_cmp_imm(c, 10, 94); size_t imul = a64_bcond(c, A64_EQ);
    a64_cmp_imm(c, 10, 95); size_t idiv = a64_bcond(c, A64_EQ);
    a64_cmp_imm(c, 10, 96); size_t imod = a64_bcond(c, A64_EQ);
    a64_cmp_reg(c, 9, 12);
    size_t ic[6];
    for (int i=0;i<6;i++) {
        a64_cmp_imm(c, 10, 98+i);
        ic[i] = a64_bcond(c, A64_EQ);
    }
    a64_mov_imm(c, 9, 0); a64_mov_imm(c, 13, ANY_TAG_INT);
    size_t ijend = a64_b(c);
    a64_patch_cond(c->data, iadd, a64_size(c));
    a64_add_reg(c, 9, 9, 12); a64_mov_imm(c, 13, ANY_TAG_INT); size_t ij1=a64_b(c);
    a64_patch_cond(c->data, isub, a64_size(c));
    a64_sub_reg(c, 9, 9, 12); a64_mov_imm(c, 13, ANY_TAG_INT); size_t ij2=a64_b(c);
    a64_patch_cond(c->data, imul, a64_size(c));
    a64_mul(c, 9, 9, 12); a64_mov_imm(c, 13, ANY_TAG_INT); size_t ij3=a64_b(c);
    a64_patch_cond(c->data, idiv, a64_size(c));
    size_t any_div0a = a64_cbz(c, 12);
    a64_sdiv(c, 9, 9, 12); a64_mov_imm(c, 13, ANY_TAG_INT); size_t ij4=a64_b(c);
    a64_patch_cb(c->data, any_div0a, a64_size(c));
    rt_bl(g, "mag_divzero");
    a64_patch_cond(c->data, imod, a64_size(c));
    size_t any_div0b = a64_cbz(c, 12);
    a64_mov_imm(c, 14, 0); a64_sdiv(c, 14, 9, 12); a64_mul(c, 14, 14, 12); a64_sub_reg(c, 9, 9, 14);
    a64_mov_imm(c, 13, ANY_TAG_INT); size_t ij5=a64_b(c);
    a64_patch_cb(c->data, any_div0b, a64_size(c));
    rt_bl(g, "mag_divzero");
    size_t icj[6];
    for (int i=0;i<6;i++) {
        a64_patch_cond(c->data, ic[i], a64_size(c));
        a64_cset(c, 9, scc[i]); a64_mov_imm(c, 13, ANY_TAG_INT);
        icj[i]=a64_b(c);
    }
    size_t int_end = a64_size(c);

    /* Float path. */
    a64_patch_cond(c->data, go_float1, a64_size(c));
    a64_patch_cond(c->data, go_float2, a64_size(c));
    a64_sub_imm(c, 10, 29, 40); a64_ldr_x(c, 9, 10, 0);
    a64_sub_imm(c, 10, 29, 48); a64_ldr_x(c, 11, 10, 0);
    a64_cmp_imm(c, 11, ANY_TAG_FLOAT);
    size_t lhs_float = a64_bcond(c, A64_EQ);
    a64_fmov_s_w(c, 0, 9); a64_scvtf(c, 0, 9); a64_fmov_w_s(c, 9, 0);
    a64_patch_cond(c->data, lhs_float, a64_size(c));
    a64_fmov_s_w(c, 0, 9);
    a64_sub_imm(c, 10, 29, 56); a64_ldr_x(c, 12, 10, 0);
    a64_sub_imm(c, 10, 29, 64); a64_ldr_x(c, 13, 10, 0);
    a64_cmp_imm(c, 13, ANY_TAG_FLOAT);
    size_t rhs_float = a64_bcond(c, A64_EQ);
    a64_fmov_s_w(c, 1, 12); a64_scvtf(c, 1, 12); a64_fmov_w_s(c, 12, 1);
    a64_patch_cond(c->data, rhs_float, a64_size(c));
    a64_fmov_s_w(c, 1, 12);
    a64_sub_imm(c, 10, 29, 16); a64_ldr_x(c, 10, 10, 0);
    a64_cmp_imm(c, 10, 92); size_t fadd=a64_bcond(c, A64_EQ);
    a64_cmp_imm(c, 10, 93); size_t fsub=a64_bcond(c, A64_EQ);
    a64_cmp_imm(c, 10, 94); size_t fmul=a64_bcond(c, A64_EQ);
    a64_cmp_imm(c, 10, 95); size_t fdiv=a64_bcond(c, A64_EQ);
    a64_fcmp(c, 0, 1);
    size_t fc[6];
    for (int i=0;i<6;i++) {
        a64_cmp_imm(c, 10, 98+i);
        fc[i]=a64_bcond(c, A64_EQ);
    }
    a64_mov_imm(c, 9, 0); a64_mov_imm(c, 13, ANY_TAG_INT);
    size_t fjend=a64_b(c);
    a64_patch_cond(c->data, fadd, a64_size(c));
    a64_fadd(c,0,0,1); a64_fmov_w_s(c,9,0); a64_mov_imm(c,13,ANY_TAG_FLOAT); size_t fj1=a64_b(c);
    a64_patch_cond(c->data, fsub, a64_size(c));
    a64_fsub(c,0,0,1); a64_fmov_w_s(c,9,0); a64_mov_imm(c,13,ANY_TAG_FLOAT); size_t fj2=a64_b(c);
    a64_patch_cond(c->data, fmul, a64_size(c));
    a64_fmul(c,0,0,1); a64_fmov_w_s(c,9,0); a64_mov_imm(c,13,ANY_TAG_FLOAT); size_t fj3=a64_b(c);
    a64_patch_cond(c->data, fdiv, a64_size(c));
    a64_fdiv(c,0,0,1); a64_fmov_w_s(c,9,0); a64_mov_imm(c,13,ANY_TAG_FLOAT); size_t fj4=a64_b(c);
    size_t fcj[6];
    for (int i=0;i<6;i++) {
        a64_patch_cond(c->data, fc[i], a64_size(c));
        a64_cset(c, 9, scc[i]); a64_mov_imm(c, 13, ANY_TAG_INT);
        fcj[i]=a64_b(c);
    }
    size_t float_end=a64_size(c);

    /* Common store. */
    size_t common = a64_size(c);
    size_t js[] = {str_join_end, ijend, ij1, ij2, ij3, ij4, ij5, fjend, fj1, fj2, fj3, fj4};
    for (int i=0;i<6;i++) a64_patch_branch(c->data, sj[i], common);
    for (int i=0;i<6;i++) a64_patch_branch(c->data, icj[i], common);
    for (int i=0;i<6;i++) a64_patch_branch(c->data, fcj[i], common);
    for (size_t i=0;i<sizeof(js)/sizeof(js[0]);i++) a64_patch_branch(c->data, js[i], common);
    a64_sub_imm(c, 10, 29, 8); a64_ldr_x(c, 8, 10, 0);
    a64_str_x(c, 9, 8, 0); a64_str_x(c, 13, 8, 8);
    a64_epilogue(c, 112);

    /* strcmp: x0, x1 -> difference */
    arm_add_label(g, "mag_strcmp", a64_size(c));
    size_t scl = a64_size(c);
    a64_ldrb(c, 2, 0, 0);
    a64_ldrb(c, 3, 1, 0);
    a64_cmp_reg(c, 2, 3);
    size_t sc_ne = a64_bcond(c, A64_NE);
    size_t sc_eq = a64_cbz(c, 2);
    a64_add_imm(c, 0, 0, 1);
    a64_add_imm(c, 1, 1, 1);
    size_t sc_back = a64_b(c);
    size_t equal = a64_size(c);
    a64_patch_cb(c->data, sc_eq, equal);
    a64_patch_branch(c->data, sc_back, scl);
    a64_mov_imm(c, 0, 0);
    a64_ret(c);
    size_t diff = a64_size(c);
    a64_patch_cond(c->data, sc_ne, diff);
    a64_sub_reg(c, 0, 2, 3);
    a64_ret(c);

    /* Heap allocator: bump pointer with a first-fit free list.  Each block
       has a 16-byte header: [size][next], and the returned pointer is
       block+16.  x28 is the bump pointer; the list head lives at
       HEAP_BASE-16, outside the usable heap. */
    arm_add_label(g, "mag_alloc", a64_size(c));
    a64_prologue(c, 48);
    a64_sub_imm(c, 10, 29, 8);   a64_str_x(c, 0, 10, 0);   /* requested size */
    a64_add_imm(c, 10, 0, 15);
    a64_mov_imm(c, 11, 0xFFFFFFFFFFFFFFF0ULL);
    a64_and_reg(c, 10, 10, 11);                             /* rounded size */
    a64_sub_imm(c, 12, 29, 16); a64_str_x(c, 10, 12, 0);   /* need */
    /* First-fit scan of the free list. */
    a64_mov_imm(c, 13, HEAP_BASE - 16);
    a64_ldr_x(c, 14, 13, 0);                                /* candidate */
    size_t al_scan = a64_size(c);
    a64_cmp_imm(c, 14, 0);
    size_t al_bump = a64_bcond(c, A64_EQ);
    a64_ldr_x(c, 15, 14, 0);                                /* candidate size */
    a64_sub_imm(c, 11, 29, 16); a64_ldr_x(c, 11, 11, 0);   /* need */
    a64_cmp_reg(c, 15, 11);
    size_t al_found = a64_bcond(c, A64_GE);
    a64_ldr_x(c, 14, 14, 8);                                /* next */
    size_t al_next = a64_b(c);
    a64_patch_branch(c->data, al_next, al_scan);
    a64_patch_cond(c->data, al_found, a64_size(c));
    /* Reuse: unlink candidate and return candidate+16. */
    a64_ldr_x(c, 15, 14, 8);
    a64_str_x(c, 15, 13, 0);
    a64_add_imm(c, 0, 14, 16);
    size_t al_done = a64_b(c);
    /* Bump: allocate a fresh block at x28. */
    a64_patch_cond(c->data, al_bump, a64_size(c));
    a64_mov_reg(c, 14, 28);
    a64_mov_reg(c, 15, 10);
    a64_add_reg(c, 11, 14, 15);
    a64_add_imm(c, 11, 11, 16);
    a64_mov_reg(c, 28, 11);
    a64_str_x(c, 10, 14, 0);                                /* size */
    a64_mov_imm(c, 11, 0);
    a64_str_x(c, 11, 14, 8);                                /* next */
    a64_add_imm(c, 0, 14, 16);
    a64_patch_branch(c->data, al_done, a64_size(c));
    a64_epilogue(c, 48);

    /* mag_free: return a block to the first-fit free list. */
    arm_add_label(g, "mag_free", a64_size(c));
    a64_prologue(c, 32);
    a64_sub_imm(c, 10, 0, 16);                              /* block = ptr - 16 */
    a64_mov_imm(c, 11, HEAP_BASE - 16);                     /* list head */
    a64_ldr_x(c, 12, 11, 0);                                /* current head */
    a64_str_x(c, 12, 10, 8);                                /* block->next = head */
    a64_str_x(c, 10, 11, 0);                                /* head = block */
    a64_epilogue(c, 32);

    arm_add_label(g, "mag_abort", a64_size(c));
    a64_mov_imm(c, 0, 134);
    a64_mov_imm(c, 8, 94);
    a64_svc(c);
    a64_ret(c);

    /* get_timestamp: CLOCK_REALTIME via clock_gettime (syscall 113).  AArch64
       has no sys_time; the generic ABI passes clk_id in x0 and timespec* in
       x1, and returns tv_sec in x0. */
    arm_add_label(g, "mag_get_timestamp", a64_size(c));
    a64_prologue(c, 32);
    a64_sub_imm(c, 10, 29, 16);
    a64_mov_imm(c, 11, 0);
    a64_str_x(c, 11, 10, 0);                                /* tv_sec = 0 */
    a64_str_x(c, 11, 10, 8);                                /* tv_nsec = 0 */
    a64_mov_imm(c, 0, 0);                                   /* CLOCK_REALTIME */
    a64_mov_reg(c, 1, 10);
    a64_mov_imm(c, 8, 113);
    a64_svc(c);
    a64_sub_imm(c, 10, 29, 16);
    a64_ldr_x(c, 0, 10, 0);
    a64_epilogue(c, 32);

    /* sleep_ms: nanosleep (syscall 101) with a stack-allocated timespec. */
    arm_add_label(g, "mag_sleep_ms", a64_size(c));
    a64_prologue(c, 48);
    a64_sub_imm(c, 11, 29, 16);
    a64_mov_imm(c, 12, 1000);
    a64_mov_reg(c, 10, 0);                                  /* ms */
    a64_sdiv(c, 13, 10, 12);                                /* seconds */
    a64_mul(c, 14, 13, 12);
    a64_sub_reg(c, 14, 10, 14);                             /* remainder ms */
    a64_mov_imm(c, 10, 1000000);
    a64_mul(c, 14, 14, 10);                                 /* nanoseconds */
    a64_str_x(c, 13, 11, 0);
    a64_str_x(c, 14, 11, 8);
    a64_mov_reg(c, 0, 11);
    a64_mov_imm(c, 1, 0);
    a64_mov_imm(c, 8, 101);
    a64_svc(c);
    a64_epilogue(c, 48);

    arm_add_label(g, "mag_rand", a64_size(c));
    a64_mov_imm(c, 9, 6364136223846793005ULL);
    a64_mov_imm(c, 10, 1442695040888963407ULL);
    a64_mul(c, 27, 27, 9);
    a64_add_reg(c, 27, 27, 10);
    a64_mov_imm(c, 11, 0x7FFFFFFFULL);
    a64_and_reg(c, 0, 27, 11);
    a64_ret(c);

    /* Integer division/modulo by zero: write the diagnostic and exit(1),
       with the same message as the x86_64 backend. */
    arm_add_label(g, "mag_divzero", a64_size(c));
    arm_emit_string_addr(g, "magnetar: division by zero\n");
    a64_mov_reg(c, 1, 0);         /* buffer */
    a64_mov_imm(c, 0, 2);         /* stderr */
    a64_mov_imm(c, 2, 27);
    a64_mov_imm(c, 8, 64);
    a64_svc(c);
    a64_mov_imm(c, 0, 1);
    a64_mov_imm(c, 8, 94);
    a64_svc(c);
}

/* ------------------------------------------------------------------ */
/* ELF writer                                                         */
/* ------------------------------------------------------------------ */
static void put16(uint8_t* p, uint16_t v) { p[0]=(uint8_t)v; p[1]=(uint8_t)(v>>8); }
static void put32(uint8_t* p, uint32_t v) { st32(p,v); }
static void put64(uint8_t* p, uint64_t v) {
    for (int i = 0; i < 8; i++) p[i] = (uint8_t)(v >> (i*8));
}

bool ArmGen_write_elf(const char* path, BackendResult* r) {
    FILE* f = fopen(path, "wb");
    if (!f) return false;
    uint8_t eh[64] = {0};
    eh[0]=0x7f; eh[1]='E'; eh[2]='L'; eh[3]='F';
    eh[4]=2; eh[5]=1; eh[6]=1;
    put16(eh+16, 2);       /* ET_EXEC */
    put16(eh+18, 0xB7);    /* EM_AARCH64 */
    put32(eh+20, 1);
    put64(eh+24, ELF_BASE + 64 + 56); /* entry = _start after ELF + phdr */
    put64(eh+32, 64);
    put64(eh+40, 0);
    put32(eh+48, 0);
    put16(eh+52, 64);
    put16(eh+54, 56);
    put16(eh+56, 1);

    uint64_t file_size = 64 + 56 + r->code_size + r->rodata_size;
    uint8_t ph[56] = {0};
    put32(ph, 1);          /* PT_LOAD */
    put32(ph+4, 7);        /* RWX */
    put64(ph+8, 64);
    put64(ph+16, ELF_BASE);
    put64(ph+24, ELF_BASE);
    put64(ph+32, file_size);
    put64(ph+40, file_size + HEAP_SIZE);
    put64(ph+48, 0x10000);

    fwrite(eh, 1, 64, f);
    fwrite(ph, 1, 56, f);
    if (r->code_size) fwrite(r->code, 1, r->code_size, f);
    if (r->rodata_size) fwrite(r->rodata, 1, r->rodata_size, f);
    fclose(f);
    chmod(path, 0755);
    return true;
}

/* ------------------------------------------------------------------ */
/* Public codegen API                                                  */
/* ------------------------------------------------------------------ */

static void arm_cleanup(ArmGen* g) {
    if (!g) return;
    for (int i = 0; i < g->local_count; i++) free_sym(&g->locals[i]);
    for (int i = 0; i < g->global_count; i++) free_sym(&g->globals[i]);
    for (int i = 0; i < g->func_count; i++) free(g->funcs[i].name);
    for (int i = 0; i < g->label_count; i++) free(g->labels[i].name);
    for (int i = 0; i < g->reloc_count; i++) free(g->relocs[i].name);
    for (int i = 0; i < g->data_reloc_count; i++) free(g->data_relocs[i].name);
    for (int i = 0; i < g->string_count; i++) {
        free(g->strings[i].name);
        free(g->strings[i].bytes);
    }
    g->local_count = 0;
    g->global_count = 0;
    g->func_count = 0;
    g->label_count = 0;
    g->reloc_count = 0;
    g->data_reloc_count = 0;
    g->string_count = 0;
    a64_free(&g->code);
    bb_free(&g->rodata);
    bb_free(&g->data);
    free(g->entry_name);
    g->entry_name = NULL;
}

void ArmGen_init(ArmGen* g, IRProgram* ir, const char* entry_name, bool object_mode) {
    memset(g, 0, sizeof(*g));
    g->object_mode = object_mode;
    if (object_mode)
        snprintf(g->obj_prefix, sizeof(g->obj_prefix), "__mg_%llx_%x.",
                 (unsigned long long)time(NULL), (unsigned)getpid());
    g->entry_name = strdup(entry_name && *entry_name ? entry_name : "main");
    if (ir && ir->count > 0 && ir->instructions[0].op == IR_AST_NODE)
        g->program = ir->instructions[0].ast_node;
    a64_init(&g->code, 4096);
    bb_init(&g->rodata, 256);
    bb_init(&g->data, 64);
}

bool ArmGen_generate(ArmGen* g, BackendResult* result) {
    if (!g || !g->program) return false;
    backend_result_init(result);

    const char* entry = g->entry_name ? g->entry_name : "main";
    bool obj = g->object_mode;

    if (!obj) {
        /* _start: align SP, initialise heap pointer, call entry, exit cleanly.
           In object mode this is emitted by the mag linker instead. */
        a64_align_sp(&g->code);
        a64_mov_imm(&g->code, 28, HEAP_BASE);
        a64_mov_imm(&g->code, 27, 12345);
        arm_add_reloc(g, entry, a64_bl(&g->code), RELOC_BRANCH);
        /* x0 is the value returned by the entry function, as in the linker
           startup path. */
        a64_mov_imm(&g->code, 8, 94);
        a64_svc(&g->code);
        arm_add_label(g, "_start", 0);
    }

    arm_collect_funcs(g, g->program);
    bool entry_found = false;
    for (int i = 0; i < g->func_count; i++)
        if (!strcmp(g->funcs[i].name, entry)) { entry_found = true; break; }
    if (!entry_found) {
        fprintf(stderr,
                "Error: entry function '%s' was not defined. "
                "Use --entry <name> to select a different start function.\n",
                entry);
        return false;
    }
    arm_register_globals(g, g->program);

    for (int i = 0; i < g->func_count; i++) {
        Func* f = &g->funcs[i];
        if (f->is_extern) continue;
        ASTNode* def = arm_find_func_node(g->program, f->name);
        if (def) {
            f->offset = a64_size(&g->code);
            arm_add_label(g, f->name, f->offset);
            arm_emit_function(g, def);
        }
    }
    arm_emit_runtime(g);

    if (!obj) {
        /* Standalone ELF: unresolved externs get the same generated stubs as
           the linker emits for aggregate objects.  Anything we cannot emit is
           a hard error instead of a silently unpatched BL. */
        for (int i = 0; i < g->reloc_count; i++) {
            Reloc* rel = &g->relocs[i];
            /* Extern Func entries have offset 0 and are not definitions;
               only emitted labels count.  Global/string labels are appended
               below, once the final code size is known. */
            if (arm_has_label(g, rel->name) || arm_is_late_label(g, rel->name))
                continue;
            if (rel->type != RELOC_BRANCH) {
                fprintf(stderr, "Error: unresolved ARM64 external '%s'.\n",
                        rel->name);
                arm_cleanup(g);
                return false;
            }
            bool duplicate = false;
            for (int j = 0; j < i; j++)
                if (!strcmp(g->relocs[j].name, rel->name)) { duplicate = true; break; }
            if (duplicate) continue;
            size_t stub_pos = a64_size(&g->code);
            if (!arm_emit_stub(&g->code, rel->name)) {
                fprintf(stderr, "Error: unresolved ARM64 external '%s'.\n",
                        rel->name);
                arm_cleanup(g);
                return false;
            }
            arm_add_label(g, rel->name, stub_pos);
        }
    }

    if (g->abi_error) {
        arm_cleanup(g);
        return false;
    }

    if (!obj) {
        /* Lay out mutable globals first, then string literals, immediately
           after the code segment. The whole image is one RWX PT_LOAD. */
        uint64_t data_base = 64 + 56 + g->code.len;
        bb_put(&g->rodata, g->data.data, g->data.len);
        for (int i = 0; i < g->global_count; i++) {
            Sym* s = &g->globals[i];
            if (!s->is_global_mutable) continue;
            char name[128];
            snprintf(name, sizeof(name), "__mg_data_%s", s->name ? s->name : "anon");
            arm_add_label(g, name, (size_t)(data_base + s->offset));
        }
        uint64_t cur = ELF_BASE + data_base + g->data.len;
        for (int i = 0; i < g->string_count; i++) {
            Str* s = &g->strings[i];
            s->addr = cur;
            s->offset = g->rodata.len;
            arm_add_label(g, s->name, (size_t)(cur - ELF_BASE));
            bb_put(&g->rodata, s->bytes, s->len + 1);
            cur += s->len + 1;
        }

        for (int i = 0; i < g->data_reloc_count; i++) {
            DataReloc* rel=&g->data_relocs[i];
            bool found=false;
            size_t target=arm_find_label(g,rel->name,&found);
            if(!found||rel->offset+8>g->rodata.len) continue;
            put64(g->rodata.data+rel->offset,(uint64_t)(ELF_BASE+target));
        }

        for (int i = 0; i < g->reloc_count; i++) {
            Reloc* rel = &g->relocs[i];
            bool found = false;
            size_t target = arm_find_label(g, rel->name, &found);
            if (!found) continue;
            if (rel->type == RELOC_BRANCH) a64_patch_branch(g->code.data, rel->pos, target);
            else a64_patch_mov64(g->code.data, rel->pos, target + ELF_BASE);
        }

        result->code = g->code.data;
        result->code_size = g->code.len;
        result->rodata = g->rodata.data;
        result->rodata_size = g->rodata.len;
        g->code.data = NULL;
        g->rodata.data = NULL;

        result->num_exports = 0;
        for (int i = 0; i < g->func_count && result->num_exports < MAX_EXPORTS; i++) {
            if (g->funcs[i].is_extern) continue;
            result->exports[result->num_exports].name = strdup(g->funcs[i].name);
            result->exports[result->num_exports].offset = (uint32_t)g->funcs[i].offset;
            result->num_exports++;
        }
    } else {
        /* Object mode: keep code and data in one buffer and export every
           label.  All relocations are left for the mag linker, which knows the
           final address after prepending its ARM64 startup code. */
        while (g->code.len % 8) a64_emit_byte(&g->code, 0);
        size_t data_pos = g->code.len;
        for (size_t i = 0; i < g->data.len; i++)
            a64_emit_byte(&g->code, g->data.data[i]);
        size_t cur = data_pos + g->data.len;

        for (int i = 0; i < g->global_count; i++) {
            Sym* s = &g->globals[i];
            if (!s->is_global_mutable) continue;
            char name[128];
            snprintf(name, sizeof(name), "__mg_data_%s", s->name ? s->name : "anon");
            arm_add_label(g, name, (size_t)(data_pos + s->offset));
        }
        for (int i = 0; i < g->string_count; i++) {
            Str* s = &g->strings[i];
            s->offset = (size_t)cur;
            s->addr = ELF_BASE + cur;
            arm_add_label(g, s->name, (size_t)cur);
            for (size_t j = 0; j < s->len + 1; j++)
                a64_emit_byte(&g->code, s->bytes[j]);
            cur += s->len + 1;
        }
        for (int i = 0; i < g->data_reloc_count; i++)
            arm_add_reloc(g,g->data_relocs[i].name,
                          data_pos+g->data_relocs[i].offset,RELOC_DATA_ADDR);

        result->num_exports = 0;
        for (int i = 0; i < g->func_count && result->num_exports < MAX_EXPORTS; i++) {
            if (g->funcs[i].is_extern) continue;
            result->exports[result->num_exports].name = strdup(g->funcs[i].name);
            result->exports[result->num_exports].offset = (uint32_t)g->funcs[i].offset;
            result->num_exports++;
        }
        for (int i = 0; i < g->label_count && result->num_exports < MAX_EXPORTS; i++) {
            if (!strcmp(g->labels[i].name, "_start")) continue;
            char* export_name = arm_export_name(g, g->labels[i].name);
            bool dup = false;
            for (int j = 0; j < result->num_exports; j++)
                if (!strcmp(result->exports[j].name, export_name)) { dup = true; break; }
            if (dup) { free(export_name); continue; }
            result->exports[result->num_exports].name = export_name;
            result->exports[result->num_exports].offset = (uint32_t)g->labels[i].pos;
            result->num_exports++;
        }

        result->num_patches = 0;
        result->patches = NULL;
        for (int i = 0; i < g->reloc_count; i++) {
            Reloc* rel = &g->relocs[i];
            result->patches = (ImportPatch*)realloc(result->patches,
                sizeof(ImportPatch) * (size_t)(result->num_patches + 1));
            if (!result->patches) { result->num_patches = 0; break; }
            ImportPatch* p = &result->patches[result->num_patches++];
            bool local = false;
            for (int j = 0; j < g->label_count; j++) {
                if (!strcmp(g->labels[j].name, rel->name) &&
                    !arm_is_func_name(g, rel->name)) { local = true; break; }
            }
            p->name = local ? arm_export_name(g, rel->name) : strdup(rel->name);
            p->position = (uint32_t)rel->pos;
            p->type = (rel->type == RELOC_BRANCH)
                ? MAG_PATCH_AARCH64_CALL26
                : (rel->type == RELOC_DATA_ADDR)
                    ? MAG_PATCH_AARCH64_ABS64_RAW
                    : MAG_PATCH_AARCH64_ABS64;
        }

        result->code = g->code.data;
        result->code_size = g->code.len;
        result->rodata = NULL;
        result->rodata_size = 0;
        g->code.data = NULL;
    }

    arm_cleanup(g);
    return true;
}

void ArmGen_free(ArmGen* g) {
    arm_cleanup(g);
}

ArmGen* ArmGen_create(IRProgram* ir, const char* entry_name, bool object_mode) {
    ArmGen* g = (ArmGen*)calloc(1, sizeof(*g));
    if (!g) return NULL;
    ArmGen_init(g, ir, entry_name, object_mode);
    return g;
}

void ArmGen_destroy(ArmGen* g) {
    ArmGen_free(g);
    free(g);
}

uint64_t ArmGen_entry_point(void) {
    return ELF_BASE + 64 + 56;
}
