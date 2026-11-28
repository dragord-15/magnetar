#include "parser.h"
#include "struct_registry.h"
#include "../utils/diagnostics.h"
#include <ctype.h>
#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

StructType struct_types[128];
int struct_type_count = 0;

EnumMember enum_members[256];
int enum_member_count = 0;

ClassInheritance class_inherits[64];
int class_inherits_count = 0;

const char *last_type_name = NULL;

/* Set by magc --bounds-check. Only fixed arrays have a statically known
   extent, so literal indices into dyn/slice/alloc are not rejected here. */
static bool parser_bounds_check = false;

void Parser_set_bounds_check(bool enabled) { parser_bounds_check = enabled; }

/* Converts a token's 1-based line/column into an offset in the lexer source.
   Used to capture the original text of an `asm { ... }` block. */
static int token_source_offset(const Lexer *lexer, const Token *token) {
    if (!lexer || !lexer->source || !token) return -1;
    int line = 1, col = 1;
    for (int i = 0; lexer->source[i]; i++) {
        if (line == token->line && col == token->column) return i;
        if (lexer->source[i] == '\n') { line++; col = 1; }
        else col++;
    }
    return -1;
}

/* The type whose body is currently being parsed. Used to resolve a call to a
   sibling method without an explicit receiver. */
static const char *current_type_context = NULL;

/* Builds "char*", "char**", ... from a base type name for multi-level pointers.
   Rotating static buffers keep a couple of nested calls alive at once. */
static const char *type_name_with_depth(const char *base, int depth) {
    static char bufs[4][48];
    static int next_buf = 0;
    char *out = bufs[next_buf];
    next_buf = (next_buf + 1) & 3;
    int i = 0;
    while (base[i] && i < 24) {
        out[i] = base[i];
        i++;
    }
    int stars = 1;
    while (stars < depth && i < 46) {
        out[i] = '*';
        i++;
        stars++;
    }
    out[i] = 0;
    return out;
}
#define MAX_ARRAY_DIMS 8

TokenType last_array_elem_type = TOK_UNKNOWN;
/* Total number of elements (the product of every dimension). Kept for the
   code paths that only need the flat size of the array. */
int last_array_size = 0;
/* Dimensions of the last parsed array, outermost first. `int a[2][3]` stores
   {2, 3}; the product is `last_array_size`. */
int last_array_dims[MAX_ARRAY_DIMS];
int last_array_dim_count = 0;

typedef struct {
  char *name;
  TokenType type;
  char *type_name;
  int array_size;
  int array_dim_count;
  int array_dims[MAX_ARRAY_DIMS];
  TokenType array_elem_type;
  bool is_const;
} ParserVar;

typedef struct {
  TokenType elem_type;
  int dims[MAX_ARRAY_DIMS];
  int dim_count;
  int total;
} ArrayShape;

static void array_shape_set(TokenType elem, const int *dims, int dim_count) {
  if (dim_count < 0) dim_count = 0;
  if (dim_count > MAX_ARRAY_DIMS) dim_count = MAX_ARRAY_DIMS;
  last_array_elem_type = elem;
  last_array_dim_count = dim_count;
  int total = 1;
  for (int i = 0; i < dim_count; i++) {
    last_array_dims[i] = dims[i] > 0 ? dims[i] : 1;
    total *= last_array_dims[i];
  }
  for (int i = dim_count; i < MAX_ARRAY_DIMS; i++)
    last_array_dims[i] = 0;
  last_array_size = dim_count > 0 ? total : 0;
}

static void array_shape_capture(ArrayShape *shape) {
  if (!shape) return;
  shape->elem_type = last_array_elem_type;
  shape->dim_count = last_array_dim_count;
  shape->total = last_array_size;
  for (int i = 0; i < MAX_ARRAY_DIMS; i++)
    shape->dims[i] = last_array_dims[i];
}

static void array_shape_restore(const ArrayShape *shape) {
  if (!shape) return;
  array_shape_set(shape->elem_type, shape->dims, shape->dim_count);
}

ParserVar parser_vars[256];
int parser_var_count = 0;

/* Function signatures known to the parser. Needed to infer the type of a
   call (`let x = sqrt(2.0)` is a float) and to resolve a method that is
   called without a receiver inside another method of the same type. */
typedef struct {
  char *name;
  TokenType return_type;
  char *owner; /* struct/class the method belongs to, NULL for free functions */
  char *return_type_name; /* struct/tuple name for aggregate returns, else NULL */
} ParserFunc;

#define MAX_PARSER_FUNCS 1024
ParserFunc parser_funcs[MAX_PARSER_FUNCS];
int parser_func_count = 0;

static void register_parser_func(const char *name, TokenType return_type,
                                  const char *owner,
                                  const char *return_type_name) {
  if (!name)
    return;
  for (int i = 0; i < parser_func_count; i++) {
    if (strcmp(parser_funcs[i].name, name) == 0) {
      parser_funcs[i].return_type = return_type;
      if (parser_funcs[i].owner)
        free(parser_funcs[i].owner);
      parser_funcs[i].owner = owner ? strdup(owner) : NULL;
      if (parser_funcs[i].return_type_name)
        free(parser_funcs[i].return_type_name);
      parser_funcs[i].return_type_name =
          return_type_name ? strdup(return_type_name) : NULL;
      return;
    }
  }
  if (parser_func_count >= MAX_PARSER_FUNCS)
    return;
  parser_funcs[parser_func_count].name = strdup(name);
  parser_funcs[parser_func_count].return_type = return_type;
  parser_funcs[parser_func_count].owner = owner ? strdup(owner) : NULL;
  parser_funcs[parser_func_count].return_type_name =
      return_type_name ? strdup(return_type_name) : NULL;
  parser_func_count++;
}

static ParserFunc *lookup_parser_func(const char *name) {
  if (!name)
    return NULL;
  for (int i = 0; i < parser_func_count; i++) {
    if (strcmp(parser_funcs[i].name, name) == 0)
      return &parser_funcs[i];
  }
  return NULL;
}

static void cleanup_parser_funcs(void) {
  for (int i = 0; i < parser_func_count; i++) {
    if (parser_funcs[i].name)
      free(parser_funcs[i].name);
    if (parser_funcs[i].owner)
      free(parser_funcs[i].owner);
    if (parser_funcs[i].return_type_name)
      free(parser_funcs[i].return_type_name);
    parser_funcs[i].name = NULL;
    parser_funcs[i].owner = NULL;
    parser_funcs[i].return_type_name = NULL;
  }
  parser_func_count = 0;
}

/* Turns `sibling(...)` inside a method of `type_name` into the mangled
   `Type_sibling(...)` call and passes the receiver implicitly. The rewrite
   runs after the whole type has been parsed so that a method may call a
   sibling that is declared later. */
static void rewrite_call_to_mangled(ASTNode *call, const char *mangled) {
  ASTNode *callee = call->children[0];
  if (callee->token.text)
    free((void *)callee->token.text);
  callee->token.text = strdup(mangled);

  Token this_tok;
  this_tok.type = TOK_KW_THIS;
  this_tok.text = strdup("this");
  this_tok.line = callee->token.line;
  this_tok.column = callee->token.column;
  ASTNode *receiver = ASTNode_create(NODE_THIS, this_tok);

  ASTNode **kids = (ASTNode **)malloc(sizeof(ASTNode *) * (call->child_count + 1));
  kids[0] = callee;
  kids[1] = receiver;
  for (int i = 1; i < call->child_count; i++)
    kids[i + 1] = call->children[i];
  free(call->children);
  call->children = kids;
  call->child_count++;
  call->child_capacity = call->child_count;
}

static void resolve_sibling_calls(ASTNode *node, const char *type_name) {
  if (!node || !type_name)
    return;
  if (node->type == AST_FUNC_DECL)
    return; /* a nested function has its own context */
  if (node->type == AST_CALL_EXPR && node->child_count >= 1 &&
      node->children[0] && node->children[0]->type == AST_IDENTIFIER_EXPR &&
      node->children[0]->token.text) {
    char mangled[256];
    snprintf(mangled, sizeof(mangled), "%s_%s", type_name,
             node->children[0]->token.text);
    if (strcmp(mangled, node->children[0]->token.text) != 0 &&
        lookup_parser_func(mangled)) {
      rewrite_call_to_mangled(node, mangled);
    }
  }
  for (int i = 0; i < node->child_count; i++)
    resolve_sibling_calls(node->children[i], type_name);
}

/* Token text must outlive every AST node that copies it. ASTNode_create()
   strdups the text, but plenty of call sites build the node *after*
   advance_token() ran, which used to free the string first. Instead of
   auditing every site, keep each lexed text in an arena and release the whole
   arena once parsing is finished. */
static char **token_text_arena = NULL;
static size_t token_text_arena_count = 0;
static size_t token_text_arena_cap = 0;

static void token_text_keep(char *text) {
  if (!text) return;
  if (token_text_arena_count == token_text_arena_cap) {
    size_t ncap = token_text_arena_cap ? token_text_arena_cap * 2 : 256;
    char **grown = (char **)realloc(token_text_arena, ncap * sizeof(char *));
    if (!grown) return; /* out of memory: leak rather than crash */
    token_text_arena = grown;
    token_text_arena_cap = ncap;
  }
  token_text_arena[token_text_arena_count++] = text;
}

static void token_text_arena_reset(void) {
  for (size_t i = 0; i < token_text_arena_count; i++)
    free(token_text_arena[i]);
  free(token_text_arena);
  token_text_arena = NULL;
  token_text_arena_count = 0;
  token_text_arena_cap = 0;
}

/* تحرير جميع المتغيرات المسجلة لمنع تسرب الذاكرة */
static void cleanup_parser_vars(void) {
  for (int i = 0; i < parser_var_count; i++) {
    if (parser_vars[i].name) free(parser_vars[i].name);
    if (parser_vars[i].type_name) free(parser_vars[i].type_name);
    parser_vars[i].name = NULL;
    parser_vars[i].type_name = NULL;
  }
  parser_var_count = 0;
  cleanup_parser_funcs();
  token_text_arena_reset();
}

static void register_parser_var_full(const char *name, TokenType type,
                                     const char *type_name, bool is_const) {
  if (!name)
    return;
  if (parser_var_count < 256) {
    parser_vars[parser_var_count].name = strdup(name);
    parser_vars[parser_var_count].type = type;
    parser_vars[parser_var_count].type_name =
        type_name ? strdup(type_name) : NULL;
    parser_vars[parser_var_count].array_size =
        type == TOK_KW_FIXED ? last_array_size : 0;
    parser_vars[parser_var_count].array_dim_count =
        type == TOK_KW_FIXED ? last_array_dim_count : 0;
    parser_vars[parser_var_count].array_elem_type =
        (type == TOK_KW_FIXED || type == TOK_KW_DYN || type == TOK_KW_SLICE)
            ? last_array_elem_type
            : TOK_UNKNOWN;
    for (int i = 0; i < MAX_ARRAY_DIMS; i++) {
      parser_vars[parser_var_count].array_dims[i] =
          type == TOK_KW_FIXED ? last_array_dims[i] : 0;
    }
    parser_vars[parser_var_count].is_const = is_const;
    parser_var_count++;
  }
}

static void register_parser_var(const char *name, TokenType type,
                                const char *type_name) {
  register_parser_var_full(name, type, type_name, false);
}

static void restore_parser_vars(int saved_count) {
  while (parser_var_count > saved_count) {
    parser_var_count--;
    free(parser_vars[parser_var_count].name);
    free(parser_vars[parser_var_count].type_name);
    parser_vars[parser_var_count].name = NULL;
    parser_vars[parser_var_count].type_name = NULL;
  }
}

static ParserVar *lookup_parser_var(const char *name) {
  if (!name)
    return NULL;
  for (int i = parser_var_count - 1; i >= 0; i--) {
    if (strcmp(parser_vars[i].name, name) == 0) {
      return &parser_vars[i];
    }
  }
  return NULL;
}

/* First extent of a genuinely fixed array (0 for dyn/slice/pointer/member
   accesses), used by the optional literal-index range check. */
static int parser_fixed_extent(const ASTNode *node) {
  if (!node || node->type != AST_IDENTIFIER_EXPR || !node->token.text)
    return 0;
  ParserVar *pv = lookup_parser_var(node->token.text);
  if (pv && pv->type == TOK_KW_FIXED && pv->array_dim_count > 0 &&
      pv->array_dims[0] > 0)
    return pv->array_dims[0];
  return 0;
}

/* Report a statically provable out-of-bounds literal index. */
static void check_literal_index(Parser *parser, ASTNode *index, int extent,
                                int dimension) {
  if (!parser_bounds_check || extent <= 0 || !index ||
      index->type != AST_LITERAL_EXPR || index->token.type != TOK_INT_LITERAL ||
      !index->token.text)
    return;
  char *end = NULL;
  errno = 0;
  long long value = strtoll(index->token.text, &end, 10);
  if (errno || end == index->token.text || *end != '\0') return;
  if (value < 0 || value >= extent) {
    char msg[160], hint[128];
    snprintf(msg, sizeof(msg),
             "array index %lld is out of bounds for dimension %d (size %d)",
             value, dimension + 1, extent);
    snprintf(hint, sizeof(hint),
             "valid indices are 0..%d; compile without --bounds-check to disable this check",
             extent - 1);
    diag_report_error(index->token.line, index->token.column, msg,
                      index->token.text, hint);
    parser->has_error = true;
  }
}

/* `range` values are ordinary structs with three 8-byte fields.  Registering
   the layout lazily lets `range r = range(1, 10, 2);` behave like any other
   struct value while `for (... in range(...))` keeps its dedicated lowering. */
static void parser_ensure_range_struct(void) {
  if (lookup_struct("range") != NULL || struct_type_count >= 128)
    return;
  StructType *st = &struct_types[struct_type_count++];
  memset(st, 0, sizeof(*st));
  st->name = strdup("range");
  st->size = 24;
  st->field_count = 3;
  const char *names[3] = {"start", "end", "step"};
  for (int i = 0; i < 3; i++) {
    st->fields[i].name = strdup(names[i]);
    st->fields[i].offset = i * 8;
    st->fields[i].field_type = TOK_KW_INT;
    st->fields[i].array_size = 0;
  }
}

/* Storage slot width of an array element. `any` is a tagged 16-byte value;
   every other element keeps the 8-byte language slot. */
static int parser_elem_slot_size(TokenType type) {
  return type == TOK_KW_ANY ? 16 : 8;
}

/* Byte width of a type token, matching how AST_VAR_DECL sizes locals in the
   backend. Structs resolve through type_name (struct fields store the token
   only, so struct-typed members fall back to the 8-byte default). */
static int parser_type_size(TokenType type, const char *type_name) {
  if (type_name) {
    size_t len = strlen(type_name);
    if (len > 0 && type_name[len - 1] == '*')
      return 8; /* "char*", "char**", ... are pointers */
    StructType *st = lookup_struct(type_name);
    if (st)
      return st->size;
  }
  switch (type) {
  case TOK_KW_CHAR: case TOK_KW_BYTE: case TOK_KW_BOOL:
    return 1;
  case TOK_KW_WORD:
    return 2;
  case TOK_KW_HALF:
    return 4; /* represented as a 32-bit float internally */
  case TOK_KW_DWORD: case TOK_KW_FLOAT:
    return 4;
  case TOK_KW_DYN: case TOK_KW_RANGE:
    return 24;
  case TOK_KW_SLICE:
    return 16;
  case TOK_KW_ANY:
    return 16;
  case TOK_KW_FIXED:
    return last_array_size > 0
               ? last_array_size * parser_elem_slot_size(last_array_elem_type)
               : 8;
  default:
    return 8;
  }
}

/* Byte width of an expression whose type is known at parse time -- `sizeof(x)`
   and `sizeof(expr)`. Unknown expressions keep sizeof's 8-byte default. */
static int parser_expr_size(ASTNode *expr) {
  if (!expr)
    return 8;
  switch (expr->type) {
  case AST_IDENTIFIER_EXPR: {
    ParserVar *pv = lookup_parser_var(expr->token.text);
    if (pv && pv->type == TOK_KW_FIXED && pv->array_size > 0)
      return pv->array_size * parser_elem_slot_size(pv->array_elem_type);
    if (pv)
      return parser_type_size(pv->type, pv->type_name);
    return 8;
  }
  case AST_CAST_EXPR:
    return parser_type_size((TokenType)expr->int_value, expr->string_value);
  case AST_MEMBER_ACCESS: {
    ASTNode *base = expr->children[0];
    const char *type_name = NULL;
    if (base && base->type == AST_IDENTIFIER_EXPR) {
      ParserVar *pv = lookup_parser_var(base->token.text);
      if (pv)
        type_name = pv->type_name;
    }
    if (type_name) {
      StructType *st = lookup_struct(type_name);
      if (st) {
        for (int i = 0; i < st->field_count; i++) {
          if (strcmp(st->fields[i].name, expr->token.text) == 0) {
            StructField *field = &st->fields[i];
            if (field->array_size > 0)
              return field->array_size *
                     parser_elem_slot_size((TokenType)field->field_type);
            return parser_type_size((TokenType)field->field_type, NULL);
          }
        }
      }
    }
    return 8;
  }
  case NODE_FLOAT_LIT:
    return 4;
  case NODE_BOOL_LIT:
  case NODE_CHAR_LIT:
    return 1;
  case AST_LITERAL_EXPR:
    if (expr->token.type == TOK_CHAR_LITERAL)
      return 1;
    return 8;
  default:
    return 8;
  }
}

static ASTNode *parse_function_opt(Parser *parser, bool is_extern);
static ASTNode *parse_function(Parser *parser);
static ASTNode *parse_impl_method(Parser *parser, const char *owner);

/* last_type_name must outlive advance_token(), which frees the token text it
   would otherwise point at. Rotating static buffers keep one or two live
   copies at a time, matching type_name_with_depth() above. */
static char type_name_scratch[2][64];
static int type_name_scratch_next = 0;

static const char *remember_type_name(const char *name) {
  if (!name) return NULL;
  char *buf = type_name_scratch[type_name_scratch_next];
  type_name_scratch_next = (type_name_scratch_next + 1) & 1;
  snprintf(buf, sizeof(type_name_scratch[0]), "%s", name);
  return buf;
}

/* Mirrors the declaration peek below: does the current token begin a type? */
static bool token_starts_type(Parser *parser) {
  switch (parser->current_token.type) {
  case TOK_KW_INT: case TOK_KW_FLOAT: case TOK_KW_BOOL: case TOK_KW_CHAR:
  case TOK_KW_STRING: case TOK_KW_PTR: case TOK_KW_RAW: case TOK_KW_REF:
  case TOK_KW_OWN:
  case TOK_KW_AUTO: case TOK_KW_TYPEOF: case TOK_KW_BYTE: case TOK_KW_WORD:
  case TOK_KW_DWORD: case TOK_KW_QWORD: case TOK_KW_HALF: case TOK_KW_FIXED:
  case TOK_KW_ARRAY: case TOK_KW_TUPLE:
  case TOK_KW_DYN: case TOK_KW_SLICE: case TOK_KW_ANY:
  case TOK_KW_RANGE:
  case TOK_KW_VOLATILE: case TOK_KW_REGISTER:
    return true;
  case TOK_IDENTIFIER:
    if (parser->current_token.text &&
        lookup_struct(parser->current_token.text) != NULL)
      return true;
    return parser->next_token.type == TOK_IDENTIFIER;
  default:
    return false;
  }
}

/* Finds the struct type an aggregate literal without a type of its own
   belongs to: the one whose layout has exactly as many fields as the literal
   has elements. Returns NULL when there is no such type or when several
   types match, because then the type cannot be inferred. */
static StructType *find_struct_for_literal(int elem_count) {
  StructType *found = NULL;
  for (int i = 0; i < struct_type_count; i++) {
    if (struct_types[i].field_count != elem_count) continue;
    if (found) return NULL; /* ambiguous */
    found = &struct_types[i];
  }
  return found;
}

/* Reverse of primitive_type_name(): recovers the token type from the name the
   parser stored for a pointee. Unknown names fall back to `int`. */
static TokenType token_from_type_name(const char *name) {
  if (!name) return TOK_KW_INT;
  if (strcmp(name, "char") == 0)   return TOK_KW_CHAR;
  if (strcmp(name, "byte") == 0)   return TOK_KW_BYTE;
  if (strcmp(name, "bool") == 0)   return TOK_KW_BOOL;
  if (strcmp(name, "string") == 0) return TOK_KW_STRING;
  if (strcmp(name, "dword") == 0)  return TOK_KW_DWORD;
  if (strcmp(name, "word") == 0)   return TOK_KW_WORD;
  if (strcmp(name, "qword") == 0)  return TOK_KW_QWORD;
  if (strcmp(name, "half") == 0)   return TOK_KW_HALF;
  if (strcmp(name, "float") == 0)  return TOK_KW_FLOAT;
  if (strcmp(name, "any") == 0)    return TOK_KW_ANY;
  return TOK_KW_INT;
}

