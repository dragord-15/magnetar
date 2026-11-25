#ifndef MAGNETAR_SLICE_H
#define MAGNETAR_SLICE_H
#include <stdlib.h>
#include <string.h>

typedef struct {
    void** data;
    int count;
    int capacity;
} Slice;

Slice* slice_new(void);
void slice_push(Slice* s, void* item);
void* slice_get(Slice* s, int index);
void slice_free(Slice* s);

// Implementation
inline Slice* slice_new(void) {
    Slice* s = malloc(sizeof(Slice));
    if (!s) return NULL;
    s->count = 0;
    s->capacity = 8;
    s->data = malloc(sizeof(void*) * s->capacity);
    if (!s->data) { free(s); return NULL; }
    return s;
}

inline void slice_push(Slice* s, void* item) {
    if (!s) return;
    if (s->count >= s->capacity) {
        s->capacity *= 2;
        void** new_data = realloc(s->data, sizeof(void*) * s->capacity);
        if (!new_data) return;
        s->data = new_data;
    }
    s->data[s->count++] = item;
}

inline void* slice_get(Slice* s, int index) {
    if (!s || index < 0 || index >= s->count) return NULL;
    return s->data[index];
}

inline void slice_free(Slice* s) {
    if (!s) return;
    free(s->data);
    free(s);
}

#endif
