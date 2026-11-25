#ifndef MAGNETAR_HASHMAP_H
#define MAGNETAR_HASHMAP_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

/*
 * HashMap - جدول هاش سريع للكلمات المفتاحية وجداول الرموز
 * بحث في زمن O(1) مُوسّط بدلاً من البحث الخطي.
 * الإصدار v1.4.0 - المرحلة 3
 */

#define HASHMAP_DEFAULT_CAPACITY  256
#define HASHMAP_LOAD_FACTOR       0.75

typedef struct HashEntry {
    char*            key;
    void*            value;
    uint32_t         hash;
    struct HashEntry* next;    /* للتسلسل عند التصادم */
} HashEntry;

typedef struct {
    HashEntry**  buckets;
    size_t       capacity;
    size_t       count;
    size_t       collision_count;   /* لأغراض التشخيص */
} HashMap;

/* ── دالة التجزئة djb2 ── */
uint32_t hashmap_hash(const char* key);

/* ── واجهة برمجة HashMap ── */
HashMap* hashmap_create(size_t capacity);
void     hashmap_free(HashMap* map);
bool     hashmap_set(HashMap* map, const char* key, void* value);
void*    hashmap_get(HashMap* map, const char* key);
bool     hashmap_has(HashMap* map, const char* key);
bool     hashmap_delete(HashMap* map, const char* key);
void     hashmap_stats(HashMap* map);

/* ── تهيئة هاش الكلمات المفتاحية للمُحلّل ── */
HashMap* keyword_table_create(void);
int      keyword_lookup(HashMap* table, const char* word);  /* يُعيد TokenType أو -1 */

#endif /* MAGNETAR_HASHMAP_H */