/* Type inference for `auto` and `let` initialisers. Literal values are read
   from the token type, never from int_value: an int literal may coincidentally
   equal a TOK_KW_* enum value. */
static TokenType deduce_decl_type(ASTNode *init) {
  if (!init) return TOK_KW_INT;
  switch (init->type) {
  case NODE_FLOAT_LIT: return TOK_KW_FLOAT;
  case NODE_NAN_LIT: case NODE_INF_LIT: return TOK_KW_FLOAT;
  case NODE_BOOL_LIT:  return TOK_KW_BOOL;
  case NODE_CHAR_LIT:  return TOK_KW_CHAR;
  case AST_LITERAL_EXPR:
    if (init->token.type == TOK_STRING_LITERAL) return TOK_KW_STRING;
    if (init->token.type == TOK_INT_LITERAL) return TOK_KW_INT;
    return TOK_KW_INT;
  case AST_IDENTIFIER_EXPR: {
    ParserVar *pv = lookup_parser_var(init->token.text);
    if (pv) return pv->type;
    return TOK_KW_INT;
  }
  case AST_CAST_EXPR: return (TokenType)init->int_value;
  case AST_MEMBER_ACCESS: {
    if (init->child_count > 0 && init->children[0] &&
        init->children[0]->type == AST_IDENTIFIER_EXPR) {
      ParserVar *base = lookup_parser_var(init->children[0]->token.text);
      if (base && base->type_name) {
        StructType *st = lookup_struct(base->type_name);
        StructField *f = find_field(st, init->token.text);
        if (f) {
          if (f->array_size > 0) return TOK_KW_FIXED;
          return (TokenType)f->field_type;
        }
      }
    }
    return TOK_KW_INT;
  }
  case AST_TERNARY_EXPR: {
    TokenType then_t = deduce_decl_type(init->children[1]);
    TokenType else_t =
        init->child_count > 2 ? deduce_decl_type(init->children[2]) : then_t;
    if (then_t == TOK_KW_FLOAT || else_t == TOK_KW_FLOAT)
      return TOK_KW_FLOAT;
    if (then_t == TOK_KW_STRING || else_t == TOK_KW_STRING)
      return TOK_KW_STRING;
    return then_t;
  }
  case AST_BINARY_EXPR: {
    if (init->token.type == TOK_PLUS && init->child_count >= 2) {
      TokenType lt = deduce_decl_type(init->children[0]);
      TokenType rt = deduce_decl_type(init->children[1]);
      if (lt == TOK_KW_STRING || rt == TOK_KW_STRING)
        return TOK_KW_STRING;
    }
    /* Comparisons and logical connectives produce 0/1, which are integers. */
    switch (init->token.type) {
    case TOK_LT: case TOK_LE: case TOK_GT: case TOK_GE:
    case TOK_EQ: case TOK_NEQ: case TOK_AND: case TOK_OR:
      return TOK_KW_INT;
    default:
      break;
    }
    /* An arithmetic expression is a float expression as soon as one of its
       operands is a float: `1 + 2.5` is 3.5. */
    TokenType lt = deduce_decl_type(init->children[0]);
    TokenType rt =
        init->child_count >= 2 ? deduce_decl_type(init->children[1]) : lt;
    if (lt == TOK_KW_FLOAT || rt == TOK_KW_FLOAT) return TOK_KW_FLOAT;
    if (lt == TOK_KW_BOOL && rt == TOK_KW_BOOL) return TOK_KW_BOOL;
    return TOK_KW_INT;
  }
  case AST_CALL_EXPR: {
    /* A call yields the return type of the callee, when it is known. */
    ASTNode *callee = init->children[0];
    if (callee && callee->type == AST_IDENTIFIER_EXPR && callee->token.text) {
      ParserFunc *pf = lookup_parser_func(callee->token.text);
      if (pf) return pf->return_type;
    }
    return TOK_KW_INT;
  }
  case AST_STRUCT_LITERAL:
    if (init->string_value && strcmp(init->string_value, "range") == 0)
      return TOK_KW_INT; /* stored as struct range but type token usually range */
    /* The type of an aggregate literal is inferred by the declaration. */
    return TOK_KW_AUTO;
  case AST_UNARY_EXPR: {
    /* A sign keeps the type of its operand: `-2.5` is a float. */
    if (init->child_count > 0 &&
        (init->token.type == TOK_MINUS || init->token.type == TOK_PLUS)) {
      return deduce_decl_type(init->children[0]);
    }
    /* Dereferencing a typed pointer yields the pointee type. */
    if (init->token.type == TOK_STAR && init->child_count > 0) {
      ASTNode *operand = init->children[0];
      if (operand->type == AST_IDENTIFIER_EXPR) {
        ParserVar *pv = lookup_parser_var(operand->token.text);
        if (pv && pv->type_name)
          return token_from_type_name(pv->type_name);
      }
    }
    return TOK_KW_INT;
  }
  default: return TOK_KW_INT;
  }
}

ASTNode *ASTNode_create(ASTNodeType type, Token token) {
  ASTNode *node = (ASTNode *)malloc(sizeof(ASTNode));
  node->type = type;
  node->token = token;
    if (token.text) {
    node->token.text = strdup(token.text);
    }
  node->child_capacity = 4;
  node->child_count = 0;
  node->children = (ASTNode **)malloc(sizeof(ASTNode *) * node->child_capacity);
  node->string_value = NULL;
  node->int_value = 0;
  node->float_value = 0.0f;
  node->bool_value = false;
  node->is_volatile = false;
  node->char_value = 0;
  return node;
}

void ASTNode_add_child(ASTNode *parent, ASTNode *child) {
  if (!parent || !child)
    return;
  if (parent->child_count >= parent->child_capacity) {
    parent->child_capacity *= 2;
    parent->children = (ASTNode **)realloc(
        parent->children, sizeof(ASTNode *) * parent->child_capacity);
  }
  parent->children[parent->child_count++] = child;
}

void ASTNode_free(ASTNode *node) {
  if (!node)
    return;
  for (int i = 0; i < node->child_count; i++) {
    ASTNode_free(node->children[i]);
  }
  free(node->children);
  if (node->string_value)
    free(node->string_value);
  if (node->token.text)
    free(node->token.text);
  free(node);
}

ASTNode *ASTNode_clone(ASTNode *node) {
  if (!node)
    return NULL;
  ASTNode *clone = (ASTNode *)malloc(sizeof(ASTNode));
  clone->type = node->type;
  clone->token = node->token;
  if (node->token.text) {
    clone->token.text = strdup(node->token.text);
  }
  clone->child_capacity = node->child_capacity;
  clone->child_count = node->child_count;
  clone->children =
      (ASTNode **)malloc(sizeof(ASTNode *) * clone->child_capacity);
  for (int i = 0; i < node->child_count; i++) {
    clone->children[i] = ASTNode_clone(node->children[i]);
  }
  clone->string_value = node->string_value ? strdup(node->string_value) : NULL;
  clone->int_value = node->int_value;
  clone->float_value = node->float_value;
  clone->bool_value = node->bool_value;
  clone->is_volatile = node->is_volatile;
  clone->char_value = node->char_value;
  return clone;
}

void Parser_init(Parser *parser, Lexer *lexer) {
  parser->lexer = lexer;
  parser->has_error = false;
  parser->loop_depth = 0;
  parser->switch_depth = 0;
  parser->current_token = Lexer_next_token(parser->lexer);
  parser->next_token = Lexer_next_token(parser->lexer);
}

/* 64-bit: literal bases are explicit -- `0x`/`0b`/`0o` select a radix and every
   other integer literal is decimal, so `010` is ten and `08` is eight (C would
   read those as invalid octal). Digit separators (`1_000`) are ignored.
   `int` is 64-bit in Magnetar, literals must not be truncated. */
static void strip_digit_separators(const char *text, char *out, size_t out_size) {
  size_t j = 0;
  if (!text) {
    if (out_size) out[0] = '\0';
    return;
  }
  for (size_t i = 0; text[i] && j + 1 < out_size; i++) {
    if (text[i] == '_') continue;
    out[j++] = text[i];
  }
  out[j] = '\0';
}

static int64_t parse_int_token_text(const char *text) {
  char buf[64];
  strip_digit_separators(text, buf, sizeof(buf));
  if (!buf[0]) return 0;
  int base = 10;
  const char *digits = buf;
  if (buf[0] == '0' && buf[1]) {
    char p = buf[1];
    if (p == 'x' || p == 'X') { base = 16; digits = buf + 2; }
    else if (p == 'b' || p == 'B') { base = 2; digits = buf + 2; }
    else if (p == 'o' || p == 'O') { base = 8; digits = buf + 2; }
  }
  if (!*digits) return 0;
  errno = 0;
  char *end = NULL;
  long long v = strtoll(digits, &end, base);
  if (errno == ERANGE) {
    /* Out of range for 64 bits: saturate instead of wrapping silently. */
    return v < 0 ? INT64_MIN : INT64_MAX;
  }
  return (int64_t)v;
}

/* Float literals share the digit-separator rule with integers; the optional
   `f`/`F` suffix is simply ignored by strtod. */
static double parse_float_token_text(const char *text) {
  if (!text) return 0.0;
  char buf[64];
  strip_digit_separators(text, buf, sizeof(buf));
  return strtod(buf, NULL);
}

/* Decodes a character literal (including the surrounding quotes) into its
   byte value. Every escape sequence C knows is supported; an unknown escape
   yields the escaped character itself. */
static char decode_char_literal(const char *text) {
  if (!text || text[0] != '\'') return 0;
  const char *p = text + 1;
  if (*p != '\\') return *p;
  p++;
  switch (*p) {
    case 'n': return '\n';
    case 't': return '\t';
    case 'r': return '\r';
    case '0': return '\0';
    case 'a': return '\a';
    case 'b': return '\b';
    case 'f': return '\f';
    case 'v': return '\v';
    case 'e': return 27;
    case '\\': return '\\';
    case '\'': return '\'';
    case '"': return '"';
    case 'x': {
      p++;
      int v = 0, n = 0;
      while (n < 2 && isxdigit((unsigned char)*p)) {
        int d = isdigit((unsigned char)*p) ? *p - '0'
                                           : (tolower((unsigned char)*p) - 'a' + 10);
        v = v * 16 + d;
        p++;
        n++;
      }
      return (char)v;
    }
    default: return *p;
  }
}

static void advance_token(Parser *parser) {
  /* نص التوكن يبقى صالحاً حتى نهاية التحليل (انظر token_text_arena):
   * كود كثير يبني عقدة AST بعد استدعاء advance_token. */
  if (parser->current_token.text) {
    token_text_keep(parser->current_token.text);
    parser->current_token.text = NULL;
  }
  parser->current_token = parser->next_token;
  /* إبطال next_token.text لأن الملكية انتقلت لـ current_token */
  parser->next_token.text = NULL;
  parser->next_token = Lexer_next_token(parser->lexer);
}

static bool match(Parser *parser, TokenType type) {
  if (parser->current_token.type == type) {
    advance_token(parser);
    return true;
  }
  return false;
}

static void report_error(Parser *parser, const char *message) {
  diag_report_error(parser->current_token.line, parser->current_token.column,
                    message, parser->current_token.text, NULL);
  parser->has_error = true;
}

static bool consume(Parser *parser, TokenType type, const char *err) {
  if (parser->current_token.type == type) {
    advance_token(parser);
    return true;
  }
  report_error(parser, err);
  return false;
}

/* Parses a C-style array suffix: `[2][3][4]`. Returns the number of
   dimensions and fills `dims` with their sizes, outermost first. */
static int parse_bracket_dims(Parser *parser, int *dims, int max_dims) {
  int dim_count = 0;
  while (parser->current_token.type == TOK_LBRACKET) {
    advance_token(parser);
    Token size_tok = parser->current_token;
    int size_val = 0;
    if (size_tok.type != TOK_INT_LITERAL) {
      report_error(parser, "Expected integer array size");
    } else {
      size_val = (int)parse_int_token_text(size_tok.text ? size_tok.text : "0");
      advance_token(parser);
    }
    consume(parser, TOK_RBRACKET, "Expected ']' after array size");
    if (dim_count < max_dims)
      dims[dim_count++] = size_val;
  }
  return dim_count;
}

/* Handles C-style array brackets written after the variable name:
   `int a[2][3];`. The type may already own dimensions from `int[2] a`, so the
   two shapes are concatenated. Returns TOK_KW_FIXED when a suffix was seen. */
static TokenType apply_name_array_suffix(Parser *parser, TokenType var_type) {
  if (parser->current_token.type != TOK_LBRACKET)
    return var_type;

  TokenType elem_type = var_type;
  int dims[MAX_ARRAY_DIMS];
  int dim_count = 0;
  if (var_type == TOK_KW_FIXED) {
    elem_type = last_array_elem_type;
    dim_count = last_array_dim_count;
    for (int i = 0; i < dim_count; i++)
      dims[i] = last_array_dims[i];
  }

  int suffix[MAX_ARRAY_DIMS];
  int suffix_count = parse_bracket_dims(parser, suffix, MAX_ARRAY_DIMS);
  for (int i = 0; i < suffix_count && dim_count < MAX_ARRAY_DIMS; i++)
    dims[dim_count++] = suffix[i];

  if (dim_count == 0) {
    dims[0] = 1;
    dim_count = 1;
  }
  if (elem_type == TOK_KW_AUTO)
    elem_type = TOK_KW_INT;
  array_shape_set(elem_type, dims, dim_count);
  return TOK_KW_FIXED;
}

/* C initializers nest braces for every dimension: `{{1,2},{3,4}}`. The
   backend stores a fixed array as a flat run of 8-byte slots, so the parser
   flattens the nested literal (row-major) before handing it over. */
static void flatten_array_init_collect(ASTNode *node, int dims_left,
                                       ASTNode *out) {
  if (!node)
    return;
  if (dims_left > 0 && node->type == AST_STRUCT_LITERAL) {
    for (int i = 0; i < node->child_count; i++)
      flatten_array_init_collect(node->children[i], dims_left - 1, out);
  } else {
    ASTNode_add_child(out, ASTNode_clone(node));
  }
}

static ASTNode *flatten_array_initializer(ASTNode *init, int dim_count) {
  if (!init || init->type != AST_STRUCT_LITERAL || dim_count <= 1)
    return init;
  ASTNode *flat = ASTNode_create(AST_STRUCT_LITERAL, init->token);
  flatten_array_init_collect(init, dim_count, flat);
  flat->int_value = flat->child_count;
  ASTNode_free(init);
  return flat;
}

static ASTNode *parse_statement(Parser *parser);
static ASTNode *parse_expression(Parser *parser);
static ASTNode *parse_block(Parser *parser);

/* Element width in bytes for `p[i]` indexing. Defaults to 8 like the rest of
   the language; byte pointers (char, byte, bool) must stride by 1. */
static int parser_index_stride(ASTNode *base) {
  ASTNode *b = base;
  while (b && b->type == AST_CAST_EXPR && b->children[0]) b = b->children[0];
  int w = 0;
  if (b) {
    if (b->type == AST_CAST_EXPR) {
      TokenType t = (TokenType)b->int_value;
      if (t == TOK_KW_CHAR || t == TOK_KW_BYTE || t == TOK_KW_BOOL ||
          t == TOK_KW_STRING)
        w = 1;
      else if (t == TOK_KW_DWORD || t == TOK_KW_FLOAT || t == TOK_KW_HALF)
        w = 4;
      else if (t == TOK_KW_WORD)
        w = 2;
      else if (t == TOK_KW_ANY)
        w = 16;
    } else if (b->type == AST_IDENTIFIER_EXPR && b->token.text) {
      for (int i = 0; i < parser_var_count; i++) {
        if (strcmp(parser_vars[i].name, b->token.text) != 0) continue;
        TokenType t = parser_vars[i].type;
        const char *tn = parser_vars[i].type_name;
        if (t == TOK_KW_CHAR || t == TOK_KW_BYTE || t == TOK_KW_BOOL ||
            t == TOK_KW_STRING)
          w = 1;
        else if (t == TOK_KW_WORD)
          w = 2;
        else if (t == TOK_KW_DWORD || t == TOK_KW_FLOAT || t == TOK_KW_HALF)
          w = 4;
        else if (t == TOK_KW_ANY)
          w = 16;
        else if ((t == TOK_KW_PTR || t == TOK_KW_REF || t == TOK_KW_OWN ||
                  t == TOK_KW_RAW) && tn && strcmp(tn, "any") == 0)
          w = 16;
        else if ((t == TOK_KW_PTR || t == TOK_KW_REF || t == TOK_KW_OWN ||
                  t == TOK_KW_RAW) &&
                 tn && (strcmp(tn, "char") == 0 || strcmp(tn, "byte") == 0 ||
                        strcmp(tn, "bool") == 0))
          w = 1;
        else if ((t == TOK_KW_PTR || t == TOK_KW_REF || t == TOK_KW_OWN ||
                  t == TOK_KW_RAW) &&
                  tn && (strcmp(tn, "word") == 0))
          w = 2;
        else if ((t == TOK_KW_PTR || t == TOK_KW_REF || t == TOK_KW_OWN ||
                  t == TOK_KW_RAW) &&
                 tn && (strcmp(tn, "half") == 0 || strcmp(tn, "dword") == 0 ||
                        strcmp(tn, "float") == 0))
          w = 4;
        break;
      }
    }
  }
  return w ? w : 8;
}

/* Element type behind `*p` / `p[i]` when the pointee is known at parse time.
   Used to tag a dereference of a `string*` as a string so the backend prints
   it as text instead of as an integer address. */
static TokenType parser_pointee_type(ASTNode *node) {
  if (!node)
    return TOK_UNKNOWN;
  if (node->type == AST_CAST_EXPR)
    return (TokenType)node->int_value;
  if (node->type == AST_IDENTIFIER_EXPR && node->token.text) {
    ParserVar *pv = lookup_parser_var(node->token.text);
    if (pv && (pv->type == TOK_KW_PTR || pv->type == TOK_KW_REF ||
               pv->type == TOK_KW_OWN || pv->type == TOK_KW_RAW) &&
        pv->type_name) {
      if (strcmp(pv->type_name, "string") == 0) return TOK_KW_STRING;
      if (strcmp(pv->type_name, "any") == 0) return TOK_KW_ANY;
      if (strcmp(pv->type_name, "char") == 0 ||
          strcmp(pv->type_name, "byte") == 0 ||
          strcmp(pv->type_name, "bool") == 0) return TOK_KW_CHAR;
      if (strcmp(pv->type_name, "float") == 0 ||
          strcmp(pv->type_name, "dword") == 0 ||
          strcmp(pv->type_name, "half") == 0) return TOK_KW_FLOAT;
    }
  }
  return TOK_UNKNOWN;
}

/* Human-readable name of a primitive type token, used when a generic
   pointer type (`ref<T>`, `own<T>`, `raw<T>`) has to remember the pointee
   width for the backend. */
static const char *primitive_type_name(TokenType t) {
  switch (t) {
  case TOK_KW_CHAR:   return "char";
  case TOK_KW_BYTE:   return "byte";
  case TOK_KW_BOOL:   return "bool";
  case TOK_KW_STRING: return "string";
  case TOK_KW_DWORD:  return "dword";
  case TOK_KW_FLOAT:  return "float";
  case TOK_KW_HALF:   return "half";
  case TOK_KW_INT:    return "int";
  case TOK_KW_WORD:   return "word";
  case TOK_KW_QWORD:  return "qword";
  case TOK_KW_ANY:    return "any";
  default:            return NULL;
  }
}

/* `volatile`/`register` are type qualifiers: they may appear before or after
   the base type. Returns true when `volatile` was seen so the caller can
   attach it to the declaration. */
static bool consume_type_qualifiers(Parser *parser) {
  bool is_vol = false;
  while (parser->current_token.type == TOK_KW_VOLATILE ||
         parser->current_token.type == TOK_KW_REGISTER) {
    if (parser->current_token.type == TOK_KW_VOLATILE) is_vol = true;
    advance_token(parser);
  }
  return is_vol;
}

static int parse_type_depth = 0;
static bool last_type_is_volatile = false;
/* `expr as int * 2` must lex the star as multiplication, not as pointer
   syntax. While parsing an `as` type, trailing stars are therefore left for
   parse_as_cast() to disambiguate after the base type is known. */
static bool suppress_type_star = false;

static TokenType parse_type_impl(Parser *parser);

