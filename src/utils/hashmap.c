#include "hashmap.h"
#include "../lexer/lexer.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* ── دالة التجزئة djb2 (أسرع من البحث الخطي بـ 10x) ── */
uint32_t hashmap_hash(const char* key) {
    uint32_t hash = 5381;
    int c;
    while ((c = (unsigned char)*key++))
        hash = ((hash << 5) + hash) + c;
    return hash;
}

/* ── إنشاء جدول هاش ── */
HashMap* hashmap_create(size_t capacity) {
    if (capacity == 0) capacity = HASHMAP_DEFAULT_CAPACITY;
    HashMap* map = (HashMap*)malloc(sizeof(HashMap));
    if (!map) return NULL;
    map->buckets         = (HashEntry**)calloc(capacity, sizeof(HashEntry*));
    map->capacity        = capacity;
    map->count           = 0;
    map->collision_count = 0;
    return map;
}

/* ── إدراج / تعديل قيمة ── */
bool hashmap_set(HashMap* map, const char* key, void* value) {
    if (!map || !key) return false;
    uint32_t hash  = hashmap_hash(key);
    size_t   idx   = hash % map->capacity;
    HashEntry* cur = map->buckets[idx];

    /* هل المفتاح موجود؟ نُحدّث قيمته */
    while (cur) {
        if (cur->hash == hash && strcmp(cur->key, key) == 0) {
            cur->value = value;
            return true;
        }
        cur = cur->next;
    }

    /* إدخال جديد */
    HashEntry* entry = (HashEntry*)malloc(sizeof(HashEntry));
    if (!entry) return false;
    entry->key   = strdup(key);
    entry->value = value;
    entry->hash  = hash;
    entry->next  = map->buckets[idx];
    if (map->buckets[idx] != NULL) {
        map->collision_count++;  /* تصادم فقط عند إدراج في bucket غير فارغ */
    }
    map->buckets[idx] = entry;
    map->count++;
    return true;
}

/* ── بحث في O(1) مُوسّط ── */
void* hashmap_get(HashMap* map, const char* key) {
    if (!map || !key) return NULL;
    uint32_t   hash = hashmap_hash(key);
    size_t     idx  = hash % map->capacity;
    HashEntry* cur  = map->buckets[idx];
    while (cur) {
        if (cur->hash == hash && strcmp(cur->key, key) == 0)
            return cur->value;
        cur = cur->next;
    }
    return NULL;
}

bool hashmap_has(HashMap* map, const char* key) {
    return hashmap_get(map, key) != NULL;
}

/* ── حذف مفتاح ── */
bool hashmap_delete(HashMap* map, const char* key) {
    if (!map || !key) return false;
    uint32_t   hash = hashmap_hash(key);
    size_t     idx  = hash % map->capacity;
    HashEntry* cur  = map->buckets[idx];
    HashEntry* prev = NULL;
    while (cur) {
        if (cur->hash == hash && strcmp(cur->key, key) == 0) {
            if (prev) prev->next = cur->next;
            else      map->buckets[idx] = cur->next;
            free(cur->key);
            free(cur);
            map->count--;
            return true;
        }
        prev = cur;
        cur  = cur->next;
    }
    return false;
}

/* ── تحرير الجدول ── */
void hashmap_free(HashMap* map) {
    if (!map) return;
    for (size_t i = 0; i < map->capacity; i++) {
        HashEntry* cur = map->buckets[i];
        while (cur) {
            HashEntry* next = cur->next;
            free(cur->key);
            free(cur);
            cur = next;
        }
    }
    free(map->buckets);
    free(map);
}

/* ── إحصائيات ── */
void hashmap_stats(HashMap* map) {
    if (!map) return;
    printf("[HashMap] count=%zu  capacity=%zu  collisions=%zu  load=%.2f%%\n",
           map->count, map->capacity, map->collision_count,
           (double)map->count / (double)map->capacity * 100.0);
}

/* ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 *  جدول الكلمات المفتاحية - يُستبدل به البحث الخطي
 * ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ */
