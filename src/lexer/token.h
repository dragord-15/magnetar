#ifndef MAGNETAR_TOKEN_H
#define MAGNETAR_TOKEN_H

typedef enum {
    // End of file
    TOK_EOF = 0,

    // Identifiers and Literals
    TOK_IDENTIFIER,
    TOK_INT_LITERAL,
    TOK_FLOAT_LITERAL,
    TOK_STRING_LITERAL,
    TOK_CHAR_LITERAL,

    // Keywords
    TOK_KW_LET,
    TOK_KW_INT, TOK_KW_FLOAT, TOK_KW_BOOL, TOK_KW_CHAR, TOK_KW_STRING, TOK_KW_VOID, TOK_KW_AUTO, TOK_KW_ANY,
    TOK_KW_BYTE, TOK_KW_WORD, TOK_KW_DWORD, TOK_KW_QWORD, TOK_KW_HALF, TOK_KW_FIXED, TOK_KW_DYN, TOK_KW_SLICE,
    TOK_KW_ARRAY, TOK_KW_TUPLE, TOK_KW_RANGE,
    TOK_KW_PTR, TOK_KW_REF, TOK_KW_OWN, TOK_KW_RAW, TOK_KW_NULL,
    TOK_KW_FN, TOK_KW_STRUCT, TOK_KW_CLASS, TOK_KW_ENUM, TOK_KW_UNION,
    TOK_KW_IF, TOK_KW_ELSE, TOK_KW_SWITCH, TOK_KW_CASE, TOK_KW_DEFAULT, TOK_KW_FOR, TOK_KW_WHILE, TOK_KW_DO, TOK_KW_BREAK, TOK_KW_CONTINUE,
    TOK_KW_RETURN, TOK_KW_GOTO, TOK_KW_DEFER, TOK_KW_AWAIT, TOK_KW_ASYNC, TOK_KW_SPAWN, TOK_KW_MATCH,
    TOK_KW_NEW, TOK_KW_DELETE, TOK_KW_USE, TOK_KW_EXPORT, TOK_KW_AS,
    TOK_KW_CONST, TOK_KW_STATIC, TOK_KW_EXTERN, TOK_KW_INLINE, TOK_KW_VOLATILE, TOK_KW_REGISTER,
    TOK_KW_ALLOC, TOK_KW_FREE, TOK_KW_SIZEOF, TOK_KW_TYPEOF, TOK_KW_CAST, TOK_KW_MOVE, TOK_KW_COPY, TOK_KW_BORROW, TOK_KW_CLONE,
    TOK_KW_TRUE, TOK_KW_FALSE, TOK_KW_NAN, TOK_KW_INF, TOK_KW_ASSERT,
    TOK_KW_THROW, TOK_KW_TRY, TOK_KW_CATCH, TOK_KW_FINALLY,
    TOK_KW_THIS, TOK_KW_SELF, TOK_KW_SUPER, TOK_KW_BASE, TOK_KW_EXTENDS, TOK_KW_IMPL, TOK_KW_UNSAFE,
    TOK_KW_PARALLEL, TOK_KW_ASM, TOK_PRINT,

    // Operators and Punctuation
    TOK_PLUS, TOK_MINUS, TOK_STAR, TOK_SLASH, TOK_MOD,
    TOK_ASSIGN, TOK_EQ, TOK_NEQ, TOK_LT, TOK_LE, TOK_GT, TOK_GE,
    TOK_AND, TOK_OR, TOK_NOT,
    TOK_BIT_AND, TOK_BIT_OR, TOK_BIT_XOR, TOK_BIT_NOT, TOK_SHL, TOK_SHR,
    TOK_PLUS_ASSIGN, TOK_MINUS_ASSIGN, TOK_STAR_ASSIGN, TOK_SLASH_ASSIGN, TOK_MOD_ASSIGN,
    TOK_SHL_ASSIGN, TOK_SHR_ASSIGN, TOK_AND_ASSIGN, TOK_OR_ASSIGN, TOK_XOR_ASSIGN,
    TOK_INC, TOK_DEC,          // ++, --
    TOK_QUESTION,              // ?
    TOK_ARROW, TOK_FAT_ARROW, // ->, =>
    TOK_DOT, TOK_COMMA, TOK_COLON, TOK_SEMICOLON,
    TOK_LPAREN, TOK_RPAREN,    // ()
    TOK_LBRACE, TOK_RBRACE,    // {}
    TOK_LBRACKET, TOK_RBRACKET,// []
    TOK_RANGE,                 // ..
    
    TOK_ERROR,
    TOK_UNKNOWN,
    /* Appended last on purpose: several backends encode TokenType values in
       object files, so inserting a keyword in the middle would shift every
       later opcode and corrupt emitted metadata. */
    TOK_KW_DOUBLE
} TokenType;

typedef struct {
    TokenType type;
    char* text;       // Null-terminated string for the token's lexeme
    int length;       // Length of the token
    int line;         // Line number
    int column;       // Column number
} Token;

const char* Token_type_to_string(TokenType type);

#endif // MAGNETAR_TOKEN_H
