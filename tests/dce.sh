#!/usr/bin/env bash
# Program-level DCE must remove unreachable functions without changing output.
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

cat > "$WORK/with.mg" <<'EOF'
fn used() -> int { return 41; }
fn unused() -> int { return 99; }
fn main() { print(used()); print("\n"); }
EOF
cat > "$WORK/without.mg" <<'EOF'
fn used() -> int { return 41; }
fn main() { print(used()); print("\n"); }
EOF

"$MAGC" "$WORK/with.mg" -o "$WORK/with" >"$WORK/log" 2>&1
check $? "compiles source with an unused function"
"$MAGC" "$WORK/without.mg" -o "$WORK/without" >"$WORK/log" 2>&1
check $? "compiles equivalent source without the function"

size_with="$(stat -c %s "$WORK/with")"
size_without="$(stat -c %s "$WORK/without")"
[[ "$size_with" == "$size_without" ]]
check $? "ELF size is identical after removing unused function ($size_with vs $size_without)"

output="$("$WORK/with")"
[[ "$output" == "41" ]]
check $? "reachable call still works after DCE"

echo "dce: pass=$pass fail=$fail"
[[ $fail -eq 0 ]]
