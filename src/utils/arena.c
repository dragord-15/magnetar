#include "arena.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* ── إنشاء كتلة داخلية ── */
static ArenaBlock* block_create(size_t size) {
    ArenaBlock* block = (ArenaBlock*)malloc(sizeof(ArenaBlock));
    if (!block) return NULL;
    block->base = (uint8_t*)malloc(size);
    if (!block->base) { free(block); return NULL; }
    block->size = size;
    block->used = 0;
    block->next = NULL;
    return block;
}

/* ── إنشاء Arena ── */
Arena* arena_create(size_t initial_size) {
    if (initial_size == 0) initial_size = ARENA_DEFAULT_SIZE;
    Arena* arena = (Arena*)malloc(sizeof(Arena));
    if (!arena) return NULL;
    arena->first           = block_create(initial_size);
    arena->current         = arena->first;
    arena->total_allocated = 0;
    arena->peak_usage      = 0;
    arena->alloc_count     = 0;
    return arena;
}

/* ── تخصيص ذاكرة مُحاذاة في O(1) ── */
void* arena_alloc(Arena* arena, size_t size) {
    if (!arena || size == 0) return NULL;

    /* محاذاة الحجم لـ 8 بايت */
    size_t aligned = (size + (ARENA_ALIGN - 1)) & ~(size_t)(ARENA_ALIGN - 1);

    /* تحقق من وجود مساحة في الكتلة الحالية */
    if (arena->current->used + aligned <= arena->current->size) {
        void* ptr = arena->current->base + arena->current->used;
        arena->current->used += aligned;
        arena->total_allocated += aligned;
        arena->alloc_count++;
        if (arena->total_allocated > arena->peak_usage)
            arena->peak_usage = arena->total_allocated;
        return ptr;
    }

    /* إنشاء كتلة overflow إذا امتلأت الحالية */
    size_t new_block_size = arena->current->size * 2;
    if (new_block_size < aligned) new_block_size = aligned * 2;
    ArenaBlock* new_block = block_create(new_block_size);
    if (!new_block) return NULL;

    arena->current->next = new_block;
    arena->current       = new_block;

    void* ptr = arena->current->base;
    arena->current->used = aligned;
    arena->total_allocated += aligned;
    arena->alloc_count++;
    if (arena->total_allocated > arena->peak_usage)
        arena->peak_usage = arena->total_allocated;
    return ptr;
}

/* ── تخصيص مع تصفير ── */
void* arena_alloc_zeroed(Arena* arena, size_t size) {
    void* ptr = arena_alloc(arena, size);
    if (ptr) memset(ptr, 0, size);
    return ptr;
}

/* ── نسخ نص في Arena ── */
char* arena_strdup(Arena* arena, const char* str) {
    if (!str) return NULL;
    size_t len = strlen(str) + 1;
    char* dst = (char*)arena_alloc(arena, len);
    if (dst) memcpy(dst, str, len);
    return dst;
}

/* ── إعادة تعيين بدون تحرير ذاكرة (سريع جداً) ── */
void arena_reset(Arena* arena) {
    if (!arena) return;
    ArenaBlock* block = arena->first;
    while (block) {
        block->used = 0;
        block = block->next;
    }
    arena->current         = arena->first;
    arena->total_allocated = 0;
    arena->alloc_count     = 0;
}

/* ── تحرير كل الذاكرة ── */
void arena_free(Arena* arena) {
    if (!arena) return;
    ArenaBlock* block = arena->first;
    while (block) {
        ArenaBlock* next = block->next;
        free(block->base);
        free(block);
        block = next;
    }
    free(arena);
}

/* ── طباعة إحصائيات ── */
void arena_stats(Arena* arena) {
    if (!arena) return;
    printf("[Arena] alloc_count=%zu  total=%zu bytes  peak=%zu bytes\n",
           arena->alloc_count,
           arena->total_allocated,
           arena->peak_usage);
}
