#ifndef MAGNETAR_REDEF_H
#define MAGNETAR_REDEF_H

#include "../parser/ast.h"

/* Warn (never fail) when a top-level name is defined more than once in the
   preprocessed source. `use` is textual inclusion, so two modules can define
   the same helper; the first definition keeps winning for compatibility. */
void semantic_warn_redefinitions(ASTNode* program);

#endif