static TokenType parse_type(Parser *parser) {
  if (parse_type_depth == 0) last_type_is_volatile = false;
  parse_type_depth++;
  TokenType type = parse_type_impl(parser);
  if (consume_type_qualifiers(parser)) last_type_is_volatile = true;
  parse_type_depth--;
  return type;
}

static TokenType parse_type_impl(Parser *parser) {
  if (consume_type_qualifiers(parser)) last_type_is_volatile = true;
  TokenType t = parser->current_token.type;
  if (t == TOK_KW_AUTO) {
    advance_token(parser);
    return TOK_KW_AUTO;
  }
  if (t == TOK_KW_TYPEOF) {
    advance_token(parser);
    consume(parser, TOK_LPAREN, "Expected '(' after typeof");
    last_type_name = NULL;
    TokenType resolved_t = TOK_KW_INT;
    if (token_starts_type(parser)) {
      resolved_t = parse_type(parser);
    } else {
      ASTNode *typeof_expr = parse_expression(parser);
      resolved_t = deduce_decl_type(typeof_expr);
      if (typeof_expr) {
        if (typeof_expr->type == AST_IDENTIFIER_EXPR) {
          ParserVar *pv = lookup_parser_var(typeof_expr->token.text);
          if (pv && pv->type_name)
            last_type_name = remember_type_name(pv->type_name);
        } else if (typeof_expr->type == AST_CAST_EXPR &&
                   typeof_expr->string_value) {
          last_type_name = remember_type_name(typeof_expr->string_value);
        } else if (typeof_expr->type == AST_STRUCT_LITERAL &&
                   typeof_expr->string_value) {
          last_type_name = remember_type_name(typeof_expr->string_value);
        }
        ASTNode_free(typeof_expr);
      }
    }
    consume(parser, TOK_RPAREN, "Expected ')' after typeof expression");
    while (parser->current_token.type == TOK_STAR) {
      advance_token(parser);
      resolved_t = TOK_KW_PTR;
    }
    return resolved_t;
  }

  if (t == TOK_KW_RANGE) {
    advance_token(parser);
    parser_ensure_range_struct();
    last_type_name = remember_type_name("range");
    return TOK_KW_INT;
  }

TokenType base_type = TOK_UNKNOWN;
    if (t == TOK_KW_INT || t == TOK_KW_FLOAT || t == TOK_KW_BOOL ||
        t == TOK_KW_CHAR || t == TOK_KW_STRING ||
        t == TOK_KW_VOID || t == TOK_KW_BYTE || t == TOK_KW_WORD ||
        t == TOK_KW_DWORD || t == TOK_KW_QWORD || t == TOK_KW_HALF ||
        t == TOK_KW_ANY) {
        TokenType pointee = t; /* base type before any '*' -- needed for byte access */
        const char* base_name = NULL;
        int depth = 0;
        advance_token(parser);
        while (!suppress_type_star && parser->current_token.type == TOK_STAR) {
            advance_token(parser);
            depth++;
            t = TOK_KW_PTR;
            /* `char*` collapses to TOK_KW_PTR, which loses the fact that the
               pointee is a byte. Record the base type name so the backend can
               emit movzx/mov byte accesses for `*p` and `p[i]`. */
            if (!last_type_name) {
                switch (pointee) {
                    case TOK_KW_CHAR:   base_name = "char";   break;
                    case TOK_KW_BYTE:   base_name = "byte";   break;
                    case TOK_KW_BOOL:   base_name = "bool";   break;
                    case TOK_KW_STRING: base_name = "string"; break;
                    case TOK_KW_DWORD:  base_name = "dword";  break;
                    case TOK_KW_FLOAT:  base_name = "float";  break;
                    case TOK_KW_HALF:   base_name = "half";   break;
                    case TOK_KW_ANY:    base_name = "any";    break;
                    case TOK_KW_INT:    base_name = "int";    break;
                    default: break;
                }
                if (base_name) last_type_name = base_name;
            }
        }
        /* `char** argv` indexes over pointers, not bytes: keep one '*' per extra
           level so the stride logic sees "char*" and falls back to 8 bytes. */
        if (depth > 1 && last_type_name && last_type_name == base_name) {
            last_type_name = type_name_with_depth(base_name, depth);
        }
        base_type = t;
  } else if ((t == TOK_KW_RAW || t == TOK_KW_PTR) &&
             parser->next_token.type != TOK_LT) {
    /* Bare `raw`/`ptr` is the 8-byte raw storage type. */
    last_type_name = NULL;
    advance_token(parser);
    base_type = t;
  } else if (t == TOK_KW_REF || t == TOK_KW_OWN ||
             ((t == TOK_KW_RAW || t == TOK_KW_PTR) &&
              parser->next_token.type == TOK_LT)) {
    /* `ref<T>`, `own<T>`, `raw<T>` and `ptr<T>` are pointer-like wrappers.
       The pointee name is kept so `raw<char>`/`ptr<char>` index by byte. */
    last_type_name = NULL;
    advance_token(parser);
    consume(parser, TOK_LT, "Expected '<' after pointer type");
    TokenType pointee_type = parse_type(parser);
    const char *pointee_name = last_type_name;
    if (!pointee_name) pointee_name = primitive_type_name(pointee_type);
    last_type_name = pointee_name ? remember_type_name(pointee_name) : NULL;
    consume(parser, TOK_GT, "Expected '>' after ref/own/raw");
    base_type = t;
  } else if (t == TOK_IDENTIFIER) {
    StructType *st = lookup_struct(parser->current_token.text);
    if (st) {
      last_type_name = st->name;
      advance_token(parser);
      TokenType type_res = TOK_KW_INT;
      while (!suppress_type_star && parser->current_token.type == TOK_STAR) {
        advance_token(parser);
        type_res = TOK_KW_PTR;
      }
      base_type = type_res;
    }
  } else if (t == TOK_KW_FIXED || t == TOK_KW_ARRAY) {
    advance_token(parser);
    consume(parser, TOK_LT, "Expected '<' after array");
    TokenType elem_t = parse_type(parser);
    /* A nested `fixed<fixed<int,3>,2>` already recorded the inner shape;
       capture it before the outer dimension overwrites the globals. */
    ArrayShape inner;
    array_shape_capture(&inner);
    consume(parser, TOK_COMMA, "Expected ',' after array type");
    Token size_tok = parser->current_token;
    int size_val = (int)parse_int_token_text(size_tok.text ? size_tok.text : "0");
    consume(parser, TOK_INT_LITERAL, "Expected integer array size");
    consume(parser, TOK_GT, "Expected '>' after array size");
    int dims[MAX_ARRAY_DIMS];
    int dim_count = 0;
    if (elem_t == TOK_KW_FIXED && inner.dim_count > 0) {
      /* Outer dimension comes first: `fixed<fixed<int,3>,2>` is a [2][3]
         array, just like `int[2][3]`. */
      dims[dim_count++] = size_val;
      for (int i = 0; i < inner.dim_count && dim_count < MAX_ARRAY_DIMS; i++)
        dims[dim_count++] = inner.dims[i];
      array_shape_set(inner.elem_type == TOK_UNKNOWN ? TOK_KW_INT
                                                     : inner.elem_type,
                      dims, dim_count);
    } else {
      dims[0] = size_val;
      array_shape_set(elem_t, dims, 1);
    }
    return TOK_KW_FIXED;
  } else if (t == TOK_KW_TUPLE) {
    advance_token(parser);
    consume(parser, TOK_LT, "Expected '<' after tuple");
    static int tuple_counter = 0;
    char tuple_name[64];
    snprintf(tuple_name, sizeof(tuple_name), "tuple_%d", tuple_counter++);
    StructType *st = &struct_types[struct_type_count++];
    st->name = strdup(tuple_name);
    st->field_count = 0;
    st->size = 0;
    do {
      TokenType field_t = parse_type(parser);
      bool field_volatile = last_type_is_volatile;
      char field_name[16];
      snprintf(field_name, sizeof(field_name), "_%d", st->field_count);
      StructField *f = &st->fields[st->field_count++];
      f->name = strdup(field_name);
      f->offset = st->size;
      f->field_type = field_t;
      f->array_size = 0;
      f->array_dim_count = 0;
      f->array_elem_type = field_t;
      f->is_volatile = field_volatile;
      st->size += parser_elem_slot_size(field_t);
    } while (match(parser, TOK_COMMA));
    consume(parser, TOK_GT, "Expected '>' after tuple types");
    last_type_name = st->name;
    return TOK_KW_INT;
  } else if (t == TOK_KW_DYN) {
    advance_token(parser);
    consume(parser, TOK_LT, "Expected '<' after dyn");
    TokenType elem_t = parse_type(parser);
    consume(parser, TOK_GT, "Expected '>' after dyn type");
    last_array_elem_type = elem_t;
    return TOK_KW_DYN;
  } else if (t == TOK_KW_SLICE) {
    advance_token(parser);
    consume(parser, TOK_LT, "Expected '<' after slice");
    TokenType elem_t = parse_type(parser);
    consume(parser, TOK_GT, "Expected '>' after slice type");
    last_array_elem_type = elem_t;
    return TOK_KW_SLICE;
  }

  if (consume_type_qualifiers(parser)) last_type_is_volatile = true;

  if (base_type != TOK_UNKNOWN) {
    if (parser->current_token.type == TOK_LBRACKET) {
      int dims[MAX_ARRAY_DIMS];
      int dim_count = parse_bracket_dims(parser, dims, MAX_ARRAY_DIMS);
      array_shape_set(base_type, dims, dim_count);
      return TOK_KW_FIXED;
    }
    return base_type;
  }

  return TOK_UNKNOWN;
}

/* `x++`, `++x`, `x--`, `--x` desugar to `x = x + 1` / `x = x - 1` exactly the
   way compound assignment is rewritten in parse_expression(): the expression
   yields the assigned (new) value. */
static ASTNode *build_inc_dec(ASTNode *target, TokenType op_type) {
  bool is_inc = (op_type == TOK_INC);

  Token bin_tok = target->token;
  bin_tok.type = is_inc ? TOK_PLUS : TOK_MINUS;
  bin_tok.text = (char *)(is_inc ? "+" : "-");
  ASTNode *arith = ASTNode_create(AST_BINARY_EXPR, bin_tok);
  ASTNode_add_child(arith, ASTNode_clone(target));

  Token one_tok = bin_tok;
  one_tok.type = TOK_INT_LITERAL;
  one_tok.text = (char *)"1";
  ASTNode *one = ASTNode_create(AST_LITERAL_EXPR, one_tok);
  one->int_value = 1;
  ASTNode_add_child(arith, one);

  Token assign_tok = target->token;
  assign_tok.type = TOK_ASSIGN;
  assign_tok.text = (char *)"=";
  ASTNode *assign = ASTNode_create(AST_BINARY_EXPR, assign_tok);
  ASTNode_add_child(assign, target);
  ASTNode_add_child(assign, arith);
  return assign;
}

/* Array shape behind an indexable expression: a local/global array variable
   or an array field (`buf.data`). Returns false for plain pointers. */
static bool get_array_info(ASTNode *node, int *dims, int *dim_count,
                           TokenType *elem_type) {
  if (!node)
    return false;
  if (node->type == AST_IDENTIFIER_EXPR) {
    ParserVar *pv = lookup_parser_var(node->token.text);
    if (pv && pv->type == TOK_KW_FIXED && pv->array_dim_count > 0) {
      *dim_count = pv->array_dim_count;
      for (int i = 0; i < *dim_count && i < MAX_ARRAY_DIMS; i++)
        dims[i] = pv->array_dims[i];
      *elem_type = pv->array_elem_type;
      return true;
    }
    /* `dyn<T>` / `slice<T>` are one-dimensional value arrays behind a
       pointer; treating them like a fixed [1] shape lets the index rewrite
       remember the element type (e.g. string) for the backend. */
    if (pv && (pv->type == TOK_KW_DYN || pv->type == TOK_KW_SLICE) &&
        pv->array_elem_type != TOK_UNKNOWN) {
      *dim_count = 1;
      dims[0] = 1;
      *elem_type = pv->array_elem_type;
      return true;
    }
    /* A `string*` (e.g. what `alloc<string>(n)` returns) is an array of
       8-byte string slots, not a byte pointer into one string. */
    if (pv && pv->type == TOK_KW_PTR && pv->type_name &&
        strcmp(pv->type_name, "string") == 0) {
      *dim_count = 1;
      dims[0] = 1;
      *elem_type = TOK_KW_STRING;
      return true;
    }
    return false;
  }
  if (node->type == AST_MEMBER_ACCESS && node->child_count > 0) {
    ASTNode *base = node->children[0];
    const char *type_name = NULL;
    if (base->type == AST_IDENTIFIER_EXPR) {
      ParserVar *pv = lookup_parser_var(base->token.text);
      if (pv)
        type_name = pv->type_name;
    }
    if (type_name) {
      StructType *st = lookup_struct(type_name);
      StructField *f = find_field(st, node->token.text);
      if (f && f->array_size > 0) {
        int nd = f->array_dim_count > 0 ? f->array_dim_count : 1;
        if (nd > MAX_ARRAY_DIMS) nd = MAX_ARRAY_DIMS;
        *dim_count = nd;
        for (int i = 0; i < nd; i++) {
          if (i < f->array_dim_count)
            dims[i] = f->array_dims[i];
          else
            dims[i] = (i == 0) ? f->array_size : 1;
        }
        int et = f->array_elem_type;
        *elem_type = (TokenType)(et != TOK_UNKNOWN ? et : f->field_type);
        return true;
      }
    }
  }
  return false;
}

static ASTNode *make_index_mul(ASTNode *index, int stride, Token proto) {
  Token mul_tok = proto;
  mul_tok.type = TOK_STAR;
  mul_tok.text = (char *)"*";
  ASTNode *mul = ASTNode_create(AST_BINARY_EXPR, mul_tok);
  ASTNode_add_child(mul, index);

  Token lit_tok = proto;
  lit_tok.type = TOK_INT_LITERAL;
  lit_tok.text = (char *)"0";
  ASTNode *lit = ASTNode_create(AST_LITERAL_EXPR, lit_tok);
  lit->int_value = stride;
  ASTNode_add_child(mul, lit);
  return mul;
}

static ASTNode *make_index_add(ASTNode *base, ASTNode *offset, Token proto) {
  Token add_tok = proto;
  add_tok.type = TOK_PLUS;
  add_tok.text = (char *)"+";
  ASTNode *add = ASTNode_create(AST_BINARY_EXPR, add_tok);
  ASTNode_add_child(add, base);
  ASTNode_add_child(add, offset);
  return add;
}

static ASTNode *make_index_deref(ASTNode *addr, TokenType elem_type,
                                 Token proto) {
  Token deref_tok = proto;
  deref_tok.type = TOK_STAR;
  deref_tok.text = (char *)"*";
  ASTNode *deref = ASTNode_create(AST_UNARY_EXPR, deref_tok);
  ASTNode_add_child(deref, addr);
  if (elem_type == TOK_KW_ANY) {
    /* An `any` slot is a 16-byte tagged value. Hand its address to the any
       helpers instead of loading the payload word. */
    deref->string_value = strdup("any");
    deref->int_value = TOK_KW_ANY;
  } else if (elem_type == TOK_KW_CHAR || elem_type == TOK_KW_BYTE ||
             elem_type == TOK_KW_BOOL) {
    deref->string_value = strdup("char");
    deref->int_value = elem_type;
  } else if (elem_type == TOK_KW_DWORD || elem_type == TOK_KW_FLOAT ||
             elem_type == TOK_KW_HALF) {
    deref->string_value = strdup("float");
    deref->int_value = elem_type;
  } else if (elem_type == TOK_KW_STRING) {
    /* An array slot holds a `char*`, so the dereference itself is a string.
       The backend needs this marker to print/concatenate/compare the element
       as text instead of as an integer address. */
    deref->string_value = strdup("string");
    deref->int_value = elem_type;
  }
  return deref;
}

static ASTNode *parse_postfix(Parser *parser, ASTNode *node) {
  if (!node)
    return NULL;
  while (true) {
    if (parser->current_token.type == TOK_INC ||
        parser->current_token.type == TOK_DEC) {
      if (node && node->type == AST_IDENTIFIER_EXPR) {
        ParserVar *pv = lookup_parser_var(node->token.text);
        if (pv && pv->is_const) {
          report_error(parser, "Cannot mutate const variable");
          advance_token(parser);
          return node;
        }
      }
      TokenType op_type = parser->current_token.type;
      advance_token(parser);
      node = build_inc_dec(node, op_type);
      continue;
    }
    if (match(parser, TOK_DOT)) {
      Token field_tok = parser->current_token;
      char *field_name_copy = field_tok.text ? strdup(field_tok.text) : NULL;
      if (field_tok.type == TOK_IDENTIFIER || field_tok.type == TOK_KW_PTR) {
        advance_token(parser);
      } else {
        report_error(parser, "Expected member field name after '.'");
      }
      ASTNode *access = ASTNode_create(AST_MEMBER_ACCESS, field_tok);
      if (access->token.text) {
        free((void *)access->token.text);
      }
      access->token.text = field_name_copy;
      ASTNode_add_child(access, node);
      node = access;

      if (match(parser, TOK_LPAREN)) {
        ASTNode *call = ASTNode_create(AST_CALL_EXPR, field_tok);
        ASTNode_add_child(call, node);
        if (parser->current_token.type != TOK_RPAREN) {
          do {
            ASTNode_add_child(call, parse_expression(parser));
          } while (match(parser, TOK_COMMA));
        }
        consume(parser, TOK_RPAREN, "Expected ')' after arguments");
        node = call;
      }
    } else if (match(parser, TOK_LBRACKET)) {
      ASTNode *index_expr = parse_expression(parser);
      int first_extent = parser_fixed_extent(node);
      check_literal_index(parser, index_expr, first_extent, 0);
      if (parser->current_token.type == TOK_RANGE) {
        Token range_tok = parser->current_token;
        advance_token(parser); // Consume '..'
        ASTNode *end_expr = parse_expression(parser);
        consume(parser, TOK_RBRACKET, "Expected ']' after slice index");

        ASTNode *slice_node = ASTNode_create(AST_SLICE_EXPR, range_tok);
        ASTNode_add_child(slice_node, node);       // Child 0: receiver
        ASTNode_add_child(slice_node, index_expr); // Child 1: start
        ASTNode_add_child(slice_node, end_expr);   // Child 2: end
        node = slice_node;
      } else {
        consume(parser, TOK_RBRACKET, "Expected ']' after index");

        int dims[MAX_ARRAY_DIMS];
        int dim_count = 0;
        TokenType elem_type = TOK_UNKNOWN;
        bool is_array = get_array_info(node, dims, &dim_count, &elem_type);

        if (is_array) {
          /* C-style multi-dimensional subscripting, row-major. Every array
             slot is 8 bytes wide in Magnetar. Consume every following
             `[k]` that still fits the array shape, so `a[i][j][k]` becomes a
             single flattened access. A partial index (`a[i]` on a 2-D array)
             yields the address of the sub-array, like C's array decay. */
          int used = 1;
          int elem_slot = parser_elem_slot_size(elem_type);
          int stride = elem_slot;
          for (int d = 1; d < dim_count; d++)
            stride *= dims[d] > 0 ? dims[d] : 1;
          ASTNode *offset = make_index_mul(index_expr, stride, index_expr->token);

          while (used < dim_count &&
                 parser->current_token.type == TOK_LBRACKET) {
            advance_token(parser);
            ASTNode *next_index = parse_expression(parser);
            if (used < dim_count && dims[used] > 0)
              check_literal_index(parser, next_index, dims[used], used);
            consume(parser, TOK_RBRACKET, "Expected ']' after index");
            int next_stride = elem_slot;
            for (int d = used + 1; d < dim_count; d++)
              next_stride *= dims[d] > 0 ? dims[d] : 1;
            ASTNode *term =
                make_index_mul(next_index, next_stride, next_index->token);
            offset = make_index_add(offset, term, next_index->token);
            used++;
          }

          ASTNode *addr = make_index_add(node, offset, index_expr->token);
          if (used >= dim_count) {
            node = make_index_deref(addr, elem_type, index_expr->token);
          } else {
            node = addr;
          }
        } else {
          Token plus_tok = index_expr->token;
          plus_tok.type = TOK_PLUS;
          plus_tok.text = strdup("+");
          ASTNode *add_node = ASTNode_create(AST_BINARY_EXPR, plus_tok);
          free(plus_tok.text); /* ASTNode_create ينسخ النص، نحرر الأصل */
          ASTNode_add_child(add_node, node);

          int stride = parser_index_stride(node);
          ASTNode *scale_node =
              make_index_mul(index_expr, stride, index_expr->token);
          ASTNode_add_child(add_node, scale_node);

          Token deref_tok = index_expr->token;
          deref_tok.type = TOK_STAR;
          deref_tok.text = strdup("*");
          ASTNode *deref_node = ASTNode_create(AST_UNARY_EXPR, deref_tok);
          free(deref_tok.text); /* ASTNode_create ينسخ النص، نحرر الأصل */
          ASTNode_add_child(deref_node, add_node);
          /* `a[i]` becomes `*(a + i*stride)`; that rewrite hides the pointee
             type from the backend, so `cast<char*>(p)[0]` would load eight
             bytes instead of one. Keep the pointee name on the deref node. */
          if (parser_pointee_type(node) == TOK_KW_ANY) {
            deref_node->string_value = strdup("any");
            deref_node->int_value = TOK_KW_ANY;
          } else if (node->type == AST_CAST_EXPR && node->string_value) {
            deref_node->string_value = strdup(node->string_value);
            deref_node->int_value = node->int_value;
          }
          node = deref_node;
        }
      }
    } else {
      break;
    }
  }
  return node;
}

