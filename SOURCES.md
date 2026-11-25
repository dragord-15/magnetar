# سجل المصادر / Source manifest

هذا الملف يوضح محتويات حزمة المصدر `magnetar-v3.5`. الأرقام تقريبية وقد تتغير مع التحديثات.

## C sources used by `Makefile`

```text
src/main.c
src/lexer/lexer.c
src/parser/parser.c
src/semantic/symbols.c
src/semantic/types.c
src/ir/ir.c
src/ir/ir_builder.c
src/ir/ir_optimizer.c
src/utils/arena.c
src/utils/hashmap.c
src/utils/job_scheduler.c
src/utils/diagnostics.c
src/runtime/gc.c
src/runtime/memory.c
src/backend/backend.c
src/backend/elf_writer.c
src/backend/pe_writer.c
src/backend/x86_64/backend.c
src/backend/x86_64/codegen.c
src/backend/x86_64/encoder.c
src/backend/arm64/backend.c
src/backend/riscv/backend.c
```

## C headers

```text
src/lexer/lexer.h        src/lexer/token.h
src/parser/ast.h         src/parser/parser.h        src/parser/struct_registry.h
src/semantic/symbols.h   src/semantic/types.h
src/ir/ir.h
src/utils/arena.h        src/utils/hashmap.h        src/utils/job_scheduler.h
src/utils/diagnostics.h  src/utils/slice.h
src/runtime/gc.h         src/runtime/memory.h
src/backend/backend.h    src/backend/elf_writer.h   src/backend/pe_writer.h
src/backend/x86_64/codegen.h  src/backend/x86_64/encoder.h
src/codegen/asm_gen.h    src/codegen/codegen_x64.h  src/codegen/elf_writer.h src/codegen/opcode.h
src/backup_c/gfx.h
```

## Magnetar sources and data

| Directory | Count | Purpose |
|-----------|------:|---------|
| `lib/` | 47 `.mg` files | Standard library modules |
| `examples/` | 54 `.mg` files | Runnable examples and demos |
| `tests/cases/` | 64 `.mg` files | Positive regression cases |
| `tests/compile_fail/` | - | Expected compile failures |
| `tests/expected/` | - | Expected stdout files |
| `docs_mag/` | 36 `.md` files | Arabic documentation and references |
| `gui/` | - | Higher-level GUI framework |
| `apps/` | - | Extra tools and experiments |

## Notable source files

- `src/backend/x86_64/codegen.c` — native code generator and inline assembler.
- `src/backend/elf_writer.c` — ELF program header and segment writer.
- `src/ir/ir_optimizer.c` — IR optimizations.
- `src/runtime/gc.c`, `src/runtime/memory.c` — runtime allocator and GC.
- `lib/gui.mg` — high-level X11 GUI library.
- `examples/tiny_gui_1474.mg` — 1,474-byte X11 window demo.
- `tests/run.sh` — regression test driver.
- `Makefile` — build rules.

## Excluded from this release bundle

- `*.o` object files
- built binaries `mag` and `magc`
- local photos and sample media in `local_photos/`
- editor/IDE settings in `.vscode/`