static const struct { const char* word; int token_type; } kw_table[] = {
    {"fn",          TOK_KW_FN},       {"return",    TOK_KW_RETURN},
    {"let",         TOK_KW_LET},      {"if",        TOK_KW_IF},
    {"else",        TOK_KW_ELSE},     {"while",     TOK_KW_WHILE},
    {"for",         TOK_KW_FOR},
    {"int",         TOK_KW_INT},      {"float",     TOK_KW_FLOAT},
    {"bool",        TOK_KW_BOOL},     {"char",      TOK_KW_CHAR},
    {"string",      TOK_KW_STRING},   {"void",      TOK_KW_VOID},
    {"true",        TOK_KW_TRUE},     {"false",     TOK_KW_FALSE},
    {"struct",      TOK_KW_STRUCT},   {"class",     TOK_KW_CLASS},
    {"enum",        TOK_KW_ENUM},     {"union",     TOK_KW_UNION},
    {"use",         TOK_KW_USE},
    {"extern",      TOK_KW_EXTERN},
    {"const",       TOK_KW_CONST},    {"static",    TOK_KW_STATIC},
    {"print",       TOK_PRINT},       {"new",       TOK_KW_NEW},
    {"delete",      TOK_KW_DELETE},   {"alloc",     TOK_KW_ALLOC},
    {"free",        TOK_KW_FREE},     {"null",      TOK_KW_NULL},
    {"nan",         TOK_KW_NAN},      {"inf",       TOK_KW_INF},
    {"auto",        TOK_KW_AUTO},     {"typeof",    TOK_KW_TYPEOF},
    {"sizeof",      TOK_KW_SIZEOF},   {"cast",      TOK_KW_CAST},
    {"match",       TOK_KW_MATCH},    {"defer",     TOK_KW_DEFER},
    {"goto",        TOK_KW_GOTO},
    {"async",       TOK_KW_ASYNC},    {"await",     TOK_KW_AWAIT},
    {"spawn",       TOK_KW_SPAWN},    {"parallel",  TOK_KW_PARALLEL},
    {"try",         TOK_KW_TRY},      {"catch",     TOK_KW_CATCH},
    {"finally",     TOK_KW_FINALLY},  {"throw",     TOK_KW_THROW},
    {"impl",        TOK_KW_IMPL},     {"extends",   TOK_KW_EXTENDS},
    {"inline",      TOK_KW_INLINE},   {"unsafe",    TOK_KW_UNSAFE},
    {"asm",         TOK_KW_ASM},      {"assert",    TOK_KW_ASSERT},
    {"move",        TOK_KW_MOVE},     {"copy",      TOK_KW_COPY},
    {"borrow",      TOK_KW_BORROW},   {"clone",     TOK_KW_CLONE},
    {"ref",         TOK_KW_REF},      {"own",       TOK_KW_OWN},
    {"dyn",         TOK_KW_DYN},      {"any",       TOK_KW_ANY},
    {"tuple",       TOK_KW_TUPLE},    {"slice",     TOK_KW_SLICE},
    {"raw",         TOK_KW_RAW},
    {"fixed",       TOK_KW_FIXED},    {"array",     TOK_KW_ARRAY},
    {"byte",        TOK_KW_BYTE},     {"word",      TOK_KW_WORD},
    {"dword",       TOK_KW_DWORD},    {"qword",     TOK_KW_QWORD},
    {"half",        TOK_KW_HALF},     {"double",      TOK_KW_DOUBLE},
    {"volatile",    TOK_KW_VOLATILE}, {"register",  TOK_KW_REGISTER},
    {"break",        TOK_KW_BREAK},
    {"continue",    TOK_KW_CONTINUE}, {"switch",    TOK_KW_SWITCH},
    {"case",        TOK_KW_CASE},     {"default",   TOK_KW_DEFAULT},
    {NULL, 0}
};

HashMap* keyword_table_create(void) {
    HashMap* table = hashmap_create(512);
    if (!table) return NULL;
    for (int i = 0; kw_table[i].word != NULL; i++) {
        hashmap_set(table, kw_table[i].word,
                    (void*)(intptr_t)kw_table[i].token_type);
    }
    printf("[HashMap] Keyword table built: %zu keywords indexed\n", table->count);
    return table;
}

int keyword_lookup(HashMap* table, const char* word) {
    if (!table || !word) return -1;
    void* val = hashmap_get(table, word);
    if (!val) return -1;
    return (int)(intptr_t)val;
}
