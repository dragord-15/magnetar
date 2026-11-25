#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Magnetar regression suite.
#
#   tests/cases/<name>.mg        program that MUST compile and run
#   tests/expected/<name>.txt    its exact expected stdout        (required)
#   tests/expected/<name>.rc     expected exit status              (optional, 0)
#   tests/expected/<name>.err    substring expected on stderr      (optional)
#   tests/compile_fail/<name>.mg program that MUST be rejected at compile time
#   tests/compile_fail/<name>.err substring that must appear in the error
#
# Usage: tests/run.sh [--verbose] [name-filter]
# Exit code: 0 = all green, 1 = at least one failure.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAGC="${MAGC:-$ROOT/magc}"
VERBOSE=0
FILTER=""

for arg in "$@"; do
  case "$arg" in
    -v|--verbose) VERBOSE=1 ;;
    *) FILTER="$arg" ;;
  esac
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0; fail=0; failed_names=()

strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

run_case() {
  local src="$1" name; name="$(basename "$src" .mg)"
  [[ -n "$FILTER" && "$name" != *"$FILTER"* ]] && return 0

  local exp="$ROOT/tests/expected/$name.txt"
  local bin="$WORK/$name"

  if ! err="$("$MAGC" "$src" -o "$bin" 2>&1)"; then
    echo "FAIL  $name — compilation failed"
    echo "$err" | strip_ansi | grep -v '^\[Magnetar\]' | head -6 | sed 's/^/        /'
    fail=$((fail+1)); failed_names+=("$name"); return 0
  fi

  local out rc
  out="$(cd "$WORK" && timeout 10 "./$name" 2>"$WORK/$name.err")"; rc=$?
  if [[ $rc -ge 128 ]]; then
    echo "FAIL  $name — crashed with signal $((rc-128))"
    fail=$((fail+1)); failed_names+=("$name"); return 0
  fi

  local want_rc=0
  [[ -f "$ROOT/tests/expected/$name.rc" ]] && want_rc="$(cat "$ROOT/tests/expected/$name.rc")"
  if [[ "$rc" != "$want_rc" ]]; then
    echo "FAIL  $name — exit status $rc, expected $want_rc"
    fail=$((fail+1)); failed_names+=("$name"); return 0
  fi

  if [[ -f "$ROOT/tests/expected/$name.err" ]]; then
    local needle; needle="$(cat "$ROOT/tests/expected/$name.err")"
    if ! cat "$WORK/$name.err" | strip_ansi | grep -qF -- "$needle"; then
      echo "FAIL  $name — stderr does not contain: $needle"
      cat "$WORK/$name.err" | strip_ansi | head -4 | sed 's/^/        /'
      fail=$((fail+1)); failed_names+=("$name"); return 0
    fi
  fi

  if [[ ! -f "$exp" ]]; then
    echo "FAIL  $name — no expected file (tests/expected/$name.txt)"
    fail=$((fail+1)); failed_names+=("$name"); return 0
  fi

  if [[ "$out" != "$(cat "$exp")" ]]; then
    echo "FAIL  $name — output mismatch"
    echo "        expected: $(cat "$exp" | tr '\n' '|')"
    echo "        actual:   $(echo "$out" | tr '\n' '|')"
    fail=$((fail+1)); failed_names+=("$name"); return 0
  fi

  [[ $VERBOSE -eq 1 ]] && echo "ok    $name"
  pass=$((pass+1))
}

run_compile_fail() {
  local src="$1" name; name="$(basename "$src" .mg)"
  [[ -n "$FILTER" && "$name" != *"$FILTER"* ]] && return 0

  local errfile="$ROOT/tests/compile_fail/$name.err"
  local bin="$WORK/$name.fail"

  if err="$("$MAGC" "$src" -o "$bin" 2>&1)"; then
    echo "FAIL  $name — expected a compile error, but it compiled"
    fail=$((fail+1)); failed_names+=("$name"); return 0
  fi

  if [[ -f "$errfile" ]]; then
    local needle; needle="$(cat "$errfile")"
    if ! echo "$err" | strip_ansi | grep -qF -- "$needle"; then
      echo "FAIL  $name — error message does not contain: $needle"
      echo "$err" | strip_ansi | head -4 | sed 's/^/        /'
      fail=$((fail+1)); failed_names+=("$name"); return 0
    fi
  fi

  [[ $VERBOSE -eq 1 ]] && echo "ok    $name (rejected)"
  pass=$((pass+1))
}

