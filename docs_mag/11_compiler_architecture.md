# 11 — بنية المترجم من الداخل

> **TL;DR**
> - المسار: `preprocess_source` ← Lexer ← Parser ← Semantic/Symbols ← IR ← Backend ← ELF.
> - لكل مرحلة ملفات واضحة في `src/` — ابدأ من `src/main.c` و `src/parser/parser.c`.
> - `preprocess_source()` هو من يوسّع `use` نصّياً **قبل** أي تحليل لغوي.
> - الـ backend الناضج هو `src/backend/x86_64/` (codegen + encoder)، و`src/backend/elf_writer.c` يبني الملف التنفيذي.
> - `src/codegen/` و `src/backup_c/` مهملان (legacy) ولا يُبنيان؛ أمّا `src/mag.c`
>   فهو مصدر الرابط الذي ينتج `./mag`.

**حالة الدعم:** ✅ مستقر

هذا الفصل يشرح كيف يعمل المترجم من المصدر إلى الملف التنفيذي، مع الإشارة للملفات في `src/`.

## خط الأنابيب (Pipeline)

```
                  preprocess_source()          Lexer           Parser
  source.mg  ───────────────────────▶  tokens  ───▶  AST  ───▶  AST
                                                               │
                                                               ▼
                 IRProgram_build()        Semantic + Symbols
       IR  ◀─────────────────────  AST  ◀──────────────────────
        │
        ▼
    IRProgram_optimize()
        │
        ▼
    backend->generate()  ──▶  BackendResult (code + rodata + exports)
        │
        ▼
    backend->write_executable()  ──▶  ELF file
```

## المراحل والملفات

### 1) المعالجة المسبقة (Preprocessing)

**الملف:** `src/main.c` → `preprocess_source()`

- يعالج أسطر `use "module";` ويُدرج محتوى الوحدات نصّياً.
- يمنع التضمين المكرّر (حتى **64 وحدة** محمّلة، وعمق تداخل حتى **32**).
- يبحث عن الوحدات في `lib/`، مسارات النظام، ومتغيّرات البيئة.

### 2) التحليل اللغوي (Lexing)

**الملفات:** `src/lexer/lexer.c`, `src/lexer/token.h`

- يحوّل النص إلى رموز (`Token`).
- يعرّف كل الكلمات المفتاحية (أنواع، تحكم، دوال، عمليات).

`Token` يحتوي على:

```c
typedef struct {
    TokenType type;
    char* text;
    int length;
    int line;
    int column;
} Token;
```

### 3) التحليل النحوي (Parsing)

**الملفات:** `src/parser/parser.c`, `src/parser/ast.h`

- يبني شجرة **AST** من الرموز.
- يستخدم تحليلاً هبوطياً تعاودياً (recursive descent) مع مستويات أسبقية للعمليات:
  `parse_multiplicative` → `parse_additive` → `parse_shift` → `parse_bitwise_*` →
  `parse_comparison` → `parse_logical_*` → `parse_ternary`.
- أنواع العقد (`ASTNodeType`) تغطي: التصريحات، الجمل، التعبيرات، الفئات، الوحدات، ... إلخ.

المكوّن الأساسي:

```c
typedef struct ASTNode {
    ASTNodeType type;
    Token token;
    struct ASTNode** children;
    int child_count;
    int child_capacity;
    char* string_value;
    int64_t int_value;
    float float_value;
    bool bool_value;
    char char_value;
} ASTNode;
```

### 4) التحليل الدلالي والرموز (Semantic + Symbols)

**الملفات:** `src/semantic/types.c`, `src/semantic/symbols.c`

- جمع الرموز (المتغيرات، الدوال، الأنواع).
- فحص الأنواع الأساسي.
- كشف الرموز غير المعرّفة.

### 5) التمثيل الوسيط (IR)

**الملفات:** `src/ir/ir.c`, `src/ir/ir_builder.c`, `src/ir/ir_helpers.c`, `src/ir/ir_optimizer.c`

