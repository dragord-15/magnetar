#ifndef MAGNETAR_LEXER_H
#define MAGNETAR_LEXER_H

#include "token.h"
#include <stdio.h>

typedef struct {
    const char* source;
    int length;
    int position;
    int line;
    int column;
} Lexer;

void Lexer_init(Lexer* lexer, const char* source);
Token Lexer_next_token(Lexer* lexer);
void Token_free(Token* token);

#endif // MAGNETAR_LEXER_H