static ASTNode *parse_primary(Parser *parser) {
  Token t = parser->current_token;
  ASTNode *node = NULL;

  if (t.type == TOK_KW_SPAWN) {
    /* `spawn { ... }` and `spawn expr` are expressions: the parent receives
       the child pid, the child receives 0. */
    advance_token(parser);
    node = ASTNode_create(AST_SPAWN_STMT, t);
    if (parser->current_token.type == TOK_LBRACE)
      ASTNode_add_child(node, parse_block(parser));
    else
      ASTNode_add_child(node, parse_expression(parser));
    return node;
  } else if (t.type == TOK_KW_ASYNC || t.type == TOK_KW_PARALLEL) {
    /* `async { ... }` / `parallel { ... }` are also statements, but as
       expressions they yield the child pid / joined value respectively. */
    advance_token(parser);
    node = ASTNode_create(t.type == TOK_KW_ASYNC ? AST_ASYNC_STMT
                                                 : AST_PARALLEL_STMT, t);
    if (parser->current_token.type == TOK_LBRACE)
      ASTNode_add_child(node, parse_block(parser));
    else
      ASTNode_add_child(node, parse_statement(parser));
    return node;
  } else if (t.type == TOK_KW_AWAIT) {
    advance_token(parser);
    node = ASTNode_create(AST_AWAIT_STMT, t);
    if (parser->current_token.type != TOK_SEMICOLON &&
        parser->current_token.type != TOK_RPAREN &&
        parser->current_token.type != TOK_RBRACE &&
        parser->current_token.type != TOK_COMMA)
      ASTNode_add_child(node, parse_expression(parser));
    return node;
  } else if (t.type == TOK_INT_LITERAL) {
    node = ASTNode_create(AST_LITERAL_EXPR, t);
    node->int_value = parse_int_token_text(t.text);
    advance_token(parser);
  } else if (t.type == TOK_STRING_LITERAL) {
    node = ASTNode_create(AST_LITERAL_EXPR, t);
    size_t len = strlen(t.text);
    if (len >= 2 && t.text[0] == '"' && t.text[len - 1] == '"') {
      node->string_value = (char *)malloc(len);
      int j = 0;
      for (size_t i = 1; i < len - 1; i++) {
        if (t.text[i] == '\\' && i + 1 < len - 1) {
          char e = t.text[i + 1];
          if (e == 'n') {
            node->string_value[j++] = '\n';
            i++;
          } else if (e == 't') {
            node->string_value[j++] = '\t';
            i++;
          } else if (e == 'r') {
            node->string_value[j++] = '\r';
            i++;
          } else if (e == 'a') {
            node->string_value[j++] = '\a';
            i++;
          } else if (e == 'b') {
            node->string_value[j++] = '\b';
            i++;
          } else if (e == 'f') {
            node->string_value[j++] = '\f';
            i++;
          } else if (e == 'v') {
            node->string_value[j++] = '\v';
            i++;
          } else if (e == 'e') {
            node->string_value[j++] = '\033'; /* ANSI escapes: "\e[1;33m" */
            i++;
          } else if (e >= '0' && e <= '7') {
            /* \NNN octal, up to three digits: the only way to type a raw ESC. */
            int val = 0;
            int digits = 0;
            while (digits < 3 && (t.text[i + 1 + digits] >= '0') &&
                   (t.text[i + 1 + digits] <= '7') && (i + 1 + digits) < len - 1) {
              val = val * 8 + (t.text[i + 1 + digits] - '0');
              digits++;
            }
            node->string_value[j++] = (char)val;
            i += digits;
          } else if (e == 'x' && i + 2 < len - 1) {
            int val = 0;
            int digits = 0;
            while (digits < 2 && i + 2 + digits < len - 1 &&
                   isxdigit((unsigned char)t.text[i + 2 + digits])) {
              char h = t.text[i + 2 + digits];
              int hv = (h >= '0' && h <= '9') ? h - '0'
                                             : (tolower((unsigned char)h) - 'a' + 10);
              val = val * 16 + hv;
              digits++;
            }
            if (digits > 0) {
              node->string_value[j++] = (char)val;
              i += 1 + digits;
            } else {
              node->string_value[j++] = t.text[i];
            }
          } else if (e == '\\') {
            node->string_value[j++] = '\\';
            i++;
          } else if (e == '\'') {
            node->string_value[j++] = '\'';
            i++;
          } else if (e == '"') {
            node->string_value[j++] = '"';
            i++;
          } else {
            node->string_value[j++] = t.text[i];
          }
        } else {
          node->string_value[j++] = t.text[i];
        }
      }
      node->string_value[j] = '\0';
    } else {
      node->string_value = strdup(t.text);
    }
    advance_token(parser);
  } else if (t.type == TOK_FLOAT_LITERAL) {
    node = ASTNode_create(NODE_FLOAT_LIT, t);
    node->float_value = parse_float_token_text(t.text);
    advance_token(parser);
  } else if (t.type == TOK_KW_TRUE || t.type == TOK_KW_FALSE) {
    node = ASTNode_create(NODE_BOOL_LIT, t);
    node->bool_value = (t.type == TOK_KW_TRUE);
    advance_token(parser);
  } else if (t.type == TOK_KW_NULL) {
    node = ASTNode_create(AST_LITERAL_EXPR, t);
    node->int_value = 0;
    advance_token(parser);
  } else if (t.type == TOK_KW_THIS || t.type == TOK_KW_SELF) {
    node = ASTNode_create(NODE_THIS, t);
    advance_token(parser);
  } else if (t.type == TOK_KW_SUPER || t.type == TOK_KW_BASE) {
    node = ASTNode_create(NODE_SUPER, t);
    advance_token(parser);
  } else if (t.type == TOK_CHAR_LITERAL) {
    node = ASTNode_create(NODE_CHAR_LIT, t);
    node->char_value = decode_char_literal(t.text);
    advance_token(parser);
  } else if (t.type == TOK_IDENTIFIER || t.type == TOK_KW_PTR) {
    node = ASTNode_create(AST_IDENTIFIER_EXPR, t);
    advance_token(parser);
    /* `Point { 1, 2 }` is an aggregate literal whose type is written down.
       Only a name that is registered as a struct type may be followed by a
       brace, so an ordinary variable is never mistaken for one. */
    if (t.type == TOK_IDENTIFIER && t.text &&
        lookup_struct(t.text) != NULL &&
        parser->current_token.type == TOK_LBRACE) {
      ASTNode *lit = ASTNode_create(AST_STRUCT_LITERAL, t);
      lit->string_value = strdup(t.text);
      advance_token(parser);
      int elem_count = 0;
      if (parser->current_token.type != TOK_RBRACE) {
        do {
          ASTNode_add_child(lit, parse_expression(parser));
          elem_count++;
        } while (match(parser, TOK_COMMA));
      }
      lit->int_value = elem_count;
      consume(parser, TOK_RBRACE, "Expected '}' after struct literal");
      return parse_postfix(parser, lit);
    }
    if (match(parser, TOK_LPAREN)) {
      ASTNode *call = ASTNode_create(AST_CALL_EXPR, node->token);
      ASTNode_add_child(call, node);
      if (parser->current_token.type != TOK_RPAREN) {
        do {
          ASTNode_add_child(call, parse_expression(parser));
        } while (match(parser, TOK_COMMA));
      }
      consume(parser, TOK_RPAREN, "Expected ')' after arguments");
      node = call;
      /* Inside a method of a type, a call to a sibling method may omit the
         receiver: `mag()` instead of `this.mag()`. The call is rewritten to
         the mangled name and the receiver is passed implicitly. */
      if (current_type_context && node->children[0] &&
          node->children[0]->token.text) {
        char mangled[256];
        snprintf(mangled, sizeof(mangled), "%s_%s", current_type_context,
                 node->children[0]->token.text);
        if (lookup_parser_func(mangled)) {
          rewrite_call_to_mangled(node, mangled);
        }
      }
      if (node->children[0] && node->children[0]->token.text) {
        ParserFunc *pf = lookup_parser_func(node->children[0]->token.text);
        if (pf && pf->return_type_name)
          node->string_value = strdup(pf->return_type_name);
      }
    }
  } else if (t.type == TOK_KW_ALLOC) {
    advance_token(parser);
    consume(parser, TOK_LT, "Expected '<' after alloc");
    Token type_token = parser->current_token;
    char *type_name = (type_token.type == TOK_IDENTIFIER && type_token.text)
                          ? strdup(type_token.text)
                          : NULL;
    TokenType base_type = parse_type(parser);
    consume(parser, TOK_GT, "Expected '>' after alloc type");
    consume(parser, TOK_LPAREN, "Expected '(' after alloc");
    ASTNode *count_expr = parse_expression(parser);
    consume(parser, TOK_RPAREN, "Expected ')' after alloc argument");

    node = ASTNode_create(AST_ALLOC_EXPR, t);
    node->int_value = base_type;
    node->string_value = type_name;
    ASTNode_add_child(node, count_expr);
  } else if (t.type == TOK_KW_NEW) {
    advance_token(parser);
    Token type_token = parser->current_token;
    char *type_name = (type_token.type == TOK_IDENTIFIER && type_token.text)
                          ? strdup(type_token.text)
                          : NULL;
    TokenType base_type = parse_type(parser);

    node = ASTNode_create(AST_NEW_EXPR, t);
    node->string_value = type_name;
    node->int_value = base_type;
  } else if (t.type == TOK_KW_NAN) {
    node = ASTNode_create(NODE_NAN_LIT, t);
    advance_token(parser);
  } else if (t.type == TOK_KW_INF) {
    node = ASTNode_create(NODE_INF_LIT, t);
    advance_token(parser);
  } else if (t.type == TOK_KW_RANGE) {
    advance_token(parser);
    consume(parser, TOK_LPAREN, "Expected '(' after range");
    ASTNode *r_start = parse_expression(parser);
    ASTNode *r_end = NULL;
    ASTNode *r_step = NULL;
    if (match(parser, TOK_COMMA)) {
      r_end = parse_expression(parser);
      if (match(parser, TOK_COMMA)) {
        r_step = parse_expression(parser);
      }
    } else {
      r_end = r_start;
      Token zero_tok = t;
      zero_tok.type = TOK_INT_LITERAL;
      zero_tok.text = "0";
      r_start = ASTNode_create(AST_LITERAL_EXPR, zero_tok);
      r_start->int_value = 0;
    }
    consume(parser, TOK_RPAREN, "Expected ')' after range arguments");
    if (!r_step) {
      Token one_tok = t;
      one_tok.type = TOK_INT_LITERAL;
      one_tok.text = "1";
      r_step = ASTNode_create(AST_LITERAL_EXPR, one_tok);
      r_step->int_value = 1;
    }
    node = ASTNode_create(AST_STRUCT_LITERAL, t);
    parser_ensure_range_struct();
    node->string_value = strdup("range");
    node->int_value = 3;
    ASTNode_add_child(node, r_start);
    ASTNode_add_child(node, r_end);
    ASTNode_add_child(node, r_step);
  } else if (t.type == TOK_KW_SIZEOF) {
    advance_token(parser);
    consume(parser, TOK_LPAREN, "Expected '(' after sizeof");
    last_type_name = NULL;
    int size = 8;
    if (token_starts_type(parser)) {
      /* sizeof(T) -- a type: structs use their layout size, primitives their
         declared byte width. */
      TokenType stype = parse_type(parser);
      size = parser_type_size(stype, last_type_name);
    } else {
      /* sizeof(x) / sizeof(expr) -- size of the expression's type. */
      ASTNode *size_expr = parse_expression(parser);
      size = parser_expr_size(size_expr);
    }
    consume(parser, TOK_RPAREN, "Expected ')' after sizeof argument");
    Token size_tok = t;
    size_tok.type = TOK_INT_LITERAL;
    char size_buf[32];
    snprintf(size_buf, sizeof(size_buf), "%d", size);
    size_tok.text = strdup(size_buf);
    node = ASTNode_create(AST_LITERAL_EXPR, size_tok);
    node->int_value = size;
  } else if (t.type == TOK_KW_CAST) {
    advance_token(parser);
    consume(parser, TOK_LT, "Expected '<' after cast");
    last_type_name = NULL;
    TokenType dest_type = parse_type(parser);
    char *dest_name = last_type_name ? strdup(last_type_name) : NULL;
    consume(parser, TOK_GT, "Expected '>' after cast type");
    consume(parser, TOK_LPAREN, "Expected '(' after cast");
    /* The operand is a full expression so cast<int>(a + b) reads naturally; the
       closing paren ends it before any trailing postfix, and parse_primary
       below applies that postfix to the cast result. */
    ASTNode *expr = parse_expression(parser);
    consume(parser, TOK_RPAREN, "Expected ')' after cast expression");

    node = ASTNode_create(AST_CAST_EXPR, t);
    node->int_value = dest_type;
    node->string_value = dest_name;
    ASTNode_add_child(node, expr);
  } else if (t.type == TOK_LBRACE) {
    advance_token(parser);
    node = ASTNode_create(AST_STRUCT_LITERAL, t);
    int elem_count = 0;
    if (parser->current_token.type != TOK_RBRACE) {
      do {
        ASTNode_add_child(node, parse_expression(parser));
        elem_count++;
      } while (match(parser, TOK_COMMA));
    }
    node->int_value = elem_count;
    consume(parser, TOK_RBRACE, "Expected '}' after struct literal");
    return parse_postfix(parser, node);
  } else if (match(parser, TOK_LPAREN)) {
    node = parse_expression(parser);
    if (parser->current_token.type == TOK_COMMA) {
      /* `(a, b, ...)` is a tuple literal. Without a comma the parentheses
         are just grouping and the expression above is already the result. */
      ASTNode *tuple_lit = ASTNode_create(AST_STRUCT_LITERAL, t);
      ASTNode_add_child(tuple_lit, node);
      while (match(parser, TOK_COMMA)) {
        if (parser->current_token.type == TOK_RPAREN) break;
        ASTNode_add_child(tuple_lit, parse_expression(parser));
      }
      tuple_lit->int_value = tuple_lit->child_count;
      node = tuple_lit;
    }
    consume(parser, TOK_RPAREN, "Expected ')' after expression");
  } else {
    report_error(parser, "Unexpected token in expression");
    advance_token(parser);
    return NULL;
  }

  return parse_postfix(parser, node);
}

static bool token_starts_expression(TokenType t) {
  switch (t) {
  case TOK_IDENTIFIER:
  case TOK_INT_LITERAL: case TOK_FLOAT_LITERAL:
  case TOK_STRING_LITERAL: case TOK_CHAR_LITERAL:
  case TOK_LPAREN: case TOK_LBRACE:
  case TOK_MINUS: case TOK_PLUS: case TOK_NOT: case TOK_BIT_NOT:
  case TOK_STAR: case TOK_BIT_AND: case TOK_INC: case TOK_DEC:
  case TOK_KW_TRUE: case TOK_KW_FALSE: case TOK_KW_NULL:
  case TOK_KW_NAN: case TOK_KW_INF: case TOK_KW_SIZEOF:
  case TOK_KW_CAST: case TOK_KW_ALLOC: case TOK_KW_NEW:
  case TOK_KW_TYPEOF: case TOK_KW_MOVE: case TOK_KW_COPY:
  case TOK_KW_CLONE: case TOK_KW_BORROW:
    return true;
  default:
    return false;
  }
}

/* `expr as Type` -- a cast with the same result shape as cast<Type>(expr).
   It binds tighter than the binary operators and looser than unary operators,
   so `-x as int` is `-(x as int)` and `a + b as int` is `a + (b as int)`. */
static ASTNode *parse_as_cast(Parser *parser) {
  ASTNode *node = parse_primary(parser);
  while (parser->current_token.type == TOK_KW_AS) {
    Token as_tok = parser->current_token;
    advance_token(parser);
    last_type_name = NULL;
    suppress_type_star = true;
    TokenType dest_type = parse_type(parser);
    suppress_type_star = false;
    char *dest_name = last_type_name ? strdup(last_type_name) : NULL;
    if (dest_type == TOK_UNKNOWN &&
        parser->current_token.type == TOK_IDENTIFIER) {
      dest_name = strdup(parser->current_token.text);
      advance_token(parser);
      dest_type = TOK_KW_INT;
    }
    /* A trailing `*` belongs to the cast type when the following token
       cannot begin an expression (`as char*;`); otherwise it is the
       multiplication operator (`as int * 2`). */
    bool pointer_cast = false;
    while (parser->current_token.type == TOK_STAR &&
           !token_starts_expression(parser->next_token.type)) {
      advance_token(parser);
      pointer_cast = true;
    }
    if (pointer_cast)
      dest_type = TOK_KW_PTR;
    ASTNode *cast = ASTNode_create(AST_CAST_EXPR, as_tok);
    cast->int_value = dest_type;
    cast->string_value = dest_name;
    ASTNode_add_child(cast, node);
    node = cast;
  }
  return node;
}

static ASTNode *parse_unary(Parser *parser) {
  if (parser->current_token.type == TOK_INC ||
      parser->current_token.type == TOK_DEC) {
    TokenType op_type = parser->current_token.type;
    advance_token(parser);
    ASTNode *operand = parse_unary(parser);
    if (operand && operand->type == AST_IDENTIFIER_EXPR) {
      ParserVar *pv = lookup_parser_var(operand->token.text);
      if (pv && pv->is_const) {
        report_error(parser, "Cannot mutate const variable");
        return operand;
      }
    }
    return build_inc_dec(operand, op_type);
  }
  if (parser->current_token.type == TOK_STAR ||
      parser->current_token.type == TOK_BIT_AND ||
      parser->current_token.type == TOK_MINUS ||
      parser->current_token.type == TOK_NOT ||
      parser->current_token.type == TOK_BIT_NOT ||
      parser->current_token.type == TOK_KW_MOVE ||
      parser->current_token.type == TOK_KW_COPY ||
      parser->current_token.type == TOK_KW_CLONE ||
      parser->current_token.type == TOK_KW_BORROW) {
    Token op = parser->current_token;
    ASTNode *node = ASTNode_create(AST_UNARY_EXPR, op);
    advance_token(parser);
    ASTNode *operand = parse_unary(parser);
    ASTNode_add_child(node, operand);
    if (op.type == TOK_STAR) {
      TokenType pointee = parser_pointee_type(operand);
      if (pointee == TOK_KW_ANY) {
        node->string_value = strdup("any");
        node->int_value = TOK_KW_ANY;
      } else if (pointee == TOK_KW_STRING) {
        node->string_value = strdup("string");
        node->int_value = TOK_KW_STRING;
      }
    }
    return node;
  }
  return parse_as_cast(parser);
}

static ASTNode *parse_multiplicative(Parser *parser) {
  ASTNode *left = parse_unary(parser);
  while (parser->current_token.type == TOK_STAR ||
         parser->current_token.type == TOK_SLASH ||
         parser->current_token.type == TOK_MOD) {
    Token op = parser->current_token;
    ASTNode *bin = ASTNode_create(AST_BINARY_EXPR, op);
    advance_token(parser);
    ASTNode *right = parse_unary(parser);
    ASTNode_add_child(bin, left);
    ASTNode_add_child(bin, right);
    left = bin;
  }
  return left;
}

static ASTNode *parse_additive(Parser *parser) {
  ASTNode *left = parse_multiplicative(parser);
  while (parser->current_token.type == TOK_PLUS ||
         parser->current_token.type == TOK_MINUS) {
    Token op = parser->current_token;
    ASTNode *bin = ASTNode_create(AST_BINARY_EXPR, op);
    advance_token(parser);
    ASTNode *right = parse_multiplicative(parser);
    ASTNode_add_child(bin, left);
    ASTNode_add_child(bin, right);
    left = bin;
  }
  return left;
}

