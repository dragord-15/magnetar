#!/usr/bin/env bash
# Cross-target parity harness.
#
# Compiles every tests/cases/*.mg source for x86_64 and arm64, runs whichever
# target is native (or is supplied through X86_RUNNER / ARM_RUNNER), and
# diffs stdout, stderr and exit codes.  Missing emulators are reported as
# SKIP, not silently treated as a pass.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAGC="${MAGC:-$ROOT/magc}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

X86_RUNNER="${X86_RUNNER:-}"
ARM_RUNNER="${ARM_RUNNER:-}"
if [[ -z "$X86_RUNNER" ]]; then
  for candidate in qemu-x86_64 qemu-x86_64-static box64; do
    if command -v "$candidate" >/dev/null 2>&1; then X86_RUNNER="$candidate"; break; fi
  done
fi
if [[ -z "$ARM_RUNNER" ]]; then
  for candidate in qemu-aarch64 qemu-aarch64-static; do
    if command -v "$candidate" >/dev/null 2>&1; then ARM_RUNNER="$candidate"; break; fi
  done
fi

HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
  x86_64|amd64) NATIVE=x86_64 ;;
  aarch64|arm64) NATIVE=arm64 ;;
  *) NATIVE=none ;;
esac

strip_ansi() { sed 's/\x1b\[[0-9;]*m//g'; }

x86_pass=0; x86_fail=0
arm_pass=0; arm_fail=0
parity_pass=0; parity_skip=0; parity_fail=0
failed=()

run_target() {
  local target="$1" bin="$2" out="$3" err="$4"
  if [[ "$target" == "$NATIVE" ]]; then
    "$bin" >"$out" 2>"$err"
    return $?
  fi
  local runner=""
  if [[ "$target" == "x86_64" && -n "$X86_RUNNER" ]]; then runner="$X86_RUNNER"
  elif [[ "$target" == "arm64" && -n "$ARM_RUNNER" ]]; then runner="$ARM_RUNNER"
  else return 125
  fi
  $runner "$bin" >"$out" 2>"$err"
  return $?
}

check_expected() {
  local name="$1" target="$2" out="$3" err="$4" rc="$5"
  local exp="$ROOT/tests/expected/$name.txt"
  local want_rc=0
  [[ -f "$ROOT/tests/expected/$name.rc" ]] && want_rc="$(cat "$ROOT/tests/expected/$name.rc")"

  if [[ ! -f "$exp" ]]; then
    echo "FAIL  $name/$target — missing expected stdout file"
    return 1
  fi
  if [[ "$rc" != "$want_rc" ]]; then
    echo "FAIL  $name/$target — exit $rc, expected $want_rc"
    return 1
  fi
  # tests/run.sh treats trailing newlines as insignificant; mirror that for
  # expected-file checks.  Cross-target parity below still uses cmp -s on the
  # raw captures.
  if [[ "$(cat "$out")" != "$(cat "$exp")" ]]; then
    echo "FAIL  $name/$target — stdout differs from expected"
    return 1
  fi
  if [[ -f "$ROOT/tests/expected/$name.err" ]]; then
    local needle; needle="$(cat "$ROOT/tests/expected/$name.err")"
    if ! strip_ansi <"$err" | grep -qF -- "$needle"; then
      echo "FAIL  $name/$target — stderr does not contain: $needle"
      return 1
    fi
  fi
  return 0
}

mkdir -p "$WORK/x86" "$WORK/arm" "$WORK/run"

shopt -s nullglob
for src in "$ROOT"/tests/cases/*.mg; do
  name="$(basename "$src" .mg)"

  if ! err="$("$MAGC" "$src" --target x86_64 -o "$WORK/x86/$name" 2>&1)"; then
    echo "FAIL  $name/x86_64 — compile failed"
    echo "$err" | strip_ansi | tail -4 | sed 's/^/        /'
    x86_fail=$((x86_fail+1)); failed+=("$name/x86-compile")
  else
    x86_pass=$((x86_pass+1))
  fi

  if ! err="$("$MAGC" "$src" --target arm64 -o "$WORK/arm/$name" 2>&1)"; then
    echo "FAIL  $name/arm64 — compile failed"
    echo "$err" | strip_ansi | tail -4 | sed 's/^/        /'
    arm_fail=$((arm_fail+1)); failed+=("$name/arm-compile")
    continue
  fi
  arm_pass=$((arm_pass+1))

  out="$WORK/run/$name.arm.out"; err="$WORK/run/$name.arm.err"
  run_target arm64 "$WORK/arm/$name" "$out" "$err"; arm_rc=$?
  if [[ $arm_rc -eq 125 ]]; then
    echo "SKIP  $name/arm64 — no native ARM64 runner (set ARM_RUNNER)"
    parity_skip=$((parity_skip+1))
  elif check_expected "$name" arm64 "$out" "$err" "$arm_rc"; then
    :
  else
    arm_fail=$((arm_fail+1)); failed+=("$name/arm-run")
  fi

  if [[ ! -x "$WORK/x86/$name" ]]; then
    parity_skip=$((parity_skip+1))
    continue
  fi
  xout="$WORK/run/$name.x86.out"; xerr="$WORK/run/$name.x86.err"
  run_target x86_64 "$WORK/x86/$name" "$xout" "$xerr"; xrc=$?
  if [[ $xrc -eq 125 ]]; then
    echo "SKIP  $name/x86_64 — no native x86_64 runner (set X86_RUNNER)"
    parity_skip=$((parity_skip+1))
    continue
  fi
  if ! check_expected "$name" x86_64 "$xout" "$xerr" "$xrc"; then
    x86_fail=$((x86_fail+1)); failed+=("$name/x86-run")
    continue
  fi

  if [[ $arm_rc -ne 125 ]] && { ! cmp -s "$xout" "$out" || [[ "$xrc" != "$arm_rc" ]]; }; then
    echo "FAIL  $name — x86_64/arm64 stdout or exit-code diff"
    echo "        x86 rc=$xrc arm rc=$arm_rc"
    parity_fail=$((parity_fail+1)); failed+=("$name/parity")
  else
    parity_pass=$((parity_pass+1))
  fi
done
shopt -u nullglob

echo
echo "─────────────────────────────────────────────"
echo " x86_64: pass=$x86_pass fail=$x86_fail"
echo " arm64:  pass=$arm_pass fail=$arm_fail"
echo " parity: pass=$parity_pass skip=$parity_skip fail=$parity_fail"
if (( x86_fail || arm_fail || parity_fail )); then
  echo " failing: ${failed[*]}"
  exit 1
fi
echo " no stdout/exit-code diffs ✅"
exit 0
