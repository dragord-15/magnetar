#!/usr/bin/env bash
# Verify that x86_64 ELF/MAGO/PE64 bytes are unchanged from HEAD.
# Skips cleanly outside a git checkout.  The baseline compiler is built from a
# temporary git archive; this never modifies the working tree.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAGC="${MAGC:-$ROOT/magc}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if ! git -C "$ROOT" rev-parse --verify HEAD >/dev/null 2>&1; then
  echo "SKIP: x86 byte-for-byte baseline check requires a git checkout"
  exit 0
fi

mkdir -p "$WORK/base" "$WORK/cur"
if ! git -C "$ROOT" archive HEAD | tar -x -C "$WORK/base"; then
  echo "FAIL: could not extract HEAD baseline"
  exit 1
fi
build_log="$WORK/build.log"
if ! make -C "$WORK/base" >"$build_log" 2>&1; then
  echo "FAIL: baseline compiler did not build"
  tail -20 "$build_log"
  exit 1
fi

pass=0; fail=0
for src in "$ROOT"/tests/cases/*.mg; do
  name="$(basename "$src" .mg)"
  rel="tests/cases/$name.mg"
  if ! git -C "$ROOT" cat-file -e "HEAD:$rel" 2>/dev/null; then
    continue  # new test source: no baseline to compare
  fi
  if ! "$WORK/base/magc" "$src" --target x86_64 -o "$WORK/cur/$name.base" >/dev/null 2>&1; then
    echo "FAIL  $name — baseline compile failed"
    fail=$((fail+1)); continue
  fi
  if ! "$MAGC" "$src" --target x86_64 -o "$WORK/cur/$name.cur" >/dev/null 2>&1; then
    echo "FAIL  $name — current compile failed"
    fail=$((fail+1)); continue
  fi
  if ! cmp -s "$WORK/cur/$name.base" "$WORK/cur/$name.cur"; then
    echo "FAIL  $name — x86_64 ELF bytes differ from HEAD"
    fail=$((fail+1)); continue
  fi
  pass=$((pass+1))
done

printf 'fn main(){print(1); print("\\n");}\n' > "$WORK/pe.mg"
"$WORK/base/magc" "$WORK/pe.mg" --target windows -o "$WORK/pe.base.exe" >/dev/null 2>&1
"$MAGC" "$WORK/pe.mg" --target windows -o "$WORK/pe.cur.exe" >/dev/null 2>&1
if cmp -s "$WORK/pe.base.exe" "$WORK/pe.cur.exe"; then
  echo "PASS  PE64 sample is byte-identical to HEAD"
else
  echo "FAIL  PE64 sample differs from HEAD"
  fail=$((fail+1))
fi

printf 'fn main(){print(1);}\n' > "$WORK/obj.mg"
"$WORK/base/magc" --target x86_64 -c "$WORK/obj.mg" -o "$WORK/obj.base.o" >/dev/null 2>&1
"$MAGC" --target x86_64 -c "$WORK/obj.mg" -o "$WORK/obj.cur.o" >/dev/null 2>&1
if cmp -s "$WORK/obj.base.o" "$WORK/obj.cur.o"; then
  echo "PASS  x86_64 MAGO object is byte-identical to HEAD"
else
  echo "FAIL  x86_64 MAGO object differs from HEAD"
  fail=$((fail+1))
fi

echo
echo "x86 byte regression: pass=$pass fail=$fail"
if (( fail )); then exit 1; fi
echo "PASS: x86_64 ELF/MAGO/PE64 output unchanged from HEAD"
