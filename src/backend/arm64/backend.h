#ifndef MAGNETAR_ARM64_BACKEND_H
#define MAGNETAR_ARM64_BACKEND_H

#include "../backend.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Register the ARM64 (AArch64) backend with the generic backend registry. */
Backend* backend_arm64_get(void);

#ifdef __cplusplus
}
#endif

#endif /* MAGNETAR_ARM64_BACKEND_H */
