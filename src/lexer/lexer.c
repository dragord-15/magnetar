#include "lexer.h"
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

void Lexer_init(Lexer* lexer, const char* source) {
    lexer->source = source;
    lexer->length = strlen(source);
    lexer->position = 0;
    lexer->line = 1;
    lexer->column = 1;
}

static char peek(Lexer* lexer) {
    if (lexer->position >= lexer->length) return '\0';
    return lexer->source[lexer->position];
}

static char peek_next(Lexer* lexer) {
    if (lexer->position + 1 >= lexer->length) return '\0';
    return lexer->source[lexer->position + 1];
}

static char advance(Lexer* lexer) {
    if (lexer->position >= lexer->length) return '\0';
    char c = lexer->source[lexer->position++];
    if (c == '\n') {
        lexer->line++;
        lexer->column = 1;
    } else {
        lexer->column++;
    }
    return c;
}

static void skip_whitespace_and_comments(Lexer* lexer) {
    while (1) {
        char c = peek(lexer);
        if (isspace(c)) {
            advance(lexer);
        } else if (c == '/' && peek_next(lexer) == '/') {
            // Line comment
            while (peek(lexer) != '\n' && peek(lexer) != '\0') {
                advance(lexer);
            }
        } else if (c == '/' && peek_next(lexer) == '*') {
            // Block comment
            advance(lexer);
            advance(lexer);
            while (peek(lexer) != '\0' && !(peek(lexer) == '*' && peek_next(lexer) == '/')) {
                advance(lexer);
            }
            if (peek(lexer) != '\0') {
                advance(lexer); // '*'
                advance(lexer); // '/'
            }
        } else {
            break;
        }
    }
}

static Token make_token(TokenType type, const char* text, int length, int line, int col) {
    Token t;
    t.type = type;
    t.text = strndup(text, length);
    t.length = length;
    t.line = line;
    t.column = col;
    return t;
}

static TokenType check_keyword(const char* text, int len) {
    struct { const char* word; TokenType type; } keywords[] = {
        {"int", TOK_KW_INT}, {"float", TOK_KW_FLOAT}, {"bool", TOK_KW_BOOL}, {"char", TOK_KW_CHAR},
        {"string", TOK_KW_STRING}, {"void", TOK_KW_VOID}, {"auto", TOK_KW_AUTO}, {"any", TOK_KW_ANY},
        {"byte", TOK_KW_BYTE}, {"word", TOK_KW_WORD}, {"dword", TOK_KW_DWORD}, {"qword", TOK_KW_QWORD},
        {"half", TOK_KW_HALF}, {"fixed", TOK_KW_FIXED}, {"dyn", TOK_KW_DYN}, {"slice", TOK_KW_SLICE},
        {"array", TOK_KW_ARRAY}, {"tuple", TOK_KW_TUPLE}, {"range", TOK_KW_RANGE},
        {"ptr", TOK_KW_PTR}, {"ref", TOK_KW_REF}, {"own", TOK_KW_OWN}, {"raw", TOK_KW_RAW}, {"null", TOK_KW_NULL},
        {"fn", TOK_KW_FN}, {"let", TOK_KW_LET}, {"struct", TOK_KW_STRUCT}, {"class", TOK_KW_CLASS}, {"enum", TOK_KW_ENUM},
        {"union", TOK_KW_UNION},
        {"if", TOK_KW_IF}, {"else", TOK_KW_ELSE}, {"switch", TOK_KW_SWITCH}, {"case", TOK_KW_CASE},
        {"default", TOK_KW_DEFAULT}, {"for", TOK_KW_FOR}, {"while", TOK_KW_WHILE}, {"do", TOK_KW_DO},
        {"break", TOK_KW_BREAK}, {"continue", TOK_KW_CONTINUE}, {"return", TOK_KW_RETURN}, {"goto", TOK_KW_GOTO},
        {"defer", TOK_KW_DEFER}, {"await", TOK_KW_AWAIT}, {"async", TOK_KW_ASYNC},
        {"spawn", TOK_KW_SPAWN}, {"match", TOK_KW_MATCH}, {"new", TOK_KW_NEW}, {"delete", TOK_KW_DELETE},
        {"use", TOK_KW_USE}, {"export", TOK_KW_EXPORT},
        {"as", TOK_KW_AS}, {"const", TOK_KW_CONST}, {"static", TOK_KW_STATIC}, {"extern", TOK_KW_EXTERN},
        {"inline", TOK_KW_INLINE}, {"volatile", TOK_KW_VOLATILE}, {"register", TOK_KW_REGISTER},
        {"alloc", TOK_KW_ALLOC}, {"free", TOK_KW_FREE},
        {"sizeof", TOK_KW_SIZEOF}, {"typeof", TOK_KW_TYPEOF}, {"cast", TOK_KW_CAST}, {"move", TOK_KW_MOVE},
        {"copy", TOK_KW_COPY}, {"borrow", TOK_KW_BORROW}, {"clone", TOK_KW_CLONE}, {"true", TOK_KW_TRUE},
        {"false", TOK_KW_FALSE}, {"nan", TOK_KW_NAN}, {"inf", TOK_KW_INF}, {"assert", TOK_KW_ASSERT},
        {"throw", TOK_KW_THROW}, {"try", TOK_KW_TRY}, {"catch", TOK_KW_CATCH}, {"finally", TOK_KW_FINALLY},
        {"this", TOK_KW_THIS}, {"self", TOK_KW_SELF}, {"super", TOK_KW_SUPER}, {"base", TOK_KW_BASE},
        {"extends", TOK_KW_EXTENDS}, {"impl", TOK_KW_IMPL}, {"unsafe", TOK_KW_UNSAFE},
        {"parallel", TOK_KW_PARALLEL}, {"asm", TOK_KW_ASM}, {"print", TOK_PRINT}
    };
    int count = sizeof(keywords) / sizeof(keywords[0]);
    for (int i = 0; i < count; i++) {
        if (strlen(keywords[i].word) == (size_t)len && strncmp(text, keywords[i].word, len) == 0) {
            return keywords[i].type;
        }
    }
    return TOK_IDENTIFIER;
}

