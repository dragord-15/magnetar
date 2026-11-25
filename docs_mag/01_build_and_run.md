# 01 — البناء والتشغيل

> **TL;DR**
> - ابنِ المترجم بأمر واحد: `make` من جذر المشروع (Linux 64-bit + GCC + make).
> - ترجم وشغّل بأمرين: `./magc prog.mg -o prog` ثم `./prog`.
> - بلا `-o` ينتج `a.out`، ومع `-c` ينتج ملف كائن `.o` (يولّده `./magc` ويربطه `./mag`).
> - `--watch` يعيد الترجمة والتشغيل عند كل حفظ؛ للخروج `Ctrl+C`.
> - عند مواجهة خطأ، راجع [حل المشكلات الشائعة](#حل-المشكلات-الشائعة) في نهاية الفصل.

**حالة الدعم:** ✅ مستقر

## المتطلبات

- نظام **Linux** (64-bit).
- مترجم **GCC** (أو clang).
- أداة `make`.
- معمارية **x86_64** (الهدف الناضج حالياً).

## البناء باستخدام Makefile

من جذر المشروع:

```bash
make
```

هذا يُنتج الملفين التنفيذيين `./magc` (المترجم: من `.mg` إلى ELF) و `./mag`
(ال الرابط: من ملفات الكائنات `.o` إلى ELF).

### أوامر Makefile المتاحة

| الأمر | الوظيفة |
|-------|---------|
| `make` | بناء `./magc` و `./mag` |
| `make clean` | حذف ملفات البناء (الكائنات `.o` والتنفيذيَين) |
| `make install` | تثبيت المترجم في النظام |
| `make uninstall` | إزالة ما ثُبِّت |
| `make info` | معلومات عن المشروع |
| `make help` | عرض قائمة الأهداف |

> **لا يوجد هدف `make examples`**، ولا وصفة فعّالة لـ `make test`: الأمر `make test`
> يطبع `Nothing to be done for 'test'` ولا يفعل شيئاً — رغم أن `make help` يَعِد به.
> للتحقق من الأمثلة يدوياً راجع
> [12_notes_and_limitations.md](12_notes_and_limitations.md#كيف-تتحقق-من-الاستقرار-بنفسك).

### البناء اليدوي (بدون Makefile)

```bash
gcc -O2 -o magc $(find src -name '*.c' \
    -not -name 'mag.c' \
    -not -path '*/codegen/*' \
    -not -path '*/backup_c/*') -lm
```

> **ملاحظة:** المجلدان `src/codegen/` و `src/backup_c/` مهملان (legacy) ولا يُبنيان.
> أمّا `src/mag.c` فهو **مصدر الرابط** (يُبنى وحده لينتج `./mag`)، لذا يُستثنى من
> بناء المترجم `magc` — وإلا تكرّر تعريف `main`.

## الترجمة والتشغيل

### الطريقة الأساسية

```bash
./magc hello.mg -o hello
./hello
```

> **ملاحظة:** لا يوجد ملف `examples/01_hello.mg` في المستودع؛ الأمثلة الموجودة
> في `examples/` تبدأ بأسماء أخرى (`test_helpers.mg`, `gui_about.mg`, ...).
> أنشئ `hello.mg` كما في [المثال الكامل](#مثال-كامل-خطوة-بخطوة) أدناه.

إن لم تحدد `-o`، فسيُنتج ملف باسم `a.out` في المجلد الحالي:

```bash
./magc hello.mg
./a.out
```

### الترجمة إلى ملف كائن (object)

```bash
./magc hello.mg -c -o hello.o
```

يُنتج ملف كائن بصيغة Magnetar الداخلية (ترويسة `MAGO`) وليس ELF عادي.

### وضع المراقبة الحيّ (Live Coding)

```bash
./magc hello.mg --watch
```

- يعيد الترجمة تلقائياً عند كل حفظ للملف.
- يشغّل البرنامج الجديد فوراً بعد كل ترجمة ناجحة.
- للخروج: `Ctrl+C`.

## مثال كامل خطوة بخطوة

```bash
# 1) أنشئ ملف hello.mg
cat > hello.mg <<'EOF'
fn main() {
    print("Hello, Magnetar!\n");
}
EOF

# 2) ترجمه
./magc hello.mg -o hello

# 3) شغّله
./hello
# الناتج:
# Hello, Magnetar!
```

## الترجمة لأهداف أخرى

```bash
# x86_64 (الافتراضي والناضج)
./magc prog.mg --target x86_64 -o prog

# arm64 (قيد الإكمال)
./magc prog.mg --target arm64 -o prog_arm

# riscv (قيد الإكمال)
./magc prog.mg --target riscv -o prog_rv
```

للمرجع الكامل لخيارات سطر الأوامر: [10_cli_reference.md](10_cli_reference.md).

## حل المشكلات الشائعة

| المشكلة | السبب المحتمل | الحل |
|---------|---------------|------|
| `Cannot open 'file.mg'` | المسار خطأ | تحقّق من مسار الملف |
| `Undefined symbol 'x'` | الرمز غير معرَّف: دالة مدمجة بلا تصريح، أو اسم خطأ، أو method نُظِر بـ `this` | أضف `extern fn` للدالة المدمجة، أو صحّح الاسم، أو استدعِ الـ method بـ `this.<اسم>` — **ترتيب التعريف لا يهم** |
| `Could not find library module 'x'` | الوحدة غير موجودة في `lib/` | تأكّد من وجود `lib/x.mg` ومن عمل المترجم من جذر المشروع |
| `Backend 'x' not found` | اسم هدف غير معروف | استخدم `x86_64` أو `arm64` أو `riscv` |
| `Maximum module nesting depth (32) exceeded` | سلسلة `use` أعمق من 32 | بسّط سلسلة الاستيراد |
| ناتج فارغ أو غريب | `print` لا يضيف سطراً جديداً | أضف `"\n"` بنفسك |
| `Segmentation fault` (كود خروج `139`) | خطأ ذاكرة | راجع [13_debugging.md](13_debugging.md#ماذا-تفعل-حين-ينهار-البرنامج) |

---
**السابق:** [00_overview.md](00_overview.md) |
**التالي:** [02_basics.md](02_basics.md) |
**الفهرس:** [README.md](README.md)
