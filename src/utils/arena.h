#ifndef MAGNETAR_ARENA_H
#define MAGNETAR_ARENA_H

#include <stddef.h>
#include <stdint.h>

/*
 * Arena Allocator - نظام تخصيص ذاكرة سريع
 * يحجز كتلة كبيرة مرة واحدة، ويُحرّر الكل دفعة واحدة.
 * زمن التخصيص: O(1) بدلاً من O(1) مع malloc overhead.
 * الإصدار v1.4.0 - المرحلة 3
 */

#define ARENA_DEFAULT_SIZE  (4 * 1024 * 1024)   /* 4 MB */
#define ARENA_ALIGN         8                    /* محاذاة 8 بايت */

typedef struct ArenaBlock {
    uint8_t*           base;     /* بداية الكتلة */
    size_t             size;     /* الحجم الكلي  */
    size_t             used;     /* المستخدم     */
    struct ArenaBlock* next;     /* كتلة تالية (overflow) */
} ArenaBlock;

typedef struct {
    ArenaBlock* current;         /* الكتلة النشطة حالياً */
    ArenaBlock* first;           /* أول كتلة (للتحرير)  */
    size_t      total_allocated; /* إجمالي ما خُصّص     */
    size_t      peak_usage;      /* الذروة              */
    size_t      alloc_count;     /* عدد عمليات التخصيص */
} Arena;

/* ── واجهة برمجة Arena ── */
Arena*  arena_create(size_t initial_size);
void*   arena_alloc(Arena* arena, size_t size);
void*   arena_alloc_zeroed(Arena* arena, size_t size);
char*   arena_strdup(Arena* arena, const char* str);
void    arena_reset(Arena* arena);       /* إعادة تعيين دون تحرير الذاكرة */
void    arena_free(Arena* arena);        /* تحرير كل الذاكرة */
void    arena_stats(Arena* arena);       /* طباعة إحصائيات */

/* ── وحدة ماكرو للراحة ── */
#define ARENA_ALLOC(arena, type)       ((type*)arena_alloc((arena), sizeof(type)))
#define ARENA_ALLOC_N(arena, type, n)  ((type*)arena_alloc((arena), sizeof(type) * (n)))

#endif /* MAGNETAR_ARENA_H */
