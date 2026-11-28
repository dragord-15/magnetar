#!/usr/bin/env bash
# Semantic validation must fail clearly for undefined names and obvious type
# errors, warn for a missing entry, and still accept forward references.
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

cat > "$WORK/undef.mg" <<'EOF'
fn main() { print(x); }
EOF
cat > "$WORK/type.mg" <<'EOF'
fn main() { int x = "text"; print(x); }
EOF
cat > "$WORK/no_main.mg" <<'EOF'
fn foo() { print("foo\n"); }
EOF

"$MAGC" "$WORK/undef.mg" -o "$WORK/undef" >"$WORK/undef.log" 2>&1
rc=$?
err="$(cat "$WORK/undef.log")"
[[ $rc -ne 0 ]]
check $? "undefined name rejected"
grep -q "undefined variable 'x'" <<<"$(strip_ansi <<<"$err")"
check $? "undefined diagnostic is explicit"
grep -q "undef.mg:1:19" <<<"$(strip_ansi <<<"$err")"
check $? "undefined diagnostic has line and column"

"$MAGC" "$WORK/type.mg" -o "$WORK/type" >"$WORK/type.log" 2>&1
rc=$?
err="$(cat "$WORK/type.log")"
[[ $rc -ne 0 ]]
check $? "int assigned a string rejected"
grep -q "type mismatch" <<<"$(strip_ansi <<<"$err")"
check $? "type diagnostic is explicit"

"$MAGC" "$WORK/no_main.mg" -o "$WORK/no_main" >"$WORK/out" 2>"$WORK/err"
[[ $? -ne 0 ]]
check $? "missing main still fails at entry selection"
grep -q "Warning: entry function 'main' was not defined" "$WORK/err"
check $? "missing main produces an explicit warning"

echo "semantic: pass=$pass fail=$fail"
[[ $fail -eq 0 ]]