- `IRProgram_build(ast)` يبني برنامج IR من الشجرة.
- `IRProgram_optimize(ir)` يطبّق تحسينات (مثل حذف الدوال غير القابلة للوصول).
- تعليمة IR تحمل إشارة لعقدة AST (`IR_AST_NODE`) في المرحلة الحالية.

### 6) التوليد الخلفي (Backend / Codegen)

**الملفات:** `src/backend/`

```
backend/
├── backend.c / backend.h      واجهة موحّدة + سجل الـ backends
├── elf_writer.c / .h          كتابة ملفات ELF
├── x86_64/
│   ├── backend.c              تعريف backend x86_64
│   ├── codegen.c              توليد تعليمات x86_64 (AsmGen)
│   ├── encoder.c / .h         ترميز التعليمات إلى بايتات
│   └── codegen.h
├── arm64/backend.c            (قيد الإكمال)
└── riscv/backend.c            (قيد الإكمال)
```

الواجهة الموحّدة لكل backend:

```c
typedef struct {
    ...
    bool (*write_executable)(const char* path, BackendResult* result);
    bool (*write_object)(const char* path, BackendResult* result);
    ...
} Backend;
```

- **x86_64** هو الناضج: يولّد ماشين-كود مباشرة ثم يكتبه كملف ELF.
- الملف التنفيذي **مستقل** (static) ويعتمد على syscalls مباشرة.
- `write_object` ينتج ملفاً بصيغة داخلية بترويسة `MAGO`.

### 7) كتابة الملف التنفيذي

**الملفات:** `src/backend/elf_writer.c`

- يبني رؤوس ELF 64-bit.
- يضع الـ text و rodata في أقسام مناسبة.
- نقطة الدخول تُحسب لتشغيل `main` مباشرة.

## الأدوات المساندة

| الملف | الوظيفة |
|-------|---------|
| `src/utils/hashmap.c` | خريطة تجزئة (Hash Map) |
| `src/utils/arena.c` | مخصّص ذاكرة إقليمي (Arena) |
| `src/utils/diagnostics.c` | تشخيص الأخطاء وعرضها |
| `src/utils/slice.h` | نوع شريحة (slice) |
| `src/utils/job_scheduler.c` | مجدول مهام (للتوازي) |
| `src/runtime/gc.c` | جامع قمامة داخلي للمترجم |
| `src/runtime/memory.c` | تخصيص ذاكرة منخفض المستوى |

## أنواع المخرجات

```
BackendResult {
    code / code_size         → قسم التعليمات
    rodata / rodata_size     → البيانات الثابتة (النصوص)
    exports[]                → الدوال المصدَّرة
    patches[]                → ترقيعات (للوحدات)
}
```

## المجلدات المهملة

هذه لا تُبنى (legacy):

- `src/codegen/` — نسخة قديمة من التوليد (لا تُبنى).
- `src/backup_c/` — نسخ احتياطية (لا تُبنى).
- `src/mag.c` — ليس legacy: هو **مصدر الرابط** الذي يُبنى وحده لينتج `./mag`،
  ويُستثنى من بناء `magc` فقط.

## دورة حياة الترجمة في `compile_file()`

1. قراءة الملف.
2. `preprocess_source` (معالجة `use`).
3. `GC_init` + `diag_init`.
4. `Lexer_init` → `Parser_parse` → AST.
5. فحص الأخطاء.
6. `IRProgram_build` + `IRProgram_optimize`.
7. `backend_get(target_arch)`.
8. `backend->generate` → `BackendResult`.
9. `backend->write_executable` أو `write_object`.
10. تنظيف: `backend_result_free`, `backend->destroy`, `IRProgram_free`, `ASTNode_free`, `GC_shutdown`.

---
**السابق:** [10_cli_reference.md](10_cli_reference.md) |
**التالي:** [12_notes_and_limitations.md](12_notes_and_limitations.md) |
**الفهرس:** [README.md](README.md)