Token Lexer_next_token(Lexer* lexer) {
    skip_whitespace_and_comments(lexer);

    int start_pos = lexer->position;
    int start_col = lexer->column;
    int start_line = lexer->line;
    char c = advance(lexer);

    if (c == '\0') return make_token(TOK_EOF, "EOF", 3, start_line, start_col);

    // Identifiers and keywords
    if (isalpha(c) || c == '_') {
        while (isalnum(peek(lexer)) || peek(lexer) == '_') {
            advance(lexer);
        }
        int len = lexer->position - start_pos;
        const char* text = lexer->source + start_pos;
        TokenType type = check_keyword(text, len);
        return make_token(type, text, len, start_line, start_col);
    }

    // Numbers
    if (isdigit(c)) {
        /* Radix prefixes: 0x/0X (hex), 0b/0B (binary), 0o/0O (octal).
           Digit separators (`1_000_000`) are accepted everywhere a digit is. */
        if (c == '0' && (peek(lexer) == 'x' || peek(lexer) == 'X')) {
            advance(lexer); // consume x/X
            while (isxdigit(peek(lexer)) || peek(lexer) == '_') advance(lexer);
            int len = lexer->position - start_pos;
            return make_token(TOK_INT_LITERAL, lexer->source + start_pos, len, start_line, start_col);
        }
        if (c == '0' && (peek(lexer) == 'b' || peek(lexer) == 'B')) {
            advance(lexer); // consume b/B
            while ((peek(lexer) == '0' || peek(lexer) == '1') || peek(lexer) == '_')
                advance(lexer);
            int len = lexer->position - start_pos;
            return make_token(TOK_INT_LITERAL, lexer->source + start_pos, len, start_line, start_col);
        }
        if (c == '0' && (peek(lexer) == 'o' || peek(lexer) == 'O')) {
            advance(lexer); // consume o/O
            while ((peek(lexer) >= '0' && peek(lexer) <= '7') || peek(lexer) == '_')
                advance(lexer);
            int len = lexer->position - start_pos;
            return make_token(TOK_INT_LITERAL, lexer->source + start_pos, len, start_line, start_col);
        }
        while (isdigit(peek(lexer)) || peek(lexer) == '_') advance(lexer);
        if (peek(lexer) == '.' && isdigit(peek_next(lexer))) {
            advance(lexer); // consume .
            while (isdigit(peek(lexer)) || peek(lexer) == '_') advance(lexer);
            if (peek(lexer) == 'e' || peek(lexer) == 'E') {
                /* Optional exponent: 1e10, 1.5e-3 */
                int save = lexer->position;
                advance(lexer);
                if (peek(lexer) == '+' || peek(lexer) == '-') advance(lexer);
                if (isdigit(peek(lexer))) {
                    while (isdigit(peek(lexer)) || peek(lexer) == '_') advance(lexer);
                } else {
                    lexer->position = save; /* not an exponent after all */
                }
            }
            if (peek(lexer) == 'f' || peek(lexer) == 'F') advance(lexer);
            int len = lexer->position - start_pos;
            return make_token(TOK_FLOAT_LITERAL, lexer->source + start_pos, len, start_line, start_col);
        }
        int len = lexer->position - start_pos;
        return make_token(TOK_INT_LITERAL, lexer->source + start_pos, len, start_line, start_col);
    }

    // Strings
    if (c == '"') {
        while (peek(lexer) != '"' && peek(lexer) != '\0') {
            if (peek(lexer) == '\\') advance(lexer); // skip escape
            advance(lexer);
        }
        if (peek(lexer) == '"') advance(lexer);
        int len = lexer->position - start_pos;
        return make_token(TOK_STRING_LITERAL, lexer->source + start_pos, len, start_line, start_col);
    }

    // Characters
    if (c == '\'') {
        /* An escape sequence consumes the backslash *and* the escaped
           character, so that `'\''` ends at its own closing quote instead of
           swallowing the escaped quote. */
        if (peek(lexer) == '\\') {
            advance(lexer); // consume '\'
        }
        advance(lexer);     // consume the (possibly escaped) character
        if (peek(lexer) == '\'') advance(lexer);
        int len = lexer->position - start_pos;
        return make_token(TOK_CHAR_LITERAL, lexer->source + start_pos, len, start_line, start_col);
    }

    // Operators and punctuation
    switch (c) {
        case '+':
            if (peek(lexer) == '=') { advance(lexer); return make_token(TOK_PLUS_ASSIGN, "+=", 2, start_line, start_col); }
            if (peek(lexer) == '+') { advance(lexer); return make_token(TOK_INC, "++", 2, start_line, start_col); }
            return make_token(TOK_PLUS, "+", 1, start_line, start_col);
        case '-':
            if (peek(lexer) == '>') { advance(lexer); return make_token(TOK_ARROW, "->", 2, start_line, start_col); }
            if (peek(lexer) == '=') { advance(lexer); return make_token(TOK_MINUS_ASSIGN, "-=", 2, start_line, start_col); }
            if (peek(lexer) == '-') { advance(lexer); return make_token(TOK_DEC, "--", 2, start_line, start_col); }
            return make_token(TOK_MINUS, "-", 1, start_line, start_col);
        case '*':
            if (peek(lexer) == '=') { advance(lexer); return make_token(TOK_STAR_ASSIGN, "*=", 2, start_line, start_col); }
            return make_token(TOK_STAR, "*", 1, start_line, start_col);
        case '/':
            if (peek(lexer) == '=') { advance(lexer); return make_token(TOK_SLASH_ASSIGN, "/=", 2, start_line, start_col); }
            return make_token(TOK_SLASH, "/", 1, start_line, start_col);
        case '=':
            if (peek(lexer) == '=') { advance(lexer); return make_token(TOK_EQ, "==", 2, start_line, start_col); }
            if (peek(lexer) == '>') { advance(lexer); return make_token(TOK_FAT_ARROW, "=>", 2, start_line, start_col); }
            return make_token(TOK_ASSIGN, "=", 1, start_line, start_col);
        case '!':
            if (peek(lexer) == '=') { advance(lexer); return make_token(TOK_NEQ, "!=", 2, start_line, start_col); }
            return make_token(TOK_NOT, "!", 1, start_line, start_col);
        case '<':
            if (peek(lexer) == '<' && peek_next(lexer) == '=') { advance(lexer); advance(lexer); return make_token(TOK_SHL_ASSIGN, "<<=", 3, start_line, start_col); }
            if (peek(lexer) == '=') { advance(lexer); return make_token(TOK_LE, "<=", 2, start_line, start_col); }
            if (peek(lexer) == '<') { advance(lexer); return make_token(TOK_SHL, "<<", 2, start_line, start_col); }
            return make_token(TOK_LT, "<", 1, start_line, start_col);
        case '>':
            if (peek(lexer) == '>' && peek_next(lexer) == '=') { advance(lexer); advance(lexer); return make_token(TOK_SHR_ASSIGN, ">>=", 3, start_line, start_col); }
            if (peek(lexer) == '=') { advance(lexer); return make_token(TOK_GE, ">=", 2, start_line, start_col); }
            if (peek(lexer) == '>') { advance(lexer); return make_token(TOK_SHR, ">>", 2, start_line, start_col); }
            return make_token(TOK_GT, ">", 1, start_line, start_col);
        case '.':
            if (peek(lexer) == '.') { advance(lexer); return make_token(TOK_RANGE, "..", 2, start_line, start_col); }
            return make_token(TOK_DOT, ".", 1, start_line, start_col);
        case ',': return make_token(TOK_COMMA, ",", 1, start_line, start_col);
        case ':': return make_token(TOK_COLON, ":", 1, start_line, start_col);
        case ';': return make_token(TOK_SEMICOLON, ";", 1, start_line, start_col);
        case '(': return make_token(TOK_LPAREN, "(", 1, start_line, start_col);
        case ')': return make_token(TOK_RPAREN, ")", 1, start_line, start_col);
        case '{': return make_token(TOK_LBRACE, "{", 1, start_line, start_col);
        case '}': return make_token(TOK_RBRACE, "}", 1, start_line, start_col);
        case '[': return make_token(TOK_LBRACKET, "[", 1, start_line, start_col);
        case ']': return make_token(TOK_RBRACKET, "]", 1, start_line, start_col);
        case '&':
            if (peek(lexer) == '&') { advance(lexer); return make_token(TOK_AND, "&&", 2, start_line, start_col); }
            if (peek(lexer) == '=') { advance(lexer); return make_token(TOK_AND_ASSIGN, "&=", 2, start_line, start_col); }
            return make_token(TOK_BIT_AND, "&", 1, start_line, start_col);
        case '|':
            if (peek(lexer) == '|') { advance(lexer); return make_token(TOK_OR, "||", 2, start_line, start_col); }
            if (peek(lexer) == '=') { advance(lexer); return make_token(TOK_OR_ASSIGN, "|=", 2, start_line, start_col); }
            return make_token(TOK_BIT_OR, "|", 1, start_line, start_col);
        case '^':
            if (peek(lexer) == '=') { advance(lexer); return make_token(TOK_XOR_ASSIGN, "^=", 2, start_line, start_col); }
            return make_token(TOK_BIT_XOR, "^", 1, start_line, start_col);
        case '~': return make_token(TOK_BIT_NOT, "~", 1, start_line, start_col);
        case '%':
            if (peek(lexer) == '=') { advance(lexer); return make_token(TOK_MOD_ASSIGN, "%=", 2, start_line, start_col); }
            return make_token(TOK_MOD, "%", 1, start_line, start_col);
        case '?': return make_token(TOK_QUESTION, "?", 1, start_line, start_col);
    }

    return make_token(TOK_UNKNOWN, lexer->source + start_pos, 1, start_line, start_col);
}

void Token_free(Token* token) {
    if (token->text) {
        free(token->text);
        token->text = NULL;
    }
}
