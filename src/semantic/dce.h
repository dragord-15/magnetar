#ifndef MAGNETAR_DCE_H
#define MAGNETAR_DCE_H

#include "../parser/ast.h"

/* Remove unreachable top-level functions after `use` sources have been merged.
   The entry point, exported/extern functions, and every function named by an
   identifier or string in the remaining program are kept. Methods nested in
   classes/impls are never removed. Returns the number of removed functions. */
int semantic_drop_unused_functions(ASTNode* program, const char* entry_name);

#endif
