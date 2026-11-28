#!/usr/bin/env bash
# `magc --bounds-check` must reject provably out-of-bounds literal indices
# while leaving normal compilation unchanged.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAGC="${MAGC:-$ROOT/magc}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

pass=0; fail=0
check() {
  if [[ $1 -eq 0 ]]; then echo "PASS  $2"; pass=$((pass+1));
  else echo "FAIL  $2"; fail=$((fail+1)); fi
}

cat > "$WORK/oob.mg" <<'EOF'
fn main() {
    fixed<int, 3> a = {1, 2, 3};
    print(a[5]);
}
EOF
cat > "$WORK/ok.mg" <<'EOF'
fn main() {
    fixed<int, 3> a = {1, 2, 3};
    print(a[2]); print("\n");
}
EOF

# Without the flag the old behavior stays intact.
"$MAGC" "$WORK/oob.mg" -o "$WORK/oob" >/dev/null 2>&1
check $? "out-of-bounds literal compiles without --bounds-check"

err="$("$MAGC" "$WORK/oob.mg" --bounds-check -o "$WORK/oob.checked" 2>&1)"
rc=$?
[[ $rc -ne 0 ]]
check $? "out-of-bounds literal rejected with --bounds-check"
grep -q "out of bounds" <<<"$(strip_ansi <<<"$err")"
check $? "diagnostic explains the bounds violation"
grep -q "oob.mg:3:13" <<<"$(strip_ansi <<<"$err")"
check $? "diagnostic includes line and column"

"$MAGC" "$WORK/ok.mg" --bounds-check -o "$WORK/ok" >/dev/null 2>&1
check $? "in-bounds literal still compiles with --bounds-check"
[[ "$("$WORK/ok")" == "3" ]]
check $? "in-bounds program still runs correctly"

echo "bounds-check: pass=$pass fail=$fail"
[[ $fail -eq 0 ]]
