# 10 — مرجع سطر الأوامر (CLI)

> **TL;DR**
> - `./magc <source.mg> [خيارات]` — والخيارات: `-c`, `-o`, `--target`, `--format`, `--watch`, `--help`.
> - بلا `-o` ينتج `a.out`، ومع `-c` ينتج كائناً باسم مشتق من اسم المصدر.
> - الأهداف: `x86_64` مستقر، `arm64`/`riscv` قيد الإكمال، `baremetal` غير منفّذ.
> - صيغة ELF فقط؛ `asm` و `bin` مخطط لها.
> - كود خروج **المترجم**: `0` نجاح و `1` خطأ (ملف أو خيار أو ترجمة).

**حالة الدعم:** ✅ مستقر

## الاستخدام الأساسي

```
./magc <source.mg> [خيارات]
```

## الخيارات

| الخيار | الوصف |
|--------|-------|
| `-c` | الترجمة إلى ملف كائن (`.o`) بدلاً من تنفيذي |
| `-o <output>` | تحديد اسم/مسار الملف الناتج |
| `--target <arch>` | تحديد المعمارية المستهدفة |
| `--target=<arch>` | صيغة مختصرة للخيار نفسه |
| `--format <fmt>` | تحديد صيغة الخرج |
| `--format=<fmt>` | صيغة مختصرة |
| `--watch` , `-w` | وضع المراقبة الحيّ (Live Coding) |
| `--help` , `-h` | عرض رسالة المساعدة |

## الرسالة الافتراضية

```text
Magnetar Compiler v3.5
Usage: ./magc <source.mg> [-c] [-o <output>] [--target <arch>] [--format <fmt>] [--watch|-w]

Options:
  -c                Compile to object file (.o)
  -o <output>       Output file name
  --target <arch>   Target architecture: x86_64 (default), arm64, riscv
  --format <fmt>    Output format: elf (default)
  -w, --watch       Live compile and run on file changes
  -h, --help        Show this help message

Targets status:
  x86_64            Stable (ELF on Linux)
  arm64             Backend present - may need more testing
  riscv             Backend present - may need more testing
  baremetal         Not implemented yet

Note: Only ELF format is supported currently.
```

## أمثلة

```bash
# ترجمة أساسية (الناتج a.out)
./magc prog.mg

# تحديد اسم الخرج
./magc prog.mg -o prog

# ملف كائن
./magc prog.mg -c -o prog.o

# هدف arm64
./magc prog.mg --target arm64 -o prog_arm

# صيغة مختصرة
./magc prog.mg --target=riscv -o prog_rv

# الوضع الحيّ
./magc prog.mg -w
```

## اسم الخرج الافتراضي

| الحالة | الاسم الافتراضي |
|--------|------------------|
| ترجمة عادية بدون `-o` | `a.out` |
| مع `-c` بدون `-o` | يُشتق من اسم المصدر: `prog.mg` → `prog.o` |

## الأهداف المدعومة

| الهدف | الحالة |
|-------|--------|
| `x86_64` | **مستقر** — إخراج ELF على Linux |
| `arm64` | الواجهة موجودة — قد تحتاج اختباراً |
| `riscv` | الواجهة موجودة — قد تحتاج اختباراً |
| `baremetal` | **غير منفّذ** — سيرفع خطأ |

## صيغ الخرج

| الصيغة | الحالة |
|--------|--------|
| `elf` | مدعومة (افتراضي) |
| `asm` | مخطط لها |
| `bin` | مخطط لها |

## رسائل الأخطاء

```text
Error: Unknown option '--foo'
       Use --help for usage information.

Error: --target requires an argument (x86_64, arm64, riscv)

Error: --target=baremetal is not implemented yet.
       Baremetal target (no OS) is planned but not available in this version.
       Currently supported: x86_64, arm64, riscv (ELF)

Error: --format 'xyz' is not implemented yet.
       Currently supported output formats: elf
       Planned formats: asm (.s), bin (.bin)

Error: Cannot open 'nosuch.mg'

Error: No source file specified.
```

> **حالتان مختلفتان:**
>
> - `./magc` **بلا أي وسيط** ⇒ يطبع رسالة استخدام **مختصرة** (بدون سطر `-h, --help`،
>   وحالة الأهداف مكتوبة `Stable` / `In progress`) ويخرج بالرمز `1`.
> - `./magc --watch` (خيارات بلا ملف) ⇒ يطبع `Error: No source file specified.` ويخرج بالرمز `1`.

## كود الخروج

| الكود | المعنى |
|-------|--------|
| `0` | نجاح |
| `1` | خطأ (ملف، خيارات، ترجمة) |

## وضع المراقبة الحيّ (`--watch`)

```bash
./magc prog.mg --watch
```

- يراقب تغيّر وقت تعديل الملف كل ثانية.
- يعيد الترجمة والتشغيل تلقائياً عند الحفظ.
- يوقف النسخة القديمة قبل تشغيل الجديدة.
- الخروج بـ `Ctrl+C`.

---
**السابق:** [09_builtins.md](09_builtins.md) |
**التالي:** [11_compiler_architecture.md](11_compiler_architecture.md) |
**الفهرس:** [README.md](README.md)
