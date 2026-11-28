#ifndef MAGNETAR_ARM64_STUBS_H
#define MAGNETAR_ARM64_STUBS_H

#include "encoder.h"
#include <stdbool.h>

/* Emit a self-contained AArch64 implementation of one unresolved external.
   The same emitter is used by the standalone code generator and by the mag
   linker, so extern calls behave identically in both object modes. */
bool arm_emit_stub(A64Buf* buf, const char* name);

#endif /* MAGNETAR_ARM64_STUBS_H */
