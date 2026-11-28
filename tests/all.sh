#!/usr/bin/env bash
# CI-style entry point: run every Magnetar verification suite.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail=0
run_suite() {
  local label="$1" script="$2"
  echo
  echo "═════════════════════════════════════════════"
  echo " $label"
  echo "═════════════════════════════════════════════"
  if bash "$ROOT/$script"; then
    echo "RESULT: $label PASS"
  else
    echo "RESULT: $label FAIL"
    fail=$((fail+1))
  fi
}

run_suite "Core regression suite (native target)" tests/run.sh
run_suite "Standalone ARM64 ELF smoke" tests/arm64_smoke.sh
run_suite "ARM64 object linking" tests/arm64_link.sh
run_suite "CLI formats and aliases" tests/cli_formats.sh
run_suite "Optional bounds checking" tests/bounds_check.sh
run_suite "x86_64 / ARM64 parity" tests/parity.sh
run_suite "x86_64 ELF/MAGO/PE64 byte regression" tests/x86_no_regression.sh

echo
if (( fail )); then
  echo "OVERALL: $fail suite(s) failed"
  exit 1
fi
echo "OVERALL: all suites passed ✅"
exit 0