/* Forward declarations for the precedence chain. The chain, from the loosest
   binding to the tightest, mirrors C:

     assignment < ternary < || < && < | < ^ < & < ==/!= < </>/<=/>= < shift
                < additive < multiplicative < unary < postfix

   The previous layout put the comparison level *below* the bitwise operators,
   which made `a == 4 & 1` unparsable and `a == b | c` group differently from C.
   Splitting equality from relational and moving the whole level above the
   bitwise operators restores C semantics on both sides of the operator. */
static ASTNode *parse_equality(Parser *parser);
static ASTNode *parse_relational(Parser *parser);

/* Shift binds looser than additive, tighter than '&' -- C precedence. */
static ASTNode *parse_shift(Parser *parser) {
  ASTNode *left = parse_additive(parser);
  while (parser->current_token.type == TOK_SHL ||
         parser->current_token.type == TOK_SHR) {
    Token op = parser->current_token;
    ASTNode *bin = ASTNode_create(AST_BINARY_EXPR, op);
    advance_token(parser);
    ASTNode *right = parse_additive(parser);
    ASTNode_add_child(bin, left);
    ASTNode_add_child(bin, right);
    left = bin;
  }
  return left;
}

/* Bitwise operator precedence (lowest first). Placed between additive and
   comparison, matching C: a & b | c == d  ==  (a & b) | (c == d) is FALSE in C
   too -- comparisons bind tighter than |. */
static ASTNode *parse_bitwise_and(Parser *parser) {
  ASTNode *left = parse_equality(parser);
  while (parser->current_token.type == TOK_BIT_AND) {
    Token op = parser->current_token;
    ASTNode *bin = ASTNode_create(AST_BINARY_EXPR, op);
    advance_token(parser);
    ASTNode *right = parse_equality(parser);
    ASTNode_add_child(bin, left);
    ASTNode_add_child(bin, right);
    left = bin;
  }
  return left;
}

static ASTNode *parse_bitwise_xor(Parser *parser) {
  ASTNode *left = parse_bitwise_and(parser);
  while (parser->current_token.type == TOK_BIT_XOR) {
    Token op = parser->current_token;
    ASTNode *bin = ASTNode_create(AST_BINARY_EXPR, op);
    advance_token(parser);
    ASTNode *right = parse_bitwise_and(parser);
    ASTNode_add_child(bin, left);
    ASTNode_add_child(bin, right);
    left = bin;
  }
  return left;
}

static ASTNode *parse_bitwise_or(Parser *parser) {
  ASTNode *left = parse_bitwise_xor(parser);
  while (parser->current_token.type == TOK_BIT_OR) {
    Token op = parser->current_token;
    ASTNode *bin = ASTNode_create(AST_BINARY_EXPR, op);
    advance_token(parser);
    ASTNode *right = parse_bitwise_xor(parser);
    ASTNode_add_child(bin, left);
    ASTNode_add_child(bin, right);
    left = bin;
  }
  return left;
}

/* Relational operators bind tighter than equality and looser than shift. */
static ASTNode *parse_relational(Parser *parser) {
  ASTNode *left = parse_shift(parser);
  while (parser->current_token.type == TOK_LT ||
         parser->current_token.type == TOK_LE ||
         parser->current_token.type == TOK_GT ||
         parser->current_token.type == TOK_GE) {
    Token op = parser->current_token;
    ASTNode *bin = ASTNode_create(AST_BINARY_EXPR, op);
    advance_token(parser);
    ASTNode *right = parse_shift(parser);
    ASTNode_add_child(bin, left);
    ASTNode_add_child(bin, right);
    left = bin;
  }
  return left;
}

/* Equality binds tighter than the bitwise operators and looser than the
   relational ones -- C precedence. */
static ASTNode *parse_equality(Parser *parser) {
  ASTNode *left = parse_relational(parser);
  while (parser->current_token.type == TOK_EQ ||
         parser->current_token.type == TOK_NEQ) {
    Token op = parser->current_token;
    ASTNode *bin = ASTNode_create(AST_BINARY_EXPR, op);
    advance_token(parser);
    ASTNode *right = parse_relational(parser);
    ASTNode_add_child(bin, left);
    ASTNode_add_child(bin, right);
    left = bin;
  }
  return left;
}

static ASTNode *parse_logical_and(Parser *parser) {
  ASTNode *left = parse_bitwise_or(parser);
  while (parser->current_token.type == TOK_AND) {
    Token op = parser->current_token;
    ASTNode *bin = ASTNode_create(AST_BINARY_EXPR, op);
    advance_token(parser);
    ASTNode *right = parse_bitwise_or(parser);
    ASTNode_add_child(bin, left);
    ASTNode_add_child(bin, right);
    left = bin;
  }
  return left;
}

static ASTNode *parse_logical(Parser *parser) {
  ASTNode *left = parse_logical_and(parser);
  while (parser->current_token.type == TOK_OR) {
    Token op = parser->current_token;
    ASTNode *bin = ASTNode_create(AST_BINARY_EXPR, op);
    advance_token(parser);
    ASTNode *right = parse_logical_and(parser);
    ASTNode_add_child(bin, left);
    ASTNode_add_child(bin, right);
    left = bin;
  }
  return left;
}

/* `cond ? then : else` -- looser than `||`, tighter than `=`. The branches are
   full expressions (like C) and the operator is right-associative. */
static ASTNode *parse_ternary(Parser *parser) {
  ASTNode *cond = parse_logical(parser);
  if (parser->current_token.type != TOK_QUESTION)
    return cond;
  Token q = parser->current_token;
  advance_token(parser);
  ASTNode *then_expr = parse_expression(parser);
  consume(parser, TOK_COLON, "Expected ':' in ternary expression");
  ASTNode *else_expr = parse_ternary(parser);

  ASTNode *tern = ASTNode_create(AST_TERNARY_EXPR, q);
  ASTNode_add_child(tern, cond);
  ASTNode_add_child(tern, then_expr);
  ASTNode_add_child(tern, else_expr);
  return tern;
}

static ASTNode *parse_expression(Parser *parser) {
  ASTNode *left = parse_ternary(parser);
  if (parser->current_token.type == TOK_ASSIGN) {
    Token op = parser->current_token;
    if (left && left->type == AST_IDENTIFIER_EXPR) {
      ParserVar *pv = lookup_parser_var(left->token.text);
      if (pv && pv->is_const) {
        report_error(parser, "Cannot assign to const variable");
        advance_token(parser);
        parse_expression(parser);
        return left;
      }
    }
    ASTNode *assign = ASTNode_create(AST_BINARY_EXPR, op);
    advance_token(parser);
    /* Assignment is right-associative in C: `a = b = c` assigns c to b and
       then b to a. The right-hand side is therefore parsed as a full
       expression, not as a ternary. */
    ASTNode *right = parse_expression(parser);
    ASTNode_add_child(assign, left);
    ASTNode_add_child(assign, right);
    return assign;
  }
  // handle i++  i--  i+=1  i<<=1  ...
  {
    TokenType compound = parser->current_token.type;
    TokenType binop = TOK_UNKNOWN;
    const char *binop_text = NULL;
    switch (compound) {
    case TOK_PLUS_ASSIGN:  binop = TOK_PLUS;      binop_text = "+";  break;
    case TOK_MINUS_ASSIGN: binop = TOK_MINUS;     binop_text = "-";  break;
    case TOK_STAR_ASSIGN:  binop = TOK_STAR;      binop_text = "*";  break;
    case TOK_SLASH_ASSIGN: binop = TOK_SLASH;     binop_text = "/";  break;
    case TOK_MOD_ASSIGN:   binop = TOK_MOD;       binop_text = "%";  break;
    case TOK_SHL_ASSIGN:   binop = TOK_SHL;       binop_text = "<<"; break;
    case TOK_SHR_ASSIGN:   binop = TOK_SHR;       binop_text = ">>"; break;
    case TOK_AND_ASSIGN:   binop = TOK_BIT_AND;   binop_text = "&";  break;
    case TOK_OR_ASSIGN:    binop = TOK_BIT_OR;    binop_text = "|";  break;
    case TOK_XOR_ASSIGN:   binop = TOK_BIT_XOR;   binop_text = "^";  break;
    default: break;
    }
    if (binop != TOK_UNKNOWN) {
      Token op = parser->current_token;
      if (left && left->type == AST_IDENTIFIER_EXPR) {
        ParserVar *pv = lookup_parser_var(left->token.text);
        if (pv && pv->is_const) {
          report_error(parser, "Cannot assign to const variable");
          advance_token(parser);
          parse_ternary(parser);
          return left;
        }
      }
      op.text = (char *)binop_text;
      advance_token(parser);
      ASTNode *rhs = parse_ternary(parser);
      // rewrite as i = i OP rhs
      Token bin_tok = op;
      bin_tok.type = binop;
      ASTNode *arith = ASTNode_create(AST_BINARY_EXPR, bin_tok);
      ASTNode_add_child(arith, ASTNode_clone(left));
      ASTNode_add_child(arith, rhs);
      Token assign_tok = op;
      assign_tok.type = TOK_ASSIGN;
      assign_tok.text = (char *)"=";
      ASTNode *assign = ASTNode_create(AST_BINARY_EXPR, assign_tok);
      ASTNode_add_child(assign, left);
      ASTNode_add_child(assign, arith);
      return assign;
    }
  }
  return left;
}

static ASTNode *parse_block(Parser *parser) {
  Token t = parser->current_token;
  ASTNode *block = ASTNode_create(AST_BLOCK, t);
  int saved_var_count = parser_var_count;
  consume(parser, TOK_LBRACE, "Expected '{' to start block");
  while (parser->current_token.type != TOK_RBRACE &&
         parser->current_token.type != TOK_EOF) {
    ASTNode *stmt = parse_statement(parser);
    if (stmt)
      ASTNode_add_child(block, stmt);
  }
  consume(parser, TOK_RBRACE, "Expected '}' to end block");
  restore_parser_vars(saved_var_count);
  return block;
}

