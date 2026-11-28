#ifndef MAGNETAR_PARSER_H
#define MAGNETAR_PARSER_H

#include "ast.h"
#include "../lexer/lexer.h"

typedef struct {
    Lexer* lexer;
    Token current_token;
    Token next_token;
    bool has_error;
    int loop_depth;   /* enclosing while/for/do bodies: `continue` target */
    int switch_depth; /* `switch` is desugared to an if/else chain: `break` is a no-op there */
} Parser;

void Parser_init(Parser* parser, Lexer* lexer);
ASTNode* Parser_parse(Parser* parser);
/* Function marked with `entry fn name(...)`, or NULL when absent. */
const char* Parser_get_entry_name(void);
/* Enable compile-time range checks for literal indices into fixed arrays.
   Off by default; selected by `magc --bounds-check`. */
void Parser_set_bounds_check(bool enabled);

#endif // MAGNETAR_PARSER_H
