#include "memory.h"
#include <stdlib.h>
#include <stdio.h>

void* magnetar_alloc(size_t size) {
    void* ptr = malloc(size);
    if (!ptr) {
        fprintf(stderr, "Magnetar Runtime Error: Out of memory\n");
        exit(1);
    }
    return ptr;
}

void magnetar_free(void* ptr) {
    if (ptr) {
        free(ptr);
    }
}

void* magnetar_realloc(void* ptr, size_t size) {
    void* new_ptr = realloc(ptr, size);
    if (!new_ptr && size > 0) {
        fprintf(stderr, "Magnetar Runtime Error: Out of memory during realloc\n");
        exit(1);
    }
    return new_ptr;
}
