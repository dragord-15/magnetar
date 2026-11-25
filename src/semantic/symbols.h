#ifndef MAGNETAR_SEMANTIC_SYMBOLS_H
#define MAGNETAR_SEMANTIC_SYMBOLS_H

#include "types.h"

typedef struct Symbol {
    char* name;
    DataType* type;
    int scope_level;
    struct Symbol* next;
} Symbol;

typedef struct SymbolTable {
    Symbol** buckets;
    int bucket_count;
    int current_scope;
} SymbolTable;

SymbolTable* SymbolTable_create(int size);
void SymbolTable_enter_scope(SymbolTable* table);
void SymbolTable_exit_scope(SymbolTable* table);
void SymbolTable_insert(SymbolTable* table, const char* name, DataType* type);
Symbol* SymbolTable_lookup(SymbolTable* table, const char* name);
void SymbolTable_free(SymbolTable* table);

#endif // MAGNETAR_SEMANTIC_SYMBOLS_H
