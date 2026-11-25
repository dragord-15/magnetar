#include "symbols.h"
#include <stdlib.h>
#include <string.h>

static unsigned int hash_str(const char* str) {
    unsigned int hash = 5381;
    int c;
    while ((c = *str++))
        hash = ((hash << 5) + hash) + c; /* hash * 33 + c */
    return hash;
}

SymbolTable* SymbolTable_create(int size) {
    SymbolTable* table = (SymbolTable*)malloc(sizeof(SymbolTable));
    table->bucket_count = size > 0 ? size : 256;
    table->buckets = (Symbol**)calloc(table->bucket_count, sizeof(Symbol*));
    table->current_scope = 0;
    return table;
}

void SymbolTable_enter_scope(SymbolTable* table) {
    table->current_scope++;
}

void SymbolTable_exit_scope(SymbolTable* table) {
    // Remove symbols in the current scope
    for (int i = 0; i < table->bucket_count; i++) {
        Symbol* curr = table->buckets[i];
        Symbol* prev = NULL;
        while (curr != NULL) {
            if (curr->scope_level == table->current_scope) {
                Symbol* to_delete = curr;
                if (prev) prev->next = curr->next;
                else table->buckets[i] = curr->next;
                curr = curr->next;
                free(to_delete->name);
                free(to_delete);
            } else {
                prev = curr;
                curr = curr->next;
            }
        }
    }
    table->current_scope--;
}

void SymbolTable_insert(SymbolTable* table, const char* name, DataType* type) {
    unsigned int index = hash_str(name) % table->bucket_count;
    Symbol* sym = (Symbol*)malloc(sizeof(Symbol));
    sym->name = strdup(name);
    sym->type = type;
    sym->scope_level = table->current_scope;
    sym->next = table->buckets[index];
    table->buckets[index] = sym;
}

Symbol* SymbolTable_lookup(SymbolTable* table, const char* name) {
    unsigned int index = hash_str(name) % table->bucket_count;
    Symbol* curr = table->buckets[index];
    while (curr != NULL) {
        if (strcmp(curr->name, name) == 0) return curr;
        curr = curr->next;
    }
    return NULL;
}

void SymbolTable_free(SymbolTable* table) {
    if (!table) return;
    for (int i = 0; i < table->bucket_count; i++) {
        Symbol* curr = table->buckets[i];
        while (curr != NULL) {
            Symbol* next = curr->next;
            free(curr->name);
            free(curr);
            curr = next;
        }
    }
    free(table->buckets);
    free(table);
}
