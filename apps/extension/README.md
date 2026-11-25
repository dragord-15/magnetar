# Magnetar Language Support

Official Antigravity / VS Code language support extension for **Magnetar** (`.mg`, `.fc`).

<p align="center">
  <img src="logo.svg" alt="Magnetar Logo" width="160" height="160">
</p>

## Features

- **Full Syntax Highlighting**:
  - All keywords: `fn`, `let`, `struct`, `class`, `enum`, `union`, `use`, `match`, `switch`, `for`, `while`, `do`, `break`, `continue`, `return`, `goto`, `defer`, etc.
  - Built-in types: `int`, `float`, `bool`, `char`, `string`, `void`, `auto`, `any`, `byte`, `word`, `dword`, `qword`, `half`.
  - Generic / Container types: `fixed<T, N>`, `dyn<T>`, `alloc<T>`, `slice`, `array`, `tuple`, `map`, `set`, `stream`, `simd`, `atom`, `range`.
  - Memory management & pointers: `alloc`, `free`, `sizeof`, `typeof`, `cast`, `move`, `copy`, `borrow`, `clone`, `new`, `delete`, `ptr`, `ref`, `own`, `raw`.
  - Builtin functions & Linux syscalls: `print`, `print_str`, `len`, `sqrt`, `sin`, `cos`, `tan`, `pow`, `rand_int`, `sleep_ms`, `get_timestamp`, `exit`, `sys_*`, `fs_*`, `net_*`, `os_*`.
  - Number formats: decimal, hexadecimal (`0x...`), binary (`0b...`), octal (`0o...`), float/scientific, and digit separators (`1_000_000`).
  - Comments: Single-line (`//`) and multi-line (`/* ... */`).
- **Language Configuration**:
  - Auto-closing pairs for brackets, quotes, and block comments.
  - Code folding markers.
  - Smart indentation rules.
- **Snippets**:
  - `main`, `fn`, `extern`, `let`, `lett`, `struct`, `enum`, `if`, `ifelse`, `for`, `forin`, `while`, `switch`, `match`, `print`, `println`, `alloc`, `fixed`, `use`, `sysopen`, `sysread`, `syswrite`, `sysclose`.
- **Supported File Extensions**:
  - `.mg` (Magnetar source file)
  - `.fc` (Falcon source file)