static ASTNode *parse_statement(Parser *parser) {
  bool is_static = false;
  bool is_thread_local = false;
  bool is_extern = false;
  bool is_const = false;
  bool is_volatile = false;

  /* A lone semicolon is an empty statement -- it is allowed anywhere a
     statement is and does nothing. */
  if (parser->current_token.type == TOK_SEMICOLON) {
    Token t = parser->current_token;
    advance_token(parser);
    return ASTNode_create(AST_EXPR_STMT, t);
  }

  // impl parsing
  if (parser->current_token.type == TOK_KW_IMPL) {
    Token t = parser->current_token;
    advance_token(parser);
    ASTNode *impl_node = ASTNode_create(NODE_IMPL, t);

    // Parse implementer name (or Trait name if "for" follows)
    Token name1 = parser->current_token;
    consume(parser, TOK_IDENTIFIER, "Expected name after impl");
    char *impl_owner = name1.text ? strdup(name1.text) : NULL;
    ASTNode_add_child(impl_node, ASTNode_create(AST_IDENTIFIER_EXPR, name1));

    if (match(parser, TOK_KW_FOR)) {
      Token name2 = parser->current_token;
      consume(parser, TOK_IDENTIFIER, "Expected target name after for");
      ASTNode_add_child(impl_node, ASTNode_create(AST_IDENTIFIER_EXPR, name2));
    }

    consume(parser, TOK_LBRACE, "Expected '{' after impl target");
    while (parser->current_token.type != TOK_RBRACE && parser->current_token.type != TOK_EOF) {
      if (parser->current_token.type == TOK_KW_FN) {
        /* A method inside an `impl` block is mangled to `Type_method`, exactly
           like a method declared inside the type itself -- otherwise the call
           `p.get()` could not find the definition. */
        ASTNode *method = parse_impl_method(parser, impl_owner);
        if (method)
          ASTNode_add_child(impl_node, method);
        continue;
      }
      ASTNode *stmt = parse_statement(parser);
      if (stmt) {
        ASTNode_add_child(impl_node, stmt);
      }
    }
    consume(parser, TOK_RBRACE, "Expected '}' at end of impl");
    match(parser, TOK_SEMICOLON);
    if (impl_owner)
      free(impl_owner);
    return impl_node;
  }

  // asm parsing
  if (parser->current_token.type == TOK_KW_ASM) {
    Token t = parser->current_token;
    advance_token(parser);
    ASTNode *asm_node = ASTNode_create(AST_ASM_STMT, t);
    if (match(parser, TOK_LPAREN)) {
      Token asm_code = parser->current_token;
      consume(parser, TOK_STRING_LITERAL, "Expected inline asm string literal");
      ASTNode_add_child(asm_node, ASTNode_create(AST_LITERAL_EXPR, asm_code));
      consume(parser, TOK_RPAREN, "Expected ')' after asm code");
    } else if (parser->current_token.type == TOK_LBRACE) {
      // ASM block: capture the exact source between the braces.
      Token start = parser->current_token;
      advance_token(parser);
      while (parser->current_token.type != TOK_RBRACE && parser->current_token.type != TOK_EOF) {
        advance_token(parser);
      }
      Token end = parser->current_token;
      consume(parser, TOK_RBRACE, "Expected '}' at end of asm block");
      int start_off = token_source_offset(parser->lexer, &start);
      int end_off = token_source_offset(parser->lexer, &end);
      if (start_off >= 0 && end_off > start_off)
        asm_node->string_value = strndup(parser->lexer->source + start_off + 1,
                                         (size_t)(end_off - start_off - 1));
    }
    match(parser, TOK_SEMICOLON);
    return asm_node;
  }

  // async and parallel parsing
  if (parser->current_token.type == TOK_KW_ASYNC || parser->current_token.type == TOK_KW_PARALLEL) {
    Token t = parser->current_token;
    advance_token(parser);
    ASTNode *async_node = ASTNode_create(
        t.type == TOK_KW_ASYNC ? AST_ASYNC_STMT : AST_PARALLEL_STMT, t);
    if (parser->current_token.type == TOK_LBRACE) {
      ASTNode_add_child(async_node, parse_block(parser));
    } else {
      ASTNode_add_child(async_node, parse_statement(parser));
    }
    return async_node;
  }

  // await and spawn parsing
  if (parser->current_token.type == TOK_KW_AWAIT) {
    Token t = parser->current_token;
    advance_token(parser);
    ASTNode *node = ASTNode_create(AST_AWAIT_STMT, t);
    /* `await;` waits for any child process; `await pid;` waits for that one. */
    if (parser->current_token.type != TOK_SEMICOLON)
      ASTNode_add_child(node, parse_expression(parser));
    match(parser, TOK_SEMICOLON);
    return node;
  }
  if (parser->current_token.type == TOK_KW_SPAWN) {
    Token t = parser->current_token;
    advance_token(parser);
    ASTNode *node = ASTNode_create(AST_SPAWN_STMT, t);
    if (parser->current_token.type == TOK_LBRACE)
      ASTNode_add_child(node, parse_block(parser));
    else
      ASTNode_add_child(node, parse_expression(parser));
    match(parser, TOK_SEMICOLON);
    return node;
  }

  // unified use parsing
  //   use X;           - namespace/simple import
  //   use X.Y;         - import symbol from module
  //   use X.Y as Z;    - import symbol from module as Z
  //   use X as Z;      - import as Z
  if (parser->current_token.type == TOK_KW_USE) {
    Token t = parser->current_token;
    advance_token(parser);
    ASTNode *use_node = ASTNode_create(AST_USE_DECL, t);
    Token name = parser->current_token;
    if (name.type != TOK_SEMICOLON && name.type != TOK_EOF) {
      advance_token(parser);
    } else {
      report_error(parser, "Expected module/namespace name after use");
    }
    ASTNode_add_child(use_node, ASTNode_create(AST_IDENTIFIER_EXPR, name));
    while (parser->current_token.type == TOK_DOT || parser->current_token.type == TOK_SLASH) {
      advance_token(parser);
      Token sym = parser->current_token;
      if (sym.type == TOK_IDENTIFIER) {
        advance_token(parser);
        ASTNode_add_child(use_node, ASTNode_create(AST_IDENTIFIER_EXPR, sym));
      } else {
        break;
      }
    }
    if (match(parser, TOK_KW_AS)) {
      Token alias = parser->current_token;
      consume(parser, TOK_IDENTIFIER, "Expected alias identifier after 'as'");
      ASTNode_add_child(use_node, ASTNode_create(AST_IDENTIFIER_EXPR, alias));
    }
    consume(parser, TOK_SEMICOLON, "Expected ';' after use");
    return use_node;
  }


  // export parsing
  if (parser->current_token.type == TOK_KW_EXPORT) {
    Token t = parser->current_token;
    advance_token(parser);
    ASTNode *export_node = ASTNode_create(AST_EXPORT_DECL, t);
    ASTNode *decl = parse_statement(parser);
    ASTNode_add_child(export_node, decl);
    return export_node;
  }

  // try-catch-finally parsing
  if (parser->current_token.type == TOK_KW_TRY) {
    Token t = parser->current_token;
    advance_token(parser);
    ASTNode *try_node = ASTNode_create(AST_TRY_STMT, t);
    ASTNode *try_block = parse_block(parser);
    ASTNode_add_child(try_node, try_block);
    
    if (match(parser, TOK_KW_CATCH)) {
      if (match(parser, TOK_LPAREN)) {
        while (parser->current_token.type != TOK_RPAREN && parser->current_token.type != TOK_EOF) {
          advance_token(parser);
        }
        consume(parser, TOK_RPAREN, "Expected ')' after catch decl");
      } else if (parser->current_token.type == TOK_IDENTIFIER) {
        advance_token(parser); // catch e
      }
      ASTNode *catch_block = parse_block(parser);
      ASTNode_add_child(try_node, catch_block);
    }
    if (match(parser, TOK_KW_FINALLY)) {
      ASTNode *finally_block = parse_block(parser);
      ASTNode_add_child(try_node, finally_block);
    }
    return try_node;
  }

  // throw parsing
  if (parser->current_token.type == TOK_KW_THROW) {
    Token t = parser->current_token;
    advance_token(parser);
    ASTNode *throw_node = ASTNode_create(AST_THROW_STMT, t);
    if (parser->current_token.type != TOK_SEMICOLON) {
      ASTNode_add_child(throw_node, parse_expression(parser));
    }
    consume(parser, TOK_SEMICOLON, "Expected ';' after throw");
    return throw_node;
  }

  // assert parsing
  if (parser->current_token.type == TOK_KW_ASSERT) {
    Token t = parser->current_token;
    advance_token(parser);
    ASTNode *assert_node = ASTNode_create(AST_ASSERT_STMT, t);
    ASTNode_add_child(assert_node, parse_expression(parser));
    consume(parser, TOK_SEMICOLON, "Expected ';' after assert");
    return assert_node;
  }

  // Unsafe block parsing
  if (parser->current_token.type == TOK_KW_UNSAFE) {
    Token t = parser->current_token;
    advance_token(parser);
    if (parser->current_token.type == TOK_LBRACE) {
      ASTNode *unsafe_block = parse_block(parser);
      unsafe_block->type = AST_UNSAFE_BLOCK;
      unsafe_block->token = t;
      return unsafe_block;
    }
  }

  // match, defer, goto, labels, and yield parsing
  if (parser->current_token.type == TOK_KW_MATCH) {
    Token t = parser->current_token;
    advance_token(parser);
    consume(parser, TOK_LPAREN, "Expected '(' after match");
    ASTNode *match_expr = parse_expression(parser);
    consume(parser, TOK_RPAREN, "Expected ')' after match expr");
    consume(parser, TOK_LBRACE, "Expected '{' after match");

    ASTNode *first_if = NULL;
    ASTNode *last_if = NULL;
    ASTNode *default_block = NULL;
    bool seen_default_arm = false;

    while (parser->current_token.type != TOK_RBRACE &&
           parser->current_token.type != TOK_EOF) {
      Token case_tok = parser->current_token;
      if (case_tok.type == TOK_IDENTIFIER && strcmp(case_tok.text, "_") == 0) {
        bool duplicate = seen_default_arm;
        if (duplicate) {
          report_error(parser, "Duplicate '_' arm in match expression");
        }
        seen_default_arm = true;
        advance_token(parser); // Consume '_'
        consume(parser, TOK_FAT_ARROW, "Expected '=>' after default pattern");
        /* A `break` inside a match arm leaves the match, not the enclosing
           loop -- same rule as `switch`. */
        parser->switch_depth++;
        ASTNode *arm_block = parse_statement(parser);
        parser->switch_depth--;
        if (parser->current_token.type == TOK_COMMA) {
          advance_token(parser);
        }
        /* The first `_` wins; a later duplicate is reported and dropped. */
        if (!duplicate) default_block = arm_block;
        else ASTNode_free(arm_block);
      } else {
        ASTNode *case_val = parse_expression(parser);
        consume(parser, TOK_FAT_ARROW, "Expected '=>' after match pattern");
        parser->switch_depth++;
        ASTNode *case_block = parse_statement(parser);
        parser->switch_depth--;
        if (parser->current_token.type == TOK_COMMA) {
          advance_token(parser);
        }

        Token eq_tok;
        eq_tok.type = TOK_EQ;
        eq_tok.text = strdup("==");
        eq_tok.line = case_val->token.line;
        eq_tok.column = case_val->token.column;

        ASTNode *cond = ASTNode_create(AST_BINARY_EXPR, eq_tok);
        ASTNode_add_child(cond, ASTNode_clone(match_expr));
        ASTNode_add_child(cond, case_val);

        Token if_tok;
        if_tok.type = TOK_KW_IF;
        if_tok.text = strdup("if");
        if_tok.line = case_val->token.line;
        if_tok.column = case_val->token.column;

        ASTNode *new_if = ASTNode_create(AST_IF_STMT, if_tok);
        ASTNode_add_child(new_if, cond);
        ASTNode_add_child(new_if, case_block);

        if (!first_if) {
          first_if = new_if;
        } else {
          ASTNode_add_child(last_if, new_if);
        }
        last_if = new_if;
      }
    }
    consume(parser, TOK_RBRACE, "Expected '}' to close match");
    ASTNode_free(match_expr);
    if (default_block) {
      if (last_if) {
        ASTNode_add_child(last_if, default_block);
      } else {
        first_if = default_block;
      }
    }
    if (!first_if) {
      first_if = ASTNode_create(AST_BLOCK, t);
    }
    return first_if;
  }

  if (parser->current_token.type == TOK_KW_DEFER) {
    Token t = parser->current_token;
    advance_token(parser);
    ASTNode *defer_node = ASTNode_create(AST_DEFER_STMT, t);
    ASTNode *stmt = parse_statement(parser);
    ASTNode_add_child(defer_node, stmt);
    return defer_node;
  }

  if (parser->current_token.type == TOK_KW_GOTO) {
    Token t = parser->current_token;
    advance_token(parser);
    Token label_tok = parser->current_token;
    char *label_name = label_tok.text ? strdup(label_tok.text) : NULL;
    consume(parser, TOK_IDENTIFIER, "Expected label name after goto");
    match(parser, TOK_SEMICOLON); // consume optional semicolon
    ASTNode *goto_node = ASTNode_create(AST_GOTO_STMT, t);
    if (goto_node->token.text) free((void*)goto_node->token.text);
    goto_node->token.text = label_name;
    return goto_node;
  }

  if (parser->current_token.type == TOK_IDENTIFIER && parser->next_token.type == TOK_COLON) {
    Token t = parser->current_token;
    char *label_name = t.text ? strdup(t.text) : NULL;
    advance_token(parser); // Consume identifier
    advance_token(parser); // Consume colon
    ASTNode *label_node = ASTNode_create(AST_LABEL_DECL, t);
    if (label_node->token.text) free((void*)label_node->token.text);
    label_node->token.text = label_name;
    return label_node;
  }

  // Parse modifiers
  while (true) {
    if (parser->current_token.type == TOK_KW_STATIC) {
      is_static = true;
      advance_token(parser);
    } else if (parser->current_token.type == TOK_KW_EXTERN) {
      is_extern = true;
      advance_token(parser);
    } else if (parser->current_token.type == TOK_KW_CONST) {
      is_const = true;
      advance_token(parser);
    } else if (parser->current_token.type == TOK_KW_VOLATILE) {
      is_volatile = true;
      advance_token(parser);
    } else if (parser->current_token.type == TOK_KW_INLINE ||
               parser->current_token.type == TOK_KW_REGISTER) {
      advance_token(parser);
    } else {
      break;
    }
  }

  /* let name = expr;  let Type name = expr;  let name: Type = expr;
     The declaration must not leave "let" behind as a type name, otherwise the
     identifier lookup below reads the variable's address instead of its value. */
  if (parser->current_token.type == TOK_KW_LET) {
    last_type_name = NULL;
    TokenType var_type = TOK_KW_AUTO;
    bool type_volatile = false;
    advance_token(parser);

    if (token_starts_type(parser)) {
      var_type = parse_type(parser);
      type_volatile = last_type_is_volatile;
    }
    if (var_type == TOK_UNKNOWN)
      var_type = TOK_KW_AUTO;

    if (parser->current_token.type != TOK_IDENTIFIER &&
        parser->current_token.type != TOK_KW_PTR) {
      report_error(parser, "Expected variable name after 'let'");
      return NULL;
    }

    Token id = parser->current_token;
    char id_name_buf[64];
    id_name_buf[0] = '\0';
    if (id.text)
      snprintf(id_name_buf, sizeof(id_name_buf), "%s", id.text);
    /* id.text is freed by the advance below -- repoint it at our own copy so
       ASTNode_create() can strdup a still-valid string. */
    id.text = id_name_buf;
    advance_token(parser);

    var_type = apply_name_array_suffix(parser, var_type);

    if (parser->current_token.type == TOK_COLON) {
      advance_token(parser);
      last_type_name = NULL;
      TokenType colon_type = parse_type(parser);
      if (colon_type != TOK_UNKNOWN)
        var_type = colon_type;
      if (var_type == TOK_UNKNOWN)
        var_type = TOK_KW_AUTO;
      type_volatile = type_volatile || last_type_is_volatile;
    }

    char decl_tn_buf[64];
    decl_tn_buf[0] = '\0';
    if (last_type_name)
      snprintf(decl_tn_buf, sizeof(decl_tn_buf), "%s", last_type_name);

    ArrayShape array_shape;
    bool has_array_shape = (var_type == TOK_KW_FIXED);
    if (has_array_shape)
      array_shape_capture(&array_shape);

    ASTNode *decl = ASTNode_create(AST_VAR_DECL, id);
    decl->int_value = var_type;
    if (is_static || is_thread_local || is_const)
      decl->bool_value = true;
    if (is_volatile || type_volatile)
      decl->is_volatile = true;
    if (decl_tn_buf[0]) {
      decl->string_value = strdup(decl_tn_buf);
    }

    if (var_type == TOK_KW_FIXED) {
      decl->char_value = (char)array_shape.elem_type;
      ASTNode *size_node = ASTNode_create(NODE_NUMBER, id);
      size_node->int_value = array_shape.total;
      ASTNode_add_child(decl, size_node);
      if (match(parser, TOK_ASSIGN)) {
        ASTNode *init = parse_expression(parser);
        init = flatten_array_initializer(init, array_shape.dim_count);
        ASTNode_add_child(decl, init);
      }
      array_shape_restore(&array_shape);
      register_parser_var_full(id_name_buf, var_type, NULL, is_const);
      consume(parser, TOK_SEMICOLON, "Expected ';' after 'let' declaration");
      return decl;
    }

    ASTNode *init = NULL;
    if (match(parser, TOK_ASSIGN)) {
      init = parse_expression(parser);
      if (var_type == TOK_KW_AUTO) {
        if (init && init->type == AST_STRUCT_LITERAL && !init->string_value) {
          /* An aggregate literal without a type of its own: the type is
             taken from the struct declaration that fits the number of
             elements. */
          StructType *st = find_struct_for_literal(init->int_value);
          if (!st) {
            report_error(parser,
                         "Cannot infer the type of the aggregate literal");
            return NULL;
          }
          var_type = TOK_KW_INT;
          decl->string_value = strdup(st->name);
        } else if (init && init->type == AST_STRUCT_LITERAL &&
                   init->string_value) {
          /* `Point { 1, 2 }` -- the type is part of the literal. */
          var_type = TOK_KW_INT;
          decl->string_value = strdup(init->string_value);
        } else {
          var_type = deduce_decl_type(init);
        }
        decl->int_value = var_type;
        if (var_type == TOK_KW_STRING && !decl->string_value) {
          decl->char_value = (char)TOK_KW_CHAR;
        }
      }
    }
    if (init)
      ASTNode_add_child(decl, init);

    register_parser_var_full(id_name_buf, var_type,
                             decl_tn_buf[0] ? decl_tn_buf
                                            : (decl->string_value ? decl->string_value : NULL),
                             is_const);
    consume(parser, TOK_SEMICOLON, "Expected ';' after 'let' declaration");
    return decl;
  }

  if (is_extern && parser->current_token.type == TOK_KW_FN) {
    return parse_function_opt(parser, true);
  }
  if (parser->current_token.type == TOK_KW_FN) {
    return parse_function(parser);
  }

  TokenType peek_type = parser->current_token.type;
  bool is_decl = false;
  if (peek_type == TOK_KW_INT || peek_type == TOK_KW_FLOAT ||
      peek_type == TOK_KW_BOOL || peek_type == TOK_KW_CHAR ||
      peek_type == TOK_KW_STRING || peek_type == TOK_KW_PTR ||
      peek_type == TOK_KW_RAW || peek_type == TOK_KW_REF ||
      peek_type == TOK_KW_OWN ||
      peek_type == TOK_KW_AUTO || peek_type == TOK_KW_TYPEOF ||
      peek_type == TOK_KW_BYTE || peek_type == TOK_KW_WORD ||
      peek_type == TOK_KW_DWORD || peek_type == TOK_KW_QWORD ||
      peek_type == TOK_KW_HALF || peek_type == TOK_KW_FIXED ||
      peek_type == TOK_KW_ARRAY || peek_type == TOK_KW_TUPLE ||
      peek_type == TOK_KW_DYN || peek_type == TOK_KW_SLICE ||
      peek_type == TOK_KW_ANY ||
      peek_type == TOK_KW_RANGE) {
    is_decl = true;
  } else if (peek_type == TOK_IDENTIFIER) {
    if (lookup_struct(parser->current_token.text) != NULL) {
      is_decl = true;
    } else if (parser->next_token.type == TOK_IDENTIFIER) {
      // Heuristic: "TypeName var = ..." treat as a declaration
      // even when TypeName is not yet a registered struct type
      is_decl = true;
    }
  }

  /* const IDENTIFIER = expr; — type-inferred declaration */
  if (is_const && peek_type == TOK_IDENTIFIER &&
      parser->next_token.type == TOK_ASSIGN) {
    is_decl = true;
  }

  if (is_decl) {
    last_type_name = NULL;
    TokenType var_type = parse_type(parser);
    bool type_volatile = last_type_is_volatile;
    // Handle unregistered struct/type names: "TypeName var = ..."
    if (var_type == TOK_UNKNOWN && parser->current_token.type == TOK_IDENTIFIER) {
      if (is_const) {
        // const name = expr; — name is the variable, not a type
        var_type = TOK_KW_INT;
      } else {
        last_type_name = remember_type_name(parser->current_token.text);
        advance_token(parser);
        var_type = TOK_KW_INT;
        while (parser->current_token.type == TOK_STAR) {
          advance_token(parser);
          var_type = TOK_KW_PTR;
        }
      }
    }
    /* Snapshot the declared type name NOW: parsing the initializer may contain
       a cast/type (e.g. `char* b = cast<char*>(...)`) which overwrites the
       last_type_name global. Losing it makes `*b` load 8 bytes instead of 1. */
    char decl_tn_buf[64];
    decl_tn_buf[0] = '\0';
    if (last_type_name)
      snprintf(decl_tn_buf, sizeof(decl_tn_buf), "%s", last_type_name);
    if (parser->current_token.type == TOK_IDENTIFIER ||
        parser->current_token.type == TOK_KW_PTR) {
      Token id = parser->current_token;
      /* id.text points into the lexer's token buffer, which is invalidated by
         parsing the initializer below. Keep our own copy for the var table. */
      char id_name_buf[64];
      id_name_buf[0] = '\0';
      if (id.text)
        snprintf(id_name_buf, sizeof(id_name_buf), "%s", id.text);
      ASTNode *decl = ASTNode_create(AST_VAR_DECL, id);
      decl->int_value = var_type;
      if (decl_tn_buf[0]) {
        decl->string_value = strdup(decl_tn_buf);
      }
      if (is_static || is_thread_local || is_const) {
        decl->bool_value = true; // Mark as static/TLS global variable storage!
      }
      if (is_volatile || type_volatile)
        decl->is_volatile = true;
      advance_token(parser);

      /* C-style dimensions after the name: `int a[2][3];` */
      var_type = apply_name_array_suffix(parser, var_type);
      decl->int_value = var_type;

      ArrayShape array_shape;
      bool has_array_shape = (var_type == TOK_KW_FIXED);
      if (has_array_shape)
        array_shape_capture(&array_shape);

      if (var_type == TOK_KW_AUTO) {
        consume(parser, TOK_ASSIGN,
                "Expected '=' after auto variable declaration");
        ASTNode *init_expr = parse_expression(parser);
        TokenType deduced = deduce_decl_type(init_expr);
        decl->int_value = deduced;
        var_type = deduced;
        ASTNode_add_child(decl, init_expr);
      } else if (var_type == TOK_KW_FIXED) {
        decl->char_value = (char)array_shape.elem_type;
        ASTNode *size_node = ASTNode_create(NODE_NUMBER, id);
        size_node->int_value = array_shape.total;
        ASTNode_add_child(decl, size_node);
        if (match(parser, TOK_ASSIGN)) {
          ASTNode *init = parse_expression(parser);
          init = flatten_array_initializer(init, array_shape.dim_count);
          ASTNode_add_child(decl, init);
        }
      } else if (var_type == TOK_KW_DYN || var_type == TOK_KW_SLICE) {
        decl->char_value = (char)last_array_elem_type;
        if (match(parser, TOK_ASSIGN)) {
          ASTNode_add_child(decl, parse_expression(parser));
        }
      } else {
        if (match(parser, TOK_ASSIGN)) {
          ASTNode_add_child(decl, parse_expression(parser));
        }
      }
      if (has_array_shape)
        array_shape_restore(&array_shape);
      register_parser_var_full(id_name_buf, var_type,
                               decl_tn_buf[0] ? decl_tn_buf : NULL, is_const);

      // Support comma-separated multiple variables: type a, b, c = val;
      if (match(parser, TOK_COMMA)) {
        ASTNode *block = ASTNode_create(AST_BLOCK, id);
        ASTNode_add_child(block, decl);
        while (true) {
          Token next_id = parser->current_token;
          char next_name_buf[64];
          next_name_buf[0] = '\0';
          if (next_id.text)
            snprintf(next_name_buf, sizeof(next_name_buf), "%s",
                     next_id.text);
          if (next_id.type != TOK_IDENTIFIER && next_id.type != TOK_KW_PTR) {
            report_error(parser, "Expected variable name");
            break;
          }
          ASTNode *next_decl = ASTNode_create(AST_VAR_DECL, next_id);
          next_decl->int_value = var_type;
          if (decl_tn_buf[0])
            next_decl->string_value = strdup(decl_tn_buf);
          if (is_static || is_thread_local || is_const)
            next_decl->bool_value = true;
          if (is_volatile || type_volatile)
            next_decl->is_volatile = true;
          advance_token(parser);
          TokenType next_type = apply_name_array_suffix(parser, var_type);
          next_decl->int_value = next_type;
          ArrayShape next_shape;
          bool next_has_shape = (next_type == TOK_KW_FIXED);
          if (next_has_shape)
            array_shape_capture(&next_shape);
          if (next_type == TOK_KW_FIXED) {
            next_decl->char_value = (char)next_shape.elem_type;
            ASTNode *size_node = ASTNode_create(NODE_NUMBER, next_id);
            size_node->int_value = next_shape.total;
            ASTNode_add_child(next_decl, size_node);
            if (match(parser, TOK_ASSIGN)) {
              ASTNode *init = parse_expression(parser);
              init = flatten_array_initializer(init, next_shape.dim_count);
              ASTNode_add_child(next_decl, init);
            }
          } else if (match(parser, TOK_ASSIGN)) {
            ASTNode_add_child(next_decl, parse_expression(parser));
          }
          if (next_has_shape)
            array_shape_restore(&next_shape);
          register_parser_var_full(next_name_buf, next_type,
                                   decl_tn_buf[0] ? decl_tn_buf : NULL, is_const);
          ASTNode_add_child(block, next_decl);
          if (!match(parser, TOK_COMMA))
            break;
        }
        consume(parser, TOK_SEMICOLON,
                "Expected ';' after variable declaration");
        return block;
      }

      consume(parser, TOK_SEMICOLON,
              "Expected ';' after variable declaration");
      return decl;
    }
  }

  // const Type X = value;
  if (parser->current_token.type == TOK_KW_CONST) {
    advance_token(parser);
    TokenType var_type = parse_type(parser);
    if (parser->current_token.type == TOK_IDENTIFIER ||
        parser->current_token.type == TOK_KW_PTR) {
      Token id = parser->current_token;
      ASTNode *decl = ASTNode_create(AST_VAR_DECL, id);
      decl->int_value = var_type;
      decl->bool_value = true;
      if (is_volatile || last_type_is_volatile)
        decl->is_volatile = true;
      advance_token(parser);
      if (match(parser, TOK_ASSIGN)) {
        ASTNode_add_child(decl, parse_expression(parser));
      }
      consume(parser, TOK_SEMICOLON, "Expected ';' after const declaration");
      return decl;
    }
  }

  // class Name [extends Parent] [impl Interface] { ... }
  if (parser->current_token.type == TOK_KW_CLASS) {
    advance_token(parser);

    Token class_tok = parser->current_token;
    char *class_name = class_tok.text ? strdup(class_tok.text) : NULL;
    consume(parser, TOK_IDENTIFIER, "Expected class name");

    char *parent_name = NULL;
    if (match(parser, TOK_KW_EXTENDS)) {
      Token p_tok = parser->current_token;
      parent_name = p_tok.text ? strdup(p_tok.text) : NULL;
      consume(parser, TOK_IDENTIFIER,
              "Expected parent class name after extends");

      if (class_inherits_count < 64) {
        class_inherits[class_inherits_count].class_name = strdup(class_name);
        class_inherits[class_inherits_count].parent_name = strdup(parent_name);
        class_inherits_count++;
      }
    }

    if (match(parser, TOK_KW_IMPL)) {
      consume(parser, TOK_IDENTIFIER,
              "Expected interface/trait name after impl");
    }

    consume(parser, TOK_LBRACE, "Expected '{' after class name");

    // Register in struct_types!
    StructType *st = &struct_types[struct_type_count];
    st->name = class_name;
    st->field_count = 0;
    st->size = 0;

    // Inherit parent fields!
    if (parent_name) {
      StructType *parent_st = lookup_struct(parent_name);
      if (parent_st) {
        for (int i = 0; i < parent_st->field_count; i++) {
          StructField *f = &st->fields[st->field_count++];
          f->name = strdup(parent_st->fields[i].name);
          f->offset = parent_st->fields[i].offset;
          f->field_type = parent_st->fields[i].field_type;
          f->array_size = parent_st->fields[i].array_size;
          f->array_dim_count = parent_st->fields[i].array_dim_count;
          f->array_elem_type = parent_st->fields[i].array_elem_type;
          for (int d = 0; d < MAX_ARRAY_DIMS; d++)
            f->array_dims[d] = parent_st->fields[i].array_dims[d];
        }
        st->size = parent_st->size;
      }
    }

    ASTNode *class_node = ASTNode_create(NODE_CLASS_DECL, class_tok);
    if (class_node->token.text)
      free((void *)class_node->token.text);
    class_node->token.text = class_name;

    // Save the parent class name on the class node!
    if (parent_name) {
      class_node->string_value = parent_name;
    }

    // Parse fields and methods inside class
    while (parser->current_token.type != TOK_RBRACE &&
           parser->current_token.type != TOK_EOF) {
      if (parser->current_token.type == TOK_KW_FN) {
        // Parse method!
        advance_token(parser); // past "fn"
        Token m_id = parser->current_token;
        char *m_id_copy = m_id.text ? strdup(m_id.text) : NULL;
        char *full_method_name = (char *)malloc(
            strlen(class_name) + (m_id_copy ? strlen(m_id_copy) : 0) + 2);
        sprintf(full_method_name, "%s_%s", class_name,
                m_id_copy ? m_id_copy : "method");
        if (m_id_copy)
          free(m_id_copy);

        // Parse the method!
        ASTNode *method = ASTNode_create(AST_FUNC_DECL, m_id);
        if (method->token.text)
          free((void *)method->token.text);
        method->token.text = full_method_name;
        advance_token(parser);

        // Add implicit "this" parameter as child 0!
        Token this_tok;
        this_tok.type = TOK_KW_THIS;
        this_tok.text = strdup("this");
        this_tok.line = m_id.line;
        this_tok.column = m_id.column;
        ASTNode *implicit_this = ASTNode_create(AST_VAR_DECL, this_tok);
        implicit_this->int_value = TOK_KW_PTR;
        implicit_this->string_value = strdup(class_name);
        ASTNode_add_child(method, implicit_this);

        // Parse explicit parameters
        consume(parser, TOK_LPAREN, "Expected '(' after method name");
        if (parser->current_token.type != TOK_RPAREN) {
          do {
            last_type_name = NULL;
            TokenType p_type = parse_type(parser);
            bool p_volatile = last_type_is_volatile;
            if (p_type == TOK_UNKNOWN && parser->current_token.type == TOK_IDENTIFIER) {
              last_type_name = remember_type_name(parser->current_token.text);
              advance_token(parser);
              p_type = TOK_KW_INT;
              while (parser->current_token.type == TOK_STAR) {
                advance_token(parser);
                p_type = TOK_KW_PTR;
              }
            } else if (p_type == TOK_UNKNOWN) {
              report_error(parser, "Invalid type in parameter declaration");
              advance_token(parser);
              continue;
            }
            Token p_name = parser->current_token;
            char *p_name_copy =
                (p_name.type == TOK_IDENTIFIER || p_name.type == TOK_KW_PTR)
                    ? (p_name.text ? strdup(p_name.text) : NULL)
                    : NULL;
            if (p_name.type == TOK_IDENTIFIER || p_name.type == TOK_KW_PTR) {
              advance_token(parser);
            } else {
              report_error(parser, "Expected parameter identifier");
            }

            p_name.text = p_name_copy;
            ASTNode *param = ASTNode_create(AST_VAR_DECL, p_name);
            if (param->token.text)
              free((void *)param->token.text);
            param->token.text = p_name_copy;
            param->int_value = p_type;
      param->is_volatile = p_volatile;
            if (last_type_name) {
              param->string_value = strdup(last_type_name);
            }
            ASTNode_add_child(method, param);
          } while (match(parser, TOK_COMMA));
        }
        consume(parser, TOK_RPAREN, "Expected ')' after method parameters");

        if (match(parser, TOK_ARROW)) {
          TokenType ret_t = parse_type(parser);
          method->int_value |= ((int)ret_t << 8);
        }
        register_parser_func(method->token.text,
                             (TokenType)(method->int_value >> 8), class_name,
                             last_type_name);

        const char *saved_ctx = current_type_context;
        current_type_context = class_name;
        ASTNode_add_child(method, parse_block(parser));
        current_type_context = saved_ctx;
        ASTNode_add_child(class_node, method);
      } else {
        // Parse field!
        TokenType f_type = parse_type(parser);
        bool f_volatile = last_type_is_volatile;
        if (f_type == TOK_UNKNOWN) {
          report_error(parser, "Invalid type in class field");
          advance_token(parser);
          continue;
        }
        Token f_name = parser->current_token;
        char *fname_copy =
            (f_name.type == TOK_IDENTIFIER || f_name.type == TOK_KW_PTR)
                ? (f_name.text ? strdup(f_name.text) : NULL)
                : NULL;
        if (f_name.type == TOK_IDENTIFIER || f_name.type == TOK_KW_PTR) {
          advance_token(parser);
        } else {
          report_error(parser, "Expected field identifier");
        }
        /* `int data[4];` / `int grid[2][3];` declares an array field. The
           shape may come from the type (`int[2][3] data`) or from a suffix
           after the field name, so both are combined here. */
        ArrayShape type_shape;
        array_shape_capture(&type_shape);
        int field_dims[MAX_ARRAY_DIMS];
        int field_dim_count = 0;
        TokenType field_elem_type = f_type;
        if (f_type == TOK_KW_FIXED && type_shape.dim_count > 0) {
          field_elem_type = type_shape.elem_type;
          for (int i = 0; i < type_shape.dim_count &&
                          field_dim_count < MAX_ARRAY_DIMS; i++)
            field_dims[field_dim_count++] = type_shape.dims[i];
        }
        int suffix_dims[MAX_ARRAY_DIMS];
        int suffix_count = parse_bracket_dims(parser, suffix_dims, MAX_ARRAY_DIMS);
        for (int i = 0; i < suffix_count && field_dim_count < MAX_ARRAY_DIMS; i++)
          field_dims[field_dim_count++] = suffix_dims[i];
        int field_array_size = 0;
        if (field_dim_count > 0) {
          field_array_size = 1;
          for (int i = 0; i < field_dim_count; i++)
            field_array_size *= field_dims[i] > 0 ? field_dims[i] : 1;
        }
        consume(parser, TOK_SEMICOLON, "Expected ';' after field declaration");

        if (st->field_count >= (int)(sizeof(st->fields) / sizeof(st->fields[0]))) {
          report_error(parser, "Too many fields in class declaration");
          continue;
        }
        StructField *f = &st->fields[st->field_count++];
        f->name = fname_copy;
        f->is_volatile = f_volatile;
        f->offset = st->size;
        f->field_type = (field_dim_count > 0) ? field_elem_type : f_type;
        f->array_size = field_array_size;
        f->array_dim_count = field_dim_count;
        f->array_elem_type = field_elem_type;
        for (int i = 0; i < MAX_ARRAY_DIMS; i++)
          f->array_dims[i] = (i < field_dim_count) ? field_dims[i] : 0;
        int elem_slot = parser_elem_slot_size(field_elem_type);
        st->size += (field_array_size > 0) ? field_array_size * elem_slot
                                           : elem_slot;
      }
    }
    consume(parser, TOK_RBRACE, "Expected '}' to close class definition");
    match(parser, TOK_SEMICOLON); // Optional semicolon

    struct_type_count++;
    return class_node;
  }

  // enum Name { ... }
  if (parser->current_token.type == TOK_KW_ENUM) {
    advance_token(parser);

    Token enum_tok = parser->current_token;
    char *enum_name = enum_tok.text ? strdup(enum_tok.text) : NULL;
    consume(parser, TOK_IDENTIFIER, "Expected enum name");
    consume(parser, TOK_LBRACE, "Expected '{' after enum name");

    ASTNode *enum_node = ASTNode_create(NODE_ENUM_DECL, enum_tok);
    if (enum_node->token.text)
      free((void *)enum_node->token.text);
    enum_node->token.text = enum_name;

    // Register in struct_types so it is recognized as a type of size 8!
    StructType *st = &struct_types[struct_type_count++];
    st->name = enum_name;
    st->field_count = 0;
    st->size = 8;

    int current_val = 0;
    while (parser->current_token.type != TOK_RBRACE &&
           parser->current_token.type != TOK_EOF) {
      Token m_tok = parser->current_token;
      char *m_name = m_tok.text ? strdup(m_tok.text) : NULL;
      consume(parser, TOK_IDENTIFIER, "Expected enum member identifier");

      if (match(parser, TOK_ASSIGN)) {
        Token val_tok = parser->current_token;
        current_val = parse_int_token_text(val_tok.text);
        consume(parser, TOK_INT_LITERAL, "Expected integer literal after '='");
      }

      // Register in the global enum members list
      if (enum_member_count < 256) {
        enum_members[enum_member_count].enum_name = strdup(enum_name);
        enum_members[enum_member_count].member_name = strdup(m_name);
        enum_members[enum_member_count].value = current_val;
        enum_member_count++;
      }

      ASTNode *member = ASTNode_create(AST_VAR_DECL, m_tok);
      if (member->token.text)
        free((void *)member->token.text);
      member->token.text = m_name;
      member->int_value = current_val; // store enum value in int_value
      ASTNode_add_child(enum_node, member);

      current_val++;
      match(parser, TOK_COMMA); // Optional comma
    }
    consume(parser, TOK_RBRACE, "Expected '}' to close enum");
    match(parser, TOK_SEMICOLON); // Optional semicolon

    return enum_node;
  }

  // union Name { ... }
  if (parser->current_token.type == TOK_KW_UNION) {
    advance_token(parser);

    Token union_tok = parser->current_token;
    char *union_name = union_tok.text ? strdup(union_tok.text) : NULL;
    consume(parser, TOK_IDENTIFIER, "Expected union name");
    consume(parser, TOK_LBRACE, "Expected '{' after union name");

    StructType *st = &struct_types[struct_type_count++];
    st->name = union_name;
    st->field_count = 0;
    st->size = 0;

    ASTNode *union_node = ASTNode_create(NODE_UNION_DECL, union_tok);
    if (union_node->token.text)
      free((void *)union_node->token.text);
    union_node->token.text = union_name;

    while (parser->current_token.type != TOK_RBRACE &&
           parser->current_token.type != TOK_EOF) {
      TokenType f_type = parse_type(parser);
      bool f_volatile = last_type_is_volatile;
      if (f_type == TOK_UNKNOWN) {
        report_error(parser, "Invalid type in union field");
        advance_token(parser);
        continue;
      }
      Token f_name = parser->current_token;
      char *fname_copy =
          (f_name.type == TOK_IDENTIFIER || f_name.type == TOK_KW_PTR)
              ? (f_name.text ? strdup(f_name.text) : NULL)
              : NULL;
      if (f_name.type == TOK_IDENTIFIER || f_name.type == TOK_KW_PTR) {
        advance_token(parser);
      } else {
        report_error(parser, "Expected field identifier");
      }
      consume(parser, TOK_SEMICOLON, "Expected ';' after field declaration");

      StructField *f = &st->fields[st->field_count++];
      f->name = fname_copy;
      f->is_volatile = f_volatile;
      f->offset = 0; // union fields overlap at offset 0!
      f->field_type = f_type;
      f->array_size = 0;
      f->array_dim_count = 0;
      f->array_elem_type = f_type;

      int field_slot = parser_elem_slot_size(f_type);
      if (st->size < field_slot)
        st->size = field_slot;
    }
    consume(parser, TOK_RBRACE, "Expected '}' to close union");
    match(parser, TOK_SEMICOLON); // Optional semicolon

    return union_node;
  }

  // struct Name { Type field; ... }
  if (parser->current_token.type == TOK_KW_STRUCT) {
    Token t = parser->current_token;
    advance_token(parser);
    Token struct_name = parser->current_token;
    char *name_copy = struct_name.text ? strdup(struct_name.text) : NULL;
    consume(parser, TOK_IDENTIFIER, "Expected struct name");
    consume(parser, TOK_LBRACE, "Expected '{' after struct name");

    StructType *st = &struct_types[struct_type_count];
    st->name = name_copy;
    st->field_count = 0;
    st->size = 0;

    ASTNode *decl = ASTNode_create(AST_STRUCT_DECL, t);

    while (parser->current_token.type != TOK_RBRACE &&
           parser->current_token.type != TOK_EOF) {
      if (parser->current_token.type == TOK_KW_FN) {
        // Parse method: mangled as StructName_method, with implicit "this".
        advance_token(parser); // past "fn"
        Token m_id = parser->current_token;
        char *m_id_copy = m_id.text ? strdup(m_id.text) : NULL;
        char full_method_name[256];
        snprintf(full_method_name, sizeof(full_method_name), "%s_%s",
                 name_copy ? name_copy : "struct",
                 m_id_copy ? m_id_copy : "method");
        if (m_id_copy)
          free(m_id_copy);

        ASTNode *method = ASTNode_create(AST_FUNC_DECL, m_id);
        if (method->token.text)
          free((void *)method->token.text);
        method->token.text = strdup(full_method_name);
        advance_token(parser);

        Token this_tok;
        this_tok.type = TOK_KW_THIS;
        this_tok.text = strdup("this");
        this_tok.line = m_id.line;
        this_tok.column = m_id.column;
        ASTNode *implicit_this = ASTNode_create(AST_VAR_DECL, this_tok);
        implicit_this->int_value = TOK_KW_PTR;
        implicit_this->string_value = name_copy ? strdup(name_copy) : NULL;
        ASTNode_add_child(method, implicit_this);

        consume(parser, TOK_LPAREN, "Expected '(' after method name");
        if (parser->current_token.type != TOK_RPAREN) {
          do {
            last_type_name = NULL;
            TokenType p_type = parse_type(parser);
            bool p_volatile = last_type_is_volatile;
            if (p_type == TOK_UNKNOWN && parser->current_token.type == TOK_IDENTIFIER) {
              last_type_name = remember_type_name(parser->current_token.text);
              advance_token(parser);
              p_type = TOK_KW_INT;
              while (parser->current_token.type == TOK_STAR) {
                advance_token(parser);
                p_type = TOK_KW_PTR;
              }
            } else if (p_type == TOK_UNKNOWN) {
              report_error(parser, "Invalid type in parameter declaration");
              advance_token(parser);
              continue;
            }
            Token p_name = parser->current_token;
            char *p_name_copy =
                (p_name.type == TOK_IDENTIFIER || p_name.type == TOK_KW_PTR)
                    ? (p_name.text ? strdup(p_name.text) : NULL)
                    : NULL;
            if (p_name.type == TOK_IDENTIFIER || p_name.type == TOK_KW_PTR) {
              advance_token(parser);
            } else {
              report_error(parser, "Expected parameter identifier");
            }

            p_name.text = p_name_copy;
            ASTNode *param = ASTNode_create(AST_VAR_DECL, p_name);
            if (param->token.text)
              free((void *)param->token.text);
            param->token.text = p_name_copy;
            param->int_value = p_type;
      param->is_volatile = p_volatile;
            if (last_type_name) {
              param->string_value = strdup(last_type_name);
            }
            ASTNode_add_child(method, param);
          } while (match(parser, TOK_COMMA));
        }
        consume(parser, TOK_RPAREN, "Expected ')' after method parameters");

        if (match(parser, TOK_ARROW)) {
          TokenType ret_t = parse_type(parser);
          method->int_value |= ((int)ret_t << 8);
        }
        register_parser_func(method->token.text,
                             (TokenType)(method->int_value >> 8), name_copy,
                             last_type_name);

        const char *saved_ctx = current_type_context;
        current_type_context = name_copy;
        ASTNode_add_child(method, parse_block(parser));
        current_type_context = saved_ctx;
        ASTNode_add_child(decl, method);
      } else {
        TokenType f_type = parse_type(parser);
        bool f_volatile = last_type_is_volatile;
        if (f_type == TOK_UNKNOWN) {
          report_error(parser, "Invalid type in struct field");
          advance_token(parser);
          continue;
        }
        Token f_name = parser->current_token;
        char *fname_copy =
            (f_name.type == TOK_IDENTIFIER || f_name.type == TOK_KW_PTR)
                ? (f_name.text ? strdup(f_name.text) : NULL)
                : NULL;
        if (f_name.type == TOK_IDENTIFIER || f_name.type == TOK_KW_PTR) {
          advance_token(parser);
        } else {
          report_error(parser, "Expected field identifier");
        }
        /* `int data[4];` / `int grid[2][3];` declares an array field. The
           shape may come from the type (`int[2][3] data`) or from a suffix
           after the field name, so both are combined here. */
        ArrayShape type_shape;
        array_shape_capture(&type_shape);
        int field_dims[MAX_ARRAY_DIMS];
        int field_dim_count = 0;
        TokenType field_elem_type = f_type;
        if (f_type == TOK_KW_FIXED && type_shape.dim_count > 0) {
          field_elem_type = type_shape.elem_type;
          for (int i = 0; i < type_shape.dim_count &&
                          field_dim_count < MAX_ARRAY_DIMS; i++)
            field_dims[field_dim_count++] = type_shape.dims[i];
        }
        int suffix_dims[MAX_ARRAY_DIMS];
        int suffix_count = parse_bracket_dims(parser, suffix_dims, MAX_ARRAY_DIMS);
        for (int i = 0; i < suffix_count && field_dim_count < MAX_ARRAY_DIMS; i++)
          field_dims[field_dim_count++] = suffix_dims[i];
        int field_array_size = 0;
        if (field_dim_count > 0) {
          field_array_size = 1;
          for (int i = 0; i < field_dim_count; i++)
            field_array_size *= field_dims[i] > 0 ? field_dims[i] : 1;
        }
        consume(parser, TOK_SEMICOLON, "Expected ';' after field declaration");

        if (st->field_count >= (int)(sizeof(st->fields) / sizeof(st->fields[0]))) {
          report_error(parser, "Too many fields in struct declaration");
          continue;
        }
        StructField *f = &st->fields[st->field_count++];
        f->name = fname_copy;
        f->is_volatile = f_volatile;
        f->offset = st->size;
        f->field_type = (field_dim_count > 0) ? field_elem_type : f_type;
        f->array_size = field_array_size;
        f->array_dim_count = field_dim_count;
        f->array_elem_type = field_elem_type;
        for (int i = 0; i < MAX_ARRAY_DIMS; i++)
          f->array_dims[i] = (i < field_dim_count) ? field_dims[i] : 0;
        /* Magnetar slots are 8 bytes wide; `any` fields are 16-byte tagged
           values, and so are arrays of `any`. */
        int elem_slot = parser_elem_slot_size(field_elem_type);
        st->size += (field_array_size > 0) ? field_array_size * elem_slot
                                           : elem_slot;
      }
    }
    consume(parser, TOK_RBRACE, "Expected '}' after struct fields");
    match(parser, TOK_SEMICOLON); // Optional semicolon

    struct_type_count++;

    return decl;
  }

  // free(expr);
  if (parser->current_token.type == TOK_KW_FREE) {
    Token t = parser->current_token;
    advance_token(parser);
    consume(parser, TOK_LPAREN, "Expected '(' after free");
    ASTNode *expr = parse_expression(parser);
    consume(parser, TOK_RPAREN, "Expected ')' after free");
    consume(parser, TOK_SEMICOLON, "Expected ';' after free");

    ASTNode *node = ASTNode_create(AST_FREE_STMT, t);
    ASTNode_add_child(node, expr);
    return node;
  }

  // delete expr;
  if (parser->current_token.type == TOK_KW_DELETE) {
    Token t = parser->current_token;
    advance_token(parser);
    ASTNode *expr = parse_expression(parser);
    consume(parser, TOK_SEMICOLON, "Expected ';' after delete");

    ASTNode *node = ASTNode_create(AST_FREE_STMT, t);
    ASTNode_add_child(node, expr);
    return node;
  }
  if (parser->current_token.type == TOK_PRINT) {
    Token t = parser->current_token;
    ASTNode *call = ASTNode_create(AST_CALL_EXPR, t);
    ASTNode *print_id = ASTNode_create(AST_IDENTIFIER_EXPR, t);
    advance_token(parser);
    ASTNode_add_child(call, print_id);

    bool has_paren = match(parser, TOK_LPAREN);
    do {
      ASTNode_add_child(call, parse_expression(parser));
    } while (match(parser, TOK_COMMA));
    if (has_paren)
      consume(parser, TOK_RPAREN, "Expected ')' after print arguments");
    consume(parser, TOK_SEMICOLON, "Expected ';' after print");
    return call;
  }
  if (match(parser, TOK_KW_RETURN)) {
    ASTNode *ret = ASTNode_create(AST_RETURN_STMT, parser->current_token);
    if (parser->current_token.type != TOK_SEMICOLON) {
      ASTNode_add_child(ret, parse_expression(parser));
    }
    consume(parser, TOK_SEMICOLON, "Expected ';' after return");
    return ret;
  }
  if (parser->current_token.type == TOK_KW_IF) {
    Token t = parser->current_token;
    ASTNode *if_node = ASTNode_create(AST_IF_STMT, t);
    advance_token(parser);
    bool has_paren = match(parser, TOK_LPAREN);
    ASTNode_add_child(if_node, parse_expression(parser));
    if (has_paren)
      consume(parser, TOK_RPAREN, "Expected ')' after if condition");
    ASTNode_add_child(if_node, parse_block(parser));
    if (match(parser, TOK_KW_ELSE)) {
      if (parser->current_token.type == TOK_KW_IF) {
        ASTNode_add_child(if_node, parse_statement(parser));
      } else {
        ASTNode_add_child(if_node, parse_block(parser));
      }
    }
    return if_node;
  }
  if (parser->current_token.type == TOK_KW_WHILE) {
    Token t = parser->current_token;
    ASTNode *while_node = ASTNode_create(AST_WHILE_STMT, t);
    advance_token(parser);
    bool has_paren = match(parser, TOK_LPAREN);
    ASTNode_add_child(while_node, parse_expression(parser));
    if (has_paren)
      consume(parser, TOK_RPAREN, "Expected ')' after while condition");
    parser->loop_depth++;
    ASTNode_add_child(while_node, parse_block(parser));
    parser->loop_depth--;
    return while_node;
  }
  if (parser->current_token.type == TOK_KW_DO) {
    Token t = parser->current_token;
    ASTNode *while_node = ASTNode_create(AST_WHILE_STMT, t);
    while_node->bool_value = true; // mark as do-while: body runs before condition
    advance_token(parser);
    parser->loop_depth++;
    ASTNode *body = parse_block(parser);
    parser->loop_depth--;
    consume(parser, TOK_KW_WHILE, "Expected 'while' after do block");
    bool has_paren = match(parser, TOK_LPAREN);
    ASTNode_add_child(while_node, parse_expression(parser));
    if (has_paren)
      consume(parser, TOK_RPAREN, "Expected ')' after while condition");
    consume(parser, TOK_SEMICOLON, "Expected ';' after do-while loop");
    ASTNode_add_child(while_node, body);
    return while_node;
  }
  // for (init; cond; post) { body } OR for (int i in range(start, end[, step]))
  // { body }
  if (parser->current_token.type == TOK_KW_FOR) {
    Token t = parser->current_token;
    ASTNode *for_node = ASTNode_create(AST_FOR_STMT, t);
    advance_token(parser);
    consume(parser, TOK_LPAREN, "Expected '(' after for");

    // Let's check if it starts with a variable declaration
    TokenType peek_type = parser->current_token.type;
    bool is_var_decl = (peek_type == TOK_KW_INT || peek_type == TOK_KW_FLOAT ||
                        peek_type == TOK_KW_BOOL || peek_type == TOK_KW_CHAR ||
                        peek_type == TOK_KW_STRING || peek_type == TOK_KW_RAW ||
                        peek_type == TOK_KW_BYTE || peek_type == TOK_KW_WORD ||
                        peek_type == TOK_KW_DWORD ||
                        peek_type == TOK_KW_QWORD || peek_type == TOK_KW_HALF ||
                        peek_type == TOK_KW_VOLATILE ||
                        peek_type == TOK_KW_REGISTER);

    if (is_var_decl) {
      TokenType var_type = parse_type(parser);
      Token id = parser->current_token;
      id.text = strdup(id.text);
      consume(parser, TOK_IDENTIFIER, "Expected identifier in loop variable");

      if (parser->current_token.type == TOK_IDENTIFIER &&
          strcmp(parser->current_token.text, "in") == 0) {
        advance_token(parser); // Consume 'in'
        consume(parser, TOK_KW_RANGE, "Expected 'range' after in");
        consume(parser, TOK_LPAREN, "Expected '(' after range");
        ASTNode *start_expr = parse_expression(parser);
        consume(parser, TOK_COMMA, "Expected ',' after range start");
        ASTNode *end_expr = parse_expression(parser);
        ASTNode *step_expr = NULL;
        if (match(parser, TOK_COMMA)) {
          step_expr = parse_expression(parser);
        } else {
          Token one_tok = id;
          one_tok.type = TOK_INT_LITERAL;
          one_tok.text = strdup("1");
          step_expr = ASTNode_create(AST_LITERAL_EXPR, one_tok);
          step_expr->int_value = 1;
        }
        consume(parser, TOK_RPAREN, "Expected ')' after range arguments");
        consume(parser, TOK_RPAREN,
                "Expected ')' after range loop declaration");

        // Lower to standard for loop!
        // 1. Init: var_type id = start;
        ASTNode *init = ASTNode_create(AST_VAR_DECL, id);
        init->int_value = var_type;
        init->is_volatile = false;
        ASTNode_add_child(init, start_expr);
        {
          char for_name_buf[64];
          for_name_buf[0] = '\0';
          if (id.text)
            snprintf(for_name_buf, sizeof(for_name_buf), "%s", id.text);
          register_parser_var(for_name_buf, var_type, NULL);
        }

        // 2. Cond: id < end
        Token lt_tok = id;
        lt_tok.type = TOK_LT;
        lt_tok.text = strdup("<");
        ASTNode *cond = ASTNode_create(AST_BINARY_EXPR, lt_tok);
        ASTNode *id_expr1 = ASTNode_create(AST_IDENTIFIER_EXPR, id);
        ASTNode_add_child(cond, id_expr1);
        ASTNode_add_child(cond, end_expr);

        // 3. Post: id = id + step
        Token assign_tok = id;
        assign_tok.type = TOK_ASSIGN;
        assign_tok.text = strdup("=");
        ASTNode *post = ASTNode_create(AST_BINARY_EXPR, assign_tok);
        ASTNode *id_expr2 = ASTNode_create(AST_IDENTIFIER_EXPR, id);
        ASTNode_add_child(post, id_expr2);

        Token plus_tok = id;
        plus_tok.type = TOK_PLUS;
        plus_tok.text = strdup("+");
        ASTNode *add = ASTNode_create(AST_BINARY_EXPR, plus_tok);
        ASTNode *id_expr3 = ASTNode_create(AST_IDENTIFIER_EXPR, id);
        ASTNode_add_child(add, id_expr3);
        ASTNode_add_child(add, step_expr);
        ASTNode_add_child(post, add);

        ASTNode_add_child(for_node, init);
        ASTNode_add_child(for_node, cond);
        ASTNode_add_child(for_node, post);
        parser->loop_depth++;
        ASTNode_add_child(for_node, parse_block(parser));
        parser->loop_depth--;
        return for_node;
      } else {
        // Reconstruct standard C-style for init
        ASTNode *init = ASTNode_create(AST_VAR_DECL, id);
        init->int_value = var_type;
        init->is_volatile = false;
        {
          char for_name_buf[64];
          for_name_buf[0] = '\0';
          if (id.text)
            snprintf(for_name_buf, sizeof(for_name_buf), "%s", id.text);
          register_parser_var(for_name_buf, var_type, NULL);
        }
        if (match(parser, TOK_ASSIGN)) {
          ASTNode_add_child(init, parse_expression(parser));
        }
        consume(parser, TOK_SEMICOLON, "Expected ';' after for init");
        ASTNode_add_child(for_node, init);

        // Rest of standard for loop
        ASTNode *cond = parse_expression(parser);
        ASTNode_add_child(for_node, cond);
        consume(parser, TOK_SEMICOLON, "Expected ';' after for condition");

        ASTNode *post = parse_expression(parser);
        ASTNode_add_child(for_node, post);
        consume(parser, TOK_RPAREN, "Expected ')' after for post");
        parser->loop_depth++;
        ASTNode_add_child(for_node, parse_block(parser));
        parser->loop_depth--;
        return for_node;
      }
    } else {
      // Standard C-style for loop without decl
      ASTNode *init = parse_statement(parser);
      ASTNode_add_child(for_node, init);
      ASTNode *cond = parse_expression(parser);
      ASTNode_add_child(for_node, cond);
      consume(parser, TOK_SEMICOLON, "Expected ';' after for condition");
      ASTNode *post = parse_expression(parser);
      ASTNode_add_child(for_node, post);
      consume(parser, TOK_RPAREN, "Expected ')' after for post");
      /* The body of a `for` loop is a loop body: `break` and `continue`
         inside it must be honoured. This branch (an init that is not a typed
         declaration, e.g. `let i = 0`) used to skip the loop_depth bump, so
         every `break`/`continue` in it was silently discarded. */
      parser->loop_depth++;
      ASTNode_add_child(for_node, parse_block(parser));
      parser->loop_depth--;
      return for_node;
    }
  }
  // switch (expr) { case x: ... default: ... }
  if (parser->current_token.type == TOK_KW_SWITCH) {
    Token t = parser->current_token;
    advance_token(parser);
    consume(parser, TOK_LPAREN, "Expected '(' after switch");
    ASTNode *switch_expr = parse_expression(parser);
    consume(parser, TOK_RPAREN, "Expected ')' after switch expr");
    consume(parser, TOK_LBRACE, "Expected '{' after switch");

    ASTNode *first_if = NULL;
    ASTNode *last_if = NULL;
    ASTNode *default_block = NULL;

    while (parser->current_token.type != TOK_RBRACE &&
           parser->current_token.type != TOK_EOF) {
      if (parser->current_token.type == TOK_KW_CASE) {
        advance_token(parser);
        ASTNode *case_val = parse_expression(parser);
        consume(parser, TOK_COLON, "Expected ':' after case value");

        ASTNode *case_block = ASTNode_create(AST_BLOCK, parser->current_token);
        parser->switch_depth++;
        while (parser->current_token.type != TOK_KW_CASE &&
               parser->current_token.type != TOK_KW_DEFAULT &&
               parser->current_token.type != TOK_RBRACE &&
               parser->current_token.type != TOK_EOF) {
          ASTNode *s = parse_statement(parser);
          if (s)
            ASTNode_add_child(case_block, s);
        }
        parser->switch_depth--;

        Token eq_tok;
        eq_tok.type = TOK_EQ;
        eq_tok.text = strdup("==");
        eq_tok.line = case_val->token.line;
        eq_tok.column = case_val->token.column;

        ASTNode *cond = ASTNode_create(AST_BINARY_EXPR, eq_tok);
        ASTNode_add_child(cond, ASTNode_clone(switch_expr));
        ASTNode_add_child(cond, case_val);

        Token if_tok;
        if_tok.type = TOK_KW_IF;
        if_tok.text = strdup("if");
        if_tok.line = case_val->token.line;
        if_tok.column = case_val->token.column;

        ASTNode *new_if = ASTNode_create(AST_IF_STMT, if_tok);
        ASTNode_add_child(new_if, cond);
        ASTNode_add_child(new_if, case_block);

        if (!first_if) {
          first_if = new_if;
        } else {
          ASTNode_add_child(last_if, new_if);
        }
        last_if = new_if;

      } else if (parser->current_token.type == TOK_KW_DEFAULT) {
        advance_token(parser);
        consume(parser, TOK_COLON, "Expected ':' after default");

        default_block =
            ASTNode_create(AST_BLOCK, parser->current_token);
        /* The default clause ends at the next `case` (if the author put
           `default` first) or at the closing brace. `switch` is desugared into
           an if/else chain, so `break` inside it must leave the switch only --
           never the enclosing loop. */
        parser->switch_depth++;
        while (parser->current_token.type != TOK_KW_CASE &&
               parser->current_token.type != TOK_KW_DEFAULT &&
               parser->current_token.type != TOK_RBRACE &&
               parser->current_token.type != TOK_EOF) {
          ASTNode *s = parse_statement(parser);
          if (s)
            ASTNode_add_child(default_block, s);
        }
        parser->switch_depth--;
      } else {
        advance_token(parser);
      }
    }
    consume(parser, TOK_RBRACE, "Expected '}' to close switch");
    ASTNode_free(switch_expr);
    if (default_block) {
      if (last_if) {
        ASTNode_add_child(last_if, default_block);
      } else {
        first_if = default_block;
      }
    }
    if (!first_if) {
      first_if = ASTNode_create(AST_BLOCK, t);
    }
    return first_if;
  }
  if (parser->current_token.type == TOK_KW_BREAK) {
    Token t = parser->current_token;
    /* Inside a loop `break` jumps to the loop exit. `switch` is desugared into
       an if/else chain, so a `break` that belongs to a switch is a no-op unless
       a loop encloses it. */
    bool real_break = (parser->loop_depth > 0 && parser->switch_depth == 0);
    ASTNode *brk =
        ASTNode_create(real_break ? AST_BREAK_STMT : AST_BLOCK, t);
    advance_token(parser);
    consume(parser, TOK_SEMICOLON, "Expected ';' after break");
    return brk;
  }
  if (parser->current_token.type == TOK_KW_CONTINUE) {
    Token t = parser->current_token;
    bool real_continue = (parser->loop_depth > 0);
    ASTNode *cont =
        ASTNode_create(real_continue ? AST_CONTINUE_STMT : AST_BLOCK, t);
    advance_token(parser);
    consume(parser, TOK_SEMICOLON, "Expected ';' after continue");
    return cont;
  }
  if (parser->current_token.type == TOK_LBRACE) {
    return parse_block(parser);
  }

  ASTNode *expr = parse_expression(parser);
  consume(parser, TOK_SEMICOLON, "Expected ';' after expression");
  ASTNode *stmt = ASTNode_create(AST_EXPR_STMT, parser->current_token);
  ASTNode_add_child(stmt, expr);
  return stmt;
}

