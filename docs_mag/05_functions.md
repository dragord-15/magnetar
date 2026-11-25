# 05 — الدوال

> **TL;DR**
> - الشكل العام: `fn name(Type a, Type b) -> ReturnType { ... }`، ويمكن حذف `-> void`.
> - **ترتيب التعريفات لا يهم** داخل نفس الملف: يمكنك استدعاء دالة معرَّفة **بعد** `main`.
> - البنى تُمرَّر **بالقيمة** افتراضياً، والمؤشرات تمرّ كما هي (`int*`).
> - الاستدعاء الذاتي مدعوم: `factorial` و `fib` مثالان جاهزان.
> - أسماء الدوال المدمجة **محجوزة** (`print`, `len`, `alloc`, `new`, `exit`, ...) — راجع [09_builtins.md](09_builtins.md).

**حالة الدعم:** ✅ مستقر

## تعريف دالة

الهيكل العام:

```c
fn name(Type arg1, Type arg2) -> ReturnType {
    ...
    return value;
}
```

- عند عدم وجود قيمة إرجاع، يمكن حذف `-> ReturnType` أو كتابة `-> void`.

```c
fn add(int a, int b) -> int {
    return a + b;
}

fn banner() -> void {
    print("=== demo ===\n");
}

fn hello() {
    print("hi\n");
}
```

## استدعاء الدوال

```c
fn main() {
    banner();
    print(add(3, 4));   // 7
}
```

## الاستدعاء الذاتي (Recursion)

```c
fn factorial(int n) -> int {
    if (n <= 1) {
        return 1;
    }
    return n * factorial(n - 1);
}
```

## استدعاء دالة من دالة أخرى

```c
fn square(int n) -> int {
    return n * n;
}

fn sum_of_squares(int a, int b) -> int {
    return square(a) + square(b);
}
```

## الدوال والمصفوفات/المؤشرات

تُمرَّر البنى بالقيمة افتراضياً، والمؤشرات كما هي:

```c
fn increment(int* v) -> int {
    *v = *v + 1;
    return *v;
}

fn manhattan(Point p) -> int {
    let dx = p.x;
    let dy = p.y;
    if (dx < 0) { dx = -dx; }
    if (dy < 0) { dy = -dy; }
    return dx + dy;
}
```

## مثال كامل

```c
fn add(int a, int b) -> int { return a + b; }
fn square(int n) -> int { return n * n; }
fn sum_of_squares(int a, int b) -> int { return square(a) + square(b); }

fn factorial(int n) -> int {
    if (n <= 1) { return 1; }
    return n * factorial(n - 1);
}

fn fib(int n) -> int {
    if (n < 2) { return n; }
    return fib(n - 1) + fib(n - 2);
}

fn banner() -> void {
    print("=== functions demo ===\n");
}

fn main() {
    banner();
    print(add(3, 4));            print("\n"); // 7
    print(sum_of_squares(3, 4)); print("\n"); // 25
    print(factorial(6));         print("\n"); // 720
    print(fib(10));              print("\n"); // 55
}
```

## قواعد مهمة

- **الترتيب:** لا يهم داخل نفس الملف — استدعاء دالة معرَّفة **بعد** نقطة الاستدعاء يعمل (المترجم يجمع الرموز أولاً).
- **المعاملات:** بالصيغة `Type name` مفصولة بفواصل، والنوع مكتوب لكل معامل.
- **`return`:** إلزامي في الدوال غير `void`، ويمكن الاستغناء عنه في `void`.
- **أسماء الدوال المدمجة محجوزة:** مثل `print`, `len`, `alloc`, `new`, `exit` — راجع
  [09_builtins.md](09_builtins.md).

> **متى يظهر `error: Undefined symbol 'X'`؟** الخطأ يأتي من مرحلة توليد الشيفرة حين لا يُعثر على
> تعريف للرمز المستدعى. الأسباب العملية:
>
> | السبب | المثال | الحل |
> |-------|--------|------|
> | استدعاء دالة مدمجة بلا تصريح | `sqrt(2.0)` | أضف `extern fn sqrt(float) -> float;` — راجع [09_builtins.md](09_builtins.md) |
> | استدعاء دالة غير موجودة (خطأ مطبعي) | `nosuchfn(1)` | صحّح الاسم |
> | استدعاء دالة عضو (method) داخل `class`/`struct` باسمها المجرّد | `magnitude()` | استخدم `this.magnitude()` |
>
> راجع [13_debugging.md](13_debugging.md) لطريقة قراءة رسائل الخطأ.

---
**السابق:** [04_control_flow.md](04_control_flow.md) |
**التالي:** [06_structs_enums.md](06_structs_enums.md) |
**الفهرس:** [README.md](README.md)
