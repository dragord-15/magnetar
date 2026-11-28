#include "dce.h"

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define DCE_BUCKETS 4096

typedef struct NameNode {
    char* name;
    struct NameNode* next;
} NameNode;

typedef struct {
    NameNode* heads[DCE_BUCKETS];
    size_t count;
} NameSet;

typedef struct {
    char* name;
    bool kept;
    bool scanned;
} FuncGroup;

static unsigned name_hash(const char* name) {
    unsigned h = 2166136261u;
    for (const unsigned char* p = (const unsigned char*)name; *p; p++) {
        h ^= *p;
        h *= 16777619u;
    }
    return h & (DCE_BUCKETS - 1);
}

static bool name_set_add(NameSet* set, const char* name) {
    if (!name || !*name) return false;
    unsigned bucket = name_hash(name);
    for (NameNode* n = set->heads[bucket]; n; n = n->next) {
        if (strcmp(n->name, name) == 0) return false;
    }
    NameNode* node = (NameNode*)malloc(sizeof(*node));
    if (!node) return false;
    node->name = strdup(name);
    node->next = set->heads[bucket];
    set->heads[bucket] = node;
    set->count++;
    return true;
}

static bool name_set_has(const NameSet* set, const char* name) {
    if (!name || !*name) return false;
    unsigned bucket = name_hash(name);
    for (const NameNode* n = set->heads[bucket]; n; n = n->next) {
        if (strcmp(n->name, name) == 0) return true;
    }
    return false;
}

static void name_set_free(NameSet* set) {
    for (size_t i = 0; i < DCE_BUCKETS; i++) {
        NameNode* n = set->heads[i];
        while (n) {
            NameNode* next = n->next;
            free(n->name);
            free(n);
            n = next;
        }
    }
}

static void scan_references(ASTNode* node, NameSet* refs) {
    if (!node) return;
    if (node->type == AST_IDENTIFIER_EXPR || node->type == AST_CALL_EXPR ||
        node->type == AST_MEMBER_ACCESS) {
        name_set_add(refs, node->token.text);
    }
    /* String literals cover indirect calls such as fn_addr("name"). */
    if (node->string_value) name_set_add(refs, node->string_value);
    for (int i = 0; i < node->child_count; i++)
        scan_references(node->children[i], refs);
}

static void scan_root(ASTNode* node, NameSet* refs) {
    if (!node) return;
    /* A function declaration's own name lives in token.text, not in a child. */
    if (node->type == AST_FUNC_DECL) {
        for (int i = 0; i < node->child_count; i++)
            scan_references(node->children[i], refs);
    } else {
        scan_references(node, refs);
    }
}

static void add_group(FuncGroup** groups, size_t* count, size_t* capacity,
                      const char* name) {
    if (!name || !*name) return;
    for (size_t i = 0; i < *count; i++) {
        if (strcmp((*groups)[i].name, name) == 0) return;
    }
    if (*count == *capacity) {
        size_t next = *capacity ? *capacity * 2 : 16;
        FuncGroup* p = (FuncGroup*)realloc(*groups, next * sizeof(*p));
        if (!p) return;
        *groups = p;
        *capacity = next;
    }
    (*groups)[*count].name = strdup(name);
    (*groups)[*count].kept = false;
    (*groups)[*count].scanned = false;
    (*count)++;
}

static size_t find_group(const FuncGroup* groups, size_t count, const char* name) {
    for (size_t i = 0; i < count; i++) {
        if (strcmp(groups[i].name, name) == 0) return i;
    }
    return (size_t)-1;
}

static void keep_group(FuncGroup* groups, size_t count, const char* name) {
    size_t i = find_group(groups, count, name);
    if (i != (size_t)-1) groups[i].kept = true;
}

static bool is_exported_function(ASTNode* node) {
    if (!node || node->type != AST_EXPORT_DECL || node->child_count == 0)
        return false;
    ASTNode* decl = node->children[0];
    return decl && decl->type == AST_FUNC_DECL;
}

int semantic_drop_unused_functions(ASTNode* program, const char* entry_name) {
    if (!program || program->type != AST_PROGRAM || program->child_count == 0)
        return 0;

    FuncGroup* groups = NULL;
    size_t group_count = 0, group_capacity = 0;
    for (int i = 0; i < program->child_count; i++) {
        ASTNode* node = program->children[i];
        if (node && node->type == AST_FUNC_DECL)
            add_group(&groups, &group_count, &group_capacity, node->token.text);
    }
    if (group_count == 0) return 0;

    NameSet refs = {0};
    if (!entry_name || !*entry_name) entry_name = "main";
    keep_group(groups, group_count, entry_name);

    for (int i = 0; i < program->child_count; i++) {
        ASTNode* node = program->children[i];
        if (!node) continue;
        if (node->type == AST_FUNC_DECL) {
            if (node->int_value == 1)
                keep_group(groups, group_count, node->token.text); /* extern */
        } else if (is_exported_function(node)) {
            keep_group(groups, group_count, node->children[0]->token.text);
            scan_root(node->children[0], &refs);
        } else {
            scan_root(node, &refs);
        }
    }

    /* Reachability fixpoint: every kept function can make another function
       reachable; dead functions' references are deliberately ignored. */
    bool progress = true;
    while (progress) {
        progress = false;
        for (size_t g = 0; g < group_count; g++) {
            if (!groups[g].kept || groups[g].scanned) continue;
            groups[g].scanned = true;
            progress = true;
            for (int i = 0; i < program->child_count; i++) {
                ASTNode* node = program->children[i];
                if (node && node->type == AST_FUNC_DECL && node->token.text &&
                    strcmp(node->token.text, groups[g].name) == 0) {
                    scan_root(node, &refs);
                }
            }
        }
        for (size_t g = 0; g < group_count; g++) {
            if (!groups[g].kept && name_set_has(&refs, groups[g].name)) {
                groups[g].kept = true;
                progress = true;
            }
        }
    }

    int removed = 0;
    int write = 0;
    for (int i = 0; i < program->child_count; i++) {
        ASTNode* node = program->children[i];
        if (node && node->type == AST_FUNC_DECL) {
            size_t g = find_group(groups, group_count, node->token.text);
            if (g != (size_t)-1 && !groups[g].kept) {
                ASTNode_free(node);
                removed++;
                continue;
            }
        }
        program->children[write++] = node;
    }
    program->child_count = write;

    for (size_t i = 0; i < group_count; i++) free(groups[i].name);
    free(groups);
    name_set_free(&refs);
    return removed;
}