run_use_resolution_cases() {
  local use_root="$WORK/use-resolution"
  mkdir -p "$use_root/project/lib/nested" "$use_root/global-lib" "$use_root/run"
  cat > "$use_root/project/main.mg" <<'EOF'
use "priority";
use "lib/outer.mg";
use "./lib/outer.mg";
fn main() {
    print(priority_value());
    print(" ");
    print(nested_value());
    print("\n");
}
EOF
  cat > "$use_root/project/lib/priority.mg" <<'EOF'
fn priority_value() -> int { return 1; }
EOF
  cat > "$use_root/global-lib/priority.mg" <<'EOF'
fn priority_value() -> int { return 9; }
EOF
  cat > "$use_root/project/lib/outer.mg" <<'EOF'
use "nested/value";
fn nested_value() -> int { return included_value(); }
EOF
  cat > "$use_root/project/lib/nested/value.fc" <<'EOF'
fn included_value() -> int { return 42; }
EOF

  if ! MAGNETAR_LIB="$use_root/global-lib" "$MAGC" "$use_root/project/main.mg" -o "$use_root/run/local-use" >/dev/null 2>&1; then
    echo "FAIL  use-relative-search — compilation failed"
    fail=$((fail+1)); failed_names+=("use-relative-search")
  else
    local use_out
    use_out="$(cd "$use_root/run" && ./local-use 2>/dev/null)"
    if [[ "$use_out" != "1 42" ]]; then
      echo "FAIL  use-relative-search — expected local module priority and nested .fc lookup"
      echo "        actual: $use_out"
      fail=$((fail+1)); failed_names+=("use-relative-search")
    else
      [[ $VERBOSE -eq 1 ]] && echo "ok    use-relative-search"
      pass=$((pass+1))
    fi
  fi

  cat > "$use_root/project/lib/aliasmod.mg" <<'EOF'
fn alias_value() -> int { return 8; }
EOF
  cat > "$use_root/project/alias_main.mg" <<'EOF'
use "lib/aliasmod.mg" as am;
fn main() {
    print(am.alias_value()); print("\n");
}
EOF
  if ! "$MAGC" "$use_root/project/alias_main.mg" -o "$use_root/run/alias-use" >/dev/null 2>&1; then
    echo "FAIL  use-alias — compilation failed"
    fail=$((fail+1)); failed_names+=("use-alias")
  else
    local alias_out
    alias_out="$(cd "$use_root/run" && ./alias-use 2>/dev/null)"
    if [[ "$alias_out" != "8" ]]; then
      echo "FAIL  use-alias — expected alias qualifier to resolve"
      echo "        actual: $alias_out"
      fail=$((fail+1)); failed_names+=("use-alias")
    else
      [[ $VERBOSE -eq 1 ]] && echo "ok    use-alias"
      pass=$((pass+1))
    fi
  fi

  mkdir -p "$use_root/project/folder"
  cat > "$use_root/project/missing.mg" <<'EOF'
use "folder";
fn main() { }
EOF
  if err="$("$MAGC" "$use_root/project/missing.mg" -o "$use_root/run/missing" 2>&1)"; then
    echo "FAIL  use-missing-module — unresolved module was accepted"
    fail=$((fail+1)); failed_names+=("use-missing-module")
  elif ! grep -qF "Could not resolve use module 'folder'" <<<"$err"; then
    echo "FAIL  use-missing-module — missing clear resolution error"
    echo "$err" | head -4 | sed 's/^/        /'
    fail=$((fail+1)); failed_names+=("use-missing-module")
  else
    [[ $VERBOSE -eq 1 ]] && echo "ok    use-missing-module"
    pass=$((pass+1))
  fi
}


run_entry_flag_cases() {
  local root="$WORK/entry-flag"
  mkdir -p "$root"
  cat > "$root/main.mg" <<'EOF'
fn start() -> int { print("flagged\n"); return 0; }
fn other() -> int { print("other\n"); return 0; }
EOF
  if ! "$MAGC" "$root/main.mg" -o "$root/app" --entry start >/dev/null 2>&1; then
    echo "FAIL  entry-flag — compilation failed"
    fail=$((fail+1)); failed_names+=("entry-flag")
    return 0
  fi
  local out
  out="$(cd "$root" && ./app 2>/dev/null)"
  if [[ "$out" != "flagged" ]]; then
    echo "FAIL  entry-flag — expected --entry start to select the start function"
    echo "        actual: $out"
    fail=$((fail+1)); failed_names+=("entry-flag")
  else
    [[ $VERBOSE -eq 1 ]] && echo "ok    entry-flag"
    pass=$((pass+1))
  fi
}

shopt -s nullglob
for f in "$ROOT"/tests/cases/*.mg;   do run_case "$f"; done
for f in "$ROOT"/tests/compile_fail/*.mg; do run_compile_fail "$f"; done
shopt -u nullglob
run_use_resolution_cases
run_entry_flag_cases

echo
echo "─────────────────────────────────────────────"
echo " passed: $pass   failed: $fail"
if [[ $fail -gt 0 ]]; then
  echo " failing: ${failed_names[*]}"
  exit 1
fi
echo " all green ✅"
exit 0