static ASTNode *parse_function_opt(Parser *parser, bool is_extern) {
  int saved_var_count = parser_var_count;
  advance_token(parser);
  if (parser->current_token.type != TOK_IDENTIFIER) {
    report_error(parser, "Expected function name");
    return NULL;
  }
  Token name_tok = parser->current_token;
  char *fn_name_copy = name_tok.text ? strdup(name_tok.text) : NULL;
  ASTNode *fn_node = ASTNode_create(AST_FUNC_DECL, name_tok);
  if (fn_node->token.text)
    free((void *)fn_node->token.text);
  fn_node->token.text = fn_name_copy;
  if (is_extern) {
    fn_node->int_value = 1; // Mark as extern function!
  }
  advance_token(parser);

  consume(parser, TOK_LPAREN, "Expected '(' after function name");
  if (parser->current_token.type != TOK_RPAREN) {
    do {
      last_type_name = NULL;
      TokenType p_type = parse_type(parser);
      bool p_volatile = last_type_is_volatile;
      if (p_type == TOK_UNKNOWN && parser->current_token.type == TOK_IDENTIFIER) {
        last_type_name = remember_type_name(parser->current_token.text);
        advance_token(parser);
        p_type = TOK_KW_INT;
        while (parser->current_token.type == TOK_STAR) {
          advance_token(parser);
          p_type = TOK_KW_PTR;
        }
      } else if (p_type == TOK_UNKNOWN) {
        report_error(parser, "Invalid type in parameter declaration");
        advance_token(parser);
        continue;
      }
      Token p_name = parser->current_token;
      char *p_name_copy =
          (p_name.type == TOK_IDENTIFIER || p_name.type == TOK_KW_PTR)
              ? (p_name.text ? strdup(p_name.text) : NULL)
              : NULL;
      if (p_name.type == TOK_IDENTIFIER || p_name.type == TOK_KW_PTR) {
        advance_token(parser);
      } else {
        report_error(parser, "Expected parameter identifier");
      }

      p_name.text = p_name_copy;
      ASTNode *param = ASTNode_create(AST_VAR_DECL, p_name);
      if (param->token.text)
        free((void *)param->token.text);
      param->token.text = p_name_copy;
      param->int_value = p_type;
      param->is_volatile = p_volatile;
      if (last_type_name) {
        param->string_value = strdup(last_type_name);
      }
      register_parser_var(p_name_copy, p_type, last_type_name);
      ASTNode_add_child(fn_node, param);
    } while (match(parser, TOK_COMMA));
  }
  consume(parser, TOK_RPAREN, "Expected ')' after function parameters");

  if (match(parser, TOK_ARROW)) {
    /* Do not let a parameter's struct name leak into the return type:
       `fn main() -> int` must not be mistaken for a struct-returning
       function after a previous parameter declared `Foo x`. */
    last_type_name = NULL;
    TokenType ret_t = parse_type(parser); // Consume return type
    fn_node->int_value |= ((int)ret_t << 8);
    if (ret_t == TOK_KW_INT && last_type_name)
      fn_node->string_value = strdup(last_type_name);
    else if (ret_t == TOK_KW_ANY)
      fn_node->string_value = strdup("any");
  }
  register_parser_func(
      fn_name_copy, (TokenType)(fn_node->int_value >> 8), NULL,
      (fn_node->int_value >> 8) == TOK_KW_INT
          ? last_type_name
          : ((fn_node->int_value >> 8) == TOK_KW_ANY ? "any" : NULL));

  if (is_extern) {
    consume(parser, TOK_SEMICOLON,
            "Expected ';' after extern function declaration");
  } else {
    ASTNode_add_child(fn_node, parse_block(parser));
  }
  restore_parser_vars(saved_var_count);
  return fn_node;
}

