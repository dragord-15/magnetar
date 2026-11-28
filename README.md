# Magnetar / Magñtar (النسر) v3.5

**Magnetar** (يُختصر `Mag`) هي لغة برمجة مترجَمة منخفضة/متوسطة المستوى تُنشئ ملفات تنفيذية
**ELF x86_64** تعمل مباشرة على Linux دون libc ودون dynamic loader.

This repository is the source distribution of the Magnetar compiler, standard library,
documentation, tests, examples, and small desktop/GUI experiments.

---

## سريع البدء / Quick start

```bash
make
./magc hello.mg -o hello
./hello
# Hello, Magnetar!
```

Run the regression suite:

```bash
./tests/run.sh
```

The compiler binary is `./magc` and the standalone object linker is `./mag`.

---

## أبرز المزايا / Highlights

- Native x86_64 code generator and ELF writer.
- Freestanding executables: no libc, no dynamic loader, one `PT_LOAD` segment.
- Small runtime footprint; a minimal `main()` executable is about **198 bytes**.
- Inline `asm(...)` block with labels, jumps, memory operands, and raw syscalls.
- Stdlib modules for files, images, bytes, HTTP/URL, JSON, GUI, plotting, and more.
- Arabic-first documentation with 26 numbered reference documents.
- A verified X11 GUI demo that produces a **1,474-byte** ELF:
  `examples/tiny_gui_1474.mg`.

---

## محتويات الحزمة / Bundle layout

| Path | Contents |
|------|----------|
| `src/` | Compiler and linker C sources: lexer, parser, semantic, IR, utils, runtime, backends |
| `lib/` | Magnetar standard library modules (`.mg`) |
| `docs_mag/` | Full Arabic documentation, API references, architecture notes, and performance diagnosis |
| `tests/` | Regression cases, expected outputs, and `run.sh` |
| `examples/` | Example programs, including the 1.5 KB GUI demo |
| `gui/` | Higher-level GUI framework and desktop widgets |
| `apps/` | Extra tools and experiments written in Magnetar |
| `Makefile` | Build rules for `magc` and `mag` |
| `LICENSE` | MIT License |
| `COPYRIGHT.md` | Copyright and usage notice |
| `USAGE.md` | Build, compile, run, and packaging instructions |
| `SOURCES.md` | Source manifest |

---

## بنية المترجم / Compiler pipeline

```text
source.mg
  -> lexer
  -> parser
  -> semantic analysis
  -> IR + optimizer
  -> x86_64 backend / inline asm
  -> ELF writer
  -> executable
```

Detailed notes: [docs_mag/11_compiler_architecture.md](docs_mag/11_compiler_architecture.md) and
[docs_mag/25_compiler_mermaid.md](docs_mag/25_compiler_mermaid.md).

---

## التوثيق / Documentation

Start at [docs_mag/README.md](docs_mag/README.md). Useful entry points:

- [00_overview.md](docs_mag/00_overview.md): language philosophy
- [01_build_and_run.md](docs_mag/01_build_and_run.md): build and run
- [02_basics.md](docs_mag/02_basics.md): variables and types
- [09_builtins.md](docs_mag/09_builtins.md): built-in functions
- [10_cli_reference.md](docs_mag/10_cli_reference.md): CLI reference
- [12_notes_and_limitations.md](docs_mag/12_notes_and_limitations.md): current limits
- [26_performance_diagnosis.md](docs_mag/26_performance_diagnosis.md): size and speed work

---

## حالة الدعم / Platform status

- **x86_64 Linux ELF64** — stable reference backend; also the default on non-ARM hosts.
- **Windows x64 PE64** — stable; use `--target windows` / `win64` / `x86_64-windows`.
- **ARM64/AArch64 Linux ELF64** — working standalone codegen and end-to-end `mag` object linking;
  native default on ARM hosts. `--target arm64` and `--target aarch64` are both accepted.
- **RISC-V** — planned; the backend currently fails fast with a clear "not yet implemented" error.
- **Baremetal** — not implemented and explicitly rejected.
- Output formats: `elf` (default), `pe` (x86_64 only), `asm` (assembly listing), `bin` (flat raw bytes).
- Some built-ins such as `audio_play`, `sql_*`, `crypto_*`, and `regex_match` are placeholders;
  see [09_builtins.md](docs_mag/09_builtins.md).

---

## الترخيص / License

Magnetar is released under the **MIT License**. See [LICENSE](LICENSE) and
[COPYRIGHT.md](COPYRIGHT.md).
