# 24 — مكتبات الخوارزميات وجداول Hash (`lib/algorithm.mg`, `lib/hashmap.mg`)

**حالة الدعم:** ✅ مستقر (MVP، أعداد `int` 64-bit ونصوص `string`)

مكتبتان قياسيتان سريعتان:
- `lib/algorithm.mg`: بحث وترتيب على مصفوفات `int*` و`IntList`.
- `lib/hashmap.mg`: جداول Hash سريعة بـ open addressing (linear probing).

## الاستيراد

```mg
use "lib/algorithm.mg"; // يتضمن lib/collections.mg
use "lib/hashmap.mg";
```

---

## 1) `lib/hashmap.mg`

### التصميم

- **Open addressing + linear probing**: عناصر أقل، cache-friendly، بدون مؤشرات عقد.
- **سعة power-of-two** + قناع `idx = hash & (cap - 1)`.
- **حالة خانة `state`**: `0=empty, 1=filled, 2=tombstone`.
- **Load factor**: إعادة hash عند `(len + tombs) * 10 >= cap * 7` (~0.7).
- **Hash**:
  - `hash_i64(int)`: خلط splitmix64 finalizer.
  - `hash_str(string)`: FNV-1a 64-bit.

> ملاحظة تنفيذية: تم استخدام `int* state` (بدل `char*`) لتفادي مشكلة سلوك تخزين byte في نمط struct الحالي.

### الدوال العامة

```mg
fn hash_i64(int x) -> int;
fn hash_str(string s) -> int;
```

### `IntIntMap` (int64 -> int64)

```mg
struct IntIntMap {
    fn init(int initial_cap) -> void;
    fn put(int key, int val) -> void;
    fn get(int key, int def) -> int;   // يرجع def إذا غير موجود
    fn has(int key) -> bool;
    fn remove(int key) -> bool;         // true إذا وجد وحذف
    fn size() -> int;
    fn clear() -> void;
    fn free_map() -> void;
}
```

Helpers: `fn intintmap_keys(IntIntMap* m, int* out_keys) -> int;` (يكتب المفاتيح في مصفوفة مُخصّصة مسبقاً ويرجع العدد).

مثال:

```mg
use "lib/hashmap.mg";
extern fn print_int(int n) -> void;

fn main() -> int {
    IntIntMap m;
    m.init(16);
    m.put(10, 100);
    m.put(20, 200);
    print_int(m.get(20, 0 - 1)); // 200
    print_int(m.has(10));        // 1
    m.remove(10);
    print_int(m.get(10, 0 - 1)); // -1
    m.free_map();
    return 0;
}
```

### `StrIntMap` (string -> int64)

```mg
struct StrIntMap {
    fn init(int initial_cap) -> void;
    fn put(string key, int val) -> void;
    fn get(string key, int def) -> int;
    fn has(string key) -> bool;
    fn remove(string key) -> bool;
    fn size() -> int;
    fn clear() -> void;
    fn free_map() -> void;
}
```

Helper: `fn strintmap_keys(StrIntMap* m, string* out_keys) -> int;`

مثال:

```mg
StrIntMap sm; sm.init(8);
sm.put("apple", 1);
sm.put("banana", 2);
int v = sm.get("banana", 0 - 1); // 2
bool ok = sm.has("pear");        // false
sm.free_map();
```

### `StrStrMap` (string -> string)

```mg
struct StrStrMap {
    fn init(int initial_cap) -> void;
    fn put(string key, string val) -> void;
    fn get(string key, string def) -> string;
    fn has(string key) -> bool;
    fn remove(string key) -> bool;
    fn size() -> int;
    fn clear() -> void;
    fn free_map() -> void;
}
```

Helper: `fn strstrmap_keys(StrStrMap* m, string* out_keys) -> int;`

مثال:

```mg
StrStrMap cfg; cfg.init(8);
cfg.put("name", "magnetar");
string name = cfg.get("name", "?");
cfg.free_map();
```

### Sets و Key Iteration

```mg
struct IntSet { fn init(int cap)->void; fn add(int key)->bool; fn has(int key)->bool; fn remove(int key)->bool; fn size()->int; fn clear()->void; fn free_set()->void; }
struct StrSet { fn init(int cap)->void; fn add(string key)->bool; fn has(string key)->bool; fn remove(string key)->bool; fn size()->int; fn clear()->void; fn free_set()->void; }
```

Helpers:
```mg
fn intset_values(IntSet* s, int* out_vals) -> int;
fn strset_values(StrSet* s, string* out_vals) -> int;
```

### تعقيد HashMap/Set

