#include "redef.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_SEEN_DEFS 4096
#define HASH_BUCKETS 8192

typedef struct {
    char* name;
    int kind;
    int line;
    int column;
    int next; /* index of the next entry in the same bucket, or -1 */
} SeenDef;

static const char* kind_name(int kind) {
    switch (kind) {
        case 0: return "function";
        case 1: return "type";
        default: return "global variable";
    }
}

static int def_kind(ASTNodeType type) {
    switch (type) {
        case AST_FUNC_DECL: return 0;
        case AST_STRUCT_DECL: case AST_CLASS_DECL: case NODE_CLASS_DECL:
        case NODE_ENUM_DECL: case NODE_UNION_DECL: return 1;
        case AST_VAR_DECL: return 2;
        default: return -1;
    }
}

static unsigned hash_name(const char* name, int kind) {
    unsigned h = 2166136261u ^ (unsigned)kind;
    for (const unsigned char* p = (const unsigned char*)name; *p; p++) {
        h ^= *p;
        h *= 16777619u;
    }
    return h & (HASH_BUCKETS - 1);
}

void semantic_warn_redefinitions(ASTNode* program) {
    if (!program) return;
    SeenDef seen[MAX_SEEN_DEFS];
    int heads[HASH_BUCKETS];
    for (int i = 0; i < HASH_BUCKETS; i++) heads[i] = -1;
    int count = 0;

    for (int i = 0; i < program->child_count; i++) {
        ASTNode* node = program->children[i];
        if (!node) continue;
        int kind = def_kind(node->type);
        const char* name = node->token.text;
        if (kind < 0 || !name || !*name) continue;

        unsigned bucket = hash_name(name, kind);
        int found = -1;
        for (int j = heads[bucket]; j >= 0; j = seen[j].next) {
            if (seen[j].kind == kind && strcmp(seen[j].name, name) == 0) {
                found = j;
                break;
            }
        }
        if (found >= 0) {
            fprintf(stderr,
                    "Warning: redefinition of %s '%s' (first definition at line %d wins; "
                    "this one is at line %d, column %d)\n",
                    kind_name(kind), name, seen[found].line,
                    node->token.line, node->token.column);
            continue;
        }
        if (count < MAX_SEEN_DEFS) {
            seen[count].name = strdup(name);
            seen[count].kind = kind;
            seen[count].line = node->token.line;
            seen[count].column = node->token.column;
            seen[count].next = heads[bucket];
            heads[bucket] = count;
            count++;
        }
    }

    for (int j = 0; j < count; j++) free(seen[j].name);
}
