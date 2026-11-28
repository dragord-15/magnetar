#!/usr/bin/env bash
# Compile tests/arm64_smoke.mg to a native AArch64 ELF, check its header,
# run it, and compare the output with the expected text.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="/data/data/com.termux/files/usr/tmp/opencode"
mkdir -p "$TMP"

SRC="$ROOT/tests/arm64_smoke.mg"
EXE="$TMP/arm64_smoke"
OUT="$TMP/arm64_smoke.out"
EXP="$ROOT/tests/arm64_smoke.expected"

if [[ ! -x "$ROOT/magc" ]]; then
    echo "magc not found; run 'make' first." >&2
    exit 1
fi

"$ROOT/magc" "$SRC" -o "$EXE" >/dev/null

machine="$(readelf -h "$EXE" | awk -F: '/Machine:/ {gsub(/^ +/, "", $2); print $2}')"
if [[ "$machine" != *AArch64* ]]; then
    echo "FAIL: expected AArch64 ELF, got: $machine" >&2
    exit 1
fi

"$EXE" > "$OUT"
if ! diff -u "$EXP" "$OUT"; then
    echo "FAIL: output mismatch" >&2
    exit 1
fi

echo "PASS: standalone ARM64 ELF built and ran correctly"