static ASTNode *parse_function(Parser *parser) {
  return parse_function_opt(parser, false);
}

/* A method declared in an `impl Type { ... }` block. It behaves exactly like a
   method declared inside the type: the name is mangled to `Type_method`, the
   receiver is passed as an implicit first parameter (`self`/`this`), and the
   method may be called either as `value.method(...)` or -- from inside another
   method of the same type -- as `method(...)`. */
static ASTNode *parse_impl_method(Parser *parser, const char *owner) {
  int saved_var_count = parser_var_count;
  advance_token(parser); // past "fn"
  Token m_id = parser->current_token;
  char *m_id_copy = m_id.text ? strdup(m_id.text) : NULL;
  if (parser->current_token.type != TOK_IDENTIFIER) {
    report_error(parser, "Expected method name");
    if (m_id_copy)
      free(m_id_copy);
    return NULL;
  }
  advance_token(parser);

  char full_method_name[256];
  snprintf(full_method_name, sizeof(full_method_name), "%s_%s",
           owner ? owner : "impl", m_id_copy ? m_id_copy : "method");

  ASTNode *method = ASTNode_create(AST_FUNC_DECL, m_id);
  if (method->token.text)
    free((void *)method->token.text);
  method->token.text = strdup(full_method_name);

  /* Implicit receiver. `self` is the Rust-style spelling, `this` the
     C++-style one; both refer to the same parameter. */
  Token this_tok;
  this_tok.type = TOK_KW_THIS;
  this_tok.text = strdup("self");
  this_tok.line = m_id.line;
  this_tok.column = m_id.column;
  ASTNode *implicit_this = ASTNode_create(AST_VAR_DECL, this_tok);
  implicit_this->int_value = TOK_KW_PTR;
  implicit_this->string_value = owner ? strdup(owner) : NULL;
  ASTNode_add_child(method, implicit_this);
  register_parser_var("self", TOK_KW_PTR, owner);

  consume(parser, TOK_LPAREN, "Expected '(' after method name");
  if (parser->current_token.type != TOK_RPAREN) {
    do {
      last_type_name = NULL;
      TokenType p_type = parse_type(parser);
      bool p_volatile = last_type_is_volatile;
      if (p_type == TOK_UNKNOWN && parser->current_token.type == TOK_IDENTIFIER) {
        last_type_name = remember_type_name(parser->current_token.text);
        advance_token(parser);
        p_type = TOK_KW_INT;
        while (parser->current_token.type == TOK_STAR) {
          advance_token(parser);
          p_type = TOK_KW_PTR;
        }
      } else if (p_type == TOK_UNKNOWN) {
        report_error(parser, "Invalid type in parameter declaration");
        advance_token(parser);
        continue;
      }
      Token p_name = parser->current_token;
      char *p_name_copy =
          (p_name.type == TOK_IDENTIFIER || p_name.type == TOK_KW_PTR)
              ? (p_name.text ? strdup(p_name.text) : NULL)
              : NULL;
      if (p_name.type == TOK_IDENTIFIER || p_name.type == TOK_KW_PTR) {
        advance_token(parser);
      } else {
        report_error(parser, "Expected parameter identifier");
      }

      p_name.text = p_name_copy;
      ASTNode *param = ASTNode_create(AST_VAR_DECL, p_name);
      if (param->token.text)
        free((void *)param->token.text);
      param->token.text = p_name_copy;
      param->int_value = p_type;
      param->is_volatile = p_volatile;
      if (last_type_name) {
        param->string_value = strdup(last_type_name);
      }
      register_parser_var(p_name_copy, p_type, last_type_name);
      ASTNode_add_child(method, param);
    } while (match(parser, TOK_COMMA));
  }
  consume(parser, TOK_RPAREN, "Expected ')' after method parameters");

  if (match(parser, TOK_ARROW)) {
    TokenType ret_t = parse_type(parser);
    method->int_value |= ((int)ret_t << 8);
  }
  register_parser_func(full_method_name, (TokenType)(method->int_value >> 8),
                       owner, last_type_name);

  const char *saved_ctx = current_type_context;
  current_type_context = owner;
  ASTNode_add_child(method, parse_block(parser));
  current_type_context = saved_ctx;

  if (m_id_copy)
    free(m_id_copy);
  restore_parser_vars(saved_var_count);
  return method;
}

static char* parser_entry_name = NULL;

const char* Parser_get_entry_name(void) {
  return parser_entry_name;
}

ASTNode *Parser_parse(Parser *parser) {
  if (parser_entry_name) {
    free(parser_entry_name);
    parser_entry_name = NULL;
  }
  ASTNode *root = ASTNode_create(AST_PROGRAM, parser->current_token);
  while (parser->current_token.type != TOK_EOF) {
    if (parser->current_token.type == TOK_KW_INLINE) {
      advance_token(parser);
    }
    bool entry_marker = parser->current_token.type == TOK_IDENTIFIER &&
                        parser->current_token.text &&
                        strcmp(parser->current_token.text, "entry") == 0 &&
                        parser->next_token.type == TOK_KW_FN;
    if (entry_marker) {
      advance_token(parser);
    }
    if (parser->current_token.type == TOK_KW_FN) {
      ASTNode *fn = parse_function(parser);
      if (fn) {
        if (entry_marker) {
          free(parser_entry_name);
          parser_entry_name = strdup(fn->token.text);
        }
        ASTNode_add_child(root, fn);
      }
    } else {
      ASTNode *stmt = parse_statement(parser);
      if (stmt)
        ASTNode_add_child(root, stmt);
    }
    if (parser->has_error) {
      advance_token(parser);
    }
  }
  cleanup_parser_vars();
  return root;
}

