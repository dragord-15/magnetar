#ifndef MAGNETAR_RUNTIME_MEMORY_H
#define MAGNETAR_RUNTIME_MEMORY_H

#include <stddef.h>

void* magnetar_alloc(size_t size);
void magnetar_free(void* ptr);
void* magnetar_realloc(void* ptr, size_t size);

#endif // MAGNETAR_RUNTIME_MEMORY_H
