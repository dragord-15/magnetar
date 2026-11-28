#!/usr/bin/env bash
# `use` is textual inclusion: duplicate top-level names must warn while the
# first definition keeps winning (backward compatibility).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAGC="${MAGC:-$ROOT/magc}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0
check() {
  if [[ $1 -eq 0 ]]; then echo "PASS  $2"; pass=$((pass+1));
  else echo "FAIL  $2"; fail=$((fail+1)); fi
}

printf 'fn helper() { print("from A\\n"); }\n' > "$WORK/a.mg"
printf 'fn helper() { print("from B\\n"); }\n' > "$WORK/b.mg"
printf 'use "a";\nuse "b";\nfn main() { helper(); }\n' > "$WORK/main.mg"

err="$("$MAGC" "$WORK/main.mg" -o "$WORK/main" 2>&1)"
check $? "program with redefinition still compiles"
grep -q "Warning: redefinition of function 'helper'" <<<"$err"
check $? "redefinition warning is emitted"
grep -q "first definition at line 1 wins" <<<"$err"
check $? "warning explains which definition wins"
[[ "$("$WORK/main")" == "from A" ]]
check $? "first definition still wins at runtime"

echo "redefinition: pass=$pass fail=$fail"
[[ $fail -eq 0 ]]
