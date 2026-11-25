# 16 — مكتبة البايتات `lib/bytes.mg`

> **TL;DR**
> - مكتبة صغيرة مكتوبة بلغة Magnetar لتحويل عدد البايتات إلى حجم مقروء:
>   `B`, `KB`, `MB`, `GB`, `TB`, `PB`, `EB`, `ZB`, `YB`.
> - تختار الوحدة تلقائياً حسب حجم العدد، فلا تحتاج إلى كتابة `if` لكل وحدة.
> - تدعم عرفين: **الثنائي** (1024، الافتراضي) و**العشري SI** (1000).
> - تُرجع `string` جاهزاً للطباعة عبر `print_str`، مع تحكم في عدد المنازل العشرية.

## 1. الاستيراد

أضف السطر التالي في بداية ملف `.mg`:

```c
use "lib/bytes.mg";
```

المكتبة تستورد `string.mg` تلقائياً، لذلك تحصل على `print_str` و`float_to_str`
و`str_concat` دون استيراد إضافي. لا حاجة لاستيراد `lib/string.mg` مرة أخرى؛
نظام الوحدات يتجنّب تحميل الملف نفسه مرتين.

## 2. الوحدات المدعومة

| الفهرس | الاسم | المعامل الثنائي (1024) | المعامل العشري SI (1000) |
|--------|-------|-------------------------|---------------------------|
| 0 | `B` | 1 | 1 |
| 1 | `KB` | 1024 | 1,000 |
| 2 | `MB` | 1024² | 1,000² |
| 3 | `GB` | 1024³ | 1,000³ |
| 4 | `TB` | 1024⁴ | 1,000⁴ |
| 5 | `PB` | 1024⁵ | 1,000⁵ |
| 6 | `EB` | 1024⁶ | 1,000⁶ |
| 7 | `ZB` | 1024⁷ | 1,000⁷ |
| 8 | `YB` | 1024⁸ | 1,000⁸ |

> `BT` ليست اختصاراً قياسياً. المكتبة تستخدم `PB` للبيتابايت (Petabyte)، وهي
> الوحدة التي تلي `TB`. أما `EB` فهي Exabyte، ثم `ZB` و`YB`.

### الثنائي مقابل العشري

- `bytes_to_string` و`bytes_value` و`unit_to_bytes` تستخدم **1024**.
  هذا هو العرف الشائع في أنظمة التشغيل والذاكرة: `1 KB = 1024 B`.
- الدوال المنتهية بـ `_si` تستخدم **1000**:
  `bytes_to_string_si`, `bytes_value_si`, `unit_to_bytes_si`.
  هذا هو العرف المستخدم في التخزين التسويقي ووحدات SI.

```c
print_str(bytes_to_string(1024));      // 1.00 KB   (1024)
print_str(bytes_to_string_si(1000));   // 1.00 KB   (1000)
```

## 3. واجهة المكتبة

### التنسيق التلقائي

| الدالة | الوصف |
|--------|-------|
| `bytes_to_string(int bytes) -> string` | وحدات ثنائية، منزلتان عشريتان، و`B` بلا كسور |
| `bytes_to_string_prec(int bytes, int decimals) -> string` | نفس الشيء مع عدد منازل مخصص (0..6) |
| `bytes_to_string_si(int bytes) -> string` | وحدات عشرية SI، منزلتان |
| `bytes_to_string_si_prec(int bytes, int decimals) -> string` | SI مع منازل مخصصة |
| `bytes_format(int bytes) -> string` | اختصار لـ `bytes_to_string` |
| `bytes_format_si(int bytes) -> string` | اختصار لـ `bytes_to_string_si` |

### اختيار الوحدة والأسماء

| الدالة | الوصف |
|--------|-------|
| `bytes_unit_index(int bytes) -> int` | فهرس الوحدة الثنائية المناسبة |
| `bytes_unit_index_si(int bytes) -> int` | فهرس الوحدة العشرية المناسبة |
| `bytes_unit_name(int unit) -> string` | اسم الوحدة من فهرسها (`0` → `"B"`) |
| `bytes_unit_count() -> int` | عدد الوحدات المدعومة (9) |

### القيم العددية والتحويل العكسي