| العملية | متوسط | أسوأ حالة |
|---|---:|---:|
| put/get/has/remove/add | O(1) | O(n) (تصادمات/cluster) |
| إعادة hash (resize) | O(n) متفرق | O(n) |

---

## 2) `lib/algorithm.mg`

### البحث

```mg
fn linear_search(int* arr, int n, int target) -> int; // index or -1
fn binary_search(int* arr, int n, int target) -> int; // sorted array
fn lower_bound(int* arr, int n, int target) -> int;   // first >= target
fn upper_bound(int* arr, int n, int target) -> int;   // first > target
```

نسخ `IntList`:

```mg
fn intlist_linear_search(IntList* list, int target) -> int;
fn intlist_binary_search(IntList* list, int target) -> int;
fn intlist_lower_bound(IntList* list, int target) -> int;
fn intlist_upper_bound(IntList* list, int target) -> int;
```

### الترتيب

```mg
fn quick_sort(int* arr, int n) -> void;    // سريع، غير stable، in-place
fn merge_sort(int* arr, int n) -> void;    // stable، O(n) temp buffer
fn heap_sort(int* arr, int n) -> void;     // in-place، O(1) extra
fn insertion_sort(int* arr, int n) -> void; // جيد للنطاقات الصغيرة
fn sort(int* arr, int n) -> void;          // alias = quick_sort
fn sort_stable(int* arr, int n) -> void;   // alias = merge_sort
```

نسخ `IntList`:

```mg
fn intlist_sort(IntList* list) -> void;
fn intlist_sort_stable(IntList* list) -> void;
fn intlist_heap_sort(IntList* list) -> void;
fn intlist_is_sorted(IntList* list) -> bool;
fn intlist_reverse(IntList* list) -> void;
```

### أدوات

```mg
fn is_sorted(int* arr, int n) -> bool;
fn reverse(int* arr, int n) -> void;
fn array_min(int* arr, int n) -> int;
fn array_max(int* arr, int n) -> int;
fn min_index(int* arr, int n) -> int;
fn max_index(int* arr, int n) -> int;
fn fill(int* arr, int n, int value) -> void;
fn copy_array(int* src, int* dst, int n) -> void;
fn count_value(int* arr, int n, int target) -> int;
fn array_equals(int* a, int* b, int n) -> bool;
fn array_sum(int* arr, int n) -> int;
fn clamp_int(int v, int lo, int hi) -> int;
fn unique_sorted(int* arr, int n) -> int;      // يزيل التكرار المتتالي، يرجع الطول الجديد
fn rotate_left(int* arr, int n, int k) -> void;
fn rotate_right(int* arr, int n, int k) -> void;
fn sort_desc(int* arr, int n) -> void;
fn binary_search_desc(int* arr, int n, int target) -> int;
```

نسخ `IntList` إضافية: `intlist_contains/index_of/remove_value/push_unique/copy/count/sum/min/max/sort_desc/unique_sorted/fill`.

### مثال كامل

```mg
use "lib/algorithm.mg";
use "lib/collections.mg";
extern fn print_int(int n) -> void;
extern fn print_str(string s) -> void;

fn main() -> int {
    IntList l; l.init(8);
    l.push(5); l.push(1); l.push(4); l.push(2); l.push(3);
    intlist_sort(&l); // 1 2 3 4 5

    int idx = intlist_binary_search(&l, 4); // 3
    print_int(idx); print_str("\n");

    int arr[6] = {9, 1, 8, 3, 7, 2};
    merge_sort(cast<int*>(arr), 6); // stable sort
    print_int(is_sorted(cast<int*>(arr), 6)); // 1

    l.free_list();
    return 0;
}
```

### التعقيد

| الخوارزمية | متوسط | أسوأ | ذاكرة إضافية | Stable |
|---|---:|---:|---:|:---:|
| quick_sort | O(n log n) | O(n^2) rare | O(log n) stack | لا |
| merge_sort | O(n log n) | O(n log n) | O(n) | نعم |
| heap_sort | O(n log n) | O(n log n) | O(1) | لا |
| insertion_sort | O(n^2) | O(n^2) | O(1) | نعم |
| binary_search | O(log n) | O(log n) | O(1) | - |

### ملاحظات عملية

- `binary_search/lower_bound/upper_bound` تتطلب **مصفوفة مرتبة تصاعدياً**.
- `quick_sort` يستخدم median-of-three + insertion cutoff (<=16) لتقليل overhead.
- لا يوجد generic comparator حالياً؛ الواجهة الحالية لـ `int`.

## الاختبار

تم التحقق بترجمة وتشغيل اختبارات صحة وفرز/بحث/resize/remove، وbenchmark بسيط: فرز 50k + 50k put/get في `IntIntMap` ~0.03s على بيئة التطوير.
