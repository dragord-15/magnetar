# 25 — مخطط Mermaid لعمل مترجم Magnetar

**حالة الدعم:** ✅ توثيق معماري (يعكس الحالة الحالية لـ `magc`)

هذا الملف يوضح مسار الترجمة في Magnetar بشكل بصري باستخدام Mermaid، مع ربط كل مرحلة بالملفات الفعلية في `src/`.

## 1) خط الأنابيب العام

```mermaid
flowchart TD
    A["Source .mg/.fc"] --> B["main.c: compile_file"]
    B --> C["Read file"]
    C --> D["preprocess_source<br/>use resolution + qualifier rewrite"]
    D --> E["Lexer_init / Lexer"]
    E --> F["Parser_parse<br/>AST"]
    F --> G{"Diagnostics / Parser errors?"}
    G -- yes --> X["Print errors<br/>GC_shutdown<br/>exit 1"]
    G -- no --> H["IRProgram_build"]
    H --> I["IRProgram_optimize"]
    I --> J["backend_get target_arch"]
    J --> K["backend-->create/set_entry/set_format"]
    K --> L["backend-->generate IR --> BackendResult"]
    L --> M{"object_mode?"}
    M -- yes --> N["backend-->write_object<br/>MAGO .o"]
    M -- no --> O["backend-->write_executable<br/>ELF/PE"]
    N --> P["Cleanup + exit"]
    O --> P
```

## 2) المعالجة المسبقة `use`

`preprocess_source()` تعمل قبل Lexer/Parser، وتقوم بتوسيع الوحدات نصياً.

```mermaid
flowchart TD
    U["Line starts with use ... ;"] --> R["Parse module name + optional 'as alias'"]
    R --> Q["resolve_and_load_use"]
    Q --> S{"Found file?"}
    S -- no --> E["stderr error<br/>preprocess_failed=1<br/>return empty"]
    S -- yes --> C{"Already loaded?<br/>MAX_LOADED_MODULES=64"}
    C -- yes --> Skip["Skip duplicate include"]
    C -- no --> Read["Read module file"]
    Read --> Rec["preprocess_source recursive<br/>depth limit 32"]
    Rec --> Ins["Insert module content into buffer"]
    R --> A{"alias exists?"}
    A -- yes --> AQ["add_qualifier alias<br/>rewrite alias.fn() --> fn()"]
    A -- no --> NOP["No qualifier"]
```

**مسارات البحث عن الوحدة** (مختصر):
- `source_dir/lib/<name>`
- `source_dir/<name>`
- `<name>` مباشرة
- `lib/<name>`
- `MAGNETAR_LIB/MAGNETAR_PATH/MAGNETAR_HOME`
- مسارات النظام (`/usr/lib/magnetar/lib`, `~/.magnetar/lib`, إلخ)

## 3) مراحل المترجم والملفات

```mermaid
flowchart LR
    subgraph Frontend
      LEX[src/lexer/lexer.c\ntoken.h] --> PAR[src/parser/parser.c\nast.h]
      PAR --> SEM[src/semantic/types.c\nsymbols.c]
    end
    subgraph Middle
      SEM --> IRB[src/ir/ir_builder.c\nir_helpers.c]
      IRB --> IRO[src/ir/ir_optimizer.c]
    end
    subgraph Backend
      IRO --> BIF[src/backend/backend.c\nbackend.h]
      BIF --> X64[src/backend/x86_64/codegen.c\nencoder.c]
      BIF --> ARM[src/backend/arm64/backend.c]
      BIF --> RV[src/backend/riscv/backend.c]
      X64 --> ELF[src/backend/elf_writer.c]
      X64 --> PE[src/backend/pe_writer.c]
    end
    subgraph Runtime/Utils
      GC[src/runtime/gc.c\nmemory.c]
      DIAG[src/utils/diagnostics.c]
      HM[src/utils/hashmap.c\narena.c]
    end
```

## 4) بنية البيانات الرئيسية

```mermaid
classDiagram
    class Token {
      +TokenType type
      +char* text
      +int length
      +int line
      +int column
    }
    class ASTNode {
      +ASTNodeType type
      +Token token
      +ASTNode** children
      +int child_count
      +char* string_value
      +int64_t int_value
      +float float_value
      +bool bool_value
      +char char_value
    }
    class IRProgram {
      +IRFunction** functions
      +int function_count
      +IRGlobal* globals
    }
    class Backend {
      +name/arch/format
      +create()
      +set_entry()
      +set_format()
      +generate()
      +write_executable()
      +write_object()
      +destroy()
    }
    class BackendResult {
      +uint8_t* code
      +size_t code_size
      +uint8_t* rodata
      +size_t rodata_size
      +exports[]
      +patches[]
    }

    Token <-- ASTNode
    ASTNode --> IRProgram : IRProgram_build
    IRProgram --> Backend : generate
    Backend --> BackendResult
```

## 5) CLI ومسار التنفيذ

```mermaid
flowchart TD
    CLI["magc args"] --> P{"Parse options"}
    P -->|--target| T["x86_64 / arm64 / riscv / windows"]
    P -->|--format| FMT["elf / pe"]
    P -->|--entry| ENT["entry function"]
    P -->|-c| OBJ["object_mode"]
    P -->|--watch| W["watch loop<br/>recompile on mtime"]
    P --> SRC["source.mg"]
    SRC --> C["compile_file"]
    W --> C
```

## 6) ملاحظات حالة حالية

- **x86_64 ELF**: المسار الأكثر نضجاً.
- **PE64**: كتابة/تنسيق مدعوم، لكن توليد الكود ما زال يعتمد Linux syscall/ABI في أماكن كثيرة (راجع حدود PE الحالية).
- **arm64/riscv**: backends موجودة وقيد الإكمال.
- **`src/codegen/` و`src/backup_c/`**: legacy/غير مبنية؛ `src/mag.c` رابط `./mag`.

## ملفات مرجعية

- `src/main.c` — CLI, preprocessing, compile pipeline.
- `src/lexer/lexer.c`, `src/lexer/token.h`
- `src/parser/parser.c`, `src/parser/ast.h`
- `src/ir/ir_builder.c`, `src/ir/ir_optimizer.c`, `src/ir/ir.c`
- `src/backend/backend.h`, `src/backend/backend.c`
- `src/backend/x86_64/codegen.c`, `src/backend/x86_64/encoder.c`
- `src/backend/elf_writer.c`, `src/backend/pe_writer.c`
