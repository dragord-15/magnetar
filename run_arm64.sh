#!/usr/bin/env bash
# Compile a Magnetar source file to a fresh standalone ARM64 ELF and run it.
# Usage: bash run_arm64.sh <source.mg> [args...]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TMP="/data/data/com.termux/files/usr/tmp/opencode"
mkdir -p "$TMP"

if [[ $# -lt 1 ]]; then
    echo "Usage: bash run_arm64.sh <source.mg>" >&2
    exit 2
fi

SRC="$1"
shift
if [[ ! -f "$SRC" ]]; then
    echo "Source not found: $SRC" >&2
    exit 2
fi
if [[ ! -x "$ROOT/magc" ]]; then
    echo "magc not built. Run: cd $ROOT && make" >&2
    exit 1
fi

NAME="$(basename "$SRC" .mg)"
OUT="$TMP/${NAME}_arm64"

# Always start from a fresh file: a stale/partial binary is the usual cause of
# an unexplained segmentation fault after recompiling.
rm -f "$OUT"
echo "[run_arm64] Compiling $SRC -> $OUT"
"$ROOT/magc" "$SRC" --target arm64 -o "$OUT" >/dev/null

MACHINE="$(readelf -h "$OUT" | awk -F: '/Machine:/ {gsub(/^ +/, "", $2); print $2}')"
if [[ "$MACHINE" != *AArch64* ]]; then
    echo "[run_arm64] FAIL: expected AArch64, got: $MACHINE" >&2
    exit 1
fi

echo "[run_arm64] ELF OK: $MACHINE"
set +e
"$OUT" "$@"
RC=$?
set -e
echo "[run_arm64] exit code: $RC"
exit "$RC"