| الدالة | الوصف |
|--------|-------|
| `bytes_value(int bytes, int unit) -> float` | قيمة البايتات بوحدة ثنائية محددة |
| `bytes_value_si(int bytes, int unit) -> float` | قيمة البايتات بوحدة عشرية محددة |
| `unit_to_bytes(float value, int unit) -> int` | تحويل قيمة بوحدة ثنائية إلى بايتات |
| `unit_to_bytes_si(float value, int unit) -> int` | تحويل قيمة بوحدة عشرية إلى بايتات |

### البتات

| الدالة | الوصف |
|--------|-------|
| `bytes_to_bits(int bytes) -> int` | `bytes * 8` |
| `bits_to_bytes(int bits) -> int` | `bits / 8` |

## 4. البدء السريع

```c
use "lib/bytes.mg";

fn main() {
    print_str(bytes_to_string(0));          // 0 B
    print_str(bytes_to_string(500));        // 500 B
    print_str(bytes_to_string(1024));       // 1.00 KB
    print_str(bytes_to_string(1536));       // 1.50 KB
    print_str(bytes_to_string(1048576));    // 1.00 MB
    print_str(bytes_to_string(2147483648)); // 2.00 GB
}
```

لأن الدوال تُرجع `string`، استخدم `print_str` وليس `print`. الدالة `print`
تعامل القيمة كعدد أو مؤشر ولا تطبع محتوى النص.

للطباعة على أسطر منفصلة:

```c
print_str(bytes_to_string(1536));
print("\n");
```

## 5. أمثلة عملية

### حجم ملف

```c
use "lib/file.mg";
use "lib/bytes.mg";

fn main() {
    int size = file_size("data.bin");
    print_str(bytes_to_string(size));
    print("\n");
}
```

### اختيار الوحدة يدوياً

```c
int bytes = 5 * 1024 * 1024 + 512 * 1024;   // 5.5 MiB
int unit = bytes_unit_index(bytes);          // 2 == MB

print_str(bytes_to_string(bytes));           // 5.50 MB
print("\n");
print_str(bytes_unit_name(unit));            // MB
print("\n");
print(bytes_value(bytes, unit));             // 5.5
```

### تحويل عكسي

```c
int bytes = unit_to_bytes(1.5, 1);   // 1.5 KB -> 1536
print(bytes);                        // 1536
print("\n");

int bits = bytes_to_bits(2);         // 16
print(bits);
print("\n");
```

### التحكم في المنازل العشرية

```c
print_str(bytes_to_string_prec(1536, 0));   // 2 KB
print_str(bytes_to_string_prec(1536, 4));   // 1.5000 KB
print_str(bytes_to_string_prec(1023, 2));   // 1023 B
```

## 6. كيف تعمل داخلياً

### الخطوة 1: إزالة الإشارة

تعمل الحسابات على القيمة المطلقة:

```c
int magnitude = _bytes_abs(bytes);
```

ثم تُضاف إشارة `-` إلى النتيجة النهائية إذا كان العدد الأصلي سالباً. هذا يتجنّب
مشاكل `float` السالبة المعروفة في الإصدارات الحالية.

### الخطوة 2: اختيار الوحدة

تبدأ الوحدة من `0` (بايت)، وتقسم القيمة على الأساس مرة كلما بقيت أكبر من أو
تساوي الأساس:

```c
int unit = 0;
while (magnitude >= radix && unit < 8) {
    magnitude = magnitude / radix;
    unit = unit + 1;
}
```

حيث `radix` هو `1024` أو `1000`. النتيجة أن الوحدة المختارة هي أكبر وحدة تجعل
القيمة المعروضة بين `1` والأساس. مثلاً:

| العدد | الوحدة المختارة | القيمة المعروضة |
|-------|------------------|------------------|
| 999 | B | 999 B |
| 1024 | KB | 1.00 KB |
| 1536 | KB | 1.50 KB |
| 1048575 | KB | 1023.999… KB ثم تُقرَّب لاحقاً |
| 1048576 | MB | 1.00 MB |

### الخطوة 3: حساب القيمة المقيسة

```c
int factor = radix ^ unit;                 // 1024, 1024², ...
float scaled = magnitude / factor;
```

القيمة `scaled` هي العدد الذي سيظهر بجانب اسم الوحدة.

### الخطوة 4: التقريب وترقية الوحدة

تُقرَّب القيمة إلى عدد المنازل المطلوبة باستخدام نصف-للأعلى:

```c
int scale = 10 ^ decimals;
int scaled_int = (int)(scaled * scale + 0.5);
```

