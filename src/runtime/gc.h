#ifndef MAGNETAR_RUNTIME_GC_H
#define MAGNETAR_RUNTIME_GC_H

#include <stddef.h>

// Simple mark-and-sweep GC interface stub
typedef struct GC_Object {
    struct GC_Object* next;
    int marked;
    size_t size;
} GC_Object;

void GC_init(void);
void* GC_alloc(size_t size);
void GC_collect(void);
void GC_shutdown(void);

#endif // MAGNETAR_RUNTIME_GC_H
