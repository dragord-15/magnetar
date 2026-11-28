#!/usr/bin/env bash
# End-to-end ARM64 object-linking regression:
#   magc -c --target arm64 -> mag --target arm64 -> run
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAGC="${MAGC:-$ROOT/magc}"
MAG="${MAG:-$ROOT/mag}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

printf 'fn main() { print("linked hello\\n"); }\n' > "$WORK/single.mg"
"$MAGC" -c --target arm64 "$WORK/single.mg" -o "$WORK/single.o" >/dev/null 2>&1
"$MAG" "$WORK/single.o" --target arm64 -o "$WORK/single" >/dev/null 2>&1

file_out="$("$WORK/single")"
[[ "$file_out" == "linked hello" ]] || {
    echo "FAIL: single-object link output was '$file_out'"
    exit 1
}

if command -v readelf >/dev/null 2>&1; then
    header="$(readelf -h "$WORK/single")"
    grep -q 'EXEC (Executable file)' <<<"$header" || { echo "FAIL: not ET_EXEC"; exit 1; }
    grep -q 'AArch64' <<<"$header" || { echo "FAIL: not EM_AARCH64"; exit 1; }
    grep -q 'Entry point address:.*0x400078' <<<"$header" || { echo "FAIL: unexpected ARM64 entry point"; exit 1; }
    phdrs="$(readelf -lW "$WORK/single")"
    [[ "$(grep -c 'LOAD' <<<"$phdrs")" == 1 ]] || { echo "FAIL: expected exactly one PT_LOAD"; exit 1; }
    grep -q '0x0000000000400000.*RWE' <<<"$phdrs" || { echo "FAIL: PT_LOAD is not RWX at 0x400000"; exit 1; }
fi

# Two objects, with a cross-object CALL26 relocation and distinct local
# string-label namespaces.
printf 'fn add(int a, int b) -> int { return a + b; }\n' > "$WORK/lib.mg"
printf 'extern fn add(int a, int b) -> int;\nfn main() { print(add(20, 22)); print("\\n"); }\n' > "$WORK/main.mg"
"$MAGC" -c --target arm64 "$WORK/lib.mg" --entry add -o "$WORK/lib.o" >/dev/null 2>&1
"$MAGC" -c --target arm64 "$WORK/main.mg" -o "$WORK/main.o" >/dev/null 2>&1
"$MAG" "$WORK/lib.o" "$WORK/main.o" --target arm64 -o "$WORK/two" >/dev/null 2>&1

two_out="$("$WORK/two")"
[[ "$two_out" == "42" ]] || {
    echo "FAIL: two-object link output was '$two_out'"
    exit 1
}

# Unresolved externs and static `any` arrays must survive the link step too:
# stubs are appended after alignment, and string pointers inside the data
# image use raw ABS64 relocations rather than code mov64 sequences.
for name in m05_arm64_extern_stubs m06_arm64_static_any_array; do
    cp "$ROOT/tests/cases/$name.mg" "$WORK/$name.mg"
    "$MAGC" -c --target arm64 "$WORK/$name.mg" -o "$WORK/$name.o" >/dev/null 2>&1
    "$MAG" "$WORK/$name.o" --target arm64 -o "$WORK/$name" >/dev/null 2>&1
    actual="$("$WORK/$name")"
    expected="$(cat "$ROOT/tests/expected/$name.txt")"
    [[ "$actual" == "$expected" ]] || {
        echo "FAIL: linked $name output was '$actual', expected '$expected'"
        exit 1
    }
done

# Cross-target mixing must fail loudly instead of silently mis-patching relocations.
printf 'fn main() {}\n' > "$WORK/x86.mg"
"$MAGC" --target x86_64 -c "$WORK/x86.mg" -o "$WORK/x86.o" >/dev/null 2>&1
if "$MAG" "$WORK/x86.o" --target arm64 -o "$WORK/bad" >/dev/null 2>&1; then
    echo "FAIL: x86_64 object was accepted by --target arm64"
    exit 1
fi
if "$MAG" "$WORK/single.o" --target x86_64 -o "$WORK/bad" >/dev/null 2>&1; then
    echo "FAIL: ARM64 object was accepted by --target x86_64"
    exit 1
fi

echo "PASS: ARM64 object linking works end-to-end (single and multi-object, mixed targets rejected)"
