#!/usr/bin/env bash
# CLI format/alias/no-silent-ignore regression checks.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAGC="${MAGC:-$ROOT/magc}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

printf 'fn main() { print("ok\\n"); }\n' > "$WORK/t.mg"
fail=0

check() {
  local desc="$1"; shift
  if "$@"; then echo "PASS  $desc"; else echo "FAIL  $desc"; fail=$((fail+1)); fi
}

err_contains() {
  local needle="$1" text="$2"
  grep -qF -- "$needle" <<<"$text"
}

strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

# x86_64 ELF header remains the reference output.
"$MAGC" "$WORK/t.mg" --target x86_64 -o "$WORK/x86.elf" >/dev/null 2>&1
if command -v readelf >/dev/null 2>&1; then
  check "x86_64 ELF machine is EM_X86_64" grep -q 'Advanced Micro Devices X86-64' <(readelf -h "$WORK/x86.elf")
else
  check "x86_64 ELF compiles" test -x "$WORK/x86.elf"
fi

# aarch64 alias must select the ARM64 backend.
"$MAGC" "$WORK/t.mg" --target aarch64 -o "$WORK/aarch64" >/dev/null 2>&1
if command -v readelf >/dev/null 2>&1; then
  check "aarch64 alias emits EM_AARCH64" grep -q 'AArch64' <(readelf -h "$WORK/aarch64")
else
  check "aarch64 alias compiles" test -x "$WORK/aarch64"
fi

# asm listings for both backends.
"$MAGC" "$WORK/t.mg" --target arm64 --format asm -o "$WORK/arm.s" >/dev/null 2>&1
check "arm64 asm listing has .arch" grep -q '\.arch armv8-a' "$WORK/arm.s"
check "arm64 asm listing has .inst" grep -q '\.inst 0x' "$WORK/arm.s"
"$MAGC" "$WORK/t.mg" --target x86_64 --format asm -o "$WORK/x86.s" >/dev/null 2>&1
check "x86_64 asm listing has .byte" grep -q '\.byte 0x' "$WORK/x86.s"
check "x86_64 asm listing has no .inst" bash -c "! grep -q '\.inst' '$WORK/x86.s'"
"$MAGC" "$WORK/t.mg" --format asm --target windows -o "$WORK/order.s" >/dev/null 2>&1
check "explicit --format wins over --target windows alias" grep -q '\.section .text' "$WORK/order.s"

# PE64 generation stays on the x86_64 backend.
"$MAGC" "$WORK/t.mg" --target windows -o "$WORK/t.exe" >/dev/null 2>&1
check "PE64 has MZ magic" bash -c "[[ \"\$(head -c2 '$WORK/t.exe')\" == MZ ]]"
check "PE64 has PE signature" bash -c "od -An -tx1 -N132 '$WORK/t.exe' | tr -d ' \n' | grep -q 50450000"

# flat binary has no ELF/PE header.
"$MAGC" "$WORK/t.mg" --target arm64 --format bin -o "$WORK/arm.bin" >/dev/null 2>&1
check "arm64 flat binary is non-empty" test -s "$WORK/arm.bin"
check "arm64 flat binary has no ELF magic" bash -c "head -c4 '$WORK/arm.bin' | grep -q ELF && exit 1 || exit 0"
"$MAGC" "$WORK/t.mg" --target x86_64 --format bin -o "$WORK/x86.bin" >/dev/null 2>&1
check "x86_64 flat binary is non-empty" test -s "$WORK/x86.bin"

# unsupported combinations must fail loudly rather than be ignored.
err="$("$MAGC" "$WORK/t.mg" --target arm64 --format pe -o "$WORK/bad" 2>&1)"
check "PE64 on ARM64 is rejected" err_contains 'PE64 output is only supported with --target x86_64' "$err"
err="$("$MAGC" "$WORK/t.mg" -c --format bin -o "$WORK/bad.o" 2>&1)"
check "asm/bin cannot be combined with -c" err_contains 'cannot be combined with -c' "$err"
err="$("$MAGC" "$WORK/t.mg" --target baremetal -o "$WORK/bad" 2>&1)"
check "baremetal fails explicitly" err_contains 'baremetal is not implemented yet' "$err"
err="$("$MAGC" "$WORK/t.mg" --target riscv -o "$WORK/bad" 2>&1)"
check "riscv fails fast" err_contains 'RISC-V backend not yet implemented' "$err"
err="$("$MAGC" "$WORK/t.mg" --format xyz -o "$WORK/bad" 2>&1)"
check "unknown format fails explicitly" err_contains "--format 'xyz'" "$err"

if (( fail )); then
  echo "FAIL: $fail CLI format checks failed"
  exit 1
fi
echo "PASS: all CLI format/alias checks succeeded"
