#include "gc.h"
#include "memory.h"
#include <stdio.h>

static GC_Object* gc_head = NULL;
static size_t bytes_allocated = 0;

void GC_init(void) {
    gc_head = NULL;
    bytes_allocated = 0;

}

void* GC_alloc(size_t size) {
    GC_Object* obj = (GC_Object*)magnetar_alloc(sizeof(GC_Object) + size);
    obj->marked = 0;
    obj->size = size;
    obj->next = gc_head;
    gc_head = obj;
    bytes_allocated += size;
    
    if (bytes_allocated > 1024 * 1024) { // Trigger collection after 1MB
        GC_collect();
    }
    return (void*)(obj + 1);
}

void GC_collect(void) {

    // STUB: Mark phase
    // STUB: Sweep phase
    GC_Object** curr = &gc_head;
    while (*curr) {
        if (!(*curr)->marked) {
            GC_Object* unreached = *curr;
            *curr = unreached->next;
            bytes_allocated -= unreached->size;
            magnetar_free(unreached);
        } else {
            (*curr)->marked = 0; // Reset mark
            curr = &(*curr)->next;
        }
    }

}

void GC_shutdown(void) {
    /* تحرير كل العناصر بدون النظر لعلامة mark */
    GC_Object* curr = gc_head;
    while (curr) {
        GC_Object* next = curr->next;
        bytes_allocated -= curr->size;
        magnetar_free(curr);
        curr = next;
    }
    gc_head = NULL;

}
