# 06 — البنى (Structs) والتعدادات (Enums)

> **TL;DR**
> - `struct` يجمع حقولاً، وتُقرأ الحقول بالنقطة `.`، والتهيئة بالحرفية `{3, 4}`.
> - `enum` يعطي قيماً عددية تُقرأ بـ `Color.RED`، وتُدمج مع `switch` و `match`.
> - البنية تُمرَّر **بالقيمة** افتراضياً: خذ `Point*` إن أردت تعديلها داخل الدالة.
> - الصيغة `let q: Point = {-3, 4};` مقبولة كبديل عن `Point q = {...};`.
> - `class`/`interface`/`trait`/`union` معرّفة في النحو فقط — راجع [12_notes_and_limitations.md](12_notes_and_limitations.md).

**حالة الدعم:** ✅ مستقر

## تعريف بنية (struct)

```c
struct Point {
    int x;
    int y;
}
```

- الأعضاء من أي نوع.
- يُنشأ المتغير ثم تُوصل الحقول بالنقطة `.`.

## استخدام البنية

```c
fn main() {
    // تهيئة حرفية بنوع صريح
    Point p = {3, 4};

    print(p.x + p.y);   // 7

    // تعديل الحقول
    p.x = 10;
    p.y = 20;
    print(p.x + p.y);   // 30
}
```

### صيغة النوع بعد النقطتين

```c
let q: Point = {-3, 4};
```

## تمرير البنية لدالة

تُمرَّر البنى **بالقيمة** افتراضياً:

```c
fn manhattan(Point p) -> int {
    let dx = p.x;
    let dy = p.y;
    if (dx < 0) { dx = -dx; }
    if (dy < 0) { dy = -dy; }
    return dx + dy;
}
```

## تعريف تعداد (enum)

```c
enum Color {
    RED = 1,
    GREEN = 2,
    BLUE = 3
}
```

- القيم اختيارية؛ إن لم تُحدَّد تُرقَّم تلقائياً: أول عنصر بلا قيمة يبدأ من `0`، وكل عنصر تالٍ بلا قيمة
  يأخذ **آخر قيمة صريحة + 1** (مثال: `A = 5, B, C = 10, D` ⇒ `5, 6, 10, 11`).
- الوصول: `Color.RED`، `Color.GREEN`، ...

```c
print(Color.RED);    // 1
print(Color.GREEN);  // 2
```

## استخدام التعداد مع `switch`

```c
let c = Color.GREEN;
switch (c) {
    case 1: { print("color is red\n"); }
    case 2: { print("color is green\n"); }
    default: { print("unknown color\n"); }
}
```

## استخدام التعداد مع `match`

```c
let grade = 2;
match (grade) {
    1 => { print("poor\n"); }
    2 => { print("fair\n"); }
    _ => { print("good\n"); }
}
```

## أنواع أخرى مذكورة في اللغة

اللغة تحتوي كلمات مفتاحية لأنواع تركيبية إضافية لم تُغطّ في هذا الفصل:

| النوع | الاستخدام |
|-------|-----------|
| `union` | اتحاد |
| `class` | صنف بميراث (`extends`) |
| `interface` | واجهة |
| `trait` | سمة |
| `module` | وحدة |

هذه الأنواع معرّفة في النحو؛ راجع [12_notes_and_limitations.md](12_notes_and_limitations.md) لمعرفة
حدود الدعم الحالية.

## مثال كامل

```c
struct Point {
    int x;
    int y;
}

enum Color {
    RED = 1,
    GREEN = 2,
    BLUE = 3
}

fn manhattan(Point p) -> int {
    let dx = p.x;
    let dy = p.y;
    if (dx < 0) { dx = -dx; }
    if (dy < 0) { dy = -dy; }
    return dx + dy;
}

fn main() {
    Point p = {3, 4};
    print(p.x + p.y);         print("\n"); // 7
    p.x = 10; p.y = 20;
    print(manhattan(p));      print("\n"); // 30

    let q: Point = {-3, 4};
    print(manhattan(q));      print("\n"); // 7

    print(Color.RED);         print("\n"); // 1
    print(Color.GREEN);       print("\n"); // 2
}
```

---
**السابق:** [05_functions.md](05_functions.md) |
**التالي:** [07_pointers_arrays_memory.md](07_pointers_arrays_memory.md) |
**الفهرس:** [README.md](README.md)
