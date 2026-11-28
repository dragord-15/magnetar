# 10 — مرجع سطر الأوامر (CLI)

> **TL;DR**
> - `./magc <source.mg> [خيارات]` — والخيارات: `-c`, `-o`, `--target`, `--format`, `--watch`, `--help`.
> - بلا `-o` ينتج `a.out`، ومع `-c` ينتج كائناً باسم مشتق من اسم المصدر.
> - الأهداف: `x86_64` مستقر، `arm64`/`aarch64` يعملان، `riscv` مخطط له، `baremetal` غير منفّذ.
> - الصيغ: `elf` (افتراضي)، `pe` (x86_64 فقط)، `asm` (قائمة تجميع)، `bin` (بايتات خام).
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
| `--bounds-check` | رفض الفهارس الحرفية خارج حدود المصفوفات `fixed` وقت الترجمة (افتراضياً متوقف) |
| `--watch` , `-w` | وضع المراقبة الحيّ (Live Coding) |
| `--help` , `-h` | عرض رسالة المساعدة |

## الرسالة الافتراضية

```text
Magnetar Compiler v3.5
Usage: ./magc <source.mg> [-c] [-o <output>] [--target <arch>] [--format <fmt>] [--entry <name>] [--watch|-w]

Options:
  -c                Compile to object file (.o)
  -o <output>       Output file name
  --target <arch>   Target: x86_64, arm64/aarch64 (native default on ARM), riscv, windows/win64
  --format <fmt>    Output format: elf (default), pe (x86_64 only), asm, bin
  --bounds-check    Reject literal indices outside fixed-array bounds at compile time
  -w, --watch       Live compile and run on file changes
  -h, --help        Show this help message

Targets status:
  x86_64            Stable (ELF64 Linux, PE64 Windows)
  arm64/aarch64     Working standalone ELF64 AArch64 (native on ARM)
  riscv             Planned - not implemented

Formats: elf (default), pe/windows/exe (x86_64 only), asm (text listing), bin (flat raw bytes).
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
| `x86_64` | **مستقر** — ELF64 على Linux وPE64 على Windows |
| `arm64` / `aarch64` | **يعمل** — ELF64 مستقل وربط كائنات عبر `mag` |
| `windows` / `win64` / `x86_64-windows` | **مستقر** — PE64 عبر خلفية x86_64 |
| `riscv` | **مخطط له** — يفشل فوراً برسالة واضحة |
| `baremetal` | **غير منفّذ** — سيرفع خطأ |

## صيغ الخرج

| الصيغة | الحالة |
|--------|--------|
| `elf` | مدعومة (افتراضي) — لكل الأهداف المنفّذة |
| `pe` / `windows` / `exe` | مدعومة مع `x86_64` فقط |
| `asm` | مدعومة — قائمة تجميع نصية تعيد إنتاج البايتات تماماً |
| `bin` | مدعومة — بايتات خام بلا رأس ELF/PE |

## رسائل الأخطاء

```text
Error: Unknown option '--foo'
       Use --help for usage information.

Error: --target requires an argument (x86_64, arm64, riscv)

Error: --target=baremetal is not implemented yet.
       Baremetal target (no OS) is planned but not available in this version.
       Currently supported: x86_64, arm64/aarch64 (ELF); riscv is planned.

Error: PE64 output is only supported with --target x86_64 (got 'arm64').

Error: --format requires an argument (elf, pe, asm, bin)

Error: --format 'xyz' is not implemented yet.
       Supported: elf, pe (x86_64 only), asm, bin

Error: --format bin cannot be combined with -c (object files are always ELF/MAGO).

Linker Error: object 'lib.o' was built for arm64 but --target x86_64 was selected.

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
