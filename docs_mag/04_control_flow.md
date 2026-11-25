# 04 — التحكم في التدفق: الشروط والحلقات

> **TL;DR**
> - التحكّم متاح بـ `if / else if / else` و `while` و `do-while` و `for` (بأسلوبي C و `range`).
> - `break` يخرج من الحلقة، و `continue` ينقل إلى الدورة التالية.
> - `switch` يعمل على قيمة واحدة بـ `case`/`default`، و `match` بنمط `=>` و `_` كبديل.
> - `range(start, end)` نصف مفتوح: يشمل `start` ولا يشمل `end`.
> - `goto` مدعوم مع تسميات (`end:`) — راجع [مثال FizzBuzz](#مثال-fizzbuzz-كامل) قبل استخدامه.

**حالة الدعم:** ✅ مستقر

## الشرط `if`

```c
if (score >= 90) {
    print("A\n");
} else if (score >= 70) {
    print("B\n");
} else {
    print("C\n");
}
```

- الشرط بين قوسين `( )`.
- الجسم بين أقواس معقوصة `{ }`.
- يدعم `else if` بأي عدد و `else` اختياري.

## حلقة `while`

تُنفّذ طالما الشرط صحيح:

```c
let i = 0;
let sum = 0;
while (i < 5) {
    sum = sum + i;
    i = i + 1;
}
print(sum);   // 10
```

### `while` مع `break`

```c
let k = 0;
while (true) {
    k += 1;
    if (k >= 4) {
        break;
    }
}
print(k);   // 4
```

### `continue`

```c
let i = 0;
while (i < 10) {
    i += 1;
    if (i % 2 == 0) {
        continue;   // تخطّي الأعداد الزوجية
    }
    print(i);
}
```

## حلقة `do ... while`

تُنفّذ الجسم **مرة واحدة على الأقل** قبل فحص الشرط:

```c
let d = 0;
do {
    d += 1;
} while (d < 3);
print(d);   // 3
```

## حلقة `for` بأسلوب C

```c
let fact = 1;
for (int n = 1; n <= 5; n = n + 1) {
    fact = fact * n;
}
print(fact);   // 120
```

الشكل العام:

```c
for (التهيئة; الشرط; التحديث) {
    ...
}
```

## حلقة `for` على نطاق (range)

```c
let rsum = 0;
for (int n in range(0, 5)) {
    rsum += n;
}
print(rsum);   // 10  (0+1+2+3+4)
```

- `range(start, end)` نصف مفتوح: يشمل `start` ولا يشمل `end`.

## `break` و `continue`

| الأمر | الوظيفة |
|-------|---------|
| `break` | الخروج من الحلقة فوراً |
| `continue` | الانتقال للدورة التالية |

## مثال: FizzBuzz كامل

```c
fn main() {
    let i = 1;
    while (i <= 20) {
        if (i % 15 == 0) {
            print("FizzBuzz\n");
        } else if (i % 3 == 0) {
            print("Fizz\n");
        } else if (i % 5 == 0) {
            print("Buzz\n");
        } else {
            print(i);
            print("\n");
        }
        i = i + 1;
    }
}
```

## `switch`

بديل نظيف لسلسلة `if/else if` على قيمة واحدة:

```c
let c = Color.GREEN;
switch (c) {
    case 1: { print("red\n"); }
    case 2: { print("green\n"); }
    default: { print("unknown\n"); }
}
```

- كل `case` يأخذ قيمة.
- `default` اختياري.

## `match`

صيغة نمطية أقرب للـ Rust:

```c
let grade = 2;
match (grade) {
    1 => { print("poor\n"); }
    2 => { print("fair\n"); }
    _ => { print("good\n"); }
}
```

- `=>` يفصل النمط عن الجسم.
- `_` هو النمط الافتراضي (wildcard).

## فرع `goto`

```c
goto end;
print("not printed\n");
end:
print("reached\n");
```

---
**السابق:** [03_operators.md](03_operators.md) |
**التالي:** [05_functions.md](05_functions.md) |
**الفهرس:** [README.md](README.md)
