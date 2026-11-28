#ifndef MAGNETAR_SEMANTIC_H
#define MAGNETAR_SEMANTIC_H

#include "../parser/ast.h"

/* Lightweight semantic validation pass, run after parsing and before IR.
   Returns the number of errors reported through the diagnostics system.
   `entry` is the selected entry function name (NULL/empty means "main" and
   allows a warning when it is absent). */
int semantic_check(ASTNode* program, const char* entry);

#endif