مشكلة شائعة: قيمة مثل `1023.999 KB` قد تُقرَّب إلى `1024.00 KB`، وهذا يجب أن
يصبح `1.00 MB` وليس `1024.00 KB`. لذلك تفحص المكتبة:

```c
if (scaled_int >= radix * scale && unit < 8) {
    unit = unit + 1;
    scaled_int = scaled_int / radix;
}
```

أي أن تجاوز الأساس عند التقريب يُرقّي الوحدة تلقائياً. هذا يظهر في مثال SI:

```c
bytes_to_string_si(999999);   // 1.00 MB وليس 1000.00 KB
```

### الخطوة 5: تنسيق النص

بعد التقريب تُستخدم `float_to_str` من `lib/string.mg` لتحويل القيمة إلى نص،
ثم يُدمج الناتج مع مسافة واسم الوحدة عبر `str_concat`:

```c
string number = float_to_str(scaled, decimals);
string result = str_concat(number, " ");
result = str_concat(result, bytes_unit_name(unit));
```

إذا كان العدد الأصلي سالباً تُضاف `-` في البداية.

### الخطوة 6: حالة البايتات

عندما تكون الوحدة `B` (الفهرس `0`) تُجبر المنازل العشرية على الصفر، فلا تظهر
`500.00 B` بل `500 B`. الوحدات الأكبر تعرض المنازل المطلوبة (`1.00 KB`).

## 7. حالات خاصة وحدود

- **الصفر:** `bytes_to_string(0)` تُرجع `"0 B"`.
- **الأعداد السالبة:** تُعرض القيمة المطلقة مع إشارة سالبة، مثل `"-1.50 KB"`.
- **المنازل العشرية:** تُقصّ إلى المدى `0..6`. القيمة الافتراضية `2`.
- **الوحدة B:** لا كسور مهما كان عدد المنازل المطلوب.
- **الترقية عند التقريب:** تعمل حتى الوحدة `YB` (الفهرس `8`).
- **حدود `int`:** النوع `int` في Magnetar هو 64-bit، وأقصى قيمة موجبة نحو
  `9.22e18` بايت، أي نحو `8 EB` ثنائياً. الوحدات `ZB` و`YB` موجودة في الأسماء
  والتحويلات لكن لا يمكن الوصول إليها بعدد بايتات يبدأ من `int` موجب.
- **الدقة:** تعتمد المكتبة على `float` 32-bit في حساب القيمة المقيسة، لذا قد
  تختلف المنازل الأخيرة جداً في الأعداد الضخمة. المنازل العشرية القليلة
  (0..2) دقيقة عملياً.
- **السلاسل الناتجة:** كل استدعاء لتنسيق يُنشئ `string` جديداً عبر `alloc`،
  مثل بقية دوال `lib/string.mg`.

## 8. الاختبار والتحقق

مثال جاهز للتشغيل:

```bash
./magc examples/test_bytes.mg -o /tmp/test_bytes
/tmp/test_bytes
```

اختبار الانحدار:

```bash
./tests/run.sh c17
```

الملف `tests/cases/c17_bytes_library.mg` يغطي:

- `0` و`500` و`1023` بايت.
- `1024` (KB)، `1536` (1.50 KB)، و`1048576` (MB).
- `5.5 MB` و`2 GB` و`3 TB` و`4 PB` و`5 EB`.
- التقريب إلى منازل صفرية.
- الوحدات العشرية SI.
- `bytes_unit_index` و`bytes_unit_name`.
- التحويل العكسي `unit_to_bytes`.
- تحويل البايتات إلى بتات والعكس.

الناتج المتوقع:

```text
0 B|500 B|1023 B|1.00 KB|1.50 KB|1.00 MB|5.50 MB|2.00 GB|3.00 TB|4.00 PB|5.00 EB|2 KB|1.50 KB|1.00 MB|KB|1536|16|2
```

## 9. مرجع سريع

```c
use "lib/bytes.mg";

// التنسيق
bytes_to_string(bytes)
bytes_to_string_prec(bytes, decimals)
bytes_to_string_si(bytes)
bytes_to_string_si_prec(bytes, decimals)

// الوحدات
bytes_unit_index(bytes)
bytes_unit_index_si(bytes)
bytes_unit_name(unit)
bytes_unit_count()

// القيم والتحويل العكسي
bytes_value(bytes, unit)
bytes_value_si(bytes, unit)
unit_to_bytes(value, unit)
unit_to_bytes_si(value, unit)

// البتات
bytes_to_bits(bytes)
bits_to_bytes(bits)
```
